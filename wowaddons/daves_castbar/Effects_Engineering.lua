-- daves_castbar / Effects_Engineering.lua
-- Engineering: an interlocking train of big spoked wheels and small pinions over a painted clockwork movement plate
-- with Roman-numeral dials, ticking Breguet hands and etched astrolabe rings; as the cast progresses from left to
-- right each gear engages in turn and drives the next until the whole train turns together to complete the recipe.
-- One of the effect files (see Effects.lua): its own 200 top-level locals, the shared helpers from ns.FXi, and its
-- hooks registered at the end. Nothing calls SetRotation per frame: gears and clock hands step through pre-rendered
-- spin-phase atlases (Make-CastbarMedia.ps1 EngGears / EngHands).

local _, ns = ...
local I = ns.FXi
local rand, PI, Smooth, Spawn = I.rand, I.PI, I.Smooth, I.Spawn
local RGB, PlaceIn, Band, lerp, clamp, ContentTex = I.RGB, I.PlaceIn, I.Band, I.lerp, I.clamp, I.ContentTex
local content, cfg, W, H, clock = nil, nil, 300, 26, 0   -- the core's state, copied in by sync

---------------------------------------------------------------------------
-- Atlas geometry (must match Make-CastbarMedia.ps1 EngGears / EngHands / EngDials)
--   Row 1: Z=20, S=5  giant spoked Gnomish brass master wheel
--   Row 2: Z=16, S=4  large forged Dwarven copper-bronze cross-spoke gear
--   Row 3: Z=12, S=6  medium tempered blued-steel 6-hole spur gear
--   Row 4: Z=8,  S=4  small high-speed gilded pinion gear
---------------------------------------------------------------------------
local GEAR_Z = { 20, 16, 12, 8 }
local GEAR_S = { 5, 4, 6, 4 }
local GEAR_SPAN = { 22.80, 18.80, 14.80, 10.80 }   -- 2 * (Z * 0.5 + 1.40) circular modules across each 128x128 cell
local GEAR_COLS, GEAR_ROWS = 16, 4
local HAND_COLS, HAND_ROWS = 8, 2
local DIALS_MAX = 12                               -- background Roman clock dials and etched Vernier rings
local GEARS_MAX = 44                               -- an 800x20 bar (40 H) needs ~36 main gears + up to 6 satellite idlers

