-- daves_castbar / Effects.lua
-- Everything that moves on its own: particles, and each element's live pieces.
--   frost   six cut layers placed at random each cast (a new ice bar every time), one cut
--           traced up to the fill edge, and a glint of light sweeping across now and then
--   nature  vines that grow with the cast, twisting around each other, with leaves and thorns
--   arcane  rune circles at random heights and sizes, each turning its own way; glyphs flare up
--   holy    four-point stars twinkling in and out
-- Positions are in bar pixels from the bottom-left corner, y up. Effects drawn on the fx frame
-- can spill past the bar; those on an element's content frame are clipped by the fill and
-- masked in the borderless style.

local _, ns = ...

local MEDIA = ns.MEDIA
local rand = ns.rand
local PI = math.pi
local FX = {}
ns.FX = FX

local fx                     -- the unclipped frame over the bar
local W, H = 300, 26
local content, cfg           -- the element being shown
local clock = 0

local function easeOutBack(t) local c = 1.7; t = t - 1; return 1 + t * t * ((c + 1) * t + c) end
local function pick(list) return list[math.random(#list)] end

-- Texture and line pools, so nothing is created during play after the first few casts.
local function Pool(make)
	local pool = { free = {}, used = {} }
	function pool:Get()
		local obj = table.remove(self.free) or make()
		self.used[obj] = true
		obj:Show()
		return obj
	end
	function pool:Release(obj)
		if not self.used[obj] then return end
		self.used[obj] = nil
		obj:Hide()
		self.free[#self.free + 1] = obj
	end
	function pool:ReleaseAll()
		for obj in pairs(self.used) do self:Release(obj) end
	end
	return pool
end

---------------------------------------------------------------------------
-- Particles
---------------------------------------------------------------------------
local particles = {}
local particlePool
local emitAcc = {}

local function Spawn(e, x, y)
	local tex = particlePool:Get()
	tex:SetTexture(MEDIA .. e.tex)
	tex:SetBlendMode(e.add and "ADD" or "BLEND")
	local c = pick(e.colors)
	tex:SetVertexColor(c[1], c[2], c[3])
	local k = H / 28
	local p = {
		tex = tex, e = e, x = x, y = y, age = 0, life = rand(e.life[1], e.life[2]),
		vx = rand(e.vx and e.vx[1] or -5, e.vx and e.vx[2] or 5) * k, vy = rand(e.vy and e.vy[1] or -5, e.vy and e.vy[2] or 5) * k,
		size = rand(e.size[1], e.size[2]) * H, rot = rand(0, 6.283), spin = e.spin and rand(e.spin[1], e.spin[2]) or 0,
		tw = e.twinkle and rand(8, 16) or 0, sw = rand(0, 6.283),
	}
	tex:SetSize(p.size, p.size)
	particles[#particles + 1] = p
	return p
end

local function UpdateParticles(dt)
	for i = #particles, 1, -1 do
		local p = particles[i]
		p.age = p.age + dt
		if p.age >= p.life then
			particlePool:Release(p.tex)
			table.remove(particles, i)
		else
			if p.e.swirl then p.vx = p.vx + math.sin(p.age * 6 + p.sw) * p.e.swirl * dt end
			p.x, p.y, p.rot = p.x + p.vx * dt, p.y + p.vy * dt, p.rot + p.spin * dt
			local t = p.age / p.life
			local a = math.min(1, t / .15) * math.min(1, (1 - t) / .4) * (p.e.alpha or 1)
			if p.tw > 0 then a = a * (.5 + .5 * math.sin(p.age * p.tw)) end
			p.tex:SetAlpha(math.max(0, a))
			p.tex:SetRotation(p.rot)
			p.tex:ClearAllPoints()
			p.tex:SetPoint("CENTER", fx, "BOTTOMLEFT", p.x, p.y)
		end
	end
end

local function Emit(dt, fillW)
	if fillW <= 2 then return end
	for i, e in ipairs(cfg.emit) do
		emitAcc[i] = (emitAcc[i] or 0) + e.rate * dt
		while emitAcc[i] >= 1 do
			emitAcc[i] = emitAcc[i] - 1
			local x, y
			if e.from == "edge" then x, y = fillW + rand(-4, 1), rand(0, H)
			elseif e.from == "bottom" then x, y = rand(0, fillW), H * rand(0, .65)
			else x, y = rand(0, fillW), rand(0, H) end
			Spawn(e, x, y)
		end
	end
end

---------------------------------------------------------------------------
-- Nature: vines
---------------------------------------------------------------------------
-- Draw order (ARTWORK sublevels on fx): back outline 0, back bark 1, back leaves 2,
-- front outline 3, front bark 4, front leaves and thorns 5.
local vines, linePool, spritePool
local LEAF_TINTS = { { .35, .65, .24 }, { .24, .53, .2 }, { .49, .69, .27 }, { .22, .45, .24 }, { .59, .73, .31 }, { .31, .59, .18 } }
local FALL_TINTS = { { .43, .65, .24 }, { .59, .67, .27 }, { .67, .55, .24 } }
local STEP = 3

local function MakeVines()
	local n = math.random() < .5 and 2 or 3
	local base = rand(0, 6.283)
	vines = {}
	for i = 1, n do
		vines[i] = {
			ph = base + (i - 1) * 6.283 / n + rand(-.4, .4), freq = rand(.28, .45), fw = ns.Wobble(2.2), yw = ns.Wobble(3),
			amp = rand(.24, .36), w = rand(.075, .105), moss = math.random() < .4, x = 0, pts = {}, segs = {}, growing = {},
			nextThorn = rand(.2, .6) * H, thornSide = 1,
		}
	end
end

local function VineLine(front, outline)
	local line = linePool:Get()
	line:SetDrawLayer("ARTWORK", (front and 3 or 0) + (outline and 0 or 1))
	if outline then
		line:SetColorTexture(.086, .055, .024, .85)
		line:SetVertexColor(1, 1, 1, 1)   -- a recycled line may still carry a bark tint
	else
		line:SetTexture(MEDIA .. "vine")
	end
	return line
end

local function Sprite(name, sub, blend)
	local tex = spritePool:Get()
	tex:SetTexture(MEDIA .. name)
	tex:SetDrawLayer("ARTWORK", sub)
	tex:SetBlendMode(blend or "BLEND")
	tex:SetTexCoord(0, 1, 0, 1)
	tex:SetRotation(0)
	tex:SetAlpha(1)
	return tex
end

local function PlaceSprite(tex, cx, cy, size, rot)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", fx, "BOTTOMLEFT", cx, cy)
	tex:SetSize(math.max(.1, size), math.max(.1, size))
	tex:SetRotation(rot)
end

local function GrowVines(fillW)
	for _, v in ipairs(vines) do
		while v.x < fillW do
			v.x = v.x + STEP
			local xn = v.x / H
			v.ph = v.ph + (STEP / H) * 6.283 * v.freq * (1 + .45 * v.fw(xn * .35))   -- the twist rate drifts randomly
			local y = H / 2 + H * v.amp * math.sin(v.ph) + H * .07 * v.yw(xn * .5)
			local d = math.cos(v.ph)                      -- > 0: in front of the other vines
			local prev = v.pts[#v.pts]
			v.pts[#v.pts + 1] = { x = v.x, y = y, d = d }
			if prev then
				local front = d >= 0
				local lit = front and (.72 + .28 * d) or (.42 + .18 * (1 + d))
				local seg = { x = v.x, d = d, front = front, outline = VineLine(front, true), bark = VineLine(front, false) }
				for _, line in ipairs({ seg.outline, seg.bark }) do
					line:SetStartPoint("BOTTOMLEFT", fx, prev.x, prev.y)
					line:SetEndPoint("BOTTOMLEFT", fx, v.x, y)
				end
				if v.moss then seg.bark:SetVertexColor(.62 * lit, .82 * lit, .5 * lit) else seg.bark:SetVertexColor(lit, lit, lit) end
				v.segs[#v.segs + 1] = seg

				local tang = math.atan2(y - prev.y, STEP)
				if math.random() < .10 then             -- a leaf sprouts
					local side = math.random() < .5 and -1 or 1
					local leaf = { x = v.x, y = y, ang = tang + side * rand(.8, 1.8), size = H * rand(.34, .55), born = clock, kind = "leaf",
						tex = Sprite("p_leaf", front and 5 or 2) }
					local c, shade = pick(LEAF_TINTS), front and 1 or .6
					leaf.tex:SetVertexColor(c[1] * shade, c[2] * shade, c[3] * shade)
					v.growing[#v.growing + 1] = leaf
				end
				if v.x >= v.nextThorn then              -- thorns: uneven spacing, alternating sides, raked toward the tip
					v.nextThorn = v.x + H * rand(.2, .45)
					v.thornSide = -v.thornSide
					local thorn = { x = v.x, y = y, ang = tang + v.thornSide * (PI / 2 - rand(.25, .6)), size = H * v.w * rand(2.8, 3.6),
						born = clock, kind = "thorn", off = H * v.w * .3, tex = Sprite("p_thorn", front and 5 or 2) }
					local shade = front and 1 or .6
					thorn.tex:SetVertexColor(shade, shade, shade)
					if v.thornSide < 0 then thorn.tex:SetTexCoord(1, 0, 0, 1) end
					v.growing[#v.growing + 1] = thorn
				end
				if math.random() < .008 then              -- a leaf lets go and falls
					Spawn({ tex = "p_leaf", colors = FALL_TINTS, size = { .3, .42 }, life = { 1.2, 2 }, vx = { -14, -4 }, vy = { -26, -10 }, spin = { -3, 3 } }, v.x, y)
				end
			end
		end
	end
end

local function UpdateVines(fillW)
	local zone = H * .8
	for _, v in ipairs(vines) do
		-- taper toward the growing tip (only the last few segments change)
		for i = math.max(1, #v.segs - math.ceil(zone / STEP) - 2), #v.segs do
			local seg = v.segs[i]
			local taper = math.max(.2, math.min(1, (fillW - seg.x) / zone))
			local w = H * v.w * (seg.front and .85 + .3 * seg.d or .7 + .2 * seg.d) * taper
			seg.bark:SetThickness(math.max(.6, w))
			seg.outline:SetThickness(math.max(1, w + 1.4))
			local show = seg.x <= fillW + .5
			seg.bark:SetShown(show); seg.outline:SetShown(show)
		end
		-- leaves and thorns pop out over 0.45 s
		for i = #v.growing, 1, -1 do
			local s = v.growing[i]
			local g = math.min(1, (clock - s.born) / .45)
			local size = easeOutBack(g) * s.size
			local dx, dy = math.cos(s.ang), math.sin(s.ang)
			if s.kind == "leaf" then
				PlaceSprite(s.tex, s.x + dx * size * .5, s.y + dy * size * .5, size, s.ang + PI / 4)
			else
				PlaceSprite(s.tex, s.x + dx * (size / 2 + s.off), s.y + dy * (size / 2 + s.off), size, s.ang - PI / 2)
			end
			if g >= 1 then table.remove(v.growing, i) end
		end
	end
end

---------------------------------------------------------------------------
-- Frost: cut layers, traced cuts, light sweep
---------------------------------------------------------------------------
local N_CUTS = 6

local function FrostCutCoords(cp)
	-- the texture coordinates that place cut layer c as this cast wants it
	local tw = 512 * (H / 64) * cp.stretch
	local span = W / tw
	local l, r = cp.u, cp.u + span
	if cp.flipH then l, r = r, l end
	local t, b = 0, 1
	if cp.flipV then t, b = 1, 0 end
	return l, r, t, b, tw, span
end

-- The cut as placed this cast, as bar-pixel segments from left to right.
local function CutSegments(cp)
	local cut = ns.FROST_CUTS[cp.c]
	local _, _, _, _, tw, span = FrostCutCoords(cp)
	local k = H / 64
	local segs = {}
	local function X(tx, n)
		if cp.flipH then return (cp.u + span - tx / 512 - n) * tw end
		return (tx / 512 + n - cp.u) * tw
	end
	local function Y(ty) return cp.flipV and ty * k or H - ty * k end
	for n = math.floor(cp.u) - 2, math.floor(cp.u + span) + 2 do
		for i = 2, #cut do
			local ax, bx = X(cut[i - 1][1], n), X(cut[i][1], n)
			local ay, by = Y(cut[i - 1][2]), Y(cut[i][2])
			if ax > bx then ax, bx, ay, by = bx, ax, by, ay end
			if bx > 0 and ax < W then segs[#segs + 1] = { ax, ay, bx, by } end
		end
	end
	table.sort(segs, function(p, q) return p[1] < q[1] end)
	return segs
end

local function BuildTraces()
	content.traceLines:ReleaseAll()
	content.traces = {}
	for _, ci in ipairs(content.traceCuts) do
		local trace = { pieces = {} }
		for _, s in ipairs(CutSegments(content.cutParams[ci])) do
			local ax, ay, bx, by = s[1], s[2], s[3], s[4]
			local steps = math.max(1, math.ceil(math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) / 8))
			for j = 0, steps - 1 do
				local t1, t2 = j / steps, (j + 1) / steps
				local piece = { x1 = ax + (bx - ax) * t1, y1 = ay + (by - ay) * t1, x2 = ax + (bx - ax) * t2, y2 = ay + (by - ay) * t2 }
				piece.glow = content.traceLines:Get(); piece.glow:SetDrawLayer("ARTWORK", 4)
				piece.core = content.traceLines:Get(); piece.core:SetDrawLayer("ARTWORK", 5)
				piece.core:SetThickness(math.max(.5, H * .018))
				for _, line in ipairs({ piece.glow, piece.core }) do
					line:SetStartPoint("BOTTOMLEFT", content, piece.x1, piece.y1)
					line:SetEndPoint("BOTTOMLEFT", content, piece.x2, piece.y2)
				end
				trace.pieces[#trace.pieces + 1] = piece
			end
		end
		content.traces[#content.traces + 1] = trace
	end
end

local function LayoutFrost()
	for i, cp in ipairs(content.cutParams) do
		local l, r, t, b = FrostCutCoords(cp)
		content.cutLo[i]:SetTexCoord(l, r, t, b)
		content.cutHi[i]:SetTexCoord(l, r, t, b)
		content.cutLo[i]:SetTexture(MEDIA .. "frost_cut" .. (cp.c - 1) .. "_lo", "REPEAT", "REPEAT")
		content.cutHi[i]:SetTexture(MEDIA .. "frost_cut" .. (cp.c - 1) .. "_hi", "REPEAT", "REPEAT")
	end
	BuildTraces()
	content.sweepTex:SetSize(H * 1.0, H * 1.8)
end

local function BeginFrost()
	content.cutParams = {}
	for i = 1, N_CUTS do
		-- the four edge-to-edge cuts and the girdle (5) once each, then one more edge-to-edge
		content.cutParams[i] = { c = i <= 5 and i or math.random(4), u = rand(0, 1), stretch = rand(.7, 1.5),
			flipH = math.random() < .5, flipV = math.random() < .5, w = rand(.55, 1), wob = ns.Wobble(1.3) }
	end
	-- one of this cast's edge-to-edge cuts gets traced (not the girdle, 5)
	local candidates = { 1, 2, 3, 4, 6 }
	content.traceCuts = { candidates[math.random(#candidates)] }
	content.sweepT, content.sweep = rand(.4, 1.5), nil
	LayoutFrost()
end

local function UpdateFrost(dt, fillW)
	for i, cp in ipairs(content.cutParams) do
		local a = cp.w * (.7 + .3 * cp.wob(clock))   -- the weights drift: the light seems to move
		content.cutLo[i]:SetAlpha(a); content.cutHi[i]:SetAlpha(a)
	end
	-- traces: bright where the head is, settling into a soft glow behind it. Only the piece crossing
	-- the fill edge moves every frame; the glow falloff behind it is refreshed about 15 times a second,
	-- and pieces are shown or hidden only when that changes.
	local fade = H * 1.6
	local tip = 0
	content.traceTick = (content.traceTick or 0) + dt
	local refresh = content.traceTick >= 1 / 15
	if refresh then content.traceTick = 0 end
	for _, trace in ipairs(content.traces) do
		for _, piece in ipairs(trace.pieces) do
			local state = piece.x1 >= fillW and "hidden" or (piece.x2 > fillW and "head" or "full")
			if state ~= piece.state then
				piece.glow:SetShown(state ~= "hidden"); piece.core:SetShown(state ~= "hidden")
				if state == "full" then   -- it just finished: run it to its own end point
					piece.glow:SetEndPoint("BOTTOMLEFT", content, piece.x2, piece.y2)
					piece.core:SetEndPoint("BOTTOMLEFT", content, piece.x2, piece.y2)
				end
			end
			if state == "head" then
				local t = (fillW - piece.x1) / (piece.x2 - piece.x1)
				local x2, y2 = fillW, piece.y1 + (piece.y2 - piece.y1) * t
				piece.glow:SetEndPoint("BOTTOMLEFT", content, x2, y2)
				piece.core:SetEndPoint("BOTTOMLEFT", content, x2, y2)
				tip = tip + 1
				local star = content.tips[tip]
				if star then star:Show(); star:ClearAllPoints(); star:SetPoint("CENTER", content, "BOTTOMLEFT", x2, y2) end
			end
			if state ~= "hidden" and (refresh or state ~= piece.state) then
				local g = math.exp(-math.max(0, fillW - math.min(fillW, piece.x2)) / fade)
				piece.glow:SetThickness(math.max(1.2, H * (.04 + .04 * g)))
				piece.glow:SetVertexColor(.59, .82, 1, .05 + .25 * g)
				piece.core:SetVertexColor(.92, .97, 1, .22 + .7 * g)
			end
			piece.state = state
		end
	end
	for i = tip + 1, #content.tips do content.tips[i]:Hide() end

	-- light sweeping across the ice at random moments
	content.sweepT = content.sweepT - dt
	if not content.sweep and content.sweepT <= 0 then content.sweep = { t = 0, dur = rand(.45, .8) } end
	local sw = content.sweep
	if sw then
		sw.t = sw.t + dt
		local p = sw.t / sw.dur
		if p >= 1 then
			content.sweep, content.sweepT = nil, rand(1.2, 3.5)
			content.sweepTex:Hide()
		else
			content.sweepTex:Show()
			content.sweepTex:ClearAllPoints()
			content.sweepTex:SetPoint("CENTER", content, "LEFT", -H + (fillW + 2 * H) * p, 0)
			content.sweepTex:SetAlpha(math.sin(p * PI) * .55)
		end
	end
end

---------------------------------------------------------------------------
-- Arcane: rune circles and glyphs
---------------------------------------------------------------------------
local CIRCLE_TINTS = { { 1, .69, .92 }, { .69, .8, 1 }, { .84, .69, 1 } }
local GLYPH_TINTS = { { 1, .59, .9 }, { .55, .78, 1 }, { 1, .84, .55 } }

local function ArcaneTexture(name, sub)
	local tex = content.arcanePool:Get()
	tex:SetTexture(MEDIA .. name)
	tex:SetBlendMode("ADD")
	tex:SetDrawLayer("ARTWORK", sub)
	return tex
end

local function UpdateArcane(dt, fillW, casting)
	-- circles appear as the bar fills, at random heights and sizes
	while casting and fillW > content.circleNext do
		local c = { x = content.circleNext, y = H * rand(.1, .9), s = H * rand(1.0, 2.3), rot = rand(0, 6.283),
			spin = rand(.12, .45) * (math.random() < .5 and -1 or 1), born = clock, ph = rand(0, 6.283), tex = ArcaneTexture("p_runecircles", 4) }
		local i = math.random(3) - 1
		c.tex:SetTexCoord(i * .25, (i + 1) * .25, 0, 1)
		local tint = pick(CIRCLE_TINTS)
		c.tex:SetVertexColor(tint[1], tint[2], tint[3])
		c.tex:SetSize(c.s, c.s)
		c.tex:ClearAllPoints(); c.tex:SetPoint("CENTER", content, "BOTTOMLEFT", c.x, c.y)
		content.circles[#content.circles + 1] = c
		content.circleNext = content.circleNext + H * rand(1.3, 3.0)
	end
	for _, c in ipairs(content.circles) do
		c.rot = c.rot + c.spin * dt
		c.tex:SetRotation(c.rot)
		c.tex:SetAlpha(math.min(1, (clock - c.born) / .5) * (.75 + .2 * math.sin(clock * 1.3 + c.ph)))
	end
	-- single glyphs flare up and fade
	content.glyphT = content.glyphT - dt
	if casting and content.glyphT <= 0 and fillW > H then
		content.glyphT = rand(.25, .6)
		local q = { x = rand(H * .3, fillW - H * .2), y = H / 2 + rand(-.12, .12) * H, s = H * rand(.6, .95), age = 0, life = rand(.9, 1.7),
			tex = ArcaneTexture("p_glyphs", 5) }
		local i = math.random(16) - 1
		local col, row = i % 8, math.floor(i / 8)
		q.tex:SetTexCoord(col / 8, (col + 1) / 8, row / 2, (row + 1) / 2)
		q.tex:SetRotation(rand(-.25, .25))
		local tint = pick(GLYPH_TINTS)
		q.tex:SetVertexColor(tint[1], tint[2], tint[3])
		content.glyphs[#content.glyphs + 1] = q
	end
	for i = #content.glyphs, 1, -1 do
		local q = content.glyphs[i]
		q.age = q.age + dt
		if q.age >= q.life or q.x > fillW then
			content.arcanePool:Release(q.tex)
			table.remove(content.glyphs, i)
		else
			local t = q.age / q.life
			local s = q.s * (.75 + .25 * easeOutBack(math.min(1, t * 2.5)))
			q.tex:SetAlpha(math.sin(PI * t) ^ 1.5)
			q.tex:SetSize(s, s)
			q.tex:ClearAllPoints(); q.tex:SetPoint("CENTER", content, "BOTTOMLEFT", q.x, q.y)
		end
	end
end

---------------------------------------------------------------------------
-- Holy: twinkling stars (on the fx frame, so they can sit past the edges)
---------------------------------------------------------------------------
local twinkles, twinkleAcc = {}, 0
local TWINKLE_TINTS = { { 1, .96, .84 }, { 1, .88, .59 }, { 1, 1, 1 } }

local function UpdateTwinkles(dt, fillW, casting)
	twinkleAcc = twinkleAcc + dt * 9
	while casting and twinkleAcc >= 1 and fillW > 4 do
		twinkleAcc = twinkleAcc - 1
		local big = math.random() < .15
		local q = { x = rand(0, fillW), y = rand(-.25, 1.25) * H, s = H * (big and rand(.9, 1.4) or rand(.35, .7)), age = 0,
			life = rand(.4, 1.1), rot = rand(-.3, .3), tex = Sprite("p_twinkle", 6, "ADD") }
		local tint = pick(TWINKLE_TINTS)
		q.tex:SetVertexColor(tint[1], tint[2], tint[3])
		twinkles[#twinkles + 1] = q
	end
	if not casting then twinkleAcc = 0 end
	for i = #twinkles, 1, -1 do
		local q = twinkles[i]
		q.age = q.age + dt
		if q.age >= q.life then
			spritePool:Release(q.tex)
			table.remove(twinkles, i)
		else
			local t = q.age / q.life
			q.tex:SetAlpha(math.sin(PI * t) ^ 2)
			PlaceSprite(q.tex, q.x, q.y, q.s * (.6 + .4 * math.sin(PI * t)), q.rot + t * .4)
		end
	end
end

---------------------------------------------------------------------------
-- Hooks called by Bar.lua
---------------------------------------------------------------------------
function FX:Init(frame)
	fx = frame
	particlePool = Pool(function() return fx:CreateTexture(nil, "ARTWORK", nil, 7) end)
	linePool = Pool(function() return fx:CreateLine(nil, "ARTWORK") end)
	spritePool = Pool(function() return fx:CreateTexture(nil, "ARTWORK") end)
end

-- Pieces that live inside an element's content frame (clipped by the fill, masked when borderless).
function FX:CreateContent(c)
	local ccfg = c.cfg
	if ccfg.frostCuts then
		c.cutLo, c.cutHi = {}, {}
		for i = 1, N_CUTS do
			c.cutLo[i] = ns.Maskable(c, c:CreateTexture(nil, "ARTWORK", nil, 1))
			c.cutLo[i]:SetAllPoints(c)
			c.cutHi[i] = ns.Maskable(c, c:CreateTexture(nil, "ARTWORK", nil, 2))
			c.cutHi[i]:SetAllPoints(c)
			c.cutHi[i]:SetBlendMode("ADD")
		end
		c.traceLines = Pool(function()
			local line = c:CreateLine(nil, "ARTWORK", nil, 5)
			line:SetColorTexture(1, 1, 1, 1)
			return line
		end)
		c.tips = {}
		for i = 1, 4 do
			local star = c:CreateTexture(nil, "OVERLAY", nil, 6)
			star:SetTexture(MEDIA .. "p_star"); star:SetBlendMode("ADD")
			star:SetVertexColor(.86, .95, 1)
			star:Hide()
			c.tips[i] = star
		end
		c.sweepTex = ns.Maskable(c, c:CreateTexture(nil, "ARTWORK", nil, 7))
		c.sweepTex:SetTexture(MEDIA .. "sweep"); c.sweepTex:SetBlendMode("ADD")
		c.sweepTex:SetVertexColor(.86, .96, 1)
		c.sweepTex:SetRotation(-.55)
		c.sweepTex:Hide()
		c.cutParams, c.traces, c.traceCuts = {}, {}, {}
	end
	if ccfg.glyphs then
		c.arcanePool = Pool(function() return ns.Maskable(c, c:CreateTexture(nil, "ARTWORK")) end)
		c.circles, c.glyphs = {}, {}
	end
end

function FX:LayoutContent(c, w, h)
	W, H = w, h
	if c.cfg.frostCuts and c == content and #c.cutParams > 0 then LayoutFrost() end
end

function FX:Layout(w, h) W, H = w, h end

local function ClearAll()
	wipe(particles)
	particlePool:ReleaseAll()
	linePool:ReleaseAll()
	spritePool:ReleaseAll()
	wipe(twinkles)
	wipe(emitAcc)
	vines = nil
end

function FX:Begin(c, w, h)
	W, H = w, h
	ClearAll()
	if content and content.arcanePool then content.arcanePool:ReleaseAll() end
	content, cfg = c, c.cfg
	if cfg.vines then MakeVines() end
	if cfg.frostCuts then BeginFrost() end
	if cfg.glyphs then
		c.arcanePool:ReleaseAll()
		wipe(c.circles); wipe(c.glyphs)
		c.circleNext, c.glyphT = rand(.2, 1.2) * H, 0
	end
end

function FX:Update(dt, t, fillW, casting)
	clock = t
	if not content then return end
	if casting then Emit(dt, fillW) end
	UpdateParticles(dt)
	if vines then
		if casting then GrowVines(fillW) end
		UpdateVines(fillW)
	end
	if cfg.frostCuts then UpdateFrost(dt, fillW) end
	if cfg.glyphs then UpdateArcane(dt, fillW, casting) end
	if cfg.twinkles then UpdateTwinkles(dt, fillW, casting) end
end

function FX:End()
	ClearAll()
	if content and content.arcanePool then content.arcanePool:ReleaseAll() end
end
