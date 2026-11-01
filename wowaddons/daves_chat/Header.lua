-- daves_chat / Header.lua
-- Internal top header row (Social, Channels, optional TTS, Chat Settings bubble icon,
-- Window Settings window icon, and top-right Close X), Blizzard social/channel button pinning,
-- and ChatConfigFrame padding.

local _, ns = ...

local CHAT_CONFIG_INSET = 8

function ns.TryTemplate(kind, name, parent, template)
	local ok, f = pcall(CreateFrame, kind, name, parent, template)
	if ok and f then return f end
end

-- Shared message-bubble icon button (FloatingChatFrame.xml:734-737): used for both the
-- draggable collapsed open-chat icon and the header's Chat Settings button.
function ns.MakeChatIcon(parent, name)
	local b = CreateFrame("Button", name, parent)
	b:SetSize(32, 32)
	b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
	b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Down")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b:RegisterForClicks("LeftButtonUp")
	return b
end

-- Matching UI-ChatIcon window-frame icon button (FloatingChatFrame.xml:665-667) for Window Settings.
local function MakeWindowIcon(parent, name)
	local b = CreateFrame("Button", name, parent)
	b:SetSize(32, 32)
	b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Maximize-Up")
	b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Maximize-Down")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	b:RegisterForClicks("LeftButtonUp")
	return b
end

-- The Social / Friends button is hidden while the in-game friends list game rule is disabled.
function ns.FriendsWanted()
	if not QuickJoinToastButton then return false end
	if C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule
		and Enum.GameRule.IngameFriendsListDisabled
		and C_GameRules.IsGameRuleActive(Enum.GameRule.IngameFriendsListDisabled) then
		return false
	end
	return true
end

-- Only reserve header space for TextToSpeechButtonFrame when Text-to-Speech is actually enabled.
function ns.TtsWanted()
	if not TextToSpeechButtonFrame then return false end
	if TextToSpeechButton and TextToSpeechButton.IsShown then
		return TextToSpeechButton:IsShown()
	end
	return (GetCVarBool and GetCVarBool("textToSpeech")) or false
end

function ns.MakeCloseButton(parent, name, onClick)
	local b = ns.TryTemplate("Button", name, parent, "UIPanelCloseButton")
	if b then
		b.anchorX, b.anchorY = 0, 0
	else
		b = CreateFrame("Button", name, parent)
		b:SetSize(32, 32)
		b.anchorX, b.anchorY = 2, 2
		b:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
		b:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
		b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
	end
	b:RegisterForClicks("LeftButtonUp")
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

