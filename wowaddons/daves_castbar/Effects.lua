-- daves_castbar / Effects.lua
-- Everything that moves on its own: particles, and each element's live pieces.
--   frost      the freeze front where the water ahead turns to ice, and a glint sweeping across
--   nature     vines that grow with the cast, twisting around each other, with leaves and thorns
--   herbalism  the same vines, with flowers blooming along them
--   fishing    lily pads and fish in the pond, the bobber and its ripples at the cast edge
--   mining     the gem cart rolling to the cast edge, a pickaxe striking the wall at the end
--   skinning   the pelt rolling back over marbled meat at the cast edge, a pool of blood, the knife sawing along the roll
--   smelting   a forged ladle riding the cast edge, pouring a stream that lands and cools to crust behind it
--   blacksmith the iron heating toward the cast edge, the forge hammer striking it, steam, the quench at the end
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
		tw = e.twinkle and rand(8, 16) or 0, sw = rand(0, 6.283), grow = e.grow and rand(e.grow[1], e.grow[2]) * H or nil,
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
			if p.e.gravity then p.vy = p.vy - p.e.gravity * (H / 28) * dt end   -- rock chips and sparks fall back down
			if p.grow then p.size = p.size + p.grow * dt; p.tex:SetSize(p.size, p.size) end   -- steam spreads as it rises
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
-- Skinning: the pelt rolls back over marbled meat. Ahead of the cast lies the fur (the track,
-- tinted to this cast's pelt through ns.TintTrack); at the cast edge the hide rolls up on itself,
-- growing as it goes; behind it lies the meat (the fill layer), a pool of blood spreads behind the
-- knife, and the knife stands against the roll, its edge on the roll, sawing up and down and lifting away when the cast ends. The roll and the knife
-- stand on `tools`, a frame above the bar's frame line; nothing here turns, it only moves and grows.
---------------------------------------------------------------------------
local function RGB(r, g, b) return { r / 255, g / 255, b / 255 } end
-- The fur textures are neutral: `fur` tints the coat, `tips` the guard hairs' light tips added on
-- top. The roll uses one texture, tinted between the two. Each cast takes the next pelt in turn.
local PELTS = {
	{ fur = RGB(86, 57, 33), tips = RGB(84, 75, 59) },       -- brown bear
	{ fur = RGB(92, 90, 92), tips = RGB(122, 120, 110) },    -- grey wolf
	{ fur = RGB(146, 100, 48), tips = RGB(84, 94, 86) },     -- tawny cat
	{ fur = RGB(168, 74, 26), tips = RGB(68, 94, 78) },      -- red fox
	{ fur = RGB(196, 196, 200), tips = RGB(50, 50, 48) },    -- arctic white
	{ fur = RGB(30, 28, 30), tips = RGB(56, 52, 46) },       -- black bear
	{ fur = RGB(70, 62, 122), tips = RGB(94, 88, 92) },      -- nightsaber
	{ fur = RGB(96, 80, 62), tips = RGB(74, 72, 64) },       -- boar
}
local peltTurn = math.random(#PELTS) - 1
local skin                   -- this cast's skinning state
local tools                  -- above the bar's frame line: the roll and the knife
local roll                   -- the roll's and knife's textures, made once
local POOL_MAX = 80          -- blots in the pool at most (three textures each)
-- The knife texture (Make-CastbarMedia.ps1 Knife): 128x256 at 120 px per bar height, upright, the tip 0.35
-- bar heights from its left and 2.0 from its top, the curved edge facing right.
local KNIFE_W, KNIFE_H, KNIFE_TIPX, KNIFE_TIPY = 128 / 120, 256 / 120, .35, 2.0
local KNIFE_L = 1.05
local KNIFE_BELLY = .22      -- how far the edge bulges right of the tip line; it rests on the roll's left edge
local ROLL_PARTS = { "shadow", "fur", "shade", "cap", "spiral", "knife", "glint", "ahead" }   -- not the mask: a hidden mask stops masking
local ROLL_SHOWN = { "fur", "shade", "cap", "spiral", "shadow" }
local ROLL_GREY = { "fur", "cap", "spiral" }   -- greyed with the fur ahead when the cast is interrupted

local function ToolTexture(name, sub, blend)
	local tex = Smooth(tools:CreateTexture(nil, "ARTWORK", nil, sub))
	tex:SetTexture(MEDIA .. name)
	tex:SetBlendMode(blend or "BLEND")
	tex:Hide()
	return tex
end

local function MakeRoll()
	roll = {}
	roll.shadow = ToolTexture("glow", 0)
	roll.shadow:SetVertexColor(0, 0, 0)
	roll.fur = ToolTexture("p_roll_fur", 1)
	roll.fur:SetTexture(MEDIA .. "p_roll_fur", "REPEAT", "REPEAT")
	roll.mask = Smooth(tools:CreateMaskTexture())   -- it moves and grows with the roll, so no pixel snapping
	roll.mask:SetTexture(MEDIA .. "p_roll_mask")
	roll.mask:SetAllPoints(roll.fur)
	roll.fur:AddMaskTexture(roll.mask)
	roll.shade = ToolTexture("p_roll_shade", 2)
	roll.shade:SetAllPoints(roll.fur)
	roll.cap = ToolTexture("p_roll_end", 3)
	roll.spiral = ToolTexture("p_roll_spiral", 4)
	roll.knife = ToolTexture("p_knife_wood", 5)
	roll.glint = ToolTexture("p_soft", 6, "ADD")
	-- the coat ahead of the roll lies in its shadow for a little way; it lives on the track, so it
	-- follows the borderless edges like the fur it darkens
	roll.ahead = Smooth(ns.TrackTexture(2))
	roll.ahead:SetTexture(MEDIA .. "edge_h")
	roll.ahead:SetTexCoord(1, 0, 0, 1)
	roll.ahead:SetVertexColor(0, 0, 0, .45)
	roll.ahead:Hide()
end

local function HideSkin()
	if roll then
		for _, k in ipairs(ROLL_PARTS) do roll[k]:Hide() end
	end
	if content and content.poolPool then
		content.poolPool:ReleaseAll()
		for _, tex in ipairs(content.skinMeat) do tex:Hide() end
	end
end

local function MakeSkin()
	if not roll then MakeRoll() end
	peltTurn = peltTurn % #PELTS + 1
	local pelt = PELTS[peltTurn]
	ns.TintTrack(pelt.fur, pelt.tips)
	local rc = {}
	for i = 1, 3 do rc[i] = pelt.fur[i] + pelt.tips[i] * .35 end
	roll.fur:SetVertexColor(rc[1], rc[2], rc[3])
	roll.spiral:SetVertexColor(pelt.fur[1], pelt.fur[2], pelt.fur[3])
	roll.knife:SetTexture(MEDIA .. (math.random() < .4 and "p_knife_antler" or "p_knife_wood"))
	for _, k in ipairs(ROLL_GREY) do roll[k]:SetDesaturation(0) end   -- the last cast may have been interrupted
	local flip = math.random() < .5   -- the spiral winds either way
	roll.cap:SetTexCoord(flip and 1 or 0, flip and 0 or 1, 0, 1)
	roll.spiral:SetTexCoord(flip and 1 or 0, flip and 0 or 1, 0, 1)
	skin = { pool = {}, poolNext = H * rand(.5, .9) }
end

-- A blot of the pool: a dark seep under it, a brighter rim, and the darker body a little smaller on
-- top. All rims sit below all bodies, so overlapping blots merge into one puddle. Blots near the
-- spell name stay smaller, and the pool thins toward the far left.
local function PoolTexture(cell, sub, r, g, b)
	local tex = content.poolPool:Get()
	tex:SetTexture(MEDIA .. "p_pool")
	tex:SetTexCoord(cell * .25, (cell + 1) * .25, 0, 1)
	tex:SetDrawLayer("ARTWORK", sub)
	tex:SetBlendMode("BLEND")
	tex:SetVertexColor(r, g, b)
	tex:SetDesaturation(0)
	return tex
end

local function PlaceIn(tex, frame, x, y, w, h)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", frame, "BOTTOMLEFT", x, y)
	tex:SetSize(math.max(.1, w), math.max(.1, h))
end

-- A blot is anchored and faded once; after that only its size changes (UpdateSkin).
local function AddBlot(x)
	local nearText = math.max(0, math.min(1, (x - H * .6) / (H * 3.2)))
	local cell = math.random(4) - 1
	local q = { x = x, y = H * (.5 + rand(-.14, .14)), max = H * rand(.2, .32) * (.55 + .45 * nearText), born = clock, grow = rand(.5, .9),
		fade = 1 - .55 * (1 - math.min(1, x / (H * 4))) }
	q.seep = PoolTexture(cell, 2, .16, 0, .02)
	q.rim = PoolTexture(cell, 3, .64, .07, .1)
	q.body = PoolTexture(cell, 4, .43, .02, .04)
	PlaceIn(q.seep, content, q.x + H * .02, q.y - H * .03, .1, .1)
	PlaceIn(q.rim, content, q.x, q.y, .1, .1)
	PlaceIn(q.body, content, q.x, q.y, .1, .1)
	q.seep:SetAlpha(.45 * q.fade); q.rim:SetAlpha(q.fade); q.body:SetAlpha(q.fade)
	if math.random() < .3 then   -- a few wet glints
		q.glint = content.poolPool:Get()
		q.glint:SetTexture(MEDIA .. "p_soft")
		q.glint:SetTexCoord(0, 1, 0, 1)
		q.glint:SetDrawLayer("ARTWORK", 5)
		q.glint:SetBlendMode("ADD")
		q.glint:SetVertexColor(1, .88, .88)
		q.glint:SetDesaturation(0)
		q.ph = rand(0, 6.283)
	end
	skin.pool[#skin.pool + 1] = q
end

-- swell, then keep creeping outward slowly
local function BlotRadius(q)
	local age = clock - q.born
	local t = math.min(1, age / q.grow)
	return q.max * ((1 - (1 - t) * (1 - t)) * .75 + .25 * math.min(1, math.log(1 + age * .6) / 2.2))
end

-- the meat's light and shade, between left and right (x in bar pixels), clipped to the bar
local function Band(tex, left, right)
	left, right = math.max(0, left), math.min(W, right)
	tex:SetShown(right - left > .5)
	if right - left > .5 then
		tex:ClearAllPoints()
		tex:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", left, 0)
		tex:SetSize(right - left, H)
	end
end

local function UpdateSkin(dt, fillW, casting)
	local r = H * (.2 + .16 * fillW / W)
	local xc = fillW - r * .9
	-- blood wells up just behind the knife as it goes, and the pool keeps spreading behind it
	while casting and xc - r * 1.6 > skin.poolNext and #skin.pool < POOL_MAX do
		AddBlot(skin.poolNext)
		-- spaced by the bar's length too, so POOL_MAX reaches the end of a long, thin bar
		skin.poolNext = skin.poolNext + math.max(H * rand(.26, .4), W / POOL_MAX)
	end
	for _, q in ipairs(skin.pool) do
		local s = BlotRadius(q) / .3          -- the blot's main lobe is 0.3 of its texture
		q.seep:SetSize(s * 1.12, s * 1.12)
		q.rim:SetSize(s, s)
		q.body:SetSize(s * .84, s * .84)
		if q.glint then
			local gr = BlotRadius(q)
			PlaceIn(q.glint, content, q.x + gr * .15, q.y + gr * .35, gr * .7, gr * .7)
			q.glint:SetAlpha((.3 + .15 * math.sin(clock * .7 + q.ph)) * q.fade * (1 - (skin.grey or 0)))
		end
	end
	-- the meat: older meat dulls, the fresh cut by the roll is moist, the roll shades it
	local m = content.skinMeat
	Band(m[1], 0, xc - H * 2)
	Band(m[2], xc - H * 1.4, xc)
	Band(m[3], xc - H * .6, xc)

	if fillW <= 1 then
		for _, k in ipairs(ROLL_PARTS) do roll[k]:Hide() end
		return
	end
	if not casting then skin.endAt = skin.endAt or clock end
	local lift = skin.endAt and math.min(1, (clock - skin.endAt) / .5) ^ 2 or 0

	-- the roll: a fur cylinder standing across the bar, seen a little from above
	local ry, top, bottom = r * .3, H * 1.08, -H * .08
	local bodyH = top - bottom + ry
	roll.fur:ClearAllPoints()
	roll.fur:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", xc - r, top)
	roll.fur:SetSize(r * 2, bodyH)
	local v0 = xc * .9 / (r * 4)          -- the fur turns as it rolls along
	roll.fur:SetTexCoord(0, 1, v0, v0 + bodyH / (r * 4))
	PlaceIn(roll.cap, tools, xc, top, r * 2, ry * 2)
	PlaceIn(roll.spiral, tools, xc, top, r * 2, ry * 2)
	PlaceIn(roll.shadow, tools, xc + H * .08, H * .44, r * 2 + H * .5, H * 1.5)
	roll.shadow:SetAlpha(.45)
	local aheadL = xc + r
	local aheadW = math.min(H * .5, W - aheadL)
	roll.ahead:SetShown(aheadW > .5)
	if aheadW > .5 then
		roll.ahead:ClearAllPoints()
		roll.ahead:SetPoint("BOTTOMLEFT", tools, "BOTTOMLEFT", aheadL, 0)
		roll.ahead:SetSize(aheadW, H)
	end
	for _, k in ipairs(ROLL_SHOWN) do roll[k]:Show() end

	-- the knife: upright just left of the roll, its curved edge resting on the roll's edge, the tip at the
	-- bottom of the bar and the handle standing above it; it saws up and down along the roll and lifts
	-- up and away to the left when the cast ends
	local saw = casting and math.sin(clock * 13) * H * .05 or 0
	local tipX = xc - r - KNIFE_BELLY * H - lift * H * .6
	local tipY = H * .04 - saw + lift * H * 1.2
	roll.knife:ClearAllPoints()
	roll.knife:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", tipX - KNIFE_TIPX * H, tipY + KNIFE_TIPY * H)
	roll.knife:SetSize(KNIFE_W * H, KNIFE_H * H)
	roll.knife:SetAlpha(1 - lift)
	roll.knife:Show()
	-- a glint sliding up and down the blade as it saws
	PlaceIn(roll.glint, tools, tipX + H * .07, tipY + KNIFE_L * H * (.25 + .5 * (.5 + .5 * math.sin(clock * 13))), H * .2, H * .2)
	roll.glint:SetAlpha(.45 * (1 - lift))
	roll.glint:Show()
end

---------------------------------------------------------------------------
-- Blacksmithing and smelting: hot metal, the forge hammer, the pouring ladle. The hammer and the ladle
-- stand on `tools`, in front of the bar's frame line. Neither turns: Make-CastbarMedia.ps1 paints them at
-- every angle they need into an atlas (Hammer, Ladle), and the addon switches cells and moves them.
---------------------------------------------------------------------------
local forge                  -- the hammer's and ladle's textures, made once
local smith, smelt           -- this cast's state
local STEAM = RGB(226, 226, 232)
local FORGE_SPARK = { tex = "p_ember", colors = { RGB(255, 226, 130), RGB(255, 172, 60), RGB(255, 250, 210), RGB(255, 130, 40) },
	size = { .07, .13 }, life = { .25, .65 }, vx = { -150, 150 }, vy = { 40, 220 }, gravity = 450, add = true }
local STRIKE_STEAM = { tex = "p_soft", colors = { STEAM }, size = { .18, .3 }, grow = { .7, 1.1 }, life = { .8, 1.4 },
	vx = { -28, 28 }, vy = { 20, 50 }, alpha = .55 }
local WISPS = {}           -- steam wisps, fainter to stronger as the iron heats
for i = 1, 4 do
	WISPS[i] = { tex = "p_soft", colors = { STEAM }, size = { .1, .18 }, grow = { .45, .75 }, life = { 1, 1.9 }, vx = { -7, 7 }, vy = { 17, 36 }, alpha = .14 + .2 * (i - 1) / 3 }
end
local QUENCH = { tex = "p_soft", colors = { STEAM }, size = { .25, .45 }, grow = { .9, 1.5 }, life = { 1, 1.6 }, vx = { -17, 17 }, vy = { 17, 62 }, alpha = .7 }
local POUR_SPARK = { tex = "p_ember", colors = { RGB(255, 210, 110), RGB(255, 160, 50), RGB(255, 240, 170) }, size = { .06, .11 },
	life = { .35, .8 }, vx = { -90, 90 }, vy = { 60, 165 }, gravity = 390, add = true }
local POUR_DROP = { tex = "p_soft", colors = { RGB(255, 150, 40) }, size = { .1, .16 }, life = { .25, .45 }, vx = { -50, 50 }, vy = { 40, 85 }, gravity = 340, add = true }

-- The hammer atlas (Make-CastbarMedia.ps1 Hammer): 4x4 cells, each HAM_SPAN bar heights square with the grip
-- end at (HAM_OX, HAM_OY) from its top-left; cell 0 lies level, cell 15 is lifted HAM_MAX rad. Drawn at
-- HAM_SCALE of the bar height; the striking face sits HAM_FACE below the haft, the head HAM_L along it.
local HAM_POSES, HAM_MAX, HAM_SPAN, HAM_OX, HAM_OY, HAM_L, HAM_FACE, HAM_SCALE = 16, .95, 3.0, .45, 2.1, 1.45, .522, .78
-- The ladle atlas (Ladle): 2x2 cells, each LADLE_SPAN square with the spout lip at (LADLE_OX, LADLE_OY), tipped
-- .58, .40, .22 and .05 rad (pouring to righted). Painted with a bowl radius of .56 bar heights, drawn at .38.
local LADLE_SPAN, LADLE_OX, LADLE_OY, LADLE_SCALE = 2.6, .3, 1.8, .38 / .56
local FORGE_PARTS = { "hammer", "stream", "ladle", "spout", "flash", "land" }
local LADLE_PARTS = { "ladle", "spout", "stream" }
local QUENCH_MAX = 60        -- steam puffs in the quench burst at most (a long, thin bar would want hundreds)
-- How far behind the landing point the fresh pour stays hot: it cools to crust within about this many pixels
-- times 3.2 (SmeltHot spans 3.2 e-folds and turns clear from about 0.4 heat down).
local function SmeltSpan() return 3.2 * (W * smelt.cool * .55 + H * .9) end

local function MakeForge()
	forge = {}
	forge.hammer = ToolTexture("p_hammer_wood", 5)
	forge.stream = ToolTexture("smelt_stream", 3)
	forge.stream:SetTexture(MEDIA .. "smelt_stream", "REPEAT", "REPEAT")
	forge.ladle = ToolTexture("p_ladle", 4)
	forge.spout = ToolTexture("p_soft", 6, "ADD")        -- molten glow over the ladle's lip
	forge.spout:SetVertexColor(1, .59, .16)
	forge.flash = Smooth(fx:CreateTexture(nil, "ARTWORK", nil, 6))   -- the hammer's strike
	forge.flash:SetTexture(MEDIA .. "p_soft"); forge.flash:SetBlendMode("ADD"); forge.flash:SetVertexColor(1, .9, .65); forge.flash:Hide()
	forge.land = Smooth(fx:CreateTexture(nil, "ARTWORK", nil, 2))    -- where the stream lands
	forge.land:SetTexture(MEDIA .. "p_soft"); forge.land:SetBlendMode("ADD"); forge.land:SetVertexColor(1, .51, .16); forge.land:Hide()
end

local function HideForge()
	if forge then
		for _, k in ipairs(FORGE_PARTS) do forge[k]:Hide() end
	end
	if content and content.forge then
		for _, tex in pairs(content.forge) do if type(tex) == "table" and tex.Hide then tex:Hide() end end
		if content.flarePool then content.flarePool:ReleaseAll() end
	end
end

-- Hammer rhythm. u is the phase in a strike cycle (0 = impact): bounce, rest, slow raise, fast drop.
-- Returns how far the head is lifted, 0..HAM_MAX rad.
local function HammerLift(u)
	if u < .12 then return .13 * math.sin(PI * u / .12) end
	if u < .26 then return 0 end
	if u < .8 then local t = (u - .26) / .54; return HAM_MAX * (1 - (1 - t) * (1 - t)) end
	local t = (u - .8) / .2
	return HAM_MAX * (1 - t * t)
end

-- heat, temper: what the last cast ended at, when this one follows straight on (FX:Begin); the iron keeps that
-- heat for a moment, and a quenched bar fades back to hot iron instead of snapping
local function MakeSmith(heat, temper)
	if not forge then MakeForge() end
	local antler = math.random() < .4                       -- a wood haft with brass, or antler with steel
	forge.hammer:SetTexture(MEDIA .. (antler and "p_hammer_antler" or "p_hammer_wood"))
	smith = { u = rand(.3, .6), period = rand(.62, .78), flares = {}, wispAcc = 0, flashAt = -1, grey = 0,
		born = clock, carryHeat = heat, carryTemper = temper }
	forge.hammer:SetDesaturation(0)   -- the last cast may have been interrupted
	local f = content.forge
	f.hot:SetDesaturation(0)
	-- the hot layer lies over the base exactly, so their scale flecks line up
	local L = content.layers[1]
	local span = W / (512 * H / 64)
	f.hot:SetTexCoord(L.u, L.u + span, 0, 1)
	f.hot:Show(); f.edge:Show()
	f.temper:SetAlpha(0); f.temper:Show()
end

-- an impact flare on the struck spot: bright, then cooling over a couple of seconds
local function AddFlare(x)
	local tex = content.flarePool:Get()
	tex:SetTexture(MEDIA .. "p_soft")
	tex:SetBlendMode("ADD")
	tex:SetDrawLayer("ARTWORK", 3)
	tex:SetVertexColor(1, .78, .4)
	smith.flares[#smith.flares + 1] = { x = x, born = clock, tex = tex }
end

local function UpdateSmith(dt, fillW, casting, state)
	local f = content.forge
	local p = fillW / W
	local base = .2 + .4 * p
	if smith.carryHeat then   -- following straight on from the last cast: its heat fades into this one's
		base = math.max(base, .2 + (smith.carryHeat - .2) * math.exp(-(clock - smith.born) * .8))
	end
	smith.heat = base
	if not casting and not smith.endAt then
		smith.endAt, smith.quench = clock, state == "done"
		if smith.quench then   -- the quench: a rolling cloud of steam bursts off the bar
			for _ = 1, math.min(QUENCH_MAX, math.floor(W / H * 5)) do Spawn(QUENCH, rand(0, W), H * rand(.2, 1.1)) end
		end
	end
	local since = smith.endAt and clock - smith.endAt or 0
	local q = smith.quench and math.min(1, 1 - (1 - math.min(1, since / .35)) ^ 2) or 0   -- turning to tempered steel
	local cool = smith.endAt and not smith.quench and math.max(0, 1 - since / .7) or 1
	local lit = 1 - smith.grey                                        -- an interrupt fades the glows out

	-- heat: the iron warms as the cast goes on, hottest at the cast edge
	f.hot:SetAlpha(math.min(1, (base - .2) / .5) * (1 - q) * cool)
	Band(f.edge, fillW - H * 3.3, fillW)
	f.edge:SetAlpha(.55 * (1 - q) * cool * lit)
	local carriedTemper = smith.carryTemper and smith.carryTemper * math.max(0, 1 - (clock - smith.born) / .4) or 0
	smith.temper = math.max(q, carriedTemper)
	f.temper:SetAlpha(smith.temper)

	-- the hammer: strikes the cast edge in rhythm (fast drop, small bounce), resting while the cast holds
	local hx = math.max(H * .3, fillW - H * .3)
	if casting then
		smith.u = smith.u + dt / smith.period
		if smith.u >= 1 then
			smith.u = smith.u - 1
			if fillW > H * .2 then   -- a strike: flash, sparks, a puff of steam, the struck spot flares
				for _ = 1, math.floor(10 + 10 * (base + .4)) do Spawn(FORGE_SPARK, hx + rand(-.2, .2) * H, H * rand(.9, 1.05)) end
				for _ = 1, 5 do Spawn(STRIKE_STEAM, hx + rand(-.45, .45) * H, H * rand(.75, 1.15)) end
				AddFlare(hx)
				smith.flashAt = clock
			end
		end
	end
	for i = #smith.flares, 1, -1 do
		local fl = smith.flares[i]
		local age = clock - fl.born
		if age > 2 then
			content.flarePool:Release(fl.tex)
			table.remove(smith.flares, i)
		else
			PlaceIn(fl.tex, content, fl.x, H * .5, H * 1.6, H * 1.3)
			fl.tex:SetAlpha(.9 * math.exp(-age * 2.2) * (1 - q) * lit)
		end
	end
	local fa = math.max(0, 1 - (clock - smith.flashAt) / .18)
	forge.flash:SetShown(fa > 0)
	if fa > 0 then
		local s = .5 + 1.1 * (1 - fa * fa)   -- swells fast, then fades
		PlaceIn(forge.flash, fx, hx, H, H * s * 2.6, H * s * 1.6)
		forge.flash:SetAlpha(.95 * fa * lit)
	end
	-- steam wisps rising off the hot part, more as it heats
	if casting and fillW > 2 then
		smith.wispAcc = smith.wispAcc + (2 + 12 * p) * fillW / 300 * dt
		while smith.wispAcc >= 1 do
			smith.wispAcc = smith.wispAcc - 1
			Spawn(WISPS[math.min(4, 1 + math.floor(p * 4))], rand(0, fillW), H * rand(.85, 1.05))
		end
	end

	local ha = smith.endAt and math.max(0, 1 - since * 3) or 1
	forge.hammer:SetShown(ha > 0 and fillW > 1)
	if ha <= 0 or fillW <= 1 then return end
	local lift = HammerLift(smith.u)
	local pose = math.max(0, math.min(HAM_POSES - 1, math.floor(lift / HAM_MAX * (HAM_POSES - 1) + .5)))
	local col, row = pose % 4, math.floor(pose / 4)
	forge.hammer:SetTexCoord(col / 4, (col + 1) / 4, row / 4, (row + 1) / 4)
	local k = H * HAM_SCALE
	local px, py = hx - HAM_L * k, H + HAM_FACE * k             -- the grip end
	forge.hammer:ClearAllPoints()
	forge.hammer:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", px - HAM_OX * k, py + HAM_OY * k)
	forge.hammer:SetSize(HAM_SPAN * k, HAM_SPAN * k)
	forge.hammer:SetAlpha(ha)
end

local function MakeSmelt()
	if not forge then MakeForge() end
	smelt = { cool = rand(.16, .22), sparkAcc = 0, streamV = rand(0, 1), bob = ns.Wobble(2), grey = 0 }
	forge.ladle:SetDesaturation(0); forge.stream:SetDesaturation(0)   -- the last cast may have been interrupted
	content.forge.hot:SetDesaturation(0)
	content.forge.hot:Show(); content.forge.front:Show()
end

local function UpdateSmelt(dt, fillW, casting)
	local f = content.forge
	if not casting and not smelt.endAt then smelt.endAt = clock end
	local since = smelt.endAt and clock - smelt.endAt or 0
	local back = smelt.endAt and 1 - (1 - math.min(1, since / .5)) ^ 2 or 0   -- the ladle tips back and lifts away
	local cool = smelt.endAt and math.exp(-since * 1.4) or 1
	local lit = 1 - smelt.grey                                    -- an interrupt fades the glows out
	local land = math.max(0, fillW - H * .32)                    -- where the stream lands, just behind the cast edge

	-- the fresh pour: pale yellow where it lands, through orange to the dark crust behind it
	local span = SmeltSpan()
	local left = land - span
	local right = math.max(fillW, land + 1)
	f.hot:ClearAllPoints()
	f.hot:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", left, 0)
	f.hot:SetSize(right - left, H)
	f.hot:SetTexCoord(0, (right - left) / span, 0, 1)            -- past the landing point it stays at its hottest
	f.hot:SetAlpha(cool)
	f.hot:SetShown(fillW > 1)
	PlaceIn(f.front, content, fillW - H * .15, H * .5, H * 1.6, H * 1.6)
	f.front:SetAlpha(.4 * cool * lit)
	f.front:SetShown(fillW > 1)

	forge.land:SetShown(fillW > 1 and back < 1)
	PlaceIn(forge.land, fx, land, H * .88, H * 2.2, H * 2.2)
	forge.land:SetAlpha(.35 * (1 - back) * lit)
	if casting and fillW > 1 then
		smelt.sparkAcc = smelt.sparkAcc + dt * 26
		while smelt.sparkAcc >= 1 do
			smelt.sparkAcc = smelt.sparkAcc - 1
			Spawn(POUR_SPARK, land, H * .88)
			if math.random() < .15 then Spawn(POUR_DROP, land, H * .88) end
		end
	end

	-- the ladle rides the cast edge, pouring; at the end it tips back and is lifted away
	local show = fillW > .5 or casting
	if not show or back >= 1 then
		for _, k in ipairs(LADLE_PARTS) do forge[k]:Hide() end
		return
	end
	local lipX = land + H * .11
	local lipY = H + H * .3 + back * H * .3 + (casting and smelt.bob(clock) * H * .02 or 0)
	local pose = math.floor(back * 3 + .5)
	local col, row = pose % 2, math.floor(pose / 2)
	local k = H * LADLE_SCALE
	forge.ladle:SetTexCoord(col / 2, (col + 1) / 2, row / 2, (row + 1) / 2)
	forge.ladle:ClearAllPoints()
	forge.ladle:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", lipX - LADLE_OX * k, lipY + LADLE_OY * k)
	forge.ladle:SetSize(LADLE_SPAN * k, LADLE_SPAN * k)
	forge.ladle:SetAlpha(1 - back * back)
	forge.ladle:Show()
	PlaceIn(forge.spout, tools, lipX - H * .04, lipY, H * .55, H * .55)
	forge.spout:SetAlpha(.5 * (1 - back) * lit)
	forge.spout:Show()
	-- the stream: from the spout down into the metal, flowing (its texture scrolls down)
	forge.stream:SetShown(casting)
	if casting then
		local top, bottom = lipY - H * .03, H * .78
		local sw = H * .11 / .64                                   -- the texture's body is 64% of its width
		smelt.streamV = (smelt.streamV - dt * 2.2) % 1
		forge.stream:ClearAllPoints()
		forge.stream:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", land + H * .015 - sw / 2, top)
		forge.stream:SetSize(sw, top - bottom)
		forge.stream:SetTexCoord(0, 1, smelt.streamV, smelt.streamV + (top - bottom) / (sw * 4))
	end
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
	-- above the frame line (border, bar level + 7) and below the text (+ 9): tools held in front of the bar
	local bar = fx:GetParent()
	tools = CreateFrame("Frame", nil, bar)
	tools:SetAllPoints(bar)
	tools:SetFrameLevel(bar:GetFrameLevel() + 8)
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
	if ccfg.skin then   -- the pool of blood, and the meat's light and shade: dulled, moist, the roll's shadow
		c.poolPool = Pool(function() return ns.Maskable(c, Smooth(c:CreateTexture(nil, "ARTWORK"))) end)
		c.skinMeat = {}
		for i, look in ipairs({ { flip = true, rgb = { 0, 0, 0 }, a = .22 }, { add = true, rgb = { 1, .47, .43 }, a = .12 }, { rgb = { 0, 0, 0 }, a = .55 } }) do
			local tex = ns.Maskable(c, Smooth(c:CreateTexture(nil, "ARTWORK", nil, 1)))
			tex:SetTexture(MEDIA .. "edge_h")
			if look.flip then tex:SetTexCoord(1, 0, 0, 1) end   -- strongest on the left
			tex:SetBlendMode(look.add and "ADD" or "BLEND")
			tex:SetVertexColor(look.rgb[1], look.rgb[2], look.rgb[3], look.a)
			tex:Hide()
			c.skinMeat[i] = tex
		end
	end
	if ccfg.smith or ccfg.smelt then   -- hot metal laid over the fill: blacksmithing's heat, edge and temper; smelting's fresh pour and front
		local function Tex(name, sub, blend, wrap)
			local tex = ns.Maskable(c, Smooth(c:CreateTexture(nil, "ARTWORK", nil, sub)))
			if wrap then tex:SetTexture(MEDIA .. name, "REPEAT", "REPEAT") else tex:SetTexture(MEDIA .. name) end
			tex:SetBlendMode(blend or "BLEND")
			tex:Hide()
			return tex
		end
		c.forge = {}
		if ccfg.smith then
			c.forge.hot = Tex("smith_hot", 1, "BLEND", true)
			c.forge.hot:SetAllPoints(c)
			c.forge.edge = Tex("edge_h", 2, "ADD")                 -- strongest on the right: the cast edge
			c.forge.edge:SetVertexColor(1, .75, .35)
			c.forge.temper = Tex("smith_temper", 4)
			c.forge.temper:SetAllPoints(c)
			c.flarePool = Pool(function() return ns.Maskable(c, Smooth(c:CreateTexture(nil, "ARTWORK"))) end)
		else
			c.forge.hot = Tex("smelt_hot", 1)
			c.forge.front = Tex("p_soft", 2, "ADD")
			c.forge.front:SetVertexColor(1, .7, .3)
		end
	end
end

function FX:LayoutContent(c, w, h)
	W, H = w, h
	if c.sweepTex then c.sweepTex:SetSize(H * 1.0, H * 1.8) end
end

function FX:Layout(w, h) W, H = w, h end

local function ClearAll(keepParticles)
	if not keepParticles then
		wipe(particles)
		particlePool:ReleaseAll()
	end
	linePool:ReleaseAll()
	spritePool:ReleaseAll()
	wipe(twinkles)
	wipe(emitAcc)
	HideSkin()
	HideForge()
	vines, pond, mine, skin, smith, smelt = nil, nil, nil, nil, nil, nil
end

-- Back-to-back casts of the same look (a "Create All" batch) run on from each other: the steam and sparks
-- already in the air stay, and blacksmithing's iron keeps its heat instead of snapping back to cold.
local CARRY_GAP = .6         -- seconds between one cast stopping and the next starting
local stoppedAt              -- when the shown cast stopped (FX:Update)

function FX:Begin(c, w, h)
	W, H = w, h
	local carry = c == content and stoppedAt and clock - stoppedAt < CARRY_GAP
	local heat = carry and smith and smith.heat or nil
	local temper = carry and smith and smith.temper or nil
	stoppedAt = nil
	ClearAll(carry)
	if content and content.arcanePool then content.arcanePool:ReleaseAll() end
	content, cfg = c, c.cfg
	if cfg.vines then MakeVines() end
	if cfg.pond then MakePond() end
	if cfg.mine then MakeMine() end
	if cfg.skin then MakeSkin() end
	if cfg.smith then MakeSmith(heat, temper) end
	if cfg.smelt then MakeSmelt() end
	fx.frontRev:Hide()
	if c.sweepTex then c.sweepT, c.sweep = rand(.4, 1.5), nil; c.sweepTex:Hide() end
	if cfg.glyphs then
		c.arcanePool:ReleaseAll()
		wipe(c.circles); wipe(c.glyphs)
		c.circleNext, c.glyphT = rand(.2, 1.2) * H, 0
	end
end

function FX:Update(dt, t, fillW, casting, state)   -- state: "cast", "done" or "interrupted"
	clock = t
	if not content then return end
	if not casting and not stoppedAt then stoppedAt = clock end
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
	if smith then UpdateSmith(dt, fillW, casting, state) end
	if smelt then UpdateSmelt(dt, fillW, casting) end
	if cfg.freezeReverse then UpdateFrontReverse(fillW) end
	if cfg.glyphs then UpdateArcane(dt, fillW, casting) end
	if cfg.twinkles then UpdateTwinkles(dt, fillW, casting) end
end

-- The interrupted tint fading in (k 0 to 1): greys the pieces that aren't layers, which the bar greys itself.
-- Painted pieces lose their colour; additive glows fade out by (1 - grey) in their Update functions.
function FX:Interrupted(k)
	if skin and roll then
		skin.grey = k
		for _, key in ipairs(ROLL_GREY) do roll[key]:SetDesaturation(k) end
		for _, q in ipairs(skin.pool) do
			q.seep:SetDesaturation(k); q.rim:SetDesaturation(k); q.body:SetDesaturation(k)
		end
	end
	if (smith or smelt) and content and content.forge then
		local o = smith or smelt
		o.grey = k
		content.forge.hot:SetDesaturation(k)
		forge.hammer:SetDesaturation(k); forge.ladle:SetDesaturation(k); forge.stream:SetDesaturation(k)
	end
end

function FX:End()
	ClearAll()
	fx.frontRev:Hide()
	if content and content.arcanePool then content.arcanePool:ReleaseAll() end
end
