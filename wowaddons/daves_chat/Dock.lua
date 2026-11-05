-- daves_chat / Dock.lua
-- Seats Blizzard's chat dock inside our inner chat-text frame beside the left tab stack,
-- applies the chosen text direction (stock bottom-up by default, or newest on top), scales owned frames,
-- and synchronizes chat chrome across open, closed, and restored states without flicker.
-- We never SetParent, HookScript, SetScript, or UnregisterEvent on a chat frame.

local _, ns = ...

local TOP_EDGE = 12      -- top border inset above the header bar (clears the 11px top metal rail)
local HEADER_GAP = 8     -- breathing room below the header divider
local EDGE = 20          -- comfortable side margin inside the outer dialog border (11px metal + 9px margin)
local COL_GAP = 10       -- gap between left tab column and inner chat frame when tabs are shown
local BOTTOM_TAB = 19    -- bottom of left tab list (8px above the 11px inner dialog border lip)
local BOTTOM_BOX = 51    -- bottom of inner chat frame (leaves equal 8px above & 8px below visible editBox)
local BOX_INSET_L = 12   -- comfortable left text margin inside ns.chatBox
local BOX_INSET_R = 24   -- right gutter inside ns.chatBox for MinimalScrollBar + margin (6 + 8 + 10)
local BOX_INSET_T = 10   -- top text padding inside ns.chatBox (fits CombatLogQuickButtonFrame +3px offset)
local BOX_INSET_B = 10   -- bottom text padding inside ns.chatBox
local EDIT_PAD_X = 5     -- transparent left/right padding inside UI-ChatInputBorder-Left2 / Right2
local EDIT_OFFSET_Y = 4  -- editBox frame top below ns.chatBox (32px frame has 4px top/bottom margin -> 8px visual gap)

local TOP_INSERT = SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP or "TOP"
local BOTTOM_INSERT = SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM or "BOTTOM"

ns.TOP_EDGE = TOP_EDGE
ns.EDGE = EDGE

-- Tracks frames we have styled so any frame later undocked gets its Blizzard chrome and insert mode restored.
local ownedFrames = {}
local lastSeatedWidth
local seating = false
local seatedLeft, seatedBottom, seatedW, seatedH

local function IsBlizzardChatBeingEdited()
	if not (EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive()) then
		return false
	end
	local chat = ChatFrame1
	if not chat then return false end
	if chat.isDragging or MOVING_CHATFRAME == chat then return true end
	local resizeBtn = chat.EditModeResizeButton
	if resizeBtn and resizeBtn.GetButtonState and resizeBtn:GetButtonState() == "PUSHED" then return true end
	return false
end

function ns:IsChatSeated()
	if IsBlizzardChatBeingEdited() then return true end
	local anchor, chat = ns.anchor, ChatFrame1
	if not anchor or not chat or not seatedW or not seatedH then return false end
	local point, rel, relPoint, x, y = chat:GetPoint(1)
	if point ~= "BOTTOMLEFT" or rel ~= anchor or relPoint ~= "BOTTOMLEFT" then
		return false
	end
	if math.abs((x or 0) - seatedLeft) > 0.5 or math.abs((y or 0) - seatedBottom) > 0.5 then
		return false
	end
	if math.abs((chat:GetWidth() or 0) - seatedW) > 0.5 or math.abs((chat:GetHeight() or 0) - seatedH) > 0.5 then
		return false
	end
	local wantScale = ns.Clamp((ns.db and ns.db.scale) or 1, 0.5, 2)
	if math.abs((chat:GetScale() or 1) - wantScale) > 0.005 then
		return false
	end
	local dockedOk = true
	ns.EachDocked(function(frame)
		if dockedOk and frame ~= chat then
			local _, dockRel = frame:GetPoint(1)
			if dockRel ~= chat then dockedOk = false end
		end
	end)
	return dockedOk
end

function ns:ContentTop()
	local barH = (ns.settingsBar and ns.settingsBar:GetHeight()) or 34
	return TOP_EDGE + barH + HEADER_GAP
end

function ns:MinFrameHeight()
	return math.max(ns.MIN_HEIGHT, math.ceil(ns:ContentTop() + BOTTOM_BOX + BOX_INSET_T + BOX_INSET_B + 48))
end

-- Visits each docked chat frame once (FCFDock_GetChatFrames already includes ChatFrame1).
function ns.EachDocked(fn)
	local seenPrimary = false
	if GENERAL_CHAT_DOCK and FCFDock_GetChatFrames then
		for _, frame in ipairs(FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)) do
			if frame == ChatFrame1 then seenPrimary = true end
			fn(frame)
		end
	end
	if not seenPrimary and ChatFrame1 then
		fn(ChatFrame1)
	end
end

local function EachTrackedOrDocked(fn)
	local visited = {}
	ns.EachDocked(function(frame)
		visited[frame] = true
		fn(frame, frame == ChatFrame1 or (frame.isDocked and true or false))
	end)
	for frame in pairs(ownedFrames) do
		if not visited[frame] then
			fn(frame, frame == ChatFrame1 or (frame.isDocked and true or false))
		end
	end
end

function ns.VisibleChatFrame()
	if GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow then
		local selected = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
		if selected then return selected end
	end
	return ChatFrame1
