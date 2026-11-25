-- daves_map / Focus.lua
-- Single owner of tracked-quest map objectives, explicit Zone/Dungeon reference marker layers,
-- single-pin selection highlight, Quest Text details sync, and map camera flight.

local _, ns = ...

local STEP_ZOOM = 4
local QUEST_ZOOM = 2
local IN_VIEW = 0.8
local Sound = ns.Sound
local Stitched = ns.IsStitched

local state = {
	lockedPin = nil,
	focusFor = nil,
	trackedSet = {},
	trackedQuestOfPin = {},
	trackedOwnerPin = {},
	refMode = nil,         -- nil | "zone" | "dungeon" (never draws until clicked)
	refMap = nil,
	refPinnedMap = nil,    -- pinned zone mapID for Zone/Dungeon reference links so out-of-zone navigation never wipes it
	sidebarDestZone = nil, -- destination zone mapID of the most recent Zone/Dungeon sidebar link flight
	inSidebarNav = false,  -- true while ShowPinMap is switching maps for a sidebar link
	sidebarNavAt = 0,
	refSet = {},
	refCount = 0,
	pendingOpen = nil,
	ownOpen = nil,
	lastFlight = nil,
	lastFlightAt = nil,
	autoFocusedAt = nil,
	mapShownAt = 0,
	hookedPOI = {},
	clickQuest = nil,
	clickFromTracker = nil,
	inQuestDetails = false,
	detailsOpenedByBlizzQ = nil,
	detailsOpenedByBlizzAt = 0,
	detailsHadPriorDetail = nil,
	hooksInstalled = false,
}

---------------------------------------------------------------------------
-- Tracked Quest Objectives & Click-Focus Model
---------------------------------------------------------------------------
function ns.SetClickFocus(q)
	daves_mapCharDB.focusClick = q
end

function ns.ClickFocus()
	return daves_mapCharDB.focusClick
end

function ns.ClickFocused(q)
	return q ~= nil and q == ns.ActiveFocusQuest()
end

local function HasMapPos(p)
	local P = ns.P
	return (p and p ~= 0 and P and ((P.zone[p] and P.zone[p] ~= 0) or (P.cont[p] and P.cont[p] ~= 0))) == true
end

function ns.ActivePinTarget(pin)
	local D = ns.DATA
	if not (D and pin) then return pin end
	ns.Calibrate()
	local st = ns.PinQuestState and ns.PinQuestState(pin) or nil
	local endp = D.endp[pin] ~= 0 and D.endp[pin] or nil
	local mappedEnd = (endp and HasMapPos(endp)) and endp or nil
	if st == "ready" and mappedEnd then
		return mappedEnd
	elseif st == "log" then
		for _, o in ipairs(D.obj and D.obj[pin] or {}) do
			if HasMapPos(o) then return o end
		end
		if mappedEnd then return mappedEnd end
	end
	return pin
end

function ns.ActiveFocusQuest()
	if not (ns.db and ns.db.focusQuest ~= false) then return nil end
	local clickQ = daves_mapCharDB and daves_mapCharDB.focusClick or nil
	local uiQ = ns.TrackerFocusQuestID and ns.TrackerFocusQuestID() or nil
	local superQ = ns.SuperTrackedQuest and ns.SuperTrackedQuest() or 0
	if issecretvalue(superQ) then superQ = 0 end
	if clickQ and not issecretvalue(clickQ) and ns.QuestInLog(clickQ) then
		if superQ == clickQ or (superQ == 0 and (uiQ == clickQ or (ns.KeepingFocus and ns.KeepingFocus(clickQ)))) then
			return clickQ
		end
	end
	if uiQ and not issecretvalue(uiQ) and ns.QuestInLog(uiQ) then
		if superQ == uiQ or superQ == 0 then
			return uiQ
		end
	end
	return nil
end

