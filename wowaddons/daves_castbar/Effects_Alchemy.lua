-- daves_castbar / Effects_Alchemy.lua
-- Alchemy: a bench of glassware on the bar the potion works through, pouring into a trough that fills like a
-- liquid. One of the effect files (see Effects.lua): its own 200 top-level locals, the shared helpers from
-- ns.FXi, and its hooks registered at the end.

local _, ns = ...
local I = ns.FXi
local MEDIA, rand, pick = I.MEDIA, I.rand, I.pick
local Smooth, Pool, Spawn, RGB, Light, ContentTex = I.Smooth, I.Pool, I.Spawn, I.RGB, I.Light, I.ContentTex
local tools                               -- above the bar's frame line: the bench (init)
local content, cfg, W, H, clock = nil, nil, 300, 26, 0   -- the core's state, copied in by sync

---------------------------------------------------------------------------
-- Alchemy: a bench of glassware stands on the bar (on `tools`), 6 to 10 stations shuffled each cast and joined
-- by glass, bent glass and rubber hoses (Lines), some with a brass valve. The potion works its way through them
-- as the cast goes on: each station fills, bubbles and lights its burner as it arrives, and it pours into the bar,
-- which is a trough of liquid for the whole cast (wholeBar): a small shallow-water simulation spreads it with a
-- rounded front, sloshes it off the ends and raises it until it brims at the end. The level is the progress.
-- The station art (alch_glass, alch_liquid) is an atlas of 128x256 cells in station units S (Make-CastbarMedia.ps1
-- ALCH_PX per S): the liquid is cropped to its level and tinted; nothing turns.
---------------------------------------------------------------------------
local alch                   -- this cast's alchemy state
local bench                  -- the stations' and tubes' textures and lines, made once
local CELL_W, CELL_H = 128 / 96, 256 / 96          -- an atlas cell in station units
local ALCH_KINDS = {   -- atlas cell; liquid zones (station units up from the bar top; fall: fills from the top); tube ends; burner
	boil   = { cell = 0, zones = { { .235, .748 } }, inn = { 0, 1.109 }, out = { 0, 1.109 }, burner = 0 },
	retort = { cell = 1, zones = { { .235, .805 } }, inn = { -.14, .777 }, out = { .471, 1.07 }, burner = -.12 },
	cyl    = { cell = 2, zones = { { .07, 1.105 } }, inn = { 0, 1.22 }, out = { 0, 1.22 } },
	erlen  = { cell = 3, zones = { { 0, .52 } }, inn = { 0, .88 }, out = { 0, .88 } },
	funnel = { cell = 4, zones = { { .699, 1.288 }, { 0, .319 } }, inn = { 0, 1.5065 }, out = { .153, .399 } },
	jacket = { cell = 5, zones = { { .12, 1.39, fall = true } }, inn = { 0, 1.39 }, out = { 0, .12 } },
	coil   = { cell = 6, zones = { { .12, 1.27, fall = true } }, inn = { 0, 1.27 }, out = { .02, .12 } },
	rack   = { cell = 7, zones = { { 0, .565 } }, inn = { -.3, .589 }, out = { .3, .551 } },
}
local ALCH_SHUFFLE = { "retort", "jacket", "cyl", "rack", "funnel", "coil", "erlen", "boil" }
local ALCH_PALETTES = {
	{ RGB(90, 255, 130), RGB(50, 225, 235), RGB(175, 100, 255), RGB(255, 205, 70) },
	{ RGB(255, 90, 110), RGB(255, 150, 60), RGB(255, 225, 90), RGB(255, 250, 210) },
	{ RGB(90, 150, 255), RGB(110, 255, 225), RGB(225, 120, 255), RGB(255, 130, 200) },
	{ RGB(160, 255, 80), RGB(255, 235, 70), RGB(255, 130, 50), RGB(255, 70, 120) },
}
local STATIONS_MAX, LINK_SEGS = 10, 12
local ALCH_LIGHT = { tex = "p_soft", colors = { { 1, 1, 1 } }, size = { .04, .08 }, life = { .4, .8 }, vx = { -25, 25 }, vy = { 8, 40 }, gravity = 70, add = true }
local ALCH_VAPOUR = { tex = "p_soft", colors = { { 1, 1, 1 } }, size = { .04, .07 }, grow = { .02, .04 }, life = { .7, 1.2 }, vx = { -4, 4 }, vy = { 10, 20 }, alpha = .45, add = true }
local ALCH_BUBBLE = { tex = "p_soft", colors = { { 1, 1, 1 } }, size = { .02, .04 }, life = { .25, .45 }, vx = { -3, 3 }, vy = { 10, 18 }, alpha = .7, add = true }
local ALCH_DRIP = { tex = "p_soft", colors = { { 1, 1, 1 } }, size = { .04, .05 }, life = { .2, .3 }, vx = { 0, 0 }, vy = { -10, -20 }, gravity = 300, add = true }
local ALCH_SPLASH = { tex = "p_soft", colors = { { 1, 1, 1 } }, size = { .02, .035 }, life = { .25, .4 }, vx = { -17, 17 }, vy = { 11, 28 }, gravity = 280, add = true }
local DROPS_MAX, RINGS_MAX, BUBBLES_MAX = 6, 8, 24
local SURF_MAX = 80          -- segments of the liquid's surface line