end

local function RegionShownAlpha(reg)
	if not reg or (issecretvalue and issecretvalue(reg)) or not reg.IsShown then return 0 end
	local shown = reg:IsShown()
	if issecretvalue and issecretvalue(shown) then return 1 end
	if not shown then return 0 end
	if not reg.GetAlpha then return 1 end
	local la = reg:GetAlpha()
	if issecretvalue and issecretvalue(la) then return 1 end
	return (type(la) == "number") and la or 1
end

local function IsFontStringRegion(reg)
	if not reg or (issecretvalue and issecretvalue(reg)) then return false end
	if not reg.GetObjectType then return true end
	local kind = reg:GetObjectType()
	if issecretvalue and issecretvalue(kind) then return true end
	return kind == "FontString"
end

local function MaxFontStringAlpha(...)
	local best = 0
	for i = 1, select("#", ...) do
		local reg = select(i, ...)
		if IsFontStringRegion(reg) then
			local la = RegionShownAlpha(reg)
			if la > best then
				best = la
				if best >= 0.999 then return 1 end
			end
		end
	end
	return ns.Clamp(best, 0, 1)
end

-- Returns the highest visible-line alpha [0..1] on the currently selected chat frame without
-- reading secret message strings or touching CircularBuffer, so Faint mode's frosted-glass pane
-- fades cleanly down to 0 when all chat lines have faded out and returns as soon as a new message
-- (or scroll/tab activity) brings text back onto the screen.
function ns.ActiveChatTextAlpha()
	local chat = ns.VisibleChatFrame()
	if not chat then return 1 end
	local lines = chat.visibleLines
	if type(lines) == "table" then
		local best = 0
		for i = 1, #lines do
			local la = RegionShownAlpha(lines[i])
			if la > best then
				best = la
				if best >= 0.999 then return 1 end
			end
		end
		return ns.Clamp(best, 0, 1)
	end
	local container = chat.FontStringContainer
	if container and container.GetRegions then
		return MaxFontStringAlpha(container:GetRegions())
	end
	return 1
end

-- The wheel delta is positive when the wheel rolls up. Bottom-insert chat scrolls up on a
-- positive amount; top-insert flips that, matching ScrollUtil.InitScrollingMessageFrameWithScrollBar
-- (ScrollUtil.lua:198-200) so wheel-down scrolls down toward older messages.
function ns.ScrollFrameByWheel(frame, delta)
	if not frame or not delta or delta == 0 then return end
	local amount = delta
	if frame.GetInsertMode and frame:GetInsertMode() == TOP_INSERT then
		amount = -amount
	end
	if frame.ScrollByAmount then
		frame:ScrollByAmount(amount * 3)
		return
	end
	if amount > 0 and frame.ScrollUp then
		frame:ScrollUp(); frame:ScrollUp(); frame:ScrollUp()
	elseif frame.ScrollDown then
		frame:ScrollDown(); frame:ScrollDown(); frame:ScrollDown()
	end
end

function ns.DockEditFocused()
	local focused = false
	ns.EachDocked(function(frame)
		if not focused and frame.editBox and frame.editBox.HasFocus and frame.editBox:HasFocus() then
			focused = true
		end
	end)
	return focused
end

local function HasEditText(edit)
	if not (edit and edit.GetText) then return false end
	local txt = edit:GetText()
	if txt == nil then return false end
	if issecretvalue and issecretvalue(txt) then return true end
	return txt ~= ""
end

local SyncEditBox -- defined below with the chrome helpers; used by ns:CloseOwnedEditBoxes(true)

-- Uses only C++ widget setters on ChatFrameEditBox so we never invoke ClearChat/DeactivateChat
-- -> SetChatType -> SetAttribute("chatType", ...), keeping C_ChatInfo.SendChatMessage untainted.
local function DeactivateSingleEditBox(edit)
	if not edit then return end
	if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(edit) end
	local hasFocus = edit.HasFocus and edit:HasFocus()
	local hasText = HasEditText(edit)
	if hasFocus then
		if not hasText and edit.SetText then
			-- Keep GetText() non-empty during ClearFocus() so OnEditFocusLost skips DeactivateChat.
			edit:SetText(" ")
			hasText = true
		end
		if edit.ClearFocus then edit:ClearFocus() end
	end
	if hasText and edit.SetText then
		edit:SetText("")
	end
	if AutoCompleteBox and AutoCompleteBox.IsShown and AutoCompleteBox:IsShown() and AutoCompleteBox.parent == edit then
		if AutoComplete_HideIfAttachedTo then
			AutoComplete_HideIfAttachedTo(edit)
		else
			AutoCompleteBox:Hide()
		end
	end
	if edit.SetFrameStrata then edit:SetFrameStrata("LOW") end
	if edit.header and edit.header.Hide then edit.header:Hide() end
	if edit.focusLeft and edit.focusLeft.Hide then edit.focusLeft:Hide() end
	if edit.focusMid and edit.focusMid.Hide then edit.focusMid:Hide() end
	if edit.focusRight and edit.focusRight.Hide then edit.focusRight:Hide() end
	local editName = edit.GetName and edit:GetName()
	local lang = editName and _G[editName .. "Language"]
	if lang and lang.Hide then lang:Hide() end
	if edit.SetAlpha then edit:SetAlpha(0) end
	if edit.EnableMouse then edit:EnableMouse(false) end
