-- The cave and dungeon maps' tiles from OpenMap's own folder (Media/Textures/Forever/MapTile), not
-- the game's: WoW Forever doesn't list them for every language, so some clients (esMX, ruRU,
-- itIT) draw them as solid green squares. Swaps each file ID in Caves.lua's and DungeonMaps.lua's
-- tile lists for its copy (tools/map-tiles/build.py copies them; RADD95's OpenMap TextureFix found it).
-- The same for Gaps.lua's maps of land no zone covers named in GAP_ART: Gilneas's (#152).
-- Written by hand (not generated); loads after Caves.lua, DungeonMaps.lua and Gaps.lua.

local _, ns = ...

local P = ns.Media.tex .. "MapTile\\"

-- (tools/map-tiles/build.py reads this line: the Gaps.lua art it copies)
local GAP_ART = { Gilneas = true }

local function Swap(tiles)
	for k, fid in ipairs(tiles) do
		if type(fid) == "number" and fid ~= 0 then tiles[k] = P .. fid end   -- (0: a tile not drawn)
	end
end

for _, cave in pairs(ns.MapCaves or {}) do
	if cave[11] then Swap(cave[11]) end
end
for _, floors in pairs(ns.MapDungeonMaps or {}) do
	for _, floor in ipairs(floors) do
		if floor.tiles then Swap(floor.tiles) end
	end
end
for _, art in ipairs(ns.MapGaps and ns.MapGaps.art or {}) do
	if GAP_ART[art[1]] then Swap(art[4]) end
end
