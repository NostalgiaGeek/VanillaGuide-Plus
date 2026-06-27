local actiontypes = {
	A = "ACCEPT",
	C = "COMPLETE",
	T = "TURNIN",
	K = "KILL",
	R = "RUN",
	H = "HEARTH",
	h = "SETHEARTH",
	G = "GRIND",
	F = "FLY",
	f = "GETFLIGHTPOINT",
	N = "NOTE",
	B = "BUY",
	b = "BOAT",
	U = "USE",
	P = "PET",
	D = "DIE",
	t = "TRAIN",
}


function TurtleGuide:GetObjectiveTag(tag, i)
	i = i or self.current
	local tags = self.tags[i]
	if not tags then return end

	if tag == "O" then
		return string.find(tags, "|O|")
	elseif tag == "T" then
		return string.find(tags, "|T|")
	elseif tag == "S" then
		return string.find(tags, "|S|")
	elseif tag == "QID" then
		return self.select(3, string.find(tags, "|QID|(%d+)|"))
	elseif tag == "L" then
		local _, _, lootitem, lootqty = string.find(tags, "|L|(%d+)%s?(%d*)|")
		lootqty = tonumber(lootqty) or 1

		return lootitem, lootqty
	end

	return self.select(3, string.find(tags, "|" .. tag .. "|([^|]*)|?"))
end

local function DumpQuestDebug(accepts, turnins, completes)
	for quest in pairs(accepts) do if not turnins[quest] then TurtleGuide:Debug(string.format(
			"Quest has no 'turnin' objective: %s", quest)) end end
	for quest in pairs(turnins) do if not accepts[quest] then TurtleGuide:Debug(string.format(
			"Quest has no 'accept' objective: %s", quest)) end end
	for quest in pairs(completes) do if not accepts[quest] and not turnins[quest] then TurtleGuide:Debug(string.format(
			"Quest has no 'accept' and 'turnin' objectives: %s", quest)) end end
end


local titlematches = { "For", "A", "The", "Or", "In", "Then", "From", "To" }
local function DebugQuestObjective(text, action, quest, accepts, turnins, completes)
	local haserrors

	if (action == "A" and accepts[quest] or action == "T" and turnins[quest] or action == "C" and completes[quest]) and not string.find(text, "|NODEBUG|") then
		TurtleGuide:Debug(string.format("%s %s -- Duplicate objective", action, quest))
		haserrors = true
	end

	if action == "A" then
		accepts[quest] = true
	elseif action == "T" then
		turnins[quest] = true
	elseif action == "C" then
		completes[quest] = true
	end

	if string.find(text, "|NODEBUG|") then return haserrors end

	if action == "A" or action == "C" or action == "T" then
		-- Catch bad Title Case
		for _, word in pairs(titlematches) do
			if string.find(quest, "[^:]%s" .. word .. "%s") or string.find(quest, "[^:]%s" .. word .. "$") or string.find(quest, "[^:]%s" .. word .. "@") then
				TurtleGuide:Debug(string.format("%s %s -- Contains bad title case", action, quest))
				haserrors = true
			end
		end
	end

	local _, _, comment = string.find(text, "(|[NLUC]V?|[^|]+)$") or string.find(text, "(|[NLUC]V?|[^|]+) |[NLUC]V?|")
	if comment then
		TurtleGuide:Debug("Unclosed comment: " .. comment)
		haserrors = true
	end

	return haserrors
end


