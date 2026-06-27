local TurtleGuide = TurtleGuide
local ww = WidgetWarlock

local title

local NUMROWS, COLWIDTH = 16, 210
local ROWHEIGHT = 305 / NUMROWS
local TOTALROWS = NUMROWS * 3

local offset = 0
local rows = {}
local displayList = {}
local levelFilterOn = false
local turtleCheck
local optimizedCheck
local rxpCheck
local zoneCheck

local function SortGuidesByLevel(a, b)
    local aMin, aMax = TurtleGuide:ParseGuideLevelRange(a)
    local bMin, bMax = TurtleGuide:ParseGuideLevelRange(b)

    if not aMin and not bMin then
        return a < b
    elseif not aMin then
        return false
    elseif not bMin then
        return true
    end

    if aMin ~= bMin then
        return aMin < bMin
    elseif aMax ~= bMax then
        return aMax < bMax
    else
        return a < b
    end
end

local function HideTooltip()
    if GameTooltip:IsOwned(this) then
        GameTooltip:Hide()
    end
end

local function ShowTooltip()
    local f = this
    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")

    local lines = {}
    if f.guide then
        table.insert(lines, "|cffffd100" .. f.guide .. "|r")
        table.insert(lines, "")
    end
    table.insert(lines, "Left-click: Load this guide")
    table.insert(lines, "Right-click: Branch to this guide")

    if f.guide and TurtleGuide.db.char.completion[f.guide] == 1 then
        table.insert(lines, "Shift-click: Reset progress")
    end

    if f.guide and TurtleGuide.db.char.isbranching and TurtleGuide.db.char.branchsavedguide == f.guide then
        table.insert(lines, "|cff00ff00(Your saved main route)|r")
    end

    GameTooltip:SetText(table.concat(lines, "\n"), nil, nil, nil, nil, true)
end

local function OnClick()
    local f = this
    local btn = arg1
    if IsShiftKeyDown() then
        TurtleGuide.db.char.completion[f.guide] = nil
        TurtleGuide.db.char.turnins[f.guide] = {}
        TurtleGuide:UpdateGuideListPanel()
        GameTooltip:Hide()
    elseif btn == "RightButton" then
        local text = f.guide
        if text then
            TurtleGuide:BranchToGuide(text)
            TurtleGuide:UpdateGuideListPanel()
        end
    else
        local text = f.guide
        if not text then
            f:SetChecked(false)
        else
            local isRXP = string.find(text, "^RXP/")
            local currentPack = TurtleGuide.db.char.routepack

            -- If manually picking an RXP guide, ensure an RXP-based route pack is active
            -- so that auto-navigation continues with compatible guides
            if isRXP and currentPack ~= "RestedXP" and currentPack ~= "Kamisayo Speedrun" then
                TurtleGuide:SelectRoutePack("RestedXP")
            end

            TurtleGuide:LoadGuide(text)
            TurtleGuide:UpdateStatusFrame()
            TurtleGuide:UpdateGuideListPanel()
        end
    end
end

local frame = CreateFrame("Frame", "TurtleGuideGuideList", TurtleGuide.statusframe)
TurtleGuide.guidelistframe = frame
frame:SetFrameStrata("DIALOG")
frame:SetWidth(660)
frame:SetHeight(320 + 28)
frame:SetPoint("TOPRIGHT", TurtleGuide.statusframe, "BOTTOMRIGHT")
frame:SetBackdrop(ww.TooltipBorderBG)
frame:SetBackdropColor(0.09, 0.09, 0.19, 1)
frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.5)
frame:Hide()

local closebutton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closebutton:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
frame.closebutton = closebutton

local title = ww.SummonFontString(frame, nil, "SubZoneTextFont", nil, "BOTTOM", frame, "TOP")
local fontname, fontheight, fontflags = title:GetFont()
title:SetFont(fontname, 18, fontflags)
title:SetText("Guide List")
frame.title = title

-- Level filter checkbox
local filterCheck = ww.SummonCheckBox(18, frame, "TOPLEFT", 15, -6)
local filterLabel = ww.SummonFontString(filterCheck, "OVERLAY", "GameFontNormalSmall", "Level filter (+/-5)", "LEFT",
    filterCheck, "RIGHT", 2, 0)
filterCheck:SetScript("OnClick", function()
    levelFilterOn = not levelFilterOn
    filterCheck:SetChecked(levelFilterOn)
    offset = 0
    TurtleGuide:UpdateGuideListPanel()
end)