end

-- Cleans up unsent text, autocomplete popups, and keyboard focus on any owned/docked edit box.
-- keepOpen = false (X close): every edit box goes invisible with the window.
-- keepOpen = true (clicking header/tab/settings controls while the window stays open): the inactive
-- edit box returns to Blizzard's resting look (IM style 0.35 alpha, classic style hidden).
function ns:CloseOwnedEditBoxes(keepOpen)
	local cleaned = {}
	local function Clean(edit)
		cleaned[edit] = true
		DeactivateSingleEditBox(edit)
		if keepOpen and SyncEditBox then SyncEditBox(edit, false) end
	end
	local active = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
		or _G.ACTIVE_CHAT_EDIT_BOX
	if active then
		local owner = active.chatFrame or (active.GetParent and active:GetParent())
		if owner == ChatFrame1 or (owner and owner.isDocked) or ownedFrames[owner] then
			Clean(active)
		end
	end
	EachTrackedOrDocked(function(frame, isDocked)
		local edit = frame and frame.editBox
		if edit and not cleaned[edit] and (isDocked or ownedFrames[frame]) then
			Clean(edit)
		end
	end)
end

-- True while any owned edit box is focused or holds unsent text (i.e. it may be floating at DIALOG strata).
function ns:OwnedEditBoxActive()
	local active = false
	EachTrackedOrDocked(function(frame, isDocked)
		local edit = frame and frame.editBox
		if not active and edit and (isDocked or ownedFrames[frame]) then
			if (edit.HasFocus and edit:HasFocus()) or HasEditText(edit) then
				active = true
			end
		end
	end)
	return active
end

---------------------------------------------------------------------------
-- Text direction (ScrollingMessageFrameMixin:SetInsertMode)
---------------------------------------------------------------------------
-- SetInsertMode is an untainted secure barrier in ScrollingMessageFrame.lua:898-900 and marks the
-- layout dirty (ScrollingMessageFrame.lua:297-301), so switching re-lays out existing lines live.
-- "bottom" (default, stock WoW) keeps INSERT_MODE_BOTTOM. "top" uses INSERT_MODE_TOP, which anchors
-- visibleLines[1] (the newest line at scrollOffset 0) at TOPLEFT and grows older lines downward.
local function ApplyInsertMode(frame, own)
	if not frame or not frame.SetInsertMode then return end
	local top = own and ns.db and ns.db.textDirection == "top"
	local want = top and TOP_INSERT or BOTTOM_INSERT
	if not frame.GetInsertMode or frame:GetInsertMode() ~= want then
		frame:SetInsertMode(want)
	end
end

function ns:ApplyTextDirection()
	if not ns.db.enabled then return end
	ns.EachDocked(function(frame)
		if frame == ChatFrame1 or frame.isDocked then
			ApplyInsertMode(frame, true)
		end
	end)
end

---------------------------------------------------------------------------
-- Scaling
---------------------------------------------------------------------------
-- ChatFrame1's SetScale is Edit Mode's override, which rewrites offsets. SetScaleBase only changes scale.
local function SetOwnScale(frame, scale)
	if not frame or not frame.GetScale then return end
	local old = frame:GetScale() or 1
	if math.abs(old - scale) < 0.001 then return end
	if frame.SetScaleBase then frame:SetScaleBase(scale) else frame:SetScale(scale) end
end

