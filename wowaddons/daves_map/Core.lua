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
ns.NO_DATA = "Tell Dave to give me the data file."   -- shown in chat and on the map when daves_map_data isn't loaded

local DEFAULTS = {
	enabled = true,         -- draw the layer on the world map
	panelOpen = true,       -- the search and filter panel beside the map; its X, the map tab, /dmap panel and Options all set it
	pinScale = 1.0,         -- pin size
	hideCompleted = false,  -- completed quests are dimmed; hidden when this is on
	otherClasses = false,   -- show quests only other classes can take
	trackMyZone = true,     -- the quest tracker follows only your log's quests for the zone you're in (see below)
	hideHighLevel = false,  -- hide quests above your level
	hideLowLevel = false,   -- hide quests well below your level
	lowLevelGap = 5,        -- ...this many levels or more below it (1-5)
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
	daves_mapDB.myZoneOnly = nil   -- 0.3.3's map filter, replaced by trackMyZone in 0.3.4
	ns.db = daves_mapDB

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
	for _, e in ipairs({ "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_GAINED", "QUEST_ACCEPTED" }) do
		events:RegisterEvent(e)
	end
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
-- Track only my zone's quests: the quest tracker shows the quests in your log for the zone you're in, and the rest
-- are untracked (they stay in the log, and the map's markers are unchanged). A quest is this zone's when the quest log
-- files it under this zone's header, or the game puts it on this zone's map (C_QuestLog.IsOnMap).
-- Event driven, no polling: entering a zone, the loading screen, accepting a quest. On a flight the zones go by
-- underneath, so it waits for the landing (PLAYER_CONTROL_GAINED) and changes once.
---------------------------------------------------------------------------
local function ZoneOf(mapID)   -- the zone-level map holding mapID (a city or a cave is inside one)
	local guard = 0
	while mapID and mapID ~= 0 and guard < 12 do
		local info = C_Map.GetMapInfo(mapID)
		if not info then return nil end
		if info.mapType == Enum.UIMapType.Zone then return mapID end
		if info.mapType < Enum.UIMapType.Zone then return nil end   -- continent or wider
		mapID = info.parentMapID
		guard = guard + 1
	end
end

-- the names this zone goes by in the quest log's headers: the game's zone text, your map and its zone
local function ZoneNames()
	local names = {}
	local real = GetRealZoneText and GetRealZoneText()
	if type(real) == "string" and real ~= "" then names[real] = true end
	local best = C_Map.GetBestMapForUnit("player")
	for _, id in ipairs({ best or 0, ZoneOf(best) or 0 }) do
		local info = id ~= 0 and C_Map.GetMapInfo(id)
		if info and info.name then names[info.name] = true end
	end
	return names
end

-- the quests in your log: all of them, and the set that is this zone's
local function LogQuests()
	local names, all, here = ZoneNames(), {}, {}
	local header
	for idx = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(idx)
		if info then
			if info.isHeader then
				header = info.title
			elseif not info.isHidden and info.questID and info.questID ~= 0 then
				local q = info.questID
				all[#all + 1] = q
				if (header and names[header]) or C_QuestLog.IsOnMap(q) then here[q] = true end
			end
		end
	end
	return all, here, names
end

local function TrackZoneQuests()
	if not ns.db.trackMyZone then return end
	if UnitOnTaxi("player") then return end   -- the landing (PLAYER_CONTROL_GAINED) comes back here
	if not next(ZoneNames()) then return end  -- nowhere the game names (a loading screen): leave the tracker alone
	local all, here = LogQuests()
	for _, q in ipairs(all) do
		local watched = C_QuestLog.GetQuestWatchType(q) ~= nil
		if here[q] and not watched then C_QuestLog.AddQuestWatch(q)
		elseif not here[q] and watched then C_QuestLog.RemoveQuestWatch(q) end
	end
end
ns.TrackZoneQuests = TrackZoneQuests

-- the quest log can lag the event by a moment (a new quest, a fresh login): run once, shortly after
local trackQueued
local function QueueTrack()
	if trackQueued then return end
	trackQueued = true
	C_Timer.After(1, function() trackQueued = nil; TrackZoneQuests() end)
end
ns.ZONE_CHANGED_NEW_AREA = QueueTrack
ns.PLAYER_ENTERING_WORLD = QueueTrack
ns.PLAYER_CONTROL_GAINED = QueueTrack
ns.QUEST_ACCEPTED = QueueTrack

-- /dmap zone: what the tracking sees, to check it in game
function ns.ReportZone()
	local all, here, names = LogQuests()
	local list = {}
	for n in pairs(names) do list[#list + 1] = n end
	ns.Print(("track only my zone's quests: %s; on a flight: %s"):format(ns.db.trackMyZone and "on" or "off", UnitOnTaxi("player") and "yes" or "no"))
	ns.Print("this zone goes by: " .. (#list > 0 and table.concat(list, ", ") or "(nothing)"))
	local mine = {}
	for _, q in ipairs(all) do if here[q] then mine[#mine + 1] = C_QuestLog.GetTitleForQuestID(q) or tostring(q) end end
	ns.Print(("your log: %d quests, %d for this zone%s"):format(#all, #mine, #mine > 0 and (": " .. table.concat(mine, ", ")) or ""))
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
		local D = ns.DATA
		ns.Print(ns.VERSION .. (D and (" - data: %s, %s, %s"):format(D.source.map, D.source.fetched, D.source.questDb or "no quest db") or " - no data"))
	else
		ns.Print("commands: /dmap [toggle | panel | options | calib | zone | version]")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function daves_map_OnAddonCompartmentClick()
	ns:OpenOptions()
end
