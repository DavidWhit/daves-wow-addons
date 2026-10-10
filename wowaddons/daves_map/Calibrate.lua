-- daves_map / Calibrate.lua
-- Map Genie's positions are pixels on their own picture of Azeroth (Data.lua x, y). The game places things by uiMapID
-- and a 0-1 position on that map. The two are tied together here, in game, from the flight points: both sides list
-- them by the same name ("Stormwind, Elwynn"), the game's own positions come from C_TaxiMap.GetTaxiNodesForMap (it
-- returns undiscovered nodes too, so any character can do this), and a least-squares affine fit per continent turns
-- every Map Genie pixel into a position on that continent. Then each pin gets its zone (C_Map.GetMapInfoAtPosition)
-- and its world position, from which any other map's position follows (C_Map.GetMapPosFromWorldPos).
-- Nothing of Blizzard's is written: only C_Map / C_TaxiMap reads.

local _, ns = ...

-- per pin, filled by Calibrate: the continent's uiMapID, the position on it, the zone, the world position
local P = { cont = {}, cx = {}, cy = {}, zone = {}, inst = {}, wx = {}, wy = {} }
ns.P = P
local report = {}            -- per continent: anchors used, dropped, rms error (in map units)
local calibrated = false

local function Norm(s)
	s = (s or ""):lower():gsub("[^%w]+", " ")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- the continents under the world map (any depth)
local function Continents()
	local list = {}
	local world = C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID()
	if not world then return list end
	for _, info in ipairs(C_Map.GetMapChildrenInfo(world, Enum.UIMapType.Continent, true) or {}) do
		list[#list + 1] = info.mapID
	end
	if #list == 0 then
		local info = C_Map.GetMapInfo(world)
		if info and info.mapType == Enum.UIMapType.Continent then list[1] = world end
	end
	return list
end

-- Least squares for u = a*x + b*y + c (and v the same), on centred and scaled pixels so the sums stay well conditioned.
local function Det3(a, b, c, d, e, f, g, h, i) return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g) end
local function Fit(pairs)
	local n = #pairs
	if n < 3 then return nil end
	local mx, my = 0, 0
	for _, p in ipairs(pairs) do mx, my = mx + p[1], my + p[2] end
	mx, my = mx / n, my / n
	local S = 1000
	local sxx, sxy, sx, syy, sy = 0, 0, 0, 0, 0
	local sxu, syu, su, sxv, syv, sv = 0, 0, 0, 0, 0, 0
	for _, p in ipairs(pairs) do
		local x, y = (p[1] - mx) / S, (p[2] - my) / S
		sxx, sxy, sx, syy, sy = sxx + x * x, sxy + x * y, sx + x, syy + y * y, sy + y
		sxu, syu, su = sxu + x * p[3], syu + y * p[3], su + p[3]
		sxv, syv, sv = sxv + x * p[4], syv + y * p[4], sv + p[4]
	end
	local det = Det3(sxx, sxy, sx, sxy, syy, sy, sx, sy, n)
	if math.abs(det) < 1e-12 then return nil end   -- anchors in a line: no fit
	local function Solve(r1, r2, r3)
		return Det3(r1, sxy, sx, r2, syy, sy, r3, sy, n) / det,
			Det3(sxx, r1, sx, sxy, r2, sy, sx, r3, n) / det,
			Det3(sxx, sxy, r1, sxy, syy, r2, sx, sy, r3) / det
	end
	local a, b, c = Solve(sxu, syu, su)
	local d, e, f = Solve(sxv, syv, sv)
	return { mx = mx, my = my, s = S, a = a, b = b, c = c, d = d, e = e, f = f }
end
local function Apply(t, x, y)
	x, y = (x - t.mx) / t.s, (y - t.my) / t.s
	return t.a * x + t.b * y + t.c, t.d * x + t.e * y + t.f
