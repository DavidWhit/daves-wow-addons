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

-- the filters; a search shows its matches whatever their category
local function Passes(i)
	local db = ns.db
	if searchSet then
		if not searchSet[i] then return false end
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
		if db.hideHighLevel and lvl > me then return false end
		if db.hideLowLevel and lvl ~= 0 and lvl <= me - db.lowLevelGap then return false end   -- 0: level unknown, kept
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
	if ns.db.enabled and D and curMap and ns.Calibrate() then
		local c = ns.PinsOnMap(curMap)
		for _, i in ipairs(c.idx) do
			if Passes(i) then
				shown[#shown + 1] = i
				nIcons = nIcons + 1
				local t = Icon(nIcons)
				local q = D.qid[i]
				PaintIcon(t, i, (q ~= 0 and IsDone(q)) and .35 or 1)   -- completed quests dimmed
				Place(t, c.x[i], c.y[i], PinSize(i))
				t:Show()
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
	local c = ns.PinsOnMap(curMap)
	for n, i in ipairs(shown) do icons[n]:SetSize(PinSize(i), PinSize(i)) end
	if c then DrawLinks() end
end

---------------------------------------------------------------------------
-- Hover and click
---------------------------------------------------------------------------
local function PinAt(cx, cy)
	local c = ns.PinsOnMap(curMap)
	local px, py = cx * curW, cy * curH
	local best, bd
	for n = #shown, 1, -1 do   -- the last drawn is on top
		local i = shown[n]
		local r = PinSize(i) * 0.55
		local dx, dy = c.x[i] * curW - px, c.y[i] * curH - py
		local d = dx * dx + dy * dy
		if d <= r * r and (not bd or d < bd) then best, bd = i, d end
	end
	return best
end

local function SetHover(i)
	if i == hoverPin then return end
	hoverPin = i
	if i then
		local x, y = Pos(i)
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
	ns.Print(("waypoint: %s (%s %.1f, %.1f)."):format(D.title[i], ns.ZoneName(i) or "?", x * 100, y * 100))
end

-- Opens the map a pin is on, when the world map shows another (a click in the panel). SetMapID from addon code
-- taints the map's refresh, and its pins' SetPassThroughButtons is blocked in combat (see the top of this file), so
-- not in combat. True when it switched.
function ns.ShowPinMap(i)
	local zone = P.zone[i]
	if not zone or zone == curMap or not WorldMapFrame:IsShown() then return false end
	if InCombatLockdown() then
		ns.Print("can't change the map in combat.")
		return false
	end
	WorldMapFrame:SetMapID(zone)
	return true
end

-- lock a pin's chain on the map (a search result, or a click); nil clears it
function ns.Focus(i)
	lockedPin = (i ~= lockedPin) and i or nil
	chain = lockedPin and BuildChain(lockedPin) or nil
	DrawLinks()
	if ns.OnLayerChanged then ns.OnLayerChanged() end
end
function ns.FocusedPin() return lockedPin end

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
	end
	local scale, zoom = WorldMapFrame:GetCanvasScale(), WorldMapFrame:GetCanvasZoomPercent()
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
	if not (WorldMapFrame.ScrollContainer:IsMouseMotionFocus() or hot:IsMouseMotionFocus()) then
		if hoverPin then SetHover(nil) end
		lastCX = nil
		return
	end
	local cx, cy = WorldMapFrame:GetNormalizedCursorPosition()
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
	local canvas = WorldMapFrame:GetCanvas()
	overlay = CreateFrame("Frame", nil, canvas)
	overlay:SetAllPoints(canvas)
	-- Blizzard's map layers are pins with absolute frame levels from 2000 up (MapCanvas_PinFrameLevelsManager.lua): the
	-- explored-area art, fog of war and zone highlight are among them. Just above the highlight puts us over all the
	-- map's art and under its markers (dig sites, dungeon entrances, flight points, POIs). GetValidFrameLevel only reads.
	local levels = WorldMapFrame:GetPinFrameLevelsManager()
	overlay:SetFrameLevel(levels:GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT") + 1)
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
end

function ns:QUEST_TURNED_IN(questID)
	if questID and not issecretvalue(questID) then done[questID] = true end
	ns.Refresh()
end

function ns:PLAYER_LEVEL_UP() ns.Refresh() end   -- "Hide quests above / below my level"

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
