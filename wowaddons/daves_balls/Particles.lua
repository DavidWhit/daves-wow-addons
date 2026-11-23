-- daves_balls / Particles.lua
-- Selectable 3D orbital dust patterns (Auto, Halo Ring, Twin Helix, Figure-8,
-- Vortex, Atom Shells, Chaos) with true sphere-rim occlusion, curved 3D comet
-- tails, and independent shimmering stardust trails. Each head, tail segment,
-- and dust-trail speck pairs a rear texture (behind the orb glass) with a front
-- texture (in front of the glass and holder, below the numbers), switching at
-- z = 0 and cleanly eclipsing behind the glass silhouette when z < 0.

local ADDON, ns = ...

local sin, cos, sqrt, atan2 = math.sin, math.cos, math.sqrt, math.atan2
local abs, max, min, floor, ceil, rad, random =
	math.abs, math.max, math.min, math.floor, math.ceil, math.rad, math.random

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local TWO_PI = 2 * math.pi
local THIRD_PI = math.pi / 3
local HELIX_TWISTS = TWO_PI * 1.60
local DUST_MIN_STEP = 0.0145   -- ~60 Hz ceiling (0 skipped frames at 60 FPS; 2x-4x less CPU at 120-240 FPS)

local RING, HELIX, FIG8, VORTEX, ATOM, EDDY = 1, 2, 3, 4, 5, 6
local TAIL_SEGS, TRAIL_DUSTS = 3, 3
local FADE_TIME = 1.0
local GLASS_RADIUS = 0.40      -- matches GLASS_RADIUS in Orbs.lua (60px at 150px orb)

local CONST = {
	MIN_COUNT = 2, MAX_MOTES = 40, DEFAULT_COUNT = 20,
	MIN_SPEED = 0.2, MAX_SPEED = 2.5, DEFAULT_SPEED = 1.0,
	MIN_TAIL_LEN = 20, MAX_TAIL_LEN = 100, DEFAULT_TAIL_LEN = 60,
	MIN_ROTATION = -180, MAX_ROTATION = 180, DEFAULT_ROTATION = 0,
	MIN_SPREAD = 0, MAX_SPREAD = 100, DEFAULT_SPREAD = 25,
	STRUCTURED_COUNT = 5, PATTERN_COUNT = 6,
}

local TAIL_ALPHA_MULT = { 0.72, 0.46, 0.24 }
local TAIL_THICK_MULT = { 0.92, 0.68, 0.44 }
local TRAIL_INTERP_T = { 0.7425, 0.6875, 0.7675 }   -- exact {0.55, 1.25, 2.05} * 1.35 along tail seg j
local TRAIL_ALPHA_MULT = { 0.84, 0.60, 0.38 }
local TRAIL_SIZE_MULT = { 0.58, 0.46, 0.35 }
local TRAIL_DRIFT_MULT = { 0.45, 0.85, 1.35 }
local TRAIL_DRIFT_FREQ = { 2.35, 2.90, 3.45 }       -- 1.8 + j * 0.55
local TRAIL_DRIFT_OFF = { 2.31, 4.62, 6.93 }        -- j * 2.31
local TRAIL_SHIM_F1 = { 1.7, 3.4, 5.1 }             -- j * 1.7
local TRAIL_SHIM_P1 = { 2.13, 4.26, 6.39 }          -- j * 2.13
local TRAIL_SHIM_F2 = { 2.3, 4.6, 6.9 }             -- j * 2.3
local TRAIL_SHIM_P2 = { 3.41, 6.82, 10.23 }         -- j * 3.41
local TRAIL_COLOR_MIX = { 0.55, 0.82, 0.28 }
local TRAIL_WHITE_BOOST = { 0.62, 0.48, 0.55 }

-- Reusable scratch buffers (zero per-frame allocations)
local ptX = { [0] = 0, 0, 0, 0 }
local ptY = { [0] = 0, 0, 0, 0 }
local ptZ = { [0] = 0, 0, 0, 0 }
local ptEnv = { [0] = 0, 0, 0, 0 }
local segDx = { 0, 0, 0 }
local segDy = { 0, 0, 0 }
local segDistBuf = { -1, -1, -1 }
local atomCosI = { [0] = 0.435, 0.435, 0.435 }
local atomSinI = { [0] = 0.900, 0.900, 0.900 }
local frame = {}

ns.DUST_PATTERN_ORDER = { "auto", "ring", "helix", "figure8", "vortex", "atom", "chaos" }

ns.DUST_PATTERNS = {
	auto    = { label = "Auto",        short = "Auto",   desc = "Cycles all particles together cleanly from one orbital pattern to the next." },
	ring    = { label = "Halo Ring",   short = "Ring",   desc = "Unified planetary ring orbiting cleanly around the orb." },
	helix   = { label = "Twin Helix",  short = "Helix",  desc = "Two intertwined helical strands spiraling in unison." },
	figure8 = { label = "Figure-8",    short = "Fig-8",  desc = "Synchronized 3D infinity-loop weaving around the orb." },
	vortex  = { label = "Vortex",      short = "Vortex", desc = "Swirling cyclone rising cleanly out of the holder." },
	atom    = { label = "Atom Shells", short = "Atom",   desc = "Three crisp intersecting orbital rings precessing in 3D." },
	chaos   = { label = "Chaos",       short = "Chaos",  desc = "Freeform mixed random swarm drifting independently." },
}

local PATTERN_KEY_TO_ID = {
	ring = RING, helix = HELIX, figure8 = FIG8,
	vortex = VORTEX, atom = ATOM,
}

local SYNC_DB_KEYS = {
	enabled = "dustEnabled", pattern = "dustPattern",
	tails = "dustTails", trails = "dustTrails",
}

local function Clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi end
	return v
end

local function SmoothStep01(u)
	if u <= 0 then return 0 elseif u >= 1 then return 1 end
	return u * u * (3 - 2 * u)
end

-- Fast rear-hemisphere sphere-rim occlusion (only called when z < 0):
-- skips sqrt for >90% of rear points (strictly inside/outside the 14% rim band).
local function SphereOcclusionRear(px, pyRelOrb)
	local r2 = px * px + pyRelOrb * pyRelOrb
	if r2 <= frame.glassInner2 then return 0 end
	if r2 >= frame.glassOuter2 then return 1 end
	local u = (sqrt(r2) - frame.glassInner) * frame.invGlassBand
	return u * u * (3 - 2 * u)
end

local function ResolveBool(val, dbKey, fallback)
	if val ~= nil then return val == true end
	if ns.db and ns.db[dbKey] ~= nil then return ns.db[dbKey] == true end
	return fallback
end

local function ClampInt(val, lo, hi, fallback)
	local n = tonumber(val)
	if not n then return fallback end
	return floor(Clamp(floor(n + 0.5), lo, hi))
end

function ns.NormalizeDustPattern(pattern)
	if type(pattern) == "string" then
		if ns.DUST_PATTERNS[pattern] then return pattern end
		local key = pattern:lower()
		if ns.DUST_PATTERNS[key] then return key end
	end
	return "auto"
end

function ns.NormalizeDustCount(count) return ClampInt(count, CONST.MIN_COUNT, CONST.MAX_MOTES, CONST.DEFAULT_COUNT) end
function ns.NormalizeDustSpeed(speed) local n = tonumber(speed); return n and Clamp(n, CONST.MIN_SPEED, CONST.MAX_SPEED) or CONST.DEFAULT_SPEED end
function ns.NormalizeDustTailLength(len) return ClampInt(len, CONST.MIN_TAIL_LEN, CONST.MAX_TAIL_LEN, CONST.DEFAULT_TAIL_LEN) end
function ns.NormalizeDustRotation(deg) return ClampInt(deg, CONST.MIN_ROTATION, CONST.MAX_ROTATION, CONST.DEFAULT_ROTATION) end
function ns.NormalizeDustSpread(spread) return ClampInt(spread, CONST.MIN_SPREAD, CONST.MAX_SPREAD, CONST.DEFAULT_SPREAD) end

