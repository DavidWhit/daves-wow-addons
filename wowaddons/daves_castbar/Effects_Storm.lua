-- daves_castbar / Effects_Storm.lua
-- Lightning: cloud banks at four depths drifting over a dark sky under a weather that changes every cast, forked
-- bolts striking and lighting them from within. One of the effect files (see Effects.lua): its own 200
-- top-level locals, the shared helpers from ns.FXi, and its hooks registered at the end.

local _, ns = ...
local I = ns.FXi
local MEDIA, rand, Smooth, ContentTex = I.MEDIA, I.rand, I.Smooth, I.ContentTex
local content, cfg, W, H, clock = nil, nil, 300, 26, 0   -- the core's state, copied in by sync

---------------------------------------------------------------------------
-- Lightning: a dark storm. Up to four cloud banks (far to near; the weather below picks which, from which painted
-- set) drift over the sky layer at their own pace, slowly swelling; forked bolts (p_bolts) strike inside the filled part every 0.08-0.3 s and light the
-- banks round them from within (each bank's texture again, additive, through a soft round mask that follows the
-- strike); now and then a dim sheet of lightning; a faint glow on the leading edge. Nothing turns: the bolts are
-- painted sprites, mirrored for variety.
---------------------------------------------------------------------------
local storm                  -- this cast's lightning state
local STORM_BANKS = {        -- as Make-CastbarMedia.ps1 STORM_BANKS: top edge y (bar heights), alpha, drift (bar heights a second)
	{ y = .06, a = .75, v = .05 }, { y = .32, a = .95, v = .1 }, { y = .58, a = 1, v = .17 }, { y = .9, a = 1, v = .26 },
}
-- The weather, one per cast in turn (as the concept, lightning.js WEATHERS). Textures can't be repainted per cast, so
-- every bank is painted in four sets (Make-CastbarMedia.ps1 STORM_VARIANTS: storm_bank, storm_tower, storm_ragged,
-- storm_over) and a weather picks its set and which banks show, tints them and the sky, scales their drift, and sets
-- the chance of stray rows and of a bank drifting backwards.
local WEATHERS = {
	{ name = "layered", banks = { 1, 2, 3, 4 }, set = "bank", tint = { 1, 1, 1 }, v = 1, stray = .5, back = .2 },
	{ name = "towering", banks = { 1, 2, 3, 4 }, set = "tower", tint = { .96, .96, 1 }, v = .8, stray = .3, back = .1 },
	{ name = "scattered", banks = { 2, 3, 4 }, set = "ragged", tint = { 1, 1, .94 }, v = 1.3, stray = .8, back = .35 },
	{ name = "overcast", banks = { 1, 2, 3, 4 }, set = "over", tint = { .86, .88, .96 }, v = .6, stray = .2, back = 0 },
	{ name = "ragged squall", banks = { 1, 3, 4 }, set = "ragged", tint = { .92, 1, 1 }, v = 1.8, stray = 1, back = .5 },
}
local weatherTurn = math.random(#WEATHERS) - 1
local BANK_W, BANK_H, BANK_TOP = 16, 2, .9       -- a bank texture in bar heights; its billows hang from BANK_TOP
local BOLT_W, BOLT_H, BOLT_TOP = 2.5, 1.25, .075 -- a bolt cell in bar heights; its top this far above the bar
local BOLTS_MAX = 6

local function MakeStorm()
	local c = content.storm
	weatherTurn = weatherTurn % #WEATHERS + 1
	local Wt = WEATHERS[weatherTurn]
	storm = { weather = Wt, u = {}, ph = {}, sx = {}, flip = {}, dy = {}, v = {}, a = {}, breath = {}, src = {}, nextBolt = .15,
		flash = 0, flashX = 0, sheet = 0, sheetX = 0, roll = ns.Wobble(2), grey = 0 }
	-- every cast the banks are laid out afresh: stretched or squeezed, mirrored or not, a little higher or lower,
	-- drifting at their own speed (some backwards), breathing at their own pace, so the sky never repeats
	for i = 1, #STORM_BANKS + 2 do
		storm.u[i], storm.ph[i] = rand(0, 1), rand(0, 6.283)
		storm.sx[i], storm.flip[i] = rand(.7, 1.45), math.random() < .5
		storm.dy[i], storm.v[i], storm.a[i] = rand(-.09, .09), rand(.7, 1.3) * Wt.v * (math.random() < Wt.back and -1 or 1), rand(.85, 1)
		storm.breath[i] = rand(.03, .08)
	end
	local shown = {}
	for i = 1, #STORM_BANKS do
		local on = false
		for _, b in ipairs(Wt.banks) do if b == i then on = true end end
		if on then shown[#shown + 1] = i end
		local file = MEDIA .. "storm_" .. Wt.set .. i
		c.banks[i]:SetTexture(file, "REPEAT", "CLAMP"); c.lits[i]:SetTexture(file, "REPEAT", "CLAMP")
		c.banks[i]:SetVertexColor(Wt.tint[1], Wt.tint[2], Wt.tint[3])
		c.banks[i]:SetDesaturation(0); c.banks[i]:SetShown(on)
		c.lits[i]:Hide()
	end
	for i, t in ipairs(c.loose) do   -- now and then a stray, fainter row of clouds (a shown bank again) at another height
		local k, src = #STORM_BANKS + i, shown[math.random(#shown)]
		storm.src[i] = src
		storm.dy[k], storm.v[k], storm.a[k] = rand(-.35, .55), storm.v[src] * rand(.6, 1.6) * (math.random() < .4 and -1 or 1), rand(.25, .45)
		t:SetTexture(MEDIA .. "storm_" .. Wt.set .. src, "REPEAT", "CLAMP")
		t:SetVertexColor(Wt.tint[1], Wt.tint[2], Wt.tint[3])
		t:SetDesaturation(0); t:SetShown(math.random() < Wt.stray)
	end
	ns.TintLayer(content, 1, Wt.tint[1], Wt.tint[2], Wt.tint[3])   -- the sky takes the weather's tint too
	for _, b in ipairs(c.bolts) do b.on = false; b.tex:Hide(); b.tex:SetDesaturation(0) end
	c.flash:Hide(); c.edge:Hide()
end

local function HideStorm()
	if not (content and content.storm) then return end
	local c = content.storm
	for _, b in ipairs(c.bolts) do b.on = false; b.tex:Hide() end
	for i = 1, #STORM_BANKS do c.lits[i]:Hide() end
	for _, t in ipairs(c.loose) do t:Hide() end
	c.flash:Hide(); c.edge:Hide()
end

local function UpdateStorm(dt, fillW, casting)
	local s, c = storm, content.storm
	local lit = 1 - s.grey
	-- now and then a dim sheet of lightning somewhere in the banks
	if casting and math.random() < dt * .8 then s.sheet, s.sheetX = rand(.35, .6), rand(0, math.max(1, fillW)) end
	s.sheet = math.max(0, s.sheet - dt * 3)
	-- strikes: a forked bolt flickers in and is gone in a fraction of a second
	s.nextBolt = s.nextBolt - dt
	if casting and s.nextBolt <= 0 and fillW > H * 1.2 then
		s.nextBolt = rand(.08, .3)
		for _, b in ipairs(c.bolts) do
			if not b.on then
				local cx = rand(H * .5, fillW - H * .5)
				local cell = math.random(8) - 1
				local col, row = cell % 4, math.floor(cell / 4)
				local l, r = col / 4, (col + 1) / 4
				if math.random() < .5 then l, r = r, l end   -- mirrored, for variety
				b.tex:SetTexCoord(l, r, row / 2, (row + 1) / 2)
				b.tex:ClearAllPoints()
				b.tex:SetPoint("TOPLEFT", content, "TOPLEFT", cx - BOLT_W * H / 2, BOLT_TOP * H)
				b.tex:SetSize(BOLT_W * H, BOLT_H * H)
				b.tex:Show()
				b.on, b.age, b.life, b.ph = true, 0, rand(.18, .32), rand(0, 6.283)
				s.flash, s.flashX = 1, cx
				break
			end
		end
	end
	for _, b in ipairs(c.bolts) do
		if b.on then
			b.age = b.age + dt
			if b.age >= b.life then
				b.on = false; b.tex:Hide()
			else
				b.tex:SetAlpha((1 - b.age / b.life) * (.7 + .3 * math.sin(b.age * 90 + b.ph)) * lit)
			end
		end
	end
	-- the banks drift, rise and fall a little, and slowly swell (taller and shorter, pinned near their base)
	local span = W / (BANK_W * H)
	local lum, cx, reach = s.flash * .5, s.flashX, H * 2.6
	if s.sheet * .35 > lum then lum, cx, reach = s.sheet * .35, s.sheetX, H * 2 end
	lum = lum * lit
	for i = 1, #STORM_BANKS + #c.loose do
		local B = STORM_BANKS[i] or STORM_BANKS[s.src[i - #STORM_BANKS]]
		local bank = c.banks[i] or c.loose[i - #STORM_BANKS]
		if bank:IsShown() then
			local sp = span / s.sx[i]   -- stretched banks show less of the texture across the bar
			s.u[i] = (s.u[i] + B.v * s.v[i] * dt / (BANK_W * s.sx[i])) % 1   -- (Lua's % keeps a backwards drift in 0..1)
			local bh = BANK_H * H * (1 + s.breath[i] * math.sin(clock * .45 + s.ph[i] * 1.7))
			local y = (B.y + s.dy[i] - BANK_TOP) * H + math.sin(clock * .3 + s.ph[i]) * H * .03 - (bh - BANK_H * H) * .6
			local l, r = s.u[i], s.u[i] + sp
			if s.flip[i] then l, r = r, l end
			bank:ClearAllPoints(); bank:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
			bank:SetSize(W, bh); bank:SetTexCoord(l, r, 0, 1)
			bank:SetAlpha(B.a * s.a[i])
			local glow = c.lits[i]
			if glow then
				glow:SetShown(lum > .02)
				if lum > .02 then   -- lit from within round the strike: the same bank, added, through the round mask
					glow:ClearAllPoints(); glow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
					glow:SetSize(W, bh); glow:SetTexCoord(l, r, 0, 1)
					glow:SetAlpha(math.min(1, lum * 1.8) * B.a * s.a[i])
				end
			end
		end
	end
	c.mask:ClearAllPoints()
	c.mask:SetPoint("CENTER", content, "BOTTOMLEFT", cx, H * .5)
	c.mask:SetSize(reach * 2, reach * 2)
	-- a whole-cloud flash behind the strike
	c.flash:SetShown(s.flash > 0)
	if s.flash > 0 then
		c.flash:ClearAllPoints(); c.flash:SetPoint("CENTER", content, "BOTTOMLEFT", s.flashX, H * .5)
		c.flash:SetSize(H * 5, H * 3)
		c.flash:SetAlpha(.4 * s.flash * lit)
	end
	s.flash = math.max(0, s.flash - dt * 5)
	-- the cloud's leading edge glows faintly, with a static flicker now and then
	local edge = casting and fillW > 2
	c.edge:SetShown(edge)
	if edge then
		c.edge:ClearAllPoints(); c.edge:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", fillW - H * 1.2, 0)
		c.edge:SetSize(H * 1.2, H)
		c.edge:SetAlpha((.25 + .2 * (s.roll(clock * 6) + 1) / 2 + (math.random() < .08 and .3 or 0)) * lit)
	end
end

---------------------------------------------------------------------------
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "storm",
	sync = function(c, cf, w, h, t) content, cfg, W, H, clock = c, cf, w, h, t end,
	create = function(c)
		local ccfg = c.cfg
		if ccfg.storm then   -- the cloud banks over the sky layer, their lit copies, the bolts, the flash, the leading edge
			local s = { banks = {}, lits = {}, bolts = {} }
			s.mask = Smooth(c:CreateMaskTexture())   -- a soft round glow that follows the strike; never hidden (a hidden mask stops masking)
			s.mask:SetTexture(MEDIA .. "p_soft", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			for i = 1, #STORM_BANKS do
				s.banks[i] = ContentTex(c, "storm_bank" .. i, i, "BLEND", "REPEAT")
				s.lits[i] = ContentTex(c, "storm_bank" .. i, 5, "ADD", "REPEAT")
				s.lits[i]:AddMaskTexture(s.mask)
			end
			s.loose = {}   -- stray clouds: a shown bank's row again, faint, at a random height (some casts; MakeStorm sets the texture)
			for i = 1, 2 do s.loose[i] = ContentTex(c, "storm_bank" .. (i + 1), 1, "BLEND", "REPEAT") end
			for i = 1, BOLTS_MAX do s.bolts[i] = { tex = ContentTex(c, "p_bolts", 5, "ADD") } end
			s.flash = ContentTex(c, "p_soft", 5, "ADD")
			s.flash:SetVertexColor(110 / 255, 140 / 255, 1)
			s.edge = ContentTex(c, "edge_h", 7, "ADD")              -- strongest on the right: the leading edge
			s.edge:SetVertexColor(150 / 255, 180 / 255, 1)
			c.storm = s
		end
	end,
	begin = function() if cfg.storm then MakeStorm() end end,
	update = function(dt, fillW, casting, _, t)
		clock = t
		if storm then UpdateStorm(dt, fillW, casting) end
	end,
	interrupted = function(k)
		if storm and content and content.storm then   -- the bolts and glows fade by (1 - grey) in UpdateStorm
			storm.grey = k
			for i = 1, #STORM_BANKS do content.storm.banks[i]:SetDesaturation(k) end
			for _, t in ipairs(content.storm.loose) do t:SetDesaturation(k) end
		end
	end,
	clear = function()
		HideStorm()
		storm = nil
	end,
})
