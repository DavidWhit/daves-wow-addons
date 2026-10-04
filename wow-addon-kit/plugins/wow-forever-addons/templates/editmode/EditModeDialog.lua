-- EditModeDialog.lua: shared Edit Mode settings UI from the wow-forever-addons kit
-- (templates/editmode/EditModeDialog.lua). Don't edit an addon's copy: change the kit file and
-- copy it into every addon. Test-WowAddon.ps1 warns when a copy differs (rule editmode-dialog).
--
-- Every addon frame that can be set up in Edit Mode gets the same look and behaviour,
-- modelled on Blizzard's own EditModeSystemSettingsDialog (Blizzard_EditMode/Shared/
-- EditModeDialogs.xml and EditModeTemplates.xml, forever branch):
--   * translucent dialog border, large title, close button; Escape closes it; drag to move
--   * rows: a label column, then a MinimalSliderWithSteppers slider with its number on the right;
--     32px checkboxes; colour swatches; button grids; notes; full-width buttons under a divider
--   * every width is measured from the real strings, so labels and slider numbers always fit
--   * one settings dialog at a time across Blizzard and every kit addon: opening one clears
--     Blizzard's selection (EditModeManagerFrame:ClearSelectedSystem runs through a secure
--     delegate) and closes other addons' dialogs; Blizzard's own dialog closes ours
--   * it opens beside its frame, where it covers neither that frame, Edit Mode's window nor
--     the screen edge
--   * frames get Blizzard's Edit Mode selection art: blue while movable, yellow while selected
--   * frames snap like Blizzard's: magnetic within 8 px to grid lines, screen edges and centre,
--     and the edges of Blizzard's Edit Mode frames (EM.SnapRect / EM.SnapEdge while dragging)
--
-- Use:
--   local sel = ns.EditMode.CreateSelection(frame, "My Frame")   -- overlay; show it while movable
--   local d = ns.EditMode.CreateDialog("MyAddonEditDialog", "My Frame")
--   d:AddSlider({ label = "Width", min = 80, max = 800, step = 2, format = "%d", get = ..., set = ... })
--   d:AddCheckbox({ label = "Show text", tooltip = "...", get = ..., set = ... })
--   d:AddColor({ label = "Colour", get = ..., set = ..., saved = ... })
--   d:AddButtonGrid({ label = "Preview", buttons = { { key = "a", text = "A" } }, onClick = ..., isActive = ... })
--   d:AddNote({ text = function() return "..." end })
--   d:AddButton({ text = "Reset position", onClick = ... })
--   ns.EditMode.Attach(frame, { label = "My Frame", dialog = d, onMoved = ..., onReset = ... })
--                               -- all of the above wired up the standard way (recommended)
--   d:OpenFor(frame)            -- on click; d:Refresh() after changing settings from elsewhere,
--                               -- d:RefreshValues() while dragging (values only, no relayout)
--   left, bottom = ns.EditMode.SnapRect(frame, left, bottom, width, height)   -- each drag frame
--   x = ns.EditMode.SnapEdge(x, true)   -- a resized edge (true: an x, false: a y)

local _, ns = ...

local EM = {}
ns.EditMode = EM
EM.VERSION = 1

local PAD = 20                 -- Blizzard: widthPadding/heightPadding 40
local MIN_CONTENT, MAX_CONTENT = 300, 460
local ROW_SPACING = 2          -- Blizzard: Settings spacing 2
local ROW_H = 32               -- Blizzard: slider and checkbox rows are 32 high
local LABEL_COL = 100          -- Blizzard: slider label 100 wide, slider 200, 5 apart
local SLIDER_W = 200
local VALUE_GAP = 6            -- RightText sits 25 px right of the inner slider, which is inset 19
local BUTTON_H = 28            -- Blizzard: EditModeSystemSettingsDialogButtonTemplate
local GAP = 12                 -- between the dialog and its frame
local OPEN_EVENT = "WowAddonKit.EditModeDialogOpened"

local dialogs = {}
local snapFrames = {}   -- this addon's Edit Mode frames, which snap to each other

local function TextWidth(fs)
	return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
end

