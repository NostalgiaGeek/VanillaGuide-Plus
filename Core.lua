local L = TURTLEGUIDE_LOCALE
TURTLEGUIDE_LOCALE = nil

TurtleGuide = AceLibrary("AceAddon-2.0"):new("AceConsole-2.0", "AceDB-2.0", "AceDebug-2.0", "AceEvent-2.0", "AceHook-2.1",
    "FuBarPlugin-2.0")
local D = AceLibrary("Dewdrop-2.0")
local DF = AceLibrary("Deformat-2.0")
local T = AceLibrary("Tablet-2.0")
local gratuity = AceLibrary("Gratuity-2.0")

TurtleGuide.guides = {}
TurtleGuide.guidelist = {}
TurtleGuide.nextzones = {}
TurtleGuide.Locale = L
TurtleGuide.myfaction = UnitFactionGroup("player")

-- Race-based route definitions
TurtleGuide.routes = {}

-- Route pack registry (named collections of per-race routes)
TurtleGuide.routepacks = {}

-- Turtle WoW custom race support
-- Maps race strings from UnitRace() to route names and faction info
TurtleGuide.turtleRaces = {
    -- Standard races
    ["Human"] = { route = "Human", faction = "Alliance" },
    ["Dwarf"] = { route = "Dwarf", faction = "Alliance" },
    ["Night Elf"] = { route = "NightElf", faction = "Alliance" },
    ["NightElf"] = { route = "NightElf", faction = "Alliance" },
    ["Gnome"] = { route = "Gnome", faction = "Alliance" },
    ["Orc"] = { route = "Orc", faction = "Horde" },
    ["Troll"] = { route = "Troll", faction = "Horde" },
    ["Tauren"] = { route = "Tauren", faction = "Horde" },
    ["Undead"] = { route = "Undead", faction = "Horde" },
    ["Scourge"] = { route = "Undead", faction = "Horde" }, -- Internal name for Undead
    -- Turtle WoW custom races
    ["High Elf"] = { route = "HighElf", faction = "Alliance" },
    ["HighElf"] = { route = "HighElf", faction = "Alliance" },
    ["BloodElf"] = { route = "HighElf", faction = "Alliance" }, -- Turtle WoW uses BloodElf internally for High Elf
    ["Goblin"] = { route = "Goblin", faction = "Horde" },       -- Horde race in Turtle WoW
}

-- Get the normalized route name for a race
function TurtleGuide:GetRouteForRace(race)
    local raceInfo = self.turtleRaces[race]
    if raceInfo then
        return raceInfo.route
    end
    -- Fallback: use the race name as-is
    return race
end

-- Get all races available for the player's faction
function TurtleGuide:GetRacesForFaction(faction)
    local races = {}
    for raceName, info in pairs(self.turtleRaces) do
        -- Include if faction matches or race is neutral (Both)
        if info.faction == faction or info.faction == "Both" then
            -- Avoid duplicates (e.g., "Night Elf" and "NightElf")
            local routeName = info.route
            local found = false
            for _, r in ipairs(races) do
                if r.route == routeName then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(races, { name = raceName, route = routeName })
            end
        end
    end
    return races
end

TurtleGuide.icons = setmetatable({
    ACCEPT = "Interface\\GossipFrame\\AvailableQuestIcon",
    COMPLETE = "Interface\\Icons\\Ability_DualWield",
    TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon",
    KILL = "Interface\\Icons\\Ability_Creature_Cursed_02",
    RUN = "Interface\\Icons\\Ability_Tracking",
    MAP = "Interface\\Icons\\Ability_Spy",
    FLY = "Interface\\Icons\\Ability_Rogue_Sprint",
    SETHEARTH = "Interface\\AddOns\\TurtleGuide\\media\\resting.tga",
    HEARTH = "Interface\\Icons\\INV_Misc_Rune_01",
    NOTE = "Interface\\Icons\\INV_Misc_Note_01",
    GRIND = "Interface\\Icons\\INV_Stone_GrindingStone_05",
    USE = "Interface\\Icons\\INV_Misc_Bag_08",
    BUY = "Interface\\Icons\\INV_Misc_Coin_01",
    BOAT = "Interface\\Icons\\Ability_Druid_AquaticForm",
    GETFLIGHTPOINT = "Interface\\Icons\\Ability_Hunter_EagleEye",
    PET = "Interface\\Icons\\Ability_Hunter_BeastCall02",
    DIE = "Interface\\AddOns\\TurtleGuide\\media\\dead.tga",
    TRAIN = "Interface\\GossipFrame\\TrainerGossipIcon",
}, { __index = function() return "Interface\\Icons\\INV_Misc_QuestionMark" end })

local defaults = {
    debug = false,
    hearth = UNKNOWN,
    turnins = {},
    cachedturnins = {},
    trackquests = true,
    completion = {},
    currentguide = "No Guide",
    currentroute = nil,
    routeselected = false,
    mapquestgivers = true,
    mapnotecoords = true,
    mapmetamap = true,
    mapbwp = true,
    showstatusframe = true,
    showuseitem = true,
    showuseitemcomplete = true,
    skipfollowups = true,
    petskills = {},
    completedquests = {},
    completedquestsbyid = {}, -- {[questId] = true} from server
    lastserverquery = 0,      -- timestamp for throttling
    -- Branching state
    isbranching = false,
    branchsavedguide = nil,
    branchsavedstep = nil,
    autobranch = false,           -- auto-branch to Turtle WoW zones
    routepack = nil,              -- Active route pack name (e.g., "VanillaGuide", "RestedXP")
    -- Starting zone selection (branch-and-rejoin)
    startingzoneselected = false, -- has player picked a starting zone?
    selectedstartingzone = nil,   -- which starting zone was selected (e.g., "Human", "Dwarf")
    startingzonecomplete = false, -- has player finished their starting zone?
    rejoinlevel = 12,             -- level at which all paths rejoin (default 12)
    filterTurtle = true,
    filterOptimized = true,
    filterRXP = true,
    filterZone = true,
    Dungeons = {
        ["RFC"] = true,
        ["WC"] = true,
        ["DM"] = true,
        ["SFK"] = true,
        ["BFD"] = true,
        ["STOCKADES"] = true,
        ["GNOMER"] = true,
        ["RFK"] = true,
        ["SM"] = true,
        ["RFD"] = true,
        ["ULDA"] = true,
        ["ZF"] = true,
        ["MARA"] = true,
        ["ST"] = true,
        ["BRD"] = true,
    },
}

