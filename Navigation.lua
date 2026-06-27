-- Navigation.lua
-- TomTom integration wrapper for TurtleGuide

local L = TurtleGuide.Locale

local function HasMetaMap()
	return IsAddOnLoaded("MetaMap") and MetaMap_NameToZoneID and MetaMap_GetCurrentMapInfo
end

local function HasMetaMapNotes()
	return HasMetaMap() and MetaMapNotes_AddNewNote
end

local function HasMetaMapBWP()
	return HasMetaMap() and BWP_ClearDest and BWP_DisplayFrame and BWPDistanceText and BWPDestText
end

local function EnsureMetaMapBWP()
	if not HasMetaMap() then return false end
	if not IsAddOnLoaded("MetaMapBWP") then
		LoadAddOn("MetaMapBWP")
	end
	if IsAddOnLoaded("MetaMapBWP") and MetaMap_LoadBWP then
		MetaMap_LoadBWP(0, 3)
	end
	return HasMetaMapBWP()
end

local zonei, zonec, zonenames = {}, {}, {}
for ci, c in pairs{GetMapContinents()} do
	zonenames[ci] = {GetMapZones(ci)}
	for zi, z in pairs(zonenames[ci]) do
		zonei[z], zonec[z] = zi, ci
	end
end

local cache = {}
local metamapnotes = {}

-- Helper to get valid zone data (ensures map is set to player location)
local function GetPlayerZoneData()
	-- Save current map state
	local wasShown = WorldMapFrame:IsShown()
	local oldContinent, oldZone
	if wasShown then
		oldContinent = GetCurrentMapContinent()
		oldZone = GetCurrentMapZone()
	end

	-- Briefly set map to player's zone to get valid data
	SetMapToCurrentZone()
	local c = GetCurrentMapContinent()
	local z = GetCurrentMapZone()

	-- Restore map state
	if wasShown and oldContinent and oldZone then
		SetMapZoom(oldContinent, oldZone)
	elseif not wasShown and WorldMapFrame:IsShown() then
		HideUIPanel(WorldMapFrame)
	end

	return c, z
end

-- Set a waypoint using TomTom
local function MapPoint(zone, x, y, desc, onArrival)
	desc = desc or "Waypoint"
	TurtleGuide:Debug(string.format("Mapping %q - %s (%.2f, %.2f)", desc, zone or "nil", x or 0, y or 0))
	local zi, zc = zone and zonei[zone], zone and zonec[zone]
	if not zi or zi == 0 then
		if zone then TurtleGuide:Print(string.format(L["Cannot find zone %q, using current zone."], zone))
		else TurtleGuide:Print(L["No zone provided, using current zone."]) end

		zc, zi = GetPlayerZoneData()
		zone = zonenames[zc] and zonenames[zc][zi]
	end

	-- Skip if still no valid zone
	if not zc or zc == 0 or not zi or zi == 0 then
		TurtleGuide:Debug("Could not determine zone for waypoint")
		return
	end

	-- Use TomTom for waypoints
	if TomTom and TomTom.AddMFWaypoint then
		local title = "[TG] " .. (desc or "Waypoint")
		TurtleGuide:Debug(string.format("TomTom waypoint: c=%d z=%d x=%.2f y=%.2f title=%s", zc, zi, x/100, y/100, title))

		-- Build waypoint options
		local opts = {title = title, crazy = true, silent = true}

		-- Add arrival callback if provided (for travel objectives)
		if onArrival then
			opts.callbacks = {
				distance = {
					[15] = function(event, uid, dist, lastdist)
						-- Only trigger on approach (lastdist > dist), not when leaving
						if lastdist and lastdist > 15 then
							TurtleGuide:Debug("TomTom arrival callback triggered")
							onArrival()
						end
					end
				}
			}
		end

		local uid = TomTom:AddMFWaypoint(zc, zi, x / 100, y / 100, opts)
		if uid then
			TurtleGuide.tomtomwaypoints = TurtleGuide.tomtomwaypoints or {}
			table.insert(TurtleGuide.tomtomwaypoints, uid)
			TurtleGuide.lastwaypoint = true
		end
	elseif Cartographer_Waypoints then
		local pt = NotePoint:new(zone, x / 100, y / 100, "[TG] " .. desc)
		Cartographer_Waypoints:AddWaypoint(pt)
		table.insert(cache, pt.WaypointID)
	elseif TurtleGuide.db.char.mapmetamap and HasMetaMap() then
		if TurtleGuide.db.char.mapbwp and EnsureMetaMapBWP() then
			local zid = MetaMap_NameToZoneID(zone) or MetaMap_GetCurrentMapInfo()
			BWP_ClearDest()
			BWP_AddDestination("[TG] " .. desc, zid, x / 100, y / 100, true, true)
			TurtleGuide.lastwaypoint = true
		elseif HasMetaMapNotes() then
			local zid = MetaMap_NameToZoneID(zone) or MetaMap_GetCurrentMapInfo()
			local note = {zoneid = zid, xPos = x / 100, yPos = y / 100, name = "[TG] " .. desc, color = 0}
			MetaMapNotes_AddNewNote(note)
			table.insert(metamapnotes, note)
			TurtleGuide.lastwaypoint = true
		end
	end