local function Tooltip(owner, title, text)
	owner:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Selection overlay: Blizzard's Edit Mode frame art
-- (EditModeSystemSelectionLayout, Blizzard_EditMode/Shared/EditModeSystemTemplates.lua)
---------------------------------------------------------------------------
local SELECTION_LAYOUT = {
	TopRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	TopLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	BottomLeftCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	BottomRightCorner = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	TopEdge = { atlas = "_%s-NineSlice-EdgeTop" },
	BottomEdge = { atlas = "_%s-NineSlice-EdgeBottom" },
	LeftEdge = { atlas = "!%s-NineSlice-EdgeLeft" },
	RightEdge = { atlas = "!%s-NineSlice-EdgeRight" },
	Center = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local HIGHLIGHT_KIT, SELECTED_KIT = "editmode-actionbar-highlight", "editmode-actionbar-selected"
local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }

local function HasEditModeArt()
	return NineSliceUtil and NineSliceUtil.ApplyLayout and C_Texture and C_Texture.GetAtlasInfo
		and C_Texture.GetAtlasInfo(HIGHLIGHT_KIT .. "-NineSlice-Corner") ~= nil
end

local function PaintSelection(sel)
	local selected = sel.selected
	if sel.art then
		NineSliceUtil.ApplyLayout(sel.art, SELECTION_LAYOUT, selected and SELECTED_KIT or HIGHLIGHT_KIT)
	else
		if selected then sel.tint:SetColorTexture(1, .82, 0, .25) else sel.tint:SetColorTexture(.25, .6, 1, .22) end
	end
	sel.label:SetFontObject(selected and "GameFontNormal" or "GameFontHighlight")
end

local function SetSelected(sel, selected)
	if not sel or sel.selected == selected then return end
	sel.selected = selected
	PaintSelection(sel)
end

