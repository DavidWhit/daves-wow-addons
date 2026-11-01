-- daves_chat / Tabs.lua
-- Default three-tab chat layout (Chat, Combat Log, General), numbered channel routing,
-- and the clean, scrollable left-side chat tab list inside the main window frame.

local _, ns = ...

-- Tab 1. Instance chat is party chat inside an instance.
local CHAT_GROUPS = {
	"SAY", "EMOTE",
	"PARTY", "PARTY_LEADER",
	"INSTANCE_CHAT", "INSTANCE_CHAT_LEADER",
	"WHISPER", "BN_WHISPER", "BN_INLINE_TOAST_ALERT",
}

-- Tab 3. Loot and the other non-combat lines live here so removing them from tab 1 does not drop them.
-- ChatFrame3 is Blizzard's voice transcription window, so General is ChatFrame4.
local GENERAL_GROUPS = {
	"YELL",
	"GUILD", "OFFICER", "GUILD_DISCORD",
	"RAID", "RAID_LEADER", "RAID_WARNING",
	"CHANNEL", "COMMUNITIES_CHANNEL",
	"MONSTER_SAY", "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_WHISPER",
	"MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER",
	"LOOT", "MONEY", "CURRENCY", "OPENING", "SKILL", "TRADESKILLS",
	"PET_INFO", "ACHIEVEMENT", "COLLECTED_APPEARANCE",
	"COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "COMBAT_MISC_INFO",
	"ERRORS", "IGNORED",
	"BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL",
	"TARGETICONS",
	-- Mainline groups (ChatTypeInfoConstantsOverride.lua). Without them, level-ups, /played, pings and guild loot toasts vanish.
	"SYSTEM", "PING", "GUILD_ACHIEVEMENT",
}

local function ChatReady()
	return ChatFrame1 and ChatFrame1.AddMessageGroup
		and ChatFrame4 and ChatFrame4.AddMessageGroup
		and GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.primary
		and FCF_DockFrame and FCF_UnDockFrame and FCF_SetWindowName and FCFDock_GetChatFrames
end

