
local TurtleGuide = TurtleGuide
local L = TurtleGuide.Locale
local ww = WidgetWarlock


local ROWHEIGHT = 30
local ROWOFFSET = 6
local HEADER_HEIGHT = 55
local DEFAULT_WIDTH = 630
local DEFAULT_HEIGHT = 305 + 28
local MIN_WIDTH = 400
local MIN_HEIGHT = 200
local MAX_ROWS = 30
local NUMROWS = math.floor((305 - HEADER_HEIGHT) / ROWHEIGHT)


local offset = 0
local rows = {}
local scrollbar, upbutt, downbutt, title, completed


local frame = CreateFrame("Frame", "TurtleGuideObjectives", UIParent)
TurtleGuide.objectiveframe = frame
frame:SetFrameStrata("DIALOG")
frame:SetWidth(DEFAULT_WIDTH)
frame:SetHeight(DEFAULT_HEIGHT)
frame:SetPoint("TOPRIGHT", TurtleGuide.statusframe, "BOTTOMRIGHT")
frame:SetBackdrop(ww.TooltipBorderBG)
frame:SetBackdropColor(0.09, 0.09, 0.19, 1)
frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.5)
frame:Hide()
frame:SetScript("OnShow", function() TurtleGuide:UpdateObjectivePanel() end)
table.insert(UISpecialFrames, "TurtleGuideObjectives")

-- Make frame resizable
frame:SetResizable(true)
frame:SetMinResize(MIN_WIDTH, MIN_HEIGHT)
frame:SetMaxResize(1200, 800)

-- Resize grip in bottom-right corner
local grip = CreateFrame("Frame", nil, frame)
grip:SetWidth(16)
grip:SetHeight(16)
grip:SetPoint("BOTTOMRIGHT", -2, 2)
grip:EnableMouse(true)
grip:SetFrameLevel(frame:GetFrameLevel() + 2)

local gripTex = grip:CreateTexture(nil, "OVERLAY")
gripTex:SetAllPoints(grip)
gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

grip:SetScript("OnEnter", function()
	gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
end)
grip:SetScript("OnLeave", function()
	gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
end)
grip:SetScript("OnMouseDown", function()
	gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	frame:StartSizing("BOTTOMRIGHT")
end)
grip:SetScript("OnMouseUp", function()
	gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	frame:StopMovingOrSizing()
	TurtleGuide:OnObjectiveFrameResized()
end)

frame:SetScript("OnSizeChanged", function()
	if rows and rows[1] then
		TurtleGuide:OnObjectiveFrameResized()
	end
end)


local function ResetScrollbar()
	local f = this
	local newval = math.max(0, (TurtleGuide.current or 0) - NUMROWS / 2 - 1)

	scrollbar:SetMinMaxValues(0, math.max(table.getn(TurtleGuide.actions) - NUMROWS, 1))
	scrollbar:SetValue(newval)

	TurtleGuide:UpdateOHPanel()
end

local function OnShow(f)
	local f = f or this
	ResetScrollbar()
	f:SetAlpha(0)
	f:SetScript("OnUpdate", ww.FadeIn)

	if TurtleGuide.optionsframe:IsVisible() then HideUIPanel(TurtleGuide.optionsframe) end
	if TurtleGuide.guidelistframe:IsVisible() then HideUIPanel(TurtleGuide.guidelistframe) end
end


local function HideTooltip()
	if GameTooltip:IsOwned(this) then
		GameTooltip:Hide()
	end
end

local function ShowTooltip()
	local f = this
	if f.text:GetStringWidth() <= f:GetWidth() then return end

	GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
	GameTooltip:SetText(f.text:GetText(), nil, nil, nil, nil, true)
end