local function ScaleFrameEditBox(frame, scale)
	local edit = frame and frame.editBox
	if not edit then return end
	-- ChatFrameEditBoxMixin:OnLoad (ChatFrameEditBox.lua:354) reparents editBox to UIParent,
	-- so it needs `scale` unless its parent is still `frame` (where `frame`'s scale already applies).
	local parent = edit.GetParent and edit:GetParent()
	SetOwnScale(edit, (parent == frame) and 1 or scale)
end

local function RestoreUnscaledRect(frame)
	local old = (frame and frame.GetScale and frame:GetScale()) or 1
	SetOwnScale(frame, 1)
	if math.abs(old - 1) > 0.001 then
		if frame.SetSize and frame.GetWidth and frame.GetHeight then
			frame:SetSize(frame:GetWidth() * old, frame:GetHeight() * old)
		end
		if frame.GetNumPoints and frame.GetPoint and frame.SetPoint then
			local n = frame:GetNumPoints()
			local pts = {}
			for i = 1, n do pts[i] = { frame:GetPoint(i) } end
			for i = 1, n do
				local point, rel, relPoint, x, y = pts[i][1], pts[i][2], pts[i][3], pts[i][4], pts[i][5]
				if point and x ~= nil and y ~= nil then
					frame:SetPoint(point, rel, relPoint, x * old, y * old)
				end
			end
		end
	end
	if frame and frame.editBox then SetOwnScale(frame.editBox, 1) end
end

function ns:ApplyOwnedScale()
	local s = ns.Clamp(ns.db.scale or 1, 0.5, 2)
	ns.db.scale = s
	if ns.anchor then SetOwnScale(ns.anchor, s) end
	if ns.fill then SetOwnScale(ns.fill, s) end
	if ns.frost then SetOwnScale(ns.frost, s) end
	EachTrackedOrDocked(function(frame, isDocked)
		if isDocked then
			ownedFrames[frame] = true
			SetOwnScale(frame, s)
			ScaleFrameEditBox(frame, s)
		elseif ownedFrames[frame] then
			SetOwnScale(frame, 1)
			if frame.editBox then SetOwnScale(frame.editBox, 1) end
		end
	end)
end

-- "Move the chat window" off. Leave the on-screen size where it is and drop our scale.
function ns:ResetOwnedScale()
	if ns.fill then SetOwnScale(ns.fill, 1) end
	if ns.frost then SetOwnScale(ns.frost, 1) end
	EachTrackedOrDocked(function(frame)
		RestoreUnscaledRect(frame)
	end)
end

function ns:ApplyScale()
	local s = ns.Clamp(ns.db.scale or 1, 0.5, 2)
	local anchor = ns.anchor
	local old = (anchor and anchor.GetScale and anchor:GetScale()) or 1
	if anchor and math.abs(old - s) > 0.001 then
		local point, _, relPoint, x, y = anchor:GetPoint(1)
		if point and x ~= nil and y ~= nil then
			ns.db.pos = { point = point, relPoint = relPoint, x = x * old / s, y = y * old / s }
		end
	end
	ns.db.scale = s
	ns:ApplyPosition()
	if ns.LayoutWindow then ns:LayoutWindow() end
end

---------------------------------------------------------------------------
-- Scrollbar & chat chrome synchronization ("open" | "closed" | "restore")
---------------------------------------------------------------------------
local function SuppressFrame(widget)
	if not widget then return end
	if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(widget) end
	if widget.SetAlpha then widget:SetAlpha(0) end
	if widget.IsShown and widget:IsShown() then widget:Hide() end
end

-- Places MinimalScrollBar centered inside ns.chatBox's 22px right gutter (+6px from chatFrame).
local function AnchorOwnedScroll(frame)
	if not frame or not frame.ScrollBar then return end
	SuppressFrame(frame.ScrollToBottomButton)
	if frame.ResizeButton and frame.ResizeButton:IsShown() then frame.ResizeButton:Hide() end
	local bar = frame.ScrollBar
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 6, 0)
end

-- Anchors editBox directly beneath ns.chatBox (independent of MinimalScrollBar visibility/width)
-- so its visible metal border aligns flush left-to-right with ns.chatBox and keeps equal 8px
-- visual margins above (to ns.chatBox) and below (to the outer dialog border's inner lip).
local function AnchorOwnedEditBox(frame)
	local edit = frame and frame.editBox
	if not edit or not ns.chatBox then return end
	edit:ClearAllPoints()
	edit:SetPoint("TOPLEFT", ns.chatBox, "BOTTOMLEFT", -EDIT_PAD_X, -EDIT_OFFSET_Y)
	edit:SetPoint("TOPRIGHT", ns.chatBox, "BOTTOMRIGHT", EDIT_PAD_X, -EDIT_OFFSET_Y)
end

-- Restores Blizzard's default XML anchors (FloatingChatFrame.xml:558-559) when unowned/undocked.
local function RestoreEditBoxAnchor(frame)
	local edit = frame and frame.editBox
	if not edit or not frame then return end
	edit:ClearAllPoints()
	edit:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -5, -2)
	if frame.ScrollBar then
		edit:SetPoint("RIGHT", frame.ScrollBar, "RIGHT", 8, 0)
	else
		edit:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 5, -2)
	end
end

-- MinimalScrollBar enables mouse on its child Track, Thumb, Back, and Forward frames.
local function SetScrollBarInteractive(bar, interactive)
	if not bar then return end
	local on = interactive and true or false
	if bar.EnableMouse then bar:EnableMouse(on) end
	if bar.Back and bar.Back.EnableMouse then bar.Back:EnableMouse(on) end
	if bar.Forward and bar.Forward.EnableMouse then bar.Forward:EnableMouse(on) end
	local track = bar.Track
	if track then
		if track.EnableMouse then track:EnableMouse(on) end
		if track.Thumb and track.Thumb.EnableMouse then track.Thumb:EnableMouse(on) end
	end
end

local function ShowOwnedScroll(frame)
	if not frame or not frame.IsShown or not frame:IsShown() then return end
	local bar = frame.ScrollBar
	if not bar or not bar.GetAlpha or not bar.SetAlpha then return end
	if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(bar) end
	-- ns.chromeAlpha (Window.lua faint fader) is 1 normally and fades to 0 while the window isn't hovered.
	local want = 0.65 * (ns.chromeAlpha or 1)
	if math.abs((bar:GetAlpha() or 0) - want) > 0.01 then
		bar:SetAlpha(want)
	end
end

local function HideOwnedScroll(frame)
	local bar = frame and frame.ScrollBar
	if not bar then return end
	if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(bar) end
	if bar.GetAlpha and bar.SetAlpha and (bar:GetAlpha() or 0) > 0 then
		bar:SetAlpha(0)
	end
end

