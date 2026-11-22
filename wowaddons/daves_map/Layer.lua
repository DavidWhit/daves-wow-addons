-- daves_map / Layer.lua
-- Taint-free world map canvas overlay: tracked quest objectives, optional POI layers, explicit Zone/Dungeon
-- reference markers, zoom-distance LOD fades, and hover/click hit-testing.
--
-- Sits on WorldMapFrame:GetCanvas() as a plain addon frame (never calling AddDataProvider or AcquirePin, so Blizzard's
-- pin pools and SetPassThroughButtons stay 100% untainted in combat). Reads quest/chain data from Quests.lua,
-- tracked/reference layer state from Focus.lua, and delegates tooltips & canvas banners to Tooltip.lua.

local _, ns = ...

local BASE = 15
local HIT_R = 0.55
local EDGE = 0.025
local WIN = 2
local HOVER_MIN_ALPHA = 0.25

local STITCH_ICON_LEVELS = { "PIN_FRAME_LEVEL_DAVES_MAP_STITCH_ICONS", "PIN_FRAME_LEVEL_OPENMAP_ICONS" }

local ATLAS = {
	quest = { "QuestNormal" }, repeatable = { "QuestNormal" },
	turnin = { "UI-QuestPoi-QuestBangTurnIn", "QuestTurnin" },
	quest_objective = { "Quest-In-Progress-Icon-yellow", "QuestObjective" },
	graveyard = { "poi-soulspiritghost", "poi-graveyard-neutral" },
	flight_master = { "TaxiNode_Neutral" }, instance = { "Dungeon" },
	treasure = { "VignetteLoot" }, rare = { "VignetteKillElite", "VignetteKill" },
}

local TRACKING = {
	auctioneer = "auction", banker = "bank", innkeeper = "innkeeper", mailbox = "mailbox", repair_vendor = "repair",
	stable_master = "stable", transmogrifier = "transmog", barber_shop = "barber", bonus_objective = "battle",
	merchant = "food", flight_master = "flight", class_trainer = "class", profession_trainer = "profession",
	_files = {
		class_trainer = "Interface\\GossipFrame\\TrainerGossipIcon",
		profession_trainer = "Interface\\GossipFrame\\TrainerGossipIcon",
		merchant = "Interface\\GossipFrame\\VendorGossipIcon",
		repair_vendor = "Interface\\GossipFrame\\VendorGossipIcon",
		turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
		quest_objective = "Interface\\GossipFrame\\IncompleteQuestIcon",
	},
}

local SIZE = { city = 1.5, town = 1.2, instance = 1.25, rare = 1.15, quest_objective = 0.95 }
local DONE_ATLASES = { "UI-LFG-ReadyMark", "common-icon-checkmark", "ui-questtracker-tracker-check" }
local doneAtlas
if C_Texture and C_Texture.GetAtlasInfo then
	for _, a in ipairs(DONE_ATLASES) do
		if C_Texture.GetAtlasInfo(a) then doneAtlas = a; break end
	end
end

local view = {
	overlay = nil, hot = nil, notice = nil,
	icons = {}, rings = {}, linked = {},
	nIcons = 0, nRings = 0, nLinked = 0, nDone = 0,
	actPin = {}, actX = {}, actY = {},
	trkPin = {}, trkX = {}, trkY = {},
	tierAlpha = { 0, 0, 0, 0, 0 }, tierMask = 0, builtTierMask = -1, lodZoom = 1,
	iconBaseAlpha = {}, iconAlpha = {}, iconDone = {},
	styles = {}, catByIcon = nil, shown = {},
	posX = {}, posY = {}, seamX = {}, seamY = {},
	win = nil, builtSeamless = false,
	checkedScale = nil, checkedX = nil, checkedY = nil, checkedW = nil, checkedH = nil,
	wasAnimating = false,
	curMap = nil, curViewZone = nil, curScale = nil, curZoom = nil, curStitchZoom = nil, curW = nil, curH = nil,
	dirty = true, panelNotified = false, hoverPin = nil, lastCX = nil, lastCY = nil, searchSet = nil,
}

---------------------------------------------------------------------------
-- Seamless View Helpers, Zoom-Distance LOD Fades & Filter Predicates
---------------------------------------------------------------------------
local function Seamless()
	return ns.IsStitched() and view.curMap == WorldMapFrame:GetMapID()
end
ns.IsSeamless = Seamless

local function UpdateLodFades(seamless, sz, zoom)
	view.lodZoom, view.tierMask = ns.ComputeLodFades(seamless, view.curMap, sz, zoom, view.tierAlpha)