function ns:GetOrbDustConfig(orb)
	if not (ns.db and orb) then
		return {
			enabled = false, pattern = "auto", count = CONST.DEFAULT_COUNT,
			speed = CONST.DEFAULT_SPEED, tails = true, trails = true,
			tailLength = CONST.DEFAULT_TAIL_LEN,
			rotation = CONST.DEFAULT_ROTATION, spread = CONST.DEFAULT_SPREAD,
		}
	end
	ns.db.orbDust = ns.db.orbDust or {}
	local cfg = ns.db.orbDust[orb.key]
	if not cfg then
		cfg = {
			enabled = ResolveBool(nil, "dustEnabled", false),
			pattern = ns.NormalizeDustPattern(ns.db.dustPattern),
			count = ns.NormalizeDustCount(ns.db.dustCount),
			speed = ns.NormalizeDustSpeed(ns.db.dustSpeed),
			tails = ResolveBool(nil, "dustTails", true),
			trails = ResolveBool(nil, "dustTrails", true),
			tailLength = ns.NormalizeDustTailLength(ns.db.dustTailLength),
			rotation = ns.NormalizeDustRotation(ns.db.dustRotation),
			spread = ns.NormalizeDustSpread(ns.db.dustSpread),
		}
		ns.db.orbDust[orb.key] = cfg
	end
	cfg.enabled = ResolveBool(cfg.enabled, "dustEnabled", false)
	cfg.pattern = ns.NormalizeDustPattern(cfg.pattern ~= nil and cfg.pattern or ns.db.dustPattern)
	cfg.count = ns.NormalizeDustCount(cfg.count ~= nil and cfg.count or ns.db.dustCount)
	cfg.speed = ns.NormalizeDustSpeed(cfg.speed ~= nil and cfg.speed or ns.db.dustSpeed)
	cfg.tails = ResolveBool(cfg.tails, "dustTails", true)
	cfg.trails = ResolveBool(cfg.trails, "dustTrails", true)
	cfg.tailLength = ns.NormalizeDustTailLength(cfg.tailLength ~= nil and cfg.tailLength or ns.db.dustTailLength)
	cfg.rotation = ns.NormalizeDustRotation(cfg.rotation ~= nil and cfg.rotation or ns.db.dustRotation)
	cfg.spread = ns.NormalizeDustSpread(cfg.spread ~= nil and cfg.spread or ns.db.dustSpread)
	if cfg.seed ~= nil then cfg.seed = nil end
	return cfg
end

local function CacheOrbDustConfig(p, cfg)
	p.enabled = cfg.enabled
	p.modeKey = cfg.pattern
	p.count = cfg.count
	p.speed = cfg.speed
	p.tails = cfg.tails
	p.trails = cfg.trails
	p.tailFrac = cfg.tailLength * 0.01
	p.rotRad = rad(cfg.rotation)
	p.spreadFrac = cfg.spread * 0.01
end

---------------------------------------------------------------------------
-- Pool visibility & coloring helpers (state-tracked: zero redundant Hide())
---------------------------------------------------------------------------
local function HideMoteTails(m)
	local tState, tFront, tBack = m.tState, m.tFront, m.tBack
	for k = 1, TAIL_SEGS do
		local st = tState[k]
		if st ~= 0 then
			if st == 1 then tFront[k]:Hide() else tBack[k]:Hide() end
			tState[k] = 0
		end
	end
end

local function HideMoteDustTrails(m)
	local dState, dFront, dBack = m.dState, m.dFront, m.dBack
	for j = 1, TRAIL_DUSTS do
		local st = dState[j]
		if st ~= 0 then
			if st == 1 then dFront[j]:Hide() else dBack[j]:Hide() end
			dState[j] = 0
		end
	end
end

local function HideMote(m)
	if not m.anyVisible then return end
	local st = m.hState
	if st ~= 0 then
		if st == 1 then m.front:Hide() else m.back:Hide() end
		m.hState = 0
	end
	HideMoteTails(m)
	HideMoteDustTrails(m)
	m.anyVisible = false
end

local function ApplyMoteColor(p, m)
	local mix = m.colorMix or 0.5
	local wb = m.whiteBoost or 0.2
	local r = p.lr + (p.ar - p.lr) * mix
	local g = p.lg + (p.ag - p.lg) * mix
	local b = p.lb + (p.ab - p.lb) * mix

	local hr, hg, hb = r + (1 - r) * wb, g + (1 - g) * wb, b + (1 - b) * wb
	m.back:SetVertexColor(hr, hg, hb)
	m.front:SetVertexColor(hr, hg, hb)

	-- Comet tails stay richer in the orb's liquid/accent hue behind the bright head.
	local twb = wb * 0.42
	local tr, tg, tb = r + (1 - r) * twb, g + (1 - g) * twb, b + (1 - b) * twb
	for k = 1, TAIL_SEGS do
		m.tBack[k]:SetVertexColor(tr, tg, tb)
		m.tFront[k]:SetVertexColor(tr, tg, tb)
	end

	-- Shimmering dust-trail specks glint between starlight-white, warm accent
	-- gold, and orb liquid glow for a crystalline stardust wake.
	for j = 1, TRAIL_DUSTS do
		local dMix, dWb = TRAIL_COLOR_MIX[j], TRAIL_WHITE_BOOST[j]
		local br = p.lr + (p.ar - p.lr) * dMix
		local bg = p.lg + (p.ag - p.lg) * dMix
		local bb = p.lb + (p.ab - p.lb) * dMix
		local dr, dg, db = br + (1 - br) * dWb, bg + (1 - bg) * dWb, bb + (1 - bb) * dWb
		m.dBack[j]:SetVertexColor(dr, dg, db)
		m.dFront[j]:SetVertexColor(dr, dg, db)
	end
end

---------------------------------------------------------------------------
-- Unified formation state & individual mote lifecycle
---------------------------------------------------------------------------
local function InitMoodForPattern(p, pat)
	p.moodPattern = pat
	p.moodGen = (p.moodGen or 0) + 1
	p.moodDir = (random() < 0.5) and 1 or -1
	-- Anchor each pattern around a predictable home orientation so the user's
	-- Pattern rotation slider points the formation cleanly where they aim it.
	p.moodHomeTilt = (pat == RING) and 0.24 or 0
	p.moodTilt = p.moodHomeTilt
	p.moodYaw = random() * TWO_PI
	p.moodYawRate = ((random() < 0.5) and 1 or -1) * (0.18 + random() * 0.12)
	p.helixPhase = p.moodYaw
	p.moodTimer = 16 + random() * 6
end

local function PickNextAutoMood(p)
	local pat = random(1, CONST.STRUCTURED_COUNT)
	if pat == (p.moodPattern or 0) then
		pat = (pat % CONST.STRUCTURED_COUNT) + 1
	end
	InitMoodForPattern(p, pat)
end

local function StepFormationMood(p, elapsed, modeKey, count)
	if modeKey == "chaos" then return end
	p.moodYaw = (p.moodYaw + elapsed * p.moodYawRate) % TWO_PI
	local home = p.moodHomeTilt or 0
	local pat = p.moodPattern
	if pat == HELIX then
		p.moodTilt = home + sin(p.moodYaw * 0.45) * 0.08
	elseif pat == VORTEX then
		p.moodTilt = home + sin(p.moodYaw * 0.35) * 0.05
	elseif pat == ATOM then
		p.moodTilt = home + sin(p.moodYaw * 0.40) * 0.12
	else
		p.moodTilt = home + sin(p.moodYaw * 0.40) * 0.06
	end

	if modeKey == "auto" then
		p.moodTimer = p.moodTimer - elapsed
		if p.moodTimer <= 0 then
			local prevTilt = p.moodTilt
			PickNextAutoMood(p)
			local denom = (count > 1) and (count - 1) or 1
			for i = 1, count do
				local m = p.motes[i]
				if m then
					local dur = 0.75 + ((i - 1) / denom) * 0.55
					m.fadeOutDur, m.fadeOutRem = dur, dur
					m.frozenTilt = prevTilt
					m.fadeCosT = nil
				end
			end
		end
	end
end

