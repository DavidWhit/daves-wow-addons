-- daves_chat / Window.lua
-- Outer dialog frame, left scrollable tab column, inner chat-text frame, background painting,
-- snap-dragging, corner resizing, draggable message-bubble open icon when collapsed,
-- whisper pulse alerts, single-pass layout orchestration, and runtime watchers.

local _, ns = ...

-- Same backgrounds as Dave's Sack (Blizzard's own dialog papers and classic panel textures).
ns.BACKGROUND_STYLES = {
	{ key = "dark",       name = "Dark" },
	{ key = "dialog",     name = "Light paper", file = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = true, light = true },
	{ key = "darkdialog", name = "Dark paper",  file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", tile = true },
	{ key = "marble",     name = "Marble",      file = "Interface\\FrameGeneral\\UI-Background-Marble", tile = true, light = true },
	{ key = "rock",       name = "Rock",        file = "Interface\\FrameGeneral\\UI-Background-Rock", tile = true, light = true },
}

function ns.BackgroundStyle(key)
	for _, s in ipairs(ns.BACKGROUND_STYLES) do
		if s.key == key then return s end
	end
	return ns.BACKGROUND_STYLES[1]
end

local function PaintTexture(bg, a, style)
	if not bg then return end
	if style.atlas and ns.HasAtlas(style.atlas) then
		bg:SetHorizTile(false); bg:SetVertTile(false)
		bg:SetAtlas(style.atlas, false)
		bg:SetVertexColor(1, 1, 1, a)
	elseif style.file then
		local wrap = style.tile and "REPEAT" or "CLAMP"
		bg:SetTexture(style.file, wrap, wrap)
		bg:SetTexCoord(0, 1, 0, 1)
		bg:SetHorizTile(style.tile or false); bg:SetVertTile(style.tile or false)
		bg:SetVertexColor(1, 1, 1, a)
	else
		bg:SetHorizTile(false); bg:SetVertTile(false)
		bg:SetColorTexture(0, 0, 0, a)
	end
end

local function PaintBackdrop(border, a, style)
	if not border or not border.SetBackdrop then return end
	local file = style.file
	border:SetBackdrop({
		bgFile = file or "Interface\\Buttons\\WHITE8X8", tile = style.tile or false, tileSize = 256,
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	if file then border:SetBackdropColor(1, 1, 1, a) else border:SetBackdropColor(0, 0, 0, a) end
end

local function DialogFillTexture(dialog)
	if not dialog then return end
	if dialog.davesFill then return dialog.davesFill end
	local n = dialog.GetNumChildren and dialog:GetNumChildren() or 0
	for i = 1, n do
		local child = select(i, dialog:GetChildren())
		if child and child.Bg then
			child.Bg:Show()
			dialog.davesFill = child.Bg
			return child.Bg
		end
	end
	local tex = dialog:CreateTexture(nil, "BACKGROUND")
	tex:SetPoint("TOPLEFT", dialog, "TOPLEFT", 7, -7)
	tex:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -7, 7)
	dialog.davesFill = tex
	return tex
end

-- The fill is its own BACKGROUND frame parented to UIParent (chat frames are LOW strata,
-- so a fill on the MEDIUM dialog would cover the text). Window Settings shares the style.
function ns:ApplyBackground()
	local a = ns.Clamp(ns.db.background or 0.8, 0.2, 1)
	local style = ns.BackgroundStyle(ns.db.backgroundStyle)
	if ns.border and ns.border.Bg and ns.fillTex then ns.border.Bg:Hide() end
	if ns.fillTex then
		PaintTexture(ns.fillTex, a, style)
	elseif ns.border then
		PaintBackdrop(ns.border, a, style)
	end
	if ns.tabColumnFill then
		if style.light then
			ns.tabColumnFill:SetColorTexture(0, 0, 0, math.min(0.22, a * 0.22))
		else
			ns.tabColumnFill:SetColorTexture(0, 0, 0, math.min(0.26, a * 0.26))
		end
	end
	if ns.chatBoxFill then
		if style.light then
			ns.chatBoxFill:SetColorTexture(0, 0, 0, math.min(0.24, a * 0.24))
		else
			ns.chatBoxFill:SetColorTexture(0, 0, 0, math.min(0.42, a * 0.42))
		end
	end
	if ns.settingsDivider then
		if style.light then
			ns.settingsDivider:SetColorTexture(0, 0, 0, 0.5)
		else
			ns.settingsDivider:SetColorTexture(1, 1, 1, 0.28)
		end
	end
	if ns.tabDivider then
		if style.light then
			ns.tabDivider:SetColorTexture(0, 0, 0, 0.4)
		else
			ns.tabDivider:SetColorTexture(1, 1, 1, 0.2)
		end
	end
	local editBg = DialogFillTexture(ns.editDialog)
	if editBg then PaintTexture(editBg, a, style) end
	if ns.RefreshTabs and ns.anchor and ns.anchor:IsShown() then
		ns:RefreshTabs()
	end
end

---------------------------------------------------------------------------
-- Shared magnetic snap-drag helper (uses ns.EditMode.SnapRect)
---------------------------------------------------------------------------
local function ResetButtonVisual(btn)
	if btn and btn.SetButtonState then
		btn:SetButtonState("NORMAL", false)
	end
end

local function MakeSnapMover(target, opts)
	opts = opts or {}
	local moving = false
	local mover = {}

	function mover.Stop()
		if not moving then return end
		moving = false
		target.isMovingIcon = nil
		if opts.markDragged then
			target.dragStopTime = GetTime()
		end
		target:SetScript("OnUpdate", nil)
		ResetButtonVisual(target)
		if opts.onStop then opts.onStop(target) end
	end

	function mover.Start()
		if moving then return end
		if target.IsProtected and target:IsProtected() and InCombatLockdown() then return end
		local scale = target:GetEffectiveScale()
		local ox, oy = target:GetCenter()
		if not ox then return end
		local cx, cy = GetCursorPosition()
		local grabX, grabY = cx - ox * scale, cy - oy * scale
		moving = true
		if opts.markDragged then target.isMovingIcon = true end
		ResetButtonVisual(target)
		target:SetScript("OnUpdate", function(self)
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
				mover.Stop()
				return
			end
			if self.GetButtonState and self.SetButtonState and self:GetButtonState() ~= "NORMAL" then
				self:SetButtonState("NORMAL", false)
			end
			local sc, ui = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
			local mx, my = GetCursorPosition()
			local x, y = (mx - grabX) / ui, (my - grabY) / ui
			local w, h = self:GetWidth() * sc / ui, self:GetHeight() * sc / ui
			if not IsShiftKeyDown() and ns.EditMode and ns.EditMode.SnapRect then
				local left, bottom = ns.EditMode.SnapRect(self, x - w / 2, y - h / 2, w, h)
				x, y = left + w / 2, bottom + h / 2
			end
			if opts.clampScreen then
				local halfW, halfH = w / 2, h / 2
				local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
				x = ns.Clamp(x, halfW, sw - halfW)
				y = ns.Clamp(y, halfH, sh - halfH)
			end
			self:ClearAllPoints()
			self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * ui / sc, y * ui / sc)
		end)
	end

	return mover
end

local function WireDragHandle(handle, mover)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", mover.Start)
	handle:SetScript("OnDragStop", mover.Stop)
	handle:SetScript("OnHide", mover.Stop)
	handle:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then ns:ResetPosition() end
	end)