local function CreateButton(parent, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20)
	local b = CreateFrame("Button", nil, parent)
	if TurtleGuide.select("#", a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20) > 0 then b:SetPoint(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20) end
	b:SetWidth(80)
	b:SetHeight(22)

	-- Fonts --
	b:SetDisabledFontObject(GameFontDisable)
	b:SetHighlightFontObject(GameFontHighlight)
	b:SetTextFontObject(GameFontNormal)

	-- Textures --
	b:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
	b:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
	b:SetDisabledTexture("Interface\\Buttons\\UI-Panel-Button-Disabled")
	b:GetNormalTexture():SetTexCoord(0, 0.625, 0, 0.6875)
	b:GetPushedTexture():SetTexCoord(0, 0.625, 0, 0.6875)
	b:GetHighlightTexture():SetTexCoord(0, 0.625, 0, 0.6875)
	b:GetDisabledTexture():SetTexCoord(0, 0.625, 0, 0.6875)
	b:GetHighlightTexture():SetBlendMode("ADD")

	return b
end


function TurtleGuide:UpdateObjectivePanel()
	frame:SetScript("OnShow", nil)
	local guidebutton = CreateButton(frame, "BOTTOMRIGHT", -6, 6)
	guidebutton:SetText("Guides")
	guidebutton:SetScript("OnClick", function() frame:Hide(); TurtleGuide.guidelistframe:Show() end)

	local configbutton = CreateButton(frame, "RIGHT", guidebutton, "LEFT")
	configbutton:SetText(L["Config"])
	configbutton:SetScript("OnClick", function() frame:Hide(); TurtleGuide.optionsframe:Show() end)

	local routebutton = CreateButton(frame, "RIGHT", configbutton, "LEFT")
	routebutton:SetText("Route")
	routebutton:SetScript("OnClick", function() frame:Hide(); TurtleGuide:ShowRouteSelector() end)

	-- Return to Main button (only visible when branching)
	local returnbutton = CreateButton(frame, "RIGHT", routebutton, "LEFT")
	returnbutton:SetWidth(100)
	returnbutton:SetText("Return Main")
	returnbutton:SetScript("OnClick", function() TurtleGuide:ReturnFromBranch() end)
	returnbutton:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_TOP")
		if TurtleGuide.db.char.branchsavedguide then
			GameTooltip:SetText("Return to: " .. TurtleGuide.db.char.branchsavedguide)
		else
			GameTooltip:SetText("Return to main route")
		end
	end)
	returnbutton:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame.returnbutton = returnbutton

	if TurtleGuide.db.char.debug then
		local b = CreateButton(frame, "RIGHT", returnbutton, "LEFT")
		b:SetText("Debug All")
		b:SetScript("OnClick", function() frame:Hide(); self:DebugGuideSequence(true) end)
	end

	title = ww.SummonFontString(frame, nil, "SubZoneTextFont", nil, "BOTTOM", frame, "TOP")
	local fontname, fontheight, fontflags = title:GetFont()
	title:SetFont(fontname, 18, fontflags)

	-- Current objective header (prominent display)
	local currentHeader = CreateFrame("Frame", nil, frame)
	currentHeader:SetHeight(50)
	currentHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
	currentHeader:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, -6)
	currentHeader:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background"})
	currentHeader:SetBackdropColor(0.2, 0.4, 0.6, 0.8)

	local currentIcon = ww.SummonTexture(currentHeader, nil, 36, 36, nil, "LEFT", currentHeader, "LEFT", 8, 0)
	local currentText = ww.SummonFontString(currentHeader, nil, "GameFontNormalLarge", nil, "LEFT", currentIcon, "RIGHT", 8, 6)
	local currentNote = ww.SummonFontString(currentHeader, nil, "GameFontNormalSmall", nil, "TOPLEFT", currentText, "BOTTOMLEFT", 0, -2)
	currentNote:SetTextColor(0.9, 0.7, 0.2)

	-- Navigation buttons in header
	local prevHeaderBtn = CreateButton(currentHeader, "RIGHT", currentHeader, "RIGHT", -90, 0)
	prevHeaderBtn:SetWidth(32) prevHeaderBtn:SetText("<")
	prevHeaderBtn:SetScript("OnClick", function() TurtleGuide:GoToPreviousObjective() end)
	prevHeaderBtn:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_TOP")
		GameTooltip:SetText("Previous objective")
	end)
	prevHeaderBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local nextHeaderBtn = CreateButton(currentHeader, "LEFT", prevHeaderBtn, "RIGHT", 2, 0)
	nextHeaderBtn:SetWidth(32) nextHeaderBtn:SetText(">")
	nextHeaderBtn:SetScript("OnClick", function() TurtleGuide:SkipToNextObjective() end)
	nextHeaderBtn:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_TOP")
		GameTooltip:SetText("Skip to next objective")
	end)
	nextHeaderBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local skipHeaderBtn = CreateButton(currentHeader, "LEFT", nextHeaderBtn, "RIGHT", 2, 0)
	skipHeaderBtn:SetWidth(32) skipHeaderBtn:SetText(">>")
	skipHeaderBtn:SetScript("OnClick", function() TurtleGuide:SetTurnedIn(); TurtleGuide:UpdateStatusFrame() end)
	skipHeaderBtn:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_TOP")
		GameTooltip:SetText("Mark complete and advance")
	end)
	skipHeaderBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	frame.currentHeader = currentHeader
	frame.currentIcon = currentIcon
	frame.currentText = currentText
	frame.currentNote = currentNote

	completed = ww.SummonFontString(frame, nil, "NumberFontNormalLarge", nil, "BOTTOMLEFT", 10, 10)

	scrollbar, upbutt, downbutt = ww.ConjureScrollBar(frame)
	scrollbar:SetPoint("TOPRIGHT", frame, -7, -21)
	scrollbar:SetPoint("BOTTOM", frame, 0, 22 + 22)
	scrollbar:SetScript("OnValueChanged", function() local f, val = this, arg1 self:UpdateOHPanel(val) end)

	upbutt:SetScript("OnClick", function()
		local f = this
		scrollbar:SetValue(offset - NUMROWS + 1)
		PlaySound("UChatScrollButton")
	end)

	downbutt:SetScript("OnClick", function()
		local f = this
		scrollbar:SetValue(offset + NUMROWS - 1)
		PlaySound("UChatScrollButton")
	end)

	local bg = {bgFile = "Interface/Tooltips/UI-Tooltip-Background"}
	for i = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetPoint("TOPLEFT", i == 1 and frame or rows[i - 1], i == 1 and "TOPLEFT" or "BOTTOMLEFT", 0, i == 1 and -58 or 0)
		row:SetPoint("RIGHT", scrollbar, "LEFT", -4, 0)
		row:SetHeight(ROWHEIGHT)
		row:SetBackdrop(bg)

		local check = ww.SummonCheckBox(ROWHEIGHT - ROWOFFSET, row, "LEFT", ROWOFFSET, 0)
		local icon = ww.SummonTexture(row, nil, ROWHEIGHT - ROWOFFSET, ROWHEIGHT - ROWOFFSET, nil, "LEFT", check, "RIGHT", ROWOFFSET, 0)
		local text = ww.SummonFontString(row, nil, "GameFontNormal", nil, "LEFT", icon, "RIGHT", ROWOFFSET, 0)

		local detailhover = CreateFrame("Button", nil, row)
		detailhover:SetHeight(ROWHEIGHT - ROWOFFSET)
		detailhover:SetPoint("LEFT", text, "RIGHT", ROWOFFSET * 3, 0)
		detailhover:SetPoint("RIGHT", scrollbar, "LEFT", -ROWOFFSET, 0)
		detailhover:SetScript("OnEnter", ShowTooltip)
		detailhover:SetScript("OnLeave", HideTooltip)

		local detail = ww.SummonFontString(detailhover, nil, "GameFontNormal", nil)
		detail:SetAllPoints(detailhover)
		detail:SetJustifyH("RIGHT")
		detail:SetTextColor(240 / 255, 121 / 255, 2 / 255)
		detailhover.text = detail

		check:SetScript("OnClick", function()
			local f = this
			self:SetTurnedIn(row.i, f:GetChecked())
		end)

		row:SetScript("OnClick", function()
			TurtleGuide:GoToObjective(row.i)
		end)

		detailhover:SetScript("OnClick", function()
			TurtleGuide:GoToObjective(row.i)
		end)

		row.text = text
		row.detail = detail
		row.check = check
		row.icon = icon
		rows[i] = row
	end

	frame:EnableMouseWheel()
	frame:SetScript("OnMouseWheel", function()
		local f, val = this, arg1
		scrollbar:SetValue(offset - val)
	end)

	-- Restore saved size
	if self.db.profile.objframewidth then
		frame:SetWidth(self.db.profile.objframewidth)
	end
	if self.db.profile.objframeheight then
		frame:SetHeight(self.db.profile.objframeheight)
	end

	self:OnObjectiveFrameResized()

	frame:SetScript("OnShow", OnShow)
	ww.SetFadeTime(frame, 0.5)
	OnShow(frame)
	return frame