local options = {
    type = "group",
    handler = TurtleGuide,
    args = {
        DiagNav = {
            name = "Navigation Diag",
            desc = "Check navigation addon status",
            type = "execute",
            func = function()
                TurtleGuide:Print("--- Navigation Status ---")
                if TomTom then
                    TurtleGuide:Print("TomTom: YES")
                    TurtleGuide:Print("  AddMFWaypoint: " .. (TomTom.AddMFWaypoint and "YES" or "NO"))
                    TurtleGuide:Print("  RemoveWaypoint: " .. (TomTom.RemoveWaypoint and "YES" or "NO"))
                else
                    TurtleGuide:Print("TomTom: NO - Install TomTom-TWOW for arrow navigation")
                end
                if Cartographer_Waypoints then
                    TurtleGuide:Print("Cartographer_Waypoints: YES")
                end
                TurtleGuide:Print("MetaMap: " .. (IsAddOnLoaded("MetaMap") and "YES" or "NO"))
            end,
        },
        TestWaypoint = {
            name = "Test Waypoint",
            desc = "Create a test TomTom waypoint",
            type = "execute",
            func = function()
                if not TomTom then
                    TurtleGuide:Print("TomTom not found")
                    return
                end

                -- Use SetMapToCurrentZone to get valid data (same as the fix)
                SetMapToCurrentZone()
                local c = GetCurrentMapContinent()
                local z = GetCurrentMapZone()
                TurtleGuide:Print(string.format("Zone data: c=%s z=%s", tostring(c), tostring(z)))

                if not c or c == 0 or not z or z == 0 then
                    TurtleGuide:Print("Could not get zone data")
                    return
                end

                -- Create waypoint at 50, 50
                local uid = TomTom:AddMFWaypoint(c, z, 0.5, 0.5, { title = "TG Test", crazy = true })
                TurtleGuide:Print("Waypoint created: " .. tostring(uid))
            end,
        },
        TrackQuests = {
            name = "Auto Track",
            desc = L["Automatically track quests"],
            type = "toggle",
            get = function() return TurtleGuide.db.char.trackquests end,
            set = function(newValue)
                TurtleGuide.db.char.trackquests = newValue
                if TurtleGuide.optionsframe then
                    TurtleGuide.optionsframe.qtrack:SetChecked(TurtleGuide.db.char.trackquests)
                end
            end,
            order = 1,
        },
        SkipFollowUps = {
            name = "Auto Skip Followups",
            desc = L["Automatically skip suggested follow-ups"],
            type = "toggle",
            get = function() return TurtleGuide.db.char.skipfollowups end,
            set = function(newValue)
                TurtleGuide.db.char.skipfollowups = newValue
                if TurtleGuide.optionsframe then
                    TurtleGuide.optionsframe.qskipfollowups:SetChecked(TurtleGuide.db.char.skipfollowups)
                end
            end,
            order = 2,
        },
        StatusFrame = {
            name = "Toggle Status",
            desc = "Show/Hide Status Frame",
            type = "toggle",
            get = function() return TurtleGuide.statusframe:IsVisible() end,
            set = "OnClick",
            order = 3,
        },
        SelectRoute = {
            name = "Select Route",
            desc = "Choose a different leveling route",
            type = "execute",
            func = function() TurtleGuide:ShowRouteSelector() end,
            order = 4,
        },
        ShowErrorLog = {
            name = "Error Log",
            desc = "Show captured Lua errors",
            type = "execute",
            func = function() TurtleGuide:ShowErrorLog() end,
            order = 5,
        },
        NextStep = {
            name = "Next",
            desc = "Skip to next objective",
            type = "execute",
            func = function() TurtleGuide:SkipToNextObjective() end,
            order = 10,
        },
        PrevStep = {
            name = "Previous",
            desc = "Go back to previous objective",
            type = "execute",
            func = function() TurtleGuide:GoToPreviousObjective() end,
            order = 11,
        },
        GoToStep = {
            name = "Go To",
            desc = "Jump to step number",
            type = "text",
            usage = "<number>",
            get = false,
            set = function(v) TurtleGuide:GoToObjective(v) end,
            order = 12,
        },
        Refresh = {
            name = "Refresh",
            desc = "Rescan quest log and update guide progress",
            type = "execute",
            func = function() TurtleGuide:QueryServerCompletedQuests() end,
            order = 13,
        },
        Branch = {
            name = "Branch",
            desc = "Branch to a different zone guide (saves current progress)",
            type = "execute",
            func = function() TurtleGuide:ShowGuideList(true) end,
            order = 14,
        },
        ReturnMain = {
            name = "Return to Main",
            desc = "Return to main route from branch",
            type = "execute",
            func = function() TurtleGuide:ReturnFromBranch() end,
            order = 15,
        },
        AutoBranch = {
            name = "Auto Branch",
            desc = "Automatically branch to Turtle WoW zones when available",
            type = "toggle",
            get = function() return TurtleGuide.db.char.autobranch end,
            set = function(v) TurtleGuide.db.char.autobranch = v end,
            order = 16,
        },
        DebugRoute = {
            name = "Debug Route",
            desc = "Show debug info about route and guide selection",
            type = "execute",
            func = function()
                local _, race = UnitRace("player")
                local routeName = TurtleGuide:GetRouteForRace(race)
                local route = TurtleGuide.routes[routeName]
                local level = UnitLevel("player")

                TurtleGuide:Print("--- Route Debug ---")
                TurtleGuide:Print("Race from UnitRace: " .. tostring(race))
                TurtleGuide:Print("Route name: " .. tostring(routeName))
                TurtleGuide:Print("Route exists: " .. tostring(route ~= nil))
                TurtleGuide:Print("Player level: " .. tostring(level))
                TurtleGuide:Print("Current guide: " .. tostring(TurtleGuide.db.char.currentguide))

                -- Check if specific guides exist
                TurtleGuide:Print("--- Guide Existence ---")
                TurtleGuide:Print("'Thalassian Highlands (1-10)': " ..
                    tostring(TurtleGuide.guides["Thalassian Highlands (1-10)"] ~= nil))
                TurtleGuide:Print("'Teldrassil (1-12)': " .. tostring(TurtleGuide.guides["Teldrassil (1-12)"] ~= nil))

                -- Show first few guides in guidelist
                TurtleGuide:Print("--- First 5 guides in guidelist ---")
                for i = 1, math.min(5, table.getn(TurtleGuide.guidelist)) do
                    TurtleGuide:Print(i .. ": " .. tostring(TurtleGuide.guidelist[i]))
                end

                -- Show what GetNextRouteGuideForLevel would return
                if route then
                    local nextGuide = TurtleGuide:GetNextRouteGuideForLevel(route, level)
                    TurtleGuide:Print("GetNextRouteGuideForLevel returns: " .. tostring(nextGuide))
                end
            end,
            order = 17,
        },
        DebugTrain = {
            name = "Debug Train",
            desc = "Debug training detection",
            type = "execute",
            func = function()
                TurtleGuide:Print("--- Skill Lines ---")
                local numSkills = GetNumSkillLines()
                TurtleGuide:Print("GetNumSkillLines: " .. tostring(numSkills))
                for i = 1, numSkills do
                    local name, isHeader, isExpanded, rank, maxRank = GetSkillLineInfo(i)
                    TurtleGuide:Print(string.format("%d: %s (Header=%s, Rank=%s)", i, tostring(name), tostring(isHeader),
                        tostring(rank)))
                end

                TurtleGuide:Print("--- Spellbook ---")
                local i = 1
                while true do
                    local name, rank = GetSpellName(i, "spell")
                    if not name then break end
                    if string.find(string.lower(name), "blacksmith") or string.find(string.lower(name), "mining") then
                        TurtleGuide:Print(string.format("Spell %d: %s (%s)", i, tostring(name), tostring(rank)))
                    end
                    i = i + 1
                end

                TurtleGuide:Print("--- Training Check ---")
                TurtleGuide:Print("IsProfessionLearned('Blacksmithing'): " ..
                tostring(TurtleGuide:IsProfessionLearned("Blacksmithing")))
                TurtleGuide:Print("IsSpellLearned('Blacksmithing'): " ..
                tostring(TurtleGuide:IsSpellLearned("Blacksmithing")))
                TurtleGuide:Print("IsTrainingCompleted('Train [Blacksmithing]'): " ..
                tostring(TurtleGuide:IsTrainingCompleted("Train [Blacksmithing]")))
            end,
            order = 17,
        },
        ListGuides = {
            name = "List Guides",
            desc = "List all loaded guides",
            type = "execute",
            func = function()
                TurtleGuide:Print("--- All Loaded Guides ---")
                for i, name in ipairs(TurtleGuide.guidelist) do
                    TurtleGuide:Print(i .. ": " .. name)
                end
                TurtleGuide:Print("Total: " .. table.getn(TurtleGuide.guidelist) .. " guides")
            end,
            order = 18,
        },
        StartingZone = {
            name = "Starting Zone",
            desc = "Choose a different starting zone (branch-and-rejoin)",
            type = "execute",
            func = function() TurtleGuide:ShowStartingZoneSelector() end,
            order = 19,
        },
        ResetStartingZone = {
            name = "Reset Starting Zone",
            desc = "Reset starting zone selection and start fresh",
            type = "execute",
            func = function()
                TurtleGuide.db.char.startingzoneselected = false
                TurtleGuide.db.char.selectedstartingzone = nil
                TurtleGuide.db.char.startingzonecomplete = false
                TurtleGuide:ShowStartingZoneSelector()
            end,
            order = 20,
        },
        RoutePack = {
            name = "Route Packs",
            desc = "List available route packs",
            type = "execute",
            func = function()
                local packs = TurtleGuide:GetAvailableRoutePacks()
                local current = TurtleGuide.db.char.routepack
                TurtleGuide:Print("--- Available Route Packs ---")
                for _, pack in ipairs(packs) do
                    local marker = (current == pack.name) and " |cff00ff00(active)|r" or ""
                    TurtleGuide:Print("  " .. pack.displayName .. marker .. " - " .. pack.description)
                end
                TurtleGuide:Print("Use |cff00ccff/vg SetRoutePack <name>|r to switch.")
            end,
            order = 21,
        },
        SetRoutePack = {
            name = "Set Route Pack",
            desc = "Switch to a route pack (e.g., /vg SetRoutePack RestedXP)",
            type = "text",
            usage = "<pack name>",
            get = false,
            set = function(v)
                TurtleGuide:SelectRoutePack(v)
            end,
            order = 22,
        },
    },
}

---------
-- FuBar
---------
TurtleGuide.hasIcon = [[Interface\QuestFrame\UI-QuestLog-BookIcon]]
TurtleGuide.title = "VanillaGuide+"
TurtleGuide.defaultMinimapPosition = 215
TurtleGuide.defaultPosition = "CENTER"
TurtleGuide.cannotDetachTooltip = true
TurtleGuide.tooltipHiddenWhenEmpty = false
TurtleGuide.hideWithoutStandby = true
TurtleGuide.independentProfile = true

function TurtleGuide:OnInitialize()
    self:RegisterDB("TurtleGuideDB")
    self:RegisterDefaults("char", defaults)

    self.db.char.Dungeons = self.db.char.Dungeons or {}
    for k, v in pairs(defaults.Dungeons) do
        if self.db.char.Dungeons[k] == nil then
            self.db.char.Dungeons[k] = v
        end
    end
    self:RegisterChatCommand({ "/vg", "/turtleguide" }, options)
    self.OnMenuRequest = options
    self:SetupErrorCapture()
    if not FuBar then
        self.OnMenuRequest.args.hide.guiName = L["Hide minimap icon"]
        self.OnMenuRequest.args.hide.desc = L["Hide minimap icon"]
    end
    self.cachedturnins = self.db.char.cachedturnins
    if self.myfaction == nil then
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    self:PositionStatusFrame()
    self:CreateConfigPanel()
end

function TurtleGuide:OnEnable()
    self:PatchAstrolabe()
    local _, title = GetAddOnInfo("TurtleGuide")
    local author, version = GetAddOnMetadata("TurtleGuide", "Author"), GetAddOnMetadata("TurtleGuide", "Version")

    if self.db.char.debug then
        self:SetDebugging(true)
    else
        self:SetDebugging(false)
    end

    if self.myfaction == nil then
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
    else
        self:InitializeRoute()
    end
end

