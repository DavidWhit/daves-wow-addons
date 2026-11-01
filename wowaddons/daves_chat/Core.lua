-- daves_chat / Core.lua
-- Startup, saved settings, shared helpers, events and the slash command.

local ADDON, ns = ...

-- WoW: Forever identifies itself as project "Camelot" (Blizzard's Forever UI source,
-- Blizzard_ProjectConstants/Camelot/ProjectConstants.lua: WOW_PROJECT_CAMELOT = 18).
ns.IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
ns.IS_RETAIL = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

-- Feature detection, never version checks: C_AddOns on modern clients, the old global elsewhere.
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = GetAddOnMetadata(ADDON, "Version") or "dev"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- Minimum window dimensions: 430 leaves >=250px for the inner chat text frame beside the 100px
-- left tab stack, and 180 fits the header row, three stacked tabs, and the bottom edit box.
ns.MIN_WIDTH = 430
ns.MIN_HEIGHT = 180
ns.TAB_WIDTH = 104

-- WoW's usual corner, clear of the left button column the chat frame hangs outside itself.
ns.DEFAULT_POS = { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = 16, y = 16 }

ns.DEFAULTS = {
	enabled = true,          -- place Blizzard's chat dock inside our window
	routeChannels = true,    -- numbered channels (General, Trade, ...) stay on the General tab
	layoutVersion = 0,       -- 0 until the three default tabs have been applied once
	width = 520,
	height = 320,
	scale = 1,               -- whole window, same range as Dave's Sack
	background = 0.8,        -- window background darkness (0.8 = Blizzard's translucent dialog)
	backgroundStyle = "dark",
	collapsed = false,       -- window hidden; the message-bubble icon opens it
	whisperAlert = true,     -- flash the message-bubble icon / tab when someone whispers
}

function ns.Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function ns.Sound(kit)
	if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

function ns.Defer(fn)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, fn)
	else
		fn()
	end
end

function ns.HasAtlas(name)
	return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

function ns.Print(...)
	print("|cffd4a94eDave's Chat|r:", ...)
end

---------------------------------------------------------------------------
-- Events: ns:EVENT_NAME(...) is called for every registered event.
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
	local handler = ns[event]
	if handler then handler(ns, ...) end
end)
ns.events = events

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

function ns:ADDON_LOADED(name)
	if name ~= ADDON then return end
	events:UnregisterEvent("ADDON_LOADED")

	-- SavedVariables are loaded by the time our own ADDON_LOADED fires.
	daves_chatDB = daves_chatDB or {}
	for k, v in pairs(ns.DEFAULTS) do
		if daves_chatDB[k] == nil then daves_chatDB[k] = v end
	end
	ns.db = daves_chatDB

	ns.db.width = math.max(ns.MIN_WIDTH, tonumber(ns.db.width) or ns.DEFAULTS.width)
	ns.db.height = math.max(ns.MIN_HEIGHT, tonumber(ns.db.height) or ns.DEFAULTS.height)
	ns.db.scale = ns.Clamp(tonumber(ns.db.scale) or ns.DEFAULTS.scale, 0.5, 2)
	ns.db.background = ns.Clamp(tonumber(ns.db.background) or ns.DEFAULTS.background, 0.2, 1)

	ns:InitOptions()
	ns:Init()
end

function ns:PLAYER_LOGIN()
	-- v<version> loaded: every reload shows which build is running.
	ns.Print(("v%s loaded. /daveschat opens settings."):format(ns.VERSION))
	if ns.OnLogin then ns:OnLogin() end
end

function ns:ToggleWindowSettings(forceOpen)
	if not (ns.editDialog and ns.anchor) then return end
	if not forceOpen and ns.editDialog:IsShown() then
		ns.editDialog:Hide()
	else
		ns.editDialog:OpenFor(ns.anchor, "Window Settings")
	end
end

---------------------------------------------------------------------------
-- Slash command and Addon Compartment (minimap addon menu)
---------------------------------------------------------------------------
SLASH_DAVES_CHAT1 = "/daveschat"
SlashCmdList["DAVES_CHAT"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "window" or msg == "settings" then
		ns:ToggleWindowSettings(true)
	elseif msg == "config" or msg == "chat" then
		ns:OpenChatConfig()
	elseif msg == "options" or msg == "addon" then
		ns:OpenOptions()
	elseif msg == "tabs" then
		if ns:ApplyTabLayout() then
			ns.Print("tabs reset: Chat, Combat Log, General.")
		else
			ns.Print("chat windows are not ready yet.")
		end
	elseif msg == "reset" then
		ns:ResetPosition()
	elseif msg == "version" then
		ns.Print(ns.VERSION)
	else
		ns.Print("commands: /daveschat [window | chat | options | tabs | reset | version]")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function daves_chat_OnAddonCompartmentClick()
	ns:ToggleWindowSettings()
end
