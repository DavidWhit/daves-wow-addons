-- daves_castbar / Effects_FirstAid.lua
-- First Aid: an open wound bleeding ahead of the cast, bound up in bandage turns that wrap round it at the cast edge,
-- blood soaking through them. One of the effect files (see Effects.lua): its own 200 top-level locals, the shared
-- helpers from ns.FXi, and its hooks registered at the end.

local _, ns = ...
local I = ns.FXi
local MEDIA, rand, pick, Smooth = I.MEDIA, I.rand, I.pick, I.Smooth
local RGB, PlaceIn, clamp = I.RGB, I.PlaceIn, I.clamp
local content, cfg, W, H, clock = nil, nil, 300, 26, 0   -- the core's state, copied in by sync

---------------------------------------------------------------------------
-- First Aid (the approved concept, tools/concepts/firstaid.js: C for casts, D for channels). The wound is the content's
-- layers: crimson running down the bar (fa_wound scrolling) under a wet shine that holds still (fa_gloss), pulsing
-- brighter on a heartbeat. Broad bandage turns, about one and a half bar heights wide, wrap round it at the cast edge
-- (the content is the whole bar, wholeBar: the turns lean across the fill edge, so they show the progress themselves).
-- Every cast takes a random wrap (spiral, figure-eight, reverse spiral with a fold in each turn, spica, circular), never
-- the last one, a random lean and a random way round; the bandage is always the same. The band is a seventh of the bar's
-- length wide (1.4 to 5 bar heights), so a long bar doesn't take many more turns than a short one.
-- A turn comes round as its band grows along its own length, its end lit, with its shadow on the wound ahead; blood
-- soaks through each turn a moment after it is laid, as blots that keep creeping and dry darker (casts), and soaked
-- turns drip. Beads swell on the wound's lower edge and fall; the heartbeat slows and the bleeding eases as it binds.
-- The bandage roll rides the end of the band, passing behind the limb at the bar's edges, clipped to the bar.
-- Channels (using a bandage) wrap in from the right as the channel drains: laid out the same way and mirrored.
-- Turns lean: each piece of a turn is rotated once, when the cast lays the turns out, and held there (nothing turns
-- while it shows). Each turn has two draw slots (its shadow and band; then its fold, creases, blots and lit end) above
-- the turn before it, in two frames at the content's level + 1 and + 2, under the bevel (Bar.lua, + 6).
---------------------------------------------------------------------------
local CRIM_L = RGB(214, 30, 44)
local DARK = { 74 / 150, 2 / 8, 10 / 24 }         -- fa_drop (painted crimson) tinted to the dark blood
local DRY = { 92 / 150, 1, 16 / 24 }              -- fa_blot (painted fresh) tinted to dried blood
local CLOTH = { base = RGB(238, 230, 214), shade = RGB(170, 156, 132) }   -- the one bandage (Make-CastbarMedia.ps1 FaBand)
local STYLES = { "spiral", "figure8", "reverse", "spica", "circular" }
local lastStyle
local BAND_PER_W, BAND_MIN, BAND_MAX = 1 / 7, 1.4, 5   -- a band's width: a seventh of the bar's length, 1.4 to 5 bar heights
local LAYERS = { "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY" }   -- 64 draw slots a frame
local PER_FRAME = 30                 -- turns a frame, two slots each; the last four slots of the top frame hold the overlays
local TURNS_MAX = PER_FRAME * 2      -- an 800 x 20 bar needs about 50
local BAND_SPAN = 4                  -- fa_band*: four band widths long (Make-CastbarMedia.ps1 FA_BAND_L / FA_BAND_W)
local ROLL_W, ROLL_D = 1.16, 1.6     -- fa_roll spans this many roll widths by roll thicknesses, the roll centred
local DROP_W, DROP_HEAD = 32 / 13, 14 / 64   -- fa_drop: width in head radii; its head's centre below the sprite's centre (of its height)
local CREASE_TILT = math.atan(.08)
local SOAK_STEP = 1 / 30             -- the blots grow slowly: placed 30 times a second, not every frame
local BEADS_MAX, DROPS_MAX = 4, 40
local fa                             -- this cast's state
local rollFrame, roll                -- the bandage roll, on a frame clipped to the bar (init)