local myclass, myrace = UnitClass("player"), UnitRace("player")
local function StepParse(guide)
	local accepts, turnins, completes = {}, {}, {}
	local uniqueid = 1
	local actions, quests, tags = {}, {}, {}
	local i, haserrors = 1, false
	local guidet = TurtleGuide.split("\r\n", guide)

	local function matchFilter(filter, myValue)
		if not filter then return true end
		local components = TurtleGuide.split("/", filter)
		local hasMatches = false
		local hasNegations = false

		for _, sp in ipairs(components) do
			if string.sub(sp, 1, 1) == "!" then
				hasNegations = true
				if string.sub(sp, 2) == myValue then return false end
			else
				if sp == myValue then hasMatches = true end
			end
		end

		if hasNegations and not hasMatches then return true end
		return hasMatches
	end

	local function matchDungeonFilter(dungeon)
		if not dungeon then return true end
		local components = TurtleGuide.split("/", dungeon)
		local hasMatches = false
		local hasNegations = false

		for _, sp in ipairs(components) do
			local isNegation = string.sub(sp, 1, 1) == "!"
			local code = isNegation and string.sub(sp, 2) or sp
			code = string.upper(code)

			local isSelected = TurtleGuide.db and TurtleGuide.db.char and TurtleGuide.db.char.Dungeons and
			TurtleGuide.db.char.Dungeons[code]

			if isNegation then
				hasNegations = true
				if isSelected then return false end
			else
				if isSelected then hasMatches = true end
			end
		end

		if hasNegations and not hasMatches then return true end
		return hasMatches
	end

	for _, text in pairs(guidet) do
		local _, _, class = string.find(text, "|C|([^|]+)|")
		local _, _, race = string.find(text, "|R|([^|]+)|")
		local _, _, dungeon = string.find(text, "|D|([^|]+)|")
		if text ~= "" and matchFilter(class, myclass) and matchFilter(race, myrace) and matchDungeonFilter(dungeon) then
			local _, _, action, quest, tag = string.find(text, "^(%a) ([^|]*)(.*)")
			if action and actiontypes[action] then
				quest = TurtleGuide.trim(quest)
				quest = quest .. "@" .. uniqueid .. "@"
				uniqueid = uniqueid + 1
				actions[i], quests[i], tags[i] = actiontypes[action], quest, tag
				i = i + 1
				haserrors = DebugQuestObjective(text, action, quest, accepts, turnins, completes) or haserrors
			end
		end
	end
	DumpQuestDebug(accepts, turnins, completes)
	if haserrors and TurtleGuide:IsDebugging() then TurtleGuide:Print("This guide contains errors") end

	return actions, quests, tags
end


function TurtleGuide:LoadGuide(name, complete)
	if not name then return end
	if complete then
		self.db.char.completion[self.db.char.currentguide] = 1
	elseif self.actions then
		self.db.char.completion[self.db.char.currentguide] = (self.current - 1) / table.getn(self.actions)
	end

	self.db.char.currentguide = self.guides[name] and name or self.guidelist[1]

	self:Debug(string.format("Loading guide: %s", name))
	self.guidechanged = true
	-- Extract zone name from guide name, stripping any path prefix (e.g., "Optimized/")
	local _, _, zonename = string.find(name, "([^/]+) %(.*%)$")
	self.zonename = zonename
	local guideContent = self.guides[self.db.char.currentguide]()
	if type(guideContent) == "table" and guideContent.steps then
		-- QuestShell+ format (Lua table with steps array)
		self.actions, self.quests, self.tags = self:ParseQuestShellPlus(guideContent)
	else
		-- Traditional TurtleGuide format (string)
		self.actions, self.quests, self.tags = StepParse(guideContent)
	end

	if not self.db.char.turnins[name] then self.db.char.turnins[name] = {} end
	self.turnedin = self.db.char.turnins[name]

	-- Smart skip: scan quest log and skip to furthest incomplete step
	self:SmartSkipToStep()
end

-- Get quest prerequisites from pfQuest database (if available)
-- Returns table of prerequisite QIDs, or nil if not found
function TurtleGuide:GetQuestPrerequisites(qid)
	if not qid then return nil end
	qid = tonumber(qid)
	if not qid then return nil end

	-- Check if pfQuest database is available
	if not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] then
		return nil
	end

	local questData = pfDB["quests"]["data"][qid]
	if questData and questData["pre"] then
		return questData["pre"]
	end
	return nil
end