local function CopyChannels(frame)
	local names = {}
	if frame and frame.channelList then
		for _, name in pairs(frame.channelList) do
			if not (issecretvalue and issecretvalue(name)) and type(name) == "string" then
				names[#names + 1] = name
			end
		end
	end
	return names
end

local function SetGroups(frame, groups)
	frame:RemoveAllMessageGroups()
	if frame.ReceiveAllPrivateMessages then frame:ReceiveAllPrivateMessages() end
	if not ChatTypeGroup then return end
	for i = 1, #groups do
		if ChatTypeGroup[groups[i]] then frame:AddMessageGroup(groups[i]) end
	end
end

-- Numbered channels follow the General tab. Runs again when a channel is joined,
-- because the client adds a new regional channel to the default window.
function ns:RouteChannels()
	if not ns.db.routeChannels then return end
	local chat, general = ChatFrame1, ChatFrame4
	if not chat or not general or not chat.RemoveChannel or not general.AddChannel then return end
	local names = CopyChannels(chat)
	for i = 1, #names do
		local name = names[i]
		chat:RemoveChannel(name)
		if not general.ContainsChannel or not general:ContainsChannel(name) then
			general:AddChannel(name)
		end
	end
end

local function ShowDocked(frame, index)
	SetChatWindowShown(frame:GetID(), true)
	if not frame:IsShown() then frame:Show() end
	if frame.isDocked then FCF_UnDockFrame(frame) end
	FCF_DockFrame(frame, index, false)
end

-- Chat, Combat Log, General, then a voice tab that was already open, then anything else the player added.
local function Redock(general)
	local dock = GENERAL_CHAT_DOCK
	local voice = ChatFrame3
	local voiceDocked = voice and voice.isDocked
	local keep = {}
	for _, frame in ipairs(FCFDock_GetChatFrames(dock)) do
		if frame ~= ChatFrame1 and frame ~= ChatFrame2 and frame ~= general and frame ~= voice then
			keep[#keep + 1] = frame
		end
	end
	local function Undock(frame)
		if frame and frame.isDocked and frame ~= ChatFrame1 then FCF_UnDockFrame(frame) end
	end
	Undock(ChatFrame2)
	Undock(general)
	if voiceDocked then Undock(voice) end
	for i = 1, #keep do Undock(keep[i]) end

	local index = 2
	local function Dock(frame)
		if not frame then return end
		ShowDocked(frame, index)
		index = index + 1
	end
	Dock(ChatFrame2)
	Dock(general)
	if voiceDocked then Dock(voice) end
	for i = 1, #keep do Dock(keep[i]) end
	if FCF_SelectDockFrame then FCF_SelectDockFrame(ChatFrame1) end
	if FCF_DockUpdate then FCF_DockUpdate() end
end

-- Returns false when the chat frames are not up yet. The login retry calls it again.
function ns:ApplyTabLayout()
	if not ChatReady() then return false end
	local chat, general = ChatFrame1, ChatFrame4
	local channels = CopyChannels(chat)
	local already = CopyChannels(general)
	local fresh = not ns.db.layoutVersion or ns.db.layoutVersion < 1

	FCF_SetWindowName(chat, "Chat")
	SetGroups(chat, CHAT_GROUPS)
	chat:RemoveAllChannels()

	local generalName = (type(GENERAL) == "string" and GENERAL) or "General"
	FCF_SetWindowName(general, generalName)
	-- Colour is the window tint. Set it only the first time, so a later tab reset keeps a tint the player chose.
	if fresh and DEFAULT_CHATFRAME_COLOR and FCF_SetWindowColor then
		local c = DEFAULT_CHATFRAME_COLOR
		FCF_SetWindowColor(general, c.r, c.g, c.b)
	end
	if fresh and DEFAULT_CHATFRAME_ALPHA and FCF_SetWindowAlpha then
		FCF_SetWindowAlpha(general, DEFAULT_CHATFRAME_ALPHA)
	end
	SetGroups(general, GENERAL_GROUPS)
	general:RemoveAllChannels()
	for i = 1, #channels do general:AddChannel(channels[i]) end
	for i = 1, #already do
		if not general:ContainsChannel(already[i]) then general:AddChannel(already[i]) end
	end

	if type(COMBAT_LOG) == "string" then FCF_SetWindowName(ChatFrame2, COMBAT_LOG) end
	Redock(general)
	if chat.UpdateDefaultChatTarget then chat:UpdateDefaultChatTarget() end
	if general.UpdateDefaultChatTarget then general:UpdateDefaultChatTarget() end

	ns.db.layoutVersion = 1
	if ns.db.enabled and ns.LayoutWindow then ns:LayoutWindow() end
	return true
end

---------------------------------------------------------------------------
-- Clean, scrollable left-side chat tab list (inside ns.tabColumn)
---------------------------------------------------------------------------
local ROW_H = 24
local ROW_GAP = 2
local ROW_STEP = ROW_H + ROW_GAP

local tabMaxScroll = 0
local lastAutoScrollTab

local function IsBuiltinTab(frame)
	if not frame then return true end
	if IsBuiltinChatWindow and IsBuiltinChatWindow(frame) then return true end
	return frame == ChatFrame1 or frame == ChatFrame2 or frame == ChatFrame3
end

local function CloseExtraTab(frame)
	if not frame or IsBuiltinTab(frame) then return end
	if frame.isTemporary and frame.chatType == "PET_BATTLE_COMBAT_LOG" then
		if FCF_Close then FCF_Close(frame) end
	elseif FCF_PopInWindow then
		FCF_PopInWindow(frame)
	end
end

local function SetLastActiveEditBox(editBox)
	if not editBox then return end
	if ChatFrameUtil and ChatFrameUtil.SetLastActiveWindow then
		ChatFrameUtil.SetLastActiveWindow(editBox)
	elseif ChatEdit_SetLastActiveWindow then
		ChatEdit_SetLastActiveWindow(editBox)
	end
end

local function SelectTabFrame(frame)
	if not frame then return end
	if FCF_SelectDockFrame then FCF_SelectDockFrame(frame) end
	-- Match Blizzard's tab selection (FloatingChatFrame.lua:1825, 2841) so IM chat style
	-- and voice transcription switch the active edit box without touching global state.
	if frame.editBox then
		local isVoice = ChatFrame3 ~= nil and (frame == ChatFrame3)
		local nonClassic = GetCVar and GetCVar("chatStyle") ~= "classic"
		if isVoice or nonClassic then
			SetLastActiveEditBox(frame.editBox)
		end
	end
end

local function OpenTabContextMenu(owner, frame)
	if not (frame and MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		if rootDescription.SetTag then
			rootDescription:SetTag("MENU_DAVES_CHAT_TAB")
		end
		if not frame.isTemporary and StaticPopup_Show and frame.GetID then
			rootDescription:CreateButton(RENAME_CHAT_WINDOW or "Rename Window", function()
				StaticPopup_Show("NAME_CHAT", nil, nil, frame:GetID())
			end)
		end
		if FCF_NewChatWindow then
			local createBtn = rootDescription:CreateButton(NEW_CHAT_WINDOW or "Create New Window", function()
				FCF_NewChatWindow()
			end)
			if createBtn and createBtn.SetEnabled and FCF_CanOpenNewWindow and not FCF_CanOpenNewWindow() then
				createBtn:SetEnabled(false)
			end
		end
		if not IsBuiltinTab(frame) then
			rootDescription:CreateButton(CLOSE_CHAT_WINDOW or "Close Window", function()
				CloseExtraTab(frame)
			end)
		end
		rootDescription:CreateButton(CHAT_CONFIGURATION or "Chat Settings", function()
			SelectTabFrame(frame)
			ns:OpenChatConfig()
		end)
	end)
end

function ns:ScrollTabs(delta)
	if not delta or delta == 0 or tabMaxScroll <= 0 then return end
	local nextOffset = ns.Clamp((ns.tabScrollOffset or 0) - delta * ROW_STEP, 0, tabMaxScroll)
	if math.abs(nextOffset - (ns.tabScrollOffset or 0)) > 0.5 then
		ns.tabScrollOffset = nextOffset
		ns:RefreshTabs()
	end
end

local function EnsureTabList(column)
	if column.viewport then return column.viewport end

	column:EnableMouseWheel(true)
	column:SetScript("OnMouseWheel", function(_, delta)
		ns:ScrollTabs(delta)
	end)

	local viewport = CreateFrame("Frame", nil, column)
	viewport:SetAllPoints(column)
	viewport:SetFrameLevel((column:GetFrameLevel() or 0) + 1)
	if viewport.SetClipsChildren then viewport:SetClipsChildren(true) end
	viewport:EnableMouse(false)
	viewport:EnableMouseWheel(true)
	viewport:SetScript("OnMouseWheel", function(_, delta)
		ns:ScrollTabs(delta)
	end)
	column.viewport = viewport

	local track = CreateFrame("Button", nil, column)
	track:SetWidth(4)
	track:SetPoint("TOPRIGHT", column, "TOPRIGHT", -3, -2)
	track:SetPoint("BOTTOMRIGHT", column, "BOTTOMRIGHT", -3, 2)
	track:SetFrameLevel((column:GetFrameLevel() or 0) + 16)
	track:EnableMouseWheel(true)
	track:SetScript("OnMouseWheel", function(_, delta)
		ns:ScrollTabs(delta)
	end)
	local trackTex = track:CreateTexture(nil, "BACKGROUND")
	trackTex:SetAllPoints()
	trackTex:SetColorTexture(1, 1, 1, 0.1)
	track.tex = trackTex

	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(4)
	thumb:SetFrameLevel(track:GetFrameLevel() + 2)
	thumb:EnableMouseWheel(true)
	thumb:SetScript("OnMouseWheel", function(_, delta)
		ns:ScrollTabs(delta)
	end)
	local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
	thumbTex:SetAllPoints()
	thumbTex:SetColorTexture(0.86, 0.72, 0.34, 0.65)
	thumb.tex = thumbTex
	local thumbHl = thumb:CreateTexture(nil, "HIGHLIGHT")
	thumbHl:SetAllPoints()
	thumbHl:SetColorTexture(1, 0.9, 0.55, 0.35)

	local dragState = {}
	local dragger = CreateFrame("Frame", nil, thumb)
	dragger:Hide()
	local function StopThumbDrag()
		if not dragger:IsShown() then return end
		dragger:Hide()
		dragState.startY = nil
	end
	dragger:SetScript("OnUpdate", function()
		if not dragState.startY or tabMaxScroll <= 0 then StopThumbDrag() return end
		if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then StopThumbDrag() return end
		local sc = track:GetEffectiveScale() or 1
		local _, cy = GetCursorPosition()
		local dy = (dragState.startY - (cy / sc))
		local travel = math.max(1, (track:GetHeight() or 1) - (thumb:GetHeight() or 1))
		ns.tabScrollOffset = ns.Clamp(dragState.startOffset + (dy / travel) * tabMaxScroll, 0, tabMaxScroll)
		ns:RefreshTabs()
	end)
	thumb:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" or tabMaxScroll <= 0 then return end
		local sc = track:GetEffectiveScale() or 1
		local _, cy = GetCursorPosition()
		dragState.startY = cy / sc
		dragState.startOffset = ns.tabScrollOffset or 0
		dragger:Show()
	end)
	thumb:SetScript("OnMouseUp", StopThumbDrag)
	thumb:SetScript("OnHide", StopThumbDrag)

	track:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" or tabMaxScroll <= 0 then return end
		local top = self:GetTop()
		if not top then return end
		local sc = self:GetEffectiveScale() or 1
		local _, cy = GetCursorPosition()
		local localY = top - (cy / sc)
		local thumbH = thumb:GetHeight() or 18
		local travel = math.max(1, (self:GetHeight() or 1) - thumbH)
		local ratio = ns.Clamp((localY - thumbH * 0.5) / travel, 0, 1)
		ns.tabScrollOffset = ratio * tabMaxScroll
		ns:RefreshTabs()
	end)

	track:Hide()
	column.scrollTrack = track
	column.scrollThumb = thumb
	return viewport