SyncEditBox = function(edit, closed)
	if not edit then return end
	if closed then
		if edit.HasFocus and edit:HasFocus() then return end
		if edit.GetAlpha and (edit:GetAlpha() or 0) > 0 then edit:SetAlpha(0) end
		if edit.EnableMouse then edit:EnableMouse(false) end
	else
		local focused = edit.HasFocus and edit:HasFocus()
		local isVoice = ChatFrame3 ~= nil and (edit.chatFrame == ChatFrame3)
		local classicInactive = (not focused) and (not isVoice) and (not edit.isGM)
			and (GetCVar and GetCVar("chatStyle") == "classic")
			and (not HasEditText(edit))
		if classicInactive then
			if edit.GetAlpha and (edit:GetAlpha() or 0) > 0 then edit:SetAlpha(0) end
			if edit.EnableMouse then edit:EnableMouse(false) end
			return
		end
		if edit.EnableMouse then edit:EnableMouse(true) end
		if focused then
			edit:SetAlpha(1)
		elseif edit.IsShown and edit:IsShown() and edit.GetAlpha and not HasEditText(edit) then
			-- ChatFrameEditBoxMixin:Deactivate (ChatFrameEditBox.lua:568) uses 0.35 in IM style;
			-- faint mode scales that resting alpha down with the rest of the window chrome.
			local want = 0.35 * (ns.chromeAlpha or 1)
			if math.abs((edit:GetAlpha() or 0) - want) > 0.01 then edit:SetAlpha(want) end
		end
	end
end

-- Re-applies scrollbar and resting edit-box alpha for the current ns.chromeAlpha (faint fader).
function ns:ApplyOwnedChromeAlpha()
	if not ns.db.enabled or (ns.db.collapsed and not ns.inEditMode) then return end
	ns.EachDocked(function(frame)
		if frame == ChatFrame1 or frame.isDocked then
			ShowOwnedScroll(frame)
			SyncEditBox(frame.editBox, false)
		end
	end)
end

-- CombatLogQuickButtonFrame_Custom is parented to ChatFrame2Tab (Blizzard_CombatLog.lua:1443).
-- Reparent it to our anchor while we hide ChatFrame2Tab so the Combat Log filter row stays visible.
local function SyncCombatLogQuickBar(ownCombatLog, closed)
	local quick = _G.CombatLogQuickButtonFrame_Custom
	if not quick then return end
	if ownCombatLog and ns.anchor then
		if quick:GetParent() ~= ns.anchor then
			quick:SetParent(ns.anchor)
			quick:SetFrameStrata("MEDIUM")
		end
		quick:SetAlpha(1)
		quick:SetShown((not closed) and ChatFrame2 ~= nil and ChatFrame2:IsShown())
	elseif ChatFrame2Tab and quick:GetParent() == ns.anchor then
		quick:SetParent(ChatFrame2Tab)
		quick:SetFrameStrata("MEDIUM")
		quick:SetShown(ChatFrame2 ~= nil and ChatFrame2:IsShown())
	end
end

local function SetSideButtonHidden(button, hide)
	if not button then return end
	local targetAlpha = hide and 0 or 1
	if not button.GetAlpha or button:GetAlpha() ~= targetAlpha then
		button:SetAlpha(targetAlpha)
	end
	if button.EnableMouse then button:EnableMouse(not hide) end
end

