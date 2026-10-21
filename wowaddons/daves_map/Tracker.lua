-- daves_map / Tracker.lua
-- The quest tracker: which of your log's quests it follows, and a "Ready to Turn In" section under it.
--
-- Track only my zone's quests: the tracker shows the quests in your log for the zone you're in, and the rest are
-- untracked (they stay in the log, and the map's markers are unchanged). A quest is this zone's when the quest log
-- files it under this zone's header, or the game puts it on this zone's map (C_QuestLog.IsOnMap). Event driven, no
-- polling: entering a zone, the loading screen, accepting a quest. On a flight the zones go by underneath, so it waits
-- for the landing (PLAYER_CONTROL_GAINED) and changes once.
--
-- Ready to Turn In: quests whose objectives are done leave Blizzard's tracker and are listed in a collapsible section
-- of our own just under it, wherever they're turned in; the zone tracking leaves them alone. Why not a module inside
-- Blizzard's tracker (ObjectiveTrackerManager:SetModuleContainer)? Adding to it from addon code would taint the whole
-- tracker, and its quest item buttons are secure: they'd be blocked in combat. So our section is a plain frame on
-- UIParent that only reads where the tracker's contents end and sits below them (Place, below).

local _, ns = ...

local events = CreateFrame("Frame")   -- our own: Layer.lua already answers QUEST_TURNED_IN on ns.events
events:SetScript("OnEvent", function(self, event, ...) if self[event] then self[event](self, ...) end end)

---------------------------------------------------------------------------
-- The quest log
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

local function IsReady(q)
	if C_QuestLog.ReadyForTurnIn then return C_QuestLog.ReadyForTurnIn(q) and true or false end
	return C_QuestLog.IsComplete(q) and true or false
end

-- the quests in your log: all of them, the set that is this zone's, and the ones ready to turn in (in log order)
local function LogQuests()
	local names, all, here, ready = ZoneNames(), {}, {}, {}
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
				if IsReady(q) then ready[#ready + 1] = q end
			end
		end
	end
	return all, here, ready, names
end

---------------------------------------------------------------------------
-- Which quests Blizzard's tracker follows
---------------------------------------------------------------------------
local function Watched(q) return C_QuestLog.GetQuestWatchType(q) ~= nil end

-- Each ready quest is moved out of Blizzard's tracker once, when it's first seen ready. Tracking it again yourself
-- sticks (it was untracked again on every quest log update, which fought you).
local movedOut = {}
local ourAdd = {}     -- [questID] = true: tracked by the zone tracking, not by you (QUEST_WATCH_LIST_CHANGED)
local accepted = {}   -- [questID] = true: just accepted, tracked by the game's own autoQuestWatch, not by you
local function MoveReadyOut(ready)
	for _, q in ipairs(ready) do
		if not movedOut[q] then
			movedOut[q] = true
			if Watched(q) then C_QuestLog.RemoveQuestWatch(q) end
		end
	end
end

local function TrackZoneQuests()
	local db = ns.db
	local all, here, ready = LogQuests()
	local isReady = {}
	for _, q in ipairs(ready) do isReady[q] = true end
	-- ready quests live in our section: out of Blizzard's tracker, whatever the zone
	MoveReadyOut(ready)
	if not db.trackMyZone or UnitOnTaxi("player") then return end   -- on a flight the landing comes back here
	if not next(ZoneNames()) then return end                          -- a loading screen: leave the tracker alone
	for _, q in ipairs(all) do
		if not isReady[q] and not db.pinned[q] then   -- the zone tracking ignores ready quests and pinned ones
			local watched = Watched(q)
			if here[q] and not watched then
				ourAdd[q] = true; C_Timer.After(2, function() ourAdd[q] = nil end)   -- its event, not a later one of yours
				C_QuestLog.AddQuestWatch(q)
			elseif not here[q] and watched then C_QuestLog.RemoveQuestWatch(q) end
		end
	end
end
ns.TrackZoneQuests = function() TrackZoneQuests(); ns.UpdateReady() end

---------------------------------------------------------------------------
-- Pins: a pinned quest stays tracked when you change zone. A small pin sits beside each quest in Blizzard's tracker
-- while "Track only my zone's quests" is on; click it to pin or unpin. The pins are our own buttons on UIParent,
-- anchored beside the tracker's quest blocks (read from QuestObjectiveTracker.usedBlocks, never changed). A pin goes
-- when its quest leaves the log or you untrack it yourself.
---------------------------------------------------------------------------
local PIN_ATLAS = (C_Texture.GetAtlasInfo("friendslist-recentallies-pin-yellow") and "friendslist-recentallies-pin-yellow")
	or (C_Texture.GetAtlasInfo("friends-icon-pinned") and "friends-icon-pinned") or nil
local pinButtons = {}   -- pool, one per quest shown in the tracker

local function PinTooltip(b)
	GameTooltip:SetOwner(b, "ANCHOR_LEFT")
	if ns.db.pinned[b.questID] then
		GameTooltip:AddLine("Pinned", 1, .82, 0)
		GameTooltip:AddLine("Stays tracked when you change zone. Click to unpin.", 1, 1, 1, true)
	else
		GameTooltip:AddLine("Pin", 1, .82, 0)
		GameTooltip:AddLine("Keep this quest tracked when you change zone.", 1, 1, 1, true)
	end
	GameTooltip:Show()
end

-- Pinned down: upright, in full colour. Not pinned: tipped over and grey, brighter under the mouse.
local function PaintPin(b)
	local on = ns.db.pinned[b.questID]
	b.icon:SetDesaturated(not on)
	b.icon:SetRotation(on and 0 or math.rad(-40))
	b.icon:SetAlpha(on and 1 or (b:IsMouseOver() and 1 or .6))
end

local function PinButton(n)
	local b = pinButtons[n]
	if b then return b end
	b = CreateFrame("Button", nil, UIParent)
	b:SetSize(16, 16)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	if PIN_ATLAS then b.icon:SetAtlas(PIN_ATLAS) else b.icon:SetTexture("Interface\\Buttons\\UI-CheckBox-Check") end
	b:SetScript("OnClick", function(self)
		ns.db.pinned[self.questID] = not ns.db.pinned[self.questID] or nil
		PaintPin(self); PinTooltip(self)
		-- unpinned: the zone check runs now, so a quest from another zone leaves the tracker straight away
		if not ns.db.pinned[self.questID] then
			GameTooltip:Hide()
			ns.TrackZoneQuests()
		end
	end)
	b:SetScript("OnEnter", function(self) PaintPin(self); PinTooltip(self) end)
	b:SetScript("OnLeave", function(self) PaintPin(self); if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
	pinButtons[n] = b
	return b
end

local PIN_MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }
local function UpdatePins()
	local n = 0
	local tracker = ObjectiveTrackerFrame
	if ns.db.trackMyZone and tracker and tracker:IsVisible() then
		local scale = tracker:GetEffectiveScale() / UIParent:GetEffectiveScale()
		for _, name in ipairs(PIN_MODULES) do
			local m = _G[name]
			if m and m.usedBlocks and m:IsVisible() then
				for _, blocks in pairs(m.usedBlocks) do
					for id, block in pairs(blocks) do
						if type(id) == "number" and block:IsVisible() and not C_QuestLog.IsComplete(id) then
							n = n + 1
							local b = PinButton(n)
							-- just left of the quest's map icon (its POI button sits left of the title:
							-- ObjectiveTrackerQuestPOIBlockMixin:AddPOIButton); left of the title when it has none
							local poi = block.poiButton
							local anchor = (poi and poi:IsShown()) and poi or (block.HeaderText or block)
							if b.block ~= block or b.questID ~= id or b.anchor ~= anchor then
								b.block, b.questID, b.anchor = block, id, anchor
								b:SetFrameStrata(tracker:GetFrameStrata())
								b:SetFrameLevel(block:GetFrameLevel() + 10)
								b:ClearAllPoints()
								if anchor == poi then b:SetPoint("RIGHT", poi, "LEFT", -1, 0)
								else b:SetPoint("RIGHT", anchor, "TOPLEFT", -6, -7) end
							end
							b:SetScale(scale)
							PaintPin(b)
							b:Show()
						end
					end
				end
			end
		end
	end
	for k = n + 1, #pinButtons do pinButtons[k]:Hide(); pinButtons[k].block = nil end
end

---------------------------------------------------------------------------
-- The Ready to Turn In section
---------------------------------------------------------------------------
local section, rows = nil, {}
local ROW_H, TITLE_H = 16, 26
local readyCollapsed = false   -- folded with its button; this session only: it opens expanded after a login or reload

-- the turn-in pin for a quest from the map data (Data.lua: a quest's pin and its endp), or nil
local pinOfQuest
local function TurnInPin(q)
	local D = ns.DATA
	if not D then return nil end
	if not pinOfQuest then
		pinOfQuest = {}
		for i = 1, #D.qid do local id = D.qid[i]; if id ~= 0 and not pinOfQuest[id] then pinOfQuest[id] = i end end
	end
	local i = pinOfQuest[q]
	local e = i and D.endp[i]
	return (e and e ~= 0) and e or nil
end

local function FontObject(name, fallback)
	local f = _G[name]
	if type(f) == "table" and f.GetObjectType and f:GetObjectType() == "Font" then return f end
	return fallback
end

-- Click: as clicking a quest in Blizzard's tracker does, the quest opens in the quest log on the map and is tracked
-- there (super-tracked: its turn-in on the map, the minimap and the arrow on screen). Where the game has no location
-- for it, the map data shows the turn-in instead (Layer.lua: ns.ShowQuestOnMap). Opening the map from addon code isn't
-- done in combat (it would taint the map); then only the tracking changes. Shift-click: our waypoint to the turn-in.
local function OnRowClick(row)
	local q = row.questID
	if not q then return end
	if IsShiftKeyDown() then
		if not row.turnIn then ns.Print("no turn-in location for this quest in the map data.") return end
		if WorldMapFrame and ns.InitLayer then ns.InitLayer() end   -- the waypoint uses the map layer's positions
		if ns.Calibrate() and ns.SetWaypoint then ns.SetWaypoint(row.turnIn) end
		return
	end
	C_SuperTrack.SetSuperTrackedQuestID(q)
	if InCombatLockdown() then
		ns.Print("tracking it; can't open the map in combat, click it again after.")
		return
	end
	if QuestMapFrame_OpenToQuestDetails then QuestMapFrame_OpenToQuestDetails(q) end
end

local function Row(n)
	local r = rows[n]
	if r then return r end
	r = CreateFrame("Button", nil, section)
	r:SetHeight(ROW_H * 2)
	r.title = r:CreateFontString(nil, "OVERLAY")
	r.title:SetFontObject(FontObject("ObjectiveTrackerLineFont", GameFontHighlight))
	r.title:SetPoint("TOPLEFT", 20, 0)   -- in line with the tracker's quest titles (its blockOffsetX)
	r.title:SetPoint("RIGHT", -4, 0)
	r.title:SetJustifyH("LEFT")
	r.title:SetWordWrap(false)
	r.where = r:CreateFontString(nil, "OVERLAY")
	r.where:SetFontObject(FontObject("ObjectiveTrackerLineFont", GameFontHighlightSmall))
	r.where:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 8, -2)
	r.where:SetPoint("RIGHT", -4, 0)
	r.where:SetJustifyH("LEFT")
	r.where:SetWordWrap(false)
	r.where:SetTextColor(.8, .8, .8)
	r:RegisterForClicks("LeftButtonUp")
	r:SetScript("OnClick", OnRowClick)
	r:SetScript("OnEnter", function(self)
		self.title:SetTextColor(1, 1, 1)
		if self.questID then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:AddLine(self.title:GetText(), 1, .82, 0)
			GameTooltip:AddLine("Click: open the quest and show where to turn it in", .5, .8, 1)
			if self.turnIn then GameTooltip:AddLine("Shift-click: a waypoint to where it's turned in", .5, .8, 1) end
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function(self)
		self.title:SetTextColor(1, .82, 0)
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	rows[n] = r
	return r
end

-- Where the section goes, read from the tracker (never written to):
-- - under the tracker's last section (Quests, or whatever follows it), anchored to it so the game keeps it there as
--   the tracker grows and shrinks: the container stacks its modules top to bottom and the last one that shows anything
--   is the bottom (ObjectiveTrackerContainerMixin:Update);
-- - alone: with nothing else tracked the tracker hides itself, so the section takes its place at the top under an
--   "All Objectives" header of its own, drawn as the tracker's (ObjectiveTrackerContainerHeaderTemplate);
-- - hidden while the tracker is collapsed, or hidden with something in it (a pet battle, a cinematic).
-- Why a watcher and not a hook: the tracker's updates run through a copy of its Update taken when it loaded
-- (DirtiableMixin:SetDirtyMethod), so hooksecurefunc on Update never sees them. A cheap check a few times a second
-- re-anchors only when the last section, or the tracker's shown or collapsed state, changes.
local ALL_H, GAP = 32, 4
local function TrackerState()
	local tracker = ObjectiveTrackerFrame
	local last
	for _, m in ipairs(tracker.modules or {}) do
		if m.GetContentsHeight and (m:GetContentsHeight() or 0) > 0 and m:IsShown() then last = m end
	end
	local shown = tracker:IsShown()
	local collapsed = tracker.IsCollapsed and tracker:IsCollapsed() or false
	return last, shown, collapsed
end

local placedLast, placedShown, placedCollapsed, placedWant
local function Place(force)
	local tracker = ObjectiveTrackerFrame
	if not (section and tracker) then return end
	local last, shown, collapsed = TrackerState()
	if not force and last == placedLast and shown == placedShown and collapsed == placedCollapsed and section.want == placedWant then return end
	placedLast, placedShown, placedCollapsed, placedWant = last, shown, collapsed, section.want
	local alone = not (last and shown)
	if alone ~= section.alone then
		section.alone = alone
		ns.UpdateReady()   -- lays out again with or without the All Objectives header; it calls back here
		return
	end
	section:SetShown(section.want and not collapsed and not (last and not shown))
	section:SetScale(tracker:GetEffectiveScale() / UIParent:GetEffectiveScale())   -- the tracker's size of text
	section:ClearAllPoints()
	if alone then   -- where the tracker's own header would be
		section:SetPoint("TOPLEFT", tracker.Header or tracker, "TOPLEFT")   -- its header keeps its place while hidden
	else
		section:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -(tracker.moduleSpacing or 10) - GAP)
	end
end

local HEADER_W = 260   -- Blizzard's header frames are this wide, their art centred on them
local function Build()
	if section or not ObjectiveTrackerFrame then return end
	section = CreateFrame("Frame", "DavesMapReadyToTurnIn", UIParent)
	section:SetFrameStrata(ObjectiveTrackerFrame:GetFrameStrata())
	section:SetSize(HEADER_W, TITLE_H)
	section:Hide()

	-- "All Objectives", only while the section is alone: ObjectiveTrackerContainerHeaderTemplate's measurements
	-- (Blizzard_ObjectiveTrackerContainer.xml): 260 by 32, art centred, text 7 in, the minimize button 1 in from the right
	local all = CreateFrame("Frame", nil, section)
	all:SetSize(HEADER_W, ALL_H)
	all:SetPoint("TOPLEFT")
	local allBg = all:CreateTexture(nil, "BACKGROUND")
	allBg:SetAtlas("ui-questtracker-primary-objective-header", true)
	allBg:SetPoint("CENTER")
	local allText = all:CreateFontString(nil, "ARTWORK")
	allText:SetFontObject(FontObject("ObjectiveTrackerHeaderFont", GameFontNormalMed2 or GameFontNormal))
	allText:SetPoint("LEFT", 7, 0)
	allText:SetText(TRACKER_ALL_OBJECTIVES or "All Objectives")
	local allBtn = CreateFrame("Button", nil, all)
	allBtn:SetSize(18, 19)
	allBtn:SetPoint("RIGHT", -1, 0)
	allBtn:SetNormalAtlas("ui-questtrackerbutton-collapse-all")
	allBtn:SetPushedAtlas("ui-questtrackerbutton-collapse-all-pressed")
	allBtn:SetHighlightAtlas("ui-questtrackerbutton-red-highlight", "ADD")
	allBtn:SetScript("OnClick", function() readyCollapsed = not readyCollapsed; ns.UpdateReady() end)
	section.all = all

	-- "Ready to Turn In (n)": ObjectiveTrackerModuleHeaderTemplate's (Blizzard_ObjectiveTrackerModule.xml): 260 by 26,
	-- art centred, text 7 in, a 16 by 16 minimize button 1 past the right edge
	local head = CreateFrame("Frame", nil, section)
	head:SetSize(HEADER_W, TITLE_H)
	local bg = head:CreateTexture(nil, "BACKGROUND")
	bg:SetAtlas("UI-QuestTracker-Secondary-Objective-Header", true)
	bg:SetPoint("CENTER")
	local text = head:CreateFontString(nil, "ARTWORK")
	text:SetFontObject(FontObject("ObjectiveTrackerHeaderFont", GameFontNormalMed2 or GameFontNormal))
	text:SetPoint("LEFT", 7, 0)
	section.text = text
	local btn = CreateFrame("Button", nil, head)
	btn:SetSize(16, 16)
	btn:SetPoint("RIGHT", 1, 0)
	btn:SetHighlightAtlas("ui-questtrackerbutton-yellow-highlight", "ADD")
	btn:SetScript("OnClick", function() readyCollapsed = not readyCollapsed; ns.UpdateReady() end)
	section.collapse = btn
	section.head = head

	local watcher, elapsed = CreateFrame("Frame"), 0
	watcher:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < .1 then return end
		elapsed = 0
		Place()
		UpdatePins()
	end)
