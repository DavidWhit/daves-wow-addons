-- daves_map / Core.lua
-- Startup, saved settings, events and the slash command.
--
-- The addon draws QuestieDB Forever's pins, objectives, turn-ins and quest chains (companion addon daves_map_data,
-- built by tools/Update-MapData.py) as a taint-free layer on Blizzard's world map, with a search and filter panel
-- beside it (Layer.lua, Panel.lua) and OpenMap's seamless world & dungeon maps (Stitch\ + companion daves_map_textures).

local ADDON, ns = ...

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
ns.MEDIA = "Interface\\AddOns\\daves_map\\Media\\"

-- Map UI audio helper: plays at most one click sound per frame unless `force` is true, and suppresses sounds
-- inside `ns.WithMutedSound` when mirroring a quest selection triggered by Blizzard's own UI.
local soundState = { at = nil, muted = false }

function ns.Sound(name, force)
	local now = GetTime()
	if soundState.muted or (soundState.at == now and not force) then return end
	local id = SOUNDKIT and SOUNDKIT[name]
	if id then
		PlaySound(id)
		soundState.at = now
	end
end

function ns.WithMutedSound(fn)
	local was = soundState.muted
	soundState.muted = true
	xpcall(fn, CallErrorHandler)
	soundState.muted = was
end

-- Quest log and super-tracking helpers (Forever C_QuestLog / C_SuperTrack / C_Map APIs).
function ns.QuestLogIndex(questID)
	return C_QuestLog.GetLogIndexForQuestID(questID)
end

function ns.QuestInLog(questID)
	if type(questID) ~= "number" or questID == 0 or issecretvalue(questID) then return false end
	if C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(questID) == true end
	return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
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

-- Per-character quest completion check: excludes Warband/account-only completions where
-- C_QuestLog.IsQuestFlaggedCompleted(questID) is false, quests currently in this character's log,
-- and account-wide quests unless turned in by this character in daves_mapCharDB.doneQuests.
function ns.IsCharQuestCompleted(questID)
	if type(questID) ~= "number" or questID == 0 or issecretvalue(questID) then return false end
	if ns.QuestInLog(questID) then return false end
	if C_QuestLog.IsQuestFlaggedCompleted(questID) ~= true then return false end
	if C_QuestLog.IsAccountQuest and C_QuestLog.IsAccountQuest(questID) == true then
		return (daves_mapCharDB and daves_mapCharDB.doneQuests and daves_mapCharDB.doneQuests[questID]) == true
	end
	return true
end

function ns.ShowObjectiveTargets()
	return ns.DATA ~= nil and ns.db ~= nil
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