-- Recursively mark all prerequisites of a quest as completed
-- Returns count of newly marked quests
function TurtleGuide:MarkPrerequisitesCompleted(qid, visited)
	if not qid then return 0 end
	visited = visited or {}

	-- Prevent infinite loops
	if visited[qid] then return 0 end
	visited[qid] = true

	local prereqs = self:GetQuestPrerequisites(qid)
	if not prereqs then return 0 end

	local count = 0
	for _, prereqQid in ipairs(prereqs) do
		-- Mark this prerequisite as completed
		if not self.db.char.completedquestsbyid[prereqQid] then
			self.db.char.completedquestsbyid[prereqQid] = true
			self:Debug("Inferred completed (pfQuest prereq): QID " .. prereqQid)
			count = count + 1
		end
		-- Recursively mark its prerequisites
		count = count + self:MarkPrerequisitesCompleted(prereqQid, visited)
	end
	return count
end

-- Check if a quest's prerequisites are met
-- Returns: met (bool), unmetQids (table of unmet prerequisite QIDs)
function TurtleGuide:ArePrerequisitesMet(qid)
	if not qid then return true, {} end
	qid = tonumber(qid)
	if not qid then return true, {} end

	local prereqs = self:GetQuestPrerequisites(qid)
	if not prereqs then return true, {} end

	local unmet = {}
	for _, prereqQid in ipairs(prereqs) do
		-- Check if prerequisite is completed (by QID or in quest log)
		local isComplete = self.db.char.completedquestsbyid[prereqQid]
		if not isComplete then
			-- Also check if it's in the quest log (accepted but not turned in yet)
			-- That means the player is working on it, which is fine
			local inLog = self:IsQuestInLogByQid(prereqQid)
			if not inLog then
				table.insert(unmet, prereqQid)
			end
		end
	end

	return table.getn(unmet) == 0, unmet
end

-- Check if a quest (by QID) is in the player's quest log
function TurtleGuide:IsQuestInLogByQid(qid)
	if not qid or not pfDB then return false end

	-- Get quest name from pfQuest database
	local questName = self:GetQuestNameByQid(qid)
	if not questName then return false end

	return self:IsQuestInLog(questName)
end

-- Get quest name from pfQuest database
function TurtleGuide:GetQuestNameByQid(qid)
	if not qid then return nil end
	qid = tonumber(qid)

	-- Check pfQuest localized quest names
	if pfDB and pfDB["quests"] and pfDB["quests"]["loc"] then
		local locData = pfDB["quests"]["loc"][qid]
		if locData then
			-- pfQuest stores quest data as table with "T" (title) field
			if type(locData) == "table" then
				return locData["T"]
			end
			return locData
		end
	end

	return nil
end

-- Find the guide step index for a given QID
-- Returns step index or nil if not found
function TurtleGuide:FindGuideStepByQid(qid)
	if not qid or not self.quests or not self.actions then return nil end
	qid = tostring(qid)

	for i, quest in ipairs(self.quests) do
		local stepQid = self:GetObjectiveTag("QID", i)
		if stepQid == qid then
			return i
		end
	end
	return nil
end

-- Get unmet prerequisites for current objective, with guide step info
-- Returns table: { {qid=123, name="Quest Name", guideStep=5}, ... }
function TurtleGuide:GetUnmetPrerequisites(stepIndex)
	stepIndex = stepIndex or self.current
	if not stepIndex then return {} end

	local qid = self:GetObjectiveTag("QID", stepIndex)
	if not qid then return {} end

	local met, unmetQids = self:ArePrerequisitesMet(qid)
	if met then return {} end

	local result = {}
	for _, prereqQid in ipairs(unmetQids) do
		local info = {
			qid = prereqQid,
			name = self:GetQuestNameByQid(prereqQid) or ("QID " .. prereqQid),
			guideStep = self:FindGuideStepByQid(prereqQid)
		}
		table.insert(result, info)
	end
	return result
end

