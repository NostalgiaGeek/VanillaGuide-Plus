-- QuestTracker.lua
-- Quest log scanning and completion detection for TurtleGuide

local TurtleGuide = TurtleGuide
local L = TurtleGuide.Locale
local hadquest


TurtleGuide.TrackEvents = {
	"UI_INFO_MESSAGE", "CHAT_MSG_LOOT", "CHAT_MSG_SYSTEM",
	"QUEST_WATCH_UPDATE", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
	"ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "MINIMAP_ZONE_CHANGED",
	"ZONE_CHANGED_NEW_AREA", "PLAYER_LEVEL_UP", "ADDON_LOADED",
	"CRAFT_SHOW", "PLAYER_DEAD", "SKILL_LINES_CHANGED", "SPELLS_CHANGED"
}


function TurtleGuide:ADDON_LOADED(event, addon)
	if addon ~= "Blizzard_TrainerUI" then return end

	self:UnregisterEvent("ADDON_LOADED")

	local f = CreateFrame("Frame", nil, ClassTrainerFrame)
	f:SetScript("OnShow", function()
		if self:GetObjectiveInfo() == "TRAIN" then self:SetTurnedIn() end
	end)
end

function TurtleGuide:SKILL_LINES_CHANGED()
	self:UpdateStatusFrame()
end

function TurtleGuide:SPELLS_CHANGED()
	self:UpdateStatusFrame()
end

function TurtleGuide:PLAYER_LEVEL_UP(event, newlevel)
	local level = tonumber((self:GetObjectiveTag("LV")))
	self:Debug("PLAYER_LEVEL_UP", newlevel, level)
	if level and newlevel >= level then self:SetTurnedIn() end
end

function TurtleGuide:ZONE_CHANGED(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19,
								  a20)
	local zonetext, subzonetext, subzonetag, action, quest = GetZoneText(), GetSubZoneText(), self:GetObjectiveTag("SZ"),
		self:GetObjectiveInfo()
	if (action == "RUN" or action == "FLY" or action == "HEARTH" or action == "BOAT") and (subzonetext == quest or subzonetext == subzonetag or zonetext == quest or zonetext == subzonetag) then
		self:Debug(string.format("Detected zone change %q - %q", action, quest))
		self:SetTurnedIn()
	end
end

TurtleGuide.ZONE_CHANGED_INDOORS = TurtleGuide.ZONE_CHANGED
TurtleGuide.MINIMAP_ZONE_CHANGED = TurtleGuide.ZONE_CHANGED
TurtleGuide.ZONE_CHANGED_NEW_AREA = TurtleGuide.ZONE_CHANGED


function TurtleGuide:CHAT_MSG_SYSTEM(msg)
	local action, quest = self:GetObjectiveInfo()

	local _, _, loc = string.find(msg, L["(.*) is now your home."])
	if loc then
		self:Debug(string.format("Detected setting hearth to %q", loc))
		self.db.char.hearth = loc
		return action == "SETHEARTH" and loc == quest and self:SetTurnedIn()
	end

	if action == "ACCEPT" then
		local _, _, text = string.find(msg, L["Quest accepted: (.*)"])
		if text and string.gsub(quest, L.PART_GSUB, "") == text then
			self:Debug(string.format("Detected quest accept %q", quest))
			return self:UpdateStatusFrame()
		end
	end

	if action == "PET" then
		local _, _, text = string.find(msg, L["You have learned a new spell: (.*)."])
		local nextEntry = table.getn(self.db.char.petskills) + 1
		self.db.char.petskills[nextEntry] = text
		if text and quest == text then
			self:Debug(string.format("Detected pet skill train %q", quest))
			return self:SetTurnedIn()
		end
	end
end

function TurtleGuide:QUEST_WATCH_UPDATE(event)
	if self:GetObjectiveInfo() == "COMPLETE" then self:UpdateStatusFrame() end
end