end

local function SyncTabPulse(tab, active)
	if not tab then return end
	if not active then
		tab.alerting = false
		if tab.glow then tab.glow:SetAlpha(0) end
		if tab.pulse then tab.pulse:Hide() end
		return
	end
	if not tab.glow then
		local glow = tab:CreateTexture(nil, "OVERLAY")
		glow:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -1)
		glow:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -3, 1)
		glow:SetColorTexture(1, 0.74, 0.22, 1)
		glow:SetBlendMode("ADD")
		glow:SetAlpha(0)
		tab.glow = glow
		local pulse = CreateFrame("Frame", nil, tab)
		pulse:Hide()
		pulse:SetScript("OnUpdate", function()
			local timed = tab.alertUntil and GetTime() <= tab.alertUntil
			if not tab.alerting and not timed then
				if tab.alertUntil and GetTime() > tab.alertUntil then tab.alertUntil = nil end
				glow:SetAlpha(0)
				if not tab.isSelected and tab.accent then tab.accent:Hide() end
				pulse:Hide()
				return
			end
			local wave = math.abs(math.sin(GetTime() * 4))
			glow:SetAlpha(0.06 + 0.16 * wave)
			if not tab.isSelected and tab.accent then
				tab.accent:Show()
				tab.accent:SetColorTexture(1, 0.76, 0.22, 0.35 + 0.6 * wave)
			end
		end)
		tab.pulse = pulse
	end
	tab.alerting = true
	tab.pulse:Show()