local function ConfigureStructuredMote(p, m, pat, size, dir, idx, nSlots, initial)
	local speedBand = 0.94 + random() * 0.12
	local slotFrac = (idx - 1) / nSlots
	m.lifeMax = 20 + random() * 10
	m.age = initial and (FADE_TIME + random() * (m.lifeMax - FADE_TIME * 2.5)) or 0
	m.rRand = (random() - 0.5) * 2
	m.ryRand = (random() - 0.5) * 2
	m.yRand = (random() - 0.5) * 2
	m.tRand = (random() - 0.5) * 2

	if pat == RING then
		m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = size * 0.58, size * 0.20, 0, size * 0.015
		m.harmPhase = (random() - 0.5) * 0.25
		m.phase = (slotFrac * TWO_PI + (random() - 0.5) * 0.10) % TWO_PI
		m.tilt = p.moodTilt
		m.omega = dir * 0.88 * speedBand
	elseif pat == HELIX then
		local halfCount = max(1, ceil(nSlots / 2))
		local strandSlot = floor((idx - 1) / 2)
		m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = size * 0.58, size * 0.17, 0, size * 0.016
		m.riseSpan = size * 0.48
		m.tilt = p.moodTilt
		m.phase = ((p.helixPhase or p.moodYaw or 0) + (random() - 0.5) * 0.06) % TWO_PI
		m.omega = dir * 0.28
		m.liftRate = 0.20 * speedBand
		m.lift = initial and Clamp((strandSlot + 0.5) / halfCount + (random() - 0.5) * 0.03, 0.02, 0.98)
			or (0.001 + (strandSlot / halfCount) * 0.06)
	elseif pat == FIG8 then
		m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = size * 0.61, size * 0.24, 0, 0
		m.phase = (slotFrac * TWO_PI + (random() - 0.5) * 0.10) % TWO_PI
		m.tilt = p.moodTilt
		m.omega = dir * 0.80 * speedBand
	elseif pat == VORTEX then
		m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = size * 0.60, size * 0.17, 0, 0
		m.yBase, m.riseSpan = -size * 0.48, size * 1.06
		m.tilt = p.moodTilt
		m.omega = dir * 1.55 * speedBand
		m.liftRate = 0.17 * speedBand
		if initial then
			m.lift = Clamp((idx - 0.5) / nSlots + (random() - 0.5) * 0.03, 0.02, 0.98)
			m.phase = (m.lift * TWO_PI * 2.2 + (idx % 3) * (TWO_PI / 3)) % TWO_PI
		else
			m.lift = 0.001
			m.phase = ((idx % 3) * (TWO_PI / 3) + random() * 0.45) % TWO_PI
		end
	else
		-- ATOM: 3 crisp intersecting shells spaced by 60 degrees.
		local perShell = max(1, ceil(nSlots / 3))
		local inShell = floor((idx - 1) / 3)
		local inc = 1.12 + 0.10 * sin(p.moodYaw + m.shellIdx * 2.0944)
		m.cosI, m.sinI = cos(inc), sin(inc)
		m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = size * 0.60, size * 0.18, 0, 0
		m.tilt = p.moodTilt + m.shellIdx * THIRD_PI
		m.phase = ((inShell / perShell) * TWO_PI + m.shellIdx * 0.65 + (random() - 0.5) * 0.10) % TWO_PI
		m.omega = dir * 1.05 * speedBand
	end
	m.rx, m.ry, m.yOff, m.waveAmp = m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp
end

local function ConfigureChaosMote(m, pat, size, dir, initial)
	m.lifeMax = 7 + random() * 8
	m.age = initial and (m.lifeMax * (0.14 + random() * 0.72)) or 0
	m.phase = random() * TWO_PI
	m.harmPhase = random() * TWO_PI
	m.precessRate = ((random() < 0.5) and 1 or -1) * (0.05 + random() * 0.12)
	m.rRand = (random() - 0.5) * 2
	m.ryRand = (random() - 0.5) * 2
	m.yRand = (random() - 0.5) * 2
	m.tRand = (random() - 0.5) * 2

	if pat == RING then
		m.rx, m.ry = size * (0.54 + random() * 0.14), size * (0.15 + random() * 0.11)
		m.yOff = size * (-0.08 + random() * 0.16)
		m.waveAmp = size * (0.025 + random() * 0.035)
		m.tilt, m.omega = (random() - 0.5) * 1.05, dir * (0.55 + random() * 0.55)
	elseif pat == HELIX then
		m.strand = (random() < 0.5) and 1 or -1
		m.strandOffset = (m.strand > 0) and 0 or math.pi
		m.rx, m.ry = size * (0.54 + random() * 0.11), size * (0.13 + random() * 0.08)
		m.riseSpan = size * (0.42 + random() * 0.10)
		m.waveAmp = size * (0.02 + random() * 0.025)
		m.tilt, m.omega = (random() - 0.5) * 0.64, dir * (0.25 + random() * 0.35)
		m.liftRate = 0.15 + random() * 0.12
		m.lift = initial and (0.08 + random() * 0.80) or 0.001
	elseif pat == FIG8 then
		m.rx, m.ry = size * (0.56 + random() * 0.12), size * (0.22 + random() * 0.10)
		m.yOff = size * (-0.06 + random() * 0.12)
		m.tilt, m.omega = (random() - 0.5) * 0.90, dir * (0.55 + random() * 0.45)
	elseif pat == VORTEX then
		m.rx, m.ry = size * (0.54 + random() * 0.11), size * (0.13 + random() * 0.07)
		m.yBase, m.riseSpan = size * (-0.50 + random() * 0.06), size * (1.00 + random() * 0.16)
		m.tilt, m.omega = (random() - 0.5) * 0.28, dir * (0.95 + random() * 0.65)
		m.liftRate = 0.12 + random() * 0.09
		m.lift = initial and (0.08 + random() * 0.78) or 0.001
	elseif pat == ATOM then
		local inc = 1.00 + random() * 0.26
		m.cosI, m.sinI = cos(inc), sin(inc)
		m.rx, m.ry = size * (0.55 + random() * 0.12), size * 0.18
		m.tilt, m.omega = random() * TWO_PI, dir * (0.72 + random() * 0.52)
	else
		m.rx, m.ry = size * (0.54 + random() * 0.13), size * (0.14 + random() * 0.10)
		m.yOff = size * (-0.10 + random() * 0.20)
		m.waveAmp = size * (0.13 + random() * 0.13)
		m.tilt, m.omega = (random() - 0.5) * 0.80, dir * (0.45 + random() * 0.48)
	end
	m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = m.rx, m.ry, m.yOff, m.waveAmp
end

local function ApplyMoteSpread(p, m, spreadFrac)
	local orbSize = p.orbSize
	local minRx, minRy = orbSize * 0.46, orbSize * 0.06
	if not m.isChaos then
		m.rx = max(minRx, m.baseRx + m.rRand * orbSize * 0.20 * spreadFrac)
		m.ry = max(minRy, m.baseRy + m.ryRand * orbSize * 0.11 * spreadFrac)
		m.yOff = m.baseYOff + m.yRand * orbSize * 0.22 * spreadFrac
		m.waveAmp = m.baseWaveAmp * (0.4 + 1.4 * spreadFrac)
		local tiltOff = ((m.pattern == ATOM) and (m.shellIdx * THIRD_PI) or 0) + m.tRand * 0.44 * spreadFrac
		m.tiltOff = tiltOff
		m.cosOff, m.sinOff = cos(tiltOff), sin(tiltOff)
	else
		m.rx = max(minRx, m.baseRx * (0.82 + 0.36 * spreadFrac) + m.rRand * orbSize * 0.14 * spreadFrac)
		m.ry = max(minRy, m.baseRy * (0.70 + 0.60 * spreadFrac))
		m.yOff = m.baseYOff * (0.40 + 1.20 * spreadFrac)
		m.waveAmp = m.baseWaveAmp * (0.40 + 1.20 * spreadFrac)
	end
	m.appliedSpread = spreadFrac
	m.fadeCosT = nil
end