-- TurtleWoW checkbox
turtleCheck = ww.SummonCheckBox(18, frame, "TOPLEFT", 145, -6)
local turtleLabel = ww.SummonFontString(turtleCheck, "OVERLAY", "GameFontNormalSmall", "TurtleWoW", "LEFT",
    turtleCheck, "RIGHT", 2, 0)
turtleCheck:SetScript("OnClick", function()
    if TurtleGuide.db.char.filterTurtle == nil then TurtleGuide.db.char.filterTurtle = true end
    TurtleGuide.db.char.filterTurtle = not TurtleGuide.db.char.filterTurtle
    turtleCheck:SetChecked(TurtleGuide.db.char.filterTurtle)
    offset = 0
    TurtleGuide:UpdateGuideListPanel()
end)

-- Optimized checkbox
optimizedCheck = ww.SummonCheckBox(18, frame, "TOPLEFT", 240, -6)
local optimizedLabel = ww.SummonFontString(optimizedCheck, "OVERLAY", "GameFontNormalSmall", "Optimized", "LEFT",
    optimizedCheck, "RIGHT", 2, 0)
optimizedCheck:SetScript("OnClick", function()
    if TurtleGuide.db.char.filterOptimized == nil then TurtleGuide.db.char.filterOptimized = true end
    TurtleGuide.db.char.filterOptimized = not TurtleGuide.db.char.filterOptimized
    optimizedCheck:SetChecked(TurtleGuide.db.char.filterOptimized)
    offset = 0
    TurtleGuide:UpdateGuideListPanel()
end)

-- RXP checkbox
rxpCheck = ww.SummonCheckBox(18, frame, "TOPLEFT", 335, -6)
local rxpLabel = ww.SummonFontString(rxpCheck, "OVERLAY", "GameFontNormalSmall", "RXP", "LEFT",
    rxpCheck, "RIGHT", 2, 0)
rxpCheck:SetScript("OnClick", function()
    if TurtleGuide.db.char.filterRXP == nil then TurtleGuide.db.char.filterRXP = true end
    TurtleGuide.db.char.filterRXP = not TurtleGuide.db.char.filterRXP
    rxpCheck:SetChecked(TurtleGuide.db.char.filterRXP)
    offset = 0
    TurtleGuide:UpdateGuideListPanel()
end)

-- Zone checkbox
zoneCheck = ww.SummonCheckBox(18, frame, "TOPLEFT", 410, -6)
local zoneLabel = ww.SummonFontString(zoneCheck, "OVERLAY", "GameFontNormalSmall", "Zone", "LEFT",
    zoneCheck, "RIGHT", 2, 0)
zoneCheck:SetScript("OnClick", function()
    if TurtleGuide.db.char.filterZone == nil then TurtleGuide.db.char.filterZone = true end
    TurtleGuide.db.char.filterZone = not TurtleGuide.db.char.filterZone
    zoneCheck:SetChecked(TurtleGuide.db.char.filterZone)
    offset = 0
    TurtleGuide:UpdateGuideListPanel()
end)

-- Return to Main button
local returnBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
returnBtn:SetWidth(120)
returnBtn:SetHeight(20)
returnBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -6)
returnBtn:SetText("Return to Main")
returnBtn:SetScript("OnClick", function()
    TurtleGuide:ReturnFromBranch()
    TurtleGuide:UpdateGuideListPanel()
end)
frame.returnBtn = returnBtn

-- Fill in the frame with guide CheckButtons (3-column layout)
for i = 1, TOTALROWS do
    local anchor, point = rows[i - 1], "BOTTOMLEFT"
    if i == 1 then
        anchor, point = frame, "TOPLEFT"
    elseif i == (NUMROWS + 1) then
        anchor, point = rows[1], "TOPRIGHT"
    elseif i == (NUMROWS * 2 + 1) then
        anchor, point = rows[NUMROWS + 1], "TOPRIGHT"
    end

    local row = CreateFrame("CheckButton", nil, frame)
    if i == 1 then
        row:SetPoint("TOPLEFT", anchor, point, 15, -30)
    else
        row:SetPoint("TOPLEFT", anchor, point)
    end
    row:SetHeight(ROWHEIGHT)
    row:SetWidth(COLWIDTH)

    local highlight = ww.SummonTexture(row, nil, nil, nil, "Interface\\HelpFrame\\HelpFrameButton-Highlight")
    highlight:SetTexCoord(0, 1, 0, 0.578125)
    highlight:SetAllPoints()
    highlight:SetAlpha(0.5)
    row:SetHighlightTexture(highlight)
    row:SetCheckedTexture(highlight)

    local text = ww.SummonFontString(row, nil, "GameFontWhite", nil, "LEFT", 6, 0)
    local fn, fh, ff = title:GetFont()
    text:SetFont(fn, 11, ff)
    text:SetTextColor(.79, .79, .79, 1)
    text:SetWidth(COLWIDTH - 12)
    text:SetHeight(ROWHEIGHT)
    text:SetJustifyH("LEFT")

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", OnClick)
    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", HideTooltip)

    row.text = text
    rows[i] = row