function TurtleGuide:InitializeRoute()
    self:SyncWithPfQuestHistory()
    -- Migration: set default route pack for existing characters
    if not self.db.char.routepack and self.db.char.routeselected then
        self.db.char.routepack = "VanillaGuide"
    end

    -- Load active route pack's routes into self.routes
    local activePack = self:GetCurrentRoutePack()
    if activePack then
        for race, route in pairs(activePack.routes) do
            self.routes[race] = route
        end
    end

    -- If no route selected yet, use the new starting zone selection system
    if not self.db.char.routeselected then
        -- Try the new branch-and-rejoin starting zone system first
        if self:InitializeRouteWithStartingZone() then
            -- Starting zone was handled, continue with initialization
        else
            -- Fallback: Auto-detect race and suggest route
            local _, race = UnitRace("player")
            local routeName = self:GetRouteForRace(race)
            if routeName and self.routes[routeName] then
                self:ApplyRouteSelection(routeName)
                local message = L["You have been assigned the %s leveling route."]
                if not message then
                    message = "You have been assigned the %s leveling route."
                end
                self:Print(string.format(message, tostring(race)))
            else
                -- Fallback to default start guides (including Turtle WoW races)
                local startguides = {
                    Orc = "Durotar (1-12)",
                    Troll = "Durotar (1-12)",
                    Tauren = "Mulgore (1-12)",
                    Undead = "Tirisfal (1-12)",
                    Dwarf = "Dun Morogh (1-12)",
                    Gnome = "Dun Morogh (1-12)",
                    Human = "Elwynn Forest (1-12)",
                    NightElf = "Teldrassil (1-12)",
                    -- Turtle WoW custom races
                    HighElf = "Thalassian Highlands (1-10)", -- High Elf starting zone
                    Goblin = "Blackstone Island (1-10)",     -- Goblin starting zone
                }
                -- Use normalized route name for lookup
                self.db.char.currentguide = startguides[routeName] or startguides[race] or self.guidelist[1]
                self.db.char.routeselected = true
            end
        end
    else
        -- Route already selected - check if we need to transition from starting zone
        if self.db.char.startingzoneselected and not self.db.char.startingzonecomplete then
            self:CheckStartingZoneCompletion()
        end
    end

    self.db.char.currentguide = self.db.char.currentguide or self.guidelist[1]
    self:LoadGuide(self.db.char.currentguide)
    self.initializeDone = true
    for _, event in pairs(self.TrackEvents) do self:RegisterEvent(event) end
    self:RegisterEvent("QUEST_COMPLETE", "UpdateStatusFrame")
    self:RegisterEvent("QUEST_DETAIL", "UpdateStatusFrame")
    self:RegisterEvent("QUEST_QUERY_COMPLETE")
    -- Register for level up to check starting zone completion
    self:RegisterEvent("PLAYER_LEVEL_UP")
    self.TrackEvents = nil
    self:QueryServerCompletedQuests()
    self:UpdateStatusFrame()
    -- Force waypoint creation on initial load
    self:ForceWaypointUpdate()
    self.enableDone = true
end

function TurtleGuide:OnDisable()
    self:UnregisterAllEvents()
end

-- Handle level up events for starting zone transition
function TurtleGuide:PLAYER_LEVEL_UP()
    -- Check if we should transition from starting zone to shared path
    if self.db.char.startingzoneselected and not self.db.char.startingzonecomplete then
        self:CheckStartingZoneCompletion()
    end
end

function TurtleGuide:OnTooltipUpdate()
    local hint = "\nClick to show/hide the Status\nRight-click for Options"
    T:SetHint(hint)
end

function TurtleGuide:OnTextUpdate()
    self:SetText("VanillaGuide+")
end

function TurtleGuide:OnClick()
    if TurtleGuide.statusframe:IsVisible() then
        HideUIPanel(TurtleGuide.statusframe)
    else
        ShowUIPanel(TurtleGuide.statusframe)
    end
end

function TurtleGuide:PLAYER_ENTERING_WORLD()
    self:PatchAstrolabe()
    self.myfaction = UnitFactionGroup("player")
    -- load static guides
    for i, t in ipairs(self.deferguides) do
        local name, nextzone, faction, sequencefunc = t[1], t[2], t[3], t[4]
        self:RegisterGuide(name, nextzone, faction, sequencefunc)
    end
    self.deferguides = {}
    -- deferred Initialize (VARIABLES_LOADED)
    if not self.initializeDone then
        self:InitializeRoute()
    end
    -- deferred Enable (PLAYER_LOGIN)
    if not self.enableDone then
        for _, event in pairs(self.TrackEvents) do self:RegisterEvent(event) end
        self:RegisterEvent("QUEST_COMPLETE", "UpdateStatusFrame")
        self:RegisterEvent("QUEST_DETAIL", "UpdateStatusFrame")
        self.TrackEvents = nil
        self:UpdateStatusFrame()
    end
    self.initializeDone = true
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end

function TurtleGuide:RegisterGuide(name, nextzone, faction, sequencefunc)
    if self.myfaction == nil then
        self.deferguides = self.deferguides or {}
        table.insert(self.deferguides, { name, nextzone, faction, sequencefunc })
    else
        if faction ~= "Both" and faction ~= self.myfaction then return end

        local isNew = (self.guides[name] == nil)
        self.guides[name] = sequencefunc
        self.nextzones[name] = nextzone

        if isNew then
            table.insert(self.guidelist, name)
        end
    end
end

-- Register a race-based route
function TurtleGuide:RegisterRoute(race, route)
    self.routes[race] = route
end

-- Register a named route pack (collection of per-race routes)
function TurtleGuide:RegisterRoutePack(packName, packInfo)
    self.routepacks[packName] = {
        name = packName,
        displayName = packInfo.displayName or packName,
        description = packInfo.description or "",
        routes = packInfo.routes or {},
        factionRestriction = packInfo.factionRestriction,
        classRestriction = packInfo.classRestriction,
    }
end

-- Check if a guide belongs to a route pack (should be hidden from guide list)
-- Note: we allow RXP guides to be shown as requested by the user
-- Now we also allow Optimized guides to be shown as requested by the user
function TurtleGuide:IsRoutePackGuide(guideName)
    return false
end

-- Get the currently active route pack (or nil)
function TurtleGuide:GetCurrentRoutePack()
    local packName = self.db.char.routepack
    if packName and self.routepacks[packName] then
        return self.routepacks[packName]
    end
    return nil
end

-- Get route packs available for the player's faction and class
function TurtleGuide:GetAvailableRoutePacks()
    local faction = self.myfaction
    local _, playerClass = UnitClass("player")
    local available = {}

    for name, pack in pairs(self.routepacks) do
        local factionOk = not pack.factionRestriction or pack.factionRestriction == faction
        local classOk = not pack.classRestriction or pack.classRestriction == playerClass
        if factionOk and classOk then
            table.insert(available, pack)
        end
    end

    -- Sort by name for consistent display
    table.sort(available, function(a, b) return a.name < b.name end)
    return available
end

-- Switch to a route pack, replacing self.routes with the pack's routes
function TurtleGuide:SelectRoutePack(packName)
    local pack = self.routepacks[packName]
    if not pack then
        self:Print("|cffff0000Unknown route pack: " .. tostring(packName) .. "|r")
        return false
    end

    -- Check faction/class restrictions
    local faction = self.myfaction
    local _, playerClass = UnitClass("player")
    if pack.factionRestriction and pack.factionRestriction ~= faction then
        self:Print("|cffff0000Route pack '" .. packName .. "' is for " .. pack.factionRestriction .. " only.|r")
        return false
    end
    if pack.classRestriction and pack.classRestriction ~= playerClass then
        self:Print("|cffff0000Route pack '" .. packName .. "' requires " .. pack.classRestriction .. " class.|r")
        return false
    end

    -- Save selection
    self.db.char.routepack = packName

    -- Auto-toggle checkboxes if RXP guide route is selected
    if packName == "RestedXP" or packName == "Kamisayo Speedrun" then
        self.db.char.filterRXP = true
        self.db.char.filterOptimized = false
        self.db.char.filterZone = false
        if self.guidelistframe and self.guidelistframe:IsVisible() then
            self:UpdateGuideListPanel()
        end
    end

    -- Copy pack routes into self.routes (replacing existing)
    for race, route in pairs(pack.routes) do
        self.routes[race] = route
    end

    -- Apply route for current race
    local _, race = UnitRace("player")
    local routeName = self:GetRouteForRace(race)
    self:ApplyRouteSelection(routeName)

    self:Print("|cff00ff00Route pack switched to: " .. pack.displayName .. "|r")
    return true
end

function TurtleGuide:LoadNextGuide()
    self:LoadGuide(self.nextzones[self.db.char.currentguide] or "No Guide", true)
    self:UpdateGuideListPanel()
    return true
end

function TurtleGuide:IsProfessionLearned(skillName)
    if not skillName then return false end
    for i = 1, GetNumSkillLines() do
        local name, isHeader = GetSkillLineInfo(i)
        if not isHeader and name and string.lower(name) == string.lower(skillName) then
            return true
        end
    end
    return false
end

function TurtleGuide:IsSpellLearned(spellName)
    if not spellName then return false end
    local i = 1
    while true do
        local name, rank = GetSpellName(i, "spell")
        if not name then break end
        if string.lower(name) == string.lower(spellName) then
            return true
        end
        i = i + 1
    end

    local i = 1
    while true do
        local name, rank = GetSpellName(i, "pet")
        if not name then break end
        if string.lower(name) == string.lower(spellName) then
            return true
        end
        i = i + 1
    end

    return false
end

function TurtleGuide:IsTrainingCompleted(stepName)
    if not stepName then return false end

    local _, _, name = string.find(stepName, "%[([^%]]+)%]")
    if not name then
        name = stepName
    end

    if name then
        name = string.gsub(name, "@.*@", "")
        name = string.gsub(name, "^Train%s+", "")
        name = string.gsub(name, "^Training%s+", "")
        name = string.gsub(name, "%s*%(Rank%s*%d+%)", "")
        name = string.gsub(name, "%s*%(.*%)", "")
        name = string.gsub(name, "%s*Part%s*%d+", "")
        name = TurtleGuide.trim(name)

        if string.len(name) > 0 then
            if self:IsProfessionLearned(name) then
                return true
            end

            if self:IsSpellLearned(name) then
                return true
            end
        end
    end

    return false