local function RespawnMote(p, m, modeKey, initial, slot, slotCount)
	local size = p.orbSize
	local isChaos = (modeKey == "chaos")
	local pat = isChaos and random(1, CONST.PATTERN_COUNT)
		or (PATTERN_KEY_TO_ID[modeKey] or p.moodPattern or RING)
	local nSlots = (slotCount and slotCount > 0) and slotCount or 1
	local idx = slot or m.index or 1

	m.pattern, m.isChaos, m.moodGen = pat, isChaos, p.moodGen or 0
	m.fadeOutRem, m.fadeOutDur, m.frozenTilt, m.fadeCosT = nil, nil, nil, nil
	m.appliedSpread = nil

	local r = random()
	local isWisp = (r > 0.58 and r <= 0.82)
	local isSpark = (r > 0.82)
	local newKind = isWisp and 2 or (isSpark and 3 or 1)
	if m.kind ~= newKind then
		local texPath = MEDIA .. (isWisp and "OrbWisp" or "OrbMote")
		m.back:SetTexture(texPath)
		m.front:SetTexture(texPath)
		if not isWisp then
			m.back:SetRotation(0)
			m.front:SetRotation(0)
		end
		m.kind = newKind
	end

	local dir = isChaos and ((random() < 0.5) and 1 or -1) or (p.moodDir or 1)
	m.dir = dir
	m.lift, m.liftRate = 0, 0
	m.shellIdx = (idx - 1) % 3
	m.strand = ((idx % 2) == 0) and 1 or -1
	m.strandOffset = (m.strand > 0) and 0 or math.pi
	m.harmPhase, m.harmPhase2 = 0, random() * TWO_PI
	m.freq2, m.freq3 = 0.65 + random() * 0.55, 1.15 + random() * 0.75
	m.yOff, m.yBase, m.riseSpan, m.waveAmp = 0, 0, 0, 0
	m.cosI, m.sinI, m.precessRate = 0.435, 0.900, 0

	if not isChaos then
		ConfigureStructuredMote(p, m, pat, size, dir, idx, nSlots, initial)
	else
		ConfigureChaosMote(m, pat, size, dir, initial)
	end

	m.cosH, m.sinH = cos(m.harmPhase), sin(m.harmPhase)
	m.cosT, m.sinT, m.cosOff, m.sinOff, m.tiltOff = cos(m.tilt), sin(m.tilt), 1, 0, 0
	m.baseW = isWisp and (6.2 + random() * 4.4)
		or (isSpark and (3.8 + random() * 3.6) or (4.6 + random() * 4.2))
	m.baseH = isWisp and (m.baseW * 0.46) or m.baseW
	m.dustBaseSize = max(4.4, m.baseW)
	m.twinkleRate, m.twinklePhase = 1.8 + random() * 3.4, random() * TWO_PI
	m.shimmerRate, m.shimmerRate2 = 6.5 + random() * 4.5, 9.5 + random() * 5.5
	m.shimmerPhase, m.shimmerPhase2 = random() * TWO_PI, random() * TWO_PI
	m.baseAlpha = isSpark and (0.64 + random() * 0.32) or (0.48 + random() * 0.34)
	m.colorMix = random()
	m.whiteBoost = isSpark and 0.44 or (isWisp and 0.26 or 0.20)
	m.angRate = abs(m.omega) + ((pat == HELIX) and (abs(m.liftRate) * HELIX_TWISTS) or 0)
	-- Invalidate head cached geometry so newly respawned motes write cleanly.
	m.hW, m.hH, m.hA, m.hR, m.hX = -1, -1, -1, 999, 9999
	ApplyMoteColor(p, m)
end

local function ReformSwarm(p, modeKey, count)
	if modeKey ~= "chaos" then
		local targetPat = PATTERN_KEY_TO_ID[modeKey]
		if targetPat then
			InitMoodForPattern(p, targetPat)
		else
			local cur = p.moodPattern
			if not cur or cur < 1 or cur > CONST.STRUCTURED_COUNT then
				PickNextAutoMood(p)
			else
				InitMoodForPattern(p, cur)
			end
		end
	else
		p.moodGen = (p.moodGen or 0) + 1
	end

	p.appliedPattern = modeKey
	local slotCount = (count and count > 0) and count or #p.motes
	for i = 1, #p.motes do
		RespawnMote(p, p.motes[i], modeKey, true, i, slotCount)
	end
end

-- Anchor every pooled texture ONCE at creation so animation updates use
-- SetPointsOffset(x, y) without ClearAllPoints()+SetPoint() anchor rebuilds.
local function MakePairedTextures(vis, frontFrame, count, texPath)
	local backList, frontList = {}, {}
	for k = 1, count do
		local tb = vis:CreateTexture(nil, "ARTWORK", nil, -2)
		tb:SetTexture(texPath)
		tb:SetBlendMode("ADD")
		tb:SetPoint("CENTER", vis, "CENTER", 0, 0)
		tb:Hide()
		backList[k] = tb

		local tf = frontFrame:CreateTexture(nil, "ARTWORK", nil, 5)
		tf:SetTexture(texPath)
		tf:SetBlendMode("ADD")
		tf:SetPoint("CENTER", vis, "CENTER", 0, 0)
		tf:Hide()
		frontList[k] = tf
	end
	return backList, frontList
end

local function EnsurePool(p, targetCount, modeKey)
	local motes = p.motes
	local cur = #motes
	if cur >= targetCount then return end
	local vis, frontFrame = p.visual, p.holderFront
	local tailTex, moteTex = MEDIA .. "OrbTail", MEDIA .. "OrbMote"

	for i = cur + 1, targetCount do
		local tBack, tFront = MakePairedTextures(vis, frontFrame, TAIL_SEGS, tailTex)
		local dBack, dFront = MakePairedTextures(vis, frontFrame, TRAIL_DUSTS, moteTex)
		local back = vis:CreateTexture(nil, "ARTWORK", nil, -2)
		back:SetBlendMode("ADD")
		back:SetPoint("CENTER", vis, "CENTER", 0, 0)
		back:Hide()
		local front = frontFrame:CreateTexture(nil, "ARTWORK", nil, 5)
		front:SetBlendMode("ADD")
		front:SetPoint("CENTER", vis, "CENTER", 0, 0)
		front:Hide()

		local m = {
			index = i, back = back, front = front, anyVisible = false,
			tBack = tBack, tFront = tFront, dBack = dBack, dFront = dFront,
			hState = 0, hX = 9999, hY = 9999, hW = -1, hH = -1, hA = -1, hR = 999,
			tState = { 0, 0, 0 }, tX = { 9999, 9999, 9999 }, tY = { 9999, 9999, 9999 },
			tW = { -1, -1, -1 }, tH = { -1, -1, -1 }, tA = { -1, -1, -1 }, tR = { 999, 999, 999 },
			dState = { 0, 0, 0 }, dX = { 9999, 9999, 9999 }, dY = { 9999, 9999, 9999 },
			dS = { -1, -1, -1 }, dA = { -1, -1, -1 },
		}
		motes[i] = m
		RespawnMote(p, m, modeKey or p.appliedPattern or "auto", true, i, targetCount)
	end
end

