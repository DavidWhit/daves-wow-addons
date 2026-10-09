-- daves_castbar / Effects.lua
-- Everything that moves on its own: particles, and each element's live pieces.
--   frost      the freeze front where the water ahead turns to ice, and a glint sweeping across
--   nature     vines that grow with the cast, twisting around each other, with leaves and thorns
--   herbalism  the same vines, with flowers blooming along them
--   fishing    lily pads and fish in the pond, the bobber and its ripples at the cast edge
--   mining     the gem cart rolling to the cast edge, a pickaxe striking the wall at the end
--   skinning   cows and pigs that a cleaver at the cast edge turns into bone piles on blood stains
--   arcane     rune circles at random heights and sizes, held still; glyphs flare up
--   holy       four-point stars twinkling in and out
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

-- Sprites that turn, grow or drift every frame must not snap to the pixel grid: each corner would
-- jump to a different pixel every frame and the sprite would shake. Blizzard turns snapping off the
-- same way on its animated textures (snapToPixelGrid="false" texelSnappingBias="0.0", e.g.
-- Blizzard_ActionBar/Shared/ActionButtonComponentTemplate.xml, forever branch).
local function Smooth(tex)
	tex:SetSnapToPixelGrid(false)
	tex:SetTexelSnappingBias(0)
	return tex
