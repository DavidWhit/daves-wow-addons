-- daves_castbar / Effects_Gathering.lua
-- The gathering looks' live pieces: fishing (lily pads and fish in the pond, the bobber and its ripples at the
-- cast edge), mining (the gem cart rolling to the cast edge, a pickaxe striking the wall at the end) and
-- skinning (the pelt rolling back over marbled meat at the cast edge, a pool of blood, the knife sawing along
-- the roll). One of the effect files (see Effects.lua): its own 200 top-level locals, the shared helpers from
-- ns.FXi, and its hooks registered at the end.

local _, ns = ...
local I = ns.FXi
local MEDIA, rand, PI, pick = I.MEDIA, I.rand, I.PI, I.pick
local Smooth, Pool, Spawn, Sprite, PlaceSprite = I.Smooth, I.Pool, I.Spawn, I.Sprite, I.PlaceSprite
local RGB, ToolTexture, PlaceIn, Band = I.RGB, I.ToolTexture, I.PlaceIn, I.Band
local fx, tools, linePool, spritePool     -- the frames and pools the core makes (init)
local content, cfg, W, H, clock = nil, nil, 300, 26, 0   -- the core's state, copied in by sync

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
	local railY = H * .08    -- the top of the near rail, at the very bottom of the bar (mine_rails has no ground strip)
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
	-- the cart: its front at the fill edge, wheels on the rail, lantern glowing; sized so the ore heap stays
	-- inside the bar (p_cart: box v .40-.80, ore up to about v .2)
	local C = H * 1.0
	local wr = C * .13
	local cx = math.max(-C * .2, fillW - C * .94)
	for i, u in ipairs(WHEEL_U) do
		PlaceSprite(mine.wheels[i], cx + C * u, railY + wr, wr * 2, -fillW / wr)
	end
	local cy = railY + 1.1 * wr + .30 * C                                -- the cart's centre
	PlaceSprite(mine.cart, cx + C / 2, cy, C, 0)
	PlaceSprite(mine.lantern, cx + C * .80, cy - C * .10, H * (.9 + .1 * math.sin(clock * 11)), 0)
end

---------------------------------------------------------------------------
-- Skinning: the pelt rolls back over marbled meat. Ahead of the cast lies the fur (the track,
-- tinted to this cast's pelt through ns.TintTrack); at the cast edge the hide rolls up on itself,
-- growing as it goes; behind it lies the meat (the fill layer), a pool of blood spreads behind the
-- knife, and the knife stands against the roll, its edge on the roll, sawing up and down and lifting away when the cast ends. The roll and the knife
-- stand on `tools`, a frame above the bar's frame line; nothing here turns, it only moves and grows.
---------------------------------------------------------------------------
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
	-- the coat ahead of the roll lies in its shadow for a little way; it lives on the track, under the
	-- fill, with the fur it darkens
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


local function UpdateSkin(dt, fillW, casting)
	local r = H * (.2 + .16 * fillW / W)
	local xc = fillW - r * .9
	-- blood wells up just behind the knife as it goes, and the pool keeps spreading behind it. Only while the
	-- fill grows: skinning given to a channel drains, the roll runs back, and no pool rushes in at the start
	local growing = fillW > (skin.reach or fillW)
	skin.reach = math.max(skin.reach or fillW, fillW)
	while casting and growing and xc - r * 1.6 > skin.poolNext and #skin.pool < POOL_MAX do
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
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "gathering",
	init = function() fx, tools, linePool, spritePool = I.fx, I.tools, I.linePool, I.spritePool end,
	sync = function(c, cf, w, h, t) content, cfg, W, H, clock = c, cf, w, h, t end,
	create = function(c)
		local ccfg = c.cfg
		if ccfg.skin then   -- the pool of blood, and the meat's light and shade: dulled, moist, the roll's shadow
			c.poolPool = Pool(function() return Smooth(c:CreateTexture(nil, "ARTWORK")) end)
			c.skinMeat = {}
			for i, look in ipairs({ { flip = true, rgb = { 0, 0, 0 }, a = .22 }, { add = true, rgb = { 1, .47, .43 }, a = .12 }, { rgb = { 0, 0, 0 }, a = .55 } }) do
				local tex = Smooth(c:CreateTexture(nil, "ARTWORK", nil, 1))
				tex:SetTexture(MEDIA .. "edge_h")
				if look.flip then tex:SetTexCoord(1, 0, 0, 1) end   -- strongest on the left
				tex:SetBlendMode(look.add and "ADD" or "BLEND")
				tex:SetVertexColor(look.rgb[1], look.rgb[2], look.rgb[3], look.a)
				tex:Hide()
				c.skinMeat[i] = tex
			end
		end
	end,
	begin = function()
		if cfg.pond then MakePond() end
		if cfg.mine then MakeMine() end
		if cfg.skin then MakeSkin() end
	end,
	update = function(dt, fillW, casting, _, t)
		clock = t
		if pond then UpdatePond(dt, fillW, casting) end
		if mine then UpdateMine(dt, fillW, casting) end
		if skin then UpdateSkin(dt, fillW, casting) end
	end,
	interrupted = function(k)
		if skin and roll then
			skin.grey = k
			for _, key in ipairs(ROLL_GREY) do roll[key]:SetDesaturation(k) end
			for _, q in ipairs(skin.pool) do
				q.seep:SetDesaturation(k); q.rim:SetDesaturation(k); q.body:SetDesaturation(k)
			end
		end
	end,
	clear = function()
		HideSkin()
		pond, mine, skin = nil, nil, nil
	end,
})