---------------------------------------------------------------------------
-- Analytic 3D orbital curve sampler (angle-addition recurrence, 0 allocs)
-- Samples head (k=0) and optionally nPts evenly spaced trailing points into
-- ptX/ptY/ptZ/ptEnv so k=1..nPts cost 0 trig calls in structured patterns.
---------------------------------------------------------------------------
local function SampleCurveUniform(m, nPts, phaseStep, liftStep, sloshScale)
	local pat = m.pattern
	local phase, lift = m.phase, m.lift
	local cosT, sinT = m.cosT, m.sinT

	if pat == RING then
		local rx, ry, yOff, waveAmp = m.rx * sloshScale, m.ry, m.yOff, m.waveAmp
		local cosH, sinH = m.cosH, m.sinH
		local c, s = cos(phase), sin(phase)
		local cd, sd
		if nPts > 0 then cd, sd = cos(phaseStep), sin(phaseStep) end
		for k = 0, nPts do
			local ox = c * rx
			local oy = yOff + s * ry + ((2 * s * c) * cosH + (c * c - s * s) * sinH) * waveAmp
			ptX[k], ptY[k], ptZ[k], ptEnv[k] = ox * cosT - oy * sinT, ox * sinT + oy * cosT, s, 1
			if k < nPts then c, s = c * cd + s * sd, s * cd - c * sd end
		end
	elseif pat == FIG8 then
		local rx, ry, yOff = m.rx * sloshScale, m.ry, m.yOff
		local c, s = cos(phase), sin(phase)
		local cd, sd
		if nPts > 0 then cd, sd = cos(phaseStep), sin(phaseStep) end
		for k = 0, nPts do
			local ox, oy = s * rx, (2 * s * c) * ry + yOff
			ptX[k], ptY[k], ptZ[k], ptEnv[k] = ox * cosT - oy * sinT, ox * sinT + oy * cosT, c, 1
			if k < nPts then c, s = c * cd + s * sd, s * cd - c * sd end
		end
	elseif pat == ATOM then
		local rx, cosI, sinI = m.rx * sloshScale, m.cosI, m.sinI
		local c, s = cos(phase), sin(phase)
		local cd, sd
		if nPts > 0 then cd, sd = cos(phaseStep), sin(phaseStep) end
		for k = 0, nPts do
			local ox, oy = c * rx, s * cosI * rx
			ptX[k], ptY[k], ptZ[k], ptEnv[k] = ox * cosT - oy * sinT, ox * sinT + oy * cosT, s * sinI, 1
			if k < nPts then c, s = c * cd + s * sd, s * cd - c * sd end
		end
	elseif pat == VORTEX then
		local rx, ry, yBase, riseSpan = m.rx * sloshScale, m.ry, m.yBase, m.riseSpan
		local c, s = cos(phase), sin(phase)
		local cd, sd
		if nPts > 0 then cd, sd = cos(phaseStep), sin(phaseStep) end
		for k = 0, nPts do
			local lf = lift - k * liftStep
			local env, u = 0, 0
			if lf >= 1 then
				u = 1
			elseif lf > 0 then
				u = lf
				if lf < 0.15 then
					local e = lf * 6.6666667; env = e * e * (3 - 2 * e)
				elseif lf > 0.75 then
					local e = (1 - lf) * 4; env = e * e * (3 - 2 * e)
				else
					env = 1
				end
			end
			local ox = c * rx * (0.56 + 0.58 * (0.35 * u + 0.65 * sqrt(u)))
			local oy = yBase + u * riseSpan + s * ry * (0.50 + 0.50 * u)
			ptX[k], ptY[k], ptZ[k], ptEnv[k] = ox * cosT - oy * sinT, ox * sinT + oy * cosT, s, env
			if k < nPts then c, s = c * cd + s * sd, s * cd - c * sd end
		end
	elseif pat == HELIX then
		local rxBase, ry, riseSpan, waveAmp = m.rx * sloshScale, m.ry, m.riseSpan, m.waveAmp
		local dir, strand = m.dir, m.strand
		local ang0 = dir * (lift * HELIX_TWISTS) + phase + m.strandOffset
		local c, s = cos(ang0), sin(ang0)
		local cd, sd
		if nPts > 0 then
			local dAng = dir * (liftStep * HELIX_TWISTS) + phaseStep
			cd, sd = cos(dAng), sin(dAng)
		end
		for k = 0, nPts do
			local lf = lift - k * liftStep
			local env, uNorm = 0, 0
			if lf >= 1 then
				uNorm = 1
			elseif lf > 0 then
				uNorm = lf
				if lf < 0.16 then
					local e = lf * 6.25; env = e * e * (3 - 2 * e)
				elseif lf > 0.82 then
					local e = (1 - lf) * 5.5555556; env = e * e * (3 - 2 * e)
				else
					env = 1
				end
			end
			local u = (uNorm - 0.5) * 2
			local ox = c * rxBase * (0.88 + 0.14 * (1 - u * u))
			local oy = u * riseSpan + s * ry + strand * c * waveAmp
			ptX[k], ptY[k], ptZ[k], ptEnv[k] = ox * cosT - oy * sinT, ox * sinT + oy * cosT, s, env
			if k < nPts then c, s = c * cd + s * sd, s * cd - c * sd end
		end
	else
		local rxBase, ry, yOff, waveAmp = m.rx * sloshScale, m.ry, m.yOff, m.waveAmp
		local freq2, freq3, h1, h2 = m.freq2, m.freq3, m.harmPhase, m.harmPhase2
		for k = 0, nPts do
			local ph = phase - k * phaseStep
			local rx = rxBase * (1 + 0.14 * sin(ph * freq2 + h1))
			local ang = ph + 0.48 * sin(ph * freq2 + h2)
			local c, s = cos(ang), sin(ang)
			local ox = c * rx
			local oy = yOff + s * ry * 0.55
				+ sin(ph * freq3 + h1) * waveAmp
				+ cos(ph * freq2 * 0.7 + h2) * waveAmp * 0.42
			ptX[k], ptY[k], ptZ[k], ptEnv[k] = ox * cosT - oy * sinT, ox * sinT + oy * cosT, s, 1
		end
	end
end

---------------------------------------------------------------------------
-- Curved 3D comet tail & shimmering dust trail renderers (dirty-tracked)
---------------------------------------------------------------------------
local function LayoutMoteTails(m, lifeEnv, litBoost, flashBoost)
	local isWisp = (m.kind == 2)
	local baseThick = isWisp and (m.baseW * 0.62) or (m.baseW * 0.90)
	-- Steady average head glow (0.72) keeps comet tails silky without per-tick twinkle SetAlpha churn.
	local baseTerm = m.baseAlpha * 0.72 * litBoost
	local flashTerm = flashBoost * 0.45
	local dustBobY, orbBobY = frame.dustBobY, frame.orbBobY
	local gi2, go2 = frame.glassInner2, frame.glassOuter2
	local tState, tFront, tBack = m.tState, m.tFront, m.tBack
	local tX, tY, tW, tH, tA, tR = m.tX, m.tY, m.tW, m.tH, m.tA, m.tR
	local headAngle

	for k = 1, TAIL_SEGS do
		local prevX, prevY, prevZ, prevEnv = ptX[k - 1], ptY[k - 1], ptZ[k - 1], ptEnv[k - 1]
		local curX, curY, curZ, curEnv = ptX[k], ptY[k], ptZ[k], ptEnv[k]
		local dx, dy = prevX - curX, prevY - curY
		segDx[k], segDy[k], segDistBuf[k] = dx, dy, -1

		local hideSeg = (prevEnv <= 0 or curEnv <= 0)
		local segZ, mx, my, occ
		if not hideSeg then
			segZ = (prevZ + curZ) * 0.5
			mx = (prevX + curX) * 0.5
			my = (prevY + curY) * 0.5 + dustBobY
			if segZ >= 0 then
				occ = 1
			else
				local ry = my - orbBobY
				local r2 = mx * mx + ry * ry
				if r2 <= gi2 then
					hideSeg = true
				elseif r2 >= go2 then
					occ = 1
				else
					local u = (sqrt(r2) - frame.glassInner) * frame.invGlassBand
					occ = u * u * (3 - 2 * u)
				end
			end
		end

		local segDist, segAlpha, segDepth01
		if not hideSeg then
			local dist2 = dx * dx + dy * dy
			if dist2 < 0.0225 then
				hideSeg = true
			else
				segDist = sqrt(dist2)
				segDistBuf[k] = segDist
				segDepth01 = (segZ + 1) * 0.5
				if segDepth01 < 0 then segDepth01 = 0 elseif segDepth01 > 1 then segDepth01 = 1 end
				segAlpha = (baseTerm * (0.54 + 0.46 * segDepth01) + flashTerm)
					* lifeEnv * ((prevEnv + curEnv) * 0.5) * TAIL_ALPHA_MULT[k] * occ
				if segAlpha > 1 then segAlpha = 1 end
				if segDist < 0.45 then segAlpha = segAlpha * (segDist / 0.45) end
				if segAlpha < 0.015 then hideSeg = true end
			end
		end

		if hideSeg then
			local st = tState[k]
			if st ~= 0 then
				if st == 1 then tFront[k]:Hide() else tBack[k]:Hide() end
				tState[k] = 0
			end
		else
			local rot = atan2(dy, dx)
			if k == 1 and isWisp then headAngle = rot end
			local segH = baseThick * (0.68 + 0.50 * segDepth01) * TAIL_THICK_MULT[k]
			local segW = max(segH * 1.15, segDist * 1.48)
			local want = (segZ >= 0) and 1 or -1
			local active = (want == 1) and tFront[k] or tBack[k]
			local st = tState[k]

			if st == want then
				if abs(segW - tW[k]) > 0.80 or abs(segH - tH[k]) > 0.35 then active:SetSize(segW, segH); tW[k], tH[k] = segW, segH end
				if abs(mx - tX[k]) > 0.20 or abs(my - tY[k]) > 0.20 then active:SetPointsOffset(mx, my); tX[k], tY[k] = mx, my end
				if abs(rot - tR[k]) > 0.035 then active:SetRotation(rot); tR[k] = rot end
				if abs(segAlpha - tA[k]) > 0.025 then active:SetAlpha(segAlpha); tA[k] = segAlpha end
			else
				if st == 1 then tFront[k]:Hide() elseif st == -1 then tBack[k]:Hide() end
				active:SetSize(segW, segH)
				active:SetPointsOffset(mx, my)
				active:SetRotation(rot)
				active:SetAlpha(segAlpha)
				active:Show()
				tState[k] = want
				m.anyVisible = true
				tW[k], tH[k], tX[k], tY[k], tR[k], tA[k] = segW, segH, mx, my, rot, segAlpha
			end
		end
	end

	return headAngle