function ns.CollectTrackerQuests()
	local pinned = (ns.db and ns.db.pinned) or {}
	local focusQ = ns.ActiveFocusQuest()
	local buckets = { focused = {}, ready = {}, pinned = {}, tracking = {}, log = {} }
	local seenQ = {}
	local nEntries = ns.NumQuestLogEntries() or 0
	for idx = 1, nEntries do
		local info = ns.QuestInfo(idx)
		if info and not info.isHeader and not info.isHidden and info.questID and info.questID ~= 0 and not issecretvalue(info.questID) then
			local q = info.questID
			if not seenQ[q] then
				seenQ[q] = true
				if focusQ and q == focusQ then
					buckets.focused[#buckets.focused + 1] = q
				elseif ns.QuestReady(q) then
					buckets.ready[#buckets.ready + 1] = q
				elseif pinned[q] then
					buckets.pinned[#buckets.pinned + 1] = q
				elseif ns.QuestWatched(q) then
					buckets.tracking[#buckets.tracking + 1] = q
				else
					buckets.log[#buckets.log + 1] = q
				end
			end
		end
	end
	return buckets, focusQ
end

local function AddTrackedQuestPins(q, outSet, outQuestOf, outOwnerOf)
	local D = ns.DATA
	if not D then return end
	local list = ns.PinsOfQuest(q)
	if not (list and list[1]) and ns.FindQuestPinsForTracker then
		list = ns.FindQuestPinsForTracker(q)
	end
	if not (list and list[1]) then return end
	local pins = list
	if #list > 1 and ns.LogQuestIDForPin then
		local matched = {}
		for _, p in ipairs(list) do
			if ns.LogQuestIDForPin(p) == q then matched[#matched + 1] = p end
		end
		if #matched > 0 then pins = matched end
	end
	if #pins > 1 then
		local facMatched = {}
		for _, p in ipairs(pins) do
			if ns.PassesPlayerFilter(p) then facMatched[#facMatched + 1] = p end
		end
		if #facMatched > 0 then pins = facMatched end
	end
	local ready = ns.QuestReady(q) or ns.QuestComplete(q) == true
	for _, p in ipairs(pins) do
		local endp = D.endp[p] ~= 0 and D.endp[p] or nil
		local mappedEnd = (endp and HasMapPos(endp)) and endp or nil
		local addedAny = false
		if ready then
			local turnPin = mappedEnd or (HasMapPos(p) and p or nil)
			if turnPin then
				outSet[turnPin] = true
				outQuestOf[turnPin] = q
				outOwnerOf[turnPin] = p
				addedAny = true
			end
		else
			for _, o in ipairs(D.obj and D.obj[p] or {}) do
				if HasMapPos(o) then
					outSet[o] = true
					outQuestOf[o] = q
					outOwnerOf[o] = p
					addedAny = true
				end
			end
			if not addedAny then
				local fallback = mappedEnd or (HasMapPos(p) and p or nil)
				if fallback then
					outSet[fallback] = true
					outQuestOf[fallback] = q
					outOwnerOf[fallback] = p
				end
			end
		end
	end
end

local function SameSet(a, b)
	for k in pairs(a) do
		if not b[k] then return false end
	end
	for k in pairs(b) do
		if not a[k] then return false end
	end
	return true
end

local function UpdateFocus(force)
	local D = ns.DATA
	if not (D and ns.db and ns.Calibrate()) then
		local had = next(state.trackedSet) ~= nil or state.focusFor ~= nil
		wipe(state.trackedSet)
		wipe(state.trackedQuestOfPin)
		wipe(state.trackedOwnerPin)
		state.focusFor = nil
		return had
	end
	local buckets, focusQ = ns.CollectTrackerQuests()
	local nextSet, nextQuestOf, nextOwnerOf = {}, {}, {}
	if focusQ then
		AddTrackedQuestPins(focusQ, nextSet, nextQuestOf, nextOwnerOf)
	else
		for _, q in ipairs(buckets.ready) do
			AddTrackedQuestPins(q, nextSet, nextQuestOf, nextOwnerOf)
		end
		for _, q in ipairs(buckets.pinned) do
			AddTrackedQuestPins(q, nextSet, nextQuestOf, nextOwnerOf)
		end
		for _, q in ipairs(buckets.tracking) do
			AddTrackedQuestPins(q, nextSet, nextQuestOf, nextOwnerOf)
		end
	end
	local changed = force == true or focusQ ~= state.focusFor or not SameSet(state.trackedSet, nextSet)
	state.focusFor = focusQ
	state.trackedSet = nextSet
	state.trackedQuestOfPin = nextQuestOf
	state.trackedOwnerPin = nextOwnerOf
	return changed
end
ns.UpdateFocus = UpdateFocus

function ns.Focused()
	return state.focusFor ~= nil
end

function ns.TrackedContains(i)
	return state.trackedSet[i] == true
end

function ns.FocusContains(i)
	return state.focusFor ~= nil and state.trackedSet[i] == true
end

function ns.TrackedQuestForPin(i)
	return state.trackedQuestOfPin[i], state.trackedOwnerPin[i]
end

---------------------------------------------------------------------------
-- Explicit Zone / Dungeon Reference Marker Layer
---------------------------------------------------------------------------
function ns.RefLayerMode()
	return state.refMode
end

function ns.PinnedRefZone()
	return state.refPinnedMap
end

function ns.SidebarDestZone()
	return state.sidebarDestZone
end

function ns.NoteSidebarNavTarget(pinOrMap)
	local z = (pinOrMap and ns.P and ns.P.zone and ns.P.zone[pinOrMap]) or pinOrMap
	if type(z) == "number" and z ~= 0 then
		state.sidebarDestZone = z
	end
	state.sidebarNavAt = GetTime()
end

function ns.IsInSidebarNav()
	return state.inSidebarNav or (state.sidebarNavAt > 0 and (GetTime() - state.sidebarNavAt) < 0.25)
end

function ns.MapShownAt()
	return state.mapShownAt or 0
end

local function SyncSuspendAutoSwitch()
	local stitch = ns.StitchWorld and ns.StitchWorld()
	if stitch then
		stitch.suspendAutoSwitch = (state.refPinnedMap ~= nil)
	end
end

function ns.PinRefZone(mapID, allowAnyZone)
	if not mapID then
		state.refPinnedMap = nil
		state.sidebarDestZone = nil
		SyncSuspendAutoSwitch()
		return
	end
	if allowAnyZone then
		state.refPinnedMap = mapID
		SyncSuspendAutoSwitch()
		return
	end
	local D = ns.DATA
	if D and D.dungeons and D.dungeons[mapID] and #D.dungeons[mapID] > 0 then
		state.refPinnedMap = mapID
		SyncSuspendAutoSwitch()
	end
end

function ns.OnUserMapNavigate(quiet)
	local browsedAway = false
	if ns.MarkDungeonBrowseOther and not (ns.IsDungeonViewShown and ns.IsDungeonViewShown()) then
		browsedAway = ns.MarkDungeonBrowseOther() == true
	end
	local hadLock = state.refPinnedMap ~= nil or state.sidebarDestZone ~= nil
		or (ns.HasRefContextLock and ns.HasRefContextLock())
	if not (hadLock or browsedAway) then return false end
	state.refPinnedMap = nil
	state.sidebarDestZone = nil
	state.refMap = nil
	SyncSuspendAutoSwitch()
	if ns.ClearRefContext then
		ns.ClearRefContext()
	elseif ns.ClearDungeonContext then
		ns.ClearDungeonContext()
	end
	if not quiet then
		if ns.Refresh then
			ns.Refresh()
		elseif ns.OnLayerChanged then
			ns.OnLayerChanged()
		end
	end
	return true
end

function ns.SwitchRefZone(mapID)
	if not mapID then return end
	state.refPinnedMap = mapID
	state.refMap = nil
	SyncSuspendAutoSwitch()
	if ns.Refresh then ns.Refresh() end
end

function ns.SetRefLayer(mode, silent, keepLockedPin)
	if mode ~= "zone" and mode ~= "dungeon" then mode = nil end
	local clearedPin = false
	if mode == nil and not keepLockedPin and state.lockedPin ~= nil then
		state.lockedPin = nil
		clearedPin = true
	end
	if state.refMode == mode and not clearedPin then return false end
	state.refMode = mode
	state.refMap = nil
	state.refPinnedMap = nil
	state.sidebarDestZone = nil
	SyncSuspendAutoSwitch()
	state.refCount = 0
	wipe(state.refSet)
	if mode == "dungeon" then
		local zMap = (ns.ActiveDungeonZone and ns.ActiveDungeonZone()) or (ns.ViewZoneMap and ns.ViewZoneMap()) or (ns.CurrentMap and ns.CurrentMap())
		if ns.HasDungeonContextLock and ns.HasDungeonContextLock() then
			ns.PinRefZone(zMap, false)
		end
		if ns.RefreshRefLayerSet then ns.RefreshRefLayerSet(zMap) end
	elseif mode == "zone" then
		local zMap = (ns.ActiveZoneContext and ns.ActiveZoneContext()) or (ns.ViewZoneMap and ns.ViewZoneMap()) or (ns.CurrentMap and ns.CurrentMap())
		if ns.HasZoneContextLock and ns.HasZoneContextLock() then
			ns.PinRefZone(zMap, true)
		end
		if ns.RefreshRefLayerSet then ns.RefreshRefLayerSet(zMap) end
	elseif mode == nil then
		if ns.ClearRefContext then
			ns.ClearRefContext()
		elseif ns.ClearDungeonContext then
			ns.ClearDungeonContext()
		end
		if clearedPin and not state.focusFor then ns.CloseQuestDetailsIfShown() end
	end
	if not silent then
		Sound(mode and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
	end
	if ns.Refresh then
		ns.Refresh()
	elseif ns.OnLayerChanged then
		ns.OnLayerChanged()
	end
	return true
end

function ns.RefreshRefLayerSet(zMap)
	wipe(state.refSet)
	state.refCount = 0
	local D, db = ns.DATA, ns.db
	if db and (db.panelTab == "tracker" or db.panelTab == "layers") then
		if state.refMode ~= nil or state.refPinnedMap ~= nil or state.sidebarDestZone ~= nil then
			state.refMode = nil
			state.refPinnedMap = nil
			state.sidebarDestZone = nil
			SyncSuspendAutoSwitch()
		end
		state.refMap = nil
		return
	end
	if not (state.refMode and D and db and ns.Calibrate()) then
		state.refMap = nil
		return
	end
	local useMap = state.refPinnedMap or zMap
	if state.refMode == "dungeon" and not state.refPinnedMap and ns.ActiveDungeonZone then
		local activeDZ = ns.ActiveDungeonZone()
		if activeDZ then useMap = activeDZ end
	end
	if not useMap then
		state.refMap = nil
		return
	end
	state.refMap = useMap
	local hideDone = db.hideCompleted == true
	if state.refMode == "zone" then
		local dungQuestPins = {}
		local zoneDungs = D.dungeons and D.dungeons[useMap]
		if zoneDungs then
			for _, d in ipairs(zoneDungs) do
				for _, qi in ipairs(d.quests or {}) do dungQuestPins[qi] = true end
			end
		end
		local idx = ns.PinsOnMap(useMap).idx
		for _, i in ipairs(idx) do
			local ic = D.cats[D.cat[i]].icon
			if not dungQuestPins[i] and (ic == "quest" or ic == "repeatable")
				and ns.PassesPlayerFilter(i) and not (hideDone and ns.PinDone(i)) then
				state.refSet[i] = true
				state.refCount = state.refCount + 1
			end
		end
	elseif state.refMode == "dungeon" then
		local zoneDungs = D.dungeons and D.dungeons[useMap]
		if zoneDungs then
			for _, d in ipairs(zoneDungs) do
				if d.pin and d.pin ~= 0 then
					state.refSet[d.pin] = true
				end
				for _, qi in ipairs(d.quests or {}) do
					if not state.refSet[qi] and ns.PassesPlayerFilter(qi) and not (hideDone and ns.PinDone(qi)) then
						state.refSet[qi] = true
						state.refCount = state.refCount + 1
					end
				end
			end
		end
	end
	if state.lockedPin and ns.PassesPlayerFilter(state.lockedPin) then
		local ic = D.cats[D.cat[state.lockedPin]].icon
		if ic == "quest" or ic == "repeatable" or ic == "instance" then
			state.refSet[state.lockedPin] = true
		end
	end
end

function ns.RefLayerContains(i)
	if ns.IsTrackerTab and ns.IsTrackerTab() then return false end
	return state.refMode ~= nil and state.refSet[i] == true
end

function ns.RefLayerSummary()
	if not state.refMode then return nil, nil, 0 end
	local zMap = state.refPinnedMap or state.refMap
		or (ns.ViewZoneMap and ns.ViewZoneMap()) or (ns.CurrentMap and ns.CurrentMap())
	local info = zMap and C_Map.GetMapInfo(zMap)
	return state.refMode, info and info.name or "Zone", state.refCount
end

---------------------------------------------------------------------------
-- Single Pin Selection & Quest Text Details Sync
---------------------------------------------------------------------------
function ns.FocusedPin()
	return state.lockedPin
end

function ns.ClearDisabledSelection()
	state.lockedPin = nil
end

function ns.RevalidateFocusOnFilterChange()
	UpdateFocus(true)
	if state.lockedPin and not state.trackedSet[state.lockedPin]
		and not (ns.LogQuestIDForPin and ns.LogQuestIDForPin(state.lockedPin))
		and not ns.PassesPlayerFilter(state.lockedPin) then
		state.lockedPin = nil
	end
end

function ns.CloseQuestDetailsIfShown()
	if ns.CloseQuestDetails then
		ns.CloseQuestDetails(true)
	end
end

local function QuestIDForDetails(pin)
	local tq = state.trackedQuestOfPin[pin]
	if tq and ns.QuestInLog(tq) then return tq end
	local q = ns.LogQuestIDForPin and ns.LogQuestIDForPin(pin) or nil
	if q then return q end
	if ns.ResolveActiveChainPin and ns.LogQuestIDForPin then
		local activePin = ns.ResolveActiveChainPin(pin)
		if activePin and activePin ~= pin then
			return ns.LogQuestIDForPin(activePin)
		end
	end
	return nil
end

-- Quest details now render inside Dave's Map (`QuestDetails.lua`) instead of Blizzard's QuestMapFrame.
-- Keep active drill-in details synced when a background chain step advances, without popping Blizzard's side panel.
function ns.SyncQuestDetailsPane(pin, _targetMapHint, fromBgEvent)
	if not (pin and ns.DATA and WorldMapFrame and WorldMapFrame:IsShown()) then
		return false
	end
	local q = QuestIDForDetails(pin)
	if fromBgEvent then
		if q and ns.PanelUI and ns.PanelUI.detailQuestID and ns.OpenQuestDetails then
			ns.OpenQuestDetails(q, pin, true)
			return true
		end
		return false
	end
	if ns.PanelUI and ns.PanelUI.detailQuestID and q and ns.OpenQuestDetails then
		ns.OpenQuestDetails(q, pin, true)
		return true
	end
	return false
end

function ns.SyncActiveChainStep()
	local changed = UpdateFocus(false)
	if not state.lockedPin then return changed end
	local activePin = ns.ResolveActiveChainPin and ns.ResolveActiveChainPin(state.lockedPin) or state.lockedPin
	if activePin and activePin ~= state.lockedPin then
		state.lockedPin = activePin
		if WorldMapFrame and WorldMapFrame:IsShown() then ns.SyncQuestDetailsPane(activePin, nil, true) end
		return true
	end
	return changed
end

function ns.SetFocusedPin(i, silent)
	local D = ns.DATA
	local focusChanged = false
	if state.focusFor then
		local keepTracked = false
		if i and D then
			if state.trackedQuestOfPin[i] == state.focusFor
				or D.qid[i] == state.focusFor
				or (ns.LogQuestIDForPin and ns.LogQuestIDForPin(i) == state.focusFor) then
				keepTracked = true
			else
				local prevCh = ns.ChainFor(i)
				local focusPin = ns.QuestPin(state.focusFor)
				if not focusPin and ns.FindQuestPinsForTracker then
					local foundPins = ns.FindQuestPinsForTracker(state.focusFor)
					focusPin = foundPins and foundPins[1] or nil
				end
				keepTracked = (prevCh and focusPin and prevCh.set and prevCh.set[focusPin]) == true
			end
		end
		if not keepTracked then
			local prev = state.focusFor
			ns.SetClickFocus(nil)
			if ns.ClearTrackerFocus then ns.ClearTrackerFocus() end
			if prev and ns.SuperTrackedQuest() == prev then ns.SetSuperTrackedQuest(0) end
			focusChanged = UpdateFocus(false)
		end
	end
	if state.lockedPin == i then
		if focusChanged or state.refMode ~= nil then
			if ns.Refresh then ns.Refresh() end
		elseif ns.OnLayerChanged then
			ns.OnLayerChanged()
		end
		return
	end
	state.lockedPin = i
	if not silent then
		Sound(state.lockedPin and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
	end
	-- Always rebuild the canvas layer when selection changes so clicking/clearing a quest while the
	-- reference layer is hidden updates the map immediately (instead of waiting for a pan/zoom).
	if ns.Refresh then
		ns.Refresh()
	elseif ns.OnLayerChanged then
		ns.OnLayerChanged()
	end
end

function ns.Focus(i)
	local nextPin = (i ~= state.lockedPin) and i or nil
	ns.SetFocusedPin(nextPin, false)
end

function ns.ClearQuestFocus()
	local fq = ns.ClickFocus()
	state.pendingOpen = nil
	ns.SetClickFocus(nil)
	if fq and ns.SuperTrackedQuest() == fq then ns.SetSuperTrackedQuest(0) end
	state.lockedPin = nil
	if ns.ClearTrackerFocus then ns.ClearTrackerFocus() end
	ns.CloseQuestDetailsIfShown()
	Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
	UpdateFocus(true)
	if ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Map Camera Flight & ScrollContainer Zoom
---------------------------------------------------------------------------
local function FlyView(mapID, u, v, factor, keepZoom)
	local stitch, S = ns.StitchWorld()
	if not u then
		local l, r, t, b = S.Rect(mapID)
		u, v = (l + r) / 2, (t + b) / 2
	end
	local zFit = stitch.FitZoom(mapID)
	local zoom
	if factor and factor > 1 then
		local effFactor = zFit > 14 and math.min(factor, 1.45) or factor
		zoom = math.min(36, math.max(zFit * 1.35, zFit * effFactor))
	else
		zoom = zFit * (factor or 1)
	end
	if keepZoom then
		local _, _, now = stitch.ViewNow()
		if now and now > zoom then zoom = now end
	end
	stitch.Fly(u, v, zoom)
end

local function FlyToMap(mapID, u, v, closer)
	local _, S = ns.StitchWorld()
	if not (Stitched() and S and mapID and S.Rect(mapID) and WorldMapFrame and WorldMapFrame:IsShown()) then
		return false
	end
	FlyView(mapID, u, v, closer, closer ~= nil)
	return true
end

local function SetWorldMapID(mapID)
	WorldMapFrame:SetMapID(mapID)
end

local function ShowMap(mapID)
	if FlyToMap(mapID) then return true end
	if not mapID or not (WorldMapFrame and WorldMapFrame:IsShown()) or mapID == WorldMapFrame:GetMapID() then
		return false
	end
	if InCombatLockdown() then
		ns.Print("can't change the map in combat.")
		return false
	end
	SetWorldMapID(mapID)
	return true
end
ns.ShowMapByID = ShowMap

local function LeftSidebarPad(totalW)
	local panel = ns.PanelFrame and ns.PanelFrame()
	if totalW > 0 and panel and panel:IsShown()
		and ((WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()) or (ns.IsPanelDockedInside and ns.IsPanelDockedInside())) then
		return math.min(totalW * 0.45, panel:GetWidth() + 18)
	end
	return 0
end

local function PanZoomScrollContainer(x, y, zoomIn)
	if InCombatLockdown() then return false end
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	if not (sc and sc.Child and sc.SetZoomTarget and sc.SetPanTarget and sc.GetScaleForMaxZoom
		and sc.zoomLevels and #sc.zoomLevels > 0) then
		return false
	end
	local cw, chH = sc.Child:GetSize()
	local vw, vh = sc:GetSize()
	if not (cw and chH and cw > 0 and chH > 0 and vw and vh and vw > 0 and vh > 0) then
		return false
	end
	local curScale = (sc.GetCanvasScale and sc:GetCanvasScale()) or 1
	local minScale = (sc.GetScaleForMinZoom and sc:GetScaleForMinZoom()) or curScale
	local maxScale = sc:GetScaleForMaxZoom() or minScale
	local scale
	if zoomIn then
		scale = math.min(maxScale, math.max(curScale, minScale * 1.6))
	else
		scale = math.max(minScale, math.min(maxScale, curScale))
		local curX = sc.GetCurrentScrollX and sc:GetCurrentScrollX()
		local curY = sc.GetCurrentScrollY and sc:GetCurrentScrollY()
		if curX and curY and cw * scale > 0 and chH * scale > 0 then
			local halfX = (vw * 0.5) / (cw * scale)
			local halfY = (vh * 0.5) / (chH * scale)
			if math.abs(x - curX) < halfX * IN_VIEW and math.abs(y - curY) < halfY * IN_VIEW then
				return false
			end
		end
	end
	local padL = LeftSidebarPad(vw)
	local cx, cy = x, y
	if padL > 0 and cw * scale > 0 then
		cx = cx - (padL * 0.5) / (cw * scale)
	end
	if sc.CalculateScrollExtentsAtScale then
		local minX, maxX, minY, maxY = sc:CalculateScrollExtentsAtScale(scale)
		cx = math.max(minX, math.min(maxX, cx))
		cy = math.max(minY, math.min(maxY, cy))
	end
	if sc.SetScalingMode then sc:SetScalingMode("SCALING_MODE_LINEAR") end
	sc:SetZoomTarget(scale)
	sc:SetPanTarget(cx, cy)
	return true
end

function ns.ShowPinMap(i, close, fromSidebar)
	local P = ns.P
	if not (P and i) then return false end
	local targetZone = P.zone[i]
	if fromSidebar then
		state.inSidebarNav = true
		state.sidebarNavAt = GetTime()
		if targetZone and targetZone ~= 0 then state.sidebarDestZone = targetZone end
	end
	local stitch, S = ns.StitchWorld()
	if close and not Stitched() and stitch and stitch.enabled and S and targetZone and S.Rect(targetZone)
		and WorldMapFrame and WorldMapFrame:IsShown() and not InCombatLockdown() then
		SetWorldMapID(targetZone)
	end
	local result = false
	local u, v
	if Stitched() then u, v = ns.WorldUV(i) end
	if u and stitch then
		local cu, cv, zoom = stitch.ViewNow()
		if cu and not close then
			local hu, hv = stitch.ViewHalfExtents(zoom)
			if math.abs(u - cu) < hu * IN_VIEW and math.abs(v - cv) < hv * IN_VIEW then
				if fromSidebar then state.inSidebarNav = false end
				return false
			end
		end
		if FlyToMap(targetZone, u, v, close and STEP_ZOOM or nil) then
			if fromSidebar then state.inSidebarNav = false end
			return true
		end
	end
	result = ShowMap(targetZone)
	if not Stitched() and targetZone and WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == targetZone then
		local x, y = ns.ProjectPin(targetZone, i)
		if x and y and PanZoomScrollContainer(x, y, close == true) then
			result = true
		end
	end
	if fromSidebar then state.inSidebarNav = false end
	return result
end

---------------------------------------------------------------------------
-- Map State Snapshots & Find-Player Action
---------------------------------------------------------------------------
function ns.CaptureMapState()
	if not WorldMapFrame then return nil end
	local mapID = (ns.CurrentMap and ns.CurrentMap()) or WorldMapFrame:GetMapID()
	local stitch = ns.StitchWorld()
	if Stitched() and stitch and stitch.ViewNow then
		local u, v, zoom = stitch.ViewNow()
		if u then return { seamless = true, map = mapID, u = u, v = v, zoom = zoom } end
	end
	return mapID and { seamless = false, map = mapID } or nil
end

function ns.RestoreMapState(mapState)
	ns.CloseDungeonView()
	if not (mapState and WorldMapFrame and WorldMapFrame:IsShown()) then return end
	local stitch = ns.StitchWorld()
	if mapState.seamless and Stitched() and stitch and mapState.u and mapState.v and stitch.Fly then
		local targetZoom = mapState.zoom or (mapState.map and stitch.FitZoom and stitch.FitZoom(mapState.map)) or 1
		local cu, cv, cz
		if stitch.ViewNow then cu, cv, cz = stitch.ViewNow() end
		if not (cu and math.abs(cu - mapState.u) < 1e-5 and math.abs(cv - mapState.v) < 1e-5 and math.abs((cz or 1) - targetZoom) < 1e-3) then
			stitch.Fly(mapState.u, mapState.v, targetZoom)
		end
	elseif mapState.map then
		ShowMap(mapState.map)
	end
end

function ns.FindPlayer()
	local clearedLock = ns.OnUserMapNavigate(true)
	local clearedBrowse = (ns.ClearDungeonBrowseOther and ns.ClearDungeonBrowseOther() == true) or false
	local stitch = ns.StitchWorld()
	if stitch and stitch.DungeonViewShown and stitch.DungeonViewShown() and stitch.CloseDungeonView then
		stitch.CloseDungeonView()
	end
	if stitch and stitch.FindMe and stitch:FindMe(false) then
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		if (clearedLock or clearedBrowse) and ns.Refresh then ns.Refresh() end
		return
	end
	local best = C_Map.GetBestMapForUnit("player")
	if best and best ~= 0 then
		if stitch then stitch.lastSwitchAt = GetTime() end
		ShowMap(best)
		if not Stitched() and WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID() == best then
			local pos = C_Map.GetPlayerMapPosition(best, "player")
			if pos then
				local px, py = pos.x, pos.y
				if pos.GetXY then px, py = pos:GetXY() end
				if type(px) == "number" and type(py) == "number" and not issecretvalue(px) and not issecretvalue(py) and (px ~= 0 or py ~= 0) then
					if PanZoomScrollContainer(px, py, true) then
						Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
					end
				end
			end
		end
	end
	if (clearedLock or clearedBrowse) and ns.Refresh then ns.Refresh() end
end

---------------------------------------------------------------------------
-- Blizzard Tracker, Quest Log & Unmapped Quest Fallback Hooks
---------------------------------------------------------------------------
local function FlyToQuestOn(mapID, questID, keepZoom)
	local stitch = ns.StitchWorld()
	local u, v
	local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
	for _, q in ipairs(ok and type(quests) == "table" and quests or {}) do
		if q.questID == questID and q.x and q.y and not issecretvalue(q.x) and not issecretvalue(q.y) then
			u, v = stitch.ToWorld(mapID, q.x, q.y)
			break
		end
	end
	if not u then
		local rawPin = ns.QuestPin and ns.QuestPin(questID)
		if not rawPin and ns.FindQuestPinsForTracker then
			local foundPins = ns.FindQuestPinsForTracker(questID)
			rawPin = foundPins and foundPins[1] or nil
		end
		local target = rawPin and ns.ActivePinTarget(rawPin) or nil
		if target then u, v = ns.WorldUV(target) end
	end
	FlyView(mapID, u, v, u and QUEST_ZOOM or 1, keepZoom)
end

local function QuestDetailsStitchedMap(questID)
	local _, S = ns.StitchWorld()
	if not (Stitched() and S and questID and not issecretvalue(questID)) then return nil end
	local mapID = WorldMapFrame:GetMapID()
	local d = QuestMapFrame and QuestMapFrame.DetailsFrame
	if mapID and d and d.questMapID == mapID and S.Rect(mapID) then return mapID end
	return nil
end

local function RestoreBeforeReset()
	local stitch = ns.StitchWorld()
	if stitch and stitch.ViewBeforeReset then
		local u0, v0, z0 = stitch.ViewBeforeReset()
		if u0 then stitch.ShowNow(u0, v0, z0) end
	end
end

local function FlyToQuest(questID)
	local mapID = QuestDetailsStitchedMap(questID)
	if not mapID then return end
	RestoreBeforeReset()
	FlyToQuestOn(mapID, questID, true)
end

local function CentreQuest(q)
	local _, S = ns.StitchWorld()
	if not (WorldMapFrame and WorldMapFrame:IsShown() and Stitched() and S) then return end
	local mapID = ns.QuestUiMapID and ns.QuestUiMapID(q, true) or (GetQuestUiMapID and GetQuestUiMapID(q, true))
	if type(mapID) ~= "number" or issecretvalue(mapID) or mapID == 0 or not S.Rect(mapID) then return end
	FlyToQuestOn(mapID, q, true)
end

function ns.PlainLeftClick(button)
	return button == "LeftButton" and not IsShiftKeyDown() and not IsModifiedClick("CHATLINK")
end

function ns.QuestClicked(q, how, toggleSound, fromTracker)
	if not (ns.db and type(q) == "number" and q ~= 0) or issecretvalue(q) then return nil end
	-- Navigating from Blizzard's real Quest Log, Objective Tracker, or map quest pins releases any Zone/Dungeon sidebar lock.
	local unlockedRef = ns.OnUserMapNavigate(true)
	local rawPin = (ns.DATA and ns.Calibrate()) and ns.QuestPin(q) or nil
	if not rawPin and fromTracker and ns.FindQuestPinsForTracker then
		local foundPins = ns.FindQuestPinsForTracker(q)
		rawPin = foundPins and foundPins[1] or nil
	end
	local pin = rawPin
	if rawPin and not ns.QuestInLog(q) and ns.ResolveActiveChainPin then
		pin = ns.ResolveActiveChainPin(rawPin)
	end
	local focusEnabled = ns.db.focusQuest ~= false
	if not focusEnabled and not fromTracker then
		if unlockedRef and ns.Refresh then ns.Refresh() end
		return nil
	end

	local now = ns.SuperTrackedQuest()
	local reopen = state.pendingOpen == q and not InCombatLockdown()
	state.pendingOpen = nil
	local mapAlreadyOpen = WorldMapFrame ~= nil and WorldMapFrame:IsShown() and (GetTime() - state.mapShownAt > .1)
	local fromBlizzDetails = (state.detailsOpenedByBlizzQ == q and state.detailsOpenedByBlizzAt == GetTime())
	local prevDetailQ = fromBlizzDetails and state.detailsHadPriorDetail or (ns.PanelUI and ns.PanelUI.detailQuestID or nil)
	local alreadyFocused = ns.ClickFocused(q)
	local letGo
	if not focusEnabled then
		if how == "focused" then
			letGo = now ~= q and not reopen
			if letGo and not (pin ~= nil and state.lockedPin == pin) and prevDetailQ ~= q then return false end
		else
			local matchedPrev = (pin ~= nil and state.lockedPin == pin) or (pin == nil and prevDetailQ == q)
			letGo = matchedPrev and not reopen and state.autoFocusedAt ~= GetTime() and mapAlreadyOpen
		end
	elseif how == "toggle" then
		letGo = alreadyFocused and not reopen and mapAlreadyOpen
	elseif how == "focused" then
		letGo = now ~= q and not reopen
	else
		letGo = false
	end
	if toggleSound then
		Sound(letGo and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
	end
	if letGo then
		if fromBlizzDetails and ns.PopRecentTrackerPush then
			ns.PopRecentTrackerPush()
		end
		ns.SetClickFocus(nil)
		if focusEnabled and now == q then ns.SetSuperTrackedQuest(0) end
		if state.lockedPin then ns.SetFocusedPin(nil, true) end
		if ns.ClearTrackerFocus then ns.ClearTrackerFocus() end
		ns.CloseQuestDetailsIfShown()
		UpdateFocus(true)
		if ns.Refresh then ns.Refresh() end
		if not (state.lastFlight == q and state.lastFlightAt == GetTime()) then
			CentreQuest(q)
		end
		return true
	end

	if fromTracker then
		-- Focused tracker quests stay on the Base map layer (tracked/focused objectives + base POIs)
		-- and drill into the quest's text inside the integrated `Tracker` tab.
		ns.SetRefLayer(nil, true)
	end
	ns.SetFocusedPin(pin, true)
	if focusEnabled then ns.SetClickFocus(q) end
	if fromTracker and ns.OpenTrackerTab then
		ns.OpenTrackerTab(focusEnabled and q or nil, pin, fromBlizzDetails, true, q)
	end
	if how == "focused" and reopen and now ~= q then
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON", true)
	end
	if now ~= q then
		ns.SetSuperTrackedQuest(q)
	elseif (UpdateFocus(false) or unlockedRef) and ns.Refresh then
		ns.Refresh()
	end
	if how == "details" then
		if ns.OpenQuestDetails and ns.QuestInLog(q) then
			ns.OpenQuestDetails(q, pin)
		end
		FlyToQuest(q)
		return false
	end
	if WorldMapFrame and WorldMapFrame:IsShown() then
		if pin then
			local target = ns.ActivePinTarget(pin)
			if mapAlreadyOpen then
				ns.ShowPinMap(target, true)
			else
				C_Timer.After(0, function()
					if WorldMapFrame and WorldMapFrame:IsShown() then
						ns.ShowPinMap(target, true)
					end
				end)
			end
		else
			CentreQuest(q)
		end
		return false
	end
	if InCombatLockdown() then
		state.pendingOpen = q
		ns.Print("focused it; can't open the map in combat: click it again after combat to see it.")
		return false
	end
	if OpenWorldMap then
		state.ownOpen = true
		xpcall(OpenWorldMap, CallErrorHandler)
		state.ownOpen = nil
	end
	if pin then
		local target = ns.ActivePinTarget(pin)
		C_Timer.After(0, function()
			if WorldMapFrame and WorldMapFrame:IsShown() then
				ns.ShowPinMap(target, true)
			end
		end)
	else
		C_Timer.After(0, function()
			if WorldMapFrame and WorldMapFrame:IsShown() then
				CentreQuest(q)
			end
		end)
	end
	return false
end

local function BeforePOIClick(poi)
	local accept = state.hookedPOI[poi]
	local q = (accept == true or accept(poi)) and poi.GetQuestID and poi:GetQuestID() or nil
	state.clickQuest = q
	state.clickFromTracker = type(accept) == "function"
end

local function OnPOIClick(_, button)
	local q, fromTracker = state.clickQuest, state.clickFromTracker
	state.clickQuest, state.clickFromTracker = nil, nil
	if q and ns.PlainLeftClick(button) then
		ns.QuestClicked(q, "focused", false, fromTracker)
	end
end

function ns.HookQuestPOI(poi, accept)
	if not poi or state.hookedPOI[poi] then return end
	state.hookedPOI[poi] = accept or true
	poi:HookScript("PreClick", BeforePOIClick)
	poi:HookScript("OnClick", OnPOIClick)
end

function ns.ShowQuestOnMap(q)
	local D = ns.DATA
	if not (D and ns.Calibrate()) then return nil end
	local raw = ns.QuestPin(q)
	if not raw then return false end
	local i = (ns.ResolveActiveChainPin and ns.ResolveActiveChainPin(raw)) or raw
	ns.WithMutedSound(function()
		if state.lockedPin ~= i then
			state.autoFocusedAt = GetTime()
			ns.SetFocusedPin(i, true)
		end
		ns.ShowPinMap(ns.ActivePinTarget(i))
	end)
	return true
end

local function OnQuestDetails(q)
	if state.inQuestDetails or state.ownOpen or type(q) ~= "number" or issecretvalue(q) then
		return
	end
	ns.OnUserMapNavigate(false)
	if ns.QuestInLog(q) and ns.OpenTrackerTab then
		state.detailsHadPriorDetail = ns.PanelUI and ns.PanelUI.detailQuestID or nil
		state.detailsOpenedByBlizzQ = q
		state.detailsOpenedByBlizzAt = GetTime()
		ns.OpenTrackerTab(nil, nil, false, true, q)
	end
	if not GetQuestUiMapID or GetQuestUiMapID(q) ~= 0 then
		return
	end
	if ns.ShowQuestOnMap(q) == false and ns.ShowUnmappedQuestFallback then
		ns.ShowUnmappedQuestFallback(q)
		return
	end
end

function ns.MarkMapShownNow()
	state.mapShownAt = GetTime()
end

function ns.InitFocus()
	if state.hooksInstalled then return end
	state.hooksInstalled = true
	ns.RegisterSuperTracking(ns.events)
	ns.events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
	ns.events:RegisterEvent("QUEST_ACCEPTED")
	ns.events:RegisterEvent("QUEST_REMOVED")
	UpdateFocus(true)
	if ns.db and (ns.db.panelTab == "zone" or ns.db.panelTab == "dungeon") then
		state.refMode = ns.db.panelTab
	end

	local stitch = ns.StitchWorld and ns.StitchWorld()
	if stitch then
		stitch.onUserMapNav = function()
			ns.OnUserMapNavigate(false)
		end
	end

	if QuestMapFrame_ShowQuestDetails then
		hooksecurefunc("QuestMapFrame_ShowQuestDetails", OnQuestDetails)
	end
	if QuestMapFrame_OpenToQuestDetails then
		hooksecurefunc("QuestMapFrame_OpenToQuestDetails", function(questID)
			state.lastFlight, state.lastFlightAt = questID, GetTime()
			if state.inQuestDetails then
				RestoreBeforeReset()
				return
			end
			if not state.ownOpen then
				ns.OnUserMapNavigate(false)
			end
			if GetTime() - state.mapShownAt > .1 then
				if not state.ownOpen then Sound("IG_MAINMENU_OPTION_CHECKBOX_ON") end
				FlyToQuest(questID)
				return
			end
			local mapID = WorldMapFrame:IsShown() and QuestDetailsStitchedMap(questID)
			C_Timer.After(0, function()
				if not WorldMapFrame:IsShown() then return end
				if mapID and Stitched() and WorldMapFrame:GetMapID() == mapID then
					FlyToQuestOn(mapID, questID, false)
				end
			end)
		end)
	end
	if QuestPinMixin and QuestPinMixin.OnMouseClickAction then
		hooksecurefunc(QuestPinMixin, "OnMouseClickAction", function(pin, button)
			if pin.GetMap and pin:GetMap() ~= WorldMapFrame then return end
			if ns.PlainLeftClick(button) then ns.QuestClicked(pin.GetQuestID and pin:GetQuestID(), "focused", false, true) end
		end)
	end
	local contents = QuestScrollFrame and QuestScrollFrame.Contents
	if contents and contents.GetButtonForQuest and contents.FindButtonByQuestID then
		hooksecurefunc(contents, "GetButtonForQuest", function(owner, questID)
			ns.HookQuestPOI(owner:FindButtonByQuestID(questID))
		end)
		if contents.buttonPool then
			for poi in contents.buttonPool:EnumerateActive() do ns.HookQuestPOI(poi) end
		end
	end
	if QuestMapLogTitleButton_OnClick then
		hooksecurefunc("QuestMapLogTitleButton_OnClick", function(button, mouseButton)
			if ns.PlainLeftClick(mouseButton) then ns.QuestClicked(button and button.questID, "details") end
		end)
	end
end

local function PinBelongsToQuest(pin, q)
	if not (pin and q and ns.DATA) then return false end
	if state.trackedQuestOfPin[pin] == q or ns.DATA.qid[pin] == q then return true end
	if ns.LogQuestIDForPin and ns.LogQuestIDForPin(pin) == q then return true end
	for tp, owner in pairs(state.trackedOwnerPin) do
		if owner == pin and state.trackedQuestOfPin[tp] == q then return true end
	end
	return false
end

function ns:SUPER_TRACKING_CHANGED()
	local q, mine = ns.SuperTrackedQuest(), ns.ClickFocus()
	local trackedFoc = mine or (ns.TrackerFocusQuestID and ns.TrackerFocusQuestID())
	local clearedPin = false
	if trackedFoc and q and not issecretvalue(q) and q ~= trackedFoc and not (q == 0 and ns.KeepingFocus and ns.KeepingFocus(trackedFoc)) then
		ns.SetClickFocus(nil)
		if ns.ClearTrackerFocus then ns.ClearTrackerFocus() end
		if state.refMode == nil and PinBelongsToQuest(state.lockedPin, trackedFoc) then
			state.lockedPin = nil
			clearedPin = true
		end
	end
	if (UpdateFocus(false) or clearedPin) and ns.Refresh then
		ns.Refresh()
	elseif WorldMapFrame and WorldMapFrame:IsVisible() and ns.db and ns.db.panelTab == "tracker" and ns.OnLayerChanged then
		ns.OnLayerChanged()
	end
end

local function RefreshTrackedIfChanged(forceRefresh)
	if WorldMapFrame and WorldMapFrame:IsVisible() then
		if (UpdateFocus(false) or forceRefresh) and ns.Refresh then
			ns.Refresh()
		elseif ns.db and ns.db.panelTab == "tracker" and ns.OnLayerChanged then
			ns.OnLayerChanged()
		end
	elseif ns.Refresh then
		ns.Refresh()
	elseif ns.OnLayerChanged then
		ns.OnLayerChanged()
	end
end

function ns:QUEST_WATCH_LIST_CHANGED(q, added)
	local clearedPin = false
	if added == false and type(q) == "number" and not issecretvalue(q)
		and not (ns.KeepingFocus and ns.KeepingFocus(q)) then
		local cleared = false
		if ns.ClickFocus() == q then
			ns.SetClickFocus(nil)
			cleared = true
		end
		if ns.TrackerFocusQuestID and ns.TrackerFocusQuestID() == q then
			if ns.ClearTrackerFocus then ns.ClearTrackerFocus() end
			cleared = true
		end
		if cleared and state.refMode == nil and PinBelongsToQuest(state.lockedPin, q) then
			state.lockedPin = nil
			clearedPin = true
		end
	end
	RefreshTrackedIfChanged(clearedPin)
end

function ns:QUEST_ACCEPTED()
	C_Timer.After(0.1, RefreshTrackedIfChanged)
end

function ns:QUEST_REMOVED()
	RefreshTrackedIfChanged()
end
