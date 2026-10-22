-- daves_map / Layer.lua
-- The pins on the world map: a frame of our own on the map's canvas, holding plain textures and lines.
--
-- Why not Blizzard's pin system (WorldMapFrame:AddDataProvider / AcquirePin)? Both would run Blizzard's map code from
-- addon code: the data provider list and pin pools would be tainted, and every pin Blizzard acquires afterwards calls
-- SetPassThroughButtons (MapCanvas_DataProviderBase.lua CheckMouseButtonPassthrough), which is blocked in combat once
-- tainted. So nothing is registered with the map: our frame sits on the canvas (and so pans and zooms with it), and
-- an OnUpdate on it reads the map's id, zoom and cursor (read only). One small button follows the hovered pin for
-- clicks; everywhere else the map gets the mouse as usual.
--
-- Links (Data.lua): quest -> where it is turned in (endp), quest -> its prerequisites (pre) and follow-ups (the
-- reverse), transport -> destination (dest). Hovering a pin draws its direct links. Clicking a quest selects its
-- chain: the prerequisites back to the first quest and the follow-ups on to the last, numbered in order (badges on
-- the pins) and joined by lines, with each step's turn-in. A step in another zone is held at the map's edge, pointing
-- the way, with its number and zone. Click again to clear. Shift-click sets a waypoint.
--
-- On the seamless map (Stitch\, with daves_map_textures) the same frame sits on the canvas over the stitched art: pins
-- are placed from their place on the stitched world, any pin in view is where it is (no edge markers), and a click
-- that opens another map flies the view there instead (FlyToMap).

local _, ns = ...

local D, P
local overlay, hot
local icons, rings, lines, linked, badges = {}, {}, {}, {}, {}   -- pools: pins, rings, lines, linked icons, step numbers
local nIcons, nRings, nLines, nLinked, nBadges = 0, 0, 0, 0, 0
local chain                  -- the selected pin's chain: { root, steps = {pins in order}, num = {[pin] = n}, set }
local MAX_CHAIN = 60         -- steps at most (a chain that big is really a zone's tangle)
local shown = {}             -- visible pins on the current map, in draw order
local curMap, curScale, curZoom, curW, curH
local dirty = true
local hoverPin, lockedPin
local nextOf = {}            -- [pin] = { follow-up pins } (the reverse of D.pre)
local styles = {}            -- [category index] = { atlas | file | dot, r, g, b, size }
local done = {}              -- [questID] = true/false, this session
local lastCX, lastCY
local searchSet              -- [pin] = true while a search is active (ns.SetSearch)
local BASE = 15              -- pin size in screen pixels at pinScale 1
local posX, posY = {}, {}    -- [pin] = where each shown pin is on the current map (0-1, past it on the seamless map)
local seamX, seamY = {}, {}  -- posX, posY's own tables on the seamless map (reused at each rebuild)

---------------------------------------------------------------------------
-- The seamless map (Stitch\, with daves_map_textures): the view runs past the map underneath into its neighbours,
-- so there pins are placed from their place on the stitched world (u, v) and any pin in view is drawn where it is,
-- not held at the map's edge. The map underneath follows the view by itself; curMap is that map.
---------------------------------------------------------------------------
local stitch, S              -- OpenMap's worldmap module and its art (Stitch\WorldMap.lua, Stitch.lua), when running
local U, V = {}, {}          -- [pin] = its place on the stitched world, or false (its continent isn't stitched)
local win                    -- the stitched world the shown pins were picked from: { u0, u1, v0, v1, zoom }
local builtSeamless = false  -- the pins were last placed for the seamless map
local WIN = 2                -- pins are picked from this many view half-widths round the view's centre

-- the map window shows the seamless map now
local function Stitched() return stitch ~= nil and stitch.IsStitched() end
-- ... and the pins are for the map it shows: a quest opened with the map closed puts the map up and calls in here
-- (ns.Focus) in the same call, before our OnUpdate has caught up with the new map (curMap)
local function Seamless() return Stitched() and curMap == WorldMapFrame:GetMapID() end
function ns.IsSeamless() return Seamless() end

local function WorldUV(i)
	local u = U[i]
	if u == nil then
		u = false
		local cont = P.cont[i]
		if cont and S.Rect(cont) then
			local v
			u, v = stitch.ToWorld(cont, P.cx[i], P.cy[i])
			V[i] = v
		end
		U[i] = u
	end
	if u then return u, V[i] end
end

-- the view has left the stitched world the pins were picked from, or zoomed well in or out of it (`flying`: zoomed in
-- doesn't count, the flight's own way in passes through it)
local checkedScale, checkedX, checkedY, checkedW, checkedH   -- the view WindowStale last looked at (OnUpdate)
local wasAnimating                                         -- the view was flying at the last OnUpdate
local function WindowStale(flying)
	if not win then return true end
	local u, v, zoom = stitch.ViewNow()
	if not u then return false end
	local hu, hv = stitch.ViewHalfExtents(zoom)
	return u - hu < win[1] or u + hu > win[2] or v - hv < win[3] or v + hv > win[4]
		or (zoom > win[5] * 2 and not flying) or zoom < win[5] / 2
end

---------------------------------------------------------------------------
-- Styles: Blizzard's own icons where the client has them, else our dot in the category's colour
---------------------------------------------------------------------------
local function Hex(c)
	if not c or #c ~= 6 then return 1, 1, 1 end
	return tonumber(c:sub(1, 2), 16) / 255, tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255
end
local ATLAS = {   -- by Map Genie icon name; each checked with C_Texture.GetAtlasInfo before use
	quest = { "QuestNormal" }, repeatable = { "QuestNormal" }, graveyard = { "poi-graveyard-neutral" },
	flight_master = { "TaxiNode_Neutral" }, instance = { "Dungeon" }, treasure = { "VignetteLoot" },
}
local TRACKING = {   -- by Map Genie icon name: words to look for in the minimap tracking list's names
	auctioneer = "auction", banker = "bank", innkeeper = "innkeeper", mailbox = "mailbox", repair_vendor = "repair",
	stable_master = "stable", transmogrifier = "transmog", barber_shop = "barber", bonus_objective = "battle",
	merchant = "food", flight_master = "flight",
}
local SIZE = { city = 1.5, town = 1.2, instance = 1.25 }

local function Style(ci)
	local s = styles[ci]
	if s then return s end
	local c = D.cats[ci]
	local r, g, b = Hex(c.color)
	s = { r = r, g = g, b = b, size = SIZE[c.icon] or 1 }
	for _, a in ipairs(ATLAS[c.icon] or {}) do
		if C_Texture.GetAtlasInfo(a) then s.atlas = a break end
	end
	if c.icon == "repeatable" then s.tint = { .35, .7, 1 } end   -- Blizzard's blue for repeatable quests
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
	styles[ci] = s
	return s
end

local function IsDone(q)
	local v = done[q]
	if v == nil then
		v = C_QuestLog.IsQuestFlaggedCompleted(q) and true or false
		done[q] = v
	end
	return v
end

local CLASS_BITS = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 32, MAGE = 64, WARLOCK = 128, DRUID = 256 }
ns.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- a quest's pins in the map data (where it's picked up), by quest ID, in data order; built once
local pinsOfQuest
local function PinsOfQuest(q)   -- (ns.DATA, not D: the tracker asks before the map layer is set up)
	if not pinsOfQuest then
		pinsOfQuest = {}
		local qid = ns.DATA.qid
		for i = 1, #qid do
			local id = qid[i]
			if id ~= 0 then pinsOfQuest[id] = pinsOfQuest[id] or {}; table.insert(pinsOfQuest[id], i) end
		end
	end
	return pinsOfQuest[q]