end

local function LayoutMoteDustTrails(m, lifeEnv, litBoost, flashBoost, hasSegDeltas)
	local t = frame.t
	local dustBobY, orbBobY = frame.dustBobY, frame.orbBobY
	local driftBase, innerSafe2 = frame.driftBase, frame.innerSafe2
	local gi2, go2 = frame.glassInner2, frame.glassOuter2
	local baseSize = m.dustBaseSize
	local shRate1, shRate2 = m.shimmerRate, m.shimmerRate2
	local shPhase1, shPhase2 = m.shimmerPhase, m.shimmerPhase2
	local litTerm, flashTerm = 0.84 * litBoost, flashBoost * 0.55
	local dState, dFront, dBack = m.dState, m.dFront, m.dBack
	local dX, dY, dS, dA = m.dX, m.dY, m.dS, m.dA

	for j = 1, TRAIL_DUSTS do
		local e0, e1 = ptEnv[j - 1], ptEnv[j]
		local hideSpeck = (e0 <= 0 or e1 <= 0)
		local tx, ty, tz, tEnv, dx, dy, knownDist

		if not hideSpeck then
			local f = TRAIL_INTERP_T[j]
			tEnv = e0 + (e1 - e0) * f
			if hasSegDeltas then
				dx, dy, knownDist = segDx[j], segDy[j], segDistBuf[j]
			else
				dx, dy, knownDist = ptX[j - 1] - ptX[j], ptY[j - 1] - ptY[j], -1
			end
			tx = ptX[j - 1] - dx * f
			ty = ptY[j - 1] - dy * f
			tz = ptZ[j - 1] + (ptZ[j] - ptZ[j - 1]) * f
			if tz < 0 then
				local ry0 = ty + dustBobY - orbBobY
				if (tx * tx + ry0 * ry0) <= innerSafe2 then hideSpeck = true end
			end
		end

		local px, py, occ, dAlpha, dDepth01
		if not hideSpeck then
			local perpX, perpY = 0, 1
			local dist = knownDist
			if dist < 0 then
				local d2 = dx * dx + dy * dy
				dist = (d2 > 0.0025) and sqrt(d2) or 0
			end
			if dist > 0.05 then perpX, perpY = -dy / dist, dx / dist end

			local sideSign = (j == 2) and -1 or 1
			local driftWave = sin(t * TRAIL_DRIFT_FREQ[j] + shPhase1 + TRAIL_DRIFT_OFF[j])
			local drift = (sideSign * 0.55 + 0.45 * driftWave) * driftBase * TRAIL_DRIFT_MULT[j]
			px, py = tx + perpX * drift, ty + perpY * drift + dustBobY
			if tz >= 0 then
				occ = 1
			else
				local ry = py - orbBobY
				local r2 = px * px + ry * ry
				if r2 <= gi2 then
					hideSpeck = true
				elseif r2 >= go2 then
					occ = 1
				else
					local u = (sqrt(r2) - frame.glassInner) * frame.invGlassBand
					occ = u * u * (3 - 2 * u)
				end
			end
			if not hideSpeck then
				-- Crisp multi-frequency diamond shimmer driven via additive alpha (avoids SetSize churn).
				local sWave = 0.5 + 0.5
					* sin(t * (shRate1 + TRAIL_SHIM_F1[j]) + shPhase1 + TRAIL_SHIM_P1[j])
					* cos(t * (shRate2 + TRAIL_SHIM_F2[j]) + shPhase2 + TRAIL_SHIM_P2[j])
				local sSq = sWave * sWave
				dDepth01 = (tz + 1) * 0.5
				if dDepth01 < 0 then dDepth01 = 0 elseif dDepth01 > 1 then dDepth01 = 1 end
				dAlpha = (litTerm * (0.16 + 0.84 * sSq) * (0.54 + 0.46 * dDepth01) + flashTerm)
					* lifeEnv * tEnv * TRAIL_ALPHA_MULT[j] * occ
				if dAlpha > 1 then dAlpha = 1 end
				if dAlpha < 0.015 then hideSpeck = true end
			end
		end

		if hideSpeck then
			local st = dState[j]
			if st ~= 0 then
				if st == 1 then dFront[j]:Hide() else dBack[j]:Hide() end
				dState[j] = 0
			end
		else
			local dSize = baseSize * TRAIL_SIZE_MULT[j] * (0.68 + 0.50 * dDepth01)
			local want = (tz >= 0) and 1 or -1
			local active = (want == 1) and dFront[j] or dBack[j]
			local st = dState[j]

			if st == want then
				if abs(dSize - dS[j]) > 0.45 then active:SetSize(dSize, dSize); dS[j] = dSize end
				if abs(px - dX[j]) > 0.20 or abs(py - dY[j]) > 0.20 then active:SetPointsOffset(px, py); dX[j], dY[j] = px, py end
				if abs(dAlpha - dA[j]) > 0.035 then active:SetAlpha(dAlpha); dA[j] = dAlpha end
			else
				if st == 1 then dFront[j]:Hide() elseif st == -1 then dBack[j]:Hide() end
				active:SetSize(dSize, dSize)
				active:SetPointsOffset(px, py)
				active:SetAlpha(dAlpha)
				active:Show()
				dState[j] = want
				m.anyVisible = true
				dS[j], dX[j], dY[j], dA[j] = dSize, px, py, dAlpha
			end
		end
	end
end

---------------------------------------------------------------------------
-- Per-frame dust update
---------------------------------------------------------------------------
local function StepMoteState(p, m, elapsed, effSpeed, modeKey, i, count)
	m.age = m.age + elapsed
	m.phase = m.phase + elapsed * m.omega * effSpeed
	if m.liftRate ~= 0 then m.lift = m.lift + elapsed * m.liftRate * effSpeed end

	local needRespawn, wasMoodFade = false, false
	if m.fadeOutRem then
		m.fadeOutRem = m.fadeOutRem - elapsed
		if m.fadeOutRem <= 0 then
			needRespawn, wasMoodFade = true, true
		end
	elseif m.age >= m.lifeMax then
		if m.isChaos or (m.pattern ~= HELIX and m.pattern ~= VORTEX) or m.lift >= 1 then
			needRespawn = true
		end
	elseif (m.pattern == HELIX or m.pattern == VORTEX) and m.lift >= 1 then
		if m.isChaos then needRespawn = true else m.lift = m.lift - 1 end
	end

	if needRespawn then
		RespawnMote(p, m, modeKey, wasMoodFade, i, count)
		if wasMoodFade then m.age = 0 end
	elseif m.isChaos then
		m.tilt = m.tilt + elapsed * m.precessRate
	elseif not m.fadeOutRem and m.pattern == ATOM then
		m.cosI, m.sinI = atomCosI[m.shellIdx], atomSinI[m.shellIdx]
	end
end

local function SyncDustPool(p, count, modeKey, showTails, showTrails)
	if #p.motes < count then EnsurePool(p, count, modeKey) end
	if p.appliedPattern ~= modeKey then ReformSwarm(p, modeKey, count) end
	if p.activeCount ~= count then
		local prevCount = p.activeCount or 0
		if count < prevCount then
			for i = count + 1, #p.motes do HideMote(p.motes[i]) end
		else
			for i = prevCount + 1, count do
				local m = p.motes[i]
				if m and m.moodGen ~= p.moodGen then
					RespawnMote(p, m, modeKey, true, i, count)
				end
			end
		end
		p.activeCount = count
	end
	if p.tailsShown ~= showTails then
		if not showTails then
			for i = 1, #p.motes do HideMoteTails(p.motes[i]) end
		end
		p.tailsShown = showTails
	end
	if p.trailsShown ~= showTrails then
		if not showTrails then
			for i = 1, #p.motes do HideMoteDustTrails(p.motes[i]) end
		end
		p.trailsShown = showTrails
	end
