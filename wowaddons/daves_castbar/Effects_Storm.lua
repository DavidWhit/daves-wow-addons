-- daves_castbar / Effects_Storm.lua
-- Lightning: painted clouds drifting over a dark sky, forked bolts striking and lighting them from within. One of
-- the effect files (see Effects.lua): its own 200 top-level locals, the shared helpers from ns.FXi, and its hooks
-- registered at the end.

local _, ns = ...
local I = ns.FXi
local rand, ContentTex = I.rand, I.ContentTex
local content, cfg, W, H, clock = nil, nil, 300, 26, 0   -- the core's state, copied in by sync

---------------------------------------------------------------------------
-- Lightning: a dark storm (the concept's C2 "Reference clouds, bank", 2026-10-09). The cloud is one painted texture,
-- storm_cloud (the user's own cloud painting, cut out by Make-CastbarMedia.ps1 StormCloud). Every cast lays copies of it
-- about the bar afresh: a far row of small faint ones high up and a near row of big ones with their bases low,
-- overlapping into one bank, each mirrored or not, drifting at its own pace, bobbing a little and wrapping round when
-- it leaves the bar. Forked bolts (p_bolts, painted sprites, mirrored for variety) strike inside the filled part every
-- 0.08-0.3 s and light the clouds near them from within (the same cloud again, added, fading with distance); now and
-- then a dim sheet of lightning; a faint glow on the leading edge. Nothing turns.
---------------------------------------------------------------------------
local storm                  -- this cast's lightning state
-- The cloud texture is 2 by 1 (512x256); the painted cloud fills its width and 0.968 of its height, so a cloud h tall
-- is drawn CLOUD_H * h tall and CLOUD_W * h wide.
local CLOUD_H = 1 / .968
local CLOUD_W = 2 * CLOUD_H
local FAR_MAX, NEAR_MAX = 24, 24   -- clouds in each row at most (an 800-wide bar wants about 20 and 24)
local BOLT_W, BOLT_H, BOLT_TOP = 2.5, 1.25, .075 -- a bolt cell in bar heights; its top this far above the bar
local BOLTS_MAX = 6

-- lay a row of clouds: height, centre (bar heights from the top), alpha, drift (bar heights a second), spacing
local function LayRow(row, n, h0, h1, y0, y1, alpha, v0, v1, sp0, sp1)
	local x = -H
	for i = 1, #row do
		local q = row[i]
		if x < W + H and n < #row then
			n = n + 1
			q.on = true
			q.x, q.y, q.h = x, H * rand(y0, y1), H * rand(h0, h1)
			q.flip, q.v, q.ph, q.a = math.random() < .5, rand(v0, v1) * H, rand(0, 6.283), alpha
			q.tex:SetTexCoord(q.flip and 1 or 0, q.flip and 0 or 1, 0, 1)
			q.lit:SetTexCoord(q.flip and 1 or 0, q.flip and 0 or 1, 0, 1)
			q.tex:SetSize(q.h * CLOUD_W, q.h * CLOUD_H); q.lit:SetSize(q.h * CLOUD_W, q.h * CLOUD_H)
			q.tex:SetDesaturation(0); q.tex:SetAlpha(alpha); q.tex:Show()
			q.litOn = false; q.lit:Hide()
			x = x + H * rand(sp0, sp1)
		else
			q.on = false; q.tex:Hide(); q.lit:Hide()
		end
	end
end

local function MakeStorm()
	local c = content.storm
	storm = { nextBolt = .15, flash = 0, flashX = 0, sheet = 0, sheetX = 0, roll = ns.Wobble(2), grey = 0, H = H }
	LayRow(c.far, 0, .45, .7, .1, .35, .65, .03, .06, 1.4, 2.2)
	LayRow(c.near, 0, 1.3, 1.7, .6, .8, 1, .07, .13, 1.3, 1.8)
	for _, b in ipairs(c.bolts) do b.on = false; b.tex:Hide(); b.tex:SetDesaturation(0) end
	c.flash:Hide(); c.edge:Hide()
end

local function HideStorm()
	if not (content and content.storm) then return end
	local c = content.storm
	for _, b in ipairs(c.bolts) do b.on = false; b.tex:Hide() end
	for _, row in ipairs({ c.far, c.near }) do
		for _, q in ipairs(row) do q.on = false; q.tex:Hide(); q.lit:Hide() end
	end
	c.flash:Hide(); c.edge:Hide()
end

-- the clouds of one row: drift, wrap, bob, and light up near a strike
local function UpdateRow(row, s, dt, lum, cx, reach, lit)
	for _, q in ipairs(row) do
		if q.on then
			q.x = q.x + q.v * dt
			local span = W + q.h * 2.4
			if q.x > W + q.h * 1.2 then q.x = q.x - span elseif q.x < -q.h * 1.2 then q.x = q.x + span end
			local y = H - (q.y + math.sin(clock * .35 + q.ph) * H * .03)   -- up from the bar's bottom
			q.tex:ClearAllPoints(); q.tex:SetPoint("CENTER", content, "BOTTOMLEFT", q.x, y)
			local d = math.abs(cx - q.x) / reach
			local k = lum * math.max(0, 1 - d * d)
			local on = k > .02
			if on ~= q.litOn then q.litOn = on; q.lit:SetShown(on) end
			if on then
				q.lit:ClearAllPoints(); q.lit:SetPoint("CENTER", content, "BOTTOMLEFT", q.x, y)
				q.lit:SetAlpha(q.a * k * lit)
			end
		end
	end
end

local function UpdateStorm(dt, fillW, casting)
	local s, c = storm, content.storm
	local lit = 1 - s.grey
	-- now and then a dim sheet of lightning somewhere in the clouds
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
	-- the clouds drift and bob; a strike (or a sheet) lights the ones near it from within, fading with distance
	local lum, cx, reach = s.flash * .6, s.flashX, H * 2.4
	if s.sheet * .35 > lum then lum, cx, reach = s.sheet * .35, s.sheetX, H * 2 end
	UpdateRow(c.far, s, dt, lum, cx, reach, lit)
	UpdateRow(c.near, s, dt, lum, cx, reach, lit)
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

-- the bar was resized mid-cast: scale every cloud's size and place with the height
local function Resize(h0)
	local c = content.storm
	local k = H / h0
	for _, row in ipairs({ c.far, c.near }) do
		for _, q in ipairs(row) do
			if q.on then
				q.x, q.y, q.h, q.v = q.x * k, q.y * k, q.h * k, q.v * k
				q.tex:SetSize(q.h * CLOUD_W, q.h * CLOUD_H); q.lit:SetSize(q.h * CLOUD_W, q.h * CLOUD_H)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "storm",
	sync = function(c, cf, w, h, t)
		local h0 = H
		content, cfg, W, H, clock = c, cf, w, h, t
		if storm and content and content.storm and h ~= h0 then Resize(h0); storm.H = h end
	end,
	create = function(c)
		local ccfg = c.cfg
		if ccfg.storm then   -- the clouds over the sky layer (far row behind the near one), their lit copies, the bolts, the flash, the leading edge
			local s = { far = {}, near = {}, bolts = {} }
			for i = 1, FAR_MAX do s.far[i] = { tex = ContentTex(c, "storm_cloud", 1), lit = ContentTex(c, "storm_cloud", 5, "ADD") } end
			for i = 1, NEAR_MAX do s.near[i] = { tex = ContentTex(c, "storm_cloud", 2), lit = ContentTex(c, "storm_cloud", 5, "ADD") } end
			for _, row in ipairs({ s.far, s.near }) do
				for _, q in ipairs(row) do q.lit:SetVertexColor(150 / 255, 170 / 255, 1) end   -- lit from within: a blue-white glow
			end
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
			for _, row in ipairs({ content.storm.far, content.storm.near }) do
				for _, q in ipairs(row) do q.tex:SetDesaturation(k) end
			end
		end
	end,
	clear = function()
		HideStorm()
		storm = nil
	end,
})