end

function TurtleGuide:GetQuestLogIndexByName(name)
    name = name or self.quests[self.current]
    if name then
        name = string.gsub(name, "@.*@", "")
        name = string.gsub(name, L.PART_GSUB, "")
    end
    for i = 1, GetNumQuestLogEntries() do
        local title, _, _, isHeader = GetQuestLogTitle(i)
        title = string.gsub(title, "%[[0-9%+%-]+]%s", "")
        if not isHeader and string.lower(title) == string.lower(name) then return i end
    end
end

function TurtleGuide:GetQuestDetails(name, oidx)
    if not name then return end
    local i = self:GetQuestLogIndexByName(name)
    if not i or i < 1 then return end
    local _, _, _, _, _, isComplete = GetQuestLogTitle(i)
    local complete = i and isComplete and isComplete == 1

    if oidx and not complete then
        -- Check only the specific objective index
        local numObjectives = GetNumQuestLeaderBoards(i)
        if numObjectives and oidx <= numObjectives then
            local text, objType, finished = GetQuestLogLeaderBoard(oidx, i)
            complete = not not finished
        else
            complete = false
        end
    elseif not complete and i then
        -- Fallback: check if all quest objectives are done via leaderboard
        local numObjectives = GetNumQuestLeaderBoards(i)
        if numObjectives and numObjectives > 0 then
            complete = true
            for j = 1, numObjectives do
                local text, objType, finished = GetQuestLogLeaderBoard(j, i)
                if not finished then
                    complete = false
                    break
                end
            end
        end
    end

    return i, complete
end

function TurtleGuide:FindBagSlot(itemid)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local item = GetContainerItemLink(bag, slot)
            if item and string.find(item, "item:" .. itemid) then return bag, slot end
        end
    end
    return false
end

function TurtleGuide:GetObjectiveInfo(i)
    local i = i or self.current
    if not self.actions[i] then return end

    return self.actions[i], string.gsub(self.quests[i], "@.*@", ""), self.quests[i] -- Action, display name, full name
end

function TurtleGuide:GetObjectiveStatus(i)
    local i = i or self.current
    if not self.actions[i] then return end

    local turnedin = self.turnedin[self.quests[i]]
    local oidx_str = self:GetObjectiveTag("OIDX", i)
    local oidx = oidx_str and tonumber(oidx_str) or nil
    local logi, complete = self:GetQuestDetails(self.quests[i], oidx)

    -- Server-side completion check for TURNIN and RUN actions with QID
    if not turnedin then
        local action = self.actions[i]
        local qid = self:GetObjectiveTag("QID", i)
        if qid and self:IsQuestCompletedOnServer(qid) then
            turnedin = true
        end
    end

    return turnedin, logi, complete
end

function TurtleGuide:SetTurnedIn(i, value, noupdate)
    if not i then
        i = self.current
        value = true
    end

    local qid = self:GetObjectiveTag("QID", i)
    if qid and not value then
        local qidNum = tonumber(qid)
        if pfQuest_history and (pfQuest_history[qidNum] or pfQuest_history[tostring(qidNum)]) then
            self:UpdateStatusFrame()
            return
        end
    end

    if value then value = true else value = nil end -- Cleanup to minimize savedvar data

    local quest = self.quests[i]
    self.turnedin[quest] = value
    self:Debug(string.format("Set turned in %q = %s", quest, tostring(value)))

    -- Mirror manual UNCHECK to clear completion state
    if not value then
        local qid = self:GetObjectiveTag("QID", i)
        local cleanQuest = string.gsub(quest, "@.*@", "")
        cleanQuest = string.gsub(cleanQuest, TurtleGuide.Locale.PART_GSUB, "")
        if qid then
            self.db.char.completedquestsbyid[tonumber(qid)] = nil
        end
        self.db.char.completedquests[cleanQuest] = nil
    end

    if not noupdate then
        self:UpdateStatusFrame()
    else
        self.updatedelay = i
    end
end

function TurtleGuide:CompleteQuest(name, noupdate)
    if not self.current then
        self:Debug(string.format("Cannot complete %q, no guide loaded", name))
        return
    end

    local action, quest
    for i in ipairs(self.actions) do
        action, quest = self:GetObjectiveInfo(i)
        self:Debug(string.format("Action %q Quest %q", action, quest))
        if action == "TURNIN" and not self:GetObjectiveStatus(i) and name == string.gsub(quest, L.PART_GSUB, "") then
            self:Debug(string.format("Saving quest turnin %q", quest))

            -- Save to completion DB permanently
            local qid = self:GetObjectiveTag("QID", i)
            local cleanQuest = string.gsub(quest, "@.*@", "")
            cleanQuest = string.gsub(cleanQuest, TurtleGuide.Locale.PART_GSUB, "")
            if qid then
                self.db.char.completedquestsbyid[tonumber(qid)] = true
            end
            self.db.char.completedquests[cleanQuest] = true

            return self:SetTurnedIn(i, true, noupdate)
        end
    end
    self:Debug(string.format("Quest %q not found!", name))
end

---------------------------------
--  Server Quest Query API     --
---------------------------------

function TurtleGuide:QueryServerCompletedQuests(force)
    self:SyncWithPfQuestHistory(force)
    -- Count locally tracked completed quests
    local localCountByName = 0
    local localCountByQid = 0
    if self.db.char.completedquests then
        for _ in pairs(self.db.char.completedquests) do
            localCountByName = localCountByName + 1
        end
    end
    if self.db.char.completedquestsbyid then
        for _ in pairs(self.db.char.completedquestsbyid) do
            localCountByQid = localCountByQid + 1
        end
    end

    -- Check pfQuest availability
    local hasPfQuest = pfDB and pfDB["quests"] and pfDB["quests"]["data"]
    if hasPfQuest then
        self:Print("|cff00ff00pfQuest database detected - using prerequisite chain inference|r")
    else
        self:Print("|cffff9900pfQuest not found - prerequisite inference unavailable|r")
    end

    self:Print(string.format("|cff88aaff%d quests tracked by name, %d by QID|r", localCountByName, localCountByQid))

    -- Re-run SmartSkipToStep to re-evaluate guide progress
    if self.actions and self.quests then
        local oldCurrent = self.current or 1
        self:SmartSkipToStep()
        local newCurrent = self.current or 1

        if newCurrent > oldCurrent then
            self:Print(string.format("|cff00ff00Skipped to step %d (was %d)|r", newCurrent, oldCurrent))
        else
            self:Print("|cff88ff88Guide progress is up to date|r")
        end
    else
        self:Print("|cffff9900No guide loaded|r")
    end

    self:UpdateStatusFrame()
    return true
end

function TurtleGuide:QUEST_QUERY_COMPLETE()
    -- Placeholder for future server API support
    -- Currently Turtle WoW 1.12 doesn't have QueryQuestsCompleted/GetQuestsCompleted
    self:Debug("QUEST_QUERY_COMPLETE fired (unexpected)")
end

function TurtleGuide:IsQuestCompletedOnServer(qid)
    if not qid then return false end
    return self.db.char.completedquestsbyid[tonumber(qid)] == true
end

---------------------------------
--   Quest Tracking            --
---------------------------------

-- Track the quest for the current objective
function TurtleGuide:TrackCurrentQuest()
    if not self.db.char.trackquests then return end
    if not self.current or not self.actions then return end

    local action, quest = self:GetObjectiveInfo(self.current)
    if not action or not quest then return end

    -- Untrack previously tracked quest from TurtleGuide
    if self.trackedQuestName and self.trackedQuestName ~= quest then
        local oldIndex = self:GetQuestLogIndexByName(self.trackedQuestName)
        if oldIndex and oldIndex > 0 and IsQuestWatched(oldIndex) then
            RemoveQuestWatch(oldIndex)
        end
        self.trackedQuestName = nil
    end

    -- Only auto-track for COMPLETE actions (quest objectives)
    if action == "COMPLETE" then
        local questLogIndex = self:GetQuestLogIndexByName(quest)
        if questLogIndex and questLogIndex > 0 then
            if not IsQuestWatched(questLogIndex) then
                AddQuestWatch(questLogIndex)
                self:Debug("Tracking quest: " .. quest .. " (index " .. questLogIndex .. ")")
            end
            self.trackedQuestName = quest
        end
    end
end

---------------------------------
--   Manual Navigation         --
---------------------------------

function TurtleGuide:SkipToNextObjective()
    if not self.current then return end
    if self.current >= table.getn(self.actions) then
        if not self:LoadNextGuide() then
            self:Print("Already at the last objective.")
        end
        return
    end

    -- Find next incomplete objective (after current)
    local nextStep = nil
    for i = self.current + 1, table.getn(self.actions) do
        if not self.turnedin[self.quests[i]] then
            nextStep = i
            break
        end
    end

    -- Mark current and all skipped objectives as done
    local endMark = nextStep and (nextStep - 1) or table.getn(self.actions)
    for i = self.current, endMark do
        self.turnedin[self.quests[i]] = true
    end

    if not nextStep then
        -- All remaining objectives are done, try next guide
        if not self:LoadNextGuide() then
            self:Print("All objectives complete.")
        end
        return
    end

    self.current = nextStep
    self:ForceWaypointUpdate()
    self:SetStatusText(self.current)
    self:UpdateOHPanel()
end

function TurtleGuide:GoToPreviousObjective()
    if not self.current or self.current <= 1 then
        self:Print("Already at the first objective.")
        return
    end

    -- Unmark current objective so we can come back to it
    self:SetTurnedIn(self.current, false, true)

    -- Find previous objective (go back one step, unmark it)
    local prevStep = self.current - 1
    self:SetTurnedIn(prevStep, false, true)

    self.current = prevStep
    self:ForceWaypointUpdate()
    self:SetStatusText(self.current)
    self:UpdateOHPanel()

    -- Flag to re-check completion conditions after rewind
    self.recheckCompletion = true
