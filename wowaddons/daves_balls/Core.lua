-- daves_balls / Core.lua
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
	textMode = "numbers",   -- "numbers", "percent", "both" or "none"
	animate = true,
	glare = true,
	locked = true,          -- unlocked: drag the orbs any time, not just in Edit Mode
	hidePlayerFrame = false,
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
	DavesBallsDB = DavesBallsDB or {}
	if DavesBallsDB.showText == false and DavesBallsDB.textMode == nil then
		DavesBallsDB.textMode = "none"   -- carry over the old on/off numbers setting
	end
	DavesBallsDB.showText = nil
	for k, v in pairs(DEFAULTS) do
		if DavesBallsDB[k] == nil then DavesBallsDB[k] = v end
	end
	ns.db = DavesBallsDB

	ns:InitOptions()
	ns:InitOrbs()
	ns:Apply()
end

function ns:PLAYER_LOGIN()
	ns.Print(("v%s loaded%s. Type /balls for options."):format(ns.VERSION, ns.IS_FOREVER and " (WoW: Forever)" or ""))
end

---------------------------------------------------------------------------
-- Slash command and Addon Compartment (minimap addon menu)
---------------------------------------------------------------------------
SLASH_DAVESBALLS1, SLASH_DAVESBALLS2 = "/balls", "/davesballs"
SlashCmdList["DAVESBALLS"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "options" then
		ns:OpenOptions()
	elseif msg == "unlock" or msg == "lock" then
		ns.db.locked = (msg == "lock")
		ns:Apply()
		ns.Print(ns.db.locked and "orbs locked." or "orbs unlocked: drag to move, right-click to reset. /balls lock when done.")
	elseif msg == "reset" then
		for _, orb in pairs(ns.orbs) do ns:ResetOrbPosition(orb) end
		ns.Print("orb positions reset.")
	elseif msg == "version" then
		ns.Print(ns.VERSION)
	else
		ns.Print("commands: /balls [options | unlock | lock | reset | version]. The orbs can also be moved in Edit Mode.")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function DavesBalls_OnAddonCompartmentClick()
	ns:OpenOptions()
end
