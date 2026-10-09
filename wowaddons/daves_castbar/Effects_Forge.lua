-- daves_castbar / Effects_Forge.lua
-- Blacksmithing (the iron heating toward the cast edge, the forge hammer striking it, steam, the quench at the
-- end) and smelting (a forged ladle riding the cast edge, pouring a stream that lands and cools to crust behind
-- it). One of the effect files (see Effects.lua): its own 200 top-level locals, the shared helpers from ns.FXi,
-- and its hooks registered at the end.

local _, ns = ...
local I = ns.FXi
local MEDIA, rand, PI = I.MEDIA, I.rand, I.PI
local Smooth, Pool, Spawn = I.Smooth, I.Pool, I.Spawn
local RGB, ToolTexture, PlaceIn, Band = I.RGB, I.ToolTexture, I.PlaceIn, I.Band
local fx, tools                           -- the frames the core makes (init)
local content, cfg, W, H, clock = nil, nil, 300, 26, 0   -- the core's state, copied in by sync
local carryHeat, carryTemper              -- what the last cast ended at, when the next follows straight on (clear, begin)

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
local FORGE_PARTS = { "hammer", "stream", "ladle", "spout", "flash", "land", "nose" }
local LADLE_PARTS = { "ladle", "spout", "stream", "nose" }
local QUENCH_MAX = 60        -- steam puffs in the quench burst at most (a long, thin bar would want hundreds)
-- Heat colours, as the concepts and Make-CastbarMedia.ps1 IRON_HEAT / MELT_HEAT: { heat, r, g, b }.
local IRON_HEAT = { { 0, 42, 34, 32 }, { .22, 104, 20, 10 }, { .45, 190, 46, 12 }, { .66, 245, 118, 28 }, { .85, 255, 196, 84 }, { 1.05, 255, 246, 214 }, { 1.3, 255, 255, 250 } }
local MELT_HEAT = { { 0, 52, 50, 56 }, { .16, 84, 38, 26 }, { .34, 165, 42, 14 }, { .52, 228, 92, 18 }, { .72, 255, 160, 44 }, { .88, 255, 208, 104 }, { 1, 255, 228, 150 } }
local function HeatRGB(ramp, t)
	if t <= ramp[1][1] then local s = ramp[1]; return s[2] / 255, s[3] / 255, s[4] / 255 end
	for i = 2, #ramp do
		local b = ramp[i]
		if t <= b[1] then
			local a = ramp[i - 1]
			local k = (t - a[1]) / (b[1] - a[1])
			return (a[2] + (b[2] - a[2]) * k) / 255, (a[3] + (b[3] - a[3]) * k) / 255, (a[4] + (b[4] - a[4]) * k) / 255
		end
	end
	local s = ramp[#ramp]
	return s[2] / 255, s[3] / 255, s[4] / 255
end
-- The pour cools over E pixels per e-fold, as the concept: temp = exp(-(land - x) / E), E = W * cool + 1.2 H.
-- SmeltHot spans 3.2 e-folds (it turns clear from about 0.4 heat down, where the crust shows through).
local function SmeltFold() return W * smelt.cool + H * 1.2 end
local function SmeltSpan() return 3.2 * SmeltFold() end
local SEAM_SEGS = 5          -- the seams' glow is drawn in this many gradient segments, so it follows the exponential

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
	-- the glow at the pour's nose: on a frame clipped to the bar but not to the fill, so it spills over the dark track
	-- ahead of the nose as the concept's does, instead of being cut off in a line at the fill edge
	forge.clip = CreateFrame("Frame", nil, fx)
	forge.clip:SetAllPoints(fx)
	forge.clip:SetFrameLevel(fx:GetFrameLevel())
	forge.clip:SetClipsChildren(true)
	forge.nose = ns.MaskCorners(Smooth(forge.clip:CreateTexture(nil, "ARTWORK", nil, 3)))   -- it reaches the right corners at the end
	forge.nose:SetTexture(MEDIA .. "p_soft"); forge.nose:SetBlendMode("ADD"); forge.nose:SetVertexColor(1, .7, .3); forge.nose:Hide()
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
	f.hot:SetDesaturation(0); f.edge:SetDesaturation(0)
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

	-- heat: the iron warms from .2 to .6 as the cast goes on (smith_hot is the .6 iron over the .2), and the cast
	-- edge is .4 hotter still, falling off over 1.1 bar heights (smith_edge, tinted to the edge's heat)
	f.hot:SetAlpha(math.max(0, math.min(1, (base - .2) / .4)) * (1 - q) * cool)
	Band(f.edge, fillW - H * 4.4, fillW)
	f.edge:SetTexCoord(math.max(0, 1 - fillW / (H * 4.4)), 1, 0, 1)   -- the falloff stays anchored to the edge
	f.edge:SetVertexColor(HeatRGB(IRON_HEAT, base + .4 * cool))
	f.edge:SetAlpha((1 - q) * cool)
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
	local e = .5 / 512                    -- half a texel in, so a neighbouring pose never bleeds along the edge
	forge.hammer:SetTexCoord(col / 4 + e, (col + 1) / 4 - e, row / 4 + e, (row + 1) / 4 - e)
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
	for i = 1, SEAM_SEGS do content.forge["seam" .. i]:SetDesaturation(0) end
	content.forge.hot:Show()
end

local function UpdateSmelt(dt, fillW, casting)
	local f = content.forge
	if not casting and not smelt.endAt then smelt.endAt = clock end
	local since = smelt.endAt and clock - smelt.endAt or 0
	local back = smelt.endAt and 1 - (1 - math.min(1, since / .5)) ^ 2 or 0   -- the ladle tips back and lifts away
	local cool = smelt.endAt and math.exp(-since * 1.4) or 1
	local lit = 1 - smelt.grey                                    -- an interrupt fades the glows out
	local land = math.max(0, fillW - H * .32)                    -- where the stream lands, just behind the cast edge

	-- the metal glows with the heat along the bar, dull at the start and bright orange near the pour: the heat map
	-- (smelt_seam: the metal between the plates, the plates darker, their edges brighter) coloured in segments, each a
	-- gradient between the heats at its ends, laid exactly over the crust layer
	local fold = SmeltFold()
	local L = content.layers[1]
	local uspan = W / (512 * H / 64)
	local x0 = 0
	for i = 1, SEAM_SEGS do
		local tex = f["seam" .. i]
		local x1 = i == SEAM_SEGS and land or math.max(0, land - (SEAM_SEGS - i) * fold)
		if x1 - x0 < .5 then
			tex:Hide()
		else
			tex:ClearAllPoints()
			tex:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", x0, 0)
			tex:SetSize(x1 - x0, H)
			tex:SetTexCoord(L.u + x0 / W * uspan, L.u + x1 / W * uspan, 0, 1)
			local c = content.seamCols[i]
			local r, g, b = HeatRGB(MELT_HEAT, math.min(1, cool * math.exp(-(land - x0) / fold) + .03))
			c[1]:SetRGBA(r, g, b, 1)
			r, g, b = HeatRGB(MELT_HEAT, math.min(1, cool * math.exp(-(land - x1) / fold) + .03))
			c[2]:SetRGBA(r, g, b, 1)
			tex:SetGradient("HORIZONTAL", c[1], c[2])
			tex:Show()
		end
		x0 = math.max(x0, x1)
	end

	-- the fresh pour: pale yellow where it lands, through orange to the crust behind it
	local span = SmeltSpan()
	local left = land - span
	local right = math.max(fillW, land + 1)
	f.hot:ClearAllPoints()
	f.hot:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", left, 0)
	f.hot:SetSize(right - left, H)
	f.hot:SetTexCoord(0, (right - left) / span, 0, 1)            -- past the landing point it stays at its hottest
	f.hot:SetAlpha(cool)
	f.hot:SetShown(fillW > 1)
	-- the pour's rounded front: the nose mask (create) rounds off everything in the fill over its last half bar height,
	-- so the metal ends in a soft D-shaped nose that fades into the dark track with no straight edge anywhere
	if smelt.noseH ~= H then content.noseMask:SetSize(H * .5, H); smelt.noseH = H end
	-- the nose's glow spills past the fill edge over the dark track (forge.nose is clipped to the bar, not the fill),
	-- so the slope from the white-hot pool down to the track is continuous
	PlaceIn(forge.nose, forge.clip, fillW - H * .2, H * .5, H * 1.6, H * 1.6)
	forge.nose:SetAlpha(.4 * cool * lit)
	forge.nose:SetShown(fillW > 1)

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
	local e = .5 / 512
	forge.ladle:SetTexCoord(col / 2 + e, (col + 1) / 2 - e, row / 2 + e, (row + 1) / 2 - e)
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
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "forge",
	init = function() fx, tools = I.fx, I.tools end,
	sync = function(c, cf, w, h, t) content, cfg, W, H, clock = c, cf, w, h, t end,
	create = function(c)
		local ccfg = c.cfg
		if ccfg.smith or ccfg.smelt then   -- hot metal laid over the fill: blacksmithing's heat, edge and temper; smelting's fresh pour and front
			local function Tex(name, sub, blend, wrap)
				local tex = Smooth(c:CreateTexture(nil, "ARTWORK", nil, sub))
				if wrap then tex:SetTexture(MEDIA .. name, "REPEAT", "REPEAT") else tex:SetTexture(MEDIA .. name) end
				tex:SetBlendMode(blend or "BLEND")
				tex:Hide()
				return tex
			end
			c.forge = {}
			if ccfg.smith then
				c.forge.hot = Tex("smith_hot", 1, "BLEND", true)
				c.forge.hot:SetAllPoints(c)
				c.forge.edge = Tex("smith_edge", 2)                     -- the cast edge's extra heat, tinted to it
				c.forge.edge:SetTexCoord(0, 1, 0, 1)
				c.forge.temper = Tex("smith_temper", 4)
				c.forge.temper:SetAllPoints(c)
				c.flarePool = Pool(function() return Smooth(c:CreateTexture(nil, "ARTWORK")) end)
			else
				-- the seams' glow in segments along the bar, each a gradient of the heat there (UpdateSmelt)
				c.seamCols = {}
				for i = 1, SEAM_SEGS do
					c.forge["seam" .. i] = Tex("smelt_seam", 1, "BLEND", true)
					c.seamCols[i] = { CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1) }
				end
				c.forge.hot = Tex("smelt_hot", 2)
				-- the pour's rounded front: a mask on everything in this content (the black, the crust layer, the veil, the flash,
				-- the seams and the pour), anchored to the fill's edge (the clip frame's right), white but for a soft D-shaped
				-- nose in its last half bar height (smelt_nose; CLAMP keeps all of the fill left of it unmasked). A third mask
				-- beside the two corner masks: the most a texture takes. Never hidden (a hidden mask stops masking).
				c.noseMask = Smooth(c:CreateMaskTexture())
				c.noseMask:SetTexture(MEDIA .. "smelt_nose", "CLAMP", "CLAMP")
				c.noseMask:SetPoint("RIGHT", c:GetParent(), "RIGHT")
				c.noseMask:SetSize(H * .5, H)
				for _, r in ipairs({ c:GetRegions() }) do
					if r:GetObjectType() == "Texture" then r:AddMaskTexture(c.noseMask) end
				end
			end
		end
	end,
	begin = function()
		if cfg.smith then MakeSmith(carryHeat, carryTemper) end
		if cfg.smelt then MakeSmelt() end
		carryHeat, carryTemper = nil, nil
	end,
	update = function(dt, fillW, casting, state, t)
		clock = t
		if smith then UpdateSmith(dt, fillW, casting, state) end
		if smelt then UpdateSmelt(dt, fillW, casting) end
	end,
	interrupted = function(k)
		if (smith or smelt) and content and content.forge then
			local o = smith or smelt
			o.grey = k
			local f = content.forge
			f.hot:SetDesaturation(k)
			if f.edge then f.edge:SetDesaturation(k) end
			for i = 1, SEAM_SEGS do if f["seam" .. i] then f["seam" .. i]:SetDesaturation(k) end end
			forge.hammer:SetDesaturation(k); forge.ladle:SetDesaturation(k); forge.stream:SetDesaturation(k)
		end
	end,
	clear = function(keep)   -- keep: the next cast follows straight on, so the iron keeps its heat (FX:Begin)
		carryHeat = keep and smith and smith.heat or nil
		carryTemper = keep and smith and smith.temper or nil
		HideForge()
		smith, smelt = nil, nil
	end,
})