end
-- its first pin; nil when the data doesn't have it
function ns.QuestPin(q)
	local list = ns.DATA and PinsOfQuest(q)
	return list and list[1]
end

-- The quest focused by a click of yours (any quest click: ns.QuestClicked), kept per character (daves_mapCharDB, made
-- at ADDON_LOADED), not one Blizzard focuses by itself (a quest accepted with nothing focused). With "Click a tracked
-- quest to focus it" on, the map then shows only its pins: where it's picked up, where it's turned in and where it
-- sends you, whatever the filters (it's in your log). focusSet nil: no such focus, or none of its pins in the data
local focusSet, focusFor
function ns.SetClickFocus(q) daves_mapCharDB.focusClick = q end
function ns.ClickFocus() return daves_mapCharDB.focusClick end
function ns.ClickFocused(q) return q == daves_mapCharDB.focusClick and q == C_SuperTrack.GetSuperTrackedQuestID() end
-- true when the set changed (so the pins need placing again)
local function UpdateFocus()
	local q = D and ns.db.focusQuest and C_SuperTrack.GetSuperTrackedQuestID()
	if not q or q == 0 or issecretvalue(q) or q ~= daves_mapCharDB.focusClick then q = nil end
	if q == focusFor then return false end
	focusFor, focusSet = q, nil
	local list = q and PinsOfQuest(q)
	if list then
		focusSet = {}
		for _, i in ipairs(list) do
			focusSet[i] = true
			if D.endp[i] ~= 0 then focusSet[D.endp[i]] = true end
			if D.dest[i] ~= 0 then focusSet[D.dest[i]] = true end
		end
	end
	return true
end
ns.UpdateFocus = UpdateFocus
function ns.Focused() return focusSet ~= nil end

-- the filters; a search shows its matches whatever their category, a focused quest (above) its own pins
local function Passes(i)
	local db = ns.db
	if searchSet then
		if not searchSet[i] then return false end
	elseif focusSet then
		return focusSet[i] == true
	elseif db.hidden[D.cats[D.cat[i]].id] then
		return false
	end
	local f = D.fac[i]
	if f ~= 0 and db.factions and not db.factions[f] then return false end
	local cls = D.cls[i]
	local mine = ns.playerClass and CLASS_BITS[ns.playerClass]
	if cls ~= 0 and mine and not db.otherClasses and bit.band(cls, mine) == 0 then return false end
	if db.hideHighLevel or db.hideLowLevel then
		local lvl, me = D.lvl[i], UnitLevel("player") or 0
		if db.hideHighLevel and lvl > me + 5 then return false end   -- more than 5 above you: up to 5 above is still doable
		if db.hideLowLevel and lvl ~= 0 and lvl < me - db.lowLevelGap then return false end   -- more than the gap below; 0: level unknown, kept
	end
	local q = D.qid[i]
	if q ~= 0 and db.hideCompleted and IsDone(q) then return false end
	return true
end
ns.Passes = Passes

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Icon(n)
	local t = icons[n]
	if not t then
		t = overlay:CreateTexture(nil, "ARTWORK", nil, 1)
		icons[n] = t
	end
	return t
end
local function Ring(n)
	local t = rings[n]
	if not t then
		t = overlay:CreateTexture(nil, "ARTWORK", nil, 3)
		t:SetTexture(ns.MEDIA .. "ring")
		t:SetBlendMode("ADD")
		rings[n] = t
	end
	return t
end
local function LinkedIcon(n)   -- a linked pin drawn over the ring, also when the filters hide it
	local t = linked[n]
	if not t then
		t = overlay:CreateTexture(nil, "ARTWORK", nil, 4)
		linked[n] = t
	end
	return t
end
local function Line(n)
	local l = lines[n]
	if not l then
		l = overlay:CreateLine(nil, "ARTWORK", nil, 0)
		l:SetTexture("Interface\\Buttons\\WHITE8X8")
		lines[n] = l
	end
	return l
end

local function PinSize(i)
	local zoomK = 0.75 + 0.5 * (curZoom or 0)                       -- a little bigger as you zoom in
	return BASE * ns.db.pinScale * zoomK * Style(D.cat[i]).size / (curScale or 1)
end

local function PaintCategory(t, ci, alpha)
	local s = Style(ci)
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
local function PaintIcon(t, i, alpha) PaintCategory(t, D.cat[i], alpha) end
function ns.PaintCategoryIcon(t, ci) PaintCategory(t, ci, 1) end

local function Place(t, x, y, size)
	t:ClearAllPoints()
	t:SetPoint("CENTER", overlay, "TOPLEFT", x * curW, -y * curH)
	t:SetSize(size, size)
end

-- Where a pin is on this map: x, y, on. Pins of this map are exact; any other pin is projected from its world
-- position (ns.ProjectPin) and, when that falls outside the map, held just inside its edge (on = false), so a link to
-- another zone still points the right way. nil when the pin is on another continent.
local EDGE = 0.02
local function Pos(i)
	if Seamless() then   -- every pin where it is: the seamless map shows past this map's edges
		local u, v = WorldUV(i)
		if not u then return nil end   -- (not on the stitched world: this map's edge is open land here, not a border)
		local x, y = stitch.FromWorld(curMap, u, v)
		return x, y, true
	end
	local x, y, mine = ns.ProjectPin(curMap, i)
	if not x then return nil end
	if mine then return x, y, true end   -- a pin drawn on this map stays exactly where it is, even at the edge
	local cx = math.min(1 - EDGE, math.max(EDGE, x))
	local cy = math.min(1 - EDGE, math.max(EDGE, y))
	return cx, cy, cx == x and cy == y
end

local LINK_COLORS = {
	endp = { 1, .82, .2 },        -- turn in here
	pre = { .55, .65, 1 },        -- needs this first
	next = { .35, 1, .45 },       -- leads on to this
	dest = { .3, .9, 1 },         -- travels to
	chain = { .35, 1, .45 },      -- one step to the next in a selected chain
}

-- A quest's chain: its prerequisites back to the first quest and its follow-ups on to the last (not the other
-- branches of quests along the way, which would take in a whole zone), numbered by depth, then title.
local function BuildChain(root)
	local set, count = {}, 0
	local function Walk(i, up)
		if set[i] or count >= MAX_CHAIN then return end
		set[i] = true
		count = count + 1
		for _, j in ipairs((up and D.pre[i] or nextOf[i]) or {}) do Walk(j, up) end
	end
	set[root], count = true, 1
	for _, p in ipairs(D.pre[root] or {}) do Walk(p, true) end
	for _, n in ipairs(nextOf[root] or {}) do Walk(n, false) end
	local depth = {}
	local function Depth(i, guard)
		if depth[i] then return depth[i] end
		local d = 1
		if guard < 64 then
			for _, p in ipairs(D.pre[i] or {}) do
				if set[p] then d = math.max(d, Depth(p, guard + 1) + 1) end
			end
		end
		depth[i] = d
		return d
	end
	local steps = {}
	for i in pairs(set) do Depth(i, 0); steps[#steps + 1] = i end
	table.sort(steps, function(a, b)
		if depth[a] ~= depth[b] then return depth[a] < depth[b] end
		if D.title[a] ~= D.title[b] then return D.title[a] < D.title[b] end
		return a < b
	end)
	local num = {}
	for n, i in ipairs(steps) do num[i] = n end
	return { root = root, steps = steps, num = num, set = set }
end

-- the selected chain, for the panel's step list (nil when nothing with a chain is selected)
function ns.Chain()
	return chain
end

local function Badge(n)   -- a step number on a pin: a frame of its own so it can keep its size while the map zooms
	local b = badges[n]
	if not b then
		b = CreateFrame("Frame", nil, overlay)
		b:SetSize(18, 18)
		b:SetFrameLevel(overlay:GetFrameLevel() + 2)
		b.bg = b:CreateTexture(nil, "ARTWORK")
		b.bg:SetAllPoints()
		b.bg:SetTexture(ns.MEDIA .. "dot")
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		b.text:SetPoint("CENTER", 0, 0)
		b.zone = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.zone:SetPoint("TOP", b, "BOTTOM", 0, -1)
		badges[n] = b
	end
	return b
end

-- A chain step's colour: each step has its own, shared by its badge, the line leading into it and its number in the
-- panel, so a line on the map can be found in the list. They run round the colour wheel in order, green first.
local function HSV(h, s, v)
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
	elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v end
	return v, p, q
end
function ns.StepColor(n, total)
	local k = total > 1 and (n - 1) / total or 0
	return HSV((1 / 3 + k) % 1, .7, 1)
end
local function StepHex(n, total)
	local r, g, b = ns.StepColor(n, total)
	return ("ff%02x%02x%02x"):format(math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end
ns.StepHex = StepHex

local function DrawLine(i, j, kind, alpha, thickPx, color)
	local x1, y1, on1 = Pos(i)
	local x2, y2, on2 = Pos(j)
	if not (x1 and x2) or (x1 == x2 and y1 == y2) then return end
	if not (on1 or on2) then return end   -- both ends off this map: it would only run along the border
	nLines = nLines + 1
	local ln = Line(nLines)
	local c = color or LINK_COLORS[kind]
	ln:SetStartPoint("TOPLEFT", overlay, x1 * curW, -y1 * curH)
	ln:SetEndPoint("TOPLEFT", overlay, x2 * curW, -y2 * curH)
	ln:SetThickness(thickPx / (curScale or 1))
	ln:SetVertexColor(c[1], c[2], c[3], alpha)
	ln:Show()
end

-- a ring round a pin and its icon above the others, also when the filters hide it (only where it really is)
local function Mark(i, focus, color)   -- color: a chain step's ring takes its step colour
	local x, y, on = Pos(i)
	if not (x and on) then return end
	local size = PinSize(i)
	nRings = nRings + 1
	local r = Ring(nRings)
	Place(r, x, y, size * 1.9)
	if focus then r:SetVertexColor(1, .9, .3)
	elseif color then r:SetVertexColor(color[1], color[2], color[3])
	else r:SetVertexColor(.9, .9, .9) end
	r:Show()
	nLinked = nLinked + 1
	local t = LinkedIcon(nLinked)
	PaintIcon(t, i, 1)
	Place(t, x, y, size * 1.15)
	t:Show()
end

-- steps off this map share one badge per zone at the edge ("3, 4, 7"), so they don't pile up on one point
local edgeBadges = {}

local function FitBadge(b)
	b:SetWidth(math.max(18, b.text:GetStringWidth() + 10))
end

-- a step's number in its colour, for the shared edge badges ("3, 4, 7", each in its own colour)
local function StepNums(nums, total)
	local out = {}
	for k, n in ipairs(nums) do out[k] = ("|c%s%d|r"):format(StepHex(n, total), n) end
	return table.concat(out, ", ")
end

local function DrawStep(i, n, isRoot, total)
	local x, y, on = Pos(i)
	if not x then return end
	if not on then
		local zone = P.zone[i] or 0
		local shared = edgeBadges[zone]
		if shared then
			shared.nums[#shared.nums + 1] = n
			shared.bg:SetVertexColor(.12, .1, .06)   -- several steps: a dark badge, each number in its colour
			shared.text:SetTextColor(1, 1, 1)
			shared.text:SetText(StepNums(shared.nums, total))
			FitBadge(shared)
			return
		end
	end
	nBadges = nBadges + 1
	local b = Badge(nBadges)
	local k = curScale or 1
	b:SetScale(1 / k)   -- constant on screen: offsets below are in the badge's own (unzoomed) units
	local px, py = x * curW * k, -y * curH * k
	local lift = on and PinSize(i) * k * 0.5 or 0   -- beside the pin's top right; on the edge marker itself when away
	b:ClearAllPoints()
	b:SetPoint("CENTER", overlay, "TOPLEFT", px + lift, py + lift)
	b.text:SetText(n)
	-- the step's colour; the selected quest's number is white (its ring is gold: Mark)
	b.bg:SetVertexColor(ns.StepColor(n, total))
	if isRoot then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(0, 0, 0) end
	b.zone:SetText(on and "" or (ns.ZoneName(i) or ""))
	b:SetAlpha(on and 1 or .85)
	b.nums = { n }
	FitBadge(b)
	if not on then edgeBadges[P.zone[i] or 0] = b end
	b:Show()
end

local function DrawLinks()
	nRings, nLines, nLinked, nBadges = 0, 0, 0, 0
	wipe(edgeBadges)
	if curMap and ns.db.enabled then
		if lockedPin then
			if not chain or chain.root ~= lockedPin then chain = BuildChain(lockedPin) end
			-- step to step along the chain, each step's turn-in, then the numbers on top
			-- (each line into a step, and its ring, in that step's colour)
			local total = #chain.steps
			local colors = {}
			for n, i in ipairs(chain.steps) do colors[i] = total > 1 and { ns.StepColor(n, total) } or nil end
			for _, i in ipairs(chain.steps) do
				for _, p in ipairs(D.pre[i] or {}) do if chain.set[p] then DrawLine(p, i, "chain", .9, 3, colors[i]) end end
				if D.endp[i] ~= 0 then DrawLine(i, D.endp[i], "endp", .7, 1.5) end
				if D.dest[i] ~= 0 then DrawLine(i, D.dest[i], "dest", .8, 2) end
			end
			for _, i in ipairs(chain.steps) do
				Mark(i, i == lockedPin, colors[i])
				if D.endp[i] ~= 0 and not chain.set[D.endp[i]] then Mark(D.endp[i], false) end
			end
			if total > 1 then
				for n, i in ipairs(chain.steps) do DrawStep(i, n, i == lockedPin, total) end
			end
		elseif hoverPin then
			local i = hoverPin
			if D.endp[i] ~= 0 then DrawLine(i, D.endp[i], "endp", .85, 2.5); Mark(D.endp[i], false) end
			if D.dest[i] ~= 0 then DrawLine(i, D.dest[i], "dest", .85, 2.5); Mark(D.dest[i], false) end
			for _, p in ipairs(D.pre[i] or {}) do DrawLine(p, i, "pre", .85, 2.5); Mark(p, false) end
			for _, n in ipairs(nextOf[i] or {}) do DrawLine(i, n, "next", .85, 2.5); Mark(n, false) end
			Mark(i, true)
		end
	end
	for n = nLines + 1, #lines do lines[n]:Hide() end
	for n = nRings + 1, #rings do rings[n]:Hide() end
	for n = nLinked + 1, #linked do linked[n]:Hide() end
	for n = nBadges + 1, #badges do badges[n]:Hide() end
end

local function Rebuild()
	dirty = false
	-- the hovered pin may be filtered out now, or the map changed: start the hover afresh
	hoverPin, lastCX, lastCY = nil, nil, nil
	if hot then
		hot:Hide()
		if GameTooltip:GetOwner() == hot then GameTooltip:Hide() end
	end
	wipe(shown)
	nIcons = 0
	local keepWin = win   -- (filled again in place on the seamless map, below)
	win = nil
	builtSeamless = Seamless()
	local level = ns.OverlayLevel()   -- (the seamless map's layers are added after us)
	if overlay and overlay:GetFrameLevel() ~= level then
		overlay:SetFrameLevel(level)
		hot:SetFrameLevel(level + 1)
		for _, b in ipairs(badges) do b:SetFrameLevel(level + 2) end
	end
	local function Add(i, x, y)
		shown[#shown + 1] = i
		nIcons = nIcons + 1
		local t = Icon(nIcons)
		local q = D.qid[i]
		PaintIcon(t, i, (q ~= 0 and IsDone(q)) and .35 or 1)   -- completed quests dimmed
		Place(t, x, y, PinSize(i))
		t:Show()
	end
	if ns.db.enabled and D and curMap and ns.Calibrate() then
		local u, v, zoom = nil, nil, nil
		if Seamless() then u, v, zoom = stitch.ViewNow() end
		if u then
			-- the pins round the view on the stitched world, wherever their zone (rebuilt as the view moves on: OnUpdate)
			local hu, hv = stitch.ViewHalfExtents(zoom)
			win = keepWin or {}
			win[1], win[2], win[3], win[4], win[5] = u - hu * WIN, u + hu * WIN, v - hv * WIN, v + hv * WIN, zoom
			wipe(seamX) wipe(seamY)   -- (not posX itself: off the seamless map it's PinsOnMap's own table)
			posX, posY = seamX, seamY
			for i = 1, #D.x do
				local pu, pv = WorldUV(i)
				if pu and pu >= win[1] and pu <= win[2] and pv >= win[3] and pv <= win[4] and Passes(i) then
					local x, y = stitch.FromWorld(curMap, pu, pv)
					posX[i], posY[i] = x, y
					Add(i, x, y)
				end
			end
		else
			local c = ns.PinsOnMap(curMap)
			posX, posY = c.x, c.y
			for _, i in ipairs(c.idx) do
				if Passes(i) then Add(i, c.x[i], c.y[i]) end
			end
		end
	end
	for n = nIcons + 1, #icons do icons[n]:Hide() end
	if lockedPin and not ns.db.enabled then lockedPin, chain = nil, nil end
	DrawLinks()
	if ns.OnLayerChanged then ns.OnLayerChanged() end
end

-- sizes only (zooming): the textures keep their places on the canvas
local function Resize()
	for n, i in ipairs(shown) do
		local size = PinSize(i)
		icons[n]:SetSize(size, size)
	end
	DrawLinks()
end

---------------------------------------------------------------------------
-- Hover and click
---------------------------------------------------------------------------
local function PinAt(cx, cy)
	local px, py = cx * curW, cy * curH
	local best, bd
	for n = #shown, 1, -1 do   -- the last drawn is on top
		local i = shown[n]
		local r = PinSize(i) * 0.55
		local dx, dy = posX[i] * curW - px, posY[i] * curH - py
		local d = dx * dx + dy * dy
		if d <= r * r and (not bd or d < bd) then best, bd = i, d end
	end
	return best
end

local function SetHover(i)
	if i == hoverPin then return end
	hoverPin = i
	local x, y
	if i then x, y = Pos(i) end
	if i and not x then hoverPin, i = nil, nil end   -- (nowhere to put it: as no pin)
	if i then
		local size = PinSize(i)
		hot:ClearAllPoints()
		hot:SetPoint("CENTER", overlay, "TOPLEFT", x * curW, -y * curH)
		hot:SetSize(size, size)
		hot:Show()
		ns.ShowTooltip(hot, i)
	else
		hot:Hide()
		if GameTooltip:GetOwner() == hot then GameTooltip:Hide() end
	end
	DrawLinks()
end

-- Blizzard's own map sounds for the same actions (Blizzard_WorldMap, Blizzard_SharedMapDataProviders)
-- one sound a click: the first in a frame (a search result's click would otherwise play the list's, the selection's
-- and the map's, all at once); the panel's too (ns.Sound). `force`: played all the same (it's the one that says what
-- happened: a waypoint placed, a quest focused again)
local soundAt, muted   -- muted: the map selecting a quest's pin for a quest opened elsewhere, whose own sound speaks
local function Sound(name, force)
	local now = GetTime()
	if muted or (soundAt == now and not force) then return end
	local id = SOUNDKIT and SOUNDKIT[name]
	if id then PlaySound(id) soundAt = now end
end
ns.Sound = Sound

function ns.SetWaypoint(i)
	local zone = P.zone[i]
	if not zone or not C_Map.CanSetUserWaypointOnMap(zone) then
		ns.Print("can't set a waypoint there.")
		return
	end
	local c = ns.PinsOnMap(zone)
	local x, y = c.x[i], c.y[i]
	if not x then return end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(zone, x, y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	Sound("UI_MAP_WAYPOINT_CLICK_TO_PLACE", true)
	ns.Print(("waypoint: %s (%s %.1f, %.1f)."):format(D.title[i], ns.ZoneName(i) or "?", x * 100, y * 100))
end

-- The seamless map's view flown to a point of the stitched world (stitch.Fly: out while it moves, then in on it,
-- centred on it): `factor` times the zoom where `mapID` fills the view (its centre when there's no point), or with
-- `keepZoom` as far in as the view is already when that's further
local function FlyView(mapID, u, v, factor, keepZoom)
	if not u then
		local l, r, t, b = S.Rect(mapID)
		u, v = (l + r) / 2, (t + b) / 2
	end
	local zoom = stitch.FitZoom(mapID) * (factor or 1)
	if keepZoom then
		local _, _, now = stitch.ViewNow()
		if now and now > zoom then zoom = now end
	end
	stitch.Fly(u, v, zoom)
end

-- On the seamless map: flies the view to a point of the stitched world at the zoom where `mapID` fills the view, as
-- its own clicks do. The map underneath follows by itself once the view settles, out of combat (Stitch\WorldMap.lua),
-- so this works in combat too. False when that map isn't part of the stitched world (a dungeon, another continent).
-- `closer`: that many times further in (a chain step: the step itself, not its whole zone), or as far in as it is now
local function FlyToMap(mapID, u, v, closer)
	if not (Stitched() and mapID and S.Rect(mapID) and WorldMapFrame:IsShown()) then return false end
	Sound("IG_QUEST_LOG_OPEN")
	FlyView(mapID, u, v, closer, closer ~= nil)
	return true
end

-- Turns the open world map to another map. SetMapID from addon code taints the map's refresh, and its pins'
-- SetPassThroughButtons is blocked in combat (see the top of this file), so not in combat. True when it switched.
local function ShowMap(mapID)
	if FlyToMap(mapID) then return true end
	if not mapID or mapID == curMap or not WorldMapFrame:IsShown() then return false end
	if InCombatLockdown() then
		ns.Print("can't change the map in combat.")
		return false
	end
	Sound("IG_QUEST_LOG_OPEN")   -- as following a map link on Blizzard's map (MapLinkDataProvider)
	WorldMapFrame:SetMapID(mapID)
	return true
end

-- the map a pin is on (a click in the panel); on the seamless map, its zone's view centred on the pin. `close` (a chain
-- step): on the seamless map, always there and zoomed in on it (STEP_ZOOM times its zone's view), in view or not.
-- False when there's nothing to open: the pin is on this map, or (seamless, not `close`) already in view
local STEP_ZOOM = 4
local IN_VIEW = 0.8   -- "in view": inside this much of the view (one at its very edge is brought in)
function ns.ShowPinMap(i, close)
	local u, v
	if Stitched() then u, v = WorldUV(i) end
	if u then
		local cu, cv, zoom = stitch.ViewNow()
		if cu and not close then
			local hu, hv = stitch.ViewHalfExtents(zoom)
			if math.abs(u - cu) < hu * IN_VIEW and math.abs(v - cv) < hv * IN_VIEW then return false end
		end
		if FlyToMap(P.zone[i], u, v, close and STEP_ZOOM or nil) then return true end
	end
	return ShowMap(P.zone[i])
end

-- A quest's place on the seamless map: the flight to it, centred, at QUEST_ZOOM times its zone's view (the whole zone
-- when it has no place on it). Two ways in: a quest's details page opened with the map (the tracker's click, its
-- menu's "Show on map", ns.QuestClicked: QuestMapFrame_OpenToQuestDetails), where Blizzard has put up its zone whole
-- at once, so from the view you had (FlyToQuest); and a click that only centres it (CentreQuest)
local QUEST_ZOOM = 2
local function FlyToQuestOn(mapID, questID, keepZoom)
	local u, v
	local ok, quests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
	for _, q in ipairs(ok and type(quests) == "table" and quests or {}) do
		if q.questID == questID and q.x and q.y and not issecretvalue(q.x) and not issecretvalue(q.y) then
			u, v = stitch.ToWorld(mapID, q.x, q.y)
			break
		end
	end
	FlyView(mapID, u, v, u and QUEST_ZOOM or 1, keepZoom)
end

-- the stitched map Blizzard has just put up for a quest's details page, or nil. It picks between the quest's own map
-- and its next waypoint's, by a choice of the player's we can't read, and leaves the one it picked in the details
-- frame (read only). (Stitched, not Seamless: curMap is only brought up to date in our OnUpdate, after this)
local function QuestDetailsStitchedMap(questID)
	if not (Stitched() and questID and not issecretvalue(questID)) then return end
	local mapID = WorldMapFrame:GetMapID()
	local d = QuestMapFrame and QuestMapFrame.DetailsFrame
	if mapID and d and d.questMapID == mapID and S.Rect(mapID) then return mapID end
end

local function FlyToQuest(questID)
	local mapID = QuestDetailsStitchedMap(questID)
	if not mapID then return end
	local u0, v0, z0 = stitch.ViewBeforeReset()
	if u0 then stitch.ShowNow(u0, v0, z0) end      -- (no reset: the quest is on the map you were on; from where you are)
	FlyToQuestOn(mapID, questID, true)
end

-- an open seamless map centred on a quest where it is (a click that let go of its focus, or one in combat): nothing
-- opened or switched, nothing for a quest with no place on the stitched world
local function CentreQuest(q)
	if not (WorldMapFrame:IsShown() and Stitched()) then return end
	local mapID = GetQuestUiMapID and GetQuestUiMapID(q)
	if not mapID or mapID == 0 or issecretvalue(mapID) or not S.Rect(mapID) then return end
	FlyToQuestOn(mapID, q, true)
end

-- a plain left click on a quest: not Shift (Blizzard's track / untrack) or a link into chat
function ns.PlainLeftClick(button)
	return button == "LeftButton" and not IsShiftKeyDown() and not IsModifiedClick("CHATLINK")
end

-- A quest clicked: in Blizzard's tracker (its name, its "..." icon), on the map (its "..." icon), in the quest log's
-- list (its name, its "..." icon), or a Ready to Turn In row (Tracker.lua). With "Click a tracked quest to focus it"
-- on, they all do the same, each after Blizzard's own click has done its part: the quest focused (super-tracked; our
-- click's focus, so Dave's Map shows only its pins), its details page open in the quest log beside the map
-- (Blizzard's: the map then shows that quest's icons) and the map centred on it (the QuestMapFrame_OpenToQuestDetails
-- hook, or FlyToQuest here). Clicked again (focused by a click of ours), let go: the focus off (Blizzard closes the
-- details page then) and an open map centred on it. `how`: "toggle" (we focus or let go: the tracker's name, our
-- rows), "focused" (Blizzard's "..." has already focused it or let it go), "details" (Blizzard's quest log has opened
-- its details page: focused, not let go). In combat an addon can't open the map: an open one is centred, a closed one
-- waits for the next click after combat. True when it let go (the caller's sound)
local pendingOpen   -- the quest focused in combat with the map closed: its next click shows it rather than letting go
local ownOpen       -- our QuestMapFrame_OpenToQuestDetails under way (its hook then plays no sound)
local lastFlight, lastFlightAt   -- the quest the OpenToQuestDetails hook last flew to, and when
function ns.QuestClicked(q, how, toggleSound)
	if not (ns.db.focusQuest and type(q) == "number" and q ~= 0) or issecretvalue(q) then return end
	local now = C_SuperTrack.GetSuperTrackedQuestID()
	local reopen = pendingOpen == q and not InCombatLockdown()
	pendingOpen = nil
	local letGo
	if how == "toggle" then letGo = ns.ClickFocused(q) and not reopen
	elseif how == "focused" then letGo = now ~= q and not reopen   -- (Blizzard let it go; after combat, shown instead)
	else letGo = false end
	-- `toggleSound` (our rows): "off" or "on" for what it does, first in the frame, before the map can sound
	if toggleSound then Sound(letGo and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON") end
	if letGo then
		ns.SetClickFocus(nil)
		if now == q then C_SuperTrack.SetSuperTrackedQuestID(0) end
		-- (not when Blizzard's own click has just opened it and flown there: a tracker name's)
		if not (lastFlight == q and lastFlightAt == GetTime()) then CentreQuest(q) end
		return true
	end
	ns.SetClickFocus(q)
	-- (a "..." clicked again after combat: Blizzard's click let it go with its "off" sound; focused again, so "on")
	if how == "focused" and reopen and now ~= q then Sound("IG_MAINMENU_OPTION_CHECKBOX_ON", true) end
	if now ~= q then
		C_SuperTrack.SetSuperTrackedQuestID(q)   -- (its event refreshes the map's filter)
	elseif UpdateFocus() then   -- (already focused, by Blizzard just now or before: our click's filter now)
		ns.Refresh()
	end
	if how == "details" then FlyToQuest(q) return false end   -- (Blizzard has just put its zone up: from the view you had)
	local d = QuestMapFrame and QuestMapFrame.DetailsFrame
	if WorldMapFrame:IsShown() and d and d:IsShown() and d.questID == q then return false end   -- (open already: flown)
	if InCombatLockdown() then
		if WorldMapFrame:IsShown() then
			CentreQuest(q)
		else
			pendingOpen = q
			ns.Print("focused it; can't open the map in combat: click it again after combat to see it.")
		end
		return false
	end
	if QuestMapFrame_OpenToQuestDetails then   -- (its hook flies there; silent: the click's own sound has played)
		ownOpen = true
		xpcall(QuestMapFrame_OpenToQuestDetails, CallErrorHandler, q)
		ownOpen = nil
	end
	return false
end

-- a "..." quest icon (a POI button: the tracker's, the quest log list's) whose click is a quest click ("focused"),
-- hooked once. The quest is read before Blizzard's click: tracking a quest from it lays the list or the tracker out
-- again, which hands the icons out again, so after the click the icon may hold another quest. `accept(poi)`: false
-- for an icon that isn't a quest's of ours (the tracker's other sections share its icons)
local hookedPOI, clickQuest = {}, nil
local function BeforePOIClick(poi)
	local accept = hookedPOI[poi]
	clickQuest = (accept == true or accept(poi)) and poi.GetQuestID and poi:GetQuestID() or nil
end
local function OnPOIClick(_, button)
	local q = clickQuest
	clickQuest = nil
	if q and ns.PlainLeftClick(button) then ns.QuestClicked(q, "focused") end
end
function ns.HookQuestPOI(poi, accept)
	if not poi or hookedPOI[poi] then return end
	hookedPOI[poi] = accept or true
	poi:HookScript("PreClick", BeforePOIClick)
	poi:HookScript("OnClick", OnPOIClick)
end

-- lock a pin's chain on the map (a search result, or a click); nil clears it
function ns.Focus(i)
	lockedPin = (i ~= lockedPin) and i or nil
	Sound(lockedPin and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")   -- as Blizzard's map pins toggle
	chain = lockedPin and BuildChain(lockedPin) or nil
	DrawLinks()
	if ns.OnLayerChanged then ns.OnLayerChanged() end
end
function ns.FocusedPin() return lockedPin end

-- Many of Forever's classic quests have no map location in the game (GetQuestUiMapID is 0), so opening one leaves
-- the map where it was with nothing marked. Then the map data stands in: the quest's chain is selected (its pin, its
-- turn-in and the steps around it) and the map turns to where you go next: the turn-in when it's ready, else where
-- it was picked up. Not in combat (ns.ShowPinMap).
function ns.ShowQuestOnMap(q)
	if not (D and ns.Calibrate()) then return end
	local i = ns.QuestPin(q)
	if not i then return false end
	local e = D.endp[i]
	local ready = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q)
	-- silent: the quest was opened elsewhere (the tracker, the quest log), and that click's own sound speaks for it
	local was = muted
	muted = true
	xpcall(function()   -- (an error reported from where it happened; muted always put back)
		if lockedPin ~= i then ns.Focus(i) end
		ns.ShowPinMap((ready and e ~= 0) and e or i)
	end, CallErrorHandler)
	muted = was
	return true
end

-- the zone a quest is filed under in the quest log: the header above it
local function QuestHeader(q)
	local idx = C_QuestLog.GetLogIndexForQuestID(q)
	for k = idx or 0, 1, -1 do
		local info = C_QuestLog.GetInfo(k)
		if info and info.isHeader then return info.title end
	end
end

-- a game map by its name, from every map under the world and cosmic maps (looked up once)
local mapByName
local function MapNamed(name)
	if not mapByName then
		mapByName = {}
		local roots = { C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID() or 0, 946 }   -- 946: the cosmic map
		for _, root in ipairs(roots) do
			for _, info in ipairs(root ~= 0 and C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
				if info.name and not mapByName[info.name] then mapByName[info.name] = info.mapID end
			end
		end
	end
	return mapByName[name]
end

-- "No map location": a dark veil of our own over the map, so it doesn't look as if the map it was on is the answer.
-- Blizzard's map can't be blanked, so this covers it. It goes when the map changes (OnUpdate), when the map closes,
-- or on a click.
local veil
local function ShowVeil(title, zone)
	if not veil then
		veil = CreateFrame("Button", nil, WorldMapFrame.ScrollContainer)
		veil:SetAllPoints()
		veil:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST") + 5)
		local bg = veil:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, .82)
		veil.title = veil:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		veil.title:SetPoint("BOTTOM", veil, "CENTER", 0, 14)
		veil.title:SetWidth(520)
		veil.text = veil:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		veil.text:SetPoint("TOP", veil, "CENTER", 0, 0)
		veil.text:SetWidth(460)
		veil.hint = veil:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		veil.hint:SetPoint("TOP", veil.text, "BOTTOM", 0, -12)
		veil.hint:SetText("Click to close")
		veil:SetScript("OnClick", function(self) self:Hide() end)
		veil:SetScript("OnHide", function(self) self:Hide() end)   -- the map closing: don't come back with it
	end
	veil.title:SetText(title)
	veil.text:SetText("No map location: the game has none for this quest, and Map Genie's map doesn't list it"
		.. (zone and (".\nThe quest log files it under " .. zone .. ", which has no map of its own.") or "."))
	veil.mapID = WorldMapFrame:GetMapID()   -- the map now (opening the quest log may just have turned it)
	veil:Show()
end
function ns.HideVeilIfMoved()   -- OnUpdate: the map turned elsewhere
	if veil and veil:IsShown() and veil.mapID ~= curMap then veil:Hide() end
end

-- With no location in the game or the map data (an instance like the Deeprun Tram, or a quest Map Genie doesn't
-- list): the game's map of the zone the quest log files it under, even when that map is empty (with a note, once a
-- session); with no such map, the veil above.
local toldNoMap = {}
local function OnQuestDetails(q)
	if type(q) ~= "number" or not GetQuestUiMapID or GetQuestUiMapID(q) ~= 0 then return end
	if ns.ShowQuestOnMap(q) ~= false then return end
	local zone = QuestHeader(q)
	local mapID = zone and MapNamed(zone)
	local title = C_QuestLog.GetTitleForQuestID(q) or tostring(q)
	if not mapID then ShowVeil(title, zone) return end
	ShowMap(mapID)
	if not toldNoMap[q] then
		toldNoMap[q] = true
		ns.Print(("no exact spot for \"%s\": showing its zone, %s."):format(title, zone))
	end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local FACTION_NAME = { "Alliance", "Horde", "Neutral" }
local FACTION_COLOR = { { .3, .55, 1 }, { 1, .3, .3 }, { 1, .82, .2 } }

local function LinkLine(label, list, base)   -- base: the pin the tooltip is for; other zones are named
	if #list == 0 then return end
	local here = ns.ZoneName(base)
	local names = {}
	for n, j in ipairs(list) do
		if n > 4 then names[#names + 1] = ("+%d more"):format(#list - 4) break end
		local z = ns.ZoneName(j)
		names[#names + 1] = D.title[j] .. ((z and z ~= here) and (" (" .. z .. ")") or "")
	end
	GameTooltip:AddLine(label .. table.concat(names, ", "), .8, .8, .8, true)
end

function ns.ShowTooltip(owner, i)
	local c = D.cats[D.cat[i]]
	local s = Style(D.cat[i])
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(D.title[i], 1, 1, 1, true)
	local zone = ns.ZoneName(i)
	GameTooltip:AddDoubleLine(c.title, zone or "", s.r, s.g, s.b, .7, .7, .7)
	local f = D.fac[i]
	if f ~= 0 then local fc = FACTION_COLOR[f]; GameTooltip:AddLine(FACTION_NAME[f], fc[1], fc[2], fc[3]) end
	local text = D.text[i]
	if text ~= "" then
		for line in text:gmatch("[^\n]+") do
			if not line:find("Faction:") and not line:find("Side:") then GameTooltip:AddLine(line, .9, .9, .9, true) end
		end
	end
	local q = D.qid[i]
	if q ~= 0 and IsDone(q) then GameTooltip:AddLine("Completed", .4, 1, .4) end
	if D.endp[i] ~= 0 then LinkLine("|cffffd200Turn in:|r ", { D.endp[i] }, i) end
	LinkLine("|cff8ca6ffRequires:|r ", D.pre[i] or {}, i)
	LinkLine("|cff59ff73Leads to:|r ", nextOf[i] or {}, i)
	if D.dest[i] ~= 0 then LinkLine("|cff4de6ffTravels to:|r ", { D.dest[i] }, i) end
	if chain and chain.num[i] and #chain.steps > 1 then
		GameTooltip:AddLine(("Step %d of %d in the selected chain"):format(chain.num[i], #chain.steps), 1, .82, .2)
	end
	local hint
	if lockedPin == i then hint = "Click: clear the selection"
	elseif D.pre[i] or nextOf[i] then hint = "Click: show this quest chain, numbered in order"
	else hint = "Click: keep its links drawn" end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(hint .. "\nShift-click: set a waypoint", .5, .8, 1)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Setup and the per-frame watch
---------------------------------------------------------------------------
local function OnUpdate()
	local map = WorldMapFrame:GetMapID()
	local canvas = WorldMapFrame:GetCanvas()
	local w, h = canvas:GetWidth(), canvas:GetHeight()
	if map ~= curMap or w ~= curW or h ~= curH then
		curMap, curW, curH = map, w, h
		dirty = true   -- Rebuild clears the hover
		ns.HideVeilIfMoved()
	end
	local scale, zoom = WorldMapFrame:GetCanvasScale(), WorldMapFrame:GetCanvasZoomPercent()
	-- the seamless map: on as the map turns to or from it, and its view moved on past the pins picked for it (looked
	-- at only when the view has moved; during a flight, zooming in alone doesn't count: the pins are already there)
	local seamless = Seamless()
	local animating = seamless and stitch.Flying()   -- (a flight only: wheel zooms and glides as ever)
	if wasAnimating and not animating then checkedScale = nil end   -- (landed: looked at again, zooming in counts now)
	wasAnimating = animating
	if seamless ~= builtSeamless then
		dirty = true
	elseif win then
		local sc = WorldMapFrame.ScrollContainer
		local sx, sy, sw, sh = sc:GetCurrentScrollX(), sc:GetCurrentScrollY(), sc:GetWidth(), sc:GetHeight()
		if scale ~= checkedScale or sx ~= checkedX or sy ~= checkedY or sw ~= checkedW or sh ~= checkedH then
			checkedScale, checkedX, checkedY, checkedW, checkedH = scale, sx, sy, sw, sh
			if WindowStale(animating) then dirty = true end
		end
	end
	if dirty then
		curScale, curZoom = scale, zoom
		Rebuild()
	elseif scale ~= curScale or zoom ~= curZoom then
		curScale, curZoom = scale, zoom
		Resize()
		if hoverPin then local s = PinSize(hoverPin); hot:SetSize(s, s) end
	end
	-- hover: only over bare canvas or our own button, so Blizzard's pins keep their mouse
	if #shown == 0 then
		if hoverPin then SetHover(nil) end
		return
	end
	if animating or not (WorldMapFrame.ScrollContainer:IsMouseMotionFocus() or hot:IsMouseMotionFocus()) then
		if hoverPin then SetHover(nil) end   -- (and none while the view flies: the pins sweep under the mouse)
		lastCX = nil
		return
	end
	local cx, cy
	if seamless then
		-- (Blizzard's cursor position is held inside the map underneath: Saturate in NormalizeUIPosition)
		local u, v = stitch.CursorWorld()
		if u then cx, cy = stitch.FromWorld(curMap, u, v) end
	end
	if not cx then cx, cy = WorldMapFrame:GetNormalizedCursorPosition() end
	if cx == lastCX and cy == lastCY then return end
	lastCX, lastCY = cx, cy
	SetHover(PinAt(cx, cy))
end

function ns.Refresh()
	dirty = true
	if overlay and overlay:IsVisible() then OnUpdate() end
end

-- search: a set of matching pins, or nil
function ns.SetSearch(set)
	searchSet = set
	ns.Refresh()
end

function ns.ShownCount() return #shown end
function ns.CurrentMap() return curMap end

-- Blizzard's map layers are pins with absolute frame levels from 2000 up (MapCanvas_PinFrameLevelsManager.lua): the
-- explored-area art, fog of war and zone highlight are among them. Just above the highlight puts us over all the map's
-- art and under its markers (dig sites, dungeon entrances, flight points, POIs). The seamless map inserts its art
-- under the highlight and its own icons just above it (Stitch\WorldMap.lua): then above those. Read each rebuild, as
-- the seamless map adds its layers when it starts. GetValidFrameLevel only reads.
-- (ours, or OpenMap's own when that addon is on instead: its icons go just above the highlight too)
local STITCH_ICON_LEVELS = { "PIN_FRAME_LEVEL_DAVES_MAP_STITCH_ICONS", "PIN_FRAME_LEVEL_OPENMAP_ICONS" }
function ns.OverlayLevel()
	local levels = WorldMapFrame:GetPinFrameLevelsManager()
	local level = levels:GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT") + 1
	for _, name in ipairs(STITCH_ICON_LEVELS) do
		local d = levels.definitions and levels.definitions[name]
		if d then level = math.max(level, d.startLevel + d.range) end
	end
	return level
end

local function Init()
	D = ns.DATA
	P = ns.P
	-- follow-ups: the reverse of the prerequisites
	for i, list in pairs(D.pre) do
		for _, p in ipairs(list) do
			nextOf[p] = nextOf[p] or {}
			table.insert(nextOf[p], i)
		end
	end
	local om = ns.OM
	stitch = om and om:GetModule("worldmap")
	S = om and om.MapStitch
	if not (stitch and S) then stitch, S = nil, nil end
	local canvas = WorldMapFrame:GetCanvas()
	overlay = CreateFrame("Frame", nil, canvas)
	overlay:SetAllPoints(canvas)
	overlay:SetFrameLevel(ns.OverlayLevel())
	overlay:SetScript("OnUpdate", OnUpdate)

	hot = CreateFrame("Button", nil, overlay)
	hot:SetFrameLevel(overlay:GetFrameLevel() + 1)
	hot:RegisterForClicks("LeftButtonUp")
	hot:Hide()
	-- right-clicks go on to the map (zoom out / up a level), as on Blizzard's pins. A left-drag that starts on a pin
	-- doesn't pan: left clicks are the pin's. SetPassThroughButtons is restricted on protected frames in combat; ours is
	-- a plain button, but it is set outside combat all the same.
	if InCombatLockdown() then ns.events:RegisterEvent("PLAYER_REGEN_ENABLED") else hot:SetPassThroughButtons("RightButton") end
	hot:SetScript("OnClick", function()
		if not hoverPin then return end
		if IsShiftKeyDown() then ns.SetWaypoint(hoverPin) else ns.Focus(hoverPin) end
	end)
	hot:SetScript("OnEnter", function(self) if hoverPin then ns.ShowTooltip(self, hoverPin) end end)
	hot:SetScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)

	ns.events:RegisterEvent("QUEST_TURNED_IN")
	ns.events:RegisterEvent("PLAYER_LEVEL_UP")
	ns.events:RegisterEvent("SUPER_TRACKING_CHANGED")   -- a quest focused or unfocused: the map's pins follow
	UpdateFocus()
	-- opening a quest's details page (the quest log, the tracker's menu, its pop-up): stand in for a missing map location
	if QuestMapFrame_ShowQuestDetails then hooksecurefunc("QuestMapFrame_ShowQuestDetails", OnQuestDetails) end
	-- a quest's details opened with the map (the tracker's click, its menu's "Show on map", our ns.QuestClicked): the
	-- map centred on the quest. Already open: Blizzard plays nothing then, only the map's opening sound the first time,
	-- so the quest list's select sound, as in the quest log, and a flight from the view you had. Just opened (zoomed in
	-- on you: Stitch\Open.lua): a frame later, once its first layout is done (a size change resets the view)
	local mapShownAt = 0
	WorldMapFrame:HookScript("OnShow", function() mapShownAt = GetTime() end)
	if QuestMapFrame_OpenToQuestDetails then
		hooksecurefunc("QuestMapFrame_OpenToQuestDetails", function(questID)
			lastFlight, lastFlightAt = questID, GetTime()
			if GetTime() - mapShownAt > .1 then
				if not ownOpen then Sound("IG_QUEST_LIST_SELECT") end
				FlyToQuest(questID)
				return
			end
			local mapID = WorldMapFrame:IsShown() and QuestDetailsStitchedMap(questID)
			if not mapID then return end
			C_Timer.After(0, function()
				if WorldMapFrame:IsShown() and Stitched() and WorldMapFrame:GetMapID() == mapID then
					FlyToQuestOn(mapID, questID, false)
				end
			end)
		end)
	end

	-- the other quest clicks (ns.QuestClicked), after Blizzard's own (hooksecurefunc, HookScript): a quest's "..." icon
	-- on the map (its pin: Blizzard's click focuses it or lets it go, POIButtonMixin.OnClick), the quest log list's own
	-- "..." icons (POI buttons from its pool, each hooked as GetButtonForQuest hands it out: ns.HookQuestPOI) and a
	-- quest's name in the list (Blizzard's click opens its details page). The map's quest pins take their methods from
	-- QuestPinMixin as they're made, all after this (the map is new here)
	if QuestPinMixin and QuestPinMixin.OnMouseClickAction then
		hooksecurefunc(QuestPinMixin, "OnMouseClickAction", function(pin, button)
			if pin.GetMap and pin:GetMap() ~= WorldMapFrame then return end   -- (the flight master's map has them too)
			if ns.PlainLeftClick(button) then ns.QuestClicked(pin.GetQuestID and pin:GetQuestID(), "focused") end
		end)
	end
	local contents = QuestScrollFrame and QuestScrollFrame.Contents
	if contents and contents.GetButtonForQuest and contents.FindButtonByQuestID then
		hooksecurefunc(contents, "GetButtonForQuest", function(owner, questID) ns.HookQuestPOI(owner:FindButtonByQuestID(questID)) end)
		if contents.buttonPool then for poi in contents.buttonPool:EnumerateActive() do ns.HookQuestPOI(poi) end end
	end
	if QuestMapLogTitleButton_OnClick then
		hooksecurefunc("QuestMapLogTitleButton_OnClick", function(button, mouseButton)
			if ns.PlainLeftClick(mouseButton) then ns.QuestClicked(button and button.questID, "details") end
		end)
	end
end

function ns:QUEST_TURNED_IN(questID)
	if questID and not issecretvalue(questID) then done[questID] = true end
	ns.Refresh()
end

function ns:PLAYER_LEVEL_UP() ns.Refresh() end   -- "Hide quests above / below my level"

function ns:SUPER_TRACKING_CHANGED()
	-- another quest focused, or the focus let go (Blizzard's menu, a map icon, its own on accepting one): the click's
	-- focus is over, so focusing that quest again some other way doesn't filter the map. Not the moment it's 0 while
	-- Tracker.lua's Unwatch keeps the focus through a quest moving to Ready to Turn In
	local q, mine = C_SuperTrack.GetSuperTrackedQuestID(), ns.ClickFocus()
	if mine and q and not issecretvalue(q) and q ~= mine and not (q == 0 and ns.KeepingFocus(mine)) then
		ns.SetClickFocus(nil)
	end
	if UpdateFocus() then ns.Refresh() end   -- (most focus changes aren't ours: then the pins stay as they are)
end

function ns:PLAYER_REGEN_ENABLED()
	ns.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if hot then hot:SetPassThroughButtons("RightButton") end
end

-- Without the companion data addon there is nothing to draw: say so on the map itself, every time it opens.
local notice
local function ShowNoDataNotice()
	if notice then return end
	notice = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
	notice:SetAllPoints()
	notice:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST") + 10)
	local text = notice:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	text:SetPoint("TOP", 0, -40)
	text:SetText(ns.NO_DATA)
end

function ns.InitLayer()
	if not WorldMapFrame then return end
	if not ns.DATA then ShowNoDataNotice(); return end
	if overlay then return end
	Init()
	if ns.InitPanel then ns.InitPanel() end
end

ns.MEDIA = "Interface\\AddOns\\daves_map\\Media\\"