end

function ns.UpdateReady()
	Build()
	if not section then return end
	local _, _, all = LogQuests()
	local ready = {}   -- the ones Blizzard's tracker isn't showing (a ready quest you track again shows there instead)
	for _, q in ipairs(all) do if not Watched(q) then ready[#ready + 1] = q end end
	-- a steady order: the quest log reorders itself (opening a quest, tracking one), which moved rows under the mouse.
	-- Grouped by where they're turned in, then by title.
	if ns.DATA and ns.Calibrate then ns.Calibrate() end   -- zones known from the start, so the order doesn't shift later
	local key = {}
	for _, q in ipairs(ready) do
		local e = TurnInPin(q)
		local zone = e and ns.IsCalibrated and ns.IsCalibrated() and ns.ZoneName(e) or "~"   -- unknown turn-ins last
		key[q] = zone .. "\1" .. (C_QuestLog.GetTitleForQuestID(q) or "") .. "\1" .. q
	end
	table.sort(ready, function(a, b) return key[a] < key[b] end)
	if #ready == 0 then section.want = false; section:Hide(); Place(true) return end
	local collapsed = readyCollapsed
	local top = section.alone and ALL_H or 0
	section.all:SetShown(section.alone and true or false)
	section.head:SetPoint("TOPLEFT", 0, -top)
	section.text:SetText(("Ready to Turn In (%d)"):format(#ready))
	local atlas = collapsed and "ui-questtrackerbutton-secondary-expand" or "ui-questtrackerbutton-secondary-collapse"
	if C_Texture.GetAtlasInfo(atlas) then section.collapse:SetNormalAtlas(atlas); section.collapse:SetPushedAtlas(atlas .. "-pressed") end
	local y = -top - TITLE_H - 6   -- a little room under the header before the first quest, as the tracker has
	for n, q in ipairs(collapsed and {} or ready) do
		local r = Row(n)
		r.questID, r.turnIn = q, TurnInPin(q)
		r.title:SetText(C_QuestLog.GetTitleForQuestID(q) or ("Quest " .. q))
		r.title:SetTextColor(1, .82, 0)
		local where = r.turnIn and ns.DATA.title[r.turnIn]
		local zone = r.turnIn and ns.IsCalibrated and ns.IsCalibrated() and ns.ZoneName(r.turnIn)
		r.where:SetText(where and ("Turn in: " .. where .. (zone and (" (" .. zone .. ")") or "")) or "Turn in")
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, y)
		r:SetPoint("RIGHT")
		r:Show()
		y = y - ROW_H * 2 - 2
	end
	for n = (collapsed and 0 or #ready) + 1, #rows do rows[n]:Hide() end
	section:SetHeight(-y)
	section.want = true   -- Place shows it, unless the tracker is collapsed
	Place(true)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- The quest log can lag the event by a moment (a new quest, a fresh login): run once, shortly after. Zone changes and
-- new quests re-decide the zone's tracking; quest log updates (an objective done) only move ready quests, so tracking
-- a quest by hand in this zone isn't undone every time the log changes.
local queued, queuedZone
local function Queue(zone, delay)
	queuedZone = queuedZone or zone
	if queued then return end
	queued = true
	C_Timer.After(delay or 1, function()
		local z = queuedZone
		queued, queuedZone = nil, nil
		if z then TrackZoneQuests() else
			local _, _, ready = LogQuests()   -- just the ready ones out of Blizzard's tracker
			MoveReadyOut(ready)
		end
		ns.UpdateReady()
	end)
end
events.ZONE_CHANGED_NEW_AREA = function() ns.TrackZoneQuests(); Queue(true) end   -- at once too (see below)
-- The loading screen: the rules apply at once, in this event, before the tracker draws (its updates run on the next
-- frame: DirtiableMixin), so it never shows the quests it is about to drop; then again a second later in case the
-- quest log was still filling in.
events.PLAYER_ENTERING_WORLD = function()
	if C_QuestLog.GetNumQuestLogEntries() > 0 then ns.TrackZoneQuests() end
	Queue(true)
end
events.PLAYER_CONTROL_GAINED = function() Queue(true) end
events.QUEST_ACCEPTED = function(_, q)
	if q then accepted[q] = true; C_Timer.After(2, function() accepted[q] = nil end) end   -- the game may auto-track it
	Queue(true)
end
events.QUEST_TURNED_IN = function() Queue(false, .3) end
events.QUEST_REMOVED = function(_, q) if q then ns.db.pinned[q] = nil end; Queue(false, .3) end
-- A quest tracked or untracked. Untracked (by you, or moved to the ready section): no longer pinned. Tracked by you
-- (the quest log, its shift-click, the map): pinned, so the zone tracking keeps it. Not when the zone tracking tracked
-- it, when the game did on accepting it (autoQuestWatch), or when it's ready to turn in (those aren't pinnable).
events.QUEST_WATCH_LIST_CHANGED = function(_, q, added)
	if not q then return end
	if added == false then ns.db.pinned[q] = nil return end
	if added ~= true then return end
	if ourAdd[q] then ourAdd[q] = nil return end
	if accepted[q] then accepted[q] = nil return end
	if ns.db.trackMyZone and not IsReady(q) then ns.db.pinned[q] = true end
end
events.QUEST_LOG_UPDATE = function() Queue(false, .3) end   -- an objective finished: the quest may be ready now
events.ADDON_LOADED = function(_, name) if name == "Blizzard_ObjectiveTracker" then Queue(false, .3) end end

local EVENTS = { "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "PLAYER_CONTROL_GAINED", "QUEST_ACCEPTED",
	"QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_WATCH_LIST_CHANGED", "QUEST_LOG_UPDATE", "ADDON_LOADED" }
function ns.InitTracker()   -- Core.lua, at PLAYER_LOGIN (before the first loading screen ends)
	for _, e in ipairs(EVENTS) do events:RegisterEvent(e) end
end

-- /dmap zone: what the tracking sees, to check it in game
function ns.ReportZone()
	local all, here, ready, names = LogQuests()
	local list = {}
	for n in pairs(names) do list[#list + 1] = n end
	ns.Print(("track only my zone's quests: %s; on a flight: %s"):format(ns.db.trackMyZone and "on" or "off",
		UnitOnTaxi("player") and "yes" or "no"))
	ns.Print("this zone goes by: " .. (#list > 0 and table.concat(list, ", ") or "(nothing)"))
	local mine = {}
	for _, q in ipairs(all) do if here[q] then mine[#mine + 1] = C_QuestLog.GetTitleForQuestID(q) or tostring(q) end end
	ns.Print(("your log: %d quests, %d for this zone%s; %d ready to turn in"):format(#all, #mine,
		#mine > 0 and (": " .. table.concat(mine, ", ")) or "", #ready))
end