end

function TurtleGuide:GoToObjective(stepNum)
    stepNum = tonumber(stepNum)
    if not stepNum or stepNum < 1 or stepNum > table.getn(self.actions) then
        self:Print("Invalid step number.")
        return
    end

    -- Mark all objectives before stepNum as done (so progress persists)
    for i = 1, stepNum - 1 do
        if not self.turnedin[self.quests[i]] then
            self.turnedin[self.quests[i]] = true
        end
    end

    -- Unmark the target step and all after it
    for i = stepNum, table.getn(self.actions) do
        if self.turnedin[self.quests[i]] then
            self.turnedin[self.quests[i]] = nil
        end
    end

    self.current = stepNum
    self:ForceWaypointUpdate()
    self:SetStatusText(self.current)
    self:UpdateOHPanel()

    -- Flag to re-check completion conditions after jump
    self.recheckCompletion = true
end

---------------------------------
--      Branching Functions    --
---------------------------------

-- Branch to a different guide while saving current position
function TurtleGuide:BranchToGuide(guideName)
    if not guideName or not self.guides[guideName] then
        self:Print("Invalid guide: " .. tostring(guideName))
        return
    end

    -- Don't branch if already on this guide
    if self.db.char.currentguide == guideName then
        self:Print("Already on this guide.")
        return
    end

    -- Save current state if not already branching
    if not self.db.char.isbranching then
        self.db.char.branchsavedguide = self.db.char.currentguide
        self.db.char.branchsavedstep = self.current
        self.db.char.isbranching = true
        self:Print(string.format("Branching to %s (main route saved: %s)", guideName, self.db.char.branchsavedguide))
    else
        self:Print(string.format("Switching branch to %s", guideName))
    end

    -- Load the branch guide
    self:LoadGuide(guideName)
    self:UpdateStatusFrame()
    self:UpdateGuideListPanel()
end

-- Return from branch to saved main route
function TurtleGuide:ReturnFromBranch()
    if not self.db.char.isbranching then
        self:Print("Not currently on a branch.")
        return
    end

    local savedGuide = self.db.char.branchsavedguide
    local savedStep = self.db.char.branchsavedstep
    local playerLevel = UnitLevel("player")

    -- Clear branch state
    self.db.char.isbranching = false
    self.db.char.branchsavedguide = nil
    self.db.char.branchsavedstep = nil

    -- Find level-appropriate guide for current level
    local optimalGuide = self:GetOptimizedGuideForLevel(playerLevel)

    if optimalGuide and optimalGuide ~= savedGuide and self.guides[optimalGuide] then
        -- Player has leveled past their saved guide, load level-appropriate one
        self:Print("Returning to optimized path: " .. optimalGuide)
        self:LoadGuide(optimalGuide)
    elseif savedGuide and self.guides[savedGuide] then
        -- Return to saved guide
        self:Print("Returning to: " .. savedGuide)
        self:LoadGuide(savedGuide)
        -- SmartSkipToStep will handle positioning
    else
        self:Print("No saved guide to return to.")
    end

    self:UpdateStatusFrame()
    self:UpdateGuideListPanel()
end

-- Get the optimized guide for a given level based on the player's race route
function TurtleGuide:GetOptimizedGuideForLevel(level)
    -- Get the player's race
    local _, race = UnitRace("player")
    local routeName = self:GetRouteForRace(race)
    local route = self.routes and self.routes[routeName]
    if not route then return nil end

    -- Find the guide entry where level falls within range
    for _, entry in ipairs(route) do
        -- Parse level range like "12-20" or "1-12"
        local _, _, minText, maxText = string.find(entry.levels or "", "(%d+)%-(%d+)")
        local minLevel = tonumber(minText)
        local maxLevel = tonumber(maxText)
        if minLevel and maxLevel and level >= minLevel and level <= maxLevel then
            -- Only return if the guide exists
            if self.guides[entry.guide] then
                return entry.guide
            end
        end
    end

    -- If above all ranges, return the last guide that exists
    for i = table.getn(route), 1, -1 do
        if self.guides[route[i].guide] then
            return route[i].guide
        end
    end
    return nil
end

-- Check if current guide is complete and handle branch return
function TurtleGuide:CheckBranchCompletion()
    if not self.db.char.isbranching then return false end

    -- Check if current branch guide is 100% complete
    local totalSteps = self.actions and table.getn(self.actions) or 0
    if totalSteps == 0 then return false end

    local completedSteps = 0
    for i, quest in ipairs(self.quests) do
        if self.turnedin[quest] then
            completedSteps = completedSteps + 1
        end
    end

    local completion = completedSteps / totalSteps
    if completion >= 1 then
        self:Print("Branch guide complete! Returning to main route.")
        self:ReturnFromBranch()
        return true
    end

    return false
end

-- Turtle WoW custom zones for categorization
local TURTLE_ZONES = {
    ["Gilneas"] = true,
    ["Balor"] = true,
    ["Northwind"] = true,
    ["Grim Reaches"] = true,
    ["Icepoint Rock"] = true,
    ["Lapidis Isle"] = true,
    ["Tel'Abim"] = true,
    ["Gillijim's Isle"] = true,
    ["Gillijims Isle"] = true,
    ["Thalassian Highlands"] = true,
    ["Blackstone Island"] = true,
}

-- Categorize a guide by its name
function TurtleGuide:GetGuideCategory(guideName)
    if string.find(guideName, "^Optimized/") then
        return "optimized"
    end
    if string.find(guideName, "^RXP/") then
        return "rxp"
    end
    -- Check if any turtle zone name appears in guide name
    for zone in pairs(TURTLE_ZONES) do
        if string.find(guideName, zone) then
            return "turtle"
        end
    end
    return "zone"
end

-- Parse level range from guide name (e.g., "(1-12)" or "(12-20)" or "1-6 Name")
function TurtleGuide:ParseGuideLevelRange(guideName)
    -- Try (1-12) format first
    local _, _, minText, maxText = string.find(guideName, "%((%d+)%-(%d+)%)")
    if not minText then
        -- Try 1-12 format (common in RXP guides)
        _, _, minText, maxText = string.find(guideName, "(%d+)%-(%d+)")
    end

    if minText and maxText then
        return tonumber(minText), tonumber(maxText)
    end
    return nil, nil
end

---------------------------------
--      Route Functions        --
---------------------------------

-- Show route selection UI
function TurtleGuide:ShowRouteSelector()
    if not self.routeSelectorFrame then
        self:CreateRouteSelectorFrame()
    end
    self.routeSelectorFrame:Show()
end

function TurtleGuide:CreateRouteSelectorFrame()
    local f = CreateFrame("Frame", "TurtleGuideRouteSelectorFrame", UIParent)
    f:SetWidth(300)
    f:SetHeight(550)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")

    local title = f:CreateFontString(nil, "ARTWORK")
    title:SetFontObject(GameFontNormalLarge)
    title:SetPoint("TOP", f, "TOP", 0, -20)
    title:SetText(L["Select Your Race"])

    -- Route Pack section
    local packHeader = f:CreateFontString(nil, "ARTWORK")
    packHeader:SetFontObject(GameFontNormal)
    packHeader:SetPoint("TOP", title, "BOTTOM", 0, -12)
    packHeader:SetText("|cffffd100Route Pack:|r")

    -- Current pack display
    local packStatus = f:CreateFontString(nil, "ARTWORK")
    packStatus:SetFontObject(GameFontHighlightSmall)
    packStatus:SetPoint("TOP", packHeader, "BOTTOM", 0, -4)
    packStatus:SetWidth(260)
    f.packStatus = packStatus

    -- Pack buttons container
    f.packButtons = {}
    local lastPackBtn
    local availablePacks = self:GetAvailableRoutePacks()
    for i, pack in ipairs(availablePacks) do
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetWidth(200)
        btn:SetHeight(24)
        if lastPackBtn then
            btn:SetPoint("TOP", lastPackBtn, "BOTTOM", 0, -4)
        else
            btn:SetPoint("TOP", packStatus, "BOTTOM", 0, -6)
        end
        btn.packName = pack.name
        btn.packDescription = pack.description
        btn:SetText(pack.displayName)
        btn:SetScript("OnClick", function()
            TurtleGuide:SelectRoutePack(this.packName)
            TurtleGuide:UpdateRouteSelectorPackHighlight()
        end)
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.packDescription, nil, nil, nil, nil, true)
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        f.packButtons[i] = btn
        lastPackBtn = btn
    end

    -- Separator
    local sep = f:CreateFontString(nil, "ARTWORK")
    sep:SetFontObject(GameFontNormal)
    if lastPackBtn then
        sep:SetPoint("TOP", lastPackBtn, "BOTTOM", 0, -10)
    else
        sep:SetPoint("TOP", packStatus, "BOTTOM", 0, -10)
    end
    sep:SetText("|cffffd100Race Override:|r")

    local desc = f:CreateFontString(nil, "ARTWORK")
    desc:SetFontObject(GameFontHighlight)
    desc:SetPoint("TOP", sep, "BOTTOM", 0, -4)
    desc:SetWidth(260)
    desc:SetText(L["Choose a leveling route based on your race:"])

    -- Create race buttons (including Turtle WoW custom races)
    -- Add "My Race" at top to use actual detected race
    local _, detectedRace = UnitRace("player")
    local detectedRoute = self:GetRouteForRace(detectedRace)

    local races = {}
    -- Add detected race first with special label
    table.insert(races, { name = "My Race: " .. tostring(detectedRace), route = detectedRoute, highlight = true })

    if self.myfaction == "Alliance" then
        local allianceRaces = {
            { name = "Human",     route = "Human" },
            { name = "Dwarf",     route = "Dwarf" },
            { name = "Night Elf", route = "NightElf" },
            { name = "Gnome",     route = "Gnome" },
            { name = "High Elf",  route = "HighElf" }, -- Turtle WoW
        }
        for _, r in ipairs(allianceRaces) do
            table.insert(races, r)
        end
    else
        local hordeRaces = {
            { name = "Orc",    route = "Orc" },
            { name = "Troll",  route = "Troll" },
            { name = "Tauren", route = "Tauren" },
            { name = "Undead", route = "Undead" },
            { name = "Goblin", route = "Goblin" }, -- Turtle WoW
        }
        for _, r in ipairs(hordeRaces) do
            table.insert(races, r)
        end
    end

    local lastButton
    for i, raceInfo in ipairs(races) do
        local displayName = raceInfo.name
        local routeName = raceInfo.route
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetWidth(200)
        btn:SetHeight(30)
        if lastButton then
            btn:SetPoint("TOP", lastButton, "BOTTOM", 0, -10)
        else
            btn:SetPoint("TOP", desc, "BOTTOM", 0, -10)
        end
        btn:SetText(displayName)
        btn:SetScript("OnClick", function()
            TurtleGuide:SelectRoute(routeName)
            f:Hide()
        end)
        lastButton = btn
    end

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    self.routeSelectorFrame = f

    -- Update pack highlight on show
    f:SetScript("OnShow", function()
        TurtleGuide:UpdateRouteSelectorPackHighlight()
    end)

    f:Hide()