-- Synchronizes all docked (and any recently undocked) chat frames for:
--   "open"    : addon enabled and window shown (or in Edit Mode)
--   "closed"  : addon enabled and collapsed to the Chat button
--   "restore" : addon disabled ("Move the chat window" off)
function ns:SyncChatChrome(mode)
	local restoring = (mode == "restore")
	local closed = (mode == "closed")
	local cvarWheel = not GetCVarBool or GetCVarBool("chatMouseScroll")

	EachTrackedOrDocked(function(frame, isDocked)
		local own = not restoring and isDocked
		if own then
			ownedFrames[frame] = true
		else
			ownedFrames[frame] = nil
		end

		ApplyInsertMode(frame, own)

		local name = frame.GetName and frame:GetName()
		if name and CHAT_FRAME_TEXTURES then
			for i = 1, #CHAT_FRAME_TEXTURES do
				local tex = _G[name .. CHAT_FRAME_TEXTURES[i]]
				if tex then tex:SetShown(not own) end
			end
		end
		if frame.buttonFrame then frame.buttonFrame:SetShown(not own) end

		if own then
			AnchorOwnedScroll(frame)
			AnchorOwnedEditBox(frame)
		else
			RestoreEditBoxAnchor(frame)
			if frame.ScrollToBottomButton and frame.ScrollToBottomButton.SetAlpha then
				frame.ScrollToBottomButton:SetAlpha(1)
			end
			if FCF_UpdateResizeButton then FCF_UpdateResizeButton(frame) end
		end

		-- FloatingChatFrameTemplate keeps enableMouse="false" so 3D camera clicks pass through
		-- empty chat space, using SetHyperlinksEnabled for links (FloatingChatFrame.xml:443).
		if frame.EnableMouse then frame:EnableMouse(false) end
		if frame.SetHyperlinksEnabled and not frame.overrideHyperlinksEnabled then
			frame:SetHyperlinksEnabled((not closed) and (not frame.isUninteractable))
		end
		if frame.EnableMouseWheel then
			frame:EnableMouseWheel((not closed) and cvarWheel)
		end
		if frame.clickAnywhereButton and frame.clickAnywhereButton.EnableMouse then
			frame.clickAnywhereButton:EnableMouse(not closed)
		end

		frame:SetAlpha((own and closed) and 0 or 1)
		SetScrollBarInteractive(frame.ScrollBar, not (own and closed))
		if own then
			if closed then HideOwnedScroll(frame) else ShowOwnedScroll(frame) end
		end
		SyncEditBox(frame.editBox, own and closed)

		local tab = name and _G[name .. "Tab"]
		if tab then
			if own then
				SuppressFrame(tab)
			else
				tab:SetAlpha(1)
				tab:Show()
			end
		end
	end)

	local ownCombatLog = (not restoring) and ChatFrame2 ~= nil and (ChatFrame2.isDocked and true or false)
	SyncCombatLogQuickBar(ownCombatLog, closed)

	-- Keep GENERAL_CHAT_DOCK at alpha 0 whenever owned so Blizzard's FCF_StartAlertFlash and
	-- FCF_FadeInChatFrame never flash hidden tabs or overflow glows for 1 frame on new messages.
	if GENERAL_CHAT_DOCK then
		if restoring then
			seatedLeft, seatedBottom, seatedW, seatedH, lastSeatedWidth = nil, nil, nil, nil, nil
			if ChatFrame1 and ChatFrame1.IsInitialized and ChatFrame1:IsInitialized()
				and not (ChatFrame1.IsProtected and ChatFrame1:IsProtected() and InCombatLockdown()) then
				if ChatFrame1.ApplySystemAnchor then ChatFrame1:ApplySystemAnchor() end
				if ChatFrame1.UpdateSystemSettingWidth then ChatFrame1:UpdateSystemSettingWidth() end
				if ChatFrame1.UpdateSystemSettingHeight then ChatFrame1:UpdateSystemSettingHeight() end
			end
			GENERAL_CHAT_DOCK:SetShown(true)
			GENERAL_CHAT_DOCK:SetAlpha(1)
			if FCF_DockUpdate then FCF_DockUpdate() end
		elseif closed then
			GENERAL_CHAT_DOCK:SetAlpha(0)
			GENERAL_CHAT_DOCK:Hide()
		else
			GENERAL_CHAT_DOCK:SetShown(true)
			GENERAL_CHAT_DOCK:SetAlpha(0)
			SuppressFrame(GENERAL_CHAT_DOCK.overflowButton)
		end
	end

	if ChatFrameMenuButton then ChatFrameMenuButton:SetShown(restoring) end
	SetSideButtonHidden(ChatFrameToggleVoiceDeafenButton, not restoring)
	SetSideButtonHidden(ChatFrameToggleVoiceMuteButton, not restoring)
end

-- Lightweight per-frame guard that only mutates properties if Blizzard re-showed a tab,
-- faded a scrollbar, reset insert mode, or woke a frame while closed.
function ns:EnforceOwnedChrome()
	if not ns.db.enabled then return end
	local closed = ns.db.collapsed and not ns.inEditMode
	ns.EachDocked(function(frame)
		local own = frame == ChatFrame1 or frame.isDocked
		if not own then return end
		ownedFrames[frame] = true
		ApplyInsertMode(frame, true)
		local name = frame.GetName and frame:GetName()
		local tab = name and _G[name .. "Tab"]
		if tab and tab.IsShown and tab:IsShown() then
			SuppressFrame(tab)
		end
		if frame.ScrollToBottomButton and frame.ScrollToBottomButton:IsShown() then
			AnchorOwnedScroll(frame)
		end
		if frame.editBox and ns.chatBox then
			local _, editRel = frame.editBox:GetPoint(1)
			if editRel ~= ns.chatBox then
				AnchorOwnedEditBox(frame)
			end
		end
		if closed then
			if frame.GetAlpha and (frame:GetAlpha() or 0) > 0 then frame:SetAlpha(0) end
			if frame.EnableMouse then frame:EnableMouse(false) end
			if frame.EnableMouseWheel then frame:EnableMouseWheel(false) end
			if frame.SetHyperlinksEnabled and not frame.overrideHyperlinksEnabled then
				frame:SetHyperlinksEnabled(false)
			end
			if frame.clickAnywhereButton and frame.clickAnywhereButton.EnableMouse then
				frame.clickAnywhereButton:EnableMouse(false)
			end
			SetScrollBarInteractive(frame.ScrollBar, false)
			HideOwnedScroll(frame)
			SyncEditBox(frame.editBox, true)
		else
			ShowOwnedScroll(frame)
		end
	end)
	SyncCombatLogQuickBar(ChatFrame2 ~= nil and (ChatFrame2.isDocked and true or false), closed)
	if GENERAL_CHAT_DOCK then
		if (GENERAL_CHAT_DOCK:GetAlpha() or 0) > 0 then GENERAL_CHAT_DOCK:SetAlpha(0) end
		if closed then
			if GENERAL_CHAT_DOCK:IsShown() then GENERAL_CHAT_DOCK:Hide() end
		elseif GENERAL_CHAT_DOCK.overflowButton and GENERAL_CHAT_DOCK.overflowButton:IsShown() then
			SuppressFrame(GENERAL_CHAT_DOCK.overflowButton)
		end
	end
	if ChatFrameMenuButton and ChatFrameMenuButton:IsShown() then ChatFrameMenuButton:Hide() end
	SetSideButtonHidden(ChatFrameToggleVoiceDeafenButton, true)
	SetSideButtonHidden(ChatFrameToggleVoiceMuteButton, true)
