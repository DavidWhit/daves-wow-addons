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