end

function TurtleGuide:UpdateRouteSelectorPackHighlight()
    local f = self.routeSelectorFrame
    if not f then return end

    local current = self.db.char.routepack or "VanillaGuide"
    f.packStatus:SetText("Active: |cff00ff00" .. current .. "|r")

    for _, btn in ipairs(f.packButtons) do
        if btn.packName == current then
            btn:SetText("|cff00ff00" .. btn.packName .. "|r")
        else
            btn:SetText(btn.packName)
        end
    end
end

function TurtleGuide:SelectRoute(race)
    self:ApplyRouteSelection(race)
    local message = L["You have been assigned the %s leveling route."]
    if not message then
        message = "You have been assigned the %s leveling route."
    end
    self:Print(string.format(message, tostring(race)))
    self:UpdateStatusFrame()
end

-- Get the next guide in the current route based on player level
-- Only returns guides that actually exist in self.guides
-- Finds the best guide for the player's level:
-- 1. First preference: guide where player is within the actual level range
-- 2. Second preference: guide where player is slightly over (within +2 buffer)
-- 3. Fallback: first future guide if player is somehow ahead of all guides
function TurtleGuide:GetNextRouteGuideForLevel(route, playerLevel)
    if not route then return nil end

    local level = playerLevel or UnitLevel("player")
    local bestGuide
    local bestMinLevel = -1
    local fallbackGuide -- For extended range matches
    local fallbackMinLevel = -1
    local futureGuide   -- First guide ahead of player's level
    local skippedGuides = {}

    for i, zone in ipairs(route) do
        local _, _, minText, maxText = string.find(zone.levels or "", "(%d+)%-(%d+)")
        local minLevel = tonumber(minText) or 1
        local maxLevel = tonumber(maxText) or 60

        if self.guides[zone.guide] then
            -- Priority 1: Player is within actual level range
            if level >= minLevel and level <= maxLevel then
                -- Pick the guide with the highest minLevel that still fits
                if minLevel > bestMinLevel then
                    bestGuide = zone.guide
                    bestMinLevel = minLevel
                end
                -- Priority 2: Player is slightly over (within +2 buffer for overlap)
            elseif level > maxLevel and level <= maxLevel + 2 then
                if minLevel > fallbackMinLevel then
                    fallbackGuide = zone.guide
                    fallbackMinLevel = minLevel
                end
                -- Priority 3: Guide is ahead of player (for fallback)
            elseif level < minLevel and not futureGuide then
                futureGuide = zone.guide
            end
        else
            -- Guide doesn't exist, record it as skipped
            table.insert(skippedGuides, zone.guide)
        end
    end

    -- Warn about skipped guides
    if table.getn(skippedGuides) > 0 then
        self:Print("|cffff9900Warning: Skipped missing guides: " .. table.concat(skippedGuides, ", ") .. "|r")
    end

    -- Return best match in priority order
    return bestGuide or fallbackGuide or futureGuide
end

function TurtleGuide:ApplyRouteSelection(race)
    self.db.char.currentroute = race
    self.db.char.routeselected = true

    local route = self.routes[race]
    local nextguide = self:GetNextRouteGuideForLevel(route, UnitLevel("player"))
    if not nextguide and route and route[1] and route[1].guide then
        nextguide = route[1].guide
    end
    if nextguide then
        self.db.char.currentguide = nextguide
        self:LoadGuide(self.db.char.currentguide)
    end
end

---------------------------------
--  Starting Zone Selection    --
--  (Branch-and-Rejoin Logic)  --
---------------------------------

-- Define starting zones for each faction
-- These are the "branch" points - race-specific 1-12 zones
TurtleGuide.startingZones = {
    Alliance = {
        { race = "Human",    zone = "Elwynn Forest",            guide = "Elwynn Forest (1-12)",        levels = "1-12", rejoinLevel = 12 },
        { race = "Dwarf",    zone = "Dun Morogh",               guide = "Dun Morogh (1-12)",           levels = "1-12", rejoinLevel = 12 },
        { race = "NightElf", zone = "Teldrassil",               guide = "Teldrassil (1-12)",           levels = "1-12", rejoinLevel = 12 },
        { race = "Gnome",    zone = "Dun Morogh",               guide = "Dun Morogh (1-12)",           levels = "1-12", rejoinLevel = 12 },
        { race = "HighElf",  zone = "Thalassian Highlands",     guide = "Thalassian Highlands (1-10)", levels = "1-10", rejoinLevel = 12 }, -- Turtle WoW
        -- RestedXP Survival Guides (Hardcore-safe routes)
        { race = "Human",    zone = "RXP Survival (Human)",     guide = "RXP/1-6 Northshire",          levels = "1-21", rejoinLevel = 21, isSurvival = true },
        { race = "Dwarf",    zone = "RXP Survival (Dwarf)",     guide = "RXP/1-6 Coldridge Valley",    levels = "1-21", rejoinLevel = 21, isSurvival = true },
        { race = "Gnome",    zone = "RXP Survival (Gnome)",     guide = "RXP/1-6 Coldridge Valley",    levels = "1-21", rejoinLevel = 21, isSurvival = true },
        { race = "NightElf", zone = "RXP Survival (Night Elf)", guide = "RXP/1-6 Shadowglen",          levels = "1-21", rejoinLevel = 21, isSurvival = true },
    },
    Horde = {
        { race = "Orc",     zone = "Durotar",                  guide = "Durotar (1-12)",             levels = "1-12", rejoinLevel = 12 },
        { race = "Troll",   zone = "Durotar",                  guide = "Durotar (1-12)",             levels = "1-12", rejoinLevel = 12 },
        { race = "Tauren",  zone = "Mulgore",                  guide = "Mulgore (1-12)",             levels = "1-12", rejoinLevel = 12 },
        { race = "Undead",  zone = "Tirisfal Glades",          guide = "Tirisfal (1-12)",            levels = "1-12", rejoinLevel = 12 },
        { race = "Goblin",  zone = "Blackstone Island",        guide = "Blackstone Island (1-10)",   levels = "1-10", rejoinLevel = 10 }, -- Turtle WoW
        -- RestedXP Survival Guides (Hardcore-safe routes)
        { race = "Orc",     zone = "RXP Survival (Orc/Troll)", guide = "RXP/1-6 Orc/Troll",          levels = "1-23", rejoinLevel = 23, isSurvival = true },
        { race = "Troll",   zone = "RXP Survival (Orc/Troll)", guide = "RXP/1-6 Orc/Troll",          levels = "1-23", rejoinLevel = 23, isSurvival = true },
        { race = "Tauren",  zone = "RXP Survival (Tauren)",    guide = "RXP/1-6 Tauren",             levels = "1-23", rejoinLevel = 23, isSurvival = true },
        { race = "Undead",  zone = "RXP Survival (Undead)",    guide = "RXP/1-6 Undead",             levels = "1-23", rejoinLevel = 23, isSurvival = true },
        -- RestedXP Speedrun Guides
        { race = "Warrior", zone = "Kamisayo Speedrun",        guide = "RXP/Kamisayo Speedrun 1-13", levels = "1-60", rejoinLevel = 60, class = "Warrior", isSpeedrun = true },
    },
}

-- Get available starting zones for the player's faction
function TurtleGuide:GetAvailableStartingZones()
    local faction = self.myfaction
    local zones = self.startingZones[faction] or {}
    local available = {}
    local _, playerClass = UnitClass("player")

    -- Filter to only include zones with existing guides and matching class
    for _, zoneInfo in ipairs(zones) do
        if self.guides[zoneInfo.guide] then
            -- Check class filter if present
            if zoneInfo.class then
                if zoneInfo.class == playerClass then
                    table.insert(available, zoneInfo)
                end
            else
                table.insert(available, zoneInfo)
            end
        end
    end

    return available
end

-- Get the player's native starting zone based on their race
function TurtleGuide:GetNativeStartingZone()
    local _, race = UnitRace("player")
    local routeName = self:GetRouteForRace(race)
    local faction = self.myfaction
    local zones = self.startingZones[faction] or {}

    for _, zoneInfo in ipairs(zones) do
        if zoneInfo.race == routeName then
            return zoneInfo
        end
    end

    -- Fallback to first zone for faction
    return zones[1]
end