-- Smart guide switching: scan quest log and skip completed content
function TurtleGuide:SmartSkipToStep()
	if not self.actions or not self.quests then return end

	local completedQuests = {}
	local inProgressQuests = {}

	-- Scan quest log
	for i = 1, GetNumQuestLogEntries() do
		local title, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
		if not isHeader and title then
			title = string.gsub(title, "%[[0-9%+%-]+]%s", "")
			if isComplete == 1 then
				completedQuests[title] = true
			else
				inProgressQuests[title] = true
			end
		end
	end

	-- Database Self-Healing:
	-- If a quest is in the player's quest log, it cannot be fully turned in / completed.
	-- Clear any stale/corrupted completed flags for this quest and all its candidates in the guide.
	for i, quest in ipairs(self.quests) do
		local cleanQuest = string.gsub(quest, "@.*@", "")
		cleanQuest = string.gsub(cleanQuest, TurtleGuide.Locale.PART_GSUB, "")
		if completedQuests[cleanQuest] or inProgressQuests[cleanQuest] then
			local qid = self:GetObjectiveTag("QID", i)
			if qid then
				local qidNum = tonumber(qid)
				-- Do not clear QID if it is confirmed completed in pfQuest history
				if not (pfQuest_history and (pfQuest_history[qidNum] or pfQuest_history[tostring(qidNum)])) then
					self.db.char.completedquestsbyid[qidNum] = nil
				end
			end
			self.db.char.completedquests[cleanQuest] = nil
		end
	end

	-- QUEST CHAIN INFERENCE via pfQuest database:
	-- For each quest in the guide that's in the player's log, look up its
	-- prerequisites in pfQuest and mark them as completed.
	if pfDB and pfDB["quests"] and pfDB["quests"]["data"] then
		for i, quest in ipairs(self.quests) do
			local action = self.actions[i]
			local qid = self:GetObjectiveTag("QID", i)
			if qid and (action == "ACCEPT" or action == "COMPLETE" or action == "TURNIN") then
				local cleanQuest = string.gsub(quest, "@.*@", "")
				cleanQuest = string.gsub(cleanQuest, TurtleGuide.Locale.PART_GSUB, "")
				-- If quest is in log, mark its prerequisites as completed
				if inProgressQuests[cleanQuest] or completedQuests[cleanQuest] then
					local qidNum = tonumber(qid)
					local canInfer = true
					local prereqs = self:GetQuestPrerequisites(qidNum)
					if prereqs then
						for _, preQid in ipairs(prereqs) do
							if not self.db.char.completedquestsbyid[preQid] then
								-- Check if the prerequisite has the same name
								local preQuestData = pfDB["quests"]["data"][preQid]
								if preQuestData then
									local preQuestName = pfDB.quests.loc and pfDB.quests.loc[preQid] and
									pfDB.quests.loc[preQid]["T"] or nil
									if preQuestName then
										local cleanPreQuest = string.gsub(preQuestName, "%[[0-9%+%-]+]%s", "")
										cleanPreQuest = string.gsub(cleanPreQuest, TurtleGuide.Locale.PART_GSUB, "")
										if cleanPreQuest == cleanQuest then
											canInfer = false
											break
										end
									end
								end
							end
						end
					end

					if canInfer then
						self:MarkPrerequisitesCompleted(qidNum)
					end
				end
			end
		end
	end

	-- Pre-mark completed quests by QID (from pfQuest inference)
	for i, quest in ipairs(self.quests) do
		local action = self.actions[i]
		local qid = self:GetObjectiveTag("QID", i)
		if qid and self.db.char.completedquestsbyid[tonumber(qid)] then
			if action == "TURNIN" or action == "ACCEPT" or action == "COMPLETE" or action == "RUN" then
				self.turnedin[quest] = true
			end
		end
	end

	-- Pre-mark locally-tracked completed quests (by name)
	for i, quest in ipairs(self.quests) do
		local action = self.actions[i]
		local qid = self:GetObjectiveTag("QID", i)
		if not qid then
			local cleanQuest = string.gsub(quest, "@.*@", "")
			cleanQuest = string.gsub(cleanQuest, TurtleGuide.Locale.PART_GSUB, "")
			if self.db.char.completedquests[cleanQuest] then
				if action == "TURNIN" or action == "ACCEPT" or action == "COMPLETE" or action == "RUN" then
					self.turnedin[quest] = true
				end
			end
		end
	end

	-- Find the furthest step that has incomplete work
	local furthestStep = 1
	for i, quest in ipairs(self.quests) do
		local action = self.actions[i]
		local cleanQuest = string.gsub(quest, "@.*@", "")
		cleanQuest = string.gsub(cleanQuest, TurtleGuide.Locale.PART_GSUB, "")
		local qid = self:GetObjectiveTag("QID", i)
		local isCompleted = (qid and self.db.char.completedquestsbyid[tonumber(qid)]) or
		(not qid and self.db.char.completedquests[cleanQuest])

		if action == "ACCEPT" then
			-- If quest is in log or completed, mark as done
			if inProgressQuests[cleanQuest] or completedQuests[cleanQuest] or isCompleted then
				self.turnedin[quest] = true
			end
		elseif action == "TURNIN" then
			-- If quest is complete and in log, we need to turn it in
			if completedQuests[cleanQuest] and not self.turnedin[quest] then
				furthestStep = i
				break
			elseif isCompleted then
				self.turnedin[quest] = true
			end
		elseif action == "COMPLETE" then
			-- If quest is in progress but not complete, this is our step
			if inProgressQuests[cleanQuest] and not completedQuests[cleanQuest] and not isCompleted then
				furthestStep = i
				break
			elseif completedQuests[cleanQuest] or isCompleted then
				self.turnedin[quest] = true
			end
		elseif action == "RUN" then
			-- Run/Travel steps with QID: auto-complete if linked quest is done
			if qid and self.db.char.completedquestsbyid[tonumber(qid)] then
				self.turnedin[quest] = true
			end
		elseif action == "TRAIN" then
			if self:IsTrainingCompleted(cleanQuest) then
				self.turnedin[quest] = true
			end
		end

		-- Track last incomplete step
		if not self.turnedin[quest] then
			furthestStep = i
		end
	end

	if furthestStep > 1 then
		self:Debug(string.format(TurtleGuide.Locale["Skipping to step %d (completed content detected)"], furthestStep))
	end

	-- Set initial current position
	self.current = furthestStep
