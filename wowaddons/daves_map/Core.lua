-- daves_map / Core.lua
-- Startup, saved settings, events and the slash command.
--
-- The addon draws QuestieDB Forever's pins, objectives, turn-ins and quest chains (companion addon daves_map_data,
-- built by tools/Update-MapData.py) as a taint-free layer on Blizzard's world map, with a search and filter panel
-- beside it (Layer.lua, Panel.lua) and OpenMap's seamless world & dungeon maps (Stitch\ + companion daves_map_textures).

local ADDON, ns = ...

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

-- Quest log and super-tracking helpers (Forever C_QuestLog / C_SuperTrack / C_Map APIs).
function ns.QuestLogIndex(questID)
	return C_QuestLog.GetLogIndexForQuestID(questID)
end

function ns.QuestTitle(questID)
	if type(questID) ~= "number" or questID == 0 or issecretvalue(questID) then return nil end
	local t = C_QuestLog.GetTitleForQuestID(questID)
	if type(t) == "string" and not issecretvalue(t) and t ~= "" then
		if ns.db and ns.db.questTitles then ns.db.questTitles[questID] = t end
		return t
	end
	return ns.db and ns.db.questTitles and ns.db.questTitles[questID] or nil
end

function ns.CompletedQuestIDs()
	return C_QuestLog.GetAllCompletedQuestIDs()
end

function ns.RequestQuestTitle(questID)
	if C_QuestLog.RequestLoadQuestByID then C_QuestLog.RequestLoadQuestByID(questID) end
end

function ns.QuestInfo(index)
	return C_QuestLog.GetInfo(index)
end

function ns.NumQuestLogEntries()
	return C_QuestLog.GetNumQuestLogEntries()
end

function ns.QuestComplete(questID)
	return C_QuestLog.IsComplete(questID)
end

function ns.QuestReady(questID)
	return C_QuestLog.ReadyForTurnIn(questID) and true or false
end

function ns.QuestUiMapID(questID)
	return GetQuestUiMapID and GetQuestUiMapID(questID) or 0
end

function ns.QuestWatched(questID)
	return C_QuestLog.GetQuestWatchType(questID) ~= nil
end

function ns.AddQuestWatch(questID)
	return C_QuestLog.AddQuestWatch(questID)
end

function ns.RemoveQuestWatch(questID)
	return C_QuestLog.RemoveQuestWatch(questID)
end

function ns.SuperTrackedQuest()
	return C_SuperTrack.GetSuperTrackedQuestID() or 0
end

function ns.SetSuperTrackedQuest(questID)
	C_SuperTrack.SetSuperTrackedQuestID(questID)
end

function ns.RegisterSuperTracking(frame)
	frame:RegisterEvent("SUPER_TRACKING_CHANGED")
end

function ns.PlaceUserWaypoint(mapID, x, y)
	if not (mapID and x and y and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
	if not C_Map.CanSetUserWaypointOnMap(mapID) then return false end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	return true
end
ns.NO_DATA = "Tell Dave to give me the data file."   -- shown in chat and on the map when daves_map_data isn't loaded

local DEFAULTS = {
	enabled = true,         -- draw the layer on the world map
	panelOpen = true,       -- the search and filter panel beside the map; its X, the map tab, /dmap panel and Options all set it
	pinScale = 1.0,         -- pin size
	hideCompleted = false,  -- completed quests are dimmed; hidden when this is on
	otherClasses = false,   -- show quests only other classes can take
	trackMyZone = true,     -- the quest tracker follows only your log's quests for the zone you're in (Tracker.lua)
	focusQuest = true,      -- a click on a tracked quest focuses it (again: unfocuses); the map then shows only its pins
	hideHighLevel = false,  -- hide quests more than 5 levels above yours
	hideLowLevel = false,   -- hide quests well below your level
	lowLevelGap = 5,        -- ...more than this many levels below it (1-5)
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
	if type(daves_mapDB.pinned) ~= "table" then daves_mapDB.pinned = {} end   -- [questID] = true: stays tracked across zones
	if type(daves_mapDB.questTitles) ~= "table" then daves_mapDB.questTitles = {} end   -- [questID] = title: Forever quest IDs -> titles
	daves_mapDB.myZoneOnly = nil   -- 0.3.3's map filter, replaced by trackMyZone in 0.3.4
	daves_mapDB.readyCollapsed = nil   -- the ready section opens expanded every session (Tracker.lua)
	daves_mapDB.readySection = nil     -- 0.3.4's tick: the ready section is always on now
	ns.db = daves_mapDB
	daves_mapCharDB = type(daves_mapCharDB) == "table" and daves_mapCharDB or {}
	if ns.InitStitch then ns.InitStitch(daves_mapDB, daves_mapCharDB) end   -- the seamless map's settings (Stitch\Base.lua)

	if type(DAVES_MAP_DATA) == "table" and DAVES_MAP_DATA.x then ns.DATA = DAVES_MAP_DATA end

	-- Seed default-off categories cleanly on QuestieDB schema v2 (wiping stale legacy Map Genie category IDs).
	if ns.DATA and daves_mapDB.dataSchema ~= 2 then
		wipe(daves_mapDB.hidden)
		for _, c in ipairs(ns.DATA.cats or {}) do
			if c.defaultOff then daves_mapDB.hidden[c.id] = true end
		end
		daves_mapDB.dataSchema = 2
	end

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
	ns.InitTracker()
	if ns.StartStitch then ns.StartStitch() end   -- the seamless map (Stitch\Base.lua)
	local D = ns.DATA
	if D then
		ns.Print(("v%s loaded: %d map pins from %s (%s). /dmap for commands."):format(ns.VERSION, #D.x, D.source.map, D.source.fetched))
	else
		ns.Print(("v%s loaded (no daves_map_data — %s)"):format(ns.VERSION, ns.NO_DATA))
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
	elseif msg == "zone" then
		ns.ReportZone()
	elseif msg == "calib" then
		if ns.ReportCalibration then ns.ReportCalibration() end
	elseif msg == "version" then
		local D, OM = ns.DATA, ns.OM
		ns.Print(ns.VERSION .. (D and (" - data: %s, %s, %s"):format(D.source.map, D.source.fetched, D.source.questDb or "no quest db") or " - no data")
			.. (OM and (" - textures: OpenMap %s, %s"):format(OM.openMapVersion, OM.built) or " - no textures"))
	elseif msg == "seamless" then
		local mod = ns.OM and ns.OM:GetModule("worldmap")
		if not mod then
			ns.Print("no daves_map_textures: the seamless map isn't installed.")
		elseif mod.padWaits then
			ns.Print(mod.PadOffText())
		elseif not mod.enabled then
			ns.Print("the seamless map is off (Options, or OpenMap is on).")
		else
			mod:Diag()
		end
	else
		ns.Print("commands: /dmap [toggle | panel | options | calib | zone | seamless | version]")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function daves_map_OnAddonCompartmentClick()
	ns:OpenOptions()
end