end

local function CreateChatTab(viewport)
	local tab = CreateFrame("Button", nil, viewport)
	tab:SetSize(ns.TAB_WIDTH, ROW_H)
	tab:SetFrameLevel((viewport:GetFrameLevel() or 0) + 3)
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
	tab:EnableMouseWheel(true)
	tab:SetScript("OnMouseWheel", function(_, delta)
		ns:ScrollTabs(delta)
	end)

	local bg = tab:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -1)
	bg:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -3, 1)
	bg:Hide()
	tab.bg = bg

	local accent = tab:CreateTexture(nil, "ARTWORK")
	accent:SetWidth(3)
	accent:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -3)
	accent:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 2, 3)
	accent:SetColorTexture(0.92, 0.74, 0.26, 1)
	accent:Hide()
	tab.accent = accent

	local sep = tab:CreateTexture(nil, "BORDER")
	sep:SetHeight(1)
	sep:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 8, -1)
	sep:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -5, -1)
	sep:SetColorTexture(1, 1, 1, 0.06)
	tab.sep = sep

	local hl = tab:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", tab, "TOPLEFT", 2, -1)
	hl:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -3, 1)
	hl:SetColorTexture(1, 1, 1, 0.08)
	tab.hl = hl

	local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("LEFT", tab, "LEFT", 10, 0)
	text:SetPoint("RIGHT", tab, "RIGHT", -6, 0)
	text:SetJustifyH("LEFT")
	if text.SetShadowOffset then text:SetShadowOffset(1, -1) end
	if text.SetShadowColor then text:SetShadowColor(0, 0, 0, 0.95) end
	if text.SetWordWrap then text:SetWordWrap(false) end
	if text.SetMaxLines then text:SetMaxLines(1) end
	tab.text = text

	tab:SetScript("OnEnter", function(self)
		if not self.showTooltip or not self.fullLabel or self.fullLabel == "" then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.fullLabel)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
	tab:SetScript("OnClick", function(self, button)
		local frame = self.chatFrame
		if button == "RightButton" then
			OpenTabContextMenu(self, frame)
			return
		elseif button == "MiddleButton" then
			CloseExtraTab(frame)
			return
		end
		SelectTabFrame(frame)
		self.alertUntil = nil
		SyncTabPulse(self, false)
		ns.Sound("U_CHAT_SCROLL_BUTTON")
		ns:RefreshTabs()
	end)
	return tab