end

local function IsAlwaysSharpPin(i)
	return view.searchSet ~= nil or ns.TrackedContains(i) or i == ns.FocusedPin()
end

local function PinLodAlpha(i, isDone)
	if IsAlwaysSharpPin(i) then return 1 end
	return view.tierAlpha[ns.PinZoomTier(i, isDone)] or 0
end

function ns.IsZoomedOutForPins()
	return (view.tierMask or 0) < 4
end

function ns.IsRefLayerZoomedOut()
	return (view.tierAlpha[3] or 0) <= 0
end

local function WindowStale(flying)
	local win = view.win
	if not win then return true end
	local stitch = ns.StitchWorld()
	if not stitch then return false end
	local u, v, zoom = stitch.ViewNow()
	if not u then return false end
	local hu, hv = stitch.ViewHalfExtents(zoom)
	return u - hu < win[1] or u + hu > win[2] or v - hv < win[3] or v + hv > win[4]
		or (zoom > win[5] * 2 and not flying) or zoom < win[5] / 2
end

local function IsFocusOnly()
	return ns.Focused() and (not ns.RefLayerMode or ns.RefLayerMode() == nil)
end

local function CanLoadPin(i, skipInstance)
	local D = ns.DATA
	local ci = D.cat[i]
	local cat = D.cats[ci]
	if skipInstance and cat.icon == "instance" and not ns.TrackedContains(i) and i ~= ns.FocusedPin() then return false end
	if view.searchSet then return view.searchSet[i] == true end
	if IsFocusOnly() then return ns.FocusContains(i) or i == ns.FocusedPin() end
	if ns.TrackedContains(i) or i == ns.FocusedPin() then return true end
	if view.tierAlpha[ns.CatBaseTier(ci)] <= 0 then return false end
	if ns.RefLayerContains(i) then return true end
	return ns.IsCategoryToggleableInLayers(cat) and ns.IsLayerCatOn(cat.id)
end

local function Passes(i)
	local D, db = ns.DATA, ns.db
	if view.searchSet then
		if not view.searchSet[i] or not ns.PassesPlayerFilter(i) then return false end
		return not (db.hideCompleted and ns.PinDone(i))
	elseif IsFocusOnly() then
		return ns.FocusContains(i) or i == ns.FocusedPin()
	end
	if ns.TrackedContains(i) or i == ns.FocusedPin() then
		return true
	end
	if not ns.PassesPlayerFilter(i) then return false end
	local cat = D.cats[D.cat[i]]
	local inRef = ns.RefLayerContains(i)
	local inLayer = ns.IsCategoryToggleableInLayers(cat) and ns.IsLayerCatOn(cat.id)
	if not (inRef or inLayer) then return false end
	local done = ns.PinDone(i)
	if db.hideCompleted and done then return false end
	return PinLodAlpha(i, done) > 0
end
ns.Passes = Passes

---------------------------------------------------------------------------
-- Category Icon Styles & Pooled Region Accessors
---------------------------------------------------------------------------
local function Hex(c)
	if not c or #c ~= 6 then return 1, 1, 1 end
	return tonumber(c:sub(1, 2), 16) / 255, tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255
end

local function CatIndexForIcon(iconName)
	if not view.catByIcon then
		view.catByIcon = {}
		for ci, c in ipairs(ns.DATA and ns.DATA.cats or {}) do
			if c.icon and not view.catByIcon[c.icon] then view.catByIcon[c.icon] = ci end
		end
	end
	return view.catByIcon[iconName]
end

local function Style(ci)
	local s = view.styles[ci]
	if s then return s end
	local c = ns.DATA.cats[ci]
	local r, g, b = Hex(c.color)
	s = { r = r, g = g, b = b, size = SIZE[c.icon] or 1 }
	for _, a in ipairs(ATLAS[c.icon] or {}) do
		if C_Texture.GetAtlasInfo(a) then s.atlas = a; break end
	end
	if c.icon == "repeatable" then s.tint = { .35, .7, 1 } end
	if not s.atlas and C_Minimap and C_Minimap.GetNumTrackingTypes then
		local want, title = TRACKING[c.icon], c.title:lower()
		for t = 1, C_Minimap.GetNumTrackingTypes() do
			local info = C_Minimap.GetTrackingInfo(t)
			local name = info and info.name and info.name:lower()
			if name and info.texture and (name:find(title, 1, true) or (want and name:find(want, 1, true))) then
				s.file = info.texture
				break
			end
		end
	end
	if not s.atlas and not s.file then s.file = TRACKING._files[c.icon] end
	view.styles[ci] = s
	return s