end

-- Slider for scrolling
local slider = CreateFrame("Slider", "TurtleGuideGuideListSlider", frame, "UIPanelScrollBarTemplate")
slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -45)
slider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 25)
slider:SetMinMaxValues(0, 100)
slider:SetValueStep(1)
slider:SetWidth(16)
frame.slider = slider

slider:SetScript("OnValueChanged", function()
    local val = arg1
    if not slider.updating and TurtleGuide.UpdateGuideListPanel then
        offset = math.floor(val)
        TurtleGuide:UpdateGuideListPanel()
    end
end)
slider:SetValue(0)

frame:SetScript("OnShow", function()
    offset = 0
    local quad, vhalf, hhalf = TurtleGuide.GetQuadrant(TurtleGuide.statusframe)
    local anchpoint = (vhalf == "TOP" and "BOTTOM" or "TOP") .. hhalf
    this:ClearAllPoints()
    this:SetPoint(quad, TurtleGuide.statusframe, anchpoint)
    TurtleGuide:UpdateGuideListPanel()
    this:SetAlpha(0)
    this:SetScript("OnUpdate", ww.FadeIn)
end)

frame:EnableMouseWheel()
frame:SetScript("OnMouseWheel", function()
    local val = arg1
    local oldOffset = offset
    offset = offset - val * NUMROWS
    local maxOffset = math.max(0, table.getn(displayList) - TOTALROWS)
    if offset > maxOffset then offset = maxOffset end
    if offset < 0 then offset = 0 end

    if offset ~= oldOffset then
        slider.updating = true
        slider:SetValue(offset)
        slider.updating = false
        TurtleGuide:UpdateGuideListPanel()
    end
end)

ww.SetFadeTime(frame, 0.7)

table.insert(UISpecialFrames, "TurtleGuideGuideList")

-- Public API: open guide list with optional level filter preset
function TurtleGuide:ShowGuideList(withLevelFilter)
    if withLevelFilter then
        levelFilterOn = true
    end
    self.guidelistframe:Show()
end