-- The overlay covers the frame (corners reach 8 px outside it, as in Blizzard's) and names it
-- above. Show it while the frame can be moved; clicking the frame should call dialog:OpenFor.
function EM.CreateSelection(target, label)
	local sel = CreateFrame("Frame", nil, target)
	sel:SetAllPoints()
	sel:SetFrameLevel(target:GetFrameLevel() + 20)
	if HasEditModeArt() then
		sel.art = CreateFrame("Frame", nil, sel)
		sel.art:SetAllPoints()
		sel.hover = CreateFrame("Frame", nil, sel)
		sel.hover:SetAllPoints()
		sel.hover:SetAlpha(.4)
		NineSliceUtil.ApplyLayout(sel.hover, SELECTION_LAYOUT, HIGHLIGHT_KIT)
		for _, key in ipairs(PIECES) do
			if sel.hover[key] then sel.hover[key]:SetBlendMode("ADD") end
		end
		sel.hover:Hide()
	else
		sel.tint = sel:CreateTexture(nil, "OVERLAY")
		sel.tint:SetAllPoints()
	end
	sel.label = sel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sel.label:SetPoint("BOTTOM", sel, "TOP", 0, 10)
	sel.label:SetText(label)
	sel.selected = false
	PaintSelection(sel)
	sel:SetIgnoreParentAlpha(true)   -- stays solid while the frame fades, as Blizzard's does
	sel:Hide()
	-- Hover glow. Addons set the frame's OnEnter/OnLeave after creating this, and SetScript drops
	-- earlier hooks, so the hooks are (re)attached whenever the overlay shows and they're missing.
	sel:SetScript("OnShow", function()
		if not sel.hover then return end
		if target:GetScript("OnEnter") ~= sel.hookedEnter or not sel.hookedEnter then
			target:HookScript("OnEnter", function() if sel:IsShown() then sel.hover:Show() end end)
			sel.hookedEnter = target:GetScript("OnEnter")
		end
		if target:GetScript("OnLeave") ~= sel.hookedLeave or not sel.hookedLeave then
			target:HookScript("OnLeave", function() sel.hover:Hide() end)
			sel.hookedLeave = target:GetScript("OnLeave")
		end
	end)
	sel:SetScript("OnHide", function() if sel.hover then sel.hover:Hide() end end)
	target.editSelection = sel
	snapFrames[#snapFrames + 1] = target   -- this addon's frames snap to each other
	return sel
end

---------------------------------------------------------------------------
-- Placement: beside the frame, clear of it, of Edit Mode's window and of the screen edge
---------------------------------------------------------------------------
-- A frame's rectangle in UIParent units, or nil.
local function Rect(f, grow, growTop)
	if not (f and f:IsVisible()) then return end
	local l, b, w, h = f:GetRect()
	if not l or (issecretvalue and issecretvalue(l)) then return end
	local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	grow = grow or 0
	return { l * s - grow, b * s - grow, (l + w) * s + grow, (b + h) * s + grow + (growTop or 0) }
end

local function Overlap(a, b)
	local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
	local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
	return (w > 0 and h > 0) and w * h or 0
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function Place(dialog, target)
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	local w, h = dialog:GetWidth(), dialog:GetHeight()
	local t = Rect(target, 8, 24)   -- the selection corners, and its name above
	if not t then
		dialog:ClearAllPoints()
		dialog:SetPoint("CENTER")
		return
	end
	local obstacles = { t }
	for _, f in ipairs({ EditModeManagerFrame, EditModeSystemSettingsDialog }) do
		local r = Rect(f, 4)
		if r then obstacles[#obstacles + 1] = r end
	end
	local cx, cy = (t[1] + t[3]) / 2, (t[2] + t[4]) / 2
	local right = { t[3] + GAP, cy - h / 2 }
	local left = { t[1] - GAP - w, cy - h / 2 }
	local above = { cx - w / 2, t[4] + GAP }
	local below = { cx - w / 2, t[2] - GAP - h }
	local order = (t[3] - t[1]) > 2 * (t[4] - t[2]) and { above, below, right, left } or { right, left, above, below }
	local bestX, bestY, bestScore
	for _, c in ipairs(order) do
		local x, y = Clamp(c[1], 0, W - w), Clamp(c[2], 0, H - h)
		local r, score = { x, y, x + w, y + h }, 0
		for _, o in ipairs(obstacles) do score = score + Overlap(r, o) end
		if not bestScore or score < bestScore then bestX, bestY, bestScore = x, y, score end
		if score == 0 then break end
	end
	dialog:ClearAllPoints()
	dialog:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bestX, bestY)
end

-- After a setting moves or resizes the frame (Scale, Reset position...), step aside again if the
-- frame is now under the dialog. Never once the user has dragged the dialog themselves.
local function Follow(dialog)
	if not dialog:IsShown() or dialog.userPlaced or not dialog.target then return end
	local d, t = Rect(dialog), Rect(dialog.target, 8, 24)
	if d and t and Overlap(d, t) > 0 then Place(dialog, dialog.target) end
end

-- Changes made with the mouse on the dialog (dragging a slider, clicking its arrows or a
-- checkbox) wait until the mouse leaves it, so the dialog never jumps away from the cursor.
local function FollowWhenMouseLeaves(dialog)
	if dialog.followPending and not dialog:IsMouseOver() then
		dialog.followPending = nil
		Follow(dialog)
	end
end

---------------------------------------------------------------------------
-- Snapping, the way Blizzard's Edit Mode does it (EditModeMagnetismManager in
-- Blizzard_EditMode/Shared/EditModeUtil.lua, forever branch). It works only while Edit Mode is
-- open with "Snap" ticked. The frame moves freely and only pulls onto something within MAGNET
-- screen pixels:
--   * the screen's edges (with the frame's matching edge)
--   * the screen's centre lines and every grid line Blizzard draws (frame centre or either edge)
--   * the facing edge of a Blizzard Edit Mode frame, or another of this addon's frames, beside it
-- Everything is in UIParent units.
---------------------------------------------------------------------------
local MAGNET = 8   -- Blizzard: EditModeMagnetismManager.magnetismRange

local function SnapEnabled()
	local manager = EditModeManagerFrame
	return manager and manager:IsShown() and manager.IsSnapEnabled and manager:IsSnapEnabled()
end