function ns:BuildHeader(anchor)
	local edge = ns.EDGE or 14
	local topEdge = ns.TOP_EDGE or 10
	local topLevel = math.max(anchor:GetFrameLevel() or 0,
		(ns.border and ns.border.GetFrameLevel and ns.border:GetFrameLevel()) or 0)

	local bar = CreateFrame("Frame", nil, anchor)
	bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", edge, -topEdge)
	bar:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -34, -topEdge)
	bar:SetHeight(34)
	bar:SetFrameLevel(topLevel + 22)
	ns.settingsBar = bar

	local divider = bar:CreateTexture(nil, "BORDER")
	divider:SetColorTexture(1, 1, 1, 0.28)
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
	divider:SetPoint("RIGHT", anchor, "RIGHT", -edge, 0)
	ns.settingsDivider = divider

	local chatSettings = ns.MakeChatIcon(bar, "DavesChatConfigButton")
	chatSettings:SetFrameLevel(bar:GetFrameLevel() + 15)
	chatSettings:SetScript("OnClick", function()
		ns:OpenChatConfig()
	end)
	chatSettings:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Chat Settings")
		GameTooltip:AddLine("Configure message types, channels, and colors for this tab.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	chatSettings:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ns.chatSettingsButton = chatSettings

	local windowSettings = MakeWindowIcon(bar, "DavesChatWindowButton")
	windowSettings:SetFrameLevel(bar:GetFrameLevel() + 15)
	windowSettings:SetScript("OnClick", function()
		ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns:ToggleWindowSettings()
	end)
	windowSettings:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Window Settings")
		GameTooltip:AddLine("Adjust window scale, size, background style, and tabs.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	windowSettings:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ns.windowSettingsButton = windowSettings

	local close = ns.MakeCloseButton(anchor, "DavesChatCloseButton", function()
		ns.Sound("IG_MAINMENU_CLOSE")
		ns:SetCollapsed(true)
	end)
	close:ClearAllPoints()
	close:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", close.anchorX, close.anchorY)
	close:SetFrameLevel(topLevel + 40)
	close:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Close chat")
		GameTooltip:Show()
	end)
	close:SetScript("OnLeave", function() GameTooltip:Hide() end)
	ns.closeButton = close
end

-- Left side of the header: Social (QuickJoinToastButton), Channels, and optional TTS.
-- Right side of the header: Chat Settings (bubble icon) and Window Settings (window icon),
-- with Close X in the top-right window corner.
function ns:PlaceSettings()
	local bar = ns.settingsBar
	if not bar or not ns.anchor then return end
	local ROW, PAD, gap = 34, 2, 6
	bar:SetHeight(ROW)

	ns.friendsX, ns.friendsY = nil, nil
	ns.channelsX, ns.channelsY = nil, nil
	ns.soundX, ns.soundY = nil, nil

	local x = PAD
	if ns.FriendsWanted() then
		local w, h = 32, 32
		ns.friendsX, ns.friendsY = x, -math.floor((ROW - h) / 2)
		x = x + w + gap
	end
	if ChatFrameChannelButton then
		local w = (ChatFrameChannelButton.GetWidth and ChatFrameChannelButton:GetWidth()) or 27
		local h = (ChatFrameChannelButton.GetHeight and ChatFrameChannelButton:GetHeight()) or 26
		if w <= 8 then w = 27 end
		if h <= 8 then h = 26 end
		ns.channelsX, ns.channelsY = x, -math.floor((ROW - h) / 2)
		x = x + w + gap
	end
	ns.seenTtsWanted = ns.TtsWanted()
	if ns.seenTtsWanted then
		local w = (TextToSpeechButtonFrame.GetWidth and TextToSpeechButtonFrame:GetWidth()) or 26
		local h = (TextToSpeechButtonFrame.GetHeight and TextToSpeechButtonFrame:GetHeight()) or 26
		if w <= 8 then w = 26 end
		if h <= 8 then h = 26 end
		ns.soundX, ns.soundY = x, -math.floor((ROW - h) / 2)
	end

	if ns.windowSettingsButton then
		ns.windowSettingsButton:ClearAllPoints()
		ns.windowSettingsButton:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
	end
	if ns.chatSettingsButton then
		ns.chatSettingsButton:ClearAllPoints()
		if ns.windowSettingsButton then
			ns.chatSettingsButton:SetPoint("RIGHT", ns.windowSettingsButton, "LEFT", -4, 0)
		else
			ns.chatSettingsButton:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
		end
	end
end

---------------------------------------------------------------------------
-- Blizzard social / channel icon pinning & ChatAlertFrame handoff
---------------------------------------------------------------------------
local function NotDefaultPosition()
	return false
end

local function RememberParent(frame, key, home)
	if not frame or ns[key] then return end
	local parent = frame.GetParent and frame:GetParent()
	if parent and parent ~= home then
		ns[key] = parent
	end
end

local function OwnedByUs(frame, home)
	if not frame or not frame.GetParent then return false end
	return frame:GetParent() == home
end

local function PlaceOnBar(frame, home, x, y, show, levelOffset)
	if not frame or not x then return end
	frame:SetParent(home)
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(home:GetFrameLevel() + (levelOffset or 20))
	frame:SetAlpha(1)
	if frame.EnableMouse then frame:EnableMouse(true) end
	-- Show before ClearAllPoints/SetPoint so any OnShow -> ChatAlertFrame:UpdateAnchors
	-- finishes before our final header anchor is applied.
	if show and not frame:IsShown() then frame:Show() end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", home, "TOPLEFT", x, y or 0)
end

-- Chat alerts re-anchor TextToSpeechButtonFrame and QuickJoinToastButton onto ChatAlertFrame.
-- Put Social, Channels, and optional TTS back on our header row synchronously without flicker.
function ns:PinHeaderIcons()
	if ns.pinning then return end
	local home = ns.settingsBar
	if not home or not ns.db.enabled or (ns.db.collapsed and not ns.inEditMode) then return end
	ns.pinning = true

	local tts = TextToSpeechButtonFrame
	if tts then
		-- Return false from IsInDefaultPosition (AlertFrames.lua:423) so Battle.net friend-online
		-- toasts stay on ChatAlertFrame instead of chaining into our header row.
		tts.IsInDefaultPosition = NotDefaultPosition
		if ns.soundX then
			PlaceOnBar(tts, home, ns.soundX, ns.soundY, false, 20)
		else
			tts:SetParent(home)
			tts:ClearAllPoints()
			if ns.chatSettingsButton then
				tts:SetPoint("RIGHT", ns.chatSettingsButton, "LEFT", -8, 0)
			else
				tts:SetPoint("RIGHT", home, "RIGHT", -80, 0)
			end
			tts:SetFrameStrata("MEDIUM")
			tts:SetFrameLevel(home:GetFrameLevel() + 20)
		end
	end

	local friends = QuickJoinToastButton
	if friends and ns.friendsX and ns.FriendsWanted() then
		friends:SetSize(32, 32)
		friends.IsInDefaultPosition = NotDefaultPosition
		-- Grow Quick Join banners left (QuickJoinToast.lua:154) so their 301px hit rect does
		-- not cover Channels or Settings to the right.
		if friends.SetToastDirection then friends:SetToastDirection(true) end
		PlaceOnBar(friends, home, ns.friendsX, ns.friendsY, true, 20)
	end

	if ChatFrameChannelButton and ns.channelsX then
		PlaceOnBar(ChatFrameChannelButton, home, ns.channelsX, ns.channelsY, true, 20)
	end

	ns.pinning = false
end

function ns:FriendsDrifted()
	local friends = QuickJoinToastButton
	local home = ns.settingsBar
	if not ns.FriendsWanted() or not home or not ns.friendsX then return false end
	if not friends:IsShown() or friends:GetParent() ~= home then return true end
	local _, rel = friends:GetPoint(1)
	return rel ~= home
end

function ns:PlaceHeaderButtons()
	if ns.placingHeader or not ns.settingsBar or not ns.chatSettingsButton then return end
	ns.placingHeader = true
	local home = ns.settingsBar
	RememberParent(QuickJoinToastButton, "friendsParent", home)
	RememberParent(ChatFrameChannelButton, "channelParent", home)

	if not ns.db.enabled then
		local moved = false
		local tts = TextToSpeechButtonFrame
		if tts then
			if tts.IsInDefaultPosition == NotDefaultPosition then
				tts.IsInDefaultPosition = nil
				moved = true
			end
			if OwnedByUs(tts, home) then
				tts:SetParent(UIParent)
				tts:SetFrameStrata("LOW")
				tts:SetFrameLevel(4)
				moved = true
			end
		end
		local friends = QuickJoinToastButton
		if friends then
			if friends.IsInDefaultPosition == NotDefaultPosition then
				friends.IsInDefaultPosition = nil
				moved = true
			end
			if OwnedByUs(friends, home) then
				friends:SetParent(ns.friendsParent or UIParent)
				friends:SetFrameStrata("LOW")
				friends:SetFrameLevel(4)
				if friends.SetToastDirection then
					friends:SetToastDirection(ChatFrame1 ~= nil and ChatFrame1.buttonSide == "right")
				end
				moved = true
			end
		end
		if ChatFrameChannelButton and OwnedByUs(ChatFrameChannelButton, home) then
			local parent = ns.channelParent or ChatFrame1ButtonFrame
			ChatFrameChannelButton:SetParent(parent)
			ChatFrameChannelButton:ClearAllPoints()
			if parent then ChatFrameChannelButton:SetPoint("TOP", parent, "TOP", 0, 0) end
			ChatFrameChannelButton:SetAlpha(1)
			if ChatFrameChannelButton.EnableMouse then ChatFrameChannelButton:EnableMouse(true) end
		end
		if moved and ChatAlertFrame and ChatAlertFrame.UpdateAnchors then
			ChatAlertFrame:UpdateAnchors()
		end
	elseif not ns.db.collapsed or ns.inEditMode then
		local tts = TextToSpeechButtonFrame
		local friends = QuickJoinToastButton
		local refreshAlerts = (tts and tts.IsInDefaultPosition ~= NotDefaultPosition)
			or (friends and ns.friendsX and friends.IsInDefaultPosition ~= NotDefaultPosition)
		ns:PinHeaderIcons()
		ns.placingHeader = false
		if refreshAlerts and ChatAlertFrame and ChatAlertFrame.UpdateAnchors then
			ChatAlertFrame:UpdateAnchors()
		end
		ns:PinHeaderIcons()
		return
	end
	ns.placingHeader = false
end

function ns:HookChatAlerts()
	if not (ChatAlertFrame and ChatAlertFrame.UpdateAnchors and hooksecurefunc) then return end
	hooksecurefunc(ChatAlertFrame, "UpdateAnchors", function()
		if not (ns.db.enabled and (not ns.db.collapsed or ns.inEditMode)) then return end
		if ns.placingHeader or ns.pinning then return end
		if ns.FriendsWanted() and not ns.friendsX then
			ns:PlaceSettings()
		end
		ns:PinHeaderIcons()
	end)
end

---------------------------------------------------------------------------
-- Blizzard ChatConfigFrame inset padding
---------------------------------------------------------------------------
-- Blizzard's chat options sit 12px off the dialog edge; add 8px inner padding as full anchors
-- so reopening never accumulates offsets. Combat settings drops the background top by 135px
-- (ChatConfigFrame.lua:1853); preserve that drop when Combat settings are shown.
function ns:PadChatConfig()
	local frame = ChatConfigFrame
	local cat = ChatConfigCategoryFrame
	local bg = ChatConfigBackgroundFrame
	if not frame or not cat or not bg then return end
	local combat = ChatConfigCombatSettings
	local combatShown = combat and combat.IsShown and combat:IsShown()

	cat:ClearAllPoints()
	cat:SetPoint("TOPLEFT", frame, "TOPLEFT", 12 + CHAT_CONFIG_INSET, -57 - CHAT_CONFIG_INSET)
	cat:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 137, 35 + CHAT_CONFIG_INSET)

	bg:ClearAllPoints()
	bg:SetPoint("TOPLEFT", cat, "TOPRIGHT", 1, combatShown and -135 or 0)
	bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12 - CHAT_CONFIG_INSET, 35 + CHAT_CONFIG_INSET)

	if combat then
		combat:ClearAllPoints()
		combat:SetPoint("TOPLEFT", cat, "TOPRIGHT", 1, 0)
		combat:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12 - CHAT_CONFIG_INSET, 35 + CHAT_CONFIG_INSET)
	end
end

function ns:OpenChatConfig()
	if InCombatLockdown and InCombatLockdown() then
		ns.Print("cannot open Chat Settings during combat.")
		return
	end
	if not ChatConfigFrame or not ToggleUIPanel then
		ns.Print("chat options are not available yet.")
		return
	end
	local selected = ns.VisibleChatFrame and ns.VisibleChatFrame()
	local id = (selected and selected.GetID and selected:GetID()) or 1
	local wasShown = ChatConfigFrame:IsShown()
	ToggleUIPanel(ChatConfigFrame) -- taint-call: ok
	-- OnShow paints the last tab. Point it at the tab the player is looking at.
	if not wasShown and ChatConfigFrame:IsShown() then
		if ChatConfigFrame.ChatTabManager and ChatConfigFrame.ChatTabManager.UpdateSelection then
			ChatConfigFrame.ChatTabManager:UpdateSelection(id)
		end
		ns:PadChatConfig()
	end
	ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
end