-- Check if the current guide is a starting zone guide
function TurtleGuide:IsInStartingZone()
    local currentGuide = self.db.char.currentguide
    if not currentGuide then return false end

    local faction = self.myfaction
    local zones = self.startingZones[faction] or {}

    for _, zoneInfo in ipairs(zones) do
        if zoneInfo.guide == currentGuide then
            return true, zoneInfo
        end
    end

    return false
end

-- Get the rejoin point (shared route) based on current starting zone
-- The rejoin point is where all starting zone paths converge
function TurtleGuide:GetRejoinGuide()
    local faction = self.myfaction
    local playerLevel = UnitLevel("player")

    -- Shared routes after starting zone (level 12+)
    -- Alliance converges to Darkshore/Westfall path
    -- Horde converges to Barrens path
    local rejoinGuides = {
        Alliance = {
            { guide = "Westfall (12-17)",   minLevel = 12, maxLevel = 17 },
            { guide = "Darkshore (12-17)",  minLevel = 12, maxLevel = 17 },
            { guide = "Loch Modan (17-18)", minLevel = 17, maxLevel = 18 },
        },
        Horde = {
            { guide = "The Barrens (12-20)",       minLevel = 12, maxLevel = 20 },
            { guide = "Silverpine Forest (12-20)", minLevel = 12, maxLevel = 20 },
        },
    }

    local guideList = rejoinGuides[faction] or {}

    -- Find the best rejoin guide for player's level
    for _, entry in ipairs(guideList) do
        if self.guides[entry.guide] then
            if playerLevel >= entry.minLevel and playerLevel <= entry.maxLevel + 2 then
                return entry.guide
            end
        end
    end

    -- Fallback to first available rejoin guide
    for _, entry in ipairs(guideList) do
        if self.guides[entry.guide] then
            return entry.guide
        end
    end

    return nil
end

-- Handle starting zone completion and transition to shared path
function TurtleGuide:CheckStartingZoneCompletion()
    local inStartingZone, zoneInfo = self:IsInStartingZone()
    if not inStartingZone then return false end

    local playerLevel = UnitLevel("player")
    local rejoinLevel = zoneInfo and zoneInfo.rejoinLevel or 12

    -- Check if player has outleveled the starting zone
    if playerLevel >= rejoinLevel then
        -- Check if current guide is complete (or nearly complete)
        local totalSteps = self.actions and table.getn(self.actions) or 0
        if totalSteps == 0 then return false end

        local completedSteps = 0
        for i, quest in ipairs(self.quests) do
            if self.turnedin[quest] then
                completedSteps = completedSteps + 1
            end
        end

        local completion = completedSteps / totalSteps
        -- Transition when guide is 80%+ complete or player is 2+ levels above rejoin
        if completion >= 0.8 or playerLevel >= rejoinLevel + 2 then
            self:TransitionFromStartingZone()
            return true
        end
    end

    return false
end

-- Transition from starting zone to shared leveling path
function TurtleGuide:TransitionFromStartingZone()
    local L = self.Locale

    -- Mark starting zone as complete
    self.db.char.startingzonecomplete = true
    self.db.char.completion[self.db.char.currentguide] = 1

    self:Print("|cff00ff00" .. L["Starting zone complete!"] .. "|r")
    self:Print(L["Transitioning to shared leveling path..."])

    -- Get the rejoin guide
    local rejoinGuide = self:GetRejoinGuide()
    if rejoinGuide then
        self.db.char.currentguide = rejoinGuide
        self:LoadGuide(rejoinGuide)
        self:UpdateStatusFrame()
        self:UpdateGuideListPanel()
    else
        -- Fallback to standard LoadNextGuide behavior
        self:LoadNextGuide()
    end
end

-- Show the Starting Zone Selector UI
function TurtleGuide:ShowStartingZoneSelector()
    if not self.startingZoneSelectorFrame then
        self:CreateStartingZoneSelectorFrame()
    end
    self:UpdateStartingZoneSelectorPanel()
    self.startingZoneSelectorFrame:Show()
end

function TurtleGuide:CreateStartingZoneSelectorFrame()
    local L = self.Locale
    local f = CreateFrame("Frame", "TurtleGuideStartingZoneSelectorFrame", UIParent)
    f:SetWidth(380)
    f:SetHeight(320)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")

    -- Title
    local title = f:CreateFontString(nil, "ARTWORK")
    title:SetFontObject(GameFontNormalLarge)
    title:SetPoint("TOP", f, "TOP", 0, -20)
    title:SetText(L["Choose Starting Zone"])

    -- Description
    local desc = f:CreateFontString(nil, "ARTWORK")
    desc:SetFontObject(GameFontHighlight)
    desc:SetPoint("TOP", title, "BOTTOM", 0, -10)
    desc:SetWidth(340)
    desc:SetText(L["Select which starting zone you want to level through:"])

    -- Native race indicator
    local nativeText = f:CreateFontString(nil, "ARTWORK")
    nativeText:SetFontObject(GameFontNormal)
    nativeText:SetPoint("TOP", desc, "BOTTOM", 0, -15)
    nativeText:SetWidth(340)
    f.nativeText = nativeText

    -- Container for zone buttons
    local buttonContainer = CreateFrame("Frame", nil, f)
    buttonContainer:SetPoint("TOP", nativeText, "BOTTOM", 0, -10)
    buttonContainer:SetWidth(340)
    buttonContainer:SetHeight(180)
    f.buttonContainer = buttonContainer

    -- Zone buttons (will be populated dynamically)
    f.zoneButtons = {}
    for i = 1, 6 do
        local btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
        btn:SetWidth(300)
        btn:SetHeight(28)
        btn:SetPoint("TOP", buttonContainer, "TOP", 0, -(i - 1) * 32)
        btn:Hide()

        btn:SetScript("OnClick", function()
            if this.zoneInfo then
                TurtleGuide:SelectStartingZone(this.zoneInfo)
                f:Hide()
            end
        end)

        f.zoneButtons[i] = btn
    end

    -- Info text at bottom
    local infoText = f:CreateFontString(nil, "ARTWORK")
    infoText:SetFontObject(GameFontNormalSmall)
    infoText:SetPoint("BOTTOM", f, "BOTTOM", 0, 40)
    infoText:SetWidth(340)
    infoText:SetTextColor(0.7, 0.7, 0.7)
    infoText:SetText(L["You can change starting zones from the Options menu"])

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    self.startingZoneSelectorFrame = f
    table.insert(UISpecialFrames, "TurtleGuideStartingZoneSelectorFrame")
    f:Hide()
end

function TurtleGuide:UpdateStartingZoneSelectorPanel()
    local f = self.startingZoneSelectorFrame
    if not f or not f:IsVisible() then return end

    local L = self.Locale
    local nativeZone = self:GetNativeStartingZone()
    local availableZones = self:GetAvailableStartingZones()

    -- Show native race info
    if nativeZone then
        local _, race = UnitRace("player")
        f.nativeText:SetText("|cff00ff00" .. L["Recommended for your race"] .. ":|r " .. race .. " - " .. nativeZone
            .zone)
    else
        f.nativeText:SetText("")
    end

    -- Hide all buttons first
    for i, btn in ipairs(f.zoneButtons) do
        btn:Hide()
        btn.zoneInfo = nil
    end

    -- Populate buttons with available zones
    for i, zoneInfo in ipairs(availableZones) do
        local btn = f.zoneButtons[i]
        if btn then
            local isNative = nativeZone and (zoneInfo.race == nativeZone.race)
            local displayText = zoneInfo.zone .. " (" .. zoneInfo.levels .. ")"

            if zoneInfo.isSpeedrun then
                displayText = "|cffff8800[Speedrun]|r " .. displayText
            elseif zoneInfo.isSurvival then
                displayText = "|cff00ffcc[Survival]|r " .. displayText
            elseif isNative then
                displayText = displayText .. " |cff00ff00*|r"
            end

            btn:SetText(displayText)
            btn.zoneInfo = zoneInfo
            btn:Show()
        end
    end

    -- Adjust frame height based on number of zones
    local numZones = table.getn(availableZones)
    local height = 180 + (numZones * 32)
    f:SetHeight(math.max(220, height))
end

-- Select a starting zone and begin leveling there
function TurtleGuide:SelectStartingZone(zoneInfo)
    local L = self.Locale

    -- Save the selection
    self.db.char.startingzoneselected = true
    self.db.char.selectedstartingzone = zoneInfo.race
    self.db.char.startingzonecomplete = false
    self.db.char.rejoinlevel = zoneInfo.rejoinLevel or 12

    -- Also set the route to match the starting zone's race
    -- This ensures the shared route after rejoin is appropriate
    self.db.char.currentroute = zoneInfo.race
    self.db.char.routeselected = true

    -- Set route pack based on zone type
    if zoneInfo.isSpeedrun then
        self.db.char.routepack = "Kamisayo Speedrun"
        local pack = self.routepacks["Kamisayo Speedrun"]
        if pack then
            for race, route in pairs(pack.routes) do
                self.routes[race] = route
            end
        end
    elseif zoneInfo.isSurvival then
        self.db.char.routepack = "RestedXP"
        local pack = self.routepacks["RestedXP"]
        if pack then
            for race, route in pairs(pack.routes) do
                self.routes[race] = route
            end
        end
    else
        if not self.db.char.routepack then
            self.db.char.routepack = "VanillaGuide"
        end
    end

    -- Load the starting zone guide
    if self.guides[zoneInfo.guide] then
        self.db.char.currentguide = zoneInfo.guide
        self:LoadGuide(zoneInfo.guide)

        local _, playerRace = UnitRace("player")
        local playerRoute = self:GetRouteForRace(playerRace)

        if zoneInfo.race ~= playerRoute then
            self:Print(string.format(L["Cross-race start: %s"], zoneInfo.zone))
        end

        self:Print(string.format(L["You have been assigned the %s leveling route."], zoneInfo.zone))
    else
        self:Print("|cffff0000Error: Guide not found: " .. zoneInfo.guide .. "|r")
    end

    self:UpdateStatusFrame()
    self:UpdateGuideListPanel()
