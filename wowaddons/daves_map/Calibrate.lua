-- daves_map / Calibrate.lua
-- Direct coordinate placement from QuestieDB Forever's exact (uiMapID, x, y) pin data (daves_map_data).
-- Every pin already carries its exact Forever zone/city uiMapID (D.map[i]) and normalized 0-1 map
-- coordinates (D.x[i], D.y[i]) — no affine approximation is needed.
--
-- On first map open, each unique zone/city uiMapID's continent rectangle is resolved once via
-- C_Map.GetMapRectOnMap (~50 calls total, zero per-pin vector churn), filling P.zone, P.cont, P.cx,
-- and P.cy. Nothing of Blizzard's UI is written: only C_Map reads.

local _, ns = ...

local P = { cont = {}, cx = {}, cy = {}, zone = {} }
ns.P = P
local calibrated = false
local numMaps = 0

local contOf = {}
local function ContinentOf(mapID)
	local v = contOf[mapID]
	if v ~= nil then return v or nil end
	local id, guard = mapID, 0
	v = false
	while id and id ~= 0 and guard < 12 do
		local info = C_Map.GetMapInfo(id)
		if not info then break end
		if info.mapType == Enum.UIMapType.Continent then v = id break end
		id = info.parentMapID
		guard = guard + 1
	end
	contOf[mapID] = v
	return v or nil
end

local rectCache = {}   -- [srcMapID] = { [dstMapID] = { l, w, t, h } | false }
local function RectOnMap(srcMap, dstMap)
	local bySrc = rectCache[srcMap]
	if not bySrc then bySrc = {}; rectCache[srcMap] = bySrc end
	local r = bySrc[dstMap]
	if r ~= nil then return r or nil end
	r = false
	local minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(srcMap, dstMap)
	if minX and maxX and minY and maxY and maxX > minX and maxY > minY then
		r = { minX, maxX - minX, minY, maxY - minY }
	else
		local inst0, w0 = C_Map.GetWorldPosFromMapPos(srcMap, CreateVector2D(0, 0))
		local inst1, w1 = C_Map.GetWorldPosFromMapPos(srcMap, CreateVector2D(1, 1))
		if inst0 and inst0 == inst1 and w0 and w1 then
			local _, p0 = C_Map.GetMapPosFromWorldPos(inst0, w0, dstMap)
			local _, p1 = C_Map.GetMapPosFromWorldPos(inst1, w1, dstMap)
			if p0 and p1 and p1.x > p0.x and p1.y > p0.y then
				r = { p0.x, p1.x - p0.x, p0.y, p1.y - p0.y }
			end
		end
	end
	bySrc[dstMap] = r
	return r or nil
end

local function MapToMap(srcMap, sx, sy, dstMap)
	if srcMap == dstMap then return sx, sy end
	local r = RectOnMap(srcMap, dstMap)
	if r then return r[1] + sx * r[2], r[3] + sy * r[4] end
	return nil, nil
end

function ns.Calibrate()
	if calibrated then return true end
	local D = ns.DATA
	if not (D and D.map and D.x and D.y) then return false end
	local seenMaps = {}
	for i = 1, #D.x do
		local z = D.map[i]
		P.zone[i] = z
		if z and z ~= 0 then
			if not seenMaps[z] then seenMaps[z] = true; numMaps = numMaps + 1 end
			local cont = ContinentOf(z)
			if cont then
				local cx, cy = MapToMap(z, D.x[i], D.y[i], cont)
				if cx then P.cont[i], P.cx[i], P.cy[i] = cont, cx, cy end
			end
		end
	end
	calibrated = true
	return true
end

function ns.IsCalibrated() return calibrated end