local function Heartbeat(t, rate)    -- lub-dub: two soft bumps a beat
	local ph = (t * rate) % 1
	local a, b = (ph - .05) / .05, (ph - .25) / .055
	return math.exp(-a * a) + .6 * math.exp(-b * b)
end
local function easeOut(t) return 1 - (1 - t) * (1 - t) end

-- The draw layer and sublevel of turn i's slot k (0: shadow and band; 1: fold, creases, blots, lit end) in its frame.
local function Slot(i, k)
	local s = ((i - 1) % PER_FRAME) * 2 + k
	return LAYERS[math.floor(s / 16) + 1], (s % 16) - 8
end

-- A point of turn t in its own frame (lx across the band, ly along it, growing down the band as in the concept), in bar
-- pixels from the bottom-left; mirrored for a channel.
local function Pt(t, lx, ly)
	local x = t.cx + lx * t.ca - ly * t.sa
	if fa.mirror then x = W - x end
	return x, H / 2 - lx * t.sa - ly * t.ca
end
-- A piece of turn t centred at (lx, ly) in the turn's frame, w across and h along (it is rotated with the turn).
local function Place(tex, t, lx, ly, w, h)
	local x, y = Pt(t, lx, ly)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", content, "BOTTOMLEFT", x, y)
	tex:SetSize(math.max(.1, w), math.max(.1, h))
end
local function Flip(tex, u0, u1, v0, v1)   -- texcoords, mirrored across for a channel
	if fa.mirror then u0, u1 = u1, u0 end
	tex:SetTexCoord(u0, u1, v0, v1)
end

local function HideTurn(T)
	T.shadow:Hide(); T.band:Hide(); T.fold:Hide(); T.lip:Hide(); T.lipShade:Hide()
	for j = 1, 4 do T.crease[j]:Hide() end
	T.blot[1]:Hide(); T.blot[2]:Hide()
end