function TurtleGuide:QUEST_LOG_UPDATE(event)
	local action = self:GetObjectiveInfo()
	local _, logi, complete = self:GetObjectiveStatus()

	self:Debug("QUEST_LOG_UPDATE", action, logi, complete)

	if (self.updatedelay and not logi) or action == "ACCEPT" or action == "COMPLETE" then self:UpdateStatusFrame() end

	if action == "KILL" or action == "NOTE" then
		local quest, questtext = self:GetObjectiveTag("Q"), self:GetObjectiveTag("QO")
		if not quest or not questtext then return end

		local qi = self:GetQuestLogIndexByName(quest)
		for i = 1, GetNumQuestLeaderBoards(qi) do
			if GetQuestLogLeaderBoard(i, qi) == questtext then self:SetTurnedIn() end
		end
	elseif action == "COMPLETE" then
		local skipNext = self:GetObjectiveTag("S")
		if self.db.char.skipfollowups and skipNext and QuestFrame:IsVisible() then
			CloseQuest()
			TurtleGuide:Print(L["Automatically skipping the follow-up"])
		end
	end
end

function TurtleGuide:UNIT_QUEST_LOG_CHANGED(event, unit)
	if unit ~= "player" then return end
	local action = self:GetObjectiveInfo()
	if action == "COMPLETE" then
		self:UpdateStatusFrame()
	end
end

function TurtleGuide:CHAT_MSG_LOOT(event, msg)
	local action, quest = self:GetObjectiveInfo()
	local lootitem, lootqty = self:GetObjectiveTag("L")
	local _, _, itemid, name = string.find(msg, L["^You .*Hitem:(%d+).*(%[.+%])"])
	self:Debug(event, action, quest, lootitem, lootqty, itemid, name)

	if action == "BUY" and name and name == quest
		or (action == "BUY" or action == "KILL" or action == "NOTE" or action == "COMPLETE") and lootitem and itemid == lootitem and (self.GetItemCount(lootitem) + 1) >= lootqty then
		return self:SetTurnedIn()
	end
end

function TurtleGuide:PLAYER_DEAD()
	if self:GetObjectiveInfo() == "DIE" then
		self:Debug("Player has died")
		self:SetTurnedIn()
	end
end

function TurtleGuide:UI_INFO_MESSAGE(event, msg)
	if msg == ERR_NEWTAXIPATH and self:GetObjectiveInfo() == "GETFLIGHTPOINT" then
		self:Debug("Discovered flight point")
		self:SetTurnedIn()
	end
end

-- Detect NPC interaction for GETFLIGHTPOINT objectives
local flightEventFrame = CreateFrame("Frame")
flightEventFrame:RegisterEvent("TAXIMAP_OPENED")
flightEventFrame:RegisterEvent("GOSSIP_SHOW")
flightEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
flightEventFrame:SetScript("OnEvent", function()
	if TurtleGuide:GetObjectiveInfo() ~= "GETFLIGHTPOINT" then return end

	if event == "TAXIMAP_OPENED" or event == "GOSSIP_SHOW" then
		TurtleGuide:Debug(event .. " - completing GETFLIGHTPOINT")
		TurtleGuide:SetTurnedIn()
	elseif event == "PLAYER_TARGET_CHANGED" then
		-- Check if targeting a friendly NPC (likely the flight master)
		if UnitExists("target") and not UnitIsPlayer("target") and not UnitCanAttack("player", "target") then
			TurtleGuide:Debug("Targeted friendly NPC - completing GETFLIGHTPOINT")
			TurtleGuide:SetTurnedIn()
		end
	end
end)


function TurtleGuide:CRAFT_SHOW()
	if not GetCraftName() == "Beast Training" then return end
	for i = 1, GetNumCrafts() do
		local name, rank = GetCraftInfo(i)
		self.db.char.petskills[name .. (rank == "" and "" or (" (" .. rank .. ")"))] = true
	end
	if self:GetObjectiveInfo() == "PET" then self:UpdateStatusFrame() end
end

-- Hook GetQuestReward to track quest turnins
local orig = GetQuestReward
GetQuestReward = function(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20)
	local quest = string.gsub(GetTitleText(), "%[[0-9%+%-]+]%s", "")

	TurtleGuide:Debug("GetQuestReward", quest)
	TurtleGuide:CompleteQuest(quest, true)

	-- Track completed quest for smart skip (by name)
	TurtleGuide.db.char.completedquests[quest] = true

	-- Also track by QID if we can find it in the current guide
	if TurtleGuide.quests and TurtleGuide.actions then
		for i, guideQuest in ipairs(TurtleGuide.quests) do
			local cleanGuideQuest = string.gsub(guideQuest, "@.*@", "")
			cleanGuideQuest = string.gsub(cleanGuideQuest, TurtleGuide.Locale.PART_GSUB, "")
			if cleanGuideQuest == quest and TurtleGuide.actions[i] == "TURNIN" then
				local qid = TurtleGuide:GetObjectiveTag("QID", i)
				if qid then
					TurtleGuide.db.char.completedquestsbyid[tonumber(qid)] = true
					TurtleGuide:Debug("Tracked completed QID: " .. qid)
				end
				break
			end
		end
	end

	return orig(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20)