end
ns.SmoothTexture = Smooth

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
	-- hidden and in place until UpdateParticles draws it, so a recycled texture never flashes
	-- for a frame where its previous particle was
	tex:SetAlpha(0)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", fx, "BOTTOMLEFT", x, y)
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
			if p.e.gravity then p.vy = p.vy - p.e.gravity * (H / 28) * dt end   -- rock chips fall back down
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
			elseif e.from == "top" then x, y = rand(0, fillW), H * rand(.7, 1)   -- embers carrying on off the top
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
local FLOWER_TINTS = { { .9, .24, .24 }, { .35, .55, 1 }, { .67, .43, .9 }, { 1, .82, .27 }, { .59, .51, .94 }, { .31, .78, .75 } }
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
	tex:SetVertexColor(1, 1, 1, 1)   -- a recycled sprite may still carry another look's tint
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
				seg.outline:SetStartPoint("BOTTOMLEFT", fx, prev.x, prev.y)
				seg.outline:SetEndPoint("BOTTOMLEFT", fx, v.x, y)
				seg.bark:SetStartPoint("BOTTOMLEFT", fx, prev.x, prev.y)
				seg.bark:SetEndPoint("BOTTOMLEFT", fx, v.x, y)
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
				if cfg.flowers and math.random() < .045 then    -- herbalism: a flower blooms on the vine
					local flower = { x = v.x, y = y, kind = "flower", ang = 0, size = H * rand(.35, .55), born = clock, rot = rand(0, 6.283),
						tex = Sprite("p_flower", front and 5 or 2) }
					local c, shade = pick(FLOWER_TINTS), front and 1 or .6
					flower.tex:SetVertexColor(c[1] * shade, c[2] * shade, c[3] * shade)
					v.growing[#v.growing + 1] = flower
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
			if s.kind == "flower" then
				PlaceSprite(s.tex, s.x, s.y, size, s.rot)
			elseif s.kind == "leaf" then
				PlaceSprite(s.tex, s.x + dx * size * .5, s.y + dy * size * .5, size, s.ang + PI / 4)
			else
				PlaceSprite(s.tex, s.x + dx * (size / 2 + s.off), s.y + dy * (size / 2 + s.off), size, s.ang - PI / 2)
			end
			if g >= 1 then table.remove(v.growing, i) end
		end
	end
end

---------------------------------------------------------------------------
-- Frost: the freeze front at the fill edge, and a glint sweeping across the ice
---------------------------------------------------------------------------
local function UpdateFrost(dt, fillW)
	if content.front then
		local front = content.front
		front:SetShown(fillW > 2)
		if fillW > 2 then
			front:ClearAllPoints()
			front:SetPoint("RIGHT", content, "LEFT", fillW, 0)
			front:SetSize(H * 1.4, H)
			front:SetAlpha(.75 + .2 * math.sin(clock * 7))
		end
	end
	if not content.sweepTex then return end
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

-- Frost while channelling: the freeze front faces right, into the ice the drained part has become.
-- It lies outside the fill's clip, so it is drawn on the fx frame, mirrored.
local function UpdateFrontReverse(fillW)
	local front = fx.frontRev
	front:SetShown(fillW < W - 2)
	if fillW >= W - 2 then return end
	front:ClearAllPoints()
	front:SetPoint("LEFT", fx, "BOTTOMLEFT", fillW, H / 2)
	local w = math.min(H * 1.4, W - fillW)
	front:SetSize(w, H)
	front:SetTexCoord(1, 1 - w / (H * 1.4), 0, 1)   -- near the bar's end, keep the edge and trim the feathered side
	front:SetAlpha(.75 + .2 * math.sin(clock * 7))
end

---------------------------------------------------------------------------
-- Fishing: lily pads drifting on the surface, fish swimming below, the bobber at the cast edge
-- (on the fx frame, so the pond covers the whole bar, not just the filled part)
---------------------------------------------------------------------------
local FISH_TINTS = { { 1, .59, .24 }, { .8, .85, .89 }, { .43, .51, .55 }, { 1, .8, .47 } }
local pond

local function MakePond()
	pond = { lilies = {}, fish = {}, ripples = {}, rippleT = 0 }
	for i = 1, 2 + math.random(0, 2) do
		local l = { x = rand(.08, .92) * W, s = rand(.75, 1.05), drift = rand(-2.5, 2.5), ph = rand(0, 6.283), tex = Sprite("p_lily", 2) }
		if math.random() < .3 then
			l.flower = Sprite("p_flower", 3)
			l.flower:SetVertexColor(1, .67, .78)
		end
		pond.lilies[i] = l
	end
	for i = 1, 2 + math.random(0, 1) do
		local f = { x = rand(.1, .9) * W, y = rand(.18, .55), dir = math.random() < .5 and -1 or 1, speed = rand(5, 13), s = rand(.6, .85),
			ph = rand(0, 6.283), turnT = rand(2, 6), tex = Sprite("p_fish", 0) }
		local c = pick(FISH_TINTS)
		f.tex:SetVertexColor(c[1], c[2], c[3])
		f.tex:SetAlpha(.55)
		pond.fish[i] = f
	end
	pond.bobber = Sprite("p_bobber", 5)
	pond.line = linePool:Get()
	pond.line:SetDrawLayer("ARTWORK", 4)
	pond.line:SetColorTexture(.9, .94, .94, .45)
	pond.line:SetVertexColor(1, 1, 1, 1)
	pond.line:SetThickness(1)
	if pond.line.SetSnapToPixelGrid then   -- it moves with the bobber every frame; snapping would make it shimmer
		pond.line:SetSnapToPixelGrid(false)    -- (lines are texture-based, but their docs don't list these, so guard)
		pond.line:SetTexelSnappingBias(0)
	end
end

local function UpdatePond(dt, fillW, casting)
	local k, surf = H / 28, H * .87
	for _, f in ipairs(pond.fish) do
		f.turnT = f.turnT - dt
		f.x = f.x + f.dir * f.speed * k * dt
		if f.x < H * .6 then f.dir, f.turnT = 1, rand(2, 6)
		elseif f.x > W - H * .6 then f.dir, f.turnT = -1, rand(2, 6)
		elseif f.turnT <= 0 then f.dir, f.turnT = -f.dir, rand(2, 6) end
		if f.dir < 0 then f.tex:SetTexCoord(1, 0, 0, 1) else f.tex:SetTexCoord(0, 1, 0, 1) end
		PlaceSprite(f.tex, f.x, H * f.y + math.sin(clock * 2 + f.ph) * H * .04, H * f.s, math.sin(clock * 9 + f.ph) * .06 * f.dir)
	end
	for _, l in ipairs(pond.lilies) do
		l.x = l.x + l.drift * k * dt
		if l.x < H * .5 then l.drift = math.abs(l.drift) elseif l.x > W - H * .5 then l.drift = -math.abs(l.drift) end
		local s, y = H * l.s, surf + math.sin(clock * 1.6 + l.ph) * H * .02
		PlaceSprite(l.tex, l.x, y, s, 0)
		if l.flower then PlaceSprite(l.flower, l.x + s * .08, y + s * .11, s * .45, 0) end
	end
	local show = fillW >= 1
	pond.bobber:SetShown(show); pond.line:SetShown(show)
	-- ripples spreading from the bobber
	pond.rippleT = pond.rippleT - dt
	if casting and show and pond.rippleT <= 0 then
		pond.rippleT = rand(.7, 1.1)
		local tex = Sprite("p_ripple", 3, "ADD")
		pond.ripples[#pond.ripples + 1] = { x = fillW, age = 0, tex = tex }
	end
	for i = #pond.ripples, 1, -1 do
		local r = pond.ripples[i]
		r.age = r.age + dt
		if r.age >= 1.4 then
			spritePool:Release(r.tex)
			table.remove(pond.ripples, i)
		else
			local t = r.age / 1.4
			local w = H * (.4 + 1.4 * t)
			r.tex:SetAlpha((1 - t) * .6)
			r.tex:ClearAllPoints()
			r.tex:SetPoint("CENTER", fx, "BOTTOMLEFT", r.x, surf)
			r.tex:SetSize(w, w * .3)
		end
	end
	if not show then return end
	-- the bobber rides the surface at the cast edge, on its line
	local bs = H * .95
	local by = surf - math.sin(clock * 3.2) * H * .05
	PlaceSprite(pond.bobber, fillW, by + bs * .05, bs, 0)
	pond.line:SetStartPoint("BOTTOMLEFT", fx, fillW, by + bs * .45)
	pond.line:SetEndPoint("BOTTOMLEFT", fx, fillW - H * .9, H * 1.85)
end

---------------------------------------------------------------------------
-- Mining: the gem cart rolls along the rail to the cast edge; a pickaxe strikes the wall at the end
---------------------------------------------------------------------------
local mine
local WHEEL_U = { .27, .73 }   -- the wheels, as fractions of the cart's width
local CHIP = { tex = "p_chip", colors = { { .47, .45, .43 }, { .59, .55, .51 }, { .8, .47, .24 } }, size = { .12, .24 }, life = { .5, .9 },
	vx = { -40, -12 }, vy = { 14, 40 }, spin = { -8, 8 }, gravity = 140 }
local SPARK = { tex = "p_star", colors = { { 1, .86, .55 }, { 1, .98, .86 } }, size = { .15, .3 }, life = { .15, .35 }, vx = { -30, 10 }, vy = { -5, 30 }, add = true }

local function MakeMine()
	mine = { swingT = rand(0, .8), last = 0, cart = Sprite("p_cart", 2), wheels = { Sprite("p_wheel", 1), Sprite("p_wheel", 1) },
		lantern = Sprite("p_soft", 3, "ADD"), pick = Sprite("p_pickaxe", 4) }
	mine.lantern:SetVertexColor(1, .75, .35)
	mine.lantern:SetAlpha(.55)
end

local function UpdateMine(dt, fillW, casting)
	local railY = H * .20
	-- the pickaxe swings from a pivot above the bar's end: raise slowly, strike fast, recoil
	local P = H * 1.1
	local L, cycle, deg = P * .76, .8, PI / 180
	mine.swingT = (mine.swingT + dt) % cycle
	local t, th = mine.swingT / cycle
	if t < .62 then th = (100 - 92 * math.sin(t / .62 * PI / 2)) * deg
	elseif t < .72 then th = (8 + 92 * ((t - .62) / .1) ^ 2) * deg
	else th = (100 - 8 * math.sin((t - .72) / .28 * PI)) * deg end
	local hx, hy = W + H * .05, H * .5                                   -- where the head lands
	local px, py = hx - L * math.sin(100 * deg), hy - L * math.cos(100 * deg)
	PlaceSprite(mine.pick, px + P * .45 * math.sin(th), py + P * .45 * math.cos(th), P, -th)
	if casting and t >= .72 and mine.last < .72 then                    -- impact: chips and sparks
		for _ = 1, 5 do Spawn(CHIP, hx + rand(-2, 2), hy + rand(-2, 2)) end
		for _ = 1, 4 do Spawn(SPARK, hx, hy) end
	end
	mine.last = t
	-- the cart: its front at the fill edge, wheels on the rail, lantern glowing
	local C = H * 1.25
	local wr = C * .14
	local cx = math.max(-C * .2, fillW - C * .94)
	for i, u in ipairs(WHEEL_U) do
		PlaceSprite(mine.wheels[i], cx + C * u, railY + wr, wr * 2, -fillW / wr)
	end
	local cy = railY + 1.15 * wr + .30 * C                               -- the cart's centre
	PlaceSprite(mine.cart, cx + C / 2, cy, C, 0)
	PlaceSprite(mine.lantern, cx + C * .80, cy - C * .10, H * (.9 + .1 * math.sin(clock * 11)), 0)
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
	tex:SetRotation(0)
	return tex
end

-- Circles and glyphs never turn: even unsnapped, a turning sprite shimmers along its fine lines.
-- A random mirror of the cell gives each one a different face instead.
local function MirroredCell(tex, l, r, t, b)
	if math.random() < .5 then l, r = r, l end
	if math.random() < .5 then t, b = b, t end
	tex:SetTexCoord(l, r, t, b)
end

local function UpdateArcane(dt, fillW, casting)
	-- circles appear as the bar fills, at random heights and sizes
	while casting and fillW > content.circleNext do
		local c = { x = content.circleNext, y = H * rand(.1, .9), s = H * rand(1.0, 2.3), born = clock, ph = rand(0, 6.283),
			tex = ArcaneTexture("p_runecircles", 4) }
		local i = math.random(3) - 1
		MirroredCell(c.tex, i * .25, (i + 1) * .25, 0, 1)
		local tint = pick(CIRCLE_TINTS)
		c.tex:SetVertexColor(tint[1], tint[2], tint[3])
		c.tex:SetSize(c.s, c.s)
		c.tex:ClearAllPoints(); c.tex:SetPoint("CENTER", content, "BOTTOMLEFT", c.x, c.y)
		content.circles[#content.circles + 1] = c
		content.circleNext = content.circleNext + H * rand(1.3, 3.0)
	end
	for _, c in ipairs(content.circles) do
		c.tex:SetAlpha(math.min(1, (clock - c.born) / .5) * (.75 + .2 * math.sin(clock * 1.3 + c.ph)))
	end
	-- single glyphs flare up and fade
	content.glyphT = content.glyphT - dt
	if casting and content.glyphT <= 0 and fillW > H then
		content.glyphT = rand(.25, .6)
		local q = { x = rand(H * .3, fillW - H * .2), y = H / 2 + rand(-.12, .12) * H, s = H * rand(.6, .95), age = 0, life = rand(.9, 1.7),
			tex = ArcaneTexture("p_glyphs", 5) }
		q.tex:ClearAllPoints(); q.tex:SetPoint("CENTER", content, "BOTTOMLEFT", q.x, q.y)   -- it never moves; only its size changes
		local i = math.random(16) - 1
		local col, row = i % 8, math.floor(i / 8)
		MirroredCell(q.tex, col / 8, (col + 1) / 8, row / 2, (row + 1) / 2)
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
-- Skinning: cows and pigs along the bar; the cleaver chops at the cast edge (the same swing as the
-- pickaxe), and each animal the edge reaches turns into a bone pile on a blood stain
---------------------------------------------------------------------------
local skin
local BLOOD = { tex = "p_soft", colors = { { .43, .03, .04 }, { .59, .06, .06 } }, size = { .07, .14 }, life = { .5, .9 },
	vx = { -25, 25 }, vy = { 10, 35 }, gravity = 160 }

local function MakeSkin()
	skin = { animals = {}, chopT = rand(0, .55), last = 0, cleaver = Sprite("p_cleaver", 4) }
	local x = H * rand(.6, 1.1)
	while x < W - H * .5 do
		local a = { x = x, s = H * rand(.85, 1), ph = rand(0, 6.283), tex = Sprite(math.random() < .5 and "p_cow" or "p_pig", 2) }
		if math.random() < .5 then a.tex:SetTexCoord(1, 0, 0, 1) end   -- facing left
		skin.animals[#skin.animals + 1] = a
		x = x + H * rand(1.1, 1.6)
	end
end

local function UpdateSkin(dt, fillW, casting)
	local ground = H * .10
	for _, a in ipairs(skin.animals) do
		if not a.dead and casting and fillW >= a.x then   -- chopped: bones on a blood stain, and a spray of blood
			a.dead = clock
			spritePool:Release(a.tex)
			a.tex = Sprite("p_bones", 1)
			for _ = 1, 6 do Spawn(BLOOD, a.x, ground + a.s * .35) end
		end
		if a.dead then
			local s = a.s * .9 * easeOutBack(math.min(1, (clock - a.dead) / .3))
			PlaceSprite(a.tex, a.x, ground + s * .4, s, 0)
		else
			local hop = math.abs(math.sin(clock * 6 + a.ph)) * H * .03
			local x, y, s = a.x, ground + a.s * .4 + hop, a.s
			a.tex:ClearAllPoints()
			a.tex:SetPoint("CENTER", fx, "BOTTOMLEFT", x, y)
			a.tex:SetSize(s, s)                                -- no SetRotation, so a left-facing flip always holds
		end
	end
	-- once the last animal is chopped the cleaver is done: it fades out instead of chopping the empty end
	local alive = false
	for _, a in ipairs(skin.animals) do if not a.dead then alive = true; break end end
	if not alive then
		skin.doneAt = skin.doneAt or clock
		local fade = 1 - (clock - skin.doneAt) / .2
		skin.cleaver:SetAlpha(math.max(0, fade))
		if fade <= 0 then return end
	end
	-- the cleaver: raise slowly, chop fast, recoil; its blade lands on the ground at the cast edge
	local P = H * 1.1
	local L, cycle, deg = P * .76, .55, PI / 180
	skin.chopT = (skin.chopT + dt) % cycle
	local t, th = skin.chopT / cycle
	if t < .62 then th = (100 - 92 * math.sin(t / .62 * PI / 2)) * deg
	elseif t < .72 then th = (8 + 92 * ((t - .62) / .1) ^ 2) * deg
	else th = (100 - 8 * math.sin((t - .72) / .28 * PI)) * deg end
	local hx, hy = fillW + H * .12, ground + H * .62   -- the handle lands here; the blade hangs down to the ground
	local px, py = hx - L * math.sin(100 * deg), hy - L * math.cos(100 * deg)
	PlaceSprite(skin.cleaver, px + P * .45 * math.sin(th), py + P * .45 * math.cos(th), P, -th)
	if casting and alive and t >= .72 and skin.last < .72 then
		for _ = 1, 2 do Spawn(BLOOD, hx, ground + H * .1) end
	end
	skin.last = t
end

---------------------------------------------------------------------------
-- Hooks called by Bar.lua
---------------------------------------------------------------------------
function FX:Init(frame)
	fx = frame
	particlePool = Pool(function() return Smooth(fx:CreateTexture(nil, "ARTWORK", nil, 7)) end)
	linePool = Pool(function() return fx:CreateLine(nil, "ARTWORK") end)
	spritePool = Pool(function() return Smooth(fx:CreateTexture(nil, "ARTWORK")) end)
	fx.frontRev = Smooth(fx:CreateTexture(nil, "ARTWORK", nil, -1))
	fx.frontRev:SetTexture(MEDIA .. "frost_front")
	fx.frontRev:SetTexCoord(1, 0, 0, 1)   -- strongest at the edge, feathering to the right
	fx.frontRev:SetBlendMode("ADD")
	fx.frontRev:Hide()
end

-- Pieces that live inside an element's content frame (clipped by the fill, masked when borderless).
function FX:CreateContent(c)
	local ccfg = c.cfg
	if ccfg.freeze then   -- the freeze front: rime feathering in from the fill edge
		c.front = ns.Maskable(c, Smooth(c:CreateTexture(nil, "ARTWORK", nil, 6)))
		c.front:SetTexture(MEDIA .. "frost_front"); c.front:SetBlendMode("ADD")
		c.front:Hide()
	end
	if ccfg.sweep then
		c.sweepTex = ns.Maskable(c, Smooth(c:CreateTexture(nil, "ARTWORK", nil, 7)))
		c.sweepTex:SetTexture(MEDIA .. "sweep"); c.sweepTex:SetBlendMode("ADD")
		c.sweepTex:SetVertexColor(.86, .96, 1)
		c.sweepTex:SetRotation(-.55)
		c.sweepTex:Hide()
	end
	if ccfg.glyphs then
		c.arcanePool = Pool(function() return ns.Maskable(c, Smooth(c:CreateTexture(nil, "ARTWORK"))) end)
		c.circles, c.glyphs = {}, {}
	end
end

function FX:LayoutContent(c, w, h)
	W, H = w, h
	if c.sweepTex then c.sweepTex:SetSize(H * 1.0, H * 1.8) end
end

function FX:Layout(w, h) W, H = w, h end

local function ClearAll()
	wipe(particles)
	particlePool:ReleaseAll()
	linePool:ReleaseAll()
	spritePool:ReleaseAll()
	wipe(twinkles)
	wipe(emitAcc)
	vines, pond, mine, skin = nil, nil, nil, nil
end

function FX:Begin(c, w, h)
	W, H = w, h
	ClearAll()
	if content and content.arcanePool then content.arcanePool:ReleaseAll() end
	content, cfg = c, c.cfg
	if cfg.vines then MakeVines() end
	if cfg.pond then MakePond() end
	if cfg.mine then MakeMine() end
	if cfg.skin then MakeSkin() end
	fx.frontRev:Hide()
	if c.sweepTex then c.sweepT, c.sweep = rand(.4, 1.5), nil; c.sweepTex:Hide() end
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
	if cfg.freeze or cfg.sweep then UpdateFrost(dt, fillW) end
	if pond then UpdatePond(dt, fillW, casting) end
	if mine then UpdateMine(dt, fillW, casting) end
	if skin then UpdateSkin(dt, fillW, casting) end
	if cfg.freezeReverse then UpdateFrontReverse(fillW) end
	if cfg.glyphs then UpdateArcane(dt, fillW, casting) end
	if cfg.twinkles then UpdateTwinkles(dt, fillW, casting) end
end

function FX:End()
	ClearAll()
	fx.frontRev:Hide()
	if content and content.arcanePool then content.arcanePool:ReleaseAll() end
end
