-- daves_map / Core.lua
-- Startup, saved settings, events and the slash command.
--
-- The addon draws Map Genie's WoW Forever pins (Data.lua, built by tools/Update-MapData.py) as a layer of its own on
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

-- Quest log and super-tracking. Forever has the C_ forms. Warcraft Classic (TBC anniversary)
-- still answers the older globals, and there AddQuestWatch takes a log index, not a quest id.
-- Each C_ lookup is on one line so a missing function is skipped instead of called.
local LogIndexForID = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID
local TitleForID = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID
local InfoAt = C_QuestLog.GetInfo and C_QuestLog.GetInfo
local NumEntries = C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries
local IsComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete
local ReadyForTurnIn = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn
local IsOnMap = C_QuestLog.IsOnMap and C_QuestLog.IsOnMap
local WatchType = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType
local AddWatch = C_QuestLog.AddQuestWatch and C_QuestLog.AddQuestWatch
local RemoveWatch = C_QuestLog.RemoveQuestWatch and C_QuestLog.RemoveQuestWatch
local GetSuperTracked = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) or GetSuperTrackedQuestID
local SetSuperTracked = (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) or SetSuperTrackedQuestID
local SetSuperWaypoint = C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint
local CanSetWaypoint = C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap
local SetUserWaypoint = C_Map.SetUserWaypoint and C_Map.SetUserWaypoint

function ns.QuestLogIndex(questID)
	if LogIndexForID then return LogIndexForID(questID) end
	if GetQuestLogIndexByID then
		local idx = GetQuestLogIndexByID(questID)
		if idx and idx > 0 then return idx end
	end
end

function ns.QuestTitle(questID)
	if TitleForID then return TitleForID(questID) end
	local idx = ns.QuestLogIndex(questID)
	if idx and GetQuestLogTitle then return (GetQuestLogTitle(idx)) end
end

function ns.QuestInfo(index)
	if InfoAt then return InfoAt(index) end
	if not (index and index > 0 and GetQuestLogTitle) then return nil end
	-- TBC QuestLogFrame.lua: title, level, tag, isHeader, isCollapsed, isComplete, frequency, questID, ...
	local title, _, _, header, _, complete, _, questID, _, _, onMap, _, _, _, _, hidden = GetQuestLogTitle(index)
	if not title then return nil end
	return {
		title = title, isHeader = header, isComplete = complete,
		questID = questID, isOnMap = onMap, isHidden = hidden, isAutoComplete = false,
	}
end

function ns.NumQuestLogEntries()
	if NumEntries then return NumEntries() end
	return GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
end

function ns.QuestComplete(questID)
	if IsComplete then return IsComplete(questID) end
	if IsQuestComplete then return IsQuestComplete(questID) end
	local info = ns.QuestInfo(ns.QuestLogIndex(questID))
	return info and (info.isComplete == 1 or info.isComplete == true) or false
end

function ns.QuestReady(questID)
	if ReadyForTurnIn then return ReadyForTurnIn(questID) and true or false end
	return ns.QuestComplete(questID) and true or false
end

function ns.QuestOnMap(questID, info)
	if IsOnMap then return IsOnMap(questID) end
	return info and info.isOnMap or false
end

function ns.QuestWatched(questID)
	if WatchType then return WatchType(questID) ~= nil end
	local idx = ns.QuestLogIndex(questID)
	return (idx and IsQuestWatched and IsQuestWatched(idx)) and true or false
end

function ns.AddQuestWatch(questID)
	if AddWatch then return AddWatch(questID) end
	local idx = ns.QuestLogIndex(questID)
	if idx and AddQuestWatch then return AddQuestWatch(idx) end
end

function ns.RemoveQuestWatch(questID)
	if RemoveWatch then return RemoveWatch(questID) end
	local idx = ns.QuestLogIndex(questID)
	if idx and RemoveQuestWatch then return RemoveQuestWatch(idx) end
end

function ns.SuperTrackedQuest()
	return GetSuperTracked and GetSuperTracked() or 0
end

function ns.SetSuperTrackedQuest(questID)
	if SetSuperTracked then SetSuperTracked(questID) end
end

function ns.RegisterSuperTracking(frame)
	-- Forever fires SUPER_TRACKING_CHANGED. This Classic client fires SUPER_TRACKED_QUEST_CHANGED.
	pcall(frame.RegisterEvent, frame, "SUPER_TRACKING_CHANGED")
	pcall(frame.RegisterEvent, frame, "SUPER_TRACKED_QUEST_CHANGED")
end

-- True when a map pin was dropped. Classic has no user waypoint until those functions exist.
function ns.PlaceUserWaypoint(mapID, x, y)
	if not (mapID and x and y and SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
	if CanSetWaypoint and not CanSetWaypoint(mapID) then return false end
	SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
	if SetSuperWaypoint then SetSuperWaypoint(true) end
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
	daves_mapDB.myZoneOnly = nil   -- 0.3.3's map filter, replaced by trackMyZone in 0.3.4
	daves_mapDB.readyCollapsed = nil   -- the ready section opens expanded every session (Tracker.lua)
	daves_mapDB.readySection = nil     -- 0.3.4's tick: the ready section is always on now
	ns.db = daves_mapDB
	daves_mapCharDB = type(daves_mapCharDB) == "table" and daves_mapCharDB or {}
	if ns.InitStitch then ns.InitStitch(daves_mapDB, daves_mapCharDB) end   -- the seamless map's settings (Stitch\Base.lua)

	-- The map data lives in the companion addon daves_map_data (generated on this machine, not in git). It is our
	-- ## OptionalDeps, so when it's installed and enabled it has loaded by now and left one global behind.
	if type(DAVES_MAP_DATA) == "table" and DAVES_MAP_DATA.x then ns.DATA = DAVES_MAP_DATA end

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
	if ns.StartStitch then ns.StartStitch() end   -- the seamless map, with daves_map_textures (Stitch\Base.lua)
	local D = ns.DATA
	if D then
		ns.Print(("v%s loaded: %d map pins from %s (%s). /dmap for commands."):format(ns.VERSION, #D.x, D.source.map, D.source.fetched))
	else
		-- installed but not loaded (disabled, out of date, ...), or not on this machine at all?
		local exists = C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("daves_map_data")
		if exists then
			-- why it didn't load, in the game's own words (the AddOns list shows the same: ADDON_<reason>)
			local ok, _, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, "daves_map_data")
			local why = ok and type(reason) == "string" and reason ~= "" and (_G["ADDON_" .. reason] or reason) or nil
			ns.Print(("v%s: %s (Dave's Map (data) is installed but not loaded%s: check it in the AddOns list.)"):format(
				ns.VERSION, ns.NO_DATA, why and (", " .. why) or ""))
		else
			ns.Print(("v%s: %s (daves_map_data.zip: unzip it into Interface\\AddOns and restart the game.)"):format(ns.VERSION, ns.NO_DATA))
		end
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
			ns.Print("no seamless map: daves_map_textures isn't loaded (tools\\Update-MapTextures.py builds it).")
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
