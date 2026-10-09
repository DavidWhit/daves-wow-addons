-- daves_castbar / Effects_Tailor.lua
-- Tailoring: a small loom, a shuttle crossing the shed at the fell and a reed beating each pick into the woven
-- cloth. One of the effect files (see Effects.lua): its own 200 top-level locals, the shared helpers from
-- ns.FXi, and its hooks registered at the end.

local _, ns = ...
local I = ns.FXi
local MEDIA, rand, PI, Smooth, Spawn = I.MEDIA, I.rand, I.PI, I.Smooth, I.Spawn
local RGB, PlaceIn, Band, Light, ContentTex = I.RGB, I.PlaceIn, I.Band, I.Light, I.ContentTex
local lerp, smooth = I.lerp, I.smooth
local tools                               -- above the bar's frame line, clipped to the bar: the loom's tools (init)
local content, cfg, W, H, clock = nil, nil, 300, 26, 0   -- the core's state, copied in by sync

---------------------------------------------------------------------------
-- Tailoring: the bar is a small loom (concept tail-a2). Ahead of the fell lies taut warp (the track, tinted to this
-- cast's cloth); behind it the woven cloth (the layer, tinted the same). At the fell a small boat shuttle crosses the
-- shed carrying the weft, and a slim reed beats each pick in: the fell darkens where it is packed, brightens for a
-- moment after each beat, and a little fluff flies. The shuttle, reed, weft and the loose weft ends at the selvedges
-- stand on `tools`, a frame clipped to the bar: the shuttle's pass and the reed reach past the bar's top and bottom
-- lines, and whatever passes them is cut off cleanly (the user: "just clip the loom as it passes the end of the bar").
-- The shed is one texture on the track, shown plain or flipped as the threads part either way.
-- Nothing turns: the shuttle moves, the reed slides, the weft is two Lines.
---------------------------------------------------------------------------
local CLOTHS = {   -- base: the cloth (the layer, the warp); weft: the thread (pirn, weft, loose ends); sheen: how much it shines
	{ base = RGB(172, 156, 124), weft = RGB(188, 172, 140), sheen = .08 },   -- linen
	{ base = RGB(120, 90, 64), weft = RGB(136, 102, 74), sheen = .05 },      -- wool
	{ base = RGB(160, 36, 48), weft = RGB(180, 52, 62), sheen = .22 },       -- silk
	{ base = RGB(112, 60, 136), weft = RGB(128, 74, 152), sheen = .14 },     -- mageweave
	{ base = RGB(72, 56, 128), weft = RGB(88, 70, 146), sheen = .12 },       -- runecloth
	{ base = RGB(146, 164, 196), weft = RGB(166, 184, 214), sheen = .25 },   -- mooncloth
}
local clothTurn = math.random(#CLOTHS) - 1
local loom                   -- the loom's tools, made once: on `tools`, and the shed on the track
local tailor                 -- this cast's state
local TAILS_MAX = 24         -- loose weft ends at most
local LOOM_PARTS = { "shuttle", "pirn", "reed" }
local SHED_REACH = .2        -- the shuttle's travel reaches this far past the bar's top and bottom (bar heights); the
                             -- clip frame cuts off whatever is past the lines
local FLUFF = { tex = "p_soft", colors = { { 1, 1, 1 } }, size = { .015, .035 }, life = { .5, 1.1 }, vx = { 8, 26 }, vy = { 6, 28 }, gravity = 8, alpha = .6 }

-- a tool sprite on the clipped tools frame (as I.ToolTexture, but on this file's frame)
local function ToolTexture(name, sub)
	local tex = Smooth(tools:CreateTexture(nil, "ARTWORK", nil, sub))
	tex:SetTexture(MEDIA .. name)
	tex:SetBlendMode("BLEND")
	tex:Hide()
	return tex
end

local function MakeLoom()
	loom = {}
	loom.shuttle = ToolTexture("p_shuttle", 3)
	loom.pirn = ToolTexture("p_pirn", 4)
	loom.reed = ToolTexture("p_reed", 5)
	loom.tails = {}
	for i = 1, TAILS_MAX do loom.tails[i] = ToolTexture("p_tail", 1) end
	loom.weft = {}
	for i = 1, 2 do   -- the weft from the fell to the shuttle, in two segments
		local line = tools:CreateLine(nil, "ARTWORK", nil, 2)
		line:SetTexture(MEDIA .. "lw_lace")
		line:Hide()
		loom.weft[i] = line
	end
	loom.shed = {}
	for i = 1, 2 do   -- the threads parting one way, and (flipped) the other
		local tex = Smooth(ns.TrackTexture(3))
		tex:SetTexture(MEDIA .. "tail_shed")
		tex:Hide()
		loom.shed[i] = tex
	end
end

local function HideTailor()
	if loom then
		for _, k in ipairs(LOOM_PARTS) do loom[k]:Hide() end
		for _, t in ipairs(loom.tails) do t:Hide() end
		for _, l in ipairs(loom.weft) do l:Hide() end
		for _, s in ipairs(loom.shed) do s:Hide() end
	end
	if content and content.loom then
		for _, tex in pairs(content.loom) do tex:Hide() end
	end
end

local function MakeTailor()
	if not loom then MakeLoom() end
	clothTurn = clothTurn % #CLOTHS + 1
	local cl = CLOTHS[clothTurn]
	ns.TintLayer(content, 1, Light(cl.base, .2))   -- the strands' lit crowns run lighter than the cloth's colour, as the concept
	ns.TintTrack(cl.base, { Light(cl.base, .18) })
	loom.pirn:SetVertexColor(Light(cl.weft, .2))
	for _, t in ipairs(loom.tails) do t:SetVertexColor(Light(cl.weft, .15)); t:SetDesaturation(0) end
	for _, l in ipairs(loom.weft) do l:SetVertexColor(cl.weft[1], cl.weft[2], cl.weft[3]); l:SetDesaturation(0) end
	for _, s in ipairs(loom.shed) do s:SetVertexColor(cl.base[1], cl.base[2], cl.base[3]); s:SetDesaturation(0) end
	for _, k in ipairs(LOOM_PARTS) do loom[k]:SetDesaturation(0) end
	FLUFF.colors[1] = { Light(cl.weft, .55) }
	tailor = { cl = cl, period = rand(.38, .5), pickT = 0, fresh = 0, sheenPh = math.random(), tails = {}, grey = 0 }
	-- loose weft ends poking out of the selvedges, anchored once: the sprite's curl is .15 bar heights long with
	-- .04 of it inside the bar, so each is scaled to its length and set with that much over the edge
	local x = H * .6
	while x < W and #tailor.tails < TAILS_MAX do
		local q = { x = x, top = math.random() < .5, len = rand(.12, .24), curl = math.random() < .5 }
		tailor.tails[#tailor.tails + 1] = q
		local t, k = loom.tails[#tailor.tails], q.len / .15
		t:SetTexCoord(q.curl and 1 or 0, q.curl and 0 or 1, q.top and 0 or 1, q.top and 1 or 0)
		t:SetSize(H * .2 * k, H * .2 * k)
		t:ClearAllPoints()
		if q.top then t:SetPoint("BOTTOM", tools, "BOTTOMLEFT", x, H - H * .04 * k)
		else t:SetPoint("TOP", tools, "BOTTOMLEFT", x, H * .04 * k) end
		x = x + H * rand(1.2, 2.6)
	end
	local c = content.loom
	c.shade:ClearAllPoints(); c.shade:SetPoint("TOPLEFT", content, "TOPLEFT"); c.shade:SetSize(math.min(W, H * 4), H); c.shade:Show()
	c.band:ClearAllPoints(); c.band:SetPoint("LEFT", content, "LEFT", 0, H * .12); c.band:SetSize(W, H * .25)
	c.band:SetAlpha(cl.sheen * .5); c.band:Show()
	c.sheen:SetAlpha(cl.sheen); c.sheen:Show()
	c.fresh:SetTexCoord(0, 1, 0, 1); c.fresh:SetDesaturation(0)
end

local function UpdateTailor(dt, fillW, casting)
	local c = content.loom
	-- one pick of the weave: the shuttle crosses the shed, the reed packs the weft in, the shed changes
	local P = tailor.period
	if casting then
		local before = (tailor.pickT % P) / P
		tailor.pickT = tailor.pickT + dt
		local after = (tailor.pickT % P) / P
		if before < .725 and after >= .725 and fillW > H * .3 then   -- the beat: fluff flies
			tailor.fresh = 1
			for _ = 1, 5 do Spawn(FLUFF, fillW + rand(0, .1) * H, H * rand(.1, .9)) end
		end
	end
	tailor.fresh = math.max(0, tailor.fresh - dt * 3)
	local u, k = (tailor.pickT % P) / P, math.floor(tailor.pickT / P)
	local down = k % 2 == 0
	local yTop, yBot = H * (1 + SHED_REACH), -H * SHED_REACH
	local f = smooth(u / .55)
	local sy = tailor.pickT <= 0 and yTop or (down and lerp(yTop, yBot, f) or lerp(yBot, yTop, f))
	local bump = (u > .6 and u < .85) and math.sin(PI * (u - .6) / .25) or 0
	local sign = down and 1 or -1
	local shed = u < .85 and sign or lerp(sign, -sign, smooth((u - .85) / .15))
	local sx, bx = fillW + H * .18, fillW + H * .4 - bump * H * .3

	-- inside the fill: the freshly beaten fell (packed tight, a hair darker, a moment brighter after each beat), a
	-- slow sheen sliding along the cloth, light along its crown, shade behind the spell name
	PlaceIn(c.fell, content, fillW - H * .02, H * .5, H * .04, H)
	c.fell:Show()
	Band(c.fresh, fillW - H * .5, fillW)
	c.fresh:SetAlpha(.22 * tailor.fresh)
	local cx = (clock * H * 1.1 + tailor.sheenPh * W) % (W + H * 6) - H * 3
	PlaceIn(c.sheen, content, cx, H * .5, H * 3.2, H)
	-- the shed, on the track just past the fell: the threads part one way, then the other
	local sw = math.min(H, W - fillW)
	for i, s in ipairs(loom.shed) do
		local a = i == 1 and math.max(0, shed) or math.max(0, -shed)
		s:SetShown(sw > .5 and a > .01 and fillW > .5)
		if sw > .5 and a > .01 then
			s:ClearAllPoints()
			s:SetPoint("BOTTOMLEFT", tools, "BOTTOMLEFT", fillW, 0)
			s:SetSize(sw, H)
			s:SetTexCoord(0, sw / H, i == 1 and 0 or 1, i == 1 and 1 or 0)
			s:SetAlpha(a)
		end
	end

	-- the tools, fading out when the cast ends
	if not casting then tailor.endAt = tailor.endAt or clock end
	local ta = tailor.endAt and math.max(0, 1 - (clock - tailor.endAt) * 2.2) or 1
	local on = fillW > .5 and ta > 0
	for _, kk in ipairs(LOOM_PARTS) do loom[kk]:SetShown(on) end
	for _, l in ipairs(loom.weft) do l:SetShown(on) end
	for i, q in ipairs(tailor.tails) do loom.tails[i]:SetShown(q.x < fillW - H * .15) end
	if not on then return end
	-- the weft from where this pick entered the shed to the shuttle carrying it
	local from = down and H or 0
	local syc = math.max(0, math.min(H, sy))
	local lw = math.max(1, H * .034)
	loom.weft[1]:SetThickness(lw); loom.weft[2]:SetThickness(lw)
	loom.weft[1]:SetStartPoint("BOTTOMLEFT", tools, fillW, from); loom.weft[1]:SetEndPoint("BOTTOMLEFT", tools, fillW + H * .1, syc)
	loom.weft[2]:SetStartPoint("BOTTOMLEFT", tools, fillW + H * .1, syc); loom.weft[2]:SetEndPoint("BOTTOMLEFT", tools, sx, sy)
	for _, l in ipairs(loom.weft) do l:SetAlpha(ta) end
	-- the shuttle (its pirn of thread in the cavity; the sprites are .4 x .8 and .2 x .8 bar heights, the shuttle .6 long
	-- inside) and the reed (.2 x 1.6: from .1 above the bar to .1 below it, the bar's top .3 down the sprite); the
	-- clip frame cuts off whatever passes the bar's lines
	PlaceIn(loom.shuttle, tools, sx, sy, H * .4, H * .8)
	PlaceIn(loom.pirn, tools, sx, sy, H * .2, H * .8)
	loom.reed:ClearAllPoints()
	loom.reed:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", bx - H * .1, H * 1.3)
	loom.reed:SetSize(H * .2, H * 1.6)
	for _, kk in ipairs(LOOM_PARTS) do loom[kk]:SetAlpha(ta) end
end

---------------------------------------------------------------------------
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "tailor",
	init = function()
		-- the loom's tools on a frame clipped to the bar (the same rect and level as the shared tools frame): the
		-- shuttle's pass and the reed reach past the bar's lines, and whatever passes them is cut off cleanly
		tools = CreateFrame("Frame", nil, I.tools)
		tools:SetAllPoints(I.tools)
		tools:SetFrameLevel(I.tools:GetFrameLevel())
		tools:SetClipsChildren(true)
	end,
	sync = function(c, cf, w, h, t) content, cfg, W, H, clock = c, cf, w, h, t end,
	create = function(c)
		local ccfg = c.cfg
		if ccfg.tailor then   -- inside the cloth: the beaten fell, its fresh brightening, the sheen, the crown's light, shade behind the name
			local t = {}
			t.fell = Smooth(c:CreateTexture(nil, "ARTWORK", nil, 2)); t.fell:SetColorTexture(0, 0, 0, .25); t.fell:Hide()
			t.fresh = ContentTex(c, "edge_h", 3, "ADD"); t.fresh:SetVertexColor(1, .96, .88)
			t.sheen = ContentTex(c, "sweep", 4, "ADD")
			t.band = ContentTex(c, "alch_band", 4, "ADD")
			t.shade = ContentTex(c, "edge_h", 5); t.shade:SetTexCoord(1, 0, 0, 1); t.shade:SetVertexColor(0, 0, 0, .28)
			c.loom = t
		end
	end,
	begin = function() if cfg.tailor then MakeTailor() end end,
	update = function(dt, fillW, casting, _, t)
		clock = t
		if tailor then UpdateTailor(dt, fillW, casting) end
	end,
	interrupted = function(k)
		if tailor and loom then   -- the cloth and the warp grey with the bar; the tools, weft and shed here
			tailor.grey = k
			for _, key in ipairs(LOOM_PARTS) do loom[key]:SetDesaturation(k) end
			for _, t in ipairs(loom.tails) do t:SetDesaturation(k) end
			for _, l in ipairs(loom.weft) do l:SetDesaturation(k) end
			for _, s in ipairs(loom.shed) do s:SetDesaturation(k) end
			if content and content.loom then content.loom.fresh:SetDesaturation(k) end
		end
	end,
	clear = function()
		HideTailor()
		tailor = nil
	end,
})