end
ns.CategoryStyle = Style

function ns.PaintDoneIcon(t, alpha)
	t:SetDesaturated(false)
	if doneAtlas then
		t:SetAtlas(doneAtlas)
		if doneAtlas == "UI-LFG-ReadyMark" then
			t:SetVertexColor(1, 1, 1)
		else
			t:SetVertexColor(.45, 1, .5)
		end
	else
		t:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		t:SetTexCoord(0, 1, 0, 1)
		t:SetVertexColor(.45, 1, .5)
	end
	t:SetAlpha(alpha or 1)
end

local function PaintCategory(t, ci, alpha)
	local s = Style(ci)
	t:SetDesaturated(false)
	if s.atlas then
		t:SetAtlas(s.atlas)
		if s.tint then t:SetVertexColor(s.tint[1], s.tint[2], s.tint[3]) else t:SetVertexColor(1, 1, 1) end
	elseif s.file then
		t:SetTexture(s.file)
		t:SetTexCoord(0, 1, 0, 1)
		t:SetVertexColor(1, 1, 1)
	else
		t:SetTexture(ns.MEDIA .. "dot")
		t:SetTexCoord(0, 1, 0, 1)
		t:SetVertexColor(s.r, s.g, s.b)
	end
	t:SetAlpha(alpha)
end

local function PaintIcon(t, i, alpha)
	local D = ns.DATA
	local ic = D.cats[D.cat[i]].icon
	if ic == "quest" or ic == "repeatable" or ic == "turnin" then
		local tq = ns.TrackedQuestForPin and ns.TrackedQuestForPin(i)
		if tq then
			local wantIcon = (ns.QuestReady(tq) or ns.QuestComplete(tq) == true) and "turnin" or "quest_objective"
			local overCi = CatIndexForIcon(wantIcon)
			if overCi then
				PaintCategory(t, overCi, alpha)
				return
			end
		end
	end
	if (ic == "quest" or ic == "repeatable") and ns.PinDone(i) then
		ns.PaintDoneIcon(t, alpha)
		return
	end
	PaintCategory(t, D.cat[i], alpha)
end
function ns.PaintCategoryIcon(t, ci) PaintCategory(t, ci, 1) end

local function Icon(n)
	local t = view.icons[n]
	if not t then
		t = view.overlay:CreateTexture(nil, "ARTWORK", nil, 1)
		view.icons[n] = t
	end
	return t
end

local function Ring(n)
	local t = view.rings[n]
	if not t then
		t = view.overlay:CreateTexture(nil, "ARTWORK", nil, 3)
		t:SetTexture(ns.MEDIA .. "ring")
		t:SetBlendMode("ADD")
		view.rings[n] = t
	end
	return t
end

local function LinkedIcon(n)
	local t = view.linked[n]
	if not t then
		t = view.overlay:CreateTexture(nil, "ARTWORK", nil, 4)
		view.linked[n] = t
	end
	return t
end

---------------------------------------------------------------------------
-- Canvas Geometry & Selection / Hover Highlight Rings
---------------------------------------------------------------------------
local function PinSize(i)
	local zoomK = 0.75 + 0.5 * (view.curZoom or 0)
	local isTracked = ns.TrackedContains(i) or i == ns.FocusedPin()
	if isTracked and zoomK < 0.95 then zoomK = 0.95 end
	local done = (not isTracked) and ns.PinDone(i)
	local mult = done and 0.9 or 1
	return BASE * ns.db.pinScale * zoomK * Style(ns.DATA.cat[i]).size * mult / (view.curScale or 1)
end

local function Place(t, x, y, size)
	t:ClearAllPoints()
	t:SetPoint("CENTER", view.overlay, "TOPLEFT", x * view.curW, -y * view.curH)
	t:SetSize(size, size)
end

local function Pos(i)
	if Seamless() then
		local stitch = ns.StitchWorld()
		local u, v = ns.WorldUV(i)
		if not (u and stitch) then return nil end
		local x, y = stitch.FromWorld(view.curMap, u, v)
		return x, y, true
	end
	local x, y, mine = ns.ProjectPin(view.curMap, i)
	if not x then return nil end
	if mine then return x, y, true end
	local cx = math.min(1 - EDGE, math.max(EDGE, x))
	local cy = math.min(1 - EDGE, math.max(EDGE, y))
	return cx, cy, cx == x and cy == y