function ns.QuestLogCounts()
	local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
	local maxQuests = (C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or 25
	if issecretvalue(numQuests) or type(numQuests) ~= "number" then numQuests = 0 end
	if issecretvalue(maxQuests) or type(maxQuests) ~= "number" or maxQuests <= 0 then maxQuests = 25 end
	return numQuests, maxQuests
end

function ns.LinkQuestInChat(questID, openIfClosed)
	if type(questID) ~= "number" or questID == 0 or issecretvalue(questID) then return false end
	if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID then
		if ChatFrameUtil.TryInsertQuestLinkForQuestID(questID) then return true end
	end
	local link = GetQuestLink and GetQuestLink(questID)
	if not link or issecretvalue(link) then return false end
	local insertLink = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
	if insertLink and insertLink(link) then return true end
	if openIfClosed == true and ChatFrameUtil and ChatFrameUtil.OpenChat then
		ChatFrameUtil.OpenChat(link)
		return true
	end
	return false
end

function ns.ToggleQuestTrack(questID)
	if type(questID) ~= "number" or questID == 0 or issecretvalue(questID) or not ns.QuestInLog(questID) then
		return false
	end
	if ns.QuestWatched(questID) then
		if ns.db and ns.db.pinned then ns.db.pinned[questID] = nil end
		ns.RemoveQuestWatch(questID)
		ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
		return false
	end
	local maxWatches = (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES) or 25
	local curWatches = (C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches()) or 0
	if not issecretvalue(curWatches) and curWatches >= maxWatches then
		if UIErrorsFrame and OBJECTIVES_WATCH_TOO_MANY then
			UIErrorsFrame:AddMessage(OBJECTIVES_WATCH_TOO_MANY, 1.0, 0.1, 0.1, 1.0)
		else
			ns.Print("you are already tracking the maximum number of quests.")
		end
		return false
	end
	if ns.db and ns.db.trackMyZone and not ns.QuestReady(questID) then
		if type(ns.db.pinned) ~= "table" then ns.db.pinned = {} end
		ns.db.pinned[questID] = true
	end
	ns.AddQuestWatch(questID)
	ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	return true
end

function ns.PinQuest(questID)
	if issecretvalue(questID) or type(questID) ~= "number" or questID == 0 or not ns.QuestInLog(questID) then
		return false
	end
	if ns.QuestReady(questID) then return false end
	if ns.db and ns.db.pinned and ns.db.pinned[questID] then return false end
	local needWatch = not ns.QuestWatched(questID)
	if needWatch then
		local maxWatches = (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES) or 25
		local curWatches = (C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches()) or 0
		if not issecretvalue(curWatches) and curWatches >= maxWatches then
			if UIErrorsFrame and OBJECTIVES_WATCH_TOO_MANY then
				UIErrorsFrame:AddMessage(OBJECTIVES_WATCH_TOO_MANY, 1.0, 0.1, 0.1, 1.0)
			else
				ns.Print("you are already tracking the maximum number of quests.")
			end
			return false
		end
	end
	if ns.db then
		if type(ns.db.pinned) ~= "table" then ns.db.pinned = {} end
		ns.db.pinned[questID] = true
	end
	if needWatch then
		ns.AddQuestWatch(questID)
	end
	ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	return true
end

function ns.QuestComplete(questID)
	return C_QuestLog.IsComplete(questID)
end

function ns.QuestReady(questID)
	return C_QuestLog.ReadyForTurnIn(questID) == true
end

function ns.QuestUiMapID(questID, ignoreWaypoints)
	if type(questID) ~= "number" or issecretvalue(questID) or questID == 0 then return 0 end
	local m = GetQuestUiMapID and GetQuestUiMapID(questID, ignoreWaypoints == true) or 0
	return (type(m) == "number" and not issecretvalue(m)) and m or 0
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
	panelTab = "layers",    -- active left-rail tab: "layers" | "tracker" | "zone" | "dungeon"
	pinScale = 1.0,         -- pin size
	panelScale = 1.0,       -- Dave's Map window scale (0.5..1.5, matching daves_sack)
	background = 0.8,       -- Dave's Map background opacity (0.2..1.0, matching daves_sack)
	backgroundStyle = "dark", -- "dark" | "dialog" | "darkdialog" | "marble" | "rock" (matching daves_sack)
	hideCompleted = false,  -- completed quests show a green checkmark; hidden when this is on
	trackMyZone = true,     -- the quest tracker follows only your log's quests for the zone you're in (Tracker.lua)
	focusQuest = true,      -- a click on a tracked quest focuses it (again: unfocuses); the map then shows only its pins
	groupQuestCount = true, -- show party/raid quest-count number pills on Dave's Map & the Objective Tracker
	trackerTrackedOnly = false, -- in Tracker & Log, hide untracked Quest Log quests and show only currently tracked/active quests
	minimalQuestInfo = false,   -- minimal quest rows only (hides chains, chain steps, reward items, and Starter/XP columns)
	mapBanner = true,       -- top-center zone level bracket & coordinates pill on the map canvas
	questSort = "lvl",      -- "lvl" | "xp" | "starter" | "name"
	questSortAsc = true,    -- sort direction for questSort
}