end

function TurtleGuide:DebugGuideSequence(dumpquests)
	local accepts, turnins, completes = {}, {}, {}
	local function DebugParse(guide)
		local uniqueid, haserrors = 1
		local guidet = TurtleGuide.split("\n", guide)
		for _, text in pairs(guidet) do
			if text ~= "" then
				local _, _, action, quest, tag = string.find(text, "^(%a) ([^|]*)(.*)")
				if action and not actiontypes[action] then TurtleGuide:Debug("Unknown action: " .. text) end
				if quest then
					quest = TurtleGuide.trim(quest)
					quest = quest .. "@" .. uniqueid .. "@"
					uniqueid = uniqueid + 1
					haserrors = DebugQuestObjective(text, action, quest, accepts, turnins, completes) or haserrors
				end
			end
		end

		return haserrors
	end

	self:Debug("------ Begin Full Debug ------")

	local name, lastzone = self.db.char.currentguide
	repeat
		if not self.guides[name] then
			self:Debug(string.format("Cannot find guide %q", name))
			name, lastzone = nil, name
		elseif DebugParse(self.guides[name]()) then
			self:Debug(string.format("Errors in guide: %s", name))
			self:Debug("---------------------------")
		end
		name, lastzone = self.nextzones[name], name
	until not name

	if dumpquests then
		self:Debug("------ Quest Continuity Debug ------")
		DumpQuestDebug(accepts, turnins, completes)
	end
	self:Debug("Last zone loaded:", lastzone)
	self:Debug("------ End Full Debug ------")
end