end

-- Set waypoint from coordinates
function TurtleGuide:SetWaypoint(x, y, zone, description)
	self:ClearWaypoint()
	MapPoint(zone, x, y, description or "TurtleGuide Waypoint")
end

-- Clear all TurtleGuide waypoints
function TurtleGuide:ClearWaypoint()
	if TomTom then
		if TurtleGuide.tomtomwaypoints then
			for _, uid in ipairs(TurtleGuide.tomtomwaypoints) do
				if TomTom.RemoveWaypoint then
					TomTom:RemoveWaypoint(uid)
				end
			end
			TurtleGuide.tomtomwaypoints = {}
		end
		self.lastwaypoint = nil
	elseif Cartographer_Waypoints then
		while cache[1] do
			local pt = table.remove(cache)
			Cartographer_Waypoints:CancelWaypoint(pt)
		end
	elseif HasMetaMapNotes() then
		for i = table.getn(metamapnotes), 1, -1 do
			local note = table.remove(metamapnotes, i)
			MetaMapNotes_DeleteNote(note.zoneid, note.xPos, note.yPos)
		end
		if HasMetaMapBWP() then
			BWP_ClearDest()
		end
	elseif HasMetaMapBWP() then
		BWP_ClearDest()
	end
end

-- Force waypoint update - directly creates waypoint for current objective
function TurtleGuide:ForceWaypointUpdate()
	if not self.current then return end

	local action, quest = self:GetObjectiveInfo(self.current)
	if not action then return end

	local note = self:GetObjectiveTag("N", self.current)
	local qid = self:GetObjectiveTag("QID", self.current)
	local zonename = self:GetObjectiveTag("Z", self.current) or self.zonename

	self:Debug(string.format("ForceWaypointUpdate: step=%d action=%s quest=%s note=%s zone=%s",
		self.current, action or "nil", quest or "nil", note or "nil", zonename or "nil"))

	-- Clear and recreate waypoint
	self:ParseAndMapCoords(qid, action, note, quest, zonename)

	-- Signal to StatusFrame that waypoint was updated
	self.waypointForced = true
end

-- Map NPC location using pfQuest database
function TurtleGuide:MapPfQuestNPC(qid, action)
	if not self.db.char.mapquestgivers then return end
	if not qid then return false end
	if not pfDB then return false end

	local unitId, objectId = "UNKNOWN", "UNKNOWN"
	local loc, qid = GetLocale(), tonumber(qid)

	local qLookup = pfDB["quests"]["data"]
	if not qLookup or not qLookup[qid] then return false end

	local title = pfDB.quests.loc[qid] and pfDB.quests.loc[qid]["T"] or "Unknown Quest"

	if action == "ACCEPT" then
		if qLookup[qid]["start"] then
			if qLookup[qid]["start"]["U"] then
				for _, uid in pairs(qLookup[qid]["start"]["U"]) do
					unitId = uid
				end
			elseif qLookup[qid]["start"]["O"] then
				for _, oid in pairs(qLookup[qid]["start"]["O"]) do
					objectId = oid
				end
			end
		end
	else
		if qLookup[qid]["end"] then
			if qLookup[qid]["end"]["U"] then
				for _, uid in pairs(qLookup[qid]["end"]["U"]) do
					unitId = uid
				end
			elseif qLookup[qid]["end"]["O"] then
				for _, oid in pairs(qLookup[qid]["end"]["O"]) do
					objectId = oid
				end
			end
		end
	end
	self:Debug(string.format("pfQuest lookup A:%s U:%s O:%s", action, unitId, objectId))

	if unitId ~= "UNKNOWN" then
		local unitLookup = pfDB["units"]["data"]
		if unitLookup[unitId] and unitLookup[unitId]["coords"] then
			for _, data in pairs(unitLookup[unitId]["coords"]) do
				local x, y, zone, _ = unpack(data)
				local zoneName = pfDB.zones.loc and pfDB.zones.loc[zone] or nil
				local unitName = pfDB.units.loc and pfDB.units.loc[unitId] or "NPC"
				MapPoint(zoneName, x, y, title .. " (" .. unitName .. ")")
				return true
			end
		end
	elseif objectId ~= "UNKNOWN" then
		local objectLookup = pfDB["objects"]["data"]
		if objectLookup[objectId] and objectLookup[objectId]["coords"] then
			for _, data in pairs(objectLookup[objectId]["coords"]) do
				local x, y, zone, _ = unpack(data)
				local zoneName = pfDB.zones.loc and pfDB.zones.loc[zone] or nil
				local objName = pfDB.objects.loc and pfDB.objects.loc[objectId] or "Object"
				MapPoint(zoneName, x, y, title .. " (" .. objName .. ")")
				return true
			end
		end
	end
	self:Debug(string.format("%s: No NPC or Object information found for %s!", action, title))
	return false
