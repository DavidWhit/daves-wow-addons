-- daves_map / Core.lua
-- Startup, saved settings, events and the slash command.
--
-- The addon draws Map Genie's WoW Forever pins (Data.lua, built by tools/Update-MapData.ps1) as a layer of its own on
-- Blizzard's world map, with a search and filter panel beside it (Layer.lua, Panel.lua). Map Genie's positions are
-- pixels on their own map image; Calibrate.lua turns them into game map positions in game, from the flight points.

local ADDON, ns = ...

-- WoW: Forever identifies itself as project "Camelot" (Blizzard's Forever UI source,
-- Blizzard_ProjectConstants/Camelot/ProjectConstants.lua: WOW_PROJECT_CAMELOT = 18).
ns.IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
ns.IS_RETAIL = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

-- Feature detection, never version checks: C_AddOns on modern clients, the old global elsewhere.
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = GetAddOnMetadata(ADDON, "Version") or "dev"

local DEFAULTS = {
	enabled = true,         -- draw the layer on the world map
	panelOpen = true,       -- the search and filter panel beside the map
	pinScale = 1.0,         -- pin size
	hideCompleted = false,  -- completed quests are dimmed; hidden when this is on
	otherClasses = false,   -- show quests only other classes can take
	hideHighLevel = false,  -- hide quests above your level
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
	if name == "Blizzard_WorldMap" then
		if ns.db then ns.InitLayer() end
		return
	end
	if name ~= ADDON then return end

	-- SavedVariables are loaded by the time our own ADDON_LOADED fires.
	daves_mapDB = daves_mapDB or {}
	for k, v in pairs(DEFAULTS) do
		if daves_mapDB[k] == nil then daves_mapDB[k] = v end
	end
	if type(daves_mapDB.hidden) ~= "table" then daves_mapDB.hidden = {} end   -- [Map Genie category id] = true: off
	ns.db = daves_mapDB

	ns:InitOptions()
	-- the world map is a Blizzard add-on of its own: it may load before us or after
	if WorldMapFrame then ns.InitLayer() end
end

function ns:PLAYER_LOGIN()
	local db = ns.db
	if type(db.factions) ~= "table" then   -- { [1] Alliance, [2] Horde, [3] Neutral }: yours and neutral to start with
		local faction = UnitFactionGroup("player")
		db.factions = { [1] = faction ~= "Horde", [2] = faction == "Horde", [3] = true }
	end
	local _, class = UnitClass("player")
	if class and not issecretvalue(class) then ns.playerClass = class end
	local D = ns.DATA
	if D then
		ns.Print(("v%s loaded: %d map pins from %s (%s). /dmap for commands."):format(ns.VERSION, #D.x, D.source.map, D.source.fetched))
	else
		ns.Print(("v%s loaded without map data: build it with tools/Update-MapData.ps1 (the daves-map-refresh skill)."):format(ns.VERSION))
	end
end

---------------------------------------------------------------------------
-- Slash command and Addon Compartment (minimap addon menu)
---------------------------------------------------------------------------
SLASH_DAVES_MAP1 = "/davesmap"
SLASH_DAVES_MAP2 = "/dmap"
SlashCmdList["DAVES_MAP"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "options" then
		ns:OpenOptions()
	elseif msg == "" or msg == "toggle" then
		ns.db.enabled = not ns.db.enabled
		ns.Print(ns.db.enabled and "map layer on." or "map layer off.")
		if ns.Refresh then ns.Refresh() end
	elseif msg == "panel" then
		ns.db.panelOpen = not ns.db.panelOpen
		if ns.UpdatePanel then ns.UpdatePanel() end
	elseif msg == "calib" then
		if ns.ReportCalibration then ns.ReportCalibration() end
	elseif msg == "version" then
		local D = ns.DATA
		ns.Print(ns.VERSION .. (D and (" - data: %s, %s, %s"):format(D.source.map, D.source.fetched, D.source.questDb or "no quest db") or " - no data"))
	else
		ns.Print("commands: /dmap [toggle | panel | options | calib | version]")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function daves_map_OnAddonCompartmentClick()
	ns:OpenOptions()
end
