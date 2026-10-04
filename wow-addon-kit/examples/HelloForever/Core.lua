-- HelloForever / Core.lua
-- Startup, saved settings, events and the slash command.

local ADDON, ns = ...

-- WoW: Forever identifies itself as project "Camelot" (Blizzard's Forever UI source,
-- Blizzard_ProjectConstants/Camelot/ProjectConstants.lua: WOW_PROJECT_CAMELOT = 18).
ns.IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
ns.IS_RETAIL = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

-- Feature detection, never version checks: C_AddOns on modern clients, the old global elsewhere.
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = GetAddOnMetadata(ADDON, "Version") or "dev"

local DEFAULTS = {
	enabled = true,
	scale = 1.0,
}

function ns.Print(...)
	print("|cff33ff99" .. ADDON .. "|r:", ...)
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
	HelloForeverDB = HelloForeverDB or {}
	for k, v in pairs(DEFAULTS) do
		if HelloForeverDB[k] == nil then HelloForeverDB[k] = v end
	end
	ns.db = HelloForeverDB

	ns:InitOptions()
	ns:InitPanel()
end

function ns:PLAYER_LOGIN()
	ns.Print(("v%s loaded%s. Type /hf for options."):format(ns.VERSION, ns.IS_FOREVER and " (WoW: Forever)" or ""))
end

---------------------------------------------------------------------------
-- Slash command and Addon Compartment (minimap addon menu)
---------------------------------------------------------------------------
SLASH_HELLOFOREVER1 = "/hf"
SlashCmdList["HELLOFOREVER"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "options" then
		ns:OpenOptions()
	elseif msg == "toggle" then
		ns:TogglePanel()
	elseif msg == "version" then
		ns.Print(ns.VERSION)
	else
		ns.Print("commands: /hf [options | toggle | version]")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function HelloForever_OnAddonCompartmentClick()
	ns:OpenOptions()
end
