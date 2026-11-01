-- daves_chat / EditMode.lua
-- Places the chat window with the kit's Edit Mode: outline, snapping, click for Window Settings,
-- right-click to reset. EditModeDialog.lua stays unmodified.

local _, ns = ...

function ns:ApplyPosition()
	local frame = ns.anchor
	if not frame then return end
	local s = ns.Clamp(ns.db.scale or 1, 0.5, 2)
	ns.db.scale = s
	if frame.SetScaleBase then frame:SetScaleBase(s) else frame:SetScale(s) end
	if ns.fill then
		if ns.fill.SetScaleBase then ns.fill:SetScaleBase(s) else ns.fill:SetScale(s) end
	end
	local pos = ns.db.pos or ns.DEFAULT_POS
	frame:ClearAllPoints()
	frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	frame:SetSize(ns.db.width, ns.db.height)
end

function ns:ResetPosition()
	ns.db.pos = nil
	ns:ApplyPosition()
	if ns.LayoutWindow then ns:LayoutWindow() end
	if ns.editDialog and ns.editDialog:IsShown() then ns.editDialog:Refresh() end
end

function ns:InitEditMode(frame)
	ns:ApplyPosition()

	local d = ns.EditMode.CreateDialog("daves_chatEditDialog", "Window Settings")

	-- Keep the dialog title as "Window Settings" even when EditMode.Attach opens it with o.label.
	local baseOpenFor = d.OpenFor
	function d.OpenFor(dialog, target)
		return baseOpenFor(dialog, target, "Window Settings")
	end

	-- Add 8px of breathing room inside the dialog border without modifying EditModeDialog.lua.
	-- Rows and buttons are anchored TOPLEFT; Divider is centered at ("TOP", self, "TOP", 0, y),
	-- so Divider moves down only and keeps x = 0 and its centered width.
	local EXTRA = 8
	local baseLayout = d.Layout
	function d.Layout(dialog)
		baseLayout(dialog)
		local function NudgeTopLeft(widget)
			if not widget or not widget.GetPoint then return end
			local point, rel, relPoint, x, y = widget:GetPoint(1)
			if not point then return end
			widget:ClearAllPoints()
			widget:SetPoint(point, rel, relPoint, (x or 0) + EXTRA, (y or 0) - EXTRA)
		end
		for _, row in ipairs(dialog.rows) do NudgeTopLeft(row) end
		if dialog.Divider and dialog.Divider.IsShown and dialog.Divider:IsShown() then
			local point, rel, relPoint, x, y = dialog.Divider:GetPoint(1)
			if point then
				dialog.Divider:ClearAllPoints()
				dialog.Divider:SetPoint(point, rel, relPoint, x or 0, (y or 0) - EXTRA)
			end
		end
		for _, b in ipairs(dialog.buttons) do NudgeTopLeft(b) end
		if dialog.Title then
			dialog.Title:ClearAllPoints()
			dialog.Title:SetPoint("TOP", 0, -15 - EXTRA)
		end
		local w, h = dialog:GetSize()
		dialog:SetSize((w or 0) + EXTRA * 2, (h or 0) + EXTRA * 2)
	end

	d:AddSlider({ label = "Scale", min = 0.5, max = 2, step = 0.05,
		format = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
		get = function() return ns.db.scale or 1 end,
		set = function(v)
			ns.db.scale = ns.Clamp(v, 0.5, 2)
			ns:ApplyScale()
		end })
	d:AddSlider({ label = "Width", min = ns.MIN_WIDTH, max = 1200, step = 10, format = "%d",
		get = function() return ns.db.width end,
		set = function(v)
			ns.db.width = math.max(ns.MIN_WIDTH, v)
			frame:SetWidth(ns.db.width)
			ns:LayoutWindow()
		end })
	d:AddSlider({ label = "Height", min = ns.MIN_HEIGHT, max = 800, step = 10, format = "%d",
		get = function() return ns.db.height end,
		set = function(v)
			local need = ns:MinFrameHeight()
			ns.db.height = math.max(need, v)
			frame:SetHeight(ns.db.height)
			ns:LayoutWindow()
		end })

	local styleButtons = {}
	for _, s in ipairs(ns.BACKGROUND_STYLES) do
		styleButtons[#styleButtons + 1] = { key = s.key, text = s.name }
	end
	d:AddSlider({ label = "Background", min = 0.2, max = 1, step = 0.05,
		format = function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
		get = function() return ns.db.background or 0.8 end,
		set = function(v)
			v = ns.Clamp(math.floor(v / 0.05 + 0.5) * 0.05, 0.2, 1)
			ns.db.background = v
			ns:ApplyBackground()
		end })
	d:AddButtonGrid({ label = "Background style", columns = 2,
		buttons = styleButtons,
		onClick = function(key)
			ns.db.backgroundStyle = key
			ns:ApplyBackground()
		end,
		isActive = function(key) return (ns.db.backgroundStyle or "dark") == key end })
	d:AddCheckbox({ label = "Whisper alert",
		tooltip = "Flashes the message-bubble open icon (when closed) or the Chat tab (when viewing another tab) when a whisper arrives. The usual whisper sound still plays while the window is closed.",
		get = function() return ns.db.whisperAlert end,
		set = function(v) ns.db.whisperAlert = v and true or false end })

	d:AddButton({ text = "Restore defaults", onClick = function()
		ns.db.scale = ns.DEFAULTS.scale
		ns.db.width, ns.db.height = ns.DEFAULTS.width, ns.DEFAULTS.height
		ns.db.background = ns.DEFAULTS.background
		ns.db.backgroundStyle = ns.DEFAULTS.backgroundStyle
		frame:SetSize(ns.db.width, ns.db.height)
		ns:ApplyScale()
		ns:ApplyBackground()
		d:Refresh()
	end })
	d:AddNote({ text = "Drag the empty header bar or left tab list to move the window, or drag a bottom corner to resize it. Tabs sit in a scrollable list on the left (right-click a tab to rename, add, or close windows), with newest messages at the top. In the header, the chat bubble opens Chat Settings, the window icon opens Window Settings, and the top-right X closes chat down to a draggable message-bubble icon." })

	d:AddButton({ text = "Reset tabs", onClick = function()
		if ns:ApplyTabLayout() then
			ns.Print("tabs reset: Chat, Combat Log, General.")
		else
			ns.Print("chat windows are not ready yet.")
		end
	end })
	d:AddButton({ text = "Reset position", onClick = function()
		ns:ResetPosition()
	end })

	ns.editDialog = d
	ns:ApplyBackground()
	ns.editMode = ns.EditMode.Attach(frame, {
		label = "Dave's Chat",
		dialog = d,
		onMoved = function(f)
			local point, _, relPoint, x, y = f:GetPoint(1)
			ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
		end,
		onReset = function()
			ns:ResetPosition()
		end,
	})
end