end

-- Blizzard's tabs stay hidden. Ours render as a clean, scrollable vertical list inside ns.tabColumn.
function ns:RefreshTabs()
	local column = ns.tabColumn
	if not column then return end
	local viewport = EnsureTabList(column)
	ns.tabs = ns.tabs or {}

	if ns.anchor and ns.anchor.SetClampRectInsets then
		ns.anchor:SetClampRectInsets(0, 0, 0, 0)
	end

	local frames = {}
	if GENERAL_CHAT_DOCK and FCFDock_GetChatFrames then
		for _, frame in ipairs(FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)) do
			frames[#frames + 1] = frame
		end
	end
	if #frames == 0 and ChatFrame1 then frames[1] = ChatFrame1 end

	local open = ns.db.enabled and (not ns.db.collapsed or ns.inEditMode)
	local selected = GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
	ns.seenTab = selected

	local colW = (column.GetWidth and column:GetWidth()) or ns.TAB_WIDTH
	if not colW or colW <= 0 then colW = ns.TAB_WIDTH end
	local availH = (column.GetHeight and column:GetHeight()) or 0
	if not availH or availH <= 0 then availH = 180 end

	local count = #frames
	local totalH = count > 0 and (count * ROW_H + (count - 1) * ROW_GAP) or 0
	tabMaxScroll = math.max(0, totalH - availH)
	local scrolling = tabMaxScroll > 0

	if selected ~= lastAutoScrollTab then
		lastAutoScrollTab = selected
		if scrolling and selected then
			for i = 1, count do
				if frames[i] == selected then
					local rowTop = (i - 1) * ROW_STEP
					local rowBottom = rowTop + ROW_H
					local cur = ns.tabScrollOffset or 0
					if rowTop < cur then
						ns.tabScrollOffset = rowTop
					elseif rowBottom > cur + availH then
						ns.tabScrollOffset = rowBottom - availH
					end
					break
				end
			end
		end
	end

	local scrollOffset = scrolling and ns.Clamp(ns.tabScrollOffset or 0, 0, tabMaxScroll) or 0
	ns.tabScrollOffset = scrollOffset

	local style = ns.BackgroundStyle and ns.BackgroundStyle(ns.db and ns.db.backgroundStyle)
	local light = style and style.light and true or false
	local rowW = scrolling and math.max(36, colW - 8) or colW
	local innerTextW = math.max(20, rowW - 16)

	for i, frame in ipairs(frames) do
		local tab = ns.tabs[i]
		if not tab then
			tab = CreateChatTab(viewport)
			ns.tabs[i] = tab
		end
		local name = frame.GetName and frame:GetName()
		local real = name and _G[name .. "Tab"]
		local raw = real and real.GetText and real:GetText()
		local isSecret = raw ~= nil and issecretvalue and issecretvalue(raw)
		local label = "Chat"
		if isSecret then
			tab.text:SetText(raw)
			tab.fullLabel = nil
		else
			if type(raw) == "string" and raw ~= "" then
				label = raw
			end
			tab.text:SetText(label)
			tab.fullLabel = label
		end

		tab.chatFrame = frame
		tab:SetSize(rowW, ROW_H)

		local on = frame == selected or (not selected and frame == ChatFrame1)
		tab.isSelected = on
		if tab.hl then
			if light then
				tab.hl:SetColorTexture(0, 0, 0, 0.08)
			else
				tab.hl:SetColorTexture(1, 1, 1, 0.08)
			end
		end
		if tab.sep then
			if light then
				tab.sep:SetColorTexture(0, 0, 0, 0.1)
			else
				tab.sep:SetColorTexture(1, 1, 1, 0.06)
			end
			tab.sep:SetShown(i < count)
		end

		if on then
			tab.alertUntil = nil
			SyncTabPulse(tab, false)
			if tab.bg then
				if light then
					tab.bg:SetColorTexture(0, 0, 0, 0.22)
				else
					tab.bg:SetColorTexture(0.9, 0.72, 0.24, 0.16)
				end
				tab.bg:Show()
			end
			if tab.accent then
				tab.accent:SetColorTexture(0.92, 0.74, 0.26, 1)
				tab.accent:Show()
			end
			tab.text:SetFontObject("GameFontHighlightSmall")
			tab.text:SetTextColor(1, 0.96, 0.86)
		else
			if tab.bg then tab.bg:Hide() end
			tab.text:SetFontObject("GameFontNormalSmall")
			if light then
				tab.text:SetTextColor(0.94, 0.9, 0.82)
			else
				tab.text:SetTextColor(0.78, 0.76, 0.72)
			end
			local blizzardAlert = real and ((ChatFrameUtil and ChatFrameUtil.IsTabAlerting and ChatFrameUtil.IsTabAlerting(real)) or real.alerting)
			local timedAlert = tab.alertUntil and GetTime() <= tab.alertUntil
			local alerting = (blizzardAlert or timedAlert) and true or false
			if not alerting and tab.accent then tab.accent:Hide() end
			SyncTabPulse(tab, alerting)
		end

		local truncated = false
		if not isSecret then
			if tab.text.IsTruncated then
				truncated = tab.text:IsTruncated() and true or false
			elseif tab.text.GetUnboundedStringWidth then
				truncated = (tab.text:GetUnboundedStringWidth() or 0) > innerTextW
			elseif tab.text.GetStringWidth then
				truncated = (tab.text:GetStringWidth() or 0) > innerTextW
			end
		end
		tab.showTooltip = truncated

		local rowTop = (i - 1) * ROW_STEP - scrollOffset
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, -rowTop)
		local visible = (rowTop + ROW_H) > 0 and rowTop < availH
		tab:SetShown(open and visible)
	end
	for i = count + 1, #ns.tabs do
		SyncTabPulse(ns.tabs[i], false)
		ns.tabs[i]:Hide()
	end

	local track = column.scrollTrack
	local thumb = column.scrollThumb
	if track and thumb then
		if open and scrolling and totalH > 0 then
			if track.tex then
				if light then
					track.tex:SetColorTexture(0, 0, 0, 0.16)
				else
					track.tex:SetColorTexture(1, 1, 1, 0.1)
				end
			end
			if thumb.tex then
				if light then
					thumb.tex:SetColorTexture(0.22, 0.17, 0.08, 0.72)
				else
					thumb.tex:SetColorTexture(0.88, 0.73, 0.34, 0.68)
				end
			end
			track:Show()
			local trackH = math.max(24, (track:GetHeight() and track:GetHeight() > 0 and track:GetHeight()) or (availH - 4))
			local thumbH = ns.Clamp(math.floor(trackH * availH / totalH), 18, trackH)
			local travel = math.max(0, trackH - thumbH)
			local thumbY = tabMaxScroll > 0 and -math.floor(travel * (scrollOffset / tabMaxScroll) + 0.5) or 0
			thumb:SetHeight(thumbH)
			thumb:ClearAllPoints()
			thumb:SetPoint("TOP", track, "TOP", 0, thumbY)
		else
			track:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Login & channel routing events
