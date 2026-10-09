-- daves_castbar / EditMode.lua
-- Moving, sizing and setting up the bar in Blizzard's Edit Mode (or any time when unlocked).
--   drag the bar            move it; with "Snap" ticked it pulls onto grid lines, the screen edges and
--                           centre, and Edit Mode frames beside it, like Blizzard's own (Shift: place freely)
--   drag the corner grip    resize it; the right and bottom edges snap the same way
--   click                   the bar's settings (the kit's shared Edit Mode dialog, EditModeDialog.lua):
--                           size, scale, style, corners, depth, text, a preview of each element
--   right-click             reset position and size
-- While Edit Mode is open the bar plays pretend casts so its look can be judged in place.
--
-- EventRegistry "EditMode.Enter"/"EditMode.Exit" are in Blizzard_EditMode/Shared/EditModeManager.lua,
-- forever branch. Snapping and the settings dialog come from the kit's EditModeDialog.lua.

local _, ns = ...

local bar, selection, grip, dialog

local function RefreshDialog()
	if dialog and dialog:IsShown() then dialog:Refresh() end
end

---------------------------------------------------------------------------
-- Moving and resizing. Snapping is the kit's (EditModeDialog.lua): magnetic, like Blizzard's
-- own frames, to grid lines, screen edges and centre, and Edit Mode frames beside the bar.
---------------------------------------------------------------------------
local function DragUpdate()
	local scale, ui = bar:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local x, y = (cx - bar.grabX) / ui, (cy - bar.grabY) / ui       -- the bar's centre, UIParent units
	if not IsShiftKeyDown() then
		local w, h = ns:BarSize()
		w, h = w * scale / ui, h * scale / ui
		local left, bottom = ns.EditMode.SnapRect(bar, x - w / 2, y - h / 2, w, h)
		x, y = left + w / 2, bottom + h / 2
	end
	bar:ClearAllPoints()
	bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * ui / scale, y * ui / scale)
end

-- Resizing keeps the top-left corner where it is.
local MIN_W, MAX_W, MIN_H, MAX_H = ns.MIN_W, ns.MAX_W, ns.MIN_H, ns.MAX_H
local function ResizeUpdate()
	local scale, ui = bar:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local right, bottom = (cx - grip.offX) / ui, (cy - grip.offY) / ui   -- where the bottom-right corner goes
	if not IsShiftKeyDown() then
		right, bottom = ns.EditMode.SnapEdge(right, true), ns.EditMode.SnapEdge(bottom, false)
	end
	local w = math.max(MIN_W, math.min(MAX_W, (right * ui - grip.left) / scale))
	local h = math.max(MIN_H, math.min(MAX_H, (grip.top - bottom * ui) / scale))
	ns.db.width, ns.db.height = math.floor(w + .5), math.floor(h + .5)
	ns:Layout()
	if dialog and dialog:IsShown() then dialog:RefreshValues() end   -- the full refresh waits for mouse-up
end

---------------------------------------------------------------------------
-- Settings dialog: the kit's shared Edit Mode dialog (EditModeDialog.lua)
---------------------------------------------------------------------------
local function CreateDialog()
	dialog = ns.EditMode.CreateDialog("DavesCastbarSettings", "Dave's Cast Bar")
	local db = ns.db
	local function Number(key) return function() return db[key] end end
	local function SetAndLayout(key) return function(v) db[key] = v; ns:Layout() end end
	local function Flag(key) return function() return db[key] end end
	local function SetFlag(key) return function(v) db[key] = v; ns:Apply() end end

	dialog:AddSlider({ label = "Width", min = MIN_W, max = MAX_W, step = 1, format = "%d", get = Number("width"), set = SetAndLayout("width") })
	dialog:AddSlider({ label = "Height", min = MIN_H, max = MAX_H, step = 1, format = "%d", get = Number("height"), set = SetAndLayout("height") })
	dialog:AddSlider({ label = "Scale", min = .5, max = 2, step = .05, format = "%.2f", get = Number("scale"), set = SetAndLayout("scale") })
	dialog:AddButtonGrid({ label = "Style", columns = 2,
		buttons = { { key = "framed", text = "Framed" }, { key = "borderless", text = "Borderless" } },
		onClick = function(key) db.style = key; ns:Layout() end,
		isActive = function(key) return (db.style or "framed") == key end })
	dialog:AddButtonGrid({ label = "Corners", columns = 3,
		buttons = { { key = "square", text = "Square" }, { key = "soft", text = "Soft" }, { key = "rounded", text = "Rounded" } },
		onClick = function(key) db.corners = key; ns:Layout() end,
		isActive = function(key) return (db.corners or "soft") == key end })
	dialog:AddButtonGrid({ label = "Depth", columns = 2,
		buttons = { { key = "flat", text = "Flat" }, { key = "bevel", text = "Bevel" } },
		onClick = function(key) db.depth = key; ns:Layout() end,
		isActive = function(key) return (db.depth or "flat") == key end })
	dialog:AddCheckbox({ label = "Show spell name", get = Flag("showName"), set = SetFlag("showName") })
	dialog:AddCheckbox({ label = "Show time left", get = Flag("showTime"), set = SetFlag("showTime") })
	dialog:AddCheckbox({ label = "Show spell icon", get = Flag("showIcon"), set = SetFlag("showIcon") })
	dialog:AddSlider({ label = "Text size", min = .6, max = 2, step = .05,
		format = function(v) return ("%d%%"):format(v * 100 + .5) end, get = Number("textScale"), set = SetAndLayout("textScale") })
	dialog:AddCheckbox({ label = "Outline text", get = Flag("textOutline"), set = SetFlag("textOutline"),
		tooltip = "A dark outline around the spell name and time, so they stand out against every element." })
	local function Placement(label, key)
		dialog:AddButtonGrid({ label = label, columns = 3,
			buttons = { { key = "left", text = "Left" }, { key = "center", text = "Center" }, { key = "right", text = "Right" } },
			onClick = function(pos) db[key] = pos; ns:Layout() end,
			isActive = function(pos) return db[key] == pos end })
	end
	Placement("Spell name", "namePos")
	Placement("Time left", "timePos")
	dialog:AddCheckbox({ label = "Hide Blizzard's cast bar", get = Flag("hideBlizzard"), set = SetFlag("hideBlizzard") })

	-- preview: loop one element, or all of them in turn
	local buttons = { { key = "all", text = "All" } }
	for _, k in ipairs(ns.ELEMENT_ORDER) do buttons[#buttons + 1] = { key = k, text = ns.ELEMENTS[k].label } end
	dialog:AddButtonGrid({ label = "Preview", buttons = buttons, columns = 4,
		onClick = function(key)
			ns.editPreview = key ~= "all" and key or nil
			ns:TestCast(ns.editPreview, ns.inEditMode)
		end,
		isActive = function(key) return (key == "all" and not ns.editPreview) or key == ns.editPreview end,
	})

	dialog:AddButton({ text = "Reset position and size", onClick = function() ns:ResetPosition() end })
end

function ns:OpenBarSettings()
	if not dialog then CreateDialog() end
	dialog:OpenFor(bar)
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

	-- Edit Mode's selection art, shown while the bar can be moved
	selection = ns.EditMode.CreateSelection(bar, "Dave's Cast Bar")

	grip = CreateFrame("Button", nil, bar)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", 4, -4)
	grip:SetFrameLevel(selection:GetFrameLevel() + 5)
	grip:SetIgnoreParentAlpha(true)   -- stays solid while preview casts fade the bar
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
		RefreshDialog()
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
			RefreshDialog()
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