-- Same 5 Blizzard dialog backgrounds offered by daves_sack.
ns.BACKGROUND_STYLES = {
	{ key = "dark",       name = "Dark" },
	{ key = "dialog",     name = "Light paper",  file = "Interface\\DialogFrame\\UI-DialogBox-Background", tile = true },
	{ key = "darkdialog", name = "Dark paper",   file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", tile = true },
	{ key = "marble",     name = "Marble",       file = "Interface\\FrameGeneral\\UI-Background-Marble", tile = true },
	{ key = "rock",       name = "Rock",         file = "Interface\\FrameGeneral\\UI-Background-Rock", tile = true },
}

function ns.BackgroundStyle(key)
	for _, s in ipairs(ns.BACKGROUND_STYLES) do
		if s.key == key then return s end
	end
	return ns.BACKGROUND_STYLES[1]
end

local LAYER_EXCLUDED_ICONS = {
	quest = true,
	repeatable = true,
	turnin = true,
	quest_objective = true,
}

function ns.IsCategoryToggleableInLayers(cat)
	return cat ~= nil and not LAYER_EXCLUDED_ICONS[cat.icon]
end

function ns.IsLayerCatOn(catId)
	return (ns.db and ns.db.layerOn and ns.db.layerOn[catId]) == true
end

function ns.IsTrackerTab()
	return (ns.db and ns.db.panelTab == "tracker") == true
end

function ns.ShowGroupQuestCount()
	return (ns.db and ns.db.groupQuestCount ~= false) == true
end

function ns.SetAllOptionalLayers(on)
	local D, db = ns.DATA, ns.db
	if not db then return end
	if type(db.layerOn) ~= "table" then db.layerOn = {} else wipe(db.layerOn) end
	if on and D and D.cats then
		for _, cat in ipairs(D.cats) do
			if ns.IsCategoryToggleableInLayers(cat) then
				db.layerOn[cat.id] = true
			end
		end
	end
end

-- Default faction checkboxes for this character: Alliance + Neutral (or Horde + Neutral).
function ns.DefaultFactions()
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	return { [1] = faction ~= "Horde", [2] = faction == "Horde", [3] = true }
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
	daves_mapDB.hidden = nil           -- replaced by layerOn in 0.8.0 (only tracked quest objectives draw by default)
	if type(daves_mapDB.layerOn) ~= "table" then daves_mapDB.layerOn = {} end -- [category id] = true: optional non-quest POI layer on
	if type(daves_mapDB.pinned) ~= "table" then daves_mapDB.pinned = {} end   -- [questID] = true: stays tracked across zones
	if type(daves_mapDB.questTitles) ~= "table" then daves_mapDB.questTitles = {} end   -- [questID] = title: Forever quest IDs -> titles
	if type(daves_mapDB.questRewards) ~= "table" then daves_mapDB.questRewards = {} end -- [questID] = { itemID, ... } from live client
	if type(daves_mapDB.zoneFold) ~= "table" then daves_mapDB.zoneFold = { locked = true, done = true } end
	daves_mapDB.myZoneOnly = nil   -- 0.3.3's map filter, replaced by trackMyZone in 0.3.4
	daves_mapDB.readyCollapsed = nil   -- the ready section opens expanded every session (Tracker.lua)
	daves_mapDB.readySection = nil     -- 0.3.4's tick: the ready section is always on now
	daves_mapDB.autoWaypoint = nil     -- removed in 0.7.2 so tracker focus & pinning stay 100% native
	daves_mapDB.filterDrawer = nil     -- removed in 0.7.3: faction & completed toggles sit directly on the sidebar
	daves_mapDB.otherClasses = nil     -- removed in 0.7.3: all quests for checked factions are shown
	daves_mapDB.hideHighLevel = nil    -- removed in 0.7.3: all quests for checked factions are shown
	daves_mapDB.hideLowLevel = nil     -- removed in 0.7.3: all quests for checked factions are shown
	daves_mapDB.lowLevelGap = nil      -- removed in 0.7.3
	daves_mapDB.factions = nil         -- moved per-character on daves_mapCharDB in 0.7.3
	daves_mapDB.panelOpen = nil        -- removed in 0.8.9: Dave's Map always opens/closes with WorldMapFrame
	daves_mapDB.panelPos = nil         -- removed in 0.9.1: unified single window anchored via WorldMapFrame
	daves_mapDB.panelW = nil           -- replaced by contentW in 0.9.1
	daves_mapDB.panelH = nil           -- removed in 0.9.1: unified window matches WorldMapFrame height
	ns.db = daves_mapDB
	daves_mapCharDB = type(daves_mapCharDB) == "table" and daves_mapCharDB or {}
	if type(daves_mapCharDB.doneQuests) ~= "table" then daves_mapCharDB.doneQuests = {} end
	ns.factions = type(daves_mapCharDB.factions) == "table" and daves_mapCharDB.factions or ns.DefaultFactions()
	if ns.InitStitch then ns.InitStitch(daves_mapDB, daves_mapCharDB) end   -- the seamless map's settings (Stitch\Base.lua)

	if type(DAVES_MAP_DATA) == "table" and DAVES_MAP_DATA.x then ns.DATA = DAVES_MAP_DATA end

	-- v0.8.4 schema v4: optional POI layers default on (toggled via right-side checkbox at top of Layers),
	-- while Zone / Dungeon quest markers remain explicit reference layers activated when clicked.
	if daves_mapDB.dataSchema ~= 4 then
		ns.SetAllOptionalLayers(true)
		daves_mapDB.panelTab = "layers"
		daves_mapDB.dataSchema = 4
	end
	if daves_mapDB.panelTab ~= "layers" and daves_mapDB.panelTab ~= "tracker" and daves_mapDB.panelTab ~= "zone" and daves_mapDB.panelTab ~= "dungeon" then
		daves_mapDB.panelTab = "layers"
	end

	ns:InitOptions()
	ns.EnforceWindowedOpaqueMap()
	-- the world map is a Blizzard add-on of its own: it may load before us or after
	if WorldMapFrame then ns.InitLayer() end
end

-- Keep Blizzard's World Map windowed (never fullscreen), opaque when moving (no mapFade),
-- and without Blizzard's built-in Quest Log side panel (questLogOpen = 0).
-- Uses taint-free CVar writes before WorldMapFrame opens so Blizzard's own WorldMapMixin:OnShow
-- opens map-only windowed securely without tainting WorldMapFrame.isMaximized in combat.
local maxMinHooked = false
function ns.EnforceWindowedOpaqueMap()
	if not InCombatLockdown() then
		if C_CVar and C_CVar.SetCVar then
			if not GetCVarBool or GetCVarBool("mapFade") then
				C_CVar.SetCVar("mapFade", "0")
			end
			if not GetCVarBool or not GetCVarBool("miniWorldMap") then
				C_CVar.SetCVar("miniWorldMap", "1")
			end
			if not GetCVarBool or GetCVarBool("questLogOpen") then
				C_CVar.SetCVar("questLogOpen", "0")
			end
		end
	end
	if WorldMapFrame then
		local a = WorldMapFrame:GetAlpha()
		if type(a) == "number" and not issecretvalue(a) and a < 1 then
			WorldMapFrame:SetAlpha(1)
		end
		local mm = WorldMapFrame.BorderFrame and WorldMapFrame.BorderFrame.MaximizeMinimizeFrame
		if mm then
			if not maxMinHooked then
				maxMinHooked = true
				mm:HookScript("OnShow", function(self)
					if not InCombatLockdown() then self:Hide() end
				end)
			end
			if not InCombatLockdown() then
				mm:Hide()
			end
		end
	end
end

function ns:PLAYER_LOGIN()
	if type(daves_mapCharDB.factions) ~= "table" then   -- { [1] Alliance, [2] Horde, [3] Neutral }: yours and neutral to start with
		daves_mapCharDB.factions = ns.DefaultFactions()
	end
	ns.factions = daves_mapCharDB.factions
	ns.EnforceWindowedOpaqueMap()
	if ns.InitQuests then ns.InitQuests() end
	ns.InitTracker()
	if ns.StartStitch then ns.StartStitch() end   -- the seamless map (Stitch\Base.lua)
	if ns.RefreshControls then ns.RefreshControls() end
	if ns.Refresh then ns.Refresh() end
	local D = ns.DATA
	if D then
		ns.Print(("v%s loaded: %d map pins from %s (%s). /dmap for commands."):format(ns.VERSION, #D.x, D.source.map, D.source.fetched))
	else
		ns.Print(("v%s loaded (no daves_map_data - %s)"):format(ns.VERSION, ns.NO_DATA))
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
	elseif msg == "style" or msg == "look" then
		if ns.ToggleStyleDialog then ns.ToggleStyleDialog() end
	elseif msg == "reset" or msg == "dock" then
		if ns.ResetPanelPosition then ns.ResetPanelPosition() end
		ns.Print("window position and size reset to default.")
	elseif msg == "" or msg == "toggle" then
		ns.db.enabled = not ns.db.enabled
		ns.Print(ns.db.enabled and "map layer on." or "map layer off.")
		if ns.NotifySetting then ns.NotifySetting("enabled") end
		if ns.RefreshOptions then ns.RefreshOptions() end
		if ns.Refresh then ns.Refresh() end
	elseif msg == "panel" then
		ns.Print("Dave's Map opens and closes automatically with the world map (M).")
	elseif msg == "zone" then
		ns.ReportZone()
	elseif msg == "check" or msg:match("^check%s+") then
		local qid = tonumber(msg:match("^check%s+(%d+)"))
		if qid then
			local title = ns.QuestTitle(qid) or "(unknown title)"
			local charFlag = C_QuestLog.IsQuestFlaggedCompleted(qid) == true
			local acctFlag = C_QuestLog.IsQuestFlaggedCompletedOnAccount and (C_QuestLog.IsQuestFlaggedCompletedOnAccount(qid) == true) or false
			local isAcct = C_QuestLog.IsAccountQuest and (C_QuestLog.IsAccountQuest(qid) == true) or false
			local inLog = ns.QuestInLog(qid)
			local done = ns.IsCharQuestCompleted(qid)
			local pin = ns.DATA and ns.QuestPin and ns.QuestPin(qid) or nil
			ns.Print(("Quest %d (%s): per-char=%s, onAccount=%s, accountQuest=%s, inLog=%s -> daves_map=%s%s"):format(
				qid, title, tostring(charFlag), tostring(acctFlag), tostring(isAcct), tostring(inLog),
				done and "DONE" or "NOT DONE", pin and "" or " [not in QuestieDB]"))
		elseif ns.DATA then
			local D = ns.DATA
			local total, charDone, acctOnly, inLog = 0, 0, 0, 0
			for i = 1, #D.qid do
				local q = D.qid[i]
				if q ~= 0 then
					total = total + 1
					if ns.QuestInLog(q) then
						inLog = inLog + 1
					elseif ns.IsCharQuestCompleted(q) then
						charDone = charDone + 1
					elseif C_QuestLog.IsQuestFlaggedCompletedOnAccount and C_QuestLog.IsQuestFlaggedCompletedOnAccount(q) == true then
						acctOnly = acctOnly + 1
					end
				end
			end
			ns.Print(("Per-character completion across %d Forever quests: %d done on this character, %d in log, %d completed only on another character (ignored). Usage: /dmap check <questID>"):format(
				total, charDone, inLog, acctOnly))
		else
			ns.Print(ns.NO_DATA)
		end
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
		ns.Print("commands: /dmap [toggle | reset | options | style | check [questID] | calib | zone | seamless | version]")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function daves_map_OnAddonCompartmentClick()
	ns:OpenOptions()
end