-- Four workshop metal palettes cycled per cast so back-to-back crafts differ while keeping painted metal richness.
local PALETTES = {
	-- Gnomish Chronometer: bright gold-brass, warm copper, cool blued steel, amber Vernier rings
	{ tint = { { 1, 1, 1 }, { 1, .98, .95 }, { .96, 1, 1.04 }, { 1, .98, .92 } }, dial = RGB(255, 214, 132), glow = RGB(255, 192, 92) },
	-- Dwarven Steamworks: burnished bronze-gold, deep forged copper, oiled dark steel, warm copper rings
	{ tint = { { 1, .92, .82 }, { 1.04, .90, .82 }, { .86, .88, .92 }, { 1, .92, .80 } }, dial = RGB(244, 184, 112), glow = RGB(255, 162, 72) },
	-- Arcane Horology: pale electrum-gold, rose-bronze, bright mythril-steel, pale gold-blue rings
	{ tint = { { 1.02, 1.0, .94 }, { .98, .92, .94 }, { .98, 1.02, 1.06 }, { 1.02, 1.0, .96 } }, dial = RGB(220, 232, 255), glow = RGB(210, 220, 255) },
	-- Tinker's Bench: antique oiled brass, weathered bronze, gunmetal steel, brass rings
	{ tint = { { .96, .95, .86 }, { .96, .92, .86 }, { .88, .94, .94 }, { 1, .96, .88 } }, dial = RGB(236, 206, 138), glow = RGB(245, 198, 104) },
}
local palTurn = math.random(#PALETTES) - 1

local SPARK = {
	tex = "p_star", colors = { RGB(255, 226, 148), RGB(255, 190, 96), RGB(255, 248, 214) },
	size = { .11, .22 }, life = { .18, .42 }, vx = { -26, 22 }, vy = { -14, 28 }, gravity = 75, add = true,
}
local STEAM = {
	tex = "p_soft", colors = { RGB(226, 220, 206) },
	size = { .18, .34 }, life = { .45, .85 }, vx = { -8, 10 }, vy = { 10, 26 }, grow = { .22, .42 }, alpha = .22,
}

local eng                    -- this cast's live engineering state

local function SetHandPhase(tex, ang)
	local idx = math.floor(((ang / (2 * PI)) % 1) * 16)
	local col, row = idx % HAND_COLS, math.floor(idx / HAND_COLS)
	tex:SetTexCoord(col / HAND_COLS, (col + 1) / HAND_COLS, row / HAND_ROWS, (row + 1) / HAND_ROWS)
end

local function SetGearPhase(tex, row, theta)
	local sec = 2 * PI / GEAR_S[row]
	local col = math.floor(((theta / sec) % 1) * GEAR_COLS)
	tex:SetTexCoord(col / GEAR_COLS, (col + 1) / GEAR_COLS, (row - 1) / GEAR_ROWS, row / GEAR_ROWS)
end

-- Exact tooth-in-valley meshing angle for child gear Zc at direction beta from parent gear (Zp, thetaP).
local function MeshAngle(beta, Zp, thetaP, Zc)
	return beta + PI - PI / Zc + (Zp / Zc) * (beta - thetaP)
end

local function HideEngineering()
	if not (content and content.eng) then return end
	local c = content.eng
	c.shade:Hide(); c.warm:Hide(); c.meshGlow:Hide()
	for i = 1, DIALS_MAX do
		local d = c.dials[i]
		d.tex:Hide(); d.hour:Hide(); d.min:Hide()
	end
	for i = 1, GEARS_MAX do c.gears[i]:Hide() end
end

-- Build the background clock dials and the continuous left-to-right interlocking gear train for the current (W, H).
-- Seeded per cast so dragging a resize handle in Edit Mode smoothly extends/scales the same train without flickering.
local function MakeRng(seed)
	local st = seed % 2147483647
	if st <= 0 then st = st + 2147483646 end
	local function u()
		st = (st * 16807) % 2147483647
		return (st - 1) / 2147483646
	end
	local function rr(a, b) return a + u() * (b - a) end
	return u, rr
end

local function BuildLayout(keepState)
	local c = content.eng
	local seed = keepState and eng.seed or math.random(1, 2000000000)
	local u01, rrng = MakeRng(seed)
	local pal = keepState and eng.pal or PALETTES[palTurn]
	local mod = keepState and eng.mod or rrng(.068, .075)
	local dir = keepState and eng.dir or (u01() < .5 and 1 or -1)
	local drive = keepState and eng.drive or rrng(0, 6.283)
	local mH = mod * H

	-- 1. Background horological dials: alternating painted Roman I-XII clock faces (with hour + minute hands)
	--    and etched Vernier/hairspring astrolabe rings behind the gears.
	local dials = {}
	local dx = H * rrng(.65, 1.35)
	local kind = u01() < .5 and 0 or 1
	while dx < W - H * .45 and #dials < DIALS_MAX do
		local roman = (kind % 2) == 0
		local sz = H * (roman and rrng(.92, 1.26) or rrng(.86, 1.22))
		local dy = H * (roman and rrng(.24, .76) or rrng(.20, .80))
		local m0 = rrng(0, 6.283)
		local prevD = keepState and eng.dials and eng.dials[#dials + 1]
		dials[#dials + 1] = {
			x = dx, y = dy, sz = sz, roman = roman,
			h0 = rrng(0, 6.283), m0 = m0, sweep = prevD and prevD.sweep or m0,
			rate = rrng(1.8, 3.0) * (u01() < .5 and 1 or -1),
		}
		dx = dx + H * rrng(2.5, 3.8)
		kind = kind + 1
	end
	for i = 1, DIALS_MAX do
		local slot, d = c.dials[i], dials[i]
		if d then
			slot.tex:SetTexCoord(d.roman and 0 or .5, d.roman and .5 or 1, 0, 1)
			slot.tex:SetBlendMode(d.roman and "BLEND" or "ADD")
			if d.roman then
				slot.tex:SetVertexColor(1, 1, 1)
			else
				slot.tex:SetVertexColor(pal.dial[1], pal.dial[2], pal.dial[3])
			end
			slot.tex:SetDesaturation(0)
			PlaceIn(slot.tex, content, d.x, d.y, d.sz, d.sz)
			slot.tex:Show()
			if d.roman then
				PlaceIn(slot.hour, content, d.x, d.y, d.sz * .54, d.sz * .54)
				PlaceIn(slot.min, content, d.x, d.y, d.sz * .78, d.sz * .78)
				slot.hour:SetDesaturation(0); slot.min:SetDesaturation(0)
				slot.hour:Show(); slot.min:Show()
			else
				slot.hour:Hide(); slot.min:Hide()
			end
		else
			slot.tex:Hide(); slot.hour:Hide(); slot.min:Hide()
		end
	end

	-- 2. Main left-to-right interlocking gear train spanning 0..W, mixing big spoked gears (rows 1, 2)
	--    and medium/small gears (rows 3, 4) that sit wholly inside the bar.
	local gears = {}
	local r1 = u01() < .55 and 1 or 2
	local y1 = H * (u01() < .5 and rrng(.22, .38) or rrng(.62, .78))
	gears[1] = {
		row = r1, x = H * rrng(.12, .28), y = y1, parent = nil, beta = 0,
		theta0 = rrng(0, 6.283), theta = 0, engageX = 0, sparked = true,
	}
	local highSide = y1 > H * .5
	local satBudget = math.min(6, math.max(1, math.floor(W / (H * 3.2))))

	while gears[#gears].x < W - H * .08 and #gears < GEARS_MAX - satBudget do
		local prev = gears[#gears]
		local pRow = prev.row
		local nRow
		if pRow <= 2 then
			-- after a big spoked wheel, usually step into a small or medium gear so both sizes show clearly
			local u = u01()
			nRow = u < .42 and 4 or u < .80 and 3 or (3 - pRow)
		else
			local u = u01()
			nRow = u < .38 and 1 or u < .72 and 2 or (7 - pRow)
		end
		local Zp, Zn = GEAR_Z[pRow], GEAR_Z[nRow]
		local dist = (Zp + Zn) * .5 * mH
		local targetY
		if nRow == 4 then
			targetY = H * rrng(.30, .70)         -- small pinion stays wholly inside the bar
		elseif nRow == 3 then
			targetY = H * rrng(.25, .75)         -- medium 6-hole spur gear
		else
			highSide = not highSide              -- alternate big spoked wheels between upper and lower edges
			targetY = H * (highSide and rrng(.64, .86) or rrng(.14, .36))
		end
		local dy = math.max(-dist * .66, math.min(dist * .66, targetY - prev.y))
		local ny = prev.y + dy
		if nRow == 4 then ny = math.max(H * .26, math.min(H * .74, ny)); dy = ny - prev.y end
		if math.abs(dy) > dist * .68 then dy = (dy < 0 and -1 or 1) * dist * .68; ny = prev.y + dy end
		local dx2 = math.sqrt(math.max(.01, dist * dist - dy * dy))
		local nx = prev.x + dx2
		local beta = math.atan2(dy, dx2)
		local th0 = MeshAngle(beta, Zp, prev.theta0, Zn)
		local contactX = prev.x + (Zp * .5 * mH) * math.cos(beta)
		gears[#gears + 1] = {
			row = nRow, x = nx, y = ny, parent = #gears, beta = beta,
			theta0 = th0, theta = th0, engageX = math.max(0, contactX), sparked = keepState,
		}
	end

	-- 3. Satellite idler pinions meshed onto big spoked wheels in open pockets on the opposite side of the bar.
	local mainCount = #gears
	for i = 2, mainCount - 1 do
		if #gears >= GEARS_MAX or satBudget <= 0 then break end
		local g = gears[i]
		if g.row <= 2 and u01() < .55 then
			local sRow = u01() < .72 and 4 or 3
			local Zp, Zs = GEAR_Z[g.row], GEAR_Z[sRow]
			local dist = (Zp + Zs) * .5 * mH
			local up = g.y < H * .5
			local beta = (up and 1 or -1) * rrng(1.18, 1.96)   -- tucked above or below the big wheel
			local sx, sy = g.x + dist * math.cos(beta), g.y + dist * math.sin(beta)
			if sx > H * .25 and sx < W - H * .25 and sy > H * .24 and sy < H * .76 then
				local clear = true
				for j = 1, #gears do
					if j ~= i then
						local o = gears[j]
						local minD = (GEAR_Z[o.row] + Zs) * .5 * mH * 1.08
						local ddx, ddy = sx - o.x, sy - o.y
						if ddx * ddx + ddy * ddy < minD * minD then clear = false; break end
					end
				end
				if clear then
					satBudget = satBudget - 1
					local th0 = MeshAngle(beta, Zp, g.theta0, Zs)
					gears[#gears + 1] = {
						row = sRow, x = sx, y = sy, parent = i, beta = beta,
						theta0 = th0, theta = th0, engageX = math.max(0, math.min(g.x, sx)), sparked = keepState,
					}
				end
			end
		end
	end

	-- Place and layer every gear sprite (big spoked wheels at sublevel 4; medium & small gears in front at sublevel 5).
	for i = 1, GEARS_MAX do
		local tex, g = c.gears[i], gears[i]
		if g then
			tex:SetDrawLayer("ARTWORK", g.row <= 2 and 4 or 5)
			PlaceIn(tex, content, g.x, g.y, GEAR_SPAN[g.row] * mH, GEAR_SPAN[g.row] * mH)
			SetGearPhase(tex, g.row, g.theta0)
			tex:SetDesaturation(0)
			tex:Show()
		else
			tex:Hide()
		end
	end

	c.warm:SetVertexColor(pal.glow[1], pal.glow[2], pal.glow[3])
	c.meshGlow:SetVertexColor(pal.glow[1], pal.glow[2], pal.glow[3])

	eng = {
		seed = seed, pal = pal, mod = mod, mH = mH, dir = dir, drive = drive,
		dials = dials, gears = gears, grey = keepState and eng.grey or 0,
		W = W, H = H, steamAcc = keepState and eng.steamAcc or 0,
	}
end

local function MakeEngineering()
	palTurn = palTurn % #PALETTES + 1
	BuildLayout(false)
end

local function UpdateEngineering(dt, fillW, casting, state)
	local c, s = content.eng, eng
	local pal, grey = s.pal, s.grey
	local lit = 1 - grey

	-- Advance master drive angle while casting; coast gently over the first .25 s of completion; jam immediately on interrupt.
	if casting then
		local prog = W > 0 and clamp(fillW / W) or 0
		s.drive = s.drive + dt * s.dir * (1.25 + .45 * prog)
	elseif state == "done" and dt > 0 then
		s.drive = s.drive + dt * s.dir * .35 * lit
	end

	-- Shade unpowered clockplate ahead of fillW; warm horological backlight trailing fillW.
	Band(c.shade, fillW, W)
	c.shade:SetAlpha(.46 * (1 - .3 * grey))
	local warmOn = fillW > 2 and lit > .02
	c.warm:SetShown(warmOn)
	if warmOn then
		local ww = math.min(fillW, H * 2.4)
		c.warm:ClearAllPoints()
		c.warm:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", fillW - ww, 0)
		c.warm:SetSize(ww, H)
		c.warm:SetAlpha(.22 * lit)
	end

	-- Background Roman clock dials & Vernier/hairspring rings wake and tick as fillW passes them.
	for i, d in ipairs(s.dials) do
		local slot = c.dials[i]
		local wake = clamp((fillW - (d.x - d.sz * .35)) / math.max(1, H * .55))
		if d.roman then
			if casting and wake > 0 then
				d.sweep = d.sweep + dt * wake * d.rate
			elseif state == "done" and wake > 0 and dt > 0 then
				d.sweep = d.sweep + dt * .25 * d.rate * lit
			end
			local b = lerp(.42, .92, wake)
			slot.tex:SetVertexColor(b, b * (1 - .4 * grey), b * (1 - .4 * grey))
			slot.tex:SetDesaturation(math.max((1 - wake) * .35, grey))
			SetHandPhase(slot.min, d.sweep)
			SetHandPhase(slot.hour, d.h0 + (d.sweep - d.m0) / 12)
			local hb = lerp(.45, 1, wake)
			slot.hour:SetVertexColor(hb, hb * (1 - .45 * grey), hb * (1 - .45 * grey))
			slot.min:SetVertexColor(hb, hb * (1 - .45 * grey), hb * (1 - .45 * grey))
			slot.hour:SetDesaturation(grey); slot.min:SetDesaturation(grey)
		else
			slot.tex:SetAlpha(lerp(.10, .30, wake) * lit)
		end
	end

	-- Compute exact meshed angles down the gear train and engage each gear as fillW reaches its contact point.
	local gears = s.gears
	local activeX, activeY, activeK = nil, nil, 0
	for i, g in ipairs(gears) do
		local liveTheta
		if i == 1 then
			liveTheta = g.theta0 + s.drive
		else
			local p = gears[g.parent]
			liveTheta = MeshAngle(g.beta, GEAR_Z[p.row], p.liveTheta, GEAR_Z[g.row])
		end
		g.liveTheta = liveTheta

		local engK = clamp((fillW - g.engageX) / math.max(1, H * .38))
		local tex = c.gears[i]
		if engK > 0 then
			g.theta = liveTheta
			if casting and not g.sparked and engK > .25 and i > 1 then
				g.sparked = true
				for _ = 1, 3 do Spawn(SPARK, g.engageX + rand(-2, 2), g.y + rand(-.18, .18) * H) end
				Spawn(STEAM, g.engageX, g.y)
			end
			if engK < 1 and engK > activeK then
				activeX, activeY, activeK = g.engageX, g.y, math.sin(engK * PI)
			end
		else
			g.sparked = false
			g.theta = g.theta0
		end
		SetGearPhase(tex, g.row, g.theta)

		local t = pal.tint[g.row]
		local flash = engK > 0 and engK < 1 and (.20 * math.sin(engK * PI) * lit) or 0
		local br = lerp(.34, .92, engK) + flash
		local r = math.min(1, t[1] * br)
		local gg = math.min(1, t[2] * br * (1 - .48 * grey))
		local bb = math.min(1, t[3] * br * (1 - .48 * grey))
		tex:SetVertexColor(r, gg, bb)
		tex:SetDesaturation(math.max((1 - engK) * .42, grey))
	end

	-- Gentle ambient workshop spark / steam wisp near the active meshing front during long casts.
	if casting and fillW > H * .25 and fillW < W - H * .1 then
		s.steamAcc = s.steamAcc + dt * 2.2
		while s.steamAcc >= 1 do
			s.steamAcc = s.steamAcc - 1
			local gy = activeY or H * .5
			if math.random() < .55 then
				Spawn(SPARK, fillW + rand(-3, 2), gy + rand(-.2, .2) * H)
			else
				Spawn(STEAM, fillW + rand(-3, 2), gy + rand(-.15, .15) * H)
			end
		end
	end

	local showMesh = casting and activeX ~= nil and lit > .02
	c.meshGlow:SetShown(showMesh)
	if showMesh then
		PlaceIn(c.meshGlow, content, activeX, activeY, H * 1.15, H * 1.15)
		c.meshGlow:SetAlpha((.18 + .26 * activeK) * lit)
	end
end

---------------------------------------------------------------------------
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "engineering",
	sync = function(c, cf, w, h, t)
		content, cfg, W, H, clock = c, cf, w, h, t
		if eng and content and content.eng and (w ~= eng.W or h ~= eng.H) then
			BuildLayout(true)
		end
	end,
	create = function(c)
		if not c.cfg.engineering then return end
		local e = { dials = {}, gears = {} }
		e.shade = Smooth(c:CreateTexture(nil, "ARTWORK", nil, 1))
		e.shade:SetColorTexture(.02, .025, .035, 1)
		e.shade:Hide()
		e.warm = ContentTex(c, "edge_h", 1, "ADD")
		for i = 1, DIALS_MAX do
			e.dials[i] = {
				tex = ContentTex(c, "eng_dials", 2),
				hour = ContentTex(c, "eng_hands", 3),
				min = ContentTex(c, "eng_hands", 3),
			}
		end
		for i = 1, GEARS_MAX do
			e.gears[i] = ContentTex(c, "eng_gears", 4)
		end
		e.meshGlow = ContentTex(c, "p_soft", 7, "ADD")
		c.eng = e
	end,
	begin = function() if cfg.engineering then MakeEngineering() end end,
	update = function(dt, fillW, casting, state, t)
		clock = t
		if eng then UpdateEngineering(dt, fillW, casting, state) end
	end,
	interrupted = function(k)
		if eng then eng.grey = k end
	end,
	clear = function()
		HideEngineering()
		eng = nil
	end,
})