local function HideFirstAid()
	if roll then roll:Hide() end
	if fa then   -- (Effects.lua has released the sprites already; this keeps the pool's books straight if not)
		for _, d in ipairs(fa.drops) do I.spritePool:Release(d.tex) end
		for _, b in ipairs(fa.beads) do I.spritePool:Release(b.tex) end
	end
	local c = content and content.fa
	if c then
		for i = 1, TURNS_MAX do HideTurn(c.turns[i]) end
		c.pulse:SetAlpha(0); c.flash:SetAlpha(0); c.round:Hide()
	end
end

---------------------------------------------------------------------------
-- Laying out a cast
---------------------------------------------------------------------------
local function LayOut(style, A, lean)
	local bw, turns = fa.bw, fa.turns
	local x, i = -bw * .55, 0
	local function Add(cx, a, fold)
		local t = { cx = cx, a = a + rand(-.05, .05), fold = fold, wx = rand(.93, 1.06), off = rand(0, BAND_SPAN * bw - fa.L), laid = -1, r = -1, creases = {} }
		for j = 1, math.random() < .5 and 1 or 2 do
			t.creases[j] = { x = rand(-.32, .32) * bw, y = rand(-.4, .2) * H, l = H * rand(.2, .5) }
		end
		turns[#turns + 1] = t
	end
	while x < W + bw and #turns < TURNS_MAX do
		local alt = i % 2 == 1 and -1 or 1
		if style == "figure8" then Add(x, A * lean * alt); x = x + bw * (i % 2 == 1 and .75 or .5)   -- crossing pairs: an X, then the next
		elseif style == "spica" then Add(x, A * lean * alt); x = x + bw * .62                       -- alternating leans: a herringbone of Vs
		elseif style == "reverse" then Add(x, A * lean, true); x = x + bw * rand(.8, .88)           -- each turn folded back on itself
		elseif style == "circular" then Add(x, 0); x = x + bw * rand(.84, .9)                       -- straight round, overlapping
		else Add(x, A * lean); x = x + bw * rand(.82, .88) end                                       -- spiral
		i = i + 1
	end
	local prev = -math.huge   -- where along the cast each turn starts and ends coming round
	for _, t in ipairs(turns) do
		t.ws = math.max(t.cx - bw * .45, prev)
		t.we = math.max(t.cx + bw * .15, t.ws + bw * .3)
		prev = t.we
	end
	local soak = fa.o.soak or 1
	for _, t in ipairs(turns) do   -- the blots that soak through each turn once it is laid
		t.blots = {}
		local n = soak > 1 and (math.random() < .5 and 1 or 2) or (math.random() < .65 and 1 or 0)
		for j = 1, n do
			local xl = rand(-.06, .06) * bw
			local room = (bw * .5 - math.abs(xl)) / (soak > 1 and 1.35 or 1)
			local rx = math.min(room * 1.15, H * (soak > 1 and rand(.28, .36) or rand(.2, .3)))
			t.blots[j] = { xl = xl, yl = rand(-.18, .18) * H, rx = rx, ry = rx * (soak > 1 and rand(1.6, 2.2) or rand(1.3, 1.9)),
				cell = math.random(0, 3), fx = math.random() < .5, fy = math.random() < .5, a = rand(.75, .95), delay = rand(.15, .9), dur = rand(1.4, 2.6) }
		end
	end
end

local function MakeFirstAid()
	local c, o = content.fa, cfg.firstaid
	local style
	repeat style = STYLES[math.random(#STYLES)] until style ~= lastStyle
	lastStyle = style
	local cl = CLOTH
	local A = style == "circular" and .05 or rand(.32, .46)
	-- the band's width follows the bar's length, so a long bar takes about as many turns as a short one
	local bw = math.max(BAND_MIN * H, math.min(BAND_MAX * H, W * BAND_PER_W)) * rand(.93, 1.07)
	fa = { o = o, cl = cl, style = style, bw = bw, L = H / math.cos(A + .08) + bw * math.tan(A + .08) + 4,
		up = math.random() < .5, mirror = o.channel, sh = H * .09, turns = {}, beads = {}, drops = {}, start = clock,
		grey = 0, soakAcc = SOAK_STEP }
	LayOut(style, A, pick({ -1, 1 }))
	-- each turn's pieces: textures, lean, the parts that never move
	local lit = { cl.base[1] + (1 - cl.base[1]) * .5, cl.base[2] + (1 - cl.base[2]) * .5, cl.base[3] + (1 - cl.base[3]) * .5 }
	for i, t in ipairs(fa.turns) do
		local T = c.turns[i]
		t.ca, t.sa = math.cos(t.a), math.sin(t.a)
		t.rot = fa.mirror and t.a or -t.a   -- the concept turns clockwise; SetRotation turns anticlockwise
		T.lip:SetColorTexture(lit[1], lit[2], lit[3], .75)   -- (its colour before its lean, as the creases)
		for _, tex in ipairs({ T.shadow, T.band, T.fold, T.lip, T.lipShade, T.blot[1], T.blot[2] }) do
			tex:SetRotation(t.rot)
			tex:SetDesaturation(0)
		end
		Flip(T.shadow, 0, 1, 0, 1)
		if fa.up then Flip(T.lipShade, 0, 1, 1, 0) else Flip(T.lipShade, 0, 1, 0, 1) end
		local crot = fa.mirror and (t.a - CREASE_TILT) or -(t.a - CREASE_TILT)
		for j = 1, 2 do
			local cr, dark, light = t.creases[j], T.crease[j * 2 - 1], T.crease[j * 2]
			if cr then
				local w = math.max(.5, H * .015)
				dark:SetColorTexture(cl.shade[1], cl.shade[2], cl.shade[3], .45)
				light:SetColorTexture(1, 1, 1, .35)
				dark:SetRotation(crot); light:SetRotation(crot)
				Place(dark, t, (cr.x + cr.l * .04) * t.wx, cr.y + cr.l / 2, w, cr.l)
				Place(light, t, (cr.x + .8 + cr.l * .04) * t.wx, cr.y + cr.l / 2, w, cr.l)
			end
		end
		for j, b in ipairs(t.blots) do
			local u0, u1, v0, v1 = b.cell / 4, (b.cell + 1) / 4, 0, 1
			if b.fx then u0, u1 = u1, u0 end
			if b.fy then v0, v1 = v1, v0 end
			Flip(T.blot[j], u0, u1, v0, v1)
			T.blot[j]:SetVertexColor(1, 1, 1)
		end
	end
	c.round:Show()
	if roll then
		roll:SetVertexColor(cl.base[1], cl.base[2], cl.base[3])
		roll:SetDesaturation(0)
		Flip(roll, 0, 1, 0, 1)
		fa.rollLead = nil
	end
end

---------------------------------------------------------------------------
-- Every frame
---------------------------------------------------------------------------
-- Turn i at r (0..1 of the way round): the band grown along its length from the end it starts at, its shadow on the
-- turn before, the fold cut to what has come round, and while it comes round, its lit end and that end's shadow ahead.
local function DrawTurn(T, t, r)
	if r <= 0 then HideTurn(T); return end
	local bw, L, wx = fa.bw, fa.L, t.wx
	local hl, len = L / 2, r * L
	local y0 = fa.up and (hl - len) or -hl
	local ym = y0 + len / 2
	Place(T.band, t, 0, ym, bw * wx, len)
	local v0 = (t.off + y0 + hl) / (BAND_SPAN * bw)
	Flip(T.band, 0, 1, v0, v0 + len / (BAND_SPAN * bw))
	T.band:Show()
	Place(T.shadow, t, (-bw / 2 - fa.sh / 2) * wx, ym, fa.sh * wx, len)
	T.shadow:Show()
	if t.fold then
		local yf = (fa.up and 1 or -1) * H * .1
		local a0, a1 = math.max(yf - bw / 2, y0), math.min(yf + bw / 2, y0 + len)
		if a1 - a0 > .5 then
			Place(T.fold, t, 0, (a0 + a1) / 2, bw * wx, a1 - a0)
			Flip(T.fold, 0, 1, (a0 - yf + bw / 2) / bw, (a1 - yf + bw / 2) / bw)
			T.fold:Show()
		else
			T.fold:Hide()
		end
	end
	local laid = r >= 1
	if not laid and t.laid >= 0 then   -- pushback unwound it: it soaks again once it is laid again
		t.laid, t.soaked = -1, nil
		T.blot[1]:Hide(); T.blot[2]:Hide()
		for _, b in ipairs(t.blots) do b.placed, b.faded = nil, nil end
	end
	for j = 1, 2 do T.crease[j * 2 - 1]:SetShown(laid and t.creases[j] ~= nil); T.crease[j * 2]:SetShown(laid and t.creases[j] ~= nil) end
	T.lip:SetShown(not laid); T.lipShade:SetShown(not laid)
	if not laid then
		local ty, sd = fa.up and y0 or y0 + len, H * .07
		Place(T.lip, t, 0, fa.up and ty + H * .015 or ty - H * .015, bw * wx, H * .03)
		Place(T.lipShade, t, 0, fa.up and ty - sd / 2 or ty + sd / 2, bw * wx, sd)
	end
end

-- The blots soaking through a laid turn: they grow in, keep creeping when soaked, and dry darker; done once they settle.
-- A blot's centre never moves, so it is anchored once and then only resized, faded in and tinted while those change.
local function SoakTurn(T, t)
	local o, settled = fa.o, true
	local creep = o.soak > 1 and 5 or 0
	for j, b in ipairs(t.blots) do
		local age = clock - t.laid - b.delay
		local tex = T.blot[j]
		if age <= 0 then settled = false else
			if not b.placed then
				b.placed = true
				local x, y = Pt(t, b.xl * t.wx, b.yl)
				tex:ClearAllPoints()
				tex:SetPoint("CENTER", content, "BOTTOMLEFT", x, y)
				tex:Show()
			end
			if age < b.dur + creep then
				local gr = easeOut(clamp(age / b.dur))
				if creep > 0 then gr = gr * (1 + .35 * clamp((age - b.dur) / creep)) end
				tex:SetSize(math.max(.1, b.rx * gr * 2 * t.wx), math.max(.1, b.ry * gr * 2))
				settled = false
			end
			if not b.faded then tex:SetAlpha(clamp(age / .4) * b.a); b.faded = age >= .4; settled = false end
			local d0 = b.dur * .5
			if o.dry and age > d0 and age < d0 + 6.05 then   -- as the concept's dried blot laid over the fresh one
				local k = clamp((age - d0) / 6) * .85
				tex:SetVertexColor(1 + (DRY[1] - 1) * k, 1, 1 + (DRY[3] - 1) * k)
				settled = false
			elseif o.dry and age <= d0 then
				settled = false
			end
		end
	end
	t.soaked = settled
end

local function Drop(x, y, vy, life, r, dark)
	if #fa.drops >= DROPS_MAX then return end
	local tex = I.Sprite("fa_drop", 6)
	if dark then tex:SetVertexColor(DARK[1], DARK[2], DARK[3]) end
	tex:SetDesaturation(fa.grey)
	fa.drops[#fa.drops + 1] = { tex = tex, x = x, y = y, vy = vy, age = 0, life = life, r = r }
end

-- Drops falling off the bottom of the open wound and the soaked turns, and beads swelling on the wound's lower edge.
local function Bleed(dt, f, casting)
	local o, bw = fa.o, fa.bw
	local bleed = (o.bleed or 1) * fa.calm
	if casting and W - f > 0 and math.random() < dt * ((W - f) / H) * .5 * bleed * (.4 + fa.beat) then
		Drop(rand(math.max(0, f), W), 0, H * rand(.2, .5), rand(.45, .8), H * rand(.025, .045), math.random() < .5)
	end
	if o.soak > 1 and math.random() < dt * .8 then
		local n, pickT = 0, nil
		for _, t in ipairs(fa.turns) do
			if t.laid >= 0 and clock - t.laid > 1.5 and t.cx > 0 and t.cx < W then
				n = n + 1
				if math.random(n) == 1 then pickT = t end
			end
		end
		if pickT then Drop(pickT.cx + rand(-.2, .2) * bw, 0, H * .3, .6, H * .03, true) end
	end
	local rate = bleed * (.6 + fa.beat * .6)
	for i = #fa.beads, 1, -1 do   -- bound up: gone
		local b = fa.beads[i]
		if b.x <= f + bw * .2 then I.spritePool:Release(b.tex); table.remove(fa.beads, i) end
	end
	local lo, hi = f + bw * .4, W - H * .25
	if casting and #fa.beads < BEADS_MAX and hi > lo and W - f > H * .6 and math.random() < dt * rate * 1.2 then
		local tex = I.Sprite("fa_drop", 6)
		tex:SetVertexColor(.9, .85, .88)   -- a little darker than a falling drop
		tex:SetDesaturation(fa.grey)
		fa.beads[#fa.beads + 1] = { tex = tex, x = rand(lo, hi), age = 0, life = rand(.7, 1.5), r = H * rand(.045, .07) }
	end
	for _, b in ipairs(fa.beads) do
		b.age = b.age + dt
		if b.age >= b.life then
			Drop(b.x, -b.r * 1.6, H * .5, rand(.4, .7), b.r * .8)
			b.age, b.life = 0, rand(.7, 1.5) / math.max(.25, rate)
		end
		-- fa_drop stretched to hang: its tip (6 px down its 64) a pixel inside the bar, its head's centre (46 px down) hang below it
		local k = clamp(b.age / b.life)
		local r = b.r * (.35 + .65 * k)
		local h = (1 + r * (.4 + 1.3 * k * k)) * 64 / 40
		b.tex:ClearAllPoints()
		b.tex:SetPoint("TOP", I.fx, "BOTTOMLEFT", fa.mirror and W - b.x or b.x, 1 + h * 6 / 64)
		b.tex:SetSize(r * DROP_W, h)
	end
	for i = #fa.drops, 1, -1 do
		local d = fa.drops[i]
		d.age = d.age + dt
		if d.age >= d.life then
			I.spritePool:Release(d.tex); table.remove(fa.drops, i)
		else
			d.vy = d.vy + H * 9 * dt
			d.y = d.y - d.vy * dt
			local t, w = d.age / d.life, d.r * DROP_W
			d.tex:SetAlpha(1 - t * t)
			PlaceIn(d.tex, I.fx, fa.mirror and W - d.x or d.x, d.y + w * 2 * DROP_HEAD, w, w * 2)
		end
	end
end

-- The roll at the end of the band coming round now: smaller as the cast uses it up, squashed and fading as it passes
-- behind the limb at the bar's edges, gone when the cast ends.
local function DrawRoll(p, casting)
	local lead, lr
	for _, t in ipairs(fa.turns) do if t.r > 0 then lead, lr = t, t.r end end
	if not lead then roll:Hide(); return end
	local L, bw = fa.L, fa.bw
	local tip = fa.up and (L / 2 - lr * L) or (-L / 2 + lr * L)
	local x, y = Pt(lead, 0, tip)
	local v = clamp((H * .55 - math.abs(y - H / 2)) / (H * .25))
	if not casting then fa.endAt = fa.endAt or clock; v = v * clamp(1 - (clock - fa.endAt) / .3) end
	if v <= 0 then roll:Hide(); return end
	if fa.rollLead ~= lead then fa.rollLead = lead; roll:SetRotation(lead.rot) end
	local d, w = H * (.44 - .2 * p) * (.7 + .3 * v), bw * 1.04
	PlaceIn(roll, rollFrame, x, y, w * ROLL_W, d * ROLL_D)
	roll:SetAlpha(v)
	roll:Show()
end

local function UpdateFirstAid(dt, fillW, casting, state)
	local c, o, bw = content.fa, fa.o, fa.bw
	local f0 = fa.mirror and W - fillW or fillW      -- how much is bound, from the end it starts at
	local p = clamp(f0 / W)
	local f = f0 * (W + bw * .9) / W                 -- the last turns past the bar's end are laid by the finish
	fa.calm = o.calm and 1 - p * .8 or 1
	fa.beat = Heartbeat(clock - fa.start, o.calm and 1.2 - p * .45 or 1.2) * fa.calm
	c.pulse:SetAlpha(.24 * fa.beat * (o.bleed or 1) * (1 - fa.grey))
	fa.soakAcc = fa.soakAcc + dt
	local soak = fa.soakAcc >= SOAK_STEP
	if soak then fa.soakAcc = 0 end
	for i, t in ipairs(fa.turns) do
		local r = clamp((f - t.ws) / (t.we - t.ws))
		if r ~= t.r then t.r = r; DrawTurn(c.turns[i], t, r) end
		if r >= 1 and t.laid < 0 then t.laid = clock end
		if soak and t.laid >= 0 and not t.soaked then SoakTurn(c.turns[i], t) end
	end
	if state == "done" then   -- the bar's own flash lies under the turns: a calm one over them
		fa.doneAt = fa.doneAt or clock
		c.flash:SetAlpha(math.max(0, 1 - (clock - fa.doneAt) / .35) * (cfg.flashAlpha or .3))
	end
	Bleed(dt, f, casting)
	if roll then DrawRoll(p, casting) end
end

---------------------------------------------------------------------------
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "firstaid",
	init = function()
		-- the roll's own frame: over the frame line like the shared tools frame, clipped to the bar and to its corners
		rollFrame = CreateFrame("Frame", nil, I.tools)
		rollFrame:SetAllPoints(I.tools)
		rollFrame:SetFrameLevel(I.tools:GetFrameLevel())
		rollFrame:SetClipsChildren(true)
		ns.MaskAllTextures(rollFrame)
		roll = Smooth(rollFrame:CreateTexture(nil, "ARTWORK"))
		roll:SetTexture(MEDIA .. "fa_roll")
		roll:Hide()
	end,
	sync = function(c, cf, w, h, t) content, cfg, W, H, clock = c, cf, w, h, t end,
	create = function(c)
		if not c.cfg.firstaid then return end
		local f = { frames = {}, turns = {} }
		f.pulse = c:CreateTexture(nil, "ARTWORK", nil, 2)   -- the heartbeat, over the wound and under the turns
		f.pulse:SetAllPoints(c)
		f.pulse:SetColorTexture(1, 1, 1, 1)
		f.pulse:SetBlendMode("ADD")
		f.pulse:SetVertexColor(CRIM_L[1], CRIM_L[2], CRIM_L[3])
		f.pulse:SetAlpha(0)
		for b = 1, 2 do   -- the turns' two frames, the second above the first, both reaching the bar's corners
			local bf = CreateFrame("Frame", nil, c)
			bf:SetAllPoints(c)
			bf:SetFrameLevel(c:GetFrameLevel() + b)
			ns.MaskAllTextures(bf)
			f.frames[b] = bf
		end
		for i = 1, TURNS_MAX do
			local bf = f.frames[math.floor((i - 1) / PER_FRAME) + 1]
			local function Tex(k, file)
				local layer, sub = Slot(i, k)
				local tex = Smooth(bf:CreateTexture(nil, layer, nil, sub))
				if file then tex:SetTexture(MEDIA .. file) end
				tex:Hide()
				return tex
			end
			local T = { crease = {} }
			T.shadow = Tex(0, "edge_h"); T.shadow:SetVertexColor(30 / 255, 10 / 255, 6 / 255, .4)
			T.band = Tex(0, "fa_band")   -- (its shadow lies beside it, on the turn before: the same slot is safe)
			T.fold = Tex(1, "fa_fold")
			for j = 1, 4 do T.crease[j] = Tex(1) end
			T.blot = { Tex(1, "fa_blot"), Tex(1, "fa_blot") }
			T.lip = Tex(1)    -- (only while the turn comes round; the creases and blots only once it is laid)
			T.lipShade = Tex(1, "bevel_v"); T.lipShade:SetVertexColor(20 / 255, 0, 2 / 255, .55)
			f.turns[i] = T
		end
		local top = f.frames[2]   -- over every turn, in the top frame's last slots: the limb's roundness, the flash
		f.round = top:CreateTexture(nil, "OVERLAY", nil, 5)
		f.round:SetTexture(MEDIA .. "fa_round")
		f.round:SetAllPoints(c)
		f.round:Hide()
		f.flash = top:CreateTexture(nil, "OVERLAY", nil, 7)
		f.flash:SetAllPoints(c)
		f.flash:SetColorTexture(1, 1, 1, 1)
		f.flash:SetBlendMode("ADD")
		f.flash:SetVertexColor(c.cfg.spark[1], c.cfg.spark[2], c.cfg.spark[3])
		f.flash:SetAlpha(0)
		c.fa = f
	end,
	begin = function() if cfg.firstaid then MakeFirstAid() end end,
	update = function(dt, fillW, casting, state, t)
		clock = t
		if fa then UpdateFirstAid(dt, fillW, casting, state) end
	end,
	interrupted = function(k)
		if not (fa and content and content.fa) then return end
		fa.grey = k   -- the wound greys with the bar's layers; the bandage, blood and roll here
		for i = 1, #fa.turns do
			local T = content.fa.turns[i]
			for _, tex in ipairs({ T.band, T.fold, T.lip, T.blot[1], T.blot[2] }) do tex:SetDesaturation(k) end
		end
		for _, d in ipairs(fa.drops) do d.tex:SetDesaturation(k) end
		for _, b in ipairs(fa.beads) do b.tex:SetDesaturation(k) end
		if roll then roll:SetDesaturation(k) end
	end,
	clear = function()
		HideFirstAid()
		fa = nil
	end,
})