end


-- Hook UseContainerItem to detect USE objective completion
local origUseContainerItem = UseContainerItem
UseContainerItem = function(bag, slot, ...)
	local action = TurtleGuide:GetObjectiveInfo()
	local useitem = TurtleGuide:GetObjectiveTag("U")

	if action == "USE" and useitem then
		local link = GetContainerItemLink(bag, slot)
		if link and string.find(link, "item:" .. useitem) then
			TurtleGuide:Debug("Detected USE item from bag: " .. useitem)
			-- Delay slightly to allow the item use to complete
			TurtleGuide.pendingUseComplete = true
		end
	end

	return origUseContainerItem(bag, slot, unpack(arg))
end

-- Check for pending USE completion after item use
local useCheckFrame = CreateFrame("Frame")
local useCheckElapsed = 0
local useCheckPending = false
useCheckFrame:SetScript("OnUpdate", function()
	if TurtleGuide.pendingUseComplete then
		-- Start tracking
		useCheckPending = true
		useCheckElapsed = 0
		TurtleGuide.pendingUseComplete = nil
	end

	if useCheckPending then
		useCheckElapsed = useCheckElapsed + arg1
		if useCheckElapsed > 0.3 then
			useCheckPending = false
			useCheckElapsed = 0
			local action = TurtleGuide:GetObjectiveInfo()
			if action == "USE" then
				TurtleGuide:Debug("Completing USE objective after item use")
				TurtleGuide:SetTurnedIn()
			end
		end
	end
end)


-- Scan quest log and return list of quests with their status
function TurtleGuide:ScanQuestLog()
	local quests = {}

	for i = 1, GetNumQuestLogEntries() do
		local title, level, questTag, isHeader, isCollapsed, isComplete = GetQuestLogTitle(i)
		if not isHeader and title then
			title = string.gsub(title, "%[[0-9%+%-]+]%s", "")
			quests[title] = {
				index = i,
				level = level,
				isComplete = isComplete == 1,
				objectives = {}
			}

			-- Get quest objectives
			local numObjectives = GetNumQuestLeaderBoards(i)
			for j = 1, numObjectives do
				local text, objType, finished = GetQuestLogLeaderBoard(j, i)
				table.insert(quests[title].objectives, {
					text = text,
					type = objType,
					finished = finished
				})
			end
		end
	end

	return quests
end

-- Check if a specific quest is in the quest log
function TurtleGuide:IsQuestInLog(questName)
	questName = string.gsub(questName, L.PART_GSUB, "")
	for i = 1, GetNumQuestLogEntries() do
		local title, _, _, isHeader = GetQuestLogTitle(i)
		if not isHeader and title then
			title = string.gsub(title, "%[[0-9%+%-]+]%s", "")
			if title == questName then
				return true, i
			end
		end
	end
	return false
end

-- Check if a specific quest is complete
function TurtleGuide:IsQuestComplete(questName)
	questName = string.gsub(questName, L.PART_GSUB, "")
	for i = 1, GetNumQuestLogEntries() do
		local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
		if not isHeader and title then
			title = string.gsub(title, "%[[0-9%+%-]+]%s", "")
			if title == questName then
				return isComplete == 1
			end
		end
	end
	return false
end

-- Distance-based arrival detection for travel objectives (fallback when TomTom not available)
local arrivalCheckFrame = CreateFrame("Frame")
local arrivalCheckElapsed = 0
local ARRIVAL_CHECK_INTERVAL = 0.5 -- Check every 0.5 seconds
local ARRIVAL_DISTANCE = 0.005     -- Map coordinate distance threshold (~15-18 yards)

-- Zone name to continent/zone index lookup (built from Navigation.lua pattern)
local zonei, zonec = {}, {}
for ci, c in pairs({ GetMapContinents() }) do
	for zi, z in pairs({ GetMapZones(ci) }) do
		zonei[z], zonec[z] = zi, ci
	end