end

local function LayoutDustMotes(orb, elapsed, s, t)
	local p = orb and orb.dust
	if not p then return end
	if p.enabled == nil then
		CacheOrbDustConfig(p, ns:GetOrbDustConfig(orb))
	end
	if not p.enabled then return end

	-- Cap high-FPS (>60 Hz) updates with staggered Health/Power orb cadence while
	-- keeping elapsed == 0 (live slider/setting refreshes) and <=60 FPS immediate.
	if elapsed > 0 then
		p.accum = p.accum + elapsed
		p.stepDt = p.stepDt + elapsed
		if p.accum < DUST_MIN_STEP then return end
		elapsed = p.stepDt
		p.accum, p.stepDt = 0, 0
		if elapsed > 0.1 then elapsed = 0.1 end
	end

	local count, modeKey, showTails, showTrails = p.count, p.modeKey, p.tails, p.trails
	if #p.motes < count or p.appliedPattern ~= modeKey or p.activeCount ~= count
		or p.tailsShown ~= showTails or p.trailsShown ~= showTrails
	then
		SyncDustPool(p, count, modeKey, showTails, showTrails)
	end

	if elapsed > 0 then StepFormationMood(p, elapsed, modeKey, count) end

	local effSpeed = p.speed * (1 + 1.15 * s)
	if elapsed > 0 and modeKey ~= "chaos" then
		p.helixPhase = ((p.helixPhase or 0) + elapsed * (p.moodDir or 1) * 0.28 * effSpeed) % TWO_PI
	end

	local isChaosMode = (modeKey == "chaos")
	local rotRad = p.rotRad
	local spreadFrac = p.spreadFrac
	local tailFrac = p.tailFrac
	local baseCosT, baseSinT = 1, 0
	if not isChaosMode then
		local baseTilt = (p.moodTilt or 0) + rotRad
		baseCosT, baseSinT = cos(baseTilt), sin(baseTilt)
		if p.moodPattern == ATOM then
			local yaw = p.moodYaw
			for sIdx = 0, 2 do
				local inc = 1.12 + 0.10 * sin(yaw + sIdx * 2.0944)
				atomCosI[sIdx] = cos(inc)
				atomSinI[sIdx] = sin(inc)
			end
		end
	end

	local sloshScale = 1 + 0.08 * s
	local flash = orb.accentFlash or 0
	local orbBobY = orb.bobY or 0
	local dustBobY = orbBobY * 0.45
	local useGlare = ns.db.glare
	local lightX = useGlare and (orb.lightX or (-sin(orb.glareAngle or 0))) or 0
	local glareBright = useGlare and (orb.glareBright or 0.45) or 0.45
	local invHalfOrb = p.invHalfOrb
	local glassInner = p.glassInner
	local driftBase = (2.1 + 2.7 * tailFrac) * (0.45 + 1.10 * spreadFrac)
	local maxDrift = driftBase * 1.35
	local innerSafe = max(0, glassInner - maxDrift)
	local innerSafe2 = innerSafe * innerSafe
	local bobDelta = dustBobY - orbBobY
	local gi2, go2 = p.glassInner2, p.glassOuter2

	frame.t = t
	frame.dustBobY = dustBobY
	frame.orbBobY = orbBobY
	frame.glassInner = glassInner
	frame.glassInner2 = gi2
	frame.glassOuter2 = go2
	frame.invGlassBand = p.invGlassBand
	frame.driftBase = driftBase
	frame.innerSafe2 = innerSafe2

	local baseSegLag = (0.075 + 0.165 * tailFrac) * (0.65 + 0.35 * Clamp(effSpeed, 0.2, 3.0))
	local needTrailPts = showTails or showTrails
	local motes = p.motes

	for i = 1, count do
		local m = motes[i]
		if elapsed > 0 then StepMoteState(p, m, elapsed, effSpeed, modeKey, i, count) end
		if m.appliedSpread ~= spreadFrac then ApplyMoteSpread(p, m, spreadFrac) end

		if not m.isChaos then
			if not m.fadeOutRem then
				local cOff, sOff = m.cosOff, m.sinOff
				m.cosT = baseCosT * cOff - baseSinT * sOff
				m.sinT = baseSinT * cOff + baseCosT * sOff
			elseif not m.fadeCosT or m.fadeRot ~= rotRad then
				local tiltVal = (m.frozenTilt or m.tilt) + m.tiltOff + rotRad
				m.fadeCosT, m.fadeSinT, m.fadeRot = cos(tiltVal), sin(tiltVal), rotRad
				m.cosT, m.sinT = m.fadeCosT, m.fadeSinT
			else
				m.cosT, m.sinT = m.fadeCosT, m.fadeSinT
			end
		else
			local tiltVal = m.tilt + rotRad
			m.cosT, m.sinT = cos(tiltVal), sin(tiltVal)
		end

		local lifeEnv = 1
		local age = m.age
		if age < FADE_TIME then
			lifeEnv = SmoothStep01(age / FADE_TIME)
		elseif (not m.fadeOutRem) and (m.isChaos or (m.pattern ~= HELIX and m.pattern ~= VORTEX))
			and age > m.lifeMax - FADE_TIME
		then
			lifeEnv = SmoothStep01((m.lifeMax - age) / FADE_TIME)
		end
		if m.fadeOutRem and m.fadeOutDur and m.fadeOutDur > 0 then
			lifeEnv = lifeEnv * SmoothStep01(m.fadeOutRem / m.fadeOutDur)
		end

		if lifeEnv <= 0.001 then
			HideMote(m)
		else
			local nPts, phaseStep, liftStep = 0, 0, 0
			if needTrailPts then
				local angRate = m.angRate
				local segDt = (baseSegLag * angRate > 0.34 and angRate > 1e-4) and (0.34 / angRate) or baseSegLag
				nPts, phaseStep, liftStep = TAIL_SEGS, segDt * m.omega, segDt * m.liftRate
			elseif m.kind == 2 then
				nPts, phaseStep, liftStep = 1, 0.04 * m.omega, 0.04 * m.liftRate
			end
			SampleCurveUniform(m, nPts, phaseStep, liftStep, sloshScale)

			local x0, y0, z0, env0 = ptX[0], ptY[0], ptZ[0], ptEnv[0]
			local py0 = y0 + dustBobY
			local r0_2
			local occ0
			if env0 <= 0 then
				occ0 = 0
			elseif z0 >= 0 then
				occ0 = 1
			else
				local ry0 = y0 + bobDelta
				r0_2 = x0 * x0 + ry0 * ry0
				if r0_2 <= gi2 then
					occ0 = 0
				elseif r0_2 >= go2 then
					occ0 = 1
				else
					occ0 = SphereOcclusionRear(x0, ry0)
				end
			end

			-- Disk convexity fast skip: when all 4 rear samples sit deep inside innerSafe2,
			-- head, comet tails, and drifted dust specks are guaranteed 100% behind the glass.
			local allEclipsed = false
			if occ0 <= 0 and z0 < 0 then
				if not needTrailPts then
					allEclipsed = true
				elseif ptZ[3] < 0 and ptZ[1] < 0 and ptZ[2] < 0 then
					local ry0 = y0 + bobDelta
					if (r0_2 or (x0 * x0 + ry0 * ry0)) <= innerSafe2 then
						local x3, ry3 = ptX[3], ptY[3] + bobDelta
						if (x3 * x3 + ry3 * ry3) <= innerSafe2 then
							local x1, ry1 = ptX[1], ptY[1] + bobDelta
							local x2, ry2 = ptX[2], ptY[2] + bobDelta
							if (x1 * x1 + ry1 * ry1) <= innerSafe2 and (x2 * x2 + ry2 * ry2) <= innerSafe2 then
								allEclipsed = true
							end
						end
					end
				end
			end

			if allEclipsed then
				HideMote(m)
			else
				local litBoost = (useGlare and (x0 * lightX) > 0)
					and (1 + 0.45 * glareBright * min(1, abs(x0) * invHalfOrb)) or 1
				local flashBoost = (m.kind == 3) and (0.35 * flash) or (0.12 * flash)

				local headAngle
				if showTails then
					headAngle = LayoutMoteTails(m, lifeEnv, litBoost, flashBoost)
				end
				if showTrails then
					LayoutMoteDustTrails(m, lifeEnv, litBoost, flashBoost, showTails)
				end

				local hideHead = (occ0 <= 0)
				local alpha, depth01
				if not hideHead then
					local twinkle = 0.64 + 0.36 * sin(t * m.twinkleRate + m.twinklePhase)
					depth01 = (z0 + 1) * 0.5
					if depth01 < 0 then depth01 = 0 elseif depth01 > 1 then depth01 = 1 end
					alpha = (m.baseAlpha * twinkle * (0.54 + 0.46 * depth01) * litBoost + flashBoost)
						* lifeEnv * env0 * occ0
					if alpha > 1 then alpha = 1 end
					if alpha < 0.01 then hideHead = true end
				end

				if hideHead then
					local st = m.hState
					if st ~= 0 then
						if st == 1 then m.front:Hide() else m.back:Hide() end
						m.hState = 0
					end
				else
					local scale = 0.68 + 0.50 * depth01
					local hw, hh = m.baseW * scale, m.baseH * scale
					local want = (z0 >= 0) and 1 or -1
					local active = (want == 1) and m.front or m.back
					local st = m.hState

					if m.kind == 2 and not headAngle then
						local dx, dy = x0 - ptX[1], y0 - ptY[1]
						if (dx * dx + dy * dy) > 1e-4 then headAngle = atan2(dy, dx) end
					end

					if st == want then
						if abs(hw - m.hW) > 0.35 or abs(hh - m.hH) > 0.35 then active:SetSize(hw, hh); m.hW, m.hH = hw, hh end
						if abs(x0 - m.hX) > 0.15 or abs(py0 - m.hY) > 0.15 then active:SetPointsOffset(x0, py0); m.hX, m.hY = x0, py0 end
						if abs(alpha - m.hA) > 0.022 then active:SetAlpha(alpha); m.hA = alpha end
						if m.kind == 2 and headAngle and abs(headAngle - m.hR) > 0.035 then active:SetRotation(headAngle); m.hR = headAngle end
					else
						if st == 1 then m.front:Hide() elseif st == -1 then m.back:Hide() end
						active:SetSize(hw, hh)
						active:SetPointsOffset(x0, py0)
						active:SetAlpha(alpha)
						if m.kind == 2 then
							local rot = headAngle or ((m.hR ~= 999) and m.hR or 0)
							active:SetRotation(rot)
							m.hR = rot
						end
						active:Show()
						m.hState = want
						m.anyVisible = true
						m.hW, m.hH, m.hX, m.hY, m.hA = hw, hh, x0, py0, alpha
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Public addon contract
---------------------------------------------------------------------------
function ns:AttachOrbDust(orb, visual, holderFront, orbSize)
	local glassR = orbSize * GLASS_RADIUS
	local glassInner = glassR * 0.88
	local glassOuter = glassR * 1.02
	local p = {
		orbSize = orbSize, visual = visual, holderFront = holderFront,
		invHalfOrb = 2 / orbSize,
		glassInner = glassInner,
		glassInner2 = glassInner * glassInner,
		glassOuter2 = glassOuter * glassOuter,
		invGlassBand = 1 / (glassR * 0.14),
		accum = (orb.key == "power") and (DUST_MIN_STEP * 0.5) or 0,
		stepDt = 0,
		motes = {}, activeCount = 0, tailsShown = false, trailsShown = false,
		appliedPattern = nil, moodGen = 0,
		lr = 1, lg = 0.85, lb = 0.85, ar = 1, ag = 0.72, ab = 0.30,
	}
	PickNextAutoMood(p)
	orb.dust = p