end

local function Mark(i, focus)
	local x, y, on = Pos(i)
	if not (x and on) then return end
	local size = PinSize(i)
	view.nRings = view.nRings + 1
	local r = Ring(view.nRings)
	Place(r, x, y, size * (focus and 2.15 or 1.85))
	if focus then
		r:SetVertexColor(1, .88, .28)
		r:SetAlpha(.95)
	else
		r:SetVertexColor(.95, .85, .45)
		r:SetAlpha(.78)
	end
	r:Show()
	view.nLinked = view.nLinked + 1
	local t = LinkedIcon(view.nLinked)
	PaintIcon(t, i, 1)
	Place(t, x, y, size * (focus and 1.24 or 1.12))
	t:Show()
end

local OnUpdate

local function DrawLinks()
	local D = ns.DATA
	view.nRings, view.nLinked = 0, 0
	local lockedPin = ns.FocusedPin()
	if view.curMap and ns.db and ns.db.enabled and D then
		if lockedPin then
			local target = ns.ActivePinTarget and ns.ActivePinTarget(lockedPin) or lockedPin
			if target and target ~= lockedPin then
				Mark(lockedPin, false)
				Mark(target, true)
			else
				Mark(lockedPin, true)
			end
		elseif view.hoverPin then
			local i = view.hoverPin
			if D.endp[i] ~= 0 then Mark(D.endp[i], false) end
			if D.dest[i] ~= 0 then Mark(D.dest[i], false) end
			Mark(i, true)
		end
	end
	for n = view.nRings + 1, #view.rings do view.rings[n]:Hide() end
	for n = view.nLinked + 1, #view.linked do view.linked[n]:Hide() end
end

function ns.RefreshHoverTooltip()
	if ns.InvalidatePinTooltip then ns.InvalidatePinTooltip() end
	if view.hoverPin and view.hot and GameTooltip:IsShown() and GameTooltip:GetOwner() == view.hot then
		ns.ShowTooltip(view.hot, view.hoverPin)
	end
end

function ns.RedrawLinks()
	if not view.overlay then return end
	DrawLinks()
	ns.RefreshHoverTooltip()
end

---------------------------------------------------------------------------
-- Pin Rebuild, Zoom Resizing & Hover Hit-Test
---------------------------------------------------------------------------
local SetHover