end

---------------------------------------------------------------------------
-- Window, inner chat frame, draggable message-bubble open icon, wheel catcher, and corner grips
---------------------------------------------------------------------------
local function BuildWindow(anchor)
	local border = ns.TryTemplate("Frame", nil, anchor, "DialogBorderTranslucentTemplate") -- editmode-ui: ok
	if border then
		border:SetAllPoints()
	else
		border = CreateFrame("Frame", nil, anchor, BackdropTemplateMixin and "BackdropTemplate" or nil)
		border:SetAllPoints()
		border:SetFrameLevel(anchor:GetFrameLevel())
		border:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		border:SetBackdropColor(0, 0, 0, 0.8)
	end
	ns.border = border
	if border.Bg then border.Bg:Hide() end

	local topLevel = math.max(anchor:GetFrameLevel() or 0,
		(border and border.GetFrameLevel and border:GetFrameLevel()) or 0)

	-- Behind the chat text on UIParent at BACKGROUND strata; scaled in Dock.lua to match anchor
	-- so its 7px dialog-border inset, inner chat well, and tiled textures line up at every window scale.
	local fill = CreateFrame("Frame", nil, UIParent)
	fill:SetFrameStrata("BACKGROUND")
	fill:SetAllPoints(anchor)
	ns.fill = fill

	local fillTex = fill:CreateTexture(nil, "BACKGROUND", nil, 0)
	fillTex:SetPoint("TOPLEFT", fill, "TOPLEFT", 7, -7)
	fillTex:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", -7, 7)
	ns.fillTex = fillTex

	ns:BuildHeader(anchor)

	-- Left-side vertical chat tab list container (inside the main window frame).
	local tabColumn = CreateFrame("Frame", nil, anchor)
	tabColumn:SetWidth(ns.TAB_WIDTH or 104)
	tabColumn:SetFrameLevel(topLevel + 10)
	ns.tabColumn = tabColumn

	local tabColumnFill = fill:CreateTexture(nil, "BACKGROUND", nil, 1)
	tabColumnFill:SetAllPoints(tabColumn)
	ns.tabColumnFill = tabColumnFill

	local tabDivider = tabColumn:CreateTexture(nil, "BORDER")
	tabDivider:SetWidth(1)
	tabDivider:SetPoint("TOPRIGHT", tabColumn, "TOPRIGHT", 0, 0)
	tabDivider:SetPoint("BOTTOMRIGHT", tabColumn, "BOTTOMRIGHT", 0, 0)
	tabDivider:SetColorTexture(1, 1, 1, 0.2)
	ns.tabDivider = tabDivider

	-- Bordered inner frame around the chat message area next to the left tab stack.
	-- Its NineSlice border renders on MEDIUM strata while its Bg stays hidden so LOW-strata chat text
	-- is never covered; chatBoxFill draws the recessed inner pane behind the text on BACKGROUND strata.
	local chatBox = ns.TryTemplate("Frame", nil, anchor, "InsetFrameTemplate") -- editmode-ui: ok
	if not chatBox then
		chatBox = CreateFrame("Frame", nil, anchor, BackdropTemplateMixin and "BackdropTemplate" or nil)
		if chatBox.SetBackdrop then
			chatBox:SetBackdrop({
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
				insets = { left = 3, right = 3, top = 3, bottom = 3 },
			})
			chatBox:SetBackdropBorderColor(0.65, 0.65, 0.65, 0.85)
		end
	end
	chatBox:SetFrameLevel(anchor:GetFrameLevel() + 5)
	if chatBox.Bg then chatBox.Bg:Hide() end
	chatBox:EnableMouse(false)
	if chatBox.NineSlice and chatBox.NineSlice.EnableMouse then
		chatBox.NineSlice:EnableMouse(false)
	end
	ns.chatBox = chatBox

	local chatBoxFill = fill:CreateTexture(nil, "BACKGROUND", nil, 1)
	chatBoxFill:SetPoint("TOPLEFT", chatBox, "TOPLEFT", 3, -3)
	chatBoxFill:SetPoint("BOTTOMRIGHT", chatBox, "BOTTOMRIGHT", -3, 3)
	ns.chatBoxFill = chatBoxFill

	-- Header, top lip, and empty tab-column drag outside Edit Mode (anchor itself stays mouse-off
	-- outside Edit Mode so clicks pass through to chat links and the 3D world).
	local windowMover = MakeSnapMover(anchor, {
		onStop = function(self)
			local point, _, relPoint, x, y = self:GetPoint(1)
			if point then ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y } end
			if ns.editDialog and ns.editDialog:IsShown() then ns.editDialog:Refresh() end
		end,
	})

	local drag = CreateFrame("Frame", nil, anchor)
	drag:SetPoint("TOPLEFT", anchor, "TOPLEFT", 6, -4)
	drag:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -32, -4)
	drag:SetHeight(14)
	drag:SetFrameLevel(topLevel + 20)
	WireDragHandle(drag, windowMover)
	drag:SetScript("OnEnter", function(self)
		ns.AnchorTooltip(self)
		GameTooltip:SetText("Drag to move")
		GameTooltip:AddLine("Right-click to reset the position.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	drag:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ns.dragStrip = drag

	WireDragHandle(ns.settingsBar, windowMover)
	WireDragHandle(tabColumn, windowMover)

	-- Draggable message-bubble icon shown while collapsed; independent of the window's rectangle.
	local toggle = ns.MakeChatIcon(UIParent, "DavesChatToggle")
	toggle:SetFrameStrata("MEDIUM")
	toggle:SetFrameLevel(40)
	toggle:SetClampedToScreen(true)
	local iconMover = MakeSnapMover(toggle, {
		clampScreen = true,
		markDragged = true,
		onStop = function(self)
			local point, _, relPoint, x, y = self:GetPoint(1)
			if point then ns.db.iconPos = { point = point, relPoint = relPoint, x = x, y = y } end
		end,
	})
	toggle:RegisterForDrag("LeftButton")
	toggle:SetScript("OnDragStart", iconMover.Start)
	toggle:SetScript("OnDragStop", iconMover.Stop)
	toggle:SetScript("OnHide", iconMover.Stop)
	toggle:SetScript("OnClick", function(self)
		ResetButtonVisual(self)
		if self.isMovingIcon or (self.dragStopTime and (GetTime() - self.dragStopTime) < 0.05) then
			return
		end
		ns.Sound("IG_CHAT_EMOTE_BUTTON")
		local opening = ns.db.collapsed
		ns:SetCollapsed(not ns.db.collapsed)
		if opening and ns.SelectDefaultTab then ns:SelectDefaultTab(false) end
	end)
	toggle:SetScript("OnEnter", function(self)
		ns.AnchorTooltip(self, "RIGHT")
		GameTooltip:SetText("Open chat")
		GameTooltip:AddLine("Drag to move this icon.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	toggle:Hide()
	ns.toggle = toggle

	-- Over the inner chat frame only. Mouse stays off so links, IM click-anywhere, and 3D world clicks
	-- pass through; EnableMouseWheel catches wheel rolls above the dialog border.
	local wheel = CreateFrame("Frame", nil, anchor)
	wheel:SetFrameLevel(topLevel + 6)
	wheel:EnableMouse(false)
	wheel:EnableMouseWheel(true)
	wheel:SetScript("OnMouseWheel", function(_, delta)
		ns.ScrollFrameByWheel(ns.VisibleChatFrame(), delta)
	end)
	wheel:Hide()
	ns.messageWheel = wheel

	-- Bottom-left and bottom-right resize grips with EditMode.SnapEdge snapping.
	ns.grips = {}
	local rs = {}
	local resizer = CreateFrame("Frame")
	resizer:Hide()
	local function StopResize()
		if not resizer:IsShown() then return end
		resizer:Hide()
		rs.x = nil
		ns.resizing = nil
		local point, _, relPoint, x, y = anchor:GetPoint(1)
		if point then ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y } end
		if ns.editDialog and ns.editDialog:IsShown() then ns.editDialog:Refresh() end
	end
	resizer:SetScript("OnUpdate", function()
		if not rs.x then return end
		if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then StopResize() return end
		local minW = ns.MIN_WIDTH
		local minH = ns:MinFrameHeight()
		local sc = anchor:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		local dx, dy = cx / sc - rs.x, cy / sc - rs.y
		local w = math.max(minW, math.min(rs.right and (rs.w + dx) or (rs.w - dx), rs.maxW))
		local h = math.max(minH, math.min(rs.h - dy, rs.maxH))
		if ns.EditMode and ns.EditMode.SnapEdge then
			local ui = sc / UIParent:GetEffectiveScale()
			local function Frame(v) return v / ui end
			if rs.right then
				w = math.max(minW, Frame(ns.EditMode.SnapEdge((rs.left + w) * ui, true)) - rs.left)
			else
				w = math.max(minW, rs.rightX - Frame(ns.EditMode.SnapEdge((rs.rightX - w) * ui, true)))
			end
			h = math.max(minH, rs.top - Frame(ns.EditMode.SnapEdge((rs.top - h) * ui, false)))
		end
		ns.db.width, ns.db.height = math.floor(w + 0.5), math.floor(h + 0.5)
		anchor:SetSize(ns.db.width, ns.db.height)
		ns:LayoutWindow()
		if ns.editDialog and ns.editDialog:IsShown() and ns.editDialog.RefreshValues then
			ns.editDialog:RefreshValues()
		end
	end)
	local function StartResize(right)
		local left, rightX, top = anchor:GetLeft(), anchor:GetRight(), anchor:GetTop()
		if not (left and top and rightX) then return end
		local sc = anchor:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		rs.right, rs.x, rs.y = right, cx / sc, cy / sc
		rs.w, rs.h, rs.left, rs.rightX, rs.top = anchor:GetWidth(), anchor:GetHeight(), left, rightX, top
		local screenW = UIParent:GetWidth() * UIParent:GetEffectiveScale() / sc
		rs.maxW = right and (screenW - left) or rightX
		rs.maxH = top - 8
		anchor:ClearAllPoints()
		if right then
			anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		else
			anchor:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", rightX, top)
		end
		ns.resizing = true
		resizer:Show()
	end
	for _, right in ipairs({ true, false }) do
		local g = CreateFrame("Button", nil, anchor)
		g:SetSize(16, 16)
		g:SetPoint(right and "BOTTOMRIGHT" or "BOTTOMLEFT", right and -4 or 4, 4)
		g:SetFrameLevel(topLevel + 40)
		local t = g:CreateTexture(nil, "OVERLAY")
		t:SetTexture(ns.MEDIA .. "grip"); t:SetAllPoints(); t:SetAlpha(0.55)
		local hl = g:CreateTexture(nil, "HIGHLIGHT")
		hl:SetTexture(ns.MEDIA .. "grip"); hl:SetAllPoints(); hl:SetBlendMode("ADD")
		if not right then t:SetTexCoord(1, 0, 0, 1); hl:SetTexCoord(1, 0, 0, 1) end
		g:SetScript("OnMouseDown", function(_, btn) if btn == "LeftButton" then StartResize(right) end end)
		g:SetScript("OnMouseUp", StopResize)
		g:SetScript("OnHide", StopResize)
		g:SetScript("OnEnter", function(self)
			ns.AnchorTooltip(self)
			GameTooltip:SetText("Drag to resize")
			GameTooltip:Show()
		end)
		g:SetScript("OnLeave", function() GameTooltip:Hide() end)
		ns.grips[#ns.grips + 1] = g
	end

	ns:ApplyBackground()
end

function ns:PlaceToggle()
	local btn, anchor = ns.toggle, ns.anchor
	if not btn then return end
	if not ns.db.iconPos and anchor and anchor:GetLeft() and anchor:GetBottom() then
		local sc = (anchor:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
		ns.db.iconPos = {
			point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT",
			x = anchor:GetLeft() * sc, y = anchor:GetBottom() * sc,
		}
	end
	local pos = ns.db.iconPos or { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 16, y = 16 }
	btn:ClearAllPoints()
	btn:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

---------------------------------------------------------------------------
-- Whisper button / tab pulse alert (reads no secret message/sender payload)
---------------------------------------------------------------------------
function ns.SetButtonPulse(button, active, duration)
	if not button then return end
	if not active then
		button.alerting = false
		button.alertUntil = nil
		if button.glow then button.glow:SetAlpha(0) end
		if button.pulse then button.pulse:Hide() end
		return
	end
	if not button.glow then
		local glow = button:CreateTexture(nil, "OVERLAY")
		glow:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
		glow:SetAllPoints()
		glow:SetBlendMode("ADD")
		glow:SetAlpha(0)
		button.glow = glow
		local pulse = CreateFrame("Frame", nil, button)
		pulse:Hide()
		pulse:SetScript("OnUpdate", function()
			local timed = button.alertUntil and GetTime() <= button.alertUntil
			if not button.alerting and not timed then
				button.alertUntil = nil
				glow:SetAlpha(0)
				pulse:Hide()
				return
			end
			glow:SetAlpha(0.25 + 0.65 * math.abs(math.sin(GetTime() * 4)))
		end)
		button.pulse = pulse
	end
	if duration then
		button.alertUntil = GetTime() + duration
	else
		button.alerting = true
	end
	button.pulse:Show()
end

local function PulseButton(button)
	ns.SetButtonPulse(button, true, 8)
end

function ns:AlertWhisper()
	if not ns.db.whisperAlert then return end
	PulseButton(ns.toggle)
	local selected = ns.VisibleChatFrame and ns.VisibleChatFrame()
	if selected ~= ChatFrame1 then
		if ns.db.showTabs == false then
			ns.hiddenTabAlertUntil = GetTime() + 8
		end
		if ns.tabs then
			for i = 1, #ns.tabs do
				local tab = ns.tabs[i]
				if tab and tab.chatFrame == ChatFrame1 then
					tab.alertUntil = GetTime() + 8
					break
				end
			end
		end
		if ns.RefreshTabs and (not ns.db.collapsed or ns.inEditMode) then
			ns:RefreshTabs()
		end
	end
end

function ns:CHAT_MSG_WHISPER()
	ns:AlertWhisper()
end

function ns:CHAT_MSG_BN_WHISPER()
	ns:AlertWhisper()
end

---------------------------------------------------------------------------
-- Clicking any window control (header icons, Social/Channels, tab list, drag strip, resize grips,
-- close X, or the Window Settings dialog) clears the Say box so it never floats above them.
-- Clicks on the chat text itself are left alone so shift-clicking links into the box still works.
---------------------------------------------------------------------------
local function MouseOverShown(frame)
	if not (frame and frame.IsShown and frame:IsShown() and frame.IsMouseOver) then return false end
	local over = frame:IsMouseOver()
	if issecretvalue and issecretvalue(over) then return false end
	return over and true or false
end

local function MouseOverWindowControls()
	if MouseOverShown(ns.settingsBar) or MouseOverShown(ns.closeButton)
		or MouseOverShown(ns.dragStrip) or MouseOverShown(ns.tabColumn)
		or MouseOverShown(ns.editDialog) then
		return true
	end
	if ns.grips then
		for i = 1, #ns.grips do
			if MouseOverShown(ns.grips[i]) then return true end
		end
	end
	return false
end

function ns:GLOBAL_MOUSE_DOWN()
	if not ns.db.enabled or (ns.db.collapsed and not ns.inEditMode) then return end
	if not (ns.OwnedEditBoxActive and ns:OwnedEditBoxActive()) then return end
	if MouseOverWindowControls() then
		ns:CloseOwnedEditBoxes(true)
	end
end

---------------------------------------------------------------------------
-- Faint mode: while the window isn't hovered, fade every piece of window chrome (border, background,
-- header, tab list, inner frame border, scrollbar, resting edit box, grips) so only chat text shows.
-- Runs on its own UIParent child frame (EditMode.Attach owns the anchor's OnUpdate while dragging).
---------------------------------------------------------------------------
local FAINT_FADE_IN = 0.15   -- seconds to fade chrome back in on hover
local FAINT_FADE_OUT = 0.4   -- seconds to fade chrome out after the hover delay
local FAINT_DELAY = 0.6      -- seconds the chrome stays after the mouse leaves

ns.chromeAlpha = 1

local function SetChromeAlpha(a)
	ns.chromeAlpha = a
	if ns.anchor then ns.anchor:SetAlpha(a) end
	if ns.fill then ns.fill:SetAlpha(a) end
	if ns.ApplyOwnedChromeAlpha then ns:ApplyOwnedChromeAlpha() end
end

local function KeepChromeVisible()
	if ns.inEditMode or ns.resizing then return true end
	if MouseOverShown(ns.anchor) then return true end
	if ns.editDialog and ns.editDialog.IsShown and ns.editDialog:IsShown() then return true end
	if ns.OwnedEditBoxActive and ns:OwnedEditBoxActive() then return true end
	return false
end

local function StartFaintFader()
	local lastHover = 0
	local fader = CreateFrame("Frame", nil, UIParent)
	fader:SetScript("OnUpdate", function(_, elapsed)
		local open = ns.db.enabled and (not ns.db.collapsed or ns.inEditMode)
		local target = 1
		if open and ns.db.faint then
			local now = GetTime()
			if KeepChromeVisible() then lastHover = now end
			if now - lastHover > FAINT_DELAY then target = 0 end
		end
		local a = ns.chromeAlpha or 1
		if a == target then return end
		if target > a then
			a = math.min(target, a + elapsed / FAINT_FADE_IN)
		else
			a = math.max(target, a - elapsed / FAINT_FADE_OUT)
		end
		SetChromeAlpha(a)
	end)
	ns.faintFader = fader
end

function ns:ApplyFaint()
	-- Turning faint off (or on while hovered) snaps the chrome fully visible right away.
	if not ns.db.faint then SetChromeAlpha(1) end
end

---------------------------------------------------------------------------
-- Single-pass window layout & enable/collapse state machine
---------------------------------------------------------------------------
function ns:LayoutWindow()
	if not ns.db.enabled or not ns.anchor then return end
	local open = not ns.db.collapsed or ns.inEditMode
	ns:ApplyOwnedScale()
	if open then
		ns:PlaceSettings()
		ns:PlaceHeaderButtons()
		ns:SeatChat()
		ns:RefreshTabs()
	else
		ns:SeatChat()
		ns:SyncChatChrome("closed")
	end
end

function ns:ApplyEnabled()
	local on = ns.db.enabled and true or false
	local open = on and (not ns.db.collapsed or ns.inEditMode)
	local showTabs = open and (ns.db.showTabs ~= false)

	if ns.border then ns.border:SetShown(open) end
	if ns.fill then ns.fill:SetShown(open) end
	if ns.settingsBar then ns.settingsBar:SetShown(open) end
	if ns.tabsToggleButton then
		ns.tabsToggleButton:SetShown(open)
		if open then
			ResetButtonVisual(ns.tabsToggleButton)
			if ns.SyncTabsToggleButton then ns:SyncTabsToggleButton() end
		else
			ns.SetButtonPulse(ns.tabsToggleButton, false)
		end
	end
	if ns.chatSettingsButton then
		ns.chatSettingsButton:SetShown(open)
		if open then ResetButtonVisual(ns.chatSettingsButton) end
	end
	if ns.windowSettingsButton then
		ns.windowSettingsButton:SetShown(open)
		if open then ResetButtonVisual(ns.windowSettingsButton) end
	end
	if ns.closeButton then
		ns.closeButton:SetShown(open)
		if open then ResetButtonVisual(ns.closeButton) end
	end
	if ns.tabColumn then ns.tabColumn:SetShown(showTabs) end
	if ns.tabColumnFill then ns.tabColumnFill:SetShown(showTabs) end
	if ns.chatBox then ns.chatBox:SetShown(open) end
	if ns.chatBoxFill then ns.chatBoxFill:SetShown(open) end
	if ns.dragStrip then ns.dragStrip:SetShown(open) end
	if ns.messageWheel then ns.messageWheel:SetShown(open) end
	if ns.grips then
		for i = 1, #ns.grips do ns.grips[i]:SetShown(open) end
	end
	if ns.toggle then
		local showToggle = on and ns.db.collapsed and true or false
		ns.toggle:SetShown(showToggle)
		if showToggle then ResetButtonVisual(ns.toggle) end
	end
	if not showTabs and ns.tabs then
		for i = 1, #ns.tabs do ns.tabs[i]:Hide() end
	end

	if open then
		if ns.anchor and not ns.anchor:IsShown() then ns.anchor:Show() end
		ns:ApplyBackground()
		ns:LayoutWindow()
	elseif on then
		-- Seat while anchor has a valid rect, place the message-bubble open icon, then hide the anchor
		-- so the closed window's rectangle takes no mouse or wheel input.
		if ns.anchor and not ns.anchor:IsShown() then ns.anchor:Show() end
		ns:LayoutWindow()
		ns:PlaceToggle()
		if ns.anchor and not ns.inEditMode then ns.anchor:Hide() end
	else
		if ns.anchor then ns.anchor:Hide() end
		ns:ResetOwnedScale()
		ns:SyncChatChrome("restore")
		ns:PlaceHeaderButtons()
	end
end

function ns:SetCollapsed(collapsed)
	if collapsed and ns.CloseOwnedEditBoxes then
		ns:CloseOwnedEditBoxes()
	end
	ns.db.collapsed = collapsed and true or false
	if not collapsed then
		ns.SetButtonPulse(ns.toggle, false)
	end
	ns:ApplyEnabled()
end

---------------------------------------------------------------------------
-- Initialization, hooks, and UIParent watcher
---------------------------------------------------------------------------
function ns:Init()
	local anchor = CreateFrame("Frame", "DavesChatAnchor", UIParent)
	anchor:SetSize(ns.db.width, ns.db.height)
	anchor:SetClampedToScreen(true)
	ns.anchor = anchor

	BuildWindow(anchor)
	ns:InitEditMode(anchor)
	ns:HookChatAlerts()
	ns:HookChatFlickerGuards()
	ns:HookChatPositionGuards()
	ns:ApplyEnabled()
	StartFaintFader()

	-- Re-hide Blizzard's real tabs, recompute auto-fitted tab width, and refresh our list whenever the dock updates tabs.
	local updatingDockTabs = false
	if hooksecurefunc and type(FCFDock_UpdateTabs) == "function" then
		hooksecurefunc("FCFDock_UpdateTabs", function()
			if updatingDockTabs or not ns.db.enabled then return end
			updatingDockTabs = true
			ns:ApplyOwnedScale()
			if not ns.db.collapsed or ns.inEditMode then
				ns:SeatChat()
				ns:RefreshTabs()
			else
				ns:SeatChat()
			end
			updatingDockTabs = false
		end)
	end

	-- Exit Edit Mode and specialization changes call UpdateLayoutInfo without firing
	-- EDIT_MODE_LAYOUTS_UPDATED, resetting ChatFrame1's anchor. Reseat synchronously before draw.
	if EditModeManagerFrame and hooksecurefunc then
		local function ReseatAfterEditMode()
			if not ns.db or not ns.db.enabled then return end
			ns:LayoutWindow()
			if not anchor:GetCenter() then
				ns.Defer(function() ns:LayoutWindow() end)
			end
		end
		hooksecurefunc(EditModeManagerFrame, "UpdateLayoutInfo", ReseatAfterEditMode)
		if type(EditModeManagerFrame.ExitEditMode) == "function" then
			hooksecurefunc(EditModeManagerFrame, "ExitEditMode", ReseatAfterEditMode)
		end
		if type(EditModeManagerFrame.RevertAllChanges) == "function" then
			hooksecurefunc(EditModeManagerFrame, "RevertAllChanges", ReseatAfterEditMode)
		end
	end

	-- Follow the anchor while dragged (the anchor's own OnUpdate belongs to Edit Mode),
	-- and catch any unhooked ChatFrame1 drift before the frame renders.
	-- Parented to UIParent so it keeps watching while the window is collapsed.
	local seatX, seatY, seatW, seatH
	local watcher = CreateFrame("Frame", nil, UIParent)
	watcher:SetScript("OnUpdate", function()
		if not ns.db.enabled then return end
		if ns.db.collapsed and not ns.inEditMode then
			if ns.DockEditFocused() then
				ns:SetCollapsed(false)
				return
			end
			if not ns:IsChatSeated() then
				ns:SeatChat()
			else
				ns:EnforceOwnedChrome()
			end
			return
		end

		ns:EnforceOwnedChrome()
		if (ns.FriendsWanted() and not ns.friendsX) or (ns.TtsWanted() ~= ns.seenTtsWanted) then
			ns:LayoutWindow()
		elseif ns:FriendsDrifted() then
			ns:PinHeaderIcons()
		end

		local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
		if selected ~= ns.seenTab then
			ns.seenTab = selected
			ns:RefreshTabs()
		end

		local x, y = anchor:GetCenter()
		if not x then return end
		local w, h = math.floor(anchor:GetWidth()), math.floor(anchor:GetHeight())
		local fx, fy = math.floor(x), math.floor(y)
		if fx == seatX and fy == seatY and w == seatW and h == seatH and ns:IsChatSeated() then return end
		local sizeChanged = (w ~= seatW) or (h ~= seatH)
		seatX, seatY, seatW, seatH = fx, fy, w, h
		if sizeChanged then
			ns:LayoutWindow()
		else
			ns:ApplyOwnedScale()
			ns:SeatChat()
		end
	end)

	ns.events:RegisterEvent("UPDATE_CHAT_WINDOWS")
	ns.events:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
	ns.events:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	ns.events:RegisterEvent("DISPLAY_SIZE_CHANGED")
	ns.events:RegisterEvent("UI_SCALE_CHANGED")
	ns.events:RegisterEvent("PLAYER_REGEN_ENABLED")
	ns.events:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
	ns.events:RegisterEvent("CHANNEL_UI_UPDATE")
	ns.events:RegisterEvent("CHAT_MSG_WHISPER")
	ns.events:RegisterEvent("CHAT_MSG_BN_WHISPER")
	-- GLOBAL_MOUSE_DOWN is Mainline/Forever; skip it where the client does not know the event.
	local validate = C_EventUtils and C_EventUtils.IsEventValid
	if validate then
		if validate("GLOBAL_MOUSE_DOWN") then ns.events:RegisterEvent("GLOBAL_MOUSE_DOWN") end
	else
		pcall(ns.events.RegisterEvent, ns.events, "GLOBAL_MOUSE_DOWN")
	end

	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			ns.inEditMode = true
			ns:ApplyEnabled()
		end, ns)
		EventRegistry:RegisterCallback("EditMode.Exit", function()
			ns.inEditMode = false
			ns:ApplyEnabled()
		end, ns)
		-- IM style leaves the edit box shown; only an actual focus opens a closed window.
		EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusGained", function(_, editBox)
			if not ns.db.enabled then return end
			local frame = editBox and editBox.chatFrame
			if frame and frame ~= ChatFrame1 and not frame.isDocked then return end
			if not frame and editBox ~= (ChatFrame1 and ChatFrame1.editBox) then return end
			if editBox and editBox.EnableMouse then editBox:EnableMouse(true) end
			if ns.db.collapsed then
				ns:SetCollapsed(false)
			end
		end, ns)
	end
end