function TurtleGuide:UpdateGuideListPanel()
    if not frame or not frame:IsVisible() then return end

    -- Update title to show branch status
    if self.db.char.isbranching then
        frame.title:SetText("Guide List |cff00ff00(Branching)|r")
    else
        frame.title:SetText("Guide List")
    end

    -- Show/hide Return to Main button
    if self.db.char.isbranching then
        frame.returnBtn:Show()
        frame.returnBtn:Enable()
    else
        frame.returnBtn:Hide()
    end

    -- Ensure default database filters are initialized
    if self.db.char.filterTurtle == nil then self.db.char.filterTurtle = true end
    if self.db.char.filterOptimized == nil then self.db.char.filterOptimized = true end
    if self.db.char.filterRXP == nil then self.db.char.filterRXP = true end
    if self.db.char.filterZone == nil then self.db.char.filterZone = true end

    -- Update filter checkboxes state
    filterCheck:SetChecked(levelFilterOn)
    if turtleCheck then turtleCheck:SetChecked(self.db.char.filterTurtle) end
    if optimizedCheck then optimizedCheck:SetChecked(self.db.char.filterOptimized) end
    if rxpCheck then rxpCheck:SetChecked(self.db.char.filterRXP) end
    if zoneCheck then zoneCheck:SetChecked(self.db.char.filterZone) end

    -- Build categorized display list (fresh table each time)
    displayList = {}
    local turtleGuides = {}
    local optimizedGuides = {}
    local rxpGuides = {}
    local zoneGuides = {}
    local seen = {}

    local playerLevel = UnitLevel("player") or 0
    local margin = 5

    for _, name in ipairs(self.guidelist) do
        if not self:IsRoutePackGuide(name) and not seen[name] then
            seen[name] = true

            local include = true
            if levelFilterOn then
                local minLevel, maxLevel = self:ParseGuideLevelRange(name)
                if minLevel and maxLevel then
                    if playerLevel < (minLevel - margin) or playerLevel > (maxLevel + margin) then
                        include = false
                    end
                end
            end

            if include then
                local cat = self:GetGuideCategory(name)
                if cat == "turtle" then
                    if self.db.char.filterTurtle then
                        table.insert(turtleGuides, name)
                    end
                elseif cat == "optimized" then
                    if self.db.char.filterOptimized then
                        table.insert(optimizedGuides, name)
                    end
                elseif cat == "rxp" then
                    if self.db.char.filterRXP then
                        table.insert(rxpGuides, name)
                    end
                else
                    if self.db.char.filterZone then
                        table.insert(zoneGuides, name)
                    end
                end
            end
        end
    end

    table.sort(turtleGuides, SortGuidesByLevel)
    table.sort(optimizedGuides, SortGuidesByLevel)
    table.sort(rxpGuides, SortGuidesByLevel)
    table.sort(zoneGuides, SortGuidesByLevel)

    if table.getn(turtleGuides) > 0 then
        table.insert(displayList, { header = true, text = "--- TurtleWoW Zones ---" })
        for _, name in ipairs(turtleGuides) do
            table.insert(displayList, { guide = name })
        end
    end

    if table.getn(optimizedGuides) > 0 then
        table.insert(displayList, { header = true, text = "--- Optimized Guides ---" })
        for _, name in ipairs(optimizedGuides) do
            table.insert(displayList, { guide = name })
        end
    end

    if table.getn(rxpGuides) > 0 then
        table.insert(displayList, { header = true, text = "--- RXP Guides ---" })
        for _, name in ipairs(rxpGuides) do
            table.insert(displayList, { guide = name })
        end
    end

    if table.getn(zoneGuides) > 0 then
        table.insert(displayList, { header = true, text = "--- Zone Guides ---" })
        for _, name in ipairs(zoneGuides) do
            table.insert(displayList, { guide = name })
        end
    end

    -- Clamp offset and update slider
    local maxOffset = math.max(0, table.getn(displayList) - TOTALROWS)
    if offset > maxOffset then offset = maxOffset end
    if offset < 0 then offset = 0 end

    if maxOffset > 0 then
        slider:Show()
        slider.updating = true
        slider:SetMinMaxValues(0, maxOffset)
        slider:SetValue(offset)
        slider.updating = false
    else
        slider:Hide()
    end

    -- Update rows (never hide — just clear text for unused slots, matching original pattern)
    for i, row in ipairs(rows) do
        local entry = displayList[i + offset]
        if entry and entry.header then
            row.text:SetText("|cffffd100" .. entry.text .. "|r")
            row.guide = nil
            row:SetChecked(false)
            row:Enable()
        elseif entry and entry.guide then
            row:Enable()
            local name = entry.guide
            row.guide = name

            -- Color by level range: green = in range, yellow = +-5, red = out of range
            local minLevel, maxLevel = self:ParseGuideLevelRange(name)
            local colorCode
            if minLevel and maxLevel then
                if playerLevel >= minLevel and playerLevel <= maxLevel then
                    colorCode = "|cff00ff00" -- green: in range
                elseif playerLevel >= (minLevel - 5) and playerLevel <= (maxLevel + 5) then
                    colorCode = "|cffffff00" -- yellow: within 5 levels
                else
                    colorCode = "|cffff4444" -- red: out of range
                end
            else
                colorCode = "|cffcccccc" -- gray: no level info
            end

            -- Completion percentage
            local complete
            if self.db.char.currentguide == name and self.current and self.actions then
                complete = (self.current - 1) / table.getn(self.actions)
            else
                complete = self.db.char.completion[name]
            end

            local text
            if complete and complete ~= 0 then
                local pct = math.floor(complete * 100)
                text = string.format("%s%s (%d%%)|r", colorCode, name, pct)
            else
                text = colorCode .. name .. "|r"
            end

            if self.db.char.isbranching and self.db.char.branchsavedguide == name then
                text = "|cff00ff00[Main]|r " .. text
            end

            row.text:SetText(text)
            row:SetChecked(self.db.char.currentguide == name)
        else
            row.guide = nil
            row.text:SetText("")
            row:SetChecked(false)
            row:Enable()
        end
    end
end
