-- daves_castbar / Effects_Spells.lua
-- The spell looks' live pieces: frost (the freeze front where the water ahead turns to ice, a glint sweeping
-- across), nature and herbalism (vines that grow with the cast, twisting around each other, with leaves, thorns
-- and flowers), arcane (rune circles at random heights and sizes, held still; glyphs flare up) and holy
-- (four-point stars twinkling in and out). One of the effect files (see Effects.lua): its own 200 top-level
-- locals, the shared helpers from ns.FXi, and its hooks registered at the end.

local _, ns = ...
local I = ns.FXi
local MEDIA, rand, PI, pick, easeOutBack = I.MEDIA, I.rand, I.PI, I.pick, I.easeOutBack
local Smooth, Pool, Spawn, Sprite, PlaceSprite = I.Smooth, I.Pool, I.Spawn, I.Sprite, I.PlaceSprite
local fx                                  -- the unclipped frame over the bar (init)
local content, cfg, W, H, clock = nil, nil, 300, 26, 0   -- the core's state, copied in by sync

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
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "spells",
	init = function() fx, linePool, spritePool = I.fx, I.linePool, I.spritePool end,
	sync = function(c, cf, w, h, t) content, cfg, W, H, clock = c, cf, w, h, t end,
	create = function(c)
		local ccfg = c.cfg
		if ccfg.freeze then   -- the freeze front: rime feathering in from the fill edge
			c.front = Smooth(c:CreateTexture(nil, "ARTWORK", nil, 6))
			c.front:SetTexture(MEDIA .. "frost_front"); c.front:SetBlendMode("ADD")
			c.front:Hide()
		end
		if ccfg.sweep then
			c.sweepTex = Smooth(c:CreateTexture(nil, "ARTWORK", nil, 7))
			c.sweepTex:SetTexture(MEDIA .. "sweep"); c.sweepTex:SetBlendMode("ADD")
			c.sweepTex:SetVertexColor(.86, .96, 1)
			c.sweepTex:SetRotation(-.55)
			c.sweepTex:Hide()
		end
		if ccfg.glyphs then
			c.arcanePool = Pool(function() return Smooth(c:CreateTexture(nil, "ARTWORK")) end)
			c.circles, c.glyphs = {}, {}
		end
	end,
	begin = function()
		if cfg.vines then MakeVines() end
		fx.frontRev:Hide()
		if content.sweepTex then content.sweepT, content.sweep = rand(.4, 1.5), nil; content.sweepTex:Hide() end
		if cfg.glyphs then
			content.arcanePool:ReleaseAll()
			wipe(content.circles); wipe(content.glyphs)
			content.circleNext, content.glyphT = rand(.2, 1.2) * H, 0
		end
	end,
	update = function(dt, fillW, casting, _, t)
		clock = t
		if vines then
			if casting then GrowVines(fillW) end
			UpdateVines(fillW)
		end
		if cfg.freeze or cfg.sweep then UpdateFrost(dt, fillW) end
		if cfg.freezeReverse then UpdateFrontReverse(fillW) end
		if cfg.glyphs then UpdateArcane(dt, fillW, casting) end
		if cfg.twinkles then UpdateTwinkles(dt, fillW, casting) end
	end,
	clear = function()
		wipe(twinkles)
		vines = nil
		if content and content.arcanePool then content.arcanePool:ReleaseAll() end
		if fx then fx.frontRev:Hide() end
	end,
})