local function SetFxColor(e, c, k)   -- the particle specs above take one colour; set it before each Spawn
	local r, g, b = Light(c, k or .4)
	e.colors[1][1], e.colors[1][2], e.colors[1][3] = r, g, b
end
local function PalAt(pal, f, out)
	f = math.max(0, math.min(1, f)) * (#pal - 1)
	local i = math.min(#pal - 2, math.floor(f))   -- at f = 1 the last pair (never past the palette's end)
	local a, b, t = pal[i + 1], pal[i + 2], f - i
	out = out or {}
	out[1], out[2], out[3] = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
	return out
end

local function BenchTexture(name, sub, blend)
	local tex = Smooth(tools:CreateTexture(nil, "ARTWORK", nil, sub))
	tex:SetTexture(MEDIA .. name)
	tex:SetBlendMode(blend or "BLEND")
	tex:Hide()
	return tex
end

local function MakeBench()
	bench = { stations = {}, valves = {}, lines = {} }
	for i = 1, STATIONS_MAX do
		bench.stations[i] = { glass = BenchTexture("alch_glass", 4), liq = { BenchTexture("alch_liquid", 3), BenchTexture("alch_liquid", 3) },
			flame = BenchTexture("p_flame", 5, "ADD") }
		bench.valves[i] = BenchTexture("p_valve", 6)
	end
	bench.head = BenchTexture("p_soft", 6, "ADD")   -- the potion's head travelling along a tube
	bench.linePool = Pool(function() return tools:CreateLine(nil, "ARTWORK") end)
end

local function HideAlchemy()
	if bench then
		for _, st in ipairs(bench.stations) do st.glass:Hide(); st.liq[1]:Hide(); st.liq[2]:Hide(); st.flame:Hide() end
		for _, v in ipairs(bench.valves) do v:Hide() end
		bench.head:Hide()
		bench.linePool:ReleaseAll()
	end
	if content and content.trough then
		local t = content.trough
		for _, tex in ipairs(t.cols) do tex:Hide() end
		for k = 1, SURF_MAX do t.sheen[k]:Hide(); t.rim[k]:Hide() end
		t.gloss:Hide()
		if alch and alch.on then for i = 1, alch.N do alch.on[i] = false end end
		for _, d in ipairs(t.drops) do d.on = false; d.tex:Hide() end
		for _, r in ipairs(t.rings) do r.on = false; r.tex:Hide() end
		for _, b in ipairs(t.bubbles) do b.on = false; b.tex:Hide() end
	end
end

-- a link's path: points (bar pixels, y up) sampled along a cubic Bezier, or bent glass with rounded corners
local function BezierInto(xs, ys, x0, y0, x1, y1, x2, y2, x3, y3)
	for k = 0, LINK_SEGS do
		local t = k / LINK_SEGS
		local u = 1 - t
		xs[k + 1] = u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3
		ys[k + 1] = u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3
	end
end
local function ElbowInto(xs, ys, ax, ay, bx, by, top, r)
	-- up from A, across at `top`, down into B; the corners rounded with radius r (LINK_SEGS + 1 points)
	local px = { ax, ax, ax + (bx > ax and r or -r), bx - (bx > ax and r or -r), bx, bx }
	local py = { ay, top - r, top, top, top - r, by }
	local n = LINK_SEGS + 1
	-- spread the points along the polyline by length
	local L, cum = 0, { 0 }
	for i = 2, 6 do L = L + math.sqrt((px[i] - px[i - 1]) ^ 2 + (py[i] - py[i - 1]) ^ 2); cum[i] = L end
	for k = 1, n do
		local d = L * (k - 1) / (n - 1)
		local i = 2
		while i < 6 and cum[i] < d do i = i + 1 end
		local seg = math.max(1e-6, cum[i] - cum[i - 1])
		local t = (d - cum[i - 1]) / seg
		xs[k], ys[k] = px[i - 1] + (px[i] - px[i - 1]) * t, py[i - 1] + (py[i] - py[i - 1]) * t
	end
end

local function TubeLine(sub, r, g, b, a, thick, x0, y0, x1, y1)
	local line = bench.linePool:Get()
	line:SetDrawLayer("ARTWORK", sub)
	line:SetColorTexture(r, g, b, a)
	line:SetThickness(math.max(.6, thick))
	line:SetStartPoint("BOTTOMLEFT", tools, x0, y0)
	line:SetEndPoint("BOTTOMLEFT", tools, x1, y1)
	return line
end

local function MakeAlchemy()
	if not bench then MakeBench() end
	local m = H * .7
	local n = math.max(6, math.min(STATIONS_MAX, math.floor((W - 2 * m) / (H * 1.05)) + 1))
	local Z = (W - 2 * m) / (n - 1)
	local S = math.min(H, Z * .92)
	local pal = pick(ALCH_PALETTES)
	alch = { n = n, Z = Z, S = S, tw = math.max(1.8, S * .075), pal = pal, st = {}, links = {}, grey = 0, lastGrey = 0 }
	-- the stations: a boiling flask first, then the rest shuffled
	for i = #ALCH_SHUFFLE, 2, -1 do local j = math.random(i); ALCH_SHUFFLE[i], ALCH_SHUFFLE[j] = ALCH_SHUFFLE[j], ALCH_SHUFFLE[i] end
	for i = 1, n do
		local kind = i == 1 and "boil" or ALCH_SHUFFLE[(i - 2) % #ALCH_SHUFFLE + 1]
		local K = ALCH_KINDS[kind]
		local x = m + Z * (i - 1) + ((i > 1 and i < n) and rand(-.06, .06) * Z or 0)
		local st = { kind = kind, K = K, x = x, col = PalAt(pal, (i - 1) / (n - 1)), seed = rand(0, 99), lit = i == 1, tex = bench.stations[i] }
		st.inX, st.inY = x + K.inn[1] * S, H + K.inn[2] * S
		st.outX, st.outY = x + K.out[1] * S, H + K.out[2] * S
		local col, row = K.cell % 4, math.floor(K.cell / 4)
		st.u0, st.u1, st.v0 = col / 4, (col + 1) / 4, row / 2
		local g = st.tex.glass
		g:SetTexCoord(st.u0, st.u1, st.v0, st.v0 + .5)
		g:ClearAllPoints(); g:SetPoint("BOTTOMLEFT", tools, "BOTTOMLEFT", x - CELL_W * S / 2, H)
		g:SetSize(CELL_W * S, CELL_H * S)
		g:SetDesaturation(0); g:Show()
		for z = 1, 2 do st.tex.liq[z]:SetVertexColor(st.col[1], st.col[2], st.col[3], .92); st.tex.liq[z]:SetDesaturation(0); st.tex.liq[z]:Hide() end
		st.tex.flame:Hide()
		alch.st[i] = st
	end
	-- the links between them: glass arches, bent glass, rubber hoses; some with a brass valve
	local tw = alch.tw
	for i = 1, n - 1 do
		local A, B = alch.st[i], alch.st[i + 1]
		local top = math.max(A.outY, B.inY) + H * rand(.14, .28)
		local kind
		if A.kind == "retort" then kind = "retort"
		elseif A.outY < B.inY - S * .3 then kind = math.random() < .5 and "hose" or "elbow"
		else kind = pick({ "glass", "glass", "elbow", "hose" }) end
		local L = { kind = kind, xs = {}, ys = {}, cum = { 0 }, valve = kind ~= "hose" and math.random() < .45, segs = {} }
		if kind == "retort" then
			local dx, dy = math.cos(.75), math.sin(.75)
			BezierInto(L.xs, L.ys, A.outX, A.outY, A.outX + dx * S * .35, A.outY + dy * S * .35, B.inX, top, B.inX, B.inY)
		elseif kind == "glass" then
			BezierInto(L.xs, L.ys, A.outX, A.outY, A.outX + Z * .1, top, B.inX - Z * .1, top, B.inX, B.inY)
		elseif kind == "elbow" then
			ElbowInto(L.xs, L.ys, A.outX, A.outY, B.inX, B.inY, top, S * .15)
		else
			local lift = (A.outY - H < S * .5) and S * .1 or -S * .45
			BezierInto(L.xs, L.ys, A.outX, A.outY, A.outX + Z * .25, A.outY + lift, B.inX - Z * .3, top + S * .1, B.inX, B.inY)
		end
		for k = 2, LINK_SEGS + 1 do L.cum[k] = L.cum[k - 1] + math.sqrt((L.xs[k] - L.xs[k - 1]) ^ 2 + (L.ys[k] - L.ys[k - 1]) ^ 2) end
		local hose = kind == "hose"
		for k = 1, LINK_SEGS do
			local x0, y0, x1, y1 = L.xs[k], L.ys[k], L.xs[k + 1], L.ys[k + 1]
			if hose then
				TubeLine(0, 120 / 255, 52 / 255, 24 / 255, .95, tw * 1.3, x0, y0, x1, y1)
				TubeLine(1, 200 / 255, 110 / 255, 60 / 255, .35, tw * .9, x0, y0, x1, y1)
			else
				TubeLine(0, 205 / 255, 235 / 255, 1, .6, tw, x0, y0, x1, y1)
				TubeLine(1, 8 / 255, 12 / 255, 20 / 255, .65, tw * .62, x0, y0, x1, y1)
			end
			-- the potion in this piece of tube, its colour between the two stations'
			local f = (k - .5) / LINK_SEGS
			local liq = TubeLine(2, A.col[1] + (B.col[1] - A.col[1]) * f, A.col[2] + (B.col[2] - A.col[2]) * f, A.col[3] + (B.col[3] - A.col[3]) * f,
				hose and .6 or 1, tw * .56, x0, y0, x1, y1)
			liq:Hide()
			L.segs[k] = { line = liq, r = A.col[1] + (B.col[1] - A.col[1]) * f, g = A.col[2] + (B.col[2] - A.col[2]) * f, b = A.col[3] + (B.col[3] - A.col[3]) * f, a = hose and .6 or 1 }
		end
		local v = bench.valves[i]
		v:SetShown(L.valve)
		if L.valve then
			local k = math.floor(LINK_SEGS / 2) + 1
			v:ClearAllPoints(); v:SetPoint("CENTER", tools, "BOTTOMLEFT", L.xs[k], L.ys[k])
			v:SetSize(tw * 2.8, tw * 2.8); v:SetTexCoord(0, .5, 0, 1)
		end
		alch.links[i] = L
	end
	for i = n, STATIONS_MAX do bench.valves[i]:Hide() end
	for i = n + 1, STATIONS_MAX do local t = bench.stations[i]; t.glass:Hide(); t.liq[1]:Hide(); t.liq[2]:Hide(); t.flame:Hide() end
	bench.head:Hide()

	-- the trough: one column of liquid every few pixels (the simulation's cells), placed once; per frame only its
	-- height and the rows it shows change (shaded by height in the bar, so neighbours match: no vertical lines)
	local t = content.trough
	local N = math.max(40, math.min(#t.cols, math.ceil(W / 4)))   -- a column every 4 pixels (the concept's 3 showed as fine lines)
	alch.N, alch.dx = N, W / N
	alch.h, alch.q, alch.hs, alch.tmp, alch.y, alch.on = {}, {}, {}, {}, {}, {}
	for i = 1, N do alch.h[i], alch.hs[i], alch.tmp[i], alch.y[i], alch.on[i] = 0, 0, 0, 0, false end
	for i = 1, N + 1 do alch.q[i] = 0 end
	local c = {}
	for i, tex in ipairs(t.cols) do
		if i <= N then
			PalAt(pal, (i - .5) / N, c)
			tex:SetVertexColor(c[1], c[2], c[3], 1)   -- opaque: overlapping translucent columns show as stripes
			tex:SetDesaturation(0)
			tex:ClearAllPoints()
			tex:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", (i - 1) * alch.dx - .5, 0)
			tex:SetWidth(alch.dx + 1)
		end
		tex:Hide()
	end
	-- the surface line: a segment every few columns, tinted along the palette
	alch.step = math.max(1, math.floor(H * .3 / alch.dx + .5), math.ceil(N / SURF_MAX))
	alch.segs = math.min(SURF_MAX, math.ceil(N / alch.step))
	for k = 1, SURF_MAX do
		local x = math.min(1, ((k - .5) * alch.step) / N)
		PalAt(pal, x, c)
		t.sheen[k]:SetVertexColor(Light(c, .55)); t.sheen[k]:SetAlpha(.55); t.sheen[k]:SetDesaturation(0)
		t.rim[k]:SetVertexColor(Light(c, .85)); t.rim[k]:SetAlpha(.85); t.rim[k]:SetDesaturation(0)
		t.sheen[k]:SetThickness(math.max(2, H * .18)); t.rim[k]:SetThickness(math.max(1, H * .025))
		t.sheen[k]:Hide(); t.rim[k]:Hide()
	end
	t.gloss:ClearAllPoints()
	t.gloss:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -H * .07)
	t.gloss:SetSize(W, math.max(1, H * .04))
	t.gloss:Show()
	alch.dripT, alch.bubT = rand(.1, .3), 0
	for _, d in ipairs(t.drops) do d.on = false; d.tex:Hide() end
	for _, r in ipairs(t.rings) do r.on = false; r.tex:Hide() end
	for _, b in ipairs(t.bubbles) do b.on = false; b.tex:Hide() end
end

-- add `amount` (an area) to the trough, spread as a bell of width sig round x
local function Bell(x, amount, sig)
	local h, dx, N = alch.h, alch.dx, alch.N
	local sum = 0
	for i = 1, N do local d = ((i - .5) * dx - x) / sig; sum = sum + math.exp(-d * d) end
	if sum <= 0 then return end
	for i = 1, N do
		local d = ((i - .5) * dx - x) / sig
		h[i] = math.max(0, h[i] + amount * math.exp(-d * d) / sum / dx)
	end
end

-- shallow water: flux follows depth times slope, so a thin film creeps and the front stays rounded; the glass at
-- both ends stops it, a little viscosity keeps it smooth, and no column drains below empty
local function StepTrough(dt)
	local h, q, tmp, N, dx = alch.h, alch.q, alch.tmp, alch.N, alch.dx
	local G, damp, DT = 120 * math.max(H, 40), 1.2, 1 / 480
	local t = math.min(dt, .05)
	while t > 1e-6 do
		local d = math.min(t, DT)
		t = t - d
		for i = 2, N do
			local depth = (h[i - 1] + h[i]) / 2
			q[i] = (q[i] + d * G * depth * (h[i - 1] - h[i]) / dx) * (1 - damp * d)
		end
		q[1], q[N + 1] = 0, 0
		for i = 2, N do tmp[i] = q[i] + .25 * (q[i - 1] - 2 * q[i] + q[i + 1]) end
		for i = 2, N do q[i] = tmp[i] end
		for i = 1, N do
			local out = (math.max(0, q[i + 1]) + math.max(0, -q[i])) * d / dx
			if out > h[i] and out > 0 then
				local k = h[i] / out
				if q[i + 1] > 0 then q[i + 1] = q[i + 1] * k end
				if q[i] < 0 then q[i] = q[i] * k end
			end
		end
		for i = 1, N do h[i] = math.max(0, h[i] + d * (q[i] - q[i + 1]) / dx) end
	end
	-- what is drawn: smoothed, with a meniscus climbing the glass at each end
	local hs = alch.hs
	for i = 1, N do tmp[i] = (h[math.max(1, i - 1)] + 2 * h[i] + h[math.min(N, i + 1)]) / 4 end
	for i = 1, N do
		hs[i] = (tmp[math.max(1, i - 1)] + 2 * tmp[i] + tmp[math.min(N, i + 1)]) / 4
		if hs[i] >= H * .04 then
			local x = (i - .5) * dx
			hs[i] = hs[i] + H * .06 * (math.exp(-x / (H * .08)) + math.exp(-(W - x) / (H * .08)))
		end
	end
end

local function SurfaceAt(x)   -- the liquid's height (bar pixels from the bottom) at x
	local i = math.max(1, math.min(alch.N, math.floor(x / alch.dx) + 1))
	return alch.hs[i]
end

local function UpdateTrough(dt, fillW, casting)
	local t = content.trough
	local p = fillW / W
	local xs = math.max(H * .15, math.min(W - H * .15, fillW - H * .12))   -- where the potion falls in
	local vol = 0
	for i = 1, alch.N do vol = vol + alch.h[i] * alch.dx end
	local target = W * H * 1.04 * p * p          -- spread over the poured length, the level rises with the cast
	if target > vol then Bell(xs, math.min(target - vol, W * H * 2.5 * dt + 1), H * .45) end
	StepTrough(dt)
	-- drops falling in now and then from the apparatus above, each leaving rings and a little splash
	alch.dripT = alch.dripT - dt
	if casting and fillW > H * .2 and alch.dripT <= 0 then
		alch.dripT = rand(.25, .5)
		for _, d in ipairs(t.drops) do
			if not d.on then
				d.on, d.x, d.y, d.vy = true, xs + rand(-.08, .08) * H, H, H * rand(.4, 1)
				local c = PalAt(alch.pal, d.x / W, d.c)
				d.c = c
				d.tex:SetVertexColor(Light(c, .35))
				d.tex:Show()
				break
			end
		end
	end
	for _, d in ipairs(t.drops) do
		if d.on then
			d.vy = d.vy + H * 14 * dt
			d.y = d.y - d.vy * dt
			local sy = SurfaceAt(d.x)
			if d.y <= sy then
				d.on = false; d.tex:Hide()
				local i = math.max(1, math.min(alch.N, math.floor(d.x / alch.dx) + 1))
				local k = math.min(alch.h[i] * .3, H * .03) * H * .3   -- pushes the surface down, heaps it round about
				Bell(d.x, -k, H * .1); Bell(d.x, k, H * .3)
				for _, r in ipairs(t.rings) do
					if not r.on then r.on, r.x, r.age = true, d.x, 0; r.tex:Show(); break end
				end
				SetFxColor(ALCH_SPLASH, d.c, .5)
				for _ = 1, 3 do Spawn(ALCH_SPLASH, d.x, sy) end
			else
				d.tex:ClearAllPoints(); d.tex:SetPoint("CENTER", content, "BOTTOMLEFT", d.x, d.y)
				d.tex:SetSize(H * .07, H * .1)
			end
		end
	end
	for _, r in ipairs(t.rings) do
		if r.on then
			r.age = r.age + dt
			if r.age >= .6 then
				r.on = false; r.tex:Hide()
			else
				local k = r.age / .6
				local rx = H * (.08 + .5 * k)
				r.tex:ClearAllPoints(); r.tex:SetPoint("CENTER", content, "BOTTOMLEFT", r.x, SurfaceAt(r.x) - 1)
				r.tex:SetSize(rx * 2, rx * .44)
				r.tex:SetAlpha(.45 * (1 - k) * (1 - alch.grey))
			end
		end
	end
	-- bubbles rise from the bottom and pop at the surface
	alch.bubT = alch.bubT - dt
	if alch.bubT <= 0 then
		alch.bubT = rand(.015, .045) * 300 / W   -- a few more bubbles rising at any time (2026-10-09)
		local i = math.random(alch.N)
		if alch.hs[i] > H * .25 then
			for _, b in ipairs(t.bubbles) do
				if not b.on then
					b.on, b.x, b.y, b.r, b.ph = true, (i - .5) * alch.dx, rand(0, .1) * H, H * rand(.015, .035), rand(0, 6.283)
					b.tex:SetSize(b.r * 2, b.r * 2); b.tex:Show()
					break
				end
			end
		end
	end
	for _, b in ipairs(t.bubbles) do
		if b.on then
			b.y = b.y + H * .7 * dt
			b.x = b.x + math.sin(clock * 6 + b.ph) * H * .08 * dt
			if b.y >= SurfaceAt(b.x) - b.r then
				b.on = false; b.tex:Hide()
				Spawn(ALCH_BUBBLE, b.x, SurfaceAt(b.x))
			else
				b.tex:ClearAllPoints(); b.tex:SetPoint("CENTER", content, "BOTTOMLEFT", b.x, b.y)
			end
		end
	end
	-- the columns: the simulated level, with small, slow travelling ripples where it is neither thin nor brimming
	local dx, ys, on = alch.dx, alch.y, alch.on
	for i = 1, alch.N do
		local tex = t.cols[i]
		local d = alch.hs[i]
		local x = (i - .5) * dx
		local calm = math.max(0, math.min(1, d / (H * .12))) * math.max(0, math.min(1, (H - d) / (H * .15)))
		local y = math.min(H, d + calm * (math.sin(x / (H * .5) - clock * 2.6) * H * .02 + math.sin(x / (H * .21) + clock * 4.3) * H * .01
			+ math.sin(x / (H * .9) + clock * 1.3) * H * .015))   -- the concept's three ripples
		ys[i] = y
		local show = y >= .5
		if show ~= on[i] then tex:SetShown(show); on[i] = show end
		if show then
			tex:SetHeight(y)
			tex:SetTexCoord(0, 1, 1 - y / H, 1)   -- the rows at this height in the bar, so every column matches its neighbours
		end
	end
	-- the surface: one continuous line along the columns' tops, a soft band of light just under it (alch_band fades to
	-- both edges, so it reads the same whichever way the line runs)
	local step, n = alch.step, alch.N
	local band = math.max(2, H * .18) / 2 - H * .01   -- the band's centre below the surface: its top edge just on it
	for k = 1, alch.segs do
		local a, b = math.min(n, (k - 1) * step + 1), math.min(n, k * step + 1)
		local ya, yb = ys[a], ys[b]
		local sheen, rim = t.sheen[k], t.rim[k]
		if ya >= 1 and yb >= 1 and b > a then
			local xa, xb = (a - .5) * dx, (b - .5) * dx
			if a == 1 then xa = 0 end
			if b == n then xb = W end
			rim:SetStartPoint("BOTTOMLEFT", content, xa, ya - .5); rim:SetEndPoint("BOTTOMLEFT", content, xb, yb - .5)
			sheen:SetStartPoint("BOTTOMLEFT", content, xa, ya - band); sheen:SetEndPoint("BOTTOMLEFT", content, xb, yb - band)
			rim:Show(); sheen:Show()
		else
			rim:Hide(); sheen:Hide()
		end
	end
end

local function UpdateAlchemy(dt, fillW, casting)
	UpdateTrough(dt, fillW, casting)
	local S, n = alch.S, alch.n
	local X, d = fillW, alch.Z * .38
	local lit = 1 - alch.grey
	local p = fillW / W
	-- the stations: each fills as the potion reaches it; burners light, flasks boil, the funnel drips
	for i = 1, n do
		local st = alch.st[i]
		local f = i == 1 and 1 or math.max(0, math.min(1, (X - st.x) / d))
		local heat = i == 1 and 1 or math.max(0, math.min(1, (X - st.x) / (H * .35)))
		if not st.lit and X > st.x then
			st.lit = true
			SetFxColor(ALCH_LIGHT, st.col, .4)
			for _ = 1, 7 do Spawn(ALCH_LIGHT, st.inX, st.inY) end
		end
		local kind = st.kind
		local lv1, lv2
		if kind == "boil" then lv1 = .8 - .4 * p
		elseif kind == "retort" then lv1 = .72 * f
		elseif kind == "cyl" then lv1 = .85 * f
		elseif kind == "erlen" then lv1 = .7 * f
		elseif kind == "funnel" then
			local ff = math.min(1, f * 1.6)
			lv1 = math.max(0, .85 * ff - math.max(0, math.min(1, f * 1.6 - .6)) * .6)
			lv2 = .82 * math.max(0, math.min(1, (f - .35) / .65))
			if casting and f > .35 and f < 1 and math.random() < dt * 6 then   -- drops from the stopcock into the beaker
				SetFxColor(ALCH_DRIP, st.col, .2)
				Spawn(ALCH_DRIP, st.x, H + .55 * S)
			end
		elseif kind == "rack" then lv1 = .8 * f
		else lv1 = f end   -- jacket and coil: the potion runs down the inner tube
		for z = 1, 2 do
			local zone, lv, tex = st.K.zones[z], z == 1 and lv1 or lv2, st.tex.liq[z]
			if zone and lv and lv > .005 then
				local y0, y1 = zone[1], zone[2]
				local a, b = y0, y0 + lv * (y1 - y0)
				if zone.fall then a, b = y1 - lv * (y1 - y0), y1 end
				tex:SetTexCoord(st.u0, st.u1, st.v0 + (CELL_H - b) / CELL_H * .5, st.v0 + (CELL_H - a) / CELL_H * .5)
				tex:ClearAllPoints(); tex:SetPoint("BOTTOMLEFT", tools, "BOTTOMLEFT", st.x - CELL_W * S / 2, H + a * S)
				tex:SetSize(CELL_W * S, math.max(.1, (b - a) * S))
				tex:Show()
			else
				tex:Hide()
			end
		end
		-- a burner under the boiling flask and the retort, lit when the potion arrives
		local fl = st.tex.flame
		if st.K.burner and heat > .02 then
			local bx = st.x + st.K.burner * S + (math.sin(clock * 9 + st.seed) * .2 + math.sin(clock * 23 + st.seed * 3) * .08) * S * .04
			local fh = .21 * S * heat * (.86 + .14 * math.sin(clock * 31 + st.seed * 7))
			fl:ClearAllPoints(); fl:SetPoint("BOTTOM", tools, "BOTTOMLEFT", bx, H + .122 * S)
			fl:SetSize(.2 * S, math.max(.1, fh))
			fl:SetAlpha(lit)
			fl:Show()
			if casting and heat > .5 and math.random() < dt * 3 then   -- vapour rising off the hot flask
				SetFxColor(ALCH_VAPOUR, st.col, .5)
				Spawn(ALCH_VAPOUR, st.inX, st.inY + H * .05)
			end
			if casting and math.random() < dt * 8 * heat then   -- bubbles in the boiling liquid
				Spawn(ALCH_BUBBLE, st.x + st.K.burner * S + rand(-.12, .12) * S, H + (st.K.zones[1][1] + .06) * S)
			end
		else
			fl:Hide()
		end
	end
	-- the links: the potion runs through each in turn; its head glows as it goes
	local headOn = false
	for i = 1, n - 1 do
		local L = alch.links[i]
		local a, b = alch.st[i], alch.st[i + 1]
		local f = math.max(0, math.min(1, (X - a.x - d) / (b.x - a.x - d)))
		local reach = f * L.cum[LINK_SEGS + 1]
		for k = 1, LINK_SEGS do
			local seg = L.segs[k]
			local line = seg.line
			if L.cum[k + 1] <= reach then
				line:SetEndPoint("BOTTOMLEFT", tools, L.xs[k + 1], L.ys[k + 1])
				line:Show()
			elseif L.cum[k] < reach then
				local t = (reach - L.cum[k]) / math.max(1e-6, L.cum[k + 1] - L.cum[k])
				local hx, hy = L.xs[k] + (L.xs[k + 1] - L.xs[k]) * t, L.ys[k] + (L.ys[k + 1] - L.ys[k]) * t
				line:SetEndPoint("BOTTOMLEFT", tools, hx, hy)
				line:Show()
				if not headOn then
					headOn = true
					bench.head:ClearAllPoints(); bench.head:SetPoint("CENTER", tools, "BOTTOMLEFT", hx, hy)
					bench.head:SetSize(alch.tw * 4.8, alch.tw * 4.8)
					bench.head:SetVertexColor(seg.r + (1 - seg.r) * .3, seg.g + (1 - seg.g) * .3, seg.b + (1 - seg.b) * .3)
					bench.head:SetAlpha(.9 * lit)
				end
			else
				line:Hide()
			end
		end
		if L.valve then bench.valves[i]:SetTexCoord(f > .45 and .5 or 0, f > .45 and 1 or .5, 0, 1) end
	end
	bench.head:SetShown(headOn and casting)
	-- an interrupt greys the potion in the tubes too (only while the grey fades in)
	if alch.grey ~= alch.lastGrey then
		alch.lastGrey = alch.grey
		local k = alch.grey
		for i = 1, n - 1 do
			for _, seg in ipairs(alch.links[i].segs) do
				local l = seg.r * .3 + seg.g * .59 + seg.b * .11
				seg.line:SetColorTexture(seg.r + (l - seg.r) * k, seg.g + (l - seg.g) * k, seg.b + (l - seg.b) * k, seg.a)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "alchemy",
	init = function() tools = I.tools end,
	sync = function(c, cf, w, h, t) content, cfg, W, H, clock = c, cf, w, h, t end,
	create = function(c)
		local ccfg = c.cfg
		if ccfg.alchemy then   -- the trough's liquid columns, falling drops, rings and bubbles
			local t = { cols = {}, drops = {}, rings = {}, bubbles = {}, sheen = {}, rim = {} }
			for i = 1, 200 do
				t.cols[i] = ContentTex(c, "alch_column", 2)
				-- a column only ever changes height, so it can snap to the pixel grid: its edges then land on whole pixels and
				-- overlap its neighbours' exactly, with no half-covered seam between them (the fine vertical lines)
				t.cols[i]:SetSnapToPixelGrid(true)
				t.cols[i]:SetTexelSnappingBias(.5)
			end
			-- the surface: one continuous line over the columns' tops (a soft band of light under it, as the concept, so a
			-- thin layer is as bright as a deep one; a bright edge on it)
			for i = 1, SURF_MAX do
				for _, set in ipairs({ t.sheen, t.rim }) do
					local line = c:CreateLine(nil, "ARTWORK", nil, set == t.sheen and 3 or 4)
					if set == t.sheen then line:SetTexture(MEDIA .. "alch_band") else line:SetColorTexture(1, 1, 1, 1) end
					line:Hide()
					set[i] = line
				end
			end
			-- the glass front's gloss: a pale stripe across the bar near its top, over the potion once it is that full
			t.gloss = c:CreateTexture(nil, "ARTWORK", nil, 5)
			t.gloss:SetColorTexture(1, 1, 1, .12)
			t.gloss:Hide()
			for i = 1, DROPS_MAX do t.drops[i] = { tex = ContentTex(c, "p_ember", 4, "ADD") } end
			for i = 1, RINGS_MAX do
				t.rings[i] = { tex = ContentTex(c, "p_ripple", 3, "ADD") }
				t.rings[i].tex:SetVertexColor(1, 1, 1)
			end
			for i = 1, BUBBLES_MAX do
				t.bubbles[i] = { tex = ContentTex(c, "p_ripple", 3, "ADD") }
				t.bubbles[i].tex:SetAlpha(.5)
			end
			c.trough = t
		end
	end,
	begin = function() if cfg.alchemy then MakeAlchemy() end end,
	update = function(dt, fillW, casting, _, t)
		clock = t
		if alch then UpdateAlchemy(dt, fillW, casting) end
	end,
	interrupted = function(k)
		if alch and bench and content and content.trough then   -- the potion in the tubes greys in UpdateAlchemy
			alch.grey = k
			for i = 1, alch.N do content.trough.cols[i]:SetDesaturation(k) end
			for j = 1, SURF_MAX do content.trough.sheen[j]:SetDesaturation(k); content.trough.rim[j]:SetDesaturation(k) end
			for i = 1, alch.n do
				local t = alch.st[i].tex
				t.glass:SetDesaturation(k); t.liq[1]:SetDesaturation(k); t.liq[2]:SetDesaturation(k)
			end
		end
	end,
	clear = function()
		HideAlchemy()
		alch = nil
	end,
})