end

-- Check if current objective completion conditions are already met
local function RecheckCurrentObjective()
	if not TurtleGuide.current or not TurtleGuide.actions then return end

	local action = TurtleGuide:GetObjectiveInfo()
	if not action then return end

	TurtleGuide:Debug("Rechecking completion for: " .. action)

	-- GETFLIGHTPOINT: Check if targeting friendly NPC
	if action == "GETFLIGHTPOINT" then
		if UnitExists("target") and not UnitIsPlayer("target") and not UnitCanAttack("player", "target") then
			TurtleGuide:Debug("Recheck: Already targeting friendly NPC - completing GETFLIGHTPOINT")
			TurtleGuide:SetTurnedIn()
			return
		end
	end

	-- Travel objectives: Will be caught by the distance check below
end

arrivalCheckFrame:SetScript("OnUpdate", function()
	arrivalCheckElapsed = arrivalCheckElapsed + arg1
	if arrivalCheckElapsed < ARRIVAL_CHECK_INTERVAL then return end
	arrivalCheckElapsed = 0

	-- Check if we need to re-evaluate after rewind
	if TurtleGuide.recheckCompletion then
		TurtleGuide.recheckCompletion = nil
		RecheckCurrentObjective()
	end

	-- Skip if TomTom is handling arrival detection (it has callbacks)
	-- Commented out to let our own robust distance-based fallback run in parallel
	-- if TomTom and TomTom.AddMFWaypoint then return end

	-- Only check if guide is loaded
	if not TurtleGuide.current or not TurtleGuide.actions then return end

	local action, quest = TurtleGuide:GetObjectiveInfo()
	if not action then return end

	-- Only check for travel/arrival objectives
	if action ~= "RUN" and action ~= "FLY" and action ~= "HEARTH" and action ~= "BOAT" and action ~= "GETFLIGHTPOINT" then return end

	-- Get target coordinates from note
	local note = TurtleGuide:GetObjectiveTag("N")
	if not note then return end

	local targetX, targetY
	for x, y in string.gfind(note, L.COORD_MATCH) do
		targetX, targetY = tonumber(x) / 100, tonumber(y) / 100
		break -- Use first coordinate found
	end

	if not targetX or not targetY then return end

	-- Get target zone
	local targetZone = TurtleGuide:GetObjectiveTag("Z") or TurtleGuide.zonename

	-- Get player position safely without interrupting the map view if open
	local playerC, playerZ, playerX, playerY
	local wasShown = WorldMapFrame:IsShown()

	if wasShown then
		-- If map is open, check if it's currently showing the player's zone
		local currentZoneName = GetRealZoneText()
		local playerZC, playerZI = zonec[currentZoneName], zonei[currentZoneName]
		local mapC, mapZ = GetCurrentMapContinent(), GetCurrentMapZone()

		if playerZC and playerZI and mapC == playerZC and mapZ == playerZI then
			playerC, playerZ = mapC, mapZ
			playerX, playerY = GetPlayerMapPosition("player")
		else
			-- Player is looking at a different map or zoomed out, skip check to avoid resetting their view
			return
		end
	else
		-- Map is hidden, safe to set to current zone and get position
		SetMapToCurrentZone()
		playerC, playerZ = GetCurrentMapContinent(), GetCurrentMapZone()
		playerX, playerY = GetPlayerMapPosition("player")
	end

	-- If target zone is specified, check we're in the right zone
	if targetZone then
		local targetZI, targetZC = zonei[targetZone], zonec[targetZone]
		if targetZC and targetZI and (playerC ~= targetZC or playerZ ~= targetZI) then
			return -- Not in target zone yet
		end
	end

	-- Skip if we couldn't get player position
	if playerX == 0 and playerY == 0 then return end

	-- Calculate distance (simple Euclidean in map coordinates)
	local dx, dy = playerX - targetX, playerY - targetY
	local distance = math.sqrt(dx * dx + dy * dy)

	if distance <= ARRIVAL_DISTANCE then
		TurtleGuide:Debug(string.format("Arrived at destination: %.3f from target (threshold %.3f)", distance,
			ARRIVAL_DISTANCE))
		TurtleGuide:SetTurnedIn()
	end
end)