---------------------------------------------------------------------------
function ns:OnLogin()
	local function Ready()
		if not ns.db.layoutVersion or ns.db.layoutVersion < 1 then
			if ChatReady() and ns:ApplyTabLayout() then
				ns.Print("tabs set: Chat, Combat Log, General.")
				return
			end
		end
		if ns.LayoutWindow then ns:LayoutWindow() end
	end
	Ready()
	if C_Timer and C_Timer.After then
		C_Timer.After(0, Ready)
		C_Timer.After(1, Ready)
	end
end

function ns:UPDATE_CHAT_WINDOWS()
	local needsInitialTabs = not ns.db.layoutVersion or ns.db.layoutVersion < 1
	if needsInitialTabs and ChatReady() then
		ns:ApplyTabLayout()
		return
	end
	if ns.LayoutWindow then ns:LayoutWindow() end
	if (needsInitialTabs and not ChatReady()) or (ns.anchor and not ns.anchor:GetCenter()) then
		ns.Defer(function()
			if (not ns.db.layoutVersion or ns.db.layoutVersion < 1) and ChatReady() then
				ns:ApplyTabLayout()
				return
			end
			if ns.LayoutWindow then ns:LayoutWindow() end
		end)
	end
end

function ns:CHAT_MSG_CHANNEL_NOTICE(notice)
	if not notice or (issecretvalue and issecretvalue(notice)) then return end
	if notice ~= "YOU_CHANGED" and notice ~= "YOU_JOINED" then return end
	if not ns.db.routeChannels then return end
	ns.Defer(function() ns:RouteChannels() end)
end

function ns:CHANNEL_UI_UPDATE()
	if not ns.db.routeChannels or not ns.db.layoutVersion or ns.db.layoutVersion < 1 then return end
	ns.Defer(function() ns:RouteChannels() end)
end