local function Rebuild(duringFlight)
	local D = ns.DATA
	local stitch, S = ns.StitchWorld()
	view.dirty = false
	view.lastCX, view.lastCY = nil, nil
	local keepHover = false
	wipe(view.shown)
	view.nIcons = 0
	local keepWin = view.win
	view.win = nil
	view.builtSeamless = Seamless()
	UpdateLodFades(view.builtSeamless, view.curStitchZoom, view.curZoom)
	view.builtTierMask = view.tierMask
	local level = ns.OverlayLevel()
	if view.overlay and view.overlay:GetFrameLevel() ~= level then
		view.overlay:SetFrameLevel(level)
		view.hot:SetFrameLevel(level + 1)
	end

	local zMap = (ns.ViewZoneMap and ns.ViewZoneMap()) or view.curMap
	view.curViewZone = zMap

	local function Add(i, x, y, isDone)
		local lodA = PinLodAlpha(i, isDone)
		if lodA <= 0 then return end
		view.shown[#view.shown + 1] = i
		if i == view.hoverPin and lodA >= HOVER_MIN_ALPHA then keepHover = true end
		view.nIcons = view.nIcons + 1
		local n = view.nIcons
		local t = Icon(n)
		local baseA = isDone and .85 or 1
		local finalA = baseA * lodA
		t:SetDrawLayer("ARTWORK", isDone and 1 or 2)
		PaintIcon(t, i, baseA)
		if finalA ~= baseA then t:SetAlpha(finalA) end
		view.iconBaseAlpha[n], view.iconAlpha[n], view.iconDone[n] = baseA, finalA, isDone
		Place(t, x, y, PinSize(i))
		t:Show()
	end

	view.nDone = 0
	local actPin, actX, actY = view.actPin, view.actX, view.actY
	local trkPin, trkX, trkY = view.trkPin, view.trkX, view.trkY
	local nAct, nTrk = 0, 0
	local function QueuePin(i, x, y)
		if ns.TrackedContains(i) or i == ns.FocusedPin() then
			nTrk = nTrk + 1
			trkPin[nTrk], trkX[nTrk], trkY[nTrk] = i, x, y
		elseif ns.PinDone(i) then
			Add(i, x, y, true)
		else
			nAct = nAct + 1
			actPin[nAct], actX[nAct], actY[nAct] = i, x, y
		end
	end

	local canBuild = ns.db.enabled and D ~= nil and view.curMap ~= nil and ns.Calibrate()
	if canBuild then
		ns.SyncDoneQuests()
		if ns.UpdateFocus and ((ns.IsTrackerTab and ns.IsTrackerTab()) or not (ns.RefLayerMode and ns.RefLayerMode())) then
			ns.UpdateFocus(false)
		end
		if ns.RefreshRefLayerSet then ns.RefreshRefLayerSet(zMap) end
	elseif ns.RefreshRefLayerSet then
		ns.RefreshRefLayerSet(nil)
	end

	local openMapDungeons = false
	if stitch and S and S.GetPinSet then
		local dset = S.GetPinSet("dungeons")
		if dset then
			local instLayerOn = false
			if D then
				for _, cat in ipairs(D.cats) do
					if cat.icon == "instance" and ns.IsLayerCatOn(cat.id) then instLayerOn = true; break end
				end
			end
			openMapDungeons = (ns.db.enabled and D ~= nil and stitch.enabled
				and not IsFocusOnly()
				and stitch.DungeonMapsOn and stitch.DungeonMapsOn()
				and stitch.db.icons ~= false
				and (instLayerOn or ns.RefLayerMode() == "dungeon")) == true
			S.SetPinSetOn(dset, openMapDungeons)
		end
	end

	if canBuild then
		local u, v, zoom
		if Seamless() and stitch then u, v, zoom = stitch.ViewNow() end
		if u and stitch then
			local hu, hv = stitch.ViewHalfExtents(zoom)
			local w = keepWin or {}
			w[1], w[2], w[3], w[4], w[5] = u - hu * WIN, u + hu * WIN, v - hv * WIN, v + hv * WIN, zoom
			view.win = w
			wipe(view.seamX)
			wipe(view.seamY)
			view.posX, view.posY = view.seamX, view.seamY
			local skipInstance = openMapDungeons and view.searchSet == nil
			for i = 1, #D.x do
				if CanLoadPin(i, skipInstance) then
					local pu, pv = ns.WorldUV(i)
					local alwaysOn = view.searchSet == nil and (ns.TrackedContains(i) or i == ns.FocusedPin())
					if pu and (alwaysOn or (pu >= w[1] and pu <= w[2] and pv >= w[3] and pv <= w[4])) and Passes(i) then
						local x, y = stitch.FromWorld(view.curMap, pu, pv)
						view.posX[i], view.posY[i] = x, y
						QueuePin(i, x, y)
					end
				end
			end
		else
			local c = ns.PinsOnMap(view.curMap)
			view.posX, view.posY = c.x, c.y
			for _, i in ipairs(c.idx) do
				if Passes(i) then QueuePin(i, c.x[i], c.y[i]) end
			end
		end
		view.nDone = view.nIcons
		for k = 1, nAct do Add(actPin[k], actX[k], actY[k], false) end
		for k = 1, nTrk do Add(trkPin[k], trkX[k], trkY[k], false) end
	end
	for n = view.nIcons + 1, #view.icons do view.icons[n]:Hide() end
	if ns.FocusedPin() and not ns.db.enabled then ns.ClearDisabledSelection() end
	if view.hoverPin and not keepHover then
		view.hoverPin = nil
		if view.hot then
			view.hot:Hide()
			if ns.HidePinTooltipIfOwned then ns.HidePinTooltipIfOwned(view.hot) end
		end
	end
	DrawLinks()
	if view.hoverPin and view.hot then
		Place(view.hot, view.posX[view.hoverPin], view.posY[view.hoverPin], PinSize(view.hoverPin) * (HIT_R * 2))
		if GameTooltip:IsShown() and GameTooltip:GetOwner() == view.hot then
			ns.ShowTooltip(view.hot, view.hoverPin)
		end
	end
	if not duringFlight and ns.OnLayerChanged then
		view.panelNotified = true
		ns.OnLayerChanged()
	end
end

local function Resize()
	view.lastCX, view.lastCY = nil, nil
	local dropHover = false
	for n, i in ipairs(view.shown) do
		local t = view.icons[n]
		local size = PinSize(i)
		t:SetSize(size, size)
		local a = (view.iconBaseAlpha[n] or 1) * PinLodAlpha(i, view.iconDone[n])
		if view.iconAlpha[n] ~= a then
			view.iconAlpha[n] = a
			t:SetAlpha(a)
		end
		if i == view.hoverPin and a < HOVER_MIN_ALPHA then dropHover = true end
	end
	if dropHover then SetHover(nil) else DrawLinks() end
end

local function PinAt(cx, cy)
	local px, py = cx * view.curW, cy * view.curH
	local best, bd
	local nDone = view.nDone or 0
	for n = #view.shown, 1, -1 do
		if n <= nDone and best then break end
		if (view.iconAlpha[n] or 1) >= HOVER_MIN_ALPHA then
			local i = view.shown[n]
			local r = PinSize(i) * HIT_R
			local dx, dy = view.posX[i] * view.curW - px, view.posY[i] * view.curH - py
			local d = dx * dx + dy * dy
			if d <= r * r and (not bd or d < bd) then best, bd = i, d end
		end
	end
	return best
end

SetHover = function(i)
	if i == view.hoverPin then return end
	view.hoverPin = i
	local x, y
	if i then x, y = view.posX[i], view.posY[i] end
	if i and not x then view.hoverPin, i = nil, nil end
	DrawLinks()
	if i then
		Place(view.hot, x, y, PinSize(i) * (HIT_R * 2))
		view.hot:Show()
		ns.ShowTooltip(view.hot, i)
	else
		view.hot:Hide()
		if ns.HidePinTooltipIfOwned then ns.HidePinTooltipIfOwned(view.hot) end
	end
end

function ns.IsHoveringCanvas()
	return (WorldMapFrame.ScrollContainer:IsMouseMotionFocus() or (view.hot ~= nil and view.hot:IsMouseMotionFocus())) == true
end

---------------------------------------------------------------------------
-- Per-Frame Canvas Watch & Startup
---------------------------------------------------------------------------
OnUpdate = function()
	local stitch = ns.StitchWorld()
	if stitch and stitch.DungeonViewShown and stitch.DungeonViewShown() then
		if ns.UpdateMapBanner then ns.UpdateMapBanner(true) end
		if view.hoverPin then SetHover(nil) end
		view.lastCX = nil
		return
	end
	local map = WorldMapFrame:GetMapID()
	local canvas = WorldMapFrame:GetCanvas()
	local w, h = canvas:GetWidth(), canvas:GetHeight()
	if map ~= view.curMap or w ~= view.curW or h ~= view.curH then
		local prevMap = view.curMap
		view.curMap, view.curW, view.curH = map, w, h
		view.dirty = true
		ns.HideVeilIfMoved(view.curMap)
		if prevMap and map ~= prevMap then
			local now = GetTime()
			local autoSwitched = stitch and stitch.lastSwitchAt and (now - stitch.lastSwitchAt) < 0.25
			local justOpened = ns.MapShownAt and (now - ns.MapShownAt()) < 0.25
			if not autoSwitched and not justOpened
				and not (ns.IsInSidebarNav and ns.IsInSidebarNav())
				and not (ns.IsRestoringNav and ns.IsRestoringNav()) then
				if ns.OnUserMapNavigate then ns.OnUserMapNavigate(true) end
			end
		end
	end
	local scale, zoom = WorldMapFrame:GetCanvasScale(), WorldMapFrame:GetCanvasZoomPercent()
	local seamless = Seamless()
	local sz = nil
	if seamless and stitch and stitch.ViewNow then
		local _, _, z = stitch.ViewNow()
		sz = z
	end
	local animating = seamless and stitch ~= nil and stitch.Flying()
	local settledFlight = view.wasAnimating and not animating
	if settledFlight then
		view.checkedScale = nil
		view.dirty = true
	end
	view.wasAnimating = animating
	local sc = WorldMapFrame.ScrollContainer
	local sx, sy, sw, sh = sc:GetCurrentScrollX(), sc:GetCurrentScrollY(), sc:GetWidth(), sc:GetHeight()
	local camMoved = scale ~= view.checkedScale or sx ~= view.checkedX or sy ~= view.checkedY or sw ~= view.checkedW or sh ~= view.checkedH
	if camMoved then
		view.checkedScale, view.checkedX, view.checkedY, view.checkedW, view.checkedH = scale, sx, sy, sw, sh
		if view.win and WindowStale(animating) then view.dirty = true end
	end
	if not animating and (camMoved or settledFlight or view.dirty) and ns.ViewZoneMap then
		local vz = ns.ViewZoneMap()
		if vz and vz ~= view.curViewZone then
			if stitch and stitch.userDraggedAt and (GetTime() - stitch.userDraggedAt) < 1.5
				and not (ns.IsInSidebarNav and ns.IsInSidebarNav())
				and not (ns.IsRestoringNav and ns.IsRestoringNav()) then
				local pinned = ns.PinnedRefZone and ns.PinnedRefZone() or nil
				local dest = ns.SidebarDestZone and ns.SidebarDestZone() or nil
				if vz ~= pinned and vz ~= dest and ns.OnUserMapNavigate then
					ns.OnUserMapNavigate(true)
				end
			end
			if ns.IsTrackerTab and ns.IsTrackerTab() then
				view.curViewZone = vz
			else
				view.dirty = true
			end
		end
	end
	UpdateLodFades(seamless, sz, zoom)
	if seamless ~= view.builtSeamless or (not animating and view.tierMask ~= view.builtTierMask) then
		view.dirty = true
	end
	if view.dirty then
		view.curScale, view.curZoom, view.curStitchZoom = scale, zoom, sz
		Rebuild(animating)
	elseif scale ~= view.curScale or zoom ~= view.curZoom
		or (sz and (not view.curStitchZoom or math.abs(sz - view.curStitchZoom) > sz * 0.005)) then
		view.curScale, view.curZoom, view.curStitchZoom = scale, zoom, sz
		Resize()
		if view.hoverPin then
			local s = PinSize(view.hoverPin) * (HIT_R * 2)
			view.hot:SetSize(s, s)
		end
	end
	if ns.UpdateMapBanner then ns.UpdateMapBanner(false) end
	if #view.shown == 0 then
		if view.hoverPin then SetHover(nil) end
		return
	end
	if animating or not ns.IsHoveringCanvas() then
		if view.hoverPin then SetHover(nil) end
		view.lastCX = nil
		return
	end
	local cx, cy
	if seamless and stitch then
		local u, v = stitch.CursorWorld()
		if u then cx, cy = stitch.FromWorld(view.curMap, u, v) end
	end
	if not cx then cx, cy = WorldMapFrame:GetNormalizedCursorPosition() end
	if cx == view.lastCX and cy == view.lastCY then return end
	view.lastCX, view.lastCY = cx, cy
	SetHover(PinAt(cx, cy))
end

function ns.Refresh()
	view.dirty = true
	view.panelNotified = false
	if view.overlay and view.overlay:IsVisible() then OnUpdate() end
	if not view.panelNotified and ns.OnLayerChanged then
		view.panelNotified = true
		ns.OnLayerChanged()
	end
end

function ns.SetSearch(set)
	view.searchSet = set
	ns.Refresh()
end

function ns.ShownCount() return #view.shown end
function ns.CurrentMap() return view.curMap end
function ns.HotButton() return view.hot end

function ns.OverlayLevel()
	local levels = WorldMapFrame:GetPinFrameLevelsManager()
	local level = levels:GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT") + 1
	for _, name in ipairs(STITCH_ICON_LEVELS) do
		local d = levels.definitions and levels.definitions[name]
		if d then level = math.max(level, d.startLevel + d.range) end
	end
	return level
end

local function OnHotClick()
	local pin = view.hoverPin
	if not pin then return end
	local D = ns.DATA
	local stitch = ns.StitchWorld()
	local pinBtn = WorldMapFrame and WorldMapFrame.WorldMapTrackingPinButton
	local pinArmed = (stitch and stitch.PinMode and stitch.PinMode()) or (pinBtn and pinBtn.isActive)
	local sel = ns.FocusedPin()
	if IsShiftKeyDown() or IsControlKeyDown() or pinArmed then
		if stitch and stitch.SetPinMode then
			stitch.SetPinMode(false)
		elseif pinBtn and pinBtn.SetActive then
			pinBtn:SetActive(false)
		end
		ns.SetWaypoint(pin)
	elseif D and D.cats[D.cat[pin]].icon == "instance" and stitch and stitch.OpenInstanceNear then
		local pu, pv = ns.WorldUV(pin)
		if not stitch.OpenInstanceNear(D.title[pin], pu, pv, view.hot) then
			ns.Focus(pin)
		end
	else
		local tq = ns.TrackedQuestForPin and ns.TrackedQuestForPin(pin) or nil
		if not tq and ns.IsTrackerTab and ns.IsTrackerTab() and ns.LogQuestIDForPin then
			tq = ns.LogQuestIDForPin(pin)
		end
		if tq and ns.QuestClicked then
			ns.QuestClicked(tq, "toggle", true, true)
			return
		end
		local ic = D and D.cats[D.cat[pin]].icon
		local questPin = nil
		if ic == "quest" or ic == "repeatable" then
			questPin = pin
		elseif ic == "turnin" or ic == "quest_objective" then
			questPin = (D.qid[pin] ~= 0 and ns.QuestPin and ns.QuestPin(D.qid[pin])) or nil
		end
		local focusTarget = questPin or pin
		if sel and focusTarget == sel and (not questPin or (ns.db and (ns.db.panelTab == "zone" or ns.db.panelTab == "dungeon" or ns.db.panelTab == "tracker"))) then
			ns.SetFocusedPin(nil)
			if ns.CloseQuestDetailsIfShown then ns.CloseQuestDetailsIfShown() end
		else
			ns.SetFocusedPin(focusTarget)
			if ns.SyncQuestDetailsPane then ns.SyncQuestDetailsPane(focusTarget) end
			if questPin and ns.RevealQuestInPanel then
				ns.RevealQuestInPanel(questPin, nil, false, true)
			end
		end
	end
end

local function OnCanvasRightClickWaypoint(_, button)
	if button ~= "RightButton" then return false end
	if not (WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate) then return false end
	for pin in WorldMapFrame:EnumeratePinsByTemplate("WaypointLocationPinTemplate") do
		if pin:IsVisible() and pin:IsMouseOver() then
			if GameTooltip:GetOwner() == pin then GameTooltip:Hide() end
			if ns.ClearUserWaypoint then
				ns.ClearUserWaypoint()
			elseif C_Map.ClearUserWaypoint then
				C_Map.ClearUserWaypoint()
				ns.Sound("UI_MAP_WAYPOINT_REMOVE", true)
			end
			return true
		end
	end
	return false
end

local function Init()
	local stitch = ns.StitchWorld()
	if stitch and stitch.RefreshDungeonCard then
		hooksecurefunc(stitch, "RefreshDungeonCard", function() view.dirty = true end)
	end
	if WorldMapFrame and WorldMapFrame.AddCanvasClickHandler then
		WorldMapFrame:AddCanvasClickHandler(OnCanvasRightClickWaypoint, 1100)
	end

	local canvas = WorldMapFrame:GetCanvas()
	local overlay = CreateFrame("Frame", nil, canvas)
	view.overlay = overlay
	overlay:SetAllPoints(canvas)
	overlay:SetFrameLevel(ns.OverlayLevel())
	overlay:SetScript("OnUpdate", OnUpdate)
	overlay:SetScript("OnHide", function()
		if view.hoverPin then SetHover(nil) end
		view.lastCX, view.lastCY = nil, nil
	end)

	local hot = CreateFrame("Button", nil, overlay)
	view.hot = hot
	hot:SetFrameLevel(overlay:GetFrameLevel() + 1)
	hot:RegisterForClicks("LeftButtonUp")
	hot:Hide()
	if hot.SetPassThroughButtons then
		if InCombatLockdown() then
			ns.events:RegisterEvent("PLAYER_REGEN_ENABLED")
		else
			hot:SetPassThroughButtons("RightButton")
		end
	end
	hot.owningMap = WorldMapFrame
	hot:SetScript("OnClick", OnHotClick)

	ns.InitQuests()
	ns.InitFocus()
	if ns.EnforceWindowedOpaqueMap then ns.EnforceWindowedOpaqueMap() end

	WorldMapFrame:HookScript("OnShow", function()
		if ns.EnforceWindowedOpaqueMap then ns.EnforceWindowedOpaqueMap() end
		ns.MarkMapShownNow()
		if ns.FlushQuestLogOnMapShow() then
			view.dirty = true
			if ns.OnLayerChanged then ns.OnLayerChanged() end
		end
	end)
end

function ns:PLAYER_REGEN_ENABLED()
	ns.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if view.hot and view.hot.SetPassThroughButtons then
		view.hot:SetPassThroughButtons("RightButton")
	end
end

local function ShowNoDataNotice()
	if view.notice then return end
	local notice = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
	view.notice = notice
	notice:SetAllPoints()
	notice:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST") + 10)
	local text = notice:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetPoint("TOP", 0, -40)
	text:SetText(ns.NO_DATA)
end

function ns.InitLayer()
	if not WorldMapFrame then return end
	if not ns.DATA then ShowNoDataNotice(); return end
	if view.overlay then return end
	Init()
	if ns.InitPanel then ns.InitPanel() end
end