end

function ns:RefreshOrbDustColors(orb)
	local p = orb and orb.dust
	if not p then return end
	local c, a = ns:GetOrbColors(orb)
	p.lr, p.lg, p.lb = c[1] + (1 - c[1]) * 0.42, c[2] + (1 - c[2]) * 0.42, c[3] + (1 - c[3]) * 0.42
	p.ar, p.ag, p.ab = a[1], a[2], a[3]
	for i = 1, #p.motes do ApplyMoteColor(p, p.motes[i]) end
end

function ns:ApplyOrbDust(orb)
	local p = orb and orb.dust
	if not p then return end
	local cfg = ns:GetOrbDustConfig(orb)
	CacheOrbDustConfig(p, cfg)
	if not cfg.enabled then
		for i = 1, #p.motes do HideMote(p.motes[i]) end
		p.activeCount, p.tailsShown, p.trailsShown = 0, false, false
		p.accum = (orb.key == "power") and (DUST_MIN_STEP * 0.5) or 0
		p.stepDt = 0
		return
	end

	SyncDustPool(p, cfg.count, cfg.pattern, cfg.tails, cfg.trails)
	ns:RefreshOrbDustColors(orb)
	LayoutDustMotes(orb, 0, orb.slosh or 0, orb.time or 0)
end

function ns:AnimateOrbDust(orb, elapsed, s, t)
	LayoutDustMotes(orb, elapsed, s, t)
end

function ns:AnyOrbDustEnabled()
	if not ns.orbs then return false end
	for _, orb in pairs(ns.orbs) do
		if orb.dust and orb.dust.enabled ~= nil then
			if orb.dust.enabled then return true end
		elseif ns:GetOrbDustConfig(orb).enabled then
			return true
		end
	end
	return false
end

function ns:SetOrbDust(orb, field, value)
	if not (ns.db and orb) then return end
	local cfg = ns:GetOrbDustConfig(orb)
	if field == "enabled" or field == "tails" or field == "trails" then cfg[field] = value and true or false
	elseif field == "pattern" then cfg.pattern = ns.NormalizeDustPattern(value)
	elseif field == "count" then cfg.count = ns.NormalizeDustCount(value)
	elseif field == "speed" then cfg.speed = ns.NormalizeDustSpeed(value)
	elseif field == "tailLength" then cfg.tailLength = ns.NormalizeDustTailLength(value)
	elseif field == "rotation" then cfg.rotation = ns.NormalizeDustRotation(value)
	elseif field == "spread" then cfg.spread = ns.NormalizeDustSpread(value)
	end
	ns:ApplyOrbDust(orb)
	if ns.UpdateDriverState then ns:UpdateDriverState() end

	local dbKey = SYNC_DB_KEYS[field]
	if dbKey then
		local allSame = true
		for orbKey in pairs(ns.ORB_DEFAULTS) do
			local other = ns.orbs and ns.orbs[orbKey]
			if other and ns:GetOrbDustConfig(other)[field] ~= cfg[field] then
				allSame = false
				break
			end
		end
		if allSame then
			ns.db[dbKey] = cfg[field]
			if ns.NotifyOptionSetting then ns:NotifyOptionSetting(dbKey) end
		end
	end
end

local function SetAllOrbDustField(field, dbKey, value, fromSettings, updateDriver)
	if not ns.db then return end
	ns.db[dbKey] = value
	if ns.orbs then
		for _, orb in pairs(ns.orbs) do
			local cfg = ns:GetOrbDustConfig(orb)
			cfg[field] = value
			ns:ApplyOrbDust(orb)
		end
	end
	if updateDriver and ns.UpdateDriverState then ns:UpdateDriverState() end
	if not fromSettings and ns.NotifyOptionSetting then ns:NotifyOptionSetting(dbKey) end
	local dlg = ns.orbSettingsDialog and ns.orbSettingsDialog()
	if dlg and dlg:IsShown() then dlg:Refresh() end
end

function ns:SetAllOrbDustEnabled(enabled, fromSettings) SetAllOrbDustField("enabled", "dustEnabled", enabled and true or false, fromSettings, true) end
function ns:SetAllOrbDustPattern(pattern, fromSettings) SetAllOrbDustField("pattern", "dustPattern", ns.NormalizeDustPattern(pattern), fromSettings, false) end
function ns:SetAllOrbDustTails(enabled, fromSettings) SetAllOrbDustField("tails", "dustTails", enabled and true or false, fromSettings, false) end
function ns:SetAllOrbDustTrails(enabled, fromSettings) SetAllOrbDustField("trails", "dustTrails", enabled and true or false, fromSettings, false) end
