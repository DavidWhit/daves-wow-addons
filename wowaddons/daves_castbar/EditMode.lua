-- daves_castbar / EditMode.lua
-- Moving, sizing and setting up the bar in Blizzard's Edit Mode (or any time when unlocked).
--   drag the bar            move it; snaps to Edit Mode's grid when "Snap" is ticked (Shift: place freely)
--   drag the corner grip    resize it; the right and bottom edges snap to the grid too
--   click                   the bar's settings: size, scale, style, text, a preview of each element
--   right-click             reset position and size
-- While Edit Mode is open the bar plays pretend casts so its look can be judged in place.
--
-- EventRegistry "EditMode.Enter"/"EditMode.Exit", EditModeManagerFrameMixin:IsSnapEnabled and the
-- grid (EditModeGridMixin:UpdateGrid draws lines every Grid.gridSpacing out from the Grid frame's
-- centre) are in Blizzard_EditMode/Shared/EditModeManager.lua, forever branch.

local _, ns = ...

local bar, selection, grip, dialog

---------------------------------------------------------------------------
-- Grid snapping (screen pixels)
---------------------------------------------------------------------------
local function GridSnapInfo()
	local manager = EditModeManagerFrame
	if not (ns.inEditMode and manager and manager.IsSnapEnabled and manager:IsSnapEnabled()) then return end
	local grid = manager.Grid
	if not (grid and grid:IsShown() and grid.gridSpacing) then return end
	local gx, gy = grid:GetCenter()
	if not gx then return end
	local scale = grid:GetEffectiveScale()
	return gx * scale, gy * scale, grid.gridSpacing * scale
end

local function SnapLine(p, gridCenter, spacing)
	return gridCenter + math.floor((p - gridCenter) / spacing + .5) * spacing
end

-- Snap the centre or either edge to the nearest grid line, whichever is closer.
local function SnapAxis(center, half, gridCenter, spacing)
	local best
	for _, p in ipairs({ center, center - half, center + half }) do
		local delta = SnapLine(p, gridCenter, spacing) - p
		if not best or math.abs(delta) < math.abs(best) then best = delta end
	end
	return center + best
end

-- Screen edges: within EDGE_SNAP pixels the bar sits flush against the edge.
local EDGE_SNAP = 12
local function SnapToEdge(center, half, size)
	if math.abs(center - half) <= EDGE_SNAP then return half end
	if math.abs(size - (center + half)) <= EDGE_SNAP then return size - half end
end

local function DragUpdate()
	local scale = bar:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local x, y = cx - bar.grabX, cy - bar.grabY
	if not IsShiftKeyDown() then
		local w, h = ns:BarSize()
		local hw, hh = w * scale / 2, h * scale / 2
		local gx, gy, spacing = GridSnapInfo()
		if gx then x, y = SnapAxis(x, hw, gx, spacing), SnapAxis(y, hh, gy, spacing) end
		local uiScale = UIParent:GetEffectiveScale()
		x = SnapToEdge(cx - bar.grabX, hw, UIParent:GetWidth() * uiScale) or x
		y = SnapToEdge(cy - bar.grabY, hh, UIParent:GetHeight() * uiScale) or y
	end
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

-- Resizing keeps the top-left corner where it is.
local MIN_W, MAX_W, MIN_H, MAX_H = 80, 800, 10, 80
local function ResizeUpdate()
	local scale = bar:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local right, bottom = cx - grip.offX, cy - grip.offY      -- where the bar's bottom-right corner should go
	if not IsShiftKeyDown() then
		local gx, gy, spacing = GridSnapInfo()
		if gx then right, bottom = SnapLine(right, gx, spacing), SnapLine(bottom, gy, spacing) end
	end
	local w = math.max(MIN_W, math.min(MAX_W, (right - grip.left) / scale))
	local h = math.max(MIN_H, math.min(MAX_H, (grip.top - bottom) / scale))
	ns.db.width, ns.db.height = math.floor(w + .5), math.floor(h + .5)
	ns:Layout()
	if dialog and dialog:IsShown() then dialog:Refresh() end
end