end

-- Synchronous post-hooks on Blizzard's per-message fade/alert helpers so neither tabs,
-- ScrollToBottomButton, nor ScrollBar alpha flicker for a single frame when new text arrives.
function ns:HookChatFlickerGuards()
	if not hooksecurefunc then return end

	local function ClampOwnedScrollbar(chatFrame)
		if not ns.db.enabled or not chatFrame or not ownedFrames[chatFrame] then return end
		SuppressFrame(chatFrame.ScrollToBottomButton)
		local closed = ns.db.collapsed and not ns.inEditMode
		if closed then HideOwnedScroll(chatFrame) else ShowOwnedScroll(chatFrame) end
	end

	local function ClampOwnedTab(chatFrame, refreshStack)
		if not ns.db.enabled or not chatFrame then return end
		if chatFrame ~= ChatFrame1 and not chatFrame.isDocked and not ownedFrames[chatFrame] then return end
		local name = chatFrame.GetName and chatFrame:GetName()
		local tab = name and _G[name .. "Tab"]
		if tab then SuppressFrame(tab) end
		if GENERAL_CHAT_DOCK then
			GENERAL_CHAT_DOCK:SetAlpha(0)
			SuppressFrame(GENERAL_CHAT_DOCK.overflowButton)
		end
		if refreshStack and ns.RefreshTabs and (not ns.db.collapsed or ns.inEditMode) then
			ns:RefreshTabs()
		end
	end

	if type(FCF_FadeInScrollbar) == "function" then
		hooksecurefunc("FCF_FadeInScrollbar", ClampOwnedScrollbar)
	end
	if type(FCF_FadeOutScrollbar) == "function" then
		hooksecurefunc("FCF_FadeOutScrollbar", ClampOwnedScrollbar)
	end
	if type(FCF_FadeInChatFrame) == "function" then
		hooksecurefunc("FCF_FadeInChatFrame", function(chatFrame) ClampOwnedTab(chatFrame, false) end)
	end
	if type(FCF_FadeOutChatFrame) == "function" then
		hooksecurefunc("FCF_FadeOutChatFrame", function(chatFrame) ClampOwnedTab(chatFrame, false) end)
	end
	if type(FCF_StartAlertFlash) == "function" then
		hooksecurefunc("FCF_StartAlertFlash", function(chatFrame) ClampOwnedTab(chatFrame, true) end)
	end
	if type(FCF_StopAlertFlash) == "function" then
		hooksecurefunc("FCF_StopAlertFlash", function(chatFrame) ClampOwnedTab(chatFrame, true) end)
	end
end

-- Synchronous post-hooks on every Blizzard Edit Mode and FloatingChatFrame anchor/size writer
-- so ChatFrame1 and docked tabs are reseated in the same Lua call stack BEFORE ScrollingMessageFrame
-- lays out lines in OnPostUpdate and BEFORE WoW draws a single frame at Blizzard's chat position.
function ns:HookChatPositionGuards()
	if not hooksecurefunc then return end

	local function ReseatNow()
		if seating or not ns.db or not ns.db.enabled then return end
		if IsBlizzardChatBeingEdited() then return end
		if not ns:IsChatSeated() then
			ns:ApplyOwnedScale()
			ns:SeatChat()
		else
			ns:EnforceOwnedChrome()
		end
	end

	local chat = ChatFrame1
	if chat then
		local chatMethods = {
			"ApplySystemAnchor",
			"UpdateSystem",
			"UpdateSystemSettingWidth",
			"UpdateSystemSettingHeight",
			"SetPoint",
			"SetScale",
		}
		for i = 1, #chatMethods do
			local method = chatMethods[i]
			if type(rawget(chat, method)) == "function" then
				hooksecurefunc(chat, method, ReseatNow)
			end
		end
	end

	if type(FloatingChatFrame_Update) == "function" then
		hooksecurefunc("FloatingChatFrame_Update", ReseatNow)
	end
	if type(FCF_RestorePositionAndDimensions) == "function" then
		hooksecurefunc("FCF_RestorePositionAndDimensions", ReseatNow)
	end
	if type(FCF_DockUpdate) == "function" then
		hooksecurefunc("FCF_DockUpdate", ReseatNow)
	end
	if type(FCFDock_ForceReanchoring) == "function" then
		hooksecurefunc("FCFDock_ForceReanchoring", ReseatNow)
	end
end