-- The screen's centre line plus the drawn grid lines along one axis (EditModeGridMixin:UpdateGrid).
local function Lines(vertical)
	local lines = { (vertical and UIParent:GetWidth() or UIParent:GetHeight()) / 2 }
	local grid = EditModeManagerFrame and EditModeManagerFrame.Grid
	if grid and grid:IsVisible() and grid.gridSpacing and grid.gridSpacing > 0 then
		local s = grid:GetEffectiveScale() / UIParent:GetEffectiveScale()
		local cx, cy = grid:GetCenter()
		if cx and not (issecretvalue and issecretvalue(cx)) then
			local center = (vertical and cx or cy) * s
			local half = math.floor((vertical and grid:GetWidth() or grid:GetHeight()) / grid.gridSpacing / 2)
			for i = -half, half do lines[#lines + 1] = center + i * grid.gridSpacing * s end
		end
	end
	return lines
end

-- Rectangles of the frames this one can sit against.
local function Neighbours(frame)
	local rects = {}
	local manager = EditModeMagnetismManager
	if manager and manager.magneticFrames then
		for f in pairs(manager.magneticFrames) do
			local r = Rect(f.Selection or f)
			if r then rects[#rects + 1] = r end
		end
	end
	for _, f in ipairs(snapFrames) do
		if f ~= frame then
			local r = Rect(f)
			if r then rects[#rects + 1] = r end
		end
	end
	return rects
end

-- Snaps one axis of a rect: lo is its left (or bottom), size its width (or height). across is
-- the rect's span on the other axis, for deciding which neighbours sit beside it.
local function SnapAxis(lo, size, vertical, across, neighbours, range)
	local best, bestD
	local function Try(delta)
		local d = math.abs(delta)
		if d <= range and (not bestD or d < bestD) then best, bestD = delta, d end
	end
	local screen = vertical and UIParent:GetWidth() or UIParent:GetHeight()
	Try(-lo)
	Try(screen - (lo + size))
	for _, line in ipairs(Lines(vertical)) do
		Try(line - lo); Try(line - (lo + size / 2)); Try(line - (lo + size))
	end
	local a, b = vertical and 1 or 2, vertical and 3 or 4         -- this axis in a rect
	local c, d = vertical and 2 or 1, vertical and 4 or 3         -- the other axis
	for _, r in ipairs(neighbours) do
		if r[c] < across[2] and r[d] > across[1] then             -- beside it, not above or below
			Try(r[b] - lo)                                         -- our left edge on their right
			Try(r[a] - (lo + size))                                -- our right edge on their left
		end
	end
	return lo + (best or 0)
end

-- A dragged frame's new rect (left, bottom, width, height in UIParent units), snapped.
-- Returns the snapped left and bottom.
function EM.SnapRect(frame, left, bottom, width, height)
	if not SnapEnabled() then return left, bottom end
	local range = MAGNET / UIParent:GetEffectiveScale()
	local neighbours = Neighbours(frame)
	local x = SnapAxis(left, width, true, { bottom, bottom + height }, neighbours, range)
	local y = SnapAxis(bottom, height, false, { left, left + width }, neighbours, range)
	return x, y
end

-- One edge being resized (an x when vertical, else a y), snapped to the screen edges, the
-- screen centre and the grid lines.
function EM.SnapEdge(value, vertical)
	if not SnapEnabled() then return value end
	local range = MAGNET / UIParent:GetEffectiveScale()
	local best, bestD = value, nil
	local targets = Lines(vertical)
	targets[#targets + 1] = 0
	targets[#targets + 1] = vertical and UIParent:GetWidth() or UIParent:GetHeight()
	for _, t in ipairs(targets) do
		local dist = math.abs(t - value)
		if dist <= range and (not bestD or dist < bestD) then best, bestD = t, dist end
	end
	return best
end

---------------------------------------------------------------------------
-- One settings dialog at a time
---------------------------------------------------------------------------
local function HideOthers(_, opened)
	for _, d in ipairs(dialogs) do
		if d ~= opened then d:Hide() end
	end
end
if EventRegistry then EventRegistry:RegisterCallback(OPEN_EVENT, HideOthers, EM) end

local hookedBlizzard
local function HookBlizzardDialog()
	if hookedBlizzard or not EditModeSystemSettingsDialog then return end
	hookedBlizzard = true
	EditModeSystemSettingsDialog:HookScript("OnShow", function() HideOthers(nil, nil) end)
end

local function ClearBlizzardSelection()
	local manager = EditModeManagerFrame
	if manager and manager.ClearSelectedSystem and manager:IsShown() and not InCombatLockdown() then
		manager:ClearSelectedSystem()
	end
end

---------------------------------------------------------------------------
-- Rows. Each row has :Measure() (the content width it needs), :Place(width) (returns its
-- height) and :Refresh().
---------------------------------------------------------------------------
local Dialog = {}

local function NewRow(dialog)
	local row = CreateFrame("Frame", nil, dialog)
	row.dialog = dialog
	dialog.rows[#dialog.rows + 1] = row
	return row
end

function Dialog.AddSlider(dialog, o)
	local row = NewRow(dialog)
	row.kind = "slider"
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	label:SetJustifyH("LEFT")
	label:SetText(o.label)
	row.label = label
	local fmt = o.format or "%d"
	local format = type(fmt) == "function" and fmt or function(v) return fmt:format(v) end
	local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	slider:SetSize(SLIDER_W, ROW_H)
	local Right = MinimalSliderWithSteppersMixin.Label.Right
	slider:Init(o.get(), o.min, o.max, math.floor((o.max - o.min) / o.step + .5),
		{ [Right] = CreateMinimalSliderFormatter(Right, format) })
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if dialog.refreshing then return end
		o.set(value)
		dialog.followPending = true
	end, row)
	row.slider = slider

	function row:Measure()
		-- the widest number this slider can show, measured in its own font
		local text, widest = slider.RightText, 0
		for _, v in ipairs({ o.min, o.max, o.min + o.step, o.max - o.step }) do
			text:SetText(format(v))
			widest = math.max(widest, TextWidth(text))
		end
		text:SetText(format(o.get()))
		self.valueWidth = math.ceil(widest)
		return math.max(LABEL_COL, math.ceil(TextWidth(label)) + 8), SLIDER_W + VALUE_GAP + self.valueWidth
	end
	function row:Place(_, labelCol)
		label:ClearAllPoints()
		label:SetPoint("LEFT")
		label:SetWidth(labelCol)
		slider:ClearAllPoints()
		slider:SetPoint("LEFT", label, "RIGHT", 5, 0)
		return ROW_H
	end
	function row:Refresh() slider:SetValue(o.get()) end
	return row
end

function Dialog.AddCheckbox(dialog, o)
	local row = NewRow(dialog)
	local button = CreateFrame("CheckButton", nil, row)
	button:SetSize(32, 32)
	button:SetPoint("LEFT", -5, 0)
	button:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
	button:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
	button:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
	button:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	button:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
	button:SetScript("OnClick", function(b)
		o.set(b:GetChecked() and true or false)
		dialog.followPending = true
	end)
	if o.tooltip then Tooltip(button, o.label, o.tooltip) end
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	label:SetJustifyH("LEFT")
	label:SetText(o.label)
	row.button, row.label = button, label

	function row:Measure() return 0, 32 + math.ceil(TextWidth(label)) end
	function row:Place(width)
		label:ClearAllPoints()
		label:SetPoint("LEFT", button, "RIGHT", 5, 0)
		label:SetWidth(width - 32)
		return math.max(ROW_H, label:GetStringHeight() + 8)
	end
	function row:Refresh() button:SetChecked(o.get() and true or false) end
	return row
end

-- o.get(frame) returns {r, g, b} to show; o.set(color, frame) saves one (nil means "use the default");
-- o.saved(frame) returns what is saved now (maybe nil), restored if the colour picker is cancelled.
-- frame is the one the dialog was open for when the picker opened.
-- SetupColorPickerAndShow fires swatchFunc once while opening, so an unchanged colour is
-- not saved (Blizzard_ColorPickerFrame/Shared/ColorPickerFrame.lua, forever branch).
function Dialog.AddColor(dialog, o)
	local row = NewRow(dialog)
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	label:SetJustifyH("LEFT")
	label:SetText(o.label)
	local swatch = CreateFrame("Button", nil, row)
	swatch:SetSize(22, 22)
	swatch:SetPoint("RIGHT", -2, 0)
	local edge = swatch:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(.8, .8, .8)
	local color = swatch:CreateTexture(nil, "ARTWORK")
	color:SetPoint("TOPLEFT", 2, -2)
	color:SetPoint("BOTTOMRIGHT", -2, 2)
	if o.tooltip then Tooltip(swatch, o.label, o.tooltip) end
	swatch:SetScript("OnClick", function()
		-- The frame the picker was opened for, so a change still lands there if the dialog has
		-- since moved on to another frame.
		local owner = dialog.target
		local cur = o.get(owner)
		local prev = cur
		if o.saved then prev = o.saved(owner) end
		local r, g, b = cur[1], cur[2], cur[3]
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b,
			swatchFunc = function()
				local nr, ng, nb = ColorPickerFrame:GetColorRGB()
				if nr == r and ng == g and nb == b then return end
				o.set({ nr, ng, nb }, owner)
				dialog:Refresh()
			end,
			cancelFunc = function() o.set(prev, owner); dialog:Refresh() end,
		})
	end)
	row.label, row.swatch = label, swatch

	function row:Measure() return 0, math.ceil(TextWidth(label)) + 12 + 24 end
	function row:Place(width)
		label:ClearAllPoints()
		label:SetPoint("LEFT")
		label:SetWidth(width - 36)
		return math.max(ROW_H, label:GetStringHeight() + 8)
	end
	function row:Refresh()
		local c = o.get(dialog.target)
		color:SetColorTexture(c[1], c[2], c[3])
	end
	return row
end

-- o.buttons = { { key = ..., text = ... }, ... }; o.onClick(key); o.isActive(key) lights one up.
function Dialog.AddButtonGrid(dialog, o)
	local row = NewRow(dialog)
	local header = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	header:SetPoint("TOPLEFT")
	header:SetText(o.label or "")
	row.buttons = {}
	for i, info in ipairs(o.buttons) do
		local b = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		b:SetHeight(22)
		b:SetText(info.text)
		b.key = info.key
		b:SetScript("OnClick", function() o.onClick(info.key); dialog:Refresh() end)
		row.buttons[i] = b
	end

	function row:Measure()
		local widest = 0
		for _, b in ipairs(self.buttons) do widest = math.max(widest, TextWidth(b:GetFontString())) end
		self.buttonWidth = math.max(64, math.ceil(widest) + 24)
		local cols = math.min(o.columns or 4, #self.buttons)
		return 0, cols * self.buttonWidth + (cols - 1) * 4
	end
	function row:Place(width)
		local cols = math.max(1, math.min(o.columns or 4, math.floor((width + 4) / (self.buttonWidth + 4))))
		local bw = (width - (cols - 1) * 4) / cols
		local top = o.label and 20 or 0
		for i, b in ipairs(self.buttons) do
			local col, line = (i - 1) % cols, math.floor((i - 1) / cols)
			b:SetWidth(bw)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", col * (bw + 4), -top - line * 24)
		end
		return top + math.ceil(#self.buttons / cols) * 24
	end
	function row:Refresh()
		for _, b in ipairs(self.buttons) do
			if o.isActive and o.isActive(b.key) then b:LockHighlight() else b:UnlockHighlight() end
		end
	end
	return row
end

-- o.text: a string, or a function returning one ("" hides the note).
function Dialog.AddNote(dialog, o)
	local row = NewRow(dialog)
	local text = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	text:SetPoint("TOPLEFT")
	text:SetJustifyH("LEFT")
	function row:Measure() return 0, 0 end
	function row:Place(width)
		text:SetWidth(width)
		local s = text:GetText()
		return (s and s ~= "") and math.ceil(text:GetStringHeight()) + 4 or 0
	end
	function row:Refresh() text:SetText(type(o.text) == "function" and o.text() or o.text) end
	return row
end

-- Full-width buttons under a divider, like Blizzard's "Reset To Default Position".
function Dialog.AddButton(dialog, o)
	local b = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	b:SetHeight(BUTTON_H)
	b:SetText(o.text)
	b:SetScript("OnClick", function() o.onClick(); dialog:Refresh(); Follow(dialog) end)
	if o.tooltip then Tooltip(b, o.text, o.tooltip) end
	b.enabled = o.enabled
	dialog.buttons[#dialog.buttons + 1] = b
	return b
end

function Dialog:Layout()
	local labelCol, content = 0, MIN_CONTENT
	for _, row in ipairs(self.rows) do
		local col, rest = row:Measure()
		if row.kind == "slider" then labelCol = math.max(labelCol, col) end
		row.rest = rest
	end
	for _, row in ipairs(self.rows) do
		content = math.max(content, (row.kind == "slider" and labelCol + 5 or 0) + row.rest)
	end
	for _, b in ipairs(self.buttons) do content = math.max(content, math.ceil(TextWidth(b:GetFontString())) + 40) end
	content = math.max(content, math.ceil(TextWidth(self.Title)) + 64)   -- title clear of the close button
	content = math.min(content, MAX_CONTENT)
	self.Title:SetWidth(content)

	local y = -15 - math.ceil(self.Title:GetStringHeight()) - 12
	for _, row in ipairs(self.rows) do
		local h = row:Place(content, labelCol)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", PAD, y)
		row:SetSize(content, math.max(h, 1))
		row:SetShown(h > 0)
		if h > 0 then y = y - h - ROW_SPACING end
	end
	if #self.buttons > 0 then
		y = y - 4
		self.Divider:ClearAllPoints()
		self.Divider:SetPoint("TOP", self, "TOP", 0, y)
		self.Divider:SetWidth(content + 10)
		self.Divider:Show()
		y = y - 16
		for _, b in ipairs(self.buttons) do
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", PAD, y)
			b:SetWidth(content)
			y = y - BUTTON_H - ROW_SPACING
		end
	else
		self.Divider:Hide()
	end
	self:SetSize(content + 2 * PAD, -y + PAD)
end

-- Everything: values, sizes and layout. Afterwards the dialog steps aside if its frame moved
-- under it (once the mouse is off the dialog).
function Dialog:Refresh()
	self:RefreshValues()
	for _, b in ipairs(self.buttons) do b:SetEnabled(not b.enabled or b.enabled()) end
	self:Layout()
	self.followPending = true
end

-- Only the values shown. Cheap enough to call every frame, e.g. while the frame is being resized.
function Dialog:RefreshValues()
	self.refreshing = true
	for _, row in ipairs(self.rows) do row:Refresh() end
	self.refreshing = nil
end

-- Opens the dialog for `target` (the frame its settings belong to), beside it. Reopening it
-- for the same frame keeps the place the user dragged it to.
function Dialog:OpenFor(target, title)
	HookBlizzardDialog()
	ClearBlizzardSelection()
	if EventRegistry then EventRegistry:TriggerEvent(OPEN_EVENT, self) else HideOthers(nil, self) end
	if self.target ~= target then
		if self.target then SetSelected(self.target.editSelection, false) end
		self.target, self.userPlaced = target, nil
	end
	if title then self.Title:SetText(title) end
	self:Refresh()
	if not self.userPlaced then Place(self, target) end
	SetSelected(target.editSelection, true)
	self:Show()
end

-- name: a global frame name (Escape closes frames listed in UISpecialFrames by name).
function EM.CreateDialog(name, title)
	local d = CreateFrame("Frame", name, UIParent)
	for k, v in pairs(Dialog) do d[k] = v end
	d.rows, d.buttons = {}, {}
	d:SetFrameStrata("DIALOG")
	d:SetFrameLevel(200)
	d:SetToplevel(true)
	d:EnableMouse(true)
	d:SetMovable(true)
	d:SetClampedToScreen(true)
	d:RegisterForDrag("LeftButton")
	d:SetScript("OnDragStart", d.StartMoving)
	d:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self.userPlaced = true
	end)
	d:SetScript("OnUpdate", FollowWhenMouseLeaves)
	d:SetScript("OnHide", function(self)
		if self.target then SetSelected(self.target.editSelection, false) end
	end)
	d:Hide()

	local ok, border = pcall(CreateFrame, "Frame", nil, d, "DialogBorderTranslucentTemplate")
	if ok and border then
		border:SetAllPoints()
	else
		local bg = d:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, .8)
	end
	d.Title = d:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	d.Title:SetPoint("TOP", 0, -15)
	d.Title:SetText(title or "")
	local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT")
	d.Divider = d:CreateTexture(nil, "ARTWORK")
	d.Divider:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-OnlineDivider")
	d.Divider:SetHeight(16)

	tinsert(UISpecialFrames, name)
	dialogs[#dialogs + 1] = d
	return d
end

---------------------------------------------------------------------------
-- Attach: the whole Edit Mode behaviour for one frame, the same way in every addon.
--   EM.Attach(frame, {
--       label = "My Frame",                -- shown on the outline and as the dialog title
--       dialog = d,                         -- from EM.CreateDialog; clicking the frame opens it
--       onMoved = function(frame) end,      -- save the position after a drag
--       onReset = function(frame) end,      -- right-click: put it back
--       canMove = function() return ... end -- optional: also movable outside Edit Mode ("unlocked")
--   })
-- It shows the outline while the frame can move, drags with Blizzard-style magnetic snapping
-- (Shift places freely), opens the dialog on click, resets on right-click and shows a hint on
-- hover. Call handle:Update() after changing whatever canMove() reads.
---------------------------------------------------------------------------
function EM.Attach(frame, o)
	local handle = {}
	local sel = EM.CreateSelection(frame, o.label)
	local inEditMode = false

	local function Movable() return inEditMode or (o.canMove and o.canMove()) or false end

	local function DragUpdate()
		local scale, ui = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		local x, y = (cx - frame.emGrabX) / ui, (cy - frame.emGrabY) / ui
		if not IsShiftKeyDown() then
			local w, h = frame:GetWidth() * scale / ui, frame:GetHeight() * scale / ui
			local left, bottom = EM.SnapRect(frame, x - w / 2, y - h / 2, w, h)
			x, y = left + w / 2, bottom + h / 2
		end
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * ui / scale, y * ui / scale)
	end

	function handle:Update()
		if frame:IsProtected() and InCombatLockdown() then return end
		local movable = Movable()
		sel:SetShown(movable)
		frame:EnableMouse(movable)
		if movable then frame:RegisterForDrag("LeftButton") else frame:RegisterForDrag() end
		if not movable and o.dialog and o.dialog.target == frame then o.dialog:Hide() end
	end

	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetScript("OnDragStart", function(self)
		if not Movable() or (self:IsProtected() and InCombatLockdown()) then return end
		local scale = self:GetEffectiveScale()
		local ox, oy = self:GetCenter()
		local cx, cy = GetCursorPosition()
		self.emGrabX, self.emGrabY = cx - ox * scale, cy - oy * scale
		self.emDragged = true
		self:SetScript("OnUpdate", DragUpdate)
	end)
	frame:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		if o.onMoved then o.onMoved(self) end
	end)
	frame:SetScript("OnMouseUp", function(self, button)
		if not Movable() then return end
		if self.emDragged then
			self.emDragged = nil
		elseif button == "LeftButton" and o.dialog then
			o.dialog:OpenFor(self, o.label)
		elseif button == "RightButton" and o.onReset then
			o.onReset(self)
			if o.dialog and o.dialog:IsShown() then o.dialog:Refresh() end
		end
	end)
	frame:SetScript("OnEnter", function(self)
		if not Movable() then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(o.label)
		GameTooltip:AddLine("Click for settings. Drag to move (with Snap on it pulls onto the grid, screen edges and nearby frames; hold Shift to place freely). Right-click to reset.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Enter", function() inEditMode = true; handle:Update() end, handle)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			inEditMode = false
			if frame:GetScript("OnUpdate") == DragUpdate then frame:GetScript("OnDragStop")(frame) end
			handle:Update()
			GameTooltip:Hide()
		end, handle)
	end
	handle:Update()
	return handle
end