---------------------------------------------------------------------------
-- Settings dialog
---------------------------------------------------------------------------
local function Slider(parent, label, y, min, max, step, fmt, get, set)
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", 20, y)
	text:SetText(label)
	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("TOPLEFT", 100, y + 6)
	slider:SetSize(190, 20)
	local formatters = {
		[MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmt:format(v) end),
	}
	slider:Init(get(), min, max, (max - min) / step, formatters)
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if parent.refreshing then return end
		set(value)
	end, parent)
	slider.get = get
	return slider
end

local function Check(parent, label, x, y, key, tooltip)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetPoint("TOPLEFT", x, y)
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 2, 0)
	text:SetText(label)
	check:SetScript("OnClick", function(self)
		ns.db[key] = self:GetChecked() and true or false
		ns:Apply()
	end)
	if tooltip then
		check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(label)
			GameTooltip:AddLine(tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	check.key = key
	return check
end

local function CreateDialog()
	dialog = CreateFrame("Frame", "DavesCastbarSettings", UIParent, "DefaultPanelTemplate")
	dialog:SetSize(320, 380)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetMovable(true)
	dialog:EnableMouse(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	dialog:SetClampedToScreen(true)
	table.insert(UISpecialFrames, dialog:GetName())   -- Escape closes it
	if dialog.TitleContainer and dialog.TitleContainer.TitleText then
		dialog.TitleContainer.TitleText:SetText("Dave's Cast Bar")
	end
	local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 0)

	local function SetAndLayout(key)
		return function(v) ns.db[key] = v; ns:Layout() end
	end
	dialog.sliders = {
		Slider(dialog, "Width", -40, MIN_W, MAX_W, 2, "%d", function() return ns.db.width end, SetAndLayout("width")),
		Slider(dialog, "Height", -72, MIN_H, MAX_H, 1, "%d", function() return ns.db.height end, SetAndLayout("height")),
		Slider(dialog, "Scale", -104, .5, 2, .05, "%.2f", function() return ns.db.scale end, SetAndLayout("scale")),
	}
	dialog.checks = {
		Check(dialog, "Borderless (soft edges)", 14, -134, "borderless", "On: the bar's edges fade out raggedly. Off: a thin frame in the element's colour."),
		Check(dialog, "Show spell name", 14, -160, "showName"),
		Check(dialog, "Show time left", 14, -186, "showTime"),
		Check(dialog, "Show spell icon", 14, -212, "showIcon"),
		Check(dialog, "Hide Blizzard's cast bar", 14, -238, "hideBlizzard"),
	}

	-- preview buttons: loop one element, or all of them in turn
	local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", 20, -272)
	label:SetText("Preview")
	local keys = { "all" }
	for _, k in ipairs(ns.ELEMENT_ORDER) do keys[#keys + 1] = k end
	dialog.previewButtons = {}
	for i, key in ipairs(keys) do
		local b = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
		b:SetSize(66, 20)
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		b:SetPoint("TOPLEFT", 20 + col * 70, -290 - row * 24)
		b:SetText(key == "all" and "All" or ns.ELEMENTS[key].label)
		b:SetScript("OnClick", function()
			ns.editPreview = key ~= "all" and key or nil
			ns:TestCast(ns.editPreview, ns.inEditMode)
			dialog:Refresh()
		end)
		b.key = key
		dialog.previewButtons[i] = b
	end

	local reset = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	reset:SetSize(280, 22)
	reset:SetPoint("BOTTOM", 0, 16)
	reset:SetText("Reset position and size")
	reset:SetScript("OnClick", function() ns:ResetPosition(); dialog:Refresh() end)

	function dialog:Refresh()
		self.refreshing = true
		for _, s in ipairs(self.sliders) do s:SetValue(s.get()) end
		for _, c in ipairs(self.checks) do c:SetChecked(ns.db[c.key]) end
		for _, b in ipairs(self.previewButtons) do
			local on = (b.key == "all" and not ns.editPreview) or b.key == ns.editPreview
			b:SetAlpha(on and 1 or .75)
		end
		self.refreshing = nil
	end
end

function ns:OpenBarSettings()
	if not dialog then CreateDialog() end
	dialog:ClearAllPoints()
	-- open above or below the bar, on whichever side has more room
	local _, y = bar:GetCenter()
	if y and y * bar:GetEffectiveScale() > UIParent:GetHeight() * UIParent:GetEffectiveScale() / 2 then
		dialog:SetPoint("TOP", bar, "BOTTOM", 0, -12)
	else
		dialog:SetPoint("BOTTOM", bar, "TOP", 0, 24)
	end
	dialog:Refresh()
	dialog:Show()
end

---------------------------------------------------------------------------
-- Edit Mode state
---------------------------------------------------------------------------
function ns:CanMoveBar()
	return ns.inEditMode or not ns.db.locked
end

function ns:ApplyEditState()
	if not selection then return end
	local movable = ns:CanMoveBar()
	selection:SetShown(movable)
	grip:SetShown(movable)
	bar:EnableMouse(movable)
	if movable then bar:RegisterForDrag("LeftButton") else bar:RegisterForDrag() end
	if not movable and dialog then dialog:Hide() end
end

local function SetEditMode(active)
	ns.inEditMode = active
	ns:ApplyEditState()
	if active then
		if not ns:IsCasting() then ns:TestCast(ns.editPreview, true) end
	else
		ns:StopTest()
		GameTooltip:Hide()
	end
	ns:UpdateVisibility()
end

function ns.InitEditMode()   -- (a plain function: the handlers below have their own 'self')
	bar = ns.bar

	-- overlay shown while the bar can be moved
	selection = CreateFrame("Frame", nil, bar)
	selection:SetPoint("TOPLEFT", -3, 3)
	selection:SetPoint("BOTTOMRIGHT", 3, -3)
	selection:SetFrameLevel(bar:GetFrameLevel() + 20)
	local tint = selection:CreateTexture(nil, "OVERLAY")
	tint:SetAllPoints()
	tint:SetColorTexture(.25, .6, 1, .22)
	local name = selection:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	name:SetPoint("BOTTOM", selection, "TOP", 0, 2)
	name:SetText("Dave's Cast Bar")
	selection:Hide()

	grip = CreateFrame("Button", nil, bar)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", 4, -4)
	grip:SetFrameLevel(bar:GetFrameLevel() + 21)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:Hide()
	grip:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		local scale = bar:GetEffectiveScale()
		local left, top = bar:GetLeft() * scale, bar:GetTop() * scale
		-- keep the top-left corner fixed while resizing
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
		local cx, cy = GetCursorPosition()
		self.left, self.top = left, top
		self.offX, self.offY = cx - bar:GetRight() * scale, cy - bar:GetBottom() * scale
		self.resizing = true
		self:SetScript("OnUpdate", ResizeUpdate)
	end)
	grip:SetScript("OnMouseUp", function(self)
		if not self.resizing then return end
		self.resizing = nil
		self:SetScript("OnUpdate", nil)
		-- store the position by the centre again (GetCenter is in the bar's own scale, as SetPoint wants)
		local x, y = bar:GetCenter()
		bar:ClearAllPoints()
		bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
		ns:SavePosition()
	end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Resize")
		GameTooltip:AddLine("Drag to change the bar's width and height. Hold Shift to ignore the grid.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

	bar:SetScript("OnDragStart", function(self)
		local scale = self:GetEffectiveScale()
		local ox, oy = self:GetCenter()
		local cx, cy = GetCursorPosition()
		self.grabX, self.grabY = cx - ox * scale, cy - oy * scale
		self.dragged = true
		self:SetScript("OnUpdate", function(_, elapsed) DragUpdate(); ns:OnBarUpdate(elapsed) end)
	end)
	bar:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", function(_, elapsed) ns:OnBarUpdate(elapsed) end)
		ns:SavePosition()
	end)
	bar:SetScript("OnMouseUp", function(self, button)
		if not ns:CanMoveBar() then return end
		if self.dragged then
			self.dragged = nil
		elseif button == "LeftButton" then
			ns:OpenBarSettings()
		elseif button == "RightButton" then
			ns:ResetPosition()
			if dialog and dialog:IsShown() then dialog:Refresh() end
		end
	end)
	bar:SetScript("OnEnter", function(self)
		if not ns:CanMoveBar() then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Dave's Cast Bar")
		GameTooltip:AddLine("Click for settings. Drag to move (snaps to the Edit Mode grid; hold Shift to place freely). Drag the corner to resize. Right-click to reset.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Enter", function() SetEditMode(true) end, ns)
		EventRegistry:RegisterCallback("EditMode.Exit", function() SetEditMode(false) end, ns)
	end
end