end
-- fit, drop anchors far off the rest (a misnamed or moved node), fit again
local function RobustFit(pairs)
	local t = Fit(pairs)
	if not t then return nil end
	local errs = {}
	for i, p in ipairs(pairs) do
		local u, v = Apply(t, p[1], p[2])
		errs[i] = math.sqrt((u - p[3]) ^ 2 + (v - p[4]) ^ 2)
	end
	local sorted = {}
	for i, e in ipairs(errs) do sorted[i] = e end
	table.sort(sorted)
	local limit = math.max(0.01, 3 * sorted[math.ceil(#sorted / 2)])
	local kept = {}
	for i, p in ipairs(pairs) do if errs[i] <= limit then kept[#kept + 1] = p end end
	local t2 = (#kept >= 3 and #kept < #pairs) and Fit(kept) or t
	if #kept < 3 then kept = pairs end   -- nothing usable to refit with: the first fit stands, with all its anchors
	local sum = 0
	for _, p in ipairs(kept) do
		local u, v = Apply(t2, p[1], p[2])
		sum = sum + (u - p[3]) ^ 2 + (v - p[4]) ^ 2
	end
	return t2, #kept, #pairs - #kept, math.sqrt(sum / #kept), kept
end

-- Builds P. Called the first time the map shows (the map data is there by then); cheap enough to run once per session.
function ns.Calibrate()
	if calibrated then return true end
	local D = ns.DATA
	if not D then return false end
	-- the flight master pins on Map Genie's side
	local flight = {}
	for ci, c in ipairs(D.cats) do if c.title:find("Flight") then flight[ci] = true end end
	local mgByName = {}
	for i = 1, #D.x do
		if flight[D.cat[i]] then
			mgByName[Norm(D.title[i])] = i
			local town = D.title[i]:match("^([^,]+),")   -- "Stormwind, Elwynn" also answers to "Stormwind"
			if town and not mgByName[Norm(town)] then mgByName[Norm(town)] = i end
		end
	end
	-- the game's flight points per continent, matched by name
	local pairsOf = {}
	for _, cont in ipairs(Continents()) do
		local list = {}
		for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap(cont) or {}) do
			local i = node.name and node.position and mgByName[Norm(node.name)]
			if not i and node.name then
				local town = node.name:match("^([^,]+),")
				i = town and mgByName[Norm(town)]
			end
			if i then list[#list + 1] = { D.x[i], D.y[i], node.position.x, node.position.y } end
		end
		pairsOf[cont] = list
	end
	local fits, anchors = {}, {}
	wipe(report)
	for cont, list in pairs(pairsOf) do
		local t, used, dropped, rms, kept = RobustFit(list)
		local info = C_Map.GetMapInfo(cont)
		report[#report + 1] = { name = info and info.name or tostring(cont), id = cont, used = used or #list, dropped = dropped or 0, rms = rms, ok = t ~= nil }
		fits[cont] = t
		-- only the anchors the fit kept decide which continent nearby pins belong to (a misnamed node is set aside)
		if t then for _, p in ipairs(kept) do anchors[#anchors + 1] = { x = p[1], y = p[2], cont = cont } end end
	end
	if not next(fits) then return false end

	-- every pin: the continent of its nearest anchor (the continents lie well apart on Map Genie's picture), its
	-- position there, its zone and its world position
	for i = 1, #D.x do
		local x, y = D.x[i], D.y[i]
		local best, bd
		for _, a in ipairs(anchors) do
			local d = (a.x - x) ^ 2 + (a.y - y) ^ 2
			if not bd or d < bd then best, bd = a.cont, d end
		end
		if best then
			local cx, cy = Apply(fits[best], x, y)
			P.cont[i], P.cx[i], P.cy[i] = best, cx, cy
			local zone = C_Map.GetMapInfoAtPosition(best, cx, cy)
			P.zone[i] = zone and zone.mapID or best
			local inst, world = C_Map.GetWorldPosFromMapPos(best, CreateVector2D(cx, cy))
			if inst and world then P.inst[i], P.wx[i], P.wy[i] = inst, world.x, world.y end
		end
	end
	calibrated = true
	return true
end

function ns.IsCalibrated() return calibrated end

function ns.ReportCalibration()
	if not calibrated then ns.Calibrate() end
	if #report == 0 then ns.Print("no calibration: no continents or no flight points matched.") return end
	for _, r in ipairs(report) do
		if r.ok then
			-- rms in map units; on a continent map 0.001 is roughly ten yards
			ns.Print(("%s (map %d): %d flight points matched, %d set aside, error %.4f of the map's width."):format(r.name, r.id, r.used, r.dropped, r.rms or 0))
		else
			ns.Print(("%s (map %d): only %d flight points matched; its pins can't be placed."):format(r.name, r.id, r.used))
		end
	end
end

---------------------------------------------------------------------------
-- Positions on any map, cached per map: { idx = {pin, ...}, x = {}, y = {} } with x/y keyed by pin
---------------------------------------------------------------------------
local cache = {}
local ancestorsOf = {}       -- [zone] = { [mapID] = true, ... } up to the continent

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
	if not calibrated or not mapID then return c end   -- not cached: it fills in once calibrated
	cache[mapID] = c
	local info = C_Map.GetMapInfo(mapID)
	if not info then return c end
	-- continents and the world: every pin that lands on the map; zones and smaller: that zone's own pins only
	local wide = info.mapType <= Enum.UIMapType.Continent
	for i = 1, #P.cx do
		local cont = P.cont[i]
		if cont and (wide or Ancestors(P.zone[i])[mapID]) then
			local x, y
			if cont == mapID then
				x, y = P.cx[i], P.cy[i]
			elseif P.inst[i] then
				local _, pos = C_Map.GetMapPosFromWorldPos(P.inst[i], CreateVector2D(P.wx[i], P.wy[i]), mapID)
				if pos then x, y = pos.x, pos.y end
			end
			if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
				c.idx[#c.idx + 1] = i
				c.x[i], c.y[i] = x, y
			end
		end
	end
	return c
end

-- The continent a map belongs to (nil for the world and cosmic maps), cached.
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

-- Any pin's position on any map, even outside that map's own pins (a quest's turn-in in the next zone): its world
-- position projected onto the map, unbounded, so links can point the right way. Returns x, y, onThisMapsPins; nil
-- when the pin is on another continent. Cached per map.
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
		if P.cont[i] == mapID then
			x, y = P.cx[i], P.cy[i]
		elseif P.inst[i] then
			local _, pos = C_Map.GetMapPosFromWorldPos(P.inst[i], CreateVector2D(P.wx[i], P.wy[i]), mapID)
			if pos then x, y = pos.x, pos.y end
		end
		pc.x[i], pc.y[i] = x, y
	end
	if x then return x, pc.y[i], false end
	return nil
end

-- the name of a pin's zone, for tooltips and search results
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