end

-- Modified InitializeRoute to show starting zone selector for new characters
function TurtleGuide:InitializeRouteWithStartingZone()
    local playerLevel = UnitLevel("player")

    -- If player is level 1-10 and hasn't selected a starting zone, show selector
    if playerLevel <= 10 and not self.db.char.startingzoneselected then
        -- Auto-detect race and pre-select the native starting zone
        local nativeZone = self:GetNativeStartingZone()
        if nativeZone and self.guides[nativeZone.guide] then
            -- Silently apply native zone as default
            self:SelectStartingZone(nativeZone)
        else
            -- Show selector if native zone doesn't exist
            self:ShowStartingZoneSelector()
        end
        return true
    end

    -- If player already selected a starting zone but hasn't completed it
    if self.db.char.startingzoneselected and not self.db.char.startingzonecomplete then
        -- Check if they've outleveled the starting zone
        if self:CheckStartingZoneCompletion() then
            return true
        end
    end

    return false
end

function TurtleGuide:SetupErrorCapture()
    if self.errorCaptured then return end
    self.errorCaptured = true
    self.errorLog = self.errorLog or {}

    local originalHandler = geterrorhandler()
    seterrorhandler(function(errorMessage)
        local timestamp = date("%H:%M:%S")
        local stack = debugstack and debugstack(2, 12, 12) or "(no stack)"
        local entry = string.format("[%s] %s\n%s", timestamp, tostring(errorMessage), tostring(stack))
        table.insert(self.errorLog, 1, entry)
        if table.getn(self.errorLog) > 50 then
            table.remove(self.errorLog)
        end
        if originalHandler then
            originalHandler(errorMessage)
        end
    end)
end

function TurtleGuide:ShowErrorLog()
    if not self.errorLogFrame then
        self:CreateErrorLogFrame()
    end
    self.errorLogFrame:Show()
end

function TurtleGuide:CreateErrorLogFrame()
    local f = CreateFrame("Frame", "TurtleGuideErrorLogFrame", UIParent)
    f:SetWidth(520)
    f:SetHeight(360)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    local title = f:CreateFontString(nil, "ARTWORK")
    title:SetFontObject(GameFontNormalLarge)
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("VanillaGuide+ Error Log")

    local desc = f:CreateFontString(nil, "ARTWORK")
    desc:SetFontObject(GameFontHighlight)
    desc:SetPoint("TOP", title, "BOTTOM", 0, -8)
    desc:SetWidth(480)
    desc:SetText("Most recent errors are at the top. Use Ctrl+C to copy.")

    local scrollFrame = CreateFrame("ScrollFrame", "TurtleGuideErrorLogScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 16)

    local editBox = CreateFrame("EditBox", "TurtleGuideErrorLogEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(470)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    editBox:SetScript("OnEditFocusGained", function()
        editBox:HighlightText(0)
    end)

    scrollFrame:SetScrollChild(editBox)
    f.editBox = editBox

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    f:SetScript("OnShow", function()
        local entries = TurtleGuide.errorLog or {}
        if table.getn(entries) == 0 then
            f.editBox:SetText("No errors captured yet.")
        else
            f.editBox:SetText(table.concat(entries, "\n\n"))
        end
        if f.editBox.SetCursorPosition then
            f.editBox:SetCursorPosition(0)
        end
        f.editBox:HighlightText(0)
    end)

    self.errorLogFrame = f
end

---------------------------------
--      Utility Functions      --
---------------------------------

function TurtleGuide.select(index, ...)
    assert(tonumber(index) or index == "#", "Invalid argument #1 to select(). Usage: select(\"#\"|int,...)")
    if index == "#" then
        return tonumber(arg.n) or 0
    end
    for i = 1, index - 1 do
        table.remove(arg, 1)
    end
    return unpack(arg)
end

function TurtleGuide.join(delimiter, list)
    assert(type(delimiter) == "string" and type(list) == "table",
        "Invalid arguments to join(). Usage: string.join(delimiter, list)")
    local len = getn(list)
    if len == 0 then
        return ""
    end
    local s = list[1]
    for i = 2, len do
        s = string.format("%s%s%s", s, delimiter, list[i])
    end
    return s
end

function TurtleGuide.trim(s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function TurtleGuide.split(...)
    assert(arg.n > 0 and type(arg[1]) == "string",
        "Invalid arguments to split(). Usage: string.split([separator], subject)")
    local sep, s = arg[1], arg[2]
    if s == nil then
        s, sep = sep, ":"
    end
    local fields = {}
    local pattern = string.format("([^%s]+)", sep)
    string.gsub(s, pattern, function(c) fields[table.getn(fields) + 1] = c end)
    return fields
end

function TurtleGuide.modf(f)
    if f > 0 then
        return math.floor(f), math.mod(f, 1)
    end
    return math.ceil(f), math.mod(f, 1)
end

function TurtleGuide.GetItemCount(itemID)
    local itemInfoTexture = TurtleGuide.select(9, GetItemInfo(itemID))
    if itemInfoTexture == nil then return 0 end
    local totalItemCount = 0
    for i = 0, NUM_BAG_FRAMES do
        local numSlots = GetContainerNumSlots(i)
        if numSlots > 0 then
            for k = 1, numSlots do
                local itemTexture, itemCount = GetContainerItemInfo(i, k)
                if itemInfoTexture == itemTexture then
                    totalItemCount = totalItemCount + itemCount
                end
            end
        end
    end
    return totalItemCount
end

function TurtleGuide.ColorGradient(perc)
    if perc >= 1 then
        return 0, 1, 0
    elseif perc <= 0 then
        return 1, 0, 0
    end

    local segment, relperc = TurtleGuide.modf(perc * 2)
    local r1, g1, b1, r2, g2, b2 = TurtleGuide.select((segment * 3) + 1, 1, 0, 0, 1, 0.82, 0, 0, 1, 0)
    return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
end

function TurtleGuide.GetQuadrant(frame)
    local x, y = frame:GetCenter()
    if not x or not y then return "BOTTOMLEFT", "BOTTOM", "LEFT" end
    local hhalf = (x > UIParent:GetWidth() / 2) and "RIGHT" or "LEFT"
    local vhalf = (y > UIParent:GetHeight() / 2) and "TOP" or "BOTTOM"
    return vhalf .. hhalf, vhalf, hhalf
end

function TurtleGuide.GetUIParentAnchor(frame)
    local w, h, x, y = UIParent:GetWidth(), UIParent:GetHeight(), frame:GetCenter()
    local hhalf, vhalf = (x > w / 2) and "RIGHT" or "LEFT", (y > h / 2) and "TOP" or "BOTTOM"
    local dx = hhalf == "RIGHT" and math.floor(frame:GetRight() + 0.5) - w or math.floor(frame:GetLeft() + 0.5)
    local dy = vhalf == "TOP" and math.floor(frame:GetTop() + 0.5) - h or math.floor(frame:GetBottom() + 0.5)
    return vhalf .. hhalf, dx, dy
end

function TurtleGuide:SyncWithPfQuestHistory(force)
    if not pfQuest_history then return end

    if force then
        self.db.char.completedquestsbyid = {}
        self.db.char.completedquests = {}
        if self.db.char.turnins then
            for k in pairs(self.db.char.turnins) do
                self.db.char.turnins[k] = nil
            end
        end
        if self.turnedin then
            for k in pairs(self.turnedin) do
                self.turnedin[k] = nil
            end
        end
        if self.db.char.currentguide then
            self.db.char.turnins[self.db.char.currentguide] = self.turnedin or {}
        end
    end

    local imported = 0

    -- pfQuest_history is a SavedVariablesPerCharacter flat table:
    -- pfQuest_history[qid] = { [1] = timestamp, [2] = level }
    for qid, data in pairs(pfQuest_history) do
        local qidNum = tonumber(qid)
        if qidNum and type(data) == "table" then
            if not self.db.char.completedquestsbyid[qidNum] then
                self.db.char.completedquestsbyid[qidNum] = true
                imported = imported + 1
            end

            -- Also populate the name-based completion table if we can find the name in pfQuest
            if pfDB and pfDB.quests and pfDB.quests.loc and pfDB.quests.loc[qidNum] then
                local questName = pfDB.quests.loc[qidNum]["T"]
                if questName then
                    local cleanQuest = string.gsub(questName, "%[[0-9%+%-]+]%s", "")
                    cleanQuest = string.gsub(cleanQuest, TurtleGuide.Locale.PART_GSUB, "")
                    self.db.char.completedquests[cleanQuest] = true
                end
            end
        end
    end

    if imported > 0 then
        self:Debug(string.format("Imported %d completed quests from pfQuest history.", imported))
    end
end

function TurtleGuide:DumpLoc()
    if IsShiftKeyDown() then
        if not self.db.global.savedpoints then
            self:Print("No saved points")
        else
            for t in string.gfind(self.db.global.savedpoints, "([^\n]+)") do self:Print(t) end
        end
    elseif IsControlKeyDown() then
        self.db.global.savedpoints = nil
        self:Print("Saved points cleared")
    else
        local _, _, x, y = Astrolabe:GetCurrentPlayerPosition()
        local s = string.format("%s, %s, (%.2f, %.2f) -- %s %s", GetZoneText(), GetSubZoneText(), x * 100, y * 100,
            self:GetObjectiveInfo())
        self.db.global.savedpoints = (self.db.global.savedpoints or "") .. s .. "\n"
        self:Print(s)
    end
end