function ns.ReportCalibration()
	if not calibrated then ns.Calibrate() end
	local D = ns.DATA
	if not D then ns.Print("no map data loaded.") return end
	ns.Print(("QuestieDB Forever coordinates: %d pins across %d Forever maps (exact in-game positions; zero projection drift)."):format(#D.x, numMaps))
end

---------------------------------------------------------------------------
-- Positions on any map, cached per map: { idx = {pin, ...}, x = {}, y = {} }
---------------------------------------------------------------------------
local cache = {}
local ancestorsOf = {}

local function Ancestors(zone)
	local set = ancestorsOf[zone]
	if set then return set end
	set = {}
	local id, guard = zone, 0
	while id and guard < 12 do
		set[id] = true
		local info = C_Map.GetMapInfo(id)
		id = info and info.parentMapID
		if id == 0 then id = nil end
		guard = guard + 1
	end
	ancestorsOf[zone] = set
	return set
end

function ns.PinsOnMap(mapID)
	local c = mapID and cache[mapID]
	if c then return c end
	c = { idx = {}, x = {}, y = {} }
	if not calibrated or not mapID then return c end
	cache[mapID] = c
	local D = ns.DATA
	local info = C_Map.GetMapInfo(mapID)
	if not (D and info) then return c end
	local wide = info.mapType < Enum.UIMapType.Continent
	for i = 1, #D.x do
		local z = P.zone[i]
		if z and (z == mapID or P.cont[i] == mapID or wide or Ancestors(z)[mapID]) then
			local x, y
			if z == mapID then
				x, y = D.x[i], D.y[i]
			elseif P.cont[i] == mapID then
				x, y = P.cx[i], P.cy[i]
			else
				x, y = MapToMap(z, D.x[i], D.y[i], mapID)
			end
			if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				c.idx[#c.idx + 1] = i
				c.x[i], c.y[i] = x, y
			end
		end
	end
	return c
end

local proj = {}
function ns.ProjectPin(mapID, i)
	if not (calibrated and mapID and i) then return nil end
	local c = ns.PinsOnMap(mapID)
	if c.x[i] then return c.x[i], c.y[i], true end
	local mapCont = ContinentOf(mapID)
	if mapCont and P.cont[i] ~= mapCont then return nil end
	local pc = proj[mapID]
	if not pc then pc = { x = {}, y = {} }; proj[mapID] = pc end
	local x = pc.x[i]
	if x == nil then
		x = false
		local y = false
		local D = ns.DATA
		local z = P.zone[i]
		if P.cont[i] == mapID then
			x, y = P.cx[i], P.cy[i]
		elseif z and D then
			local px, py = MapToMap(z, D.x[i], D.y[i], mapID)
			if px then x, y = px, py end
		end
		pc.x[i], pc.y[i] = x, y
	end
	if x then return x, pc.y[i], false end
	return nil
end

local zoneNames = {}
function ns.ZoneName(i)
	local z = P.zone[i]
	if not z then return nil end
	local n = zoneNames[z]
	if n == nil then
		local info = C_Map.GetMapInfo(z)
		n = info and info.name or false
		zoneNames[z] = n
	end
	return n or nil
end

local cityMaps = {}
function ns.IsCityMap(mapID)
	if not mapID or mapID == 0 then return false end
	local v = cityMaps[mapID]
	if v ~= nil then return v end
	v = false
	local cont = ContinentOf(mapID)
	if cont and cont ~= mapID then
		local r = RectOnMap(mapID, cont)
		if r and (r[2] * r[4] < 0.0035) then v = true end
	end
	cityMaps[mapID] = v
	return v
end

-- Progressive zoom-distance fade bands (1 = whole world, ~2 = continent, ~6-9 = zone, ~12+ = town/city).
-- Below `t[1]`, icons in that tier are not loaded or instantiated at all (`alpha == 0`).
local ZOOM_TIERS = {
	{ 1.6, 2.4 },   -- 1: Instances / Dungeons / Raids (continent landmarks)
	{ 2.4, 3.5 },   -- 2: Flight Masters (regional travel)
	{ 3.6, 5.0 },   -- 3: Active Quests, Rares & Graveyards (zone features)
	{ 5.0, 6.8 },   -- 4: Completed Quests, Treasures & global Objectives/Turn-Ins (close zone detail)
	{ 7.2, 10.0 },  -- 5: Townsfolk & City Services (hub/town/city detail)
}
local ICON_TIER = {
	instance = 1, flight_master = 2,
	quest = 3, repeatable = 3, rare = 3, graveyard = 3,
	treasure = 4, turnin = 4, quest_objective = 4,
}
local catTierCache = {}

function ns.CatBaseTier(ci)
	local t = catTierCache[ci]
	if not t then
		t = ICON_TIER[ns.DATA.cats[ci].icon] or 5
		catTierCache[ci] = t
	end
	return t
end

function ns.PinZoomTier(i, isDone)
	local ci = ns.DATA.cat[i]
	local t = ns.CatBaseTier(ci)
	if t == 3 and isDone then
		local ic = ns.DATA.cats[ci].icon
		if ic == "quest" or ic == "repeatable" then return 4 end
	end
	return t
end

function ns.ComputeLodFades(seamless, curMap, sz, zoom, outAlpha)
	local lz
	if seamless then
		lz = (sz and sz > 0) and sz or 1
	else
		local info = curMap and C_Map.GetMapInfo(curMap)
		local mtype = info and info.mapType or Enum.UIMapType.Zone
		local z = zoom or 0
		if mtype <= Enum.UIMapType.World then
			lz = 1.0
		elseif mtype == Enum.UIMapType.Continent then
			lz = 2.4 + z * 1.2
		elseif mtype == Enum.UIMapType.Zone then
			local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
			local canZoom = sc and sc.GetScaleForMaxZoom and sc.GetScaleForMinZoom
				and (sc:GetScaleForMaxZoom() > sc:GetScaleForMinZoom() + 1e-4)
			lz = (ns.IsCityMap(curMap) or not canZoom) and 12.0 or (6.8 + z * 5.2)
		else
			lz = 12.0
		end
	end
	local mask, bitVal = 0, 1
	for t = 1, #ZOOM_TIERS do
		local z0, z1 = ZOOM_TIERS[t][1], ZOOM_TIERS[t][2]
		local a = 0
		if lz > z0 then
			local u = math.min(1, (lz - z0) / (z1 - z0))
			a = math.floor(u * u * (3 - 2 * u) * 200 + 0.5) / 200
			if a > 0 then mask = mask + bitVal end
		end
		outAlpha[t] = a
		bitVal = bitVal * 2
	end
	return lz, mask
end

---------------------------------------------------------------------------
-- Stitched World Coordinates, Active Zone Lookup & Waypoints
---------------------------------------------------------------------------
local stitchState = { stitch = nil, S = nil, U = {}, V = {} }

function ns.StitchWorld()
	if not stitchState.stitch and ns.OM then
		local st = ns.OM:GetModule("worldmap")
		local mapStitch = ns.OM.MapStitch
		if st and mapStitch then
			stitchState.stitch = st
			stitchState.S = mapStitch
		end
	end
	return stitchState.stitch, stitchState.S
end

function ns.StitchModule()
	local stitch = ns.StitchWorld()
	return stitch
end

function ns.IsStitched()
	local stitch = ns.StitchWorld()
	return stitch ~= nil and stitch.IsStitched()
end

function ns.IsStitchableMap(mapID)
	local _, S = ns.StitchWorld()
	if not (S and mapID and mapID ~= 0 and not issecretvalue(mapID)) then return false end
	if mapID == S.WORLD then return true end
	local info = C_Map.GetMapInfo(mapID)
	if not info or (info.mapType ~= Enum.UIMapType.Continent and info.mapType ~= Enum.UIMapType.Zone) then return false end
	return S.Rect(mapID) ~= nil and S.ArtSize(mapID) ~= nil and S.Stitched(mapID, true)
end

function ns.WorldUV(i)
	local stitch, S = ns.StitchWorld()
	local D = ns.DATA
	if not (stitch and S and D and i) then return nil end
	local u = stitchState.U[i]
	if u == nil then
		u = false
		local zone = P.zone[i]
		if zone and S.Rect(zone) then
			local v
			u, v = stitch.ToWorld(zone, D.x[i], D.y[i])
			stitchState.V[i] = v
		else
			local cont = P.cont[i]
			if cont and S.Rect(cont) then
				local v
				u, v = stitch.ToWorld(cont, P.cx[i], P.cy[i])
				stitchState.V[i] = v
			end
		end
		stitchState.U[i] = u
	end
	if u then return u, stitchState.V[i] end
	return nil
end

function ns.ViewZoneMap()
	local mapID = (ns.CurrentMap and ns.CurrentMap()) or (WorldMapFrame and WorldMapFrame:GetMapID())
	local stitch, S = ns.StitchWorld()
	if ns.IsSeamless and ns.IsSeamless() and stitch and S and S.ChainAt then
		local u, v = stitch.ViewNow()
		if u then
			local list = S.ChainAt(u, v)
			for k = #list, 1, -1 do
				local id = list[k]
				local info = C_Map.GetMapInfo(id)
				if info and info.mapType >= Enum.UIMapType.Zone then return id end
			end
		end
	end
	if mapID then
		local info = C_Map.GetMapInfo(mapID)
		if info and info.mapType >= Enum.UIMapType.Zone then return mapID end
	end
	local best = C_Map.GetBestMapForUnit("player")
	if best and best ~= 0 then
		local info = C_Map.GetMapInfo(best)
		if info and info.mapType >= Enum.UIMapType.Zone then return best end
	end
	return mapID
end

function ns.SetWaypoint(i)
	local D = ns.DATA
	if not (D and i) then return end
	local zone = P.zone[i]
	if not zone then
		ns.Print("can't set a waypoint there.")
		return
	end
	local c = ns.PinsOnMap(zone)
	local x, y = c.x[i], c.y[i]
	if not x then return end
	if not ns.PlaceUserWaypoint(zone, x, y) then
		ns.Print("can't set a waypoint there.")
		return
	end
	ns.Sound("UI_MAP_WAYPOINT_CLICK_TO_PLACE", true)
	ns.Print(("waypoint: %s (%s %.1f, %.1f)."):format(D.title[i], ns.ZoneName(i) or "?", x * 100, y * 100))
end

function ns.PinModeActive()
	local stitch = ns.StitchWorld()
	local pinBtn = WorldMapFrame and WorldMapFrame.WorldMapTrackingPinButton
	if stitch and stitch.PinMode and stitch.PinMode() then return true end
	return (pinBtn and pinBtn.isActive) == true
end

function ns.ClearUserWaypoint()
	local stitch = ns.StitchWorld()
	if stitch and stitch.ClearPin then
		stitch.ClearPin()
	else
		if C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(false)
		end
		ns.Sound("UI_MAP_WAYPOINT_REMOVE", true)
	end
end

function ns.TogglePinMode(rightClick)
	local stitch = ns.StitchWorld()
	local pinBtn = WorldMapFrame and WorldMapFrame.WorldMapTrackingPinButton
	if rightClick then
		if stitch and stitch.SetPinMode then stitch.SetPinMode(false) end
		ns.ClearUserWaypoint()
		return
	end
	local on = not ns.PinModeActive()
	if stitch and stitch.SetPinMode then
		stitch.SetPinMode(on)
	elseif pinBtn and pinBtn.SetActive then
		pinBtn:SetActive(on)
	end
	ns.Sound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
end

function ns.IsDungeonViewShown()
	local stitch = ns.StitchWorld()
	return (stitch and stitch.DungeonViewShown and stitch.DungeonViewShown()) == true
end

function ns.CloseDungeonView()
	local stitch = ns.StitchWorld()
	if ns.IsDungeonViewShown() and stitch and stitch.CloseDungeonView then
		stitch.CloseDungeonView()
		return true
	end
	return false
end

function ns.OpenInstancePin(i, anchor, title, onlyDungeonView)
	local stitch = ns.StitchWorld()
	local D = ns.DATA
	local fallbackAnchor = anchor or (ns.HotButton and ns.HotButton())
	if stitch and stitch.OpenInstanceNear then
		if D and i and D.cats[D.cat[i]].icon == "instance" then
			local pu, pv = ns.WorldUV(i)
			if stitch.OpenInstanceNear(title or D.title[i], pu, pv, fallbackAnchor) then return true end
		elseif not i and title then
			if stitch.OpenInstanceNear(title, nil, nil, fallbackAnchor) then return true end
		end
	end
	if onlyDungeonView or not i then return false end
	return ns.ShowPinMap and ns.ShowPinMap(i, true) or false
end