end


function TurtleGuide:OnObjectiveFrameResized()
	local w = frame:GetWidth()
	local h = frame:GetHeight()

	-- Save dimensions
	self.db.profile.objframewidth = w
	self.db.profile.objframeheight = h

	-- Recalculate visible rows
	local contentHeight = h - 28 - HEADER_HEIGHT  -- 28 for bottom buttons area
	NUMROWS = math.max(1, math.floor(contentHeight / ROWHEIGHT))
	if NUMROWS > MAX_ROWS then NUMROWS = MAX_ROWS end

	-- Show/hide rows based on new count
	for i, row in ipairs(rows) do
		if i > NUMROWS then
			row:Hide()
		end
	end

	-- Update scrollbar range
	if scrollbar and self.actions then
		scrollbar:SetMinMaxValues(0, math.max(table.getn(self.actions) - NUMROWS, 1))
	end

	-- Refresh display
	if frame:IsVisible() and self.current then
		self:UpdateOHPanel()
	end
end


local accepted = {}
local acceptedDirty = true
function TurtleGuide:UpdateOHPanel(value)
	if not frame or not frame:IsVisible() then return end

	-- Update title with branch indicator
	local guideName = self.db.char.currentguide or L["No Guide Loaded"]
	if self.db.char.isbranching then
		title:SetText("|cff00ff00[Branch]|r " .. guideName)
	else
		title:SetText(guideName)
	end

	-- Show/hide return button based on branch status
	if frame.returnbutton then
		if self.db.char.isbranching then
			frame.returnbutton:Show()
			frame.returnbutton:Enable()
		else
			frame.returnbutton:Hide()
		end
	end

	local r, g, b = self.ColorGradient((self.current - 1) / table.getn(self.actions))
	completed:SetText(string.format(L["|cff%02x%02x%02x%d%% complete"], r * 255, g * 255, b * 255, (self.current - 1) / table.getn(self.actions) * 100))

	if self.guidechanged then
		self.guidechanged = nil
		acceptedDirty = true
		ResetScrollbar()
	end

	if value then offset = math.floor(value) end
	if (offset + NUMROWS) > table.getn(self.actions) then offset = table.getn(self.actions) - NUMROWS end
	if offset < 0 then offset = 0 end

	if offset == 0 then upbutt:Disable() else upbutt:Enable() end
	if offset == (table.getn(self.actions) - NUMROWS) then downbutt:Disable() else downbutt:Enable() end

	if not value or acceptedDirty then
		for i in pairs(accepted) do accepted[i] = nil end

		if self.actions then
			for i in pairs(self.actions) do
				local action, name = self:GetObjectiveInfo(i)
				local _, _, quest = string.find(name, L.PART_FIND)
				local _, _, part = string.find(name, ".*%(Part (%d+)%)")
				if quest and not accepted[quest] and not self:GetObjectiveStatus(i) then accepted[quest] = name end
			end
		end
		acceptedDirty = false
	end

	for i, row in ipairs(rows) do
		if i > NUMROWS then row:Hide()
		else
		row.i = i + offset
		local idx = i + offset
		local action, name = self:GetObjectiveInfo(idx)
		if not name then row:Hide()
		else
			local turnedin, logi, complete = self:GetObjectiveStatus(idx)
			local optional, intown = self:GetObjectiveTag("O", idx), self:GetObjectiveTag("T", idx)
			local isActive = (idx == self.current)
			row:Show()

			-- Visual hierarchy based on status
			local shortname = string.gsub(name, L.PART_GSUB, "")
			logi = not turnedin and (not accepted[shortname] or (accepted[shortname] == name)) and logi
			complete = not turnedin and (not accepted[shortname] or (accepted[shortname] == name)) and complete
			local checked = turnedin or action == "ACCEPT" and logi or action == "COMPLETE" and complete

			if isActive then
				-- ACTIVE: Bright highlight
				row:SetBackdropColor(0.2, 0.4, 0.6, 0.7)
				row.text:SetTextColor(1, 1, 1)
			elseif checked then
				-- COMPLETED: Dimmed
				row:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
				row.text:SetTextColor(0.5, 0.5, 0.5)
			elseif intown then
				-- IN-TOWN: Green tint
				row:SetBackdropColor(0, 0.3, 0, 0.4)
				row.text:SetTextColor(0.8, 1, 0.8)
			else
				-- UPCOMING: Normal
				row:SetBackdropColor(0, 0, 0, 0)
				row.text:SetTextColor(1, 0.82, 0)
			end

			-- Show quest progress for COMPLETE objectives
			local progressText = ""
			if action == "COMPLETE" and logi and not complete then
				local numObj = GetNumQuestLeaderBoards(logi)
				for j = 1, numObj do
					local text = GetQuestLogLeaderBoard(j, logi)
					if text then progressText = text break end
				end
			end

			row.icon:SetTexture(self.icons[action])
			if action ~= "ACCEPT" and action ~= "TURNIN" then row.icon:SetTexCoord(4 / 48, 44 / 48, 4 / 48, 44 / 48) end
			row.text:SetText(string.format("[%d] %s", idx, name) .. (optional and L[" |cff808080(Optional)"] or ""))
			row.detail:SetText(progressText ~= "" and progressText or self:GetObjectiveTag("N", idx))
			row.check:SetChecked(checked)

			if (TurtleGuide.current > idx) and optional and not checked then
				row.text:SetTextColor(0.5, 0.5, 0.5)
				row.check:Disable()
			elseif not isActive and not checked then
				row.check:Enable()
			else
				row.check:Enable()
			end

			if self.db.char.currentguide == "No Guide" then row.check:Disable() end
		end
		end -- i > NUMROWS
	end

	-- Update current objective header
	if frame.currentIcon and self.current then
		local action, name = self:GetObjectiveInfo(self.current)
		local note = self:GetObjectiveTag("N", self.current)
		frame.currentIcon:SetTexture(self.icons[action])
		if action ~= "ACCEPT" and action ~= "TURNIN" then
			frame.currentIcon:SetTexCoord(4 / 48, 44 / 48, 4 / 48, 44 / 48)
		else
			frame.currentIcon:SetTexCoord(0, 1, 0, 1)
		end
		frame.currentText:SetText(string.format("[%d/%d] %s: %s", self.current, table.getn(self.actions), action, name or "???"))
		frame.currentNote:SetText(note or "")
	end
end