end

-- Parse coordinates from note text and create waypoints
function TurtleGuide:ParseAndMapCoords(qid, action, note, desc, zone)
	-- Clear existing waypoints first
	self:ClearWaypoint()

	self:Debug(string.format("ParseAndMapCoords: action=%s note=%s desc=%s zone=%s",
		action or "nil", note or "nil", desc or "nil", zone or "nil"))

	-- Check if this is an objective that should auto-complete on arrival
	local isTravelObjective = (action == "RUN" or action == "FLY" or action == "HEARTH" or action == "BOAT" or action == "GETFLIGHTPOINT")
	local onArrival = nil
	if isTravelObjective then
		onArrival = function()
			TurtleGuide:Debug("Travel objective arrival - marking complete")
			TurtleGuide:SetTurnedIn()
		end
	end

	if note and string.find(note, L.COORD_MATCH) then
		self:Debug("Found coordinates in note")
		for x, y in string.gfind(note, L.COORD_MATCH) do
			MapPoint(zone, tonumber(x), tonumber(y), desc, onArrival)
		end
	elseif (action == "ACCEPT" or action == "TURNIN") then
		self:Debug("Trying pfQuest lookup for ACCEPT/TURNIN")
		if pfQuest or pfDB then
			if not self:MapPfQuestNPC(qid, action) and not self.lastwaypoint and (TomTom or Cartographer_Waypoints or HasMetaMap()) then
				self:Print("No waypoint data found. Try enabling note coords or install pfQuest.")
			end
		elseif not self.lastwaypoint and (TomTom or Cartographer_Waypoints or HasMetaMap()) then
			self:Print("No waypoint data found. Try enabling note coords or install pfQuest.")
		end
	else
		self:Debug("No coords in note and action=" .. (action or "nil") .. " - no waypoint created")
	end
end

-- Auto-update waypoint when step changes
function TurtleGuide:UpdateWaypoint()
	if not TomTom and not Cartographer_Waypoints and not HasMetaMap() then return end

	local action, quest, fullquest = self:GetObjectiveInfo()
	if not action then return end

	local note = self:GetObjectiveTag("N")
	local qid = self:GetObjectiveTag("QID")
	local zonename = self:GetObjectiveTag("Z") or self.zonename

	self:ParseAndMapCoords(qid, action, note, quest, zonename)
end

-- Patch Astrolabe/TomTom spelling mismatches and Lua errors at runtime
function TurtleGuide:PatchAstrolabe()
	if self.astrolabePatched then return end
	self.astrolabePatched = true

	-- 1. Fix Astrolabe spelling mismatches
	if Astrolabe and Astrolabe.ContinentList and WorldMapSize then
		local misspellings = {
			["orgrimmar"] = "Ogrimmar",
			["darnassus"] = "Darnassis",
			["azshara"] = "Aszhara",
			["hillsbrad"] = "Hilsbrad"
		}
		for continent, zones in pairs(Astrolabe.ContinentList) do
			for index, zData in pairs(zones) do
				if zData.mapFile then
					local correctKey = misspellings[string.lower(zData.mapFile)]
					if correctKey and WorldMapSize[continent] and WorldMapSize[continent].zoneData then
						local coords = WorldMapSize[continent].zoneData[correctKey]
						if coords then
							-- Overwrite the zeroData at mapData[index] with the correct coordinates
							WorldMapSize[continent][index] = coords
							coords.mapName = zData.mapName
						end
					end
				end
			end
		end
		self:Debug("Astrolabe spelling mismatch patches applied successfully.")
	end

	-- 2. Fix TomTom texcoords indexing Lua error when NaN or invalid keys are passed
	if TomTom and TomTom.texcoords then
		local mt = getmetatable(TomTom.texcoords)
		if mt and mt.__index then
			local original_index = mt.__index
			mt.__index = function(t, k)
				-- Ensure k is a valid string containing a colon to avoid Lua errors
				if type(k) == "string" and string.find(k, ":") then
					local status, res = pcall(original_index, t, k)
					if status then
						return res
					end
				end
				-- Safe fallback: call original_index with "1:1" to prevent crashes
				local status, res = pcall(original_index, t, "1:1")
				if status then
					return res
				end
				-- Absolute fallback: return hardcoded table to avoid returning nil/crashing
				return {0, 0, 0, 0}
			end
			self:Debug("TomTom texcoords error safety wrapper applied successfully.")
		end
	end
end

