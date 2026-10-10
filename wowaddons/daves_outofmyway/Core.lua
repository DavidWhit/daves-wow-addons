-- daves_outofmyway / Core.lua
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
	enabled = true,   -- move the loot rolls (once placed in Edit Mode)
	scale = 1.0,      -- the loot roll frames' scale once moved
	grow = "up",      -- more rolls stack above ("up") or below ("down") the first
	showAllBuffs = true,   -- buff frame: every buff shown, never collapsed (Buffs.lua)
	-- savedCVars: the buff CVars as they were before, put back if showAllBuffs is turned off
	-- pos: where you put the loot rolls in Edit Mode; nil = Blizzard's own spot
}

-- settings changed (Options panel): re-place the anchor and the rolls
function ns:Apply()
	if ns.ApplyAnchor then ns.ApplyAnchor() end
end

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
	daves_outofmywayDB = daves_outofmywayDB or {}
	for k, v in pairs(DEFAULTS) do
		if daves_outofmywayDB[k] == nil then daves_outofmywayDB[k] = v end
	end
	ns.db = daves_outofmywayDB

	ns:InitOptions()
	ns:InitEditMode(ns.InitLootRolls())
end

function ns:PLAYER_LOGIN()
	ns.InitBuffs()
	ns.Print(("v%s loaded%s. Move the loot rolls in Edit Mode; /oomw for commands."):format(ns.VERSION, ns.IS_FOREVER and " (WoW: Forever)" or ""))
end

---------------------------------------------------------------------------
-- Slash command and Addon Compartment (minimap addon menu)
---------------------------------------------------------------------------
SLASH_DAVES_OUTOFMYWAY1 = "/oomw"
SLASH_DAVES_OUTOFMYWAY2 = "/davesoutofmyway"
SlashCmdList["DAVES_OUTOFMYWAY"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "options" then
		ns:OpenOptions()
	elseif msg == "reset" then
		ns.db.pos = nil
		ns.ApplyAnchor()
		ns.Print("loot rolls are back where Blizzard puts them.")
	elseif msg == "leave" then
		ns.leaveHintShown = nil
		ns.CheckLeaveButton()
		if not ns.leaveHintShown then ns.Print("the flight-path dismount button moves in Blizzard's Edit Mode (Vehicle Leave Button: click Expand options, then Misc).") end
	elseif msg == "buffs" then
		ns.Print("buff frame: " .. ns.BuffState() .. "." .. (ns.db.showAllBuffs and "" or " (Show all buffs is off in the options.)"))
	elseif msg == "version" then
		ns.Print(ns.VERSION)
	else
		ns.Print("commands: /oomw [options | reset | leave | buffs | version]. Move the loot rolls in Edit Mode.")
		ns.Print("buff frame: " .. ns.BuffState() .. ".")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function daves_outofmyway_OnAddonCompartmentClick()
	ns:OpenOptions()
end
