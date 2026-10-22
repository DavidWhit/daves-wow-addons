-- daves_map / Stitch / Open.lua
-- daves_map's own (not OpenMap's): where the seamless map opens. WorldMap.lua's ResetView asks mod.SavedView(mapID)
-- for a view each time the map opens (nothing is drawn yet); OpenMap's own answer is the view you left. Ours: on you,
-- zoomed in as far as it goes (ResetView clamps the zoom to the deepest at that spot: a city's or a cave's goes
-- further). Only when the map opens where Blizzard puts you (M, and L: MapUtil.GetDisplayableMapForPlayer, your zone
-- or the nearest map above it with art). A quest clicked in the tracker opens the map here, then flies to the quest
-- (Layer.lua: ns.OpenQuestOnMap); one opened with its details page switches to its zone, which shows whole, or in your
-- own zone is shown whole by Layer.lua (its QuestMapFrame_OpenToQuestDetails hook). Off in Options ("Open zoomed in on
-- me"): the whole zone, as Blizzard's.

local ns = select(2, ...).OM
if not ns then return end
local mod = ns:GetModule("worldmap")
if not mod then return end

mod.defaults.openZoomed = true

function mod.SavedView(mapID)
	if not mod.db.openZoomed or not mapID then return end
	local here = (MapUtil and MapUtil.GetDisplayableMapForPlayer and MapUtil.GetDisplayableMapForPlayer())
		or C_Map.GetBestMapForUnit("player")
	if mapID ~= here then return end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")   -- (nil in instances)
	local x, y = ns.Safe.XY(pos)
	if ns.Safe.IsSecret(x) or ns.Safe.IsSecret(y) or not x or not y then return end
	local u, v = mod.ToWorld(mapID, x, y)
	if not u then return end
	return u, v, math.huge
end