-- Seats the left tab column, inner chat frame (ns.chatBox), and ChatFrame1 inside our anchor.
-- Docked tabs copy ChatFrame1's rect (and Combat Log offsets its top down by 24px for its quickbar).
function ns:SeatChat()
	if seating or IsBlizzardChatBeingEdited() then return end
	local anchor, chat = ns.anchor, ChatFrame1
	if not anchor or not chat or not ns.db.enabled then return end
	if chat.IsProtected and chat:IsProtected() and InCombatLockdown() then return end
	local closed = ns.db.collapsed and not ns.inEditMode
	if not anchor:GetCenter() then
		ns:SyncChatChrome(closed and "closed" or "open")
		return
	end

	seating = true

	local need = ns:MinFrameHeight()
	if anchor:GetHeight() < need then
		ns.db.height = need
		anchor:SetHeight(need)
		if ns.editDialog and ns.editDialog.IsShown and ns.editDialog:IsShown() and ns.editDialog.RefreshValues then
			ns.editDialog:RefreshValues()
		end
	end

	local top = ns:ContentTop()
	local showTabs = (not closed) and (ns.db.showTabs ~= false)
	local tabAvailH = math.max(48, anchor:GetHeight() - top - BOTTOM_TAB - 8)
	local tabW = 0
	if showTabs then
		if ns.ComputeTabColumnWidth then
			tabW = ns:ComputeTabColumnWidth(anchor:GetWidth(), tabAvailH)
		else
			tabW = ns.TAB_WIDTH or 96
		end
	end
	local boxLeft = (showTabs and tabW > 0) and (EDGE + tabW + COL_GAP) or EDGE

	if ns.tabColumn then
		if showTabs and tabW > 0 then
			ns.tabColumn:ClearAllPoints()
			ns.tabColumn:SetPoint("TOPLEFT", anchor, "TOPLEFT", EDGE, -top)
			ns.tabColumn:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", EDGE, BOTTOM_TAB)
			ns.tabColumn:SetWidth(tabW)
			ns.tabColumn:Show()
		else
			ns.tabColumn:Hide()
		end
	end
	if ns.tabColumnFill then
		ns.tabColumnFill:SetShown(showTabs and tabW > 0)
	end

	if ns.chatBox then
		ns.chatBox:ClearAllPoints()
		ns.chatBox:SetPoint("TOPLEFT", anchor, "TOPLEFT", boxLeft, -top)
		ns.chatBox:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -EDGE, BOTTOM_BOX)
		ns.chatBox:SetShown(not closed)
	end
	if ns.chatBoxFill then
		ns.chatBoxFill:SetShown(not closed)
	end

	local chatLeft = boxLeft + BOX_INSET_L
	local chatRight = EDGE + BOX_INSET_R
	local chatBottom = BOTTOM_BOX + BOX_INSET_B
	local chatTop = top + BOX_INSET_T
	local width = math.max(48, anchor:GetWidth() - chatLeft - chatRight)
	local height = math.max(24, anchor:GetHeight() - chatTop - chatBottom)

	-- Use Base anchor methods (EditModeSystemTemplates.lua:13-17) so seating never invokes
	-- SetPointOverride -> SetSnappedToFrame(anchor) or OnEditModeSystemAnchorChanged.
	if chat.ClearAllPointsBase then chat:ClearAllPointsBase() else chat:ClearAllPoints() end
	if chat.SetPointBase then
		chat:SetPointBase("BOTTOMLEFT", anchor, "BOTTOMLEFT", chatLeft, chatBottom)
	else
		chat:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", chatLeft, chatBottom)
	end
	chat:SetSize(width, height)
	seatedLeft, seatedBottom, seatedW, seatedH = chatLeft, chatBottom, width, height

	local dockDrifted = false
	ns.EachDocked(function(frame)
		if frame ~= chat then
			local _, rel = frame:GetPoint(1)
			if rel ~= chat then dockDrifted = true end
		end
	end)
	if dockDrifted then
		if FCFDock_ForceReanchoring and GENERAL_CHAT_DOCK then
			FCFDock_ForceReanchoring(GENERAL_CHAT_DOCK)
		end
		if FCF_DockUpdate then FCF_DockUpdate() end
	end

	if width ~= lastSeatedWidth then
		lastSeatedWidth = width
		if ChatFrame2 and ChatFrame2.isDocked and type(Blizzard_CombatLog_Update_QuickButtons) == "function" then
			Blizzard_CombatLog_Update_QuickButtons()
		end
	end

	if ns.messageWheel then
		ns.messageWheel:ClearAllPoints()
		ns.messageWheel:SetPoint("TOPLEFT", anchor, "TOPLEFT", boxLeft, -top)
		ns.messageWheel:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -EDGE, BOTTOM_BOX)
		ns.messageWheel:SetShown(not closed)
	end

	ns:SyncChatChrome(closed and "closed" or "open")
	seating = false
end

local function LayoutNowWithFallback()
	if not ns.db or not ns.db.enabled then return end
	if ns.LayoutWindow then ns:LayoutWindow() end
	if ns.anchor and not ns.anchor:GetCenter() then
		ns.Defer(function()
			if ns.LayoutWindow then ns:LayoutWindow() end
		end)
	end
end

function ns:EDIT_MODE_LAYOUTS_UPDATED()
	LayoutNowWithFallback()
end

function ns:UPDATE_FLOATING_CHAT_WINDOWS()
	LayoutNowWithFallback()
end

function ns:DISPLAY_SIZE_CHANGED()
	LayoutNowWithFallback()
end

function ns:UI_SCALE_CHANGED()
	LayoutNowWithFallback()
end

function ns:PLAYER_REGEN_ENABLED()
	if ns.db and ns.db.enabled and not ns:IsChatSeated() and ns.LayoutWindow then
		ns:LayoutWindow()
	end
end
