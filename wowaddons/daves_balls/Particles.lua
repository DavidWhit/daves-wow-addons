-- daves_balls / Particles.lua
-- Selectable 3D orbital dust patterns (Auto, Halo Ring, Twin Helix, Figure-8,
-- Vortex, Atom Shells, Chaos) with true sphere-rim occlusion, curved 3D comet
-- tails, and independent shimmering stardust trails. Each head, tail segment,
-- and dust-trail speck pairs a rear texture (behind the orb glass) with a front
-- texture (in front of the glass and holder, below the numbers), switching at
-- z = 0 and cleanly eclipsing behind the glass silhouette when z < 0.

local ADDON, ns = ...

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local TWO_PI = 2 * math.pi
local THIRD_PI = math.pi / 3
local HELIX_TWISTS = TWO_PI * 1.60

local CONST = {
	GLASS_RADIUS = 0.40,   -- matches GLASS_RADIUS in Orbs.lua (60px at 150px orb)
	MIN_COUNT = 2, MAX_MOTES = 40, DEFAULT_COUNT = 20,
	MIN_SPEED = 0.2, MAX_SPEED = 2.5, DEFAULT_SPEED = 1.0,
	MIN_TAIL_LEN = 20, MAX_TAIL_LEN = 100, DEFAULT_TAIL_LEN = 60,
	MIN_ROTATION = -180, MAX_ROTATION = 180, DEFAULT_ROTATION = 0,
	MIN_SPREAD = 0, MAX_SPREAD = 100, DEFAULT_SPREAD = 25,
	TAIL_SEGS = 3, TRAIL_DUSTS = 3, FADE_TIME = 1.0,
	STRUCTURED_COUNT = 5, PATTERN_COUNT = 6,
	RING = 1, HELIX = 2, FIG8 = 3, VORTEX = 4, ATOM = 5, EDDY = 6,
}

local TAIL_ALPHA_MULT = { 0.72, 0.46, 0.24 }
local TAIL_THICK_MULT = { 0.92, 0.68, 0.44 }
local TRAIL_LAG_MULT = { 0.55, 1.25, 2.05 }
local TRAIL_ALPHA_MULT = { 0.84, 0.60, 0.38 }
local TRAIL_SIZE_MULT = { 0.58, 0.46, 0.35 }
local TRAIL_DRIFT_MULT = { 0.45, 0.85, 1.35 }
local TRAIL_COLOR_MIX = { 0.55, 0.82, 0.28 }
local TRAIL_WHITE_BOOST = { 0.62, 0.48, 0.55 }

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
	ring = CONST.RING, helix = CONST.HELIX, figure8 = CONST.FIG8,
	vortex = CONST.VORTEX, atom = CONST.ATOM,
}

local SYNC_DB_KEYS = {
	enabled = "dustEnabled", pattern = "dustPattern",
	tails = "dustTails", trails = "dustTrails",
}

local function Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function SmoothStep01(u)
	if u <= 0 then return 0 end
	if u >= 1 then return 1 end
	return u * u * (3 - 2 * u)
end

-- Clean 3D sphere-rim occlusion: foreground (z >= 0) stays 100% crisp; rear
-- particles (z < 0) smoothly eclipse to 0 inside the glass sphere silhouette
-- so additive glow never bleeds through the translucent upper glass.
local function SphereOcclusion(px, pyRelOrb, z, glassR)
	if z >= 0 then return 1 end
	local r = math.sqrt(px * px + pyRelOrb * pyRelOrb)
	return SmoothStep01((r - glassR * 0.88) / (glassR * 0.14))
end

local function ResolveBool(val, dbKey, fallback)
	if val ~= nil then return val == true end
	if ns.db and ns.db[dbKey] ~= nil then return ns.db[dbKey] == true end
	return fallback
end

function ns.NormalizeDustPattern(pattern)
	if type(pattern) == "string" then
		local key = pattern:lower()
		if ns.DUST_PATTERNS[key] then return key end
	end
	return "auto"
end

function ns.NormalizeDustCount(count)
	local n = tonumber(count)
	if not n then return CONST.DEFAULT_COUNT end
	return math.floor(Clamp(math.floor(n + 0.5), CONST.MIN_COUNT, CONST.MAX_MOTES))
end

function ns.NormalizeDustSpeed(speed)
	local n = tonumber(speed)
	if not n then return CONST.DEFAULT_SPEED end
	return Clamp(n, CONST.MIN_SPEED, CONST.MAX_SPEED)
end

function ns.NormalizeDustTailLength(len)
	local n = tonumber(len)
	if not n then return CONST.DEFAULT_TAIL_LEN end
	return math.floor(Clamp(math.floor(n + 0.5), CONST.MIN_TAIL_LEN, CONST.MAX_TAIL_LEN))
end

function ns.NormalizeDustRotation(deg)
	local n = tonumber(deg)
	if not n then return CONST.DEFAULT_ROTATION end
	return math.floor(Clamp(math.floor(n + 0.5), CONST.MIN_ROTATION, CONST.MAX_ROTATION))
end

function ns.NormalizeDustSpread(spread)
	local n = tonumber(spread)
	if not n then return CONST.DEFAULT_SPREAD end
	return math.floor(Clamp(math.floor(n + 0.5), CONST.MIN_SPREAD, CONST.MAX_SPREAD))
end

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

---------------------------------------------------------------------------
-- Pool visibility & coloring helpers
---------------------------------------------------------------------------
local function HideMoteTails(m)
	for k = 1, CONST.TAIL_SEGS do
		m.tBack[k]:Hide()
		m.tFront[k]:Hide()
	end
end

local function HideMoteDustTrails(m)
	for j = 1, CONST.TRAIL_DUSTS do
		m.dBack[j]:Hide()
		m.dFront[j]:Hide()
	end
end

local function HideMote(m)
	m.back:Hide()
	m.front:Hide()
	HideMoteTails(m)
	HideMoteDustTrails(m)
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
	for k = 1, CONST.TAIL_SEGS do
		m.tBack[k]:SetVertexColor(tr, tg, tb)
		m.tFront[k]:SetVertexColor(tr, tg, tb)
	end

	-- Shimmering dust-trail specks glint between starlight-white, warm accent
	-- gold, and orb liquid glow for a crystalline stardust wake.
	for j = 1, CONST.TRAIL_DUSTS do
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
	p.moodDir = (math.random() < 0.5) and 1 or -1
	-- Anchor each pattern around a predictable home orientation so the user's
	-- Pattern rotation slider points the formation cleanly where they aim it.
	if pat == CONST.RING then
		p.moodHomeTilt = 0.24
	else
		p.moodHomeTilt = 0
	end
	p.moodTilt = p.moodHomeTilt
	p.moodYaw = math.random() * TWO_PI
	p.moodYawRate = ((math.random() < 0.5) and 1 or -1) * (0.18 + math.random() * 0.12)
	p.helixPhase = p.moodYaw
	p.moodTimer = 16 + math.random() * 6
end

local function PickNextAutoMood(p)
	local pat = math.random(1, CONST.STRUCTURED_COUNT)
	if pat == (p.moodPattern or 0) then
		pat = (pat % CONST.STRUCTURED_COUNT) + 1
	end
	InitMoodForPattern(p, pat)
end

local function StepFormationMood(p, elapsed, modeKey, count)
	if modeKey == "chaos" then return end
	p.moodYaw = (p.moodYaw + elapsed * p.moodYawRate) % TWO_PI
	local home = p.moodHomeTilt or 0
	if p.moodPattern == CONST.HELIX then
		p.moodTilt = home + math.sin(p.moodYaw * 0.45) * 0.08
	elseif p.moodPattern == CONST.VORTEX then
		p.moodTilt = home + math.sin(p.moodYaw * 0.35) * 0.05
	elseif p.moodPattern == CONST.ATOM then
		p.moodTilt = home + math.sin(p.moodYaw * 0.40) * 0.12
	else
		p.moodTilt = home + math.sin(p.moodYaw * 0.40) * 0.06
	end

	if modeKey == "auto" then
		p.moodTimer = p.moodTimer - elapsed
		if p.moodTimer <= 0 then
			PickNextAutoMood(p)
			local denom = (count > 1) and (count - 1) or 1
			for i = 1, count do
				local m = p.motes[i]
				if m then
					local dur = 0.75 + ((i - 1) / denom) * 0.55
					m.fadeOutDur, m.fadeOutRem = dur, dur
				end
			end
		end
	end
end

local function ConfigureStructuredMote(p, m, pat, size, dir, idx, nSlots, initial)
	-- Store crisp nominal base geometry + normalized [-1, +1] spread factors so
	-- Particle spread (0%-100%) and Pattern rotation (-180..+180 deg) react live.
	local speedBand = 0.94 + math.random() * 0.12
	local slotFrac = (idx - 1) / nSlots
	m.lifeMax = 20 + math.random() * 10
	m.age = initial and (CONST.FADE_TIME + math.random() * (m.lifeMax - CONST.FADE_TIME * 2.5)) or 0
	m.rRand = (math.random() - 0.5) * 2
	m.ryRand = (math.random() - 0.5) * 2
	m.yRand = (math.random() - 0.5) * 2
	m.tRand = (math.random() - 0.5) * 2

	if pat == CONST.RING then
		m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = size * 0.58, size * 0.20, 0, size * 0.015
		m.harmPhase = (math.random() - 0.5) * 0.25
		m.phase = (slotFrac * TWO_PI + (math.random() - 0.5) * 0.10) % TWO_PI
		m.tilt = p.moodTilt
		m.omega = dir * 0.88 * speedBand
	elseif pat == CONST.HELIX then
		local halfCount = math.max(1, math.ceil(nSlots / 2))
		local strandSlot = math.floor((idx - 1) / 2)
		m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = size * 0.58, size * 0.17, 0, size * 0.016
		m.riseSpan = size * 0.48
		m.tilt = p.moodTilt
		m.phase = ((p.helixPhase or p.moodYaw or 0) + (math.random() - 0.5) * 0.06) % TWO_PI
		m.omega = dir * 0.28
		m.liftRate = 0.20 * speedBand
		m.lift = initial and Clamp((strandSlot + 0.5) / halfCount + (math.random() - 0.5) * 0.03, 0.02, 0.98)
			or (0.001 + (strandSlot / halfCount) * 0.06)
	elseif pat == CONST.FIG8 then
		m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = size * 0.61, size * 0.24, 0, 0
		m.phase = (slotFrac * TWO_PI + (math.random() - 0.5) * 0.10) % TWO_PI
		m.tilt = p.moodTilt
		m.omega = dir * 0.80 * speedBand
	elseif pat == CONST.VORTEX then
		m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = size * 0.60, size * 0.17, 0, 0
		m.yBase, m.riseSpan = -size * 0.48, size * 1.06
		m.tilt = p.moodTilt
		m.omega = dir * 1.55 * speedBand
		m.liftRate = 0.17 * speedBand
		if initial then
			m.lift = Clamp((idx - 0.5) / nSlots + (math.random() - 0.5) * 0.03, 0.02, 0.98)
			m.phase = (m.lift * TWO_PI * 2.2 + (idx % 3) * (TWO_PI / 3)) % TWO_PI
		else
			m.lift = 0.001
			m.phase = ((idx % 3) * (TWO_PI / 3) + math.random() * 0.45) % TWO_PI
		end
	else
		-- CONST.ATOM: 3 crisp intersecting shells spaced by 60 degrees.
		local perShell = math.max(1, math.ceil(nSlots / 3))
		local inShell = math.floor((idx - 1) / 3)
		local inc = 1.12 + 0.10 * math.sin(p.moodYaw + m.shellIdx * 2.0944)
		m.cosI, m.sinI = math.cos(inc), math.sin(inc)
		m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = size * 0.60, size * 0.18, 0, 0
		m.tilt = p.moodTilt + m.shellIdx * THIRD_PI
		m.phase = ((inShell / perShell) * TWO_PI + m.shellIdx * 0.65 + (math.random() - 0.5) * 0.10) % TWO_PI
		m.omega = dir * 1.05 * speedBand
	end
	m.rx, m.ry, m.yOff, m.waveAmp = m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp
end

local function ConfigureChaosMote(m, pat, size, dir, initial)
	m.lifeMax = 7 + math.random() * 8
	m.age = initial and (m.lifeMax * (0.14 + math.random() * 0.72)) or 0
	m.phase = math.random() * TWO_PI
	m.harmPhase = math.random() * TWO_PI
	m.precessRate = ((math.random() < 0.5) and 1 or -1) * (0.05 + math.random() * 0.12)
	m.rRand = (math.random() - 0.5) * 2
	m.ryRand = (math.random() - 0.5) * 2
	m.yRand = (math.random() - 0.5) * 2
	m.tRand = (math.random() - 0.5) * 2

	if pat == CONST.RING then
		m.rx, m.ry = size * (0.54 + math.random() * 0.14), size * (0.15 + math.random() * 0.11)
		m.yOff = size * (-0.08 + math.random() * 0.16)
		m.waveAmp = size * (0.025 + math.random() * 0.035)
		m.tilt, m.omega = (math.random() - 0.5) * 1.05, dir * (0.55 + math.random() * 0.55)
	elseif pat == CONST.HELIX then
		m.strand = (math.random() < 0.5) and 1 or -1
		m.strandOffset = (m.strand > 0) and 0 or math.pi
		m.rx, m.ry = size * (0.54 + math.random() * 0.11), size * (0.13 + math.random() * 0.08)
		m.riseSpan = size * (0.42 + math.random() * 0.10)
		m.waveAmp = size * (0.02 + math.random() * 0.025)
		m.tilt, m.omega = (math.random() - 0.5) * 0.64, dir * (0.25 + math.random() * 0.35)
		m.liftRate = 0.15 + math.random() * 0.12
		m.lift = initial and (0.08 + math.random() * 0.80) or 0.001
	elseif pat == CONST.FIG8 then
		m.rx, m.ry = size * (0.56 + math.random() * 0.12), size * (0.22 + math.random() * 0.10)
		m.yOff = size * (-0.06 + math.random() * 0.12)
		m.tilt, m.omega = (math.random() - 0.5) * 0.90, dir * (0.55 + math.random() * 0.45)
	elseif pat == CONST.VORTEX then
		m.rx, m.ry = size * (0.54 + math.random() * 0.11), size * (0.13 + math.random() * 0.07)
		m.yBase, m.riseSpan = size * (-0.50 + math.random() * 0.06), size * (1.00 + math.random() * 0.16)
		m.tilt, m.omega = (math.random() - 0.5) * 0.28, dir * (0.95 + math.random() * 0.65)
		m.liftRate = 0.12 + math.random() * 0.09
		m.lift = initial and (0.08 + math.random() * 0.78) or 0.001
	elseif pat == CONST.ATOM then
		local inc = 1.00 + math.random() * 0.26
		m.cosI, m.sinI = math.cos(inc), math.sin(inc)
		m.rx, m.ry = size * (0.55 + math.random() * 0.12), size * 0.18
		m.tilt, m.omega = math.random() * TWO_PI, dir * (0.72 + math.random() * 0.52)
	else
		m.rx, m.ry = size * (0.54 + math.random() * 0.13), size * (0.14 + math.random() * 0.10)
		m.yOff = size * (-0.10 + math.random() * 0.20)
		m.waveAmp = size * (0.13 + math.random() * 0.13)
		m.tilt, m.omega = (math.random() - 0.5) * 0.80, dir * (0.45 + math.random() * 0.48)
	end
	m.baseRx, m.baseRy, m.baseYOff, m.baseWaveAmp = m.rx, m.ry, m.yOff, m.waveAmp
end

local function RespawnMote(p, m, modeKey, initial, slot, slotCount)
	local size = p.orbSize
	local isChaos = (modeKey == "chaos")
	local pat = isChaos and math.random(1, CONST.PATTERN_COUNT)
		or (PATTERN_KEY_TO_ID[modeKey] or p.moodPattern or CONST.RING)
	local nSlots = (slotCount and slotCount > 0) and slotCount or 1
	local idx = slot or m.index or 1

	m.pattern, m.isChaos, m.moodGen = pat, isChaos, p.moodGen or 0
	m.fadeOutRem, m.fadeOutDur = nil, nil

	local r = math.random()
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

	local dir = isChaos and ((math.random() < 0.5) and 1 or -1) or (p.moodDir or 1)
	m.dir = dir
	m.lift, m.liftRate = 0, 0
	m.shellIdx = (idx - 1) % 3
	m.strand = ((idx % 2) == 0) and 1 or -1
	m.strandOffset = (m.strand > 0) and 0 or math.pi
	m.harmPhase, m.harmPhase2 = 0, math.random() * TWO_PI
	m.freq2, m.freq3 = 0.65 + math.random() * 0.55, 1.15 + math.random() * 0.75
	m.yOff, m.yBase, m.riseSpan, m.waveAmp = 0, 0, 0, 0
	m.cosI, m.sinI, m.tiltOffset, m.precessRate = 0.435, 0.900, 0, 0

	if not isChaos then
		ConfigureStructuredMote(p, m, pat, size, dir, idx, nSlots, initial)
	else
		ConfigureChaosMote(m, pat, size, dir, initial)
	end

	m.cosT, m.sinT, m.sloshScale = math.cos(m.tilt), math.sin(m.tilt), 1
	m.baseW = isWisp and (6.2 + math.random() * 4.4)
		or (isSpark and (3.8 + math.random() * 3.6) or (4.6 + math.random() * 4.2))
	m.baseH = isWisp and (m.baseW * 0.46) or m.baseW
	m.twinkleRate, m.twinklePhase = 1.8 + math.random() * 3.4, math.random() * TWO_PI
	m.shimmerRate, m.shimmerRate2 = 6.5 + math.random() * 4.5, 9.5 + math.random() * 5.5
	m.shimmerPhase, m.shimmerPhase2 = math.random() * TWO_PI, math.random() * TWO_PI
	m.baseAlpha = isSpark and (0.64 + math.random() * 0.32) or (0.48 + math.random() * 0.34)
	m.colorMix = math.random()
	m.whiteBoost = isSpark and 0.44 or (isWisp and 0.26 or 0.20)
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

local function MakePairedTextures(vis, frontFrame, count, texPath)
	local backList, frontList = {}, {}
	for k = 1, count do
		local tb = vis:CreateTexture(nil, "ARTWORK", nil, -2)
		tb:SetTexture(texPath)
		tb:SetBlendMode("ADD")
		tb:Hide()
		backList[k] = tb

		local tf = frontFrame:CreateTexture(nil, "ARTWORK", nil, 5)
		tf:SetTexture(texPath)
		tf:SetBlendMode("ADD")
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
		local tBack, tFront = MakePairedTextures(vis, frontFrame, CONST.TAIL_SEGS, tailTex)
		local dBack, dFront = MakePairedTextures(vis, frontFrame, CONST.TRAIL_DUSTS, moteTex)
		local back = vis:CreateTexture(nil, "ARTWORK", nil, -2)
		back:SetBlendMode("ADD")
		back:Hide()
		local front = frontFrame:CreateTexture(nil, "ARTWORK", nil, 5)
		front:SetBlendMode("ADD")
		front:Hide()

		local m = {
			index = i, back = back, front = front,
			tBack = tBack, tFront = tFront, dBack = dBack, dFront = dFront,
		}
		motes[i] = m
		RespawnMote(p, m, modeKey or p.appliedPattern or "auto", true, i, targetCount)
	end
end

---------------------------------------------------------------------------
-- Analytic 3D orbital pattern evaluator (zero allocations)
---------------------------------------------------------------------------
local function EvalPattern(patternId, phase, lift, m)
	local sloshScale = m.sloshScale or 1

	if patternId == CONST.RING then
		local ox = math.cos(phase) * m.rx * sloshScale
		local oz = math.sin(phase)
		local oy = m.yOff + oz * m.ry + math.sin(phase * 2 + m.harmPhase) * m.waveAmp
		return ox * m.cosT - oy * m.sinT, ox * m.sinT + oy * m.cosT, oz, 1
	elseif patternId == CONST.HELIX then
		local env = (lift <= 0 or lift >= 1) and 0
			or (SmoothStep01(lift / 0.16) * SmoothStep01((1 - lift) / 0.18))
		local uNorm = Clamp(lift, 0, 1)
		local u = (uNorm - 0.5) * 2
		local rx = m.rx * (0.88 + 0.14 * (1 - u * u)) * sloshScale
		local ang = m.dir * (uNorm * HELIX_TWISTS) + phase + m.strandOffset
		local ox, oz = math.cos(ang) * rx, math.sin(ang)
		local oy = u * m.riseSpan + oz * m.ry + m.strand * math.cos(ang) * m.waveAmp
		return ox * m.cosT - oy * m.sinT, ox * m.sinT + oy * m.cosT, oz, env
	elseif patternId == CONST.FIG8 then
		local ox = math.sin(phase) * m.rx * sloshScale
		local oy = math.sin(phase * 2) * m.ry + m.yOff
		local oz = math.cos(phase)
		return ox * m.cosT - oy * m.sinT, ox * m.sinT + oy * m.cosT, oz, 1
	elseif patternId == CONST.VORTEX then
		local env = (lift <= 0 or lift >= 1) and 0
			or (SmoothStep01(lift / 0.15) * SmoothStep01((1 - lift) / 0.25))
		local u = Clamp(lift, 0, 1)
		local cone = 0.56 + 0.58 * (0.35 * u + 0.65 * math.sqrt(u))
		local ox = math.cos(phase) * m.rx * cone * sloshScale
		local oz = math.sin(phase)
		local oy = m.yBase + u * m.riseSpan + oz * m.ry * (0.50 + 0.50 * u)
		return ox * m.cosT - oy * m.sinT, ox * m.sinT + oy * m.cosT, oz, env
	elseif patternId == CONST.ATOM then
		local rx = m.rx * sloshScale
		local ox = math.cos(phase) * rx
		local sa = math.sin(phase)
		local oy = sa * m.cosI * rx
		local oz = sa * m.sinI
		return ox * m.cosT - oy * m.sinT, ox * m.sinT + oy * m.cosT, oz, 1
	else
		local rx = m.rx * (1 + 0.14 * math.sin(phase * m.freq2 + m.harmPhase)) * sloshScale
		local ang = phase + 0.48 * math.sin(phase * m.freq2 + m.harmPhase2)
		local ox, oz = math.cos(ang) * rx, math.sin(ang)
		local oy = m.yOff + oz * m.ry * 0.55
			+ math.sin(phase * m.freq3 + m.harmPhase) * m.waveAmp
			+ math.cos(phase * m.freq2 * 0.7 + m.harmPhase2) * m.waveAmp * 0.42
		return ox * m.cosT - oy * m.sinT, ox * m.sinT + oy * m.cosT, oz, 1
	end
end

---------------------------------------------------------------------------
-- Curved 3D comet tail & shimmering dust trail renderers (zero allocations)
---------------------------------------------------------------------------
local function LayoutMoteTails(
	m, vis, x0, y0, z0, env0, lifeEnv, twinkle, litBoost, flashBoost,
	phaseStep, liftStep, dustBobY, orbBobY, glassR
)
	local baseThick = (m.kind == 2) and (m.baseW * 0.62) or (m.baseW * 0.90)
	local prevX, prevY, prevZ, prevEnv = x0, y0, z0, env0
	local headAngle

	for k = 1, CONST.TAIL_SEGS do
		local curX, curY, curZ, curEnv = EvalPattern(m.pattern, m.phase - k * phaseStep, m.lift - k * liftStep, m)
		local dx, dy = prevX - curX, prevY - curY
		local segDist = math.sqrt(dx * dx + dy * dy)
		if k == 1 and segDist > 0.05 then headAngle = math.atan2(dy, dx) end

		local segEnv = (prevEnv <= 0 or curEnv <= 0) and 0 or ((prevEnv + curEnv) * 0.5)
		local segZ = (prevZ + curZ) * 0.5
		local mx, my = (prevX + curX) * 0.5, (prevY + curY) * 0.5 + dustBobY
		local occ = SphereOcclusion(mx, my - orbBobY, segZ, glassR)

		local segDepth01 = Clamp((segZ + 1) * 0.5, 0, 1)
		local segAlpha = Clamp(
			(m.baseAlpha * twinkle * (0.54 + 0.46 * segDepth01) * litBoost + flashBoost * 0.45)
				* lifeEnv * segEnv * TAIL_ALPHA_MULT[k] * occ,
			0, 1
		)
		if segDist < 0.45 then segAlpha = segAlpha * (segDist / 0.45) end

		local active, hidden
		if segZ >= 0 then active, hidden = m.tFront[k], m.tBack[k] else active, hidden = m.tBack[k], m.tFront[k] end
		hidden:Hide()

		if segAlpha < 0.015 or segDist < 0.15 then
			active:Hide()
		else
			local segH = baseThick * (0.68 + 0.50 * segDepth01) * TAIL_THICK_MULT[k]
			local segW = math.max(segH * 1.15, segDist * 1.48)
			active:SetSize(segW, segH)
			active:ClearAllPoints()
			active:SetPoint("CENTER", vis, "CENTER", mx, my)
			active:SetRotation(math.atan2(dy, dx))
			active:SetAlpha(segAlpha)
			active:Show()
		end
		prevX, prevY, prevZ, prevEnv = curX, curY, curZ, curEnv
	end

	return headAngle
end

local function LayoutMoteDustTrails(
	m, vis, t, x0, y0, lifeEnv, litBoost, flashBoost,
	trailPhaseSpan, trailLiftSpan, tailFrac, spreadFrac, dustBobY, orbBobY, glassR
)
	local prevX, prevY = x0, y0
	local driftBase = (2.1 + 2.7 * tailFrac) * (0.45 + 1.10 * spreadFrac)
	local baseSize = math.max(4.4, m.baseW)

	for j = 1, CONST.TRAIL_DUSTS do
		local lag = TRAIL_LAG_MULT[j]
		local tx, ty, tz, tEnv = EvalPattern(m.pattern, m.phase - lag * trailPhaseSpan, m.lift - lag * trailLiftSpan, m)
		local dx, dy = prevX - tx, prevY - ty
		local dist = math.sqrt(dx * dx + dy * dy)
		local perpX, perpY = 0, 1
		if dist > 0.05 then perpX, perpY = -dy / dist, dx / dist end

		local sideSign = (j == 2) and -1 or 1
		local driftWave = math.sin(t * (1.8 + j * 0.55) + m.shimmerPhase + j * 2.31)
		local drift = (sideSign * 0.55 + 0.45 * driftWave) * driftBase * TRAIL_DRIFT_MULT[j]
		local px, py = tx + perpX * drift, ty + perpY * drift + dustBobY
		local occ = SphereOcclusion(px, py - orbBobY, tz, glassR)

		-- Crisp multi-frequency diamond shimmer curve.
		local sWave = 0.5 + 0.5
			* math.sin(t * (m.shimmerRate + j * 1.7) + m.shimmerPhase + j * 2.13)
			* math.cos(t * (m.shimmerRate2 + j * 2.3) + m.shimmerPhase2 + j * 3.41)
		local sSq = sWave * sWave
		local shimmer = 0.16 + 0.84 * sSq

		local dDepth01 = Clamp((tz + 1) * 0.5, 0, 1)
		local dAlpha = Clamp(
			(0.84 * shimmer * (0.54 + 0.46 * dDepth01) * litBoost + flashBoost * 0.55)
				* lifeEnv * tEnv * TRAIL_ALPHA_MULT[j] * occ,
			0, 1
		)

		local active, hidden
		if tz >= 0 then active, hidden = m.dFront[j], m.dBack[j] else active, hidden = m.dBack[j], m.dFront[j] end
		hidden:Hide()

		if dAlpha < 0.015 then
			active:Hide()
		else
			local dSize = baseSize * TRAIL_SIZE_MULT[j] * (0.68 + 0.50 * dDepth01) * (0.78 + 0.42 * sSq)
			active:SetSize(dSize, dSize)
			active:ClearAllPoints()
			active:SetPoint("CENTER", vis, "CENTER", px, py)
			active:SetAlpha(dAlpha)
			active:Show()
		end
		prevX, prevY = tx, ty
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
		if m.isChaos or (m.pattern ~= CONST.HELIX and m.pattern ~= CONST.VORTEX) or m.lift >= 1 then
			needRespawn = true
		end
	elseif (m.pattern == CONST.HELIX or m.pattern == CONST.VORTEX) and m.lift >= 1 then
		if m.isChaos then needRespawn = true else m.lift = m.lift - 1 end
	end

	if needRespawn then
		RespawnMote(p, m, modeKey, wasMoodFade, i, count)
		if wasMoodFade then m.age = 0 end
	elseif m.isChaos then
		m.tilt = m.tilt + elapsed * m.precessRate
	elseif not m.fadeOutRem then
		if m.pattern == CONST.ATOM then
			local inc = 1.12 + 0.10 * math.sin(p.moodYaw + m.shellIdx * 2.0944)
			m.cosI, m.sinI = math.cos(inc), math.sin(inc)
			m.tilt = p.moodTilt + m.shellIdx * THIRD_PI
		else
			m.tilt = p.moodTilt
		end
	end
end

local function LayoutDustMotes(orb, elapsed, s, t)
	local p = orb and orb.dust
	if not p then return end
	local cfg = ns:GetOrbDustConfig(orb)
	if not cfg.enabled then return end
	if elapsed > 0.1 then elapsed = 0.1 end

	local count, modeKey, showTails, showTrails = cfg.count, cfg.pattern, cfg.tails, cfg.trails
	if #p.motes < count then EnsurePool(p, count, modeKey) end
	if p.appliedPattern ~= modeKey then ReformSwarm(p, modeKey, count) end
	if p.activeCount ~= count then
		local prevCount = p.activeCount or 0
		if count < prevCount then
			for i = count + 1, #p.motes do HideMote(p.motes[i]) end
		elseif count > prevCount then
			for i = prevCount + 1, count do
				local m = p.motes[i]
				if m and m.moodGen ~= p.moodGen then RespawnMote(p, m, modeKey, true, i, count) end
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

	if elapsed > 0 then StepFormationMood(p, elapsed, modeKey, count) end

	local effSpeed = cfg.speed * (1 + 1.15 * s)
	if elapsed > 0 and modeKey ~= "chaos" then
		p.helixPhase = ((p.helixPhase or 0) + elapsed * (p.moodDir or 1) * 0.28 * effSpeed) % TWO_PI
	end
	local sloshScale = 1 + 0.08 * s
	local flash = orb.accentFlash or 0
	local orbBobY = orb.bobY or 0
	local dustBobY = orbBobY * 0.45
	local useGlare = ns.db.glare
	local lightX = useGlare and (-math.sin(orb.glareAngle or 0)) or 0
	local glareBright = useGlare and (orb.glareBright or 0.45) or 0.45
	local halfOrb = p.orbSize * 0.5
	local glassR = p.orbSize * CONST.GLASS_RADIUS
	local vis = p.visual

	local tailFrac = cfg.tailLength / 100
	local rotRad = math.rad(cfg.rotation)
	local spreadFrac = cfg.spread / 100
	local orbSize = p.orbSize
	local minRx = orbSize * 0.46
	local minRy = orbSize * 0.06
	local baseSegLag = (0.075 + 0.165 * tailFrac) * (0.65 + 0.35 * Clamp(effSpeed, 0.2, 3.0))

	for i = 1, count do
		local m = p.motes[i]
		if elapsed > 0 then StepMoteState(p, m, elapsed, effSpeed, modeKey, i, count) end
		m.sloshScale = sloshScale

		-- Apply live Pattern rotation & Particle spread every frame with zero respawning lag.
		local tiltVal
		if not m.isChaos then
			m.rx = math.max(minRx, m.baseRx + m.rRand * orbSize * 0.20 * spreadFrac)
			m.ry = math.max(minRy, m.baseRy + m.ryRand * orbSize * 0.11 * spreadFrac)
			m.yOff = m.baseYOff + m.yRand * orbSize * 0.22 * spreadFrac
			m.waveAmp = m.baseWaveAmp * (0.4 + 1.4 * spreadFrac)
			tiltVal = m.tilt + m.tRand * 0.44 * spreadFrac + rotRad
		else
			m.rx = math.max(minRx, m.baseRx * (0.82 + 0.36 * spreadFrac) + m.rRand * orbSize * 0.14 * spreadFrac)
			m.ry = math.max(minRy, m.baseRy * (0.70 + 0.60 * spreadFrac))
			m.yOff = m.baseYOff * (0.40 + 1.20 * spreadFrac)
			m.waveAmp = m.baseWaveAmp * (0.40 + 1.20 * spreadFrac)
			tiltVal = m.tilt + rotRad
		end
		m.cosT, m.sinT = math.cos(tiltVal), math.sin(tiltVal)

		local lifeEnv = 1
		if m.age < CONST.FADE_TIME then
			lifeEnv = SmoothStep01(m.age / CONST.FADE_TIME)
		elseif (not m.fadeOutRem) and (m.isChaos or (m.pattern ~= CONST.HELIX and m.pattern ~= CONST.VORTEX))
			and m.age > m.lifeMax - CONST.FADE_TIME
		then
			lifeEnv = SmoothStep01((m.lifeMax - m.age) / CONST.FADE_TIME)
		end
		if m.fadeOutRem and m.fadeOutDur and m.fadeOutDur > 0 then
			lifeEnv = lifeEnv * SmoothStep01(m.fadeOutRem / m.fadeOutDur)
		end

		if lifeEnv <= 0.001 then
			HideMote(m)
		else
			local x0, y0, z0, env0 = EvalPattern(m.pattern, m.phase, m.lift, m)
			local py0 = y0 + dustBobY
			local occ0 = SphereOcclusion(x0, py0 - orbBobY, z0, glassR)
			local depth01 = Clamp((z0 + 1) * 0.5, 0, 1)
			local scale = 0.68 + 0.50 * depth01
			local twinkle = 0.64 + 0.36 * math.sin(t * m.twinkleRate + m.twinklePhase)
			local litBoost = (useGlare and (x0 * lightX) > 0)
				and (1 + 0.45 * glareBright * math.min(1, math.abs(x0) / halfOrb)) or 1
			local flashBoost = (m.kind == 3) and (0.35 * flash) or (0.12 * flash)
			local alpha = Clamp(
				(m.baseAlpha * twinkle * (0.54 + 0.46 * depth01) * litBoost + flashBoost)
					* lifeEnv * env0 * occ0,
				0, 1
			)

			local segDt
			if showTails or showTrails then
				local angRate = math.abs(m.omega)
				if m.pattern == CONST.HELIX then angRate = angRate + math.abs(m.liftRate) * HELIX_TWISTS end
				segDt = (baseSegLag * angRate > 0.34 and angRate > 1e-4) and (0.34 / angRate) or baseSegLag
			end

			local headAngle
			if showTails then
				headAngle = LayoutMoteTails(
					m, vis, x0, y0, z0, env0, lifeEnv, twinkle, litBoost, flashBoost,
					segDt * m.omega, segDt * m.liftRate, dustBobY, orbBobY, glassR
				)
			end
			if showTrails then
				local trailSpan = segDt * 1.35
				LayoutMoteDustTrails(
					m, vis, t, x0, y0, lifeEnv, litBoost, flashBoost,
					trailSpan * m.omega, trailSpan * m.liftRate, tailFrac, spreadFrac, dustBobY, orbBobY, glassR
				)
			end

			local active, hidden
			if z0 >= 0 then active, hidden = m.front, m.back else active, hidden = m.back, m.front end
			hidden:Hide()

			if alpha < 0.01 then
				active:Hide()
			else
				active:SetSize(m.baseW * scale, m.baseH * scale)
				active:ClearAllPoints()
				active:SetPoint("CENTER", vis, "CENTER", x0, py0)
				active:SetAlpha(alpha)
				if m.kind == 2 then
					if not headAngle then
						local tx, ty = EvalPattern(m.pattern, m.phase - 0.04 * m.omega, m.lift - 0.04 * m.liftRate, m)
						local dx, dy = x0 - tx, y0 - ty
						if (dx * dx + dy * dy) > 1e-4 then headAngle = math.atan2(dy, dx) end
					end
					if headAngle then active:SetRotation(headAngle) end
				end
				active:Show()
			end
		end
	end
end

---------------------------------------------------------------------------
-- Public addon contract
---------------------------------------------------------------------------
function ns:AttachOrbDust(orb, visual, holderFront, orbSize)
	local p = {
		orbSize = orbSize, visual = visual, holderFront = holderFront,
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
	if not cfg.enabled then
		for i = 1, #p.motes do HideMote(p.motes[i]) end
		p.activeCount, p.tailsShown, p.trailsShown = 0, false, false
		return
	end

	EnsurePool(p, cfg.count, cfg.pattern)
	if p.appliedPattern ~= cfg.pattern then ReformSwarm(p, cfg.pattern, cfg.count) end
	for i = 1, cfg.count do
		local m = p.motes[i]
		if m and m.moodGen ~= p.moodGen and not m.fadeOutRem then
			RespawnMote(p, m, cfg.pattern, true, i, cfg.count)
		end
	end
	for i = cfg.count + 1, #p.motes do HideMote(p.motes[i]) end
	if not cfg.tails then
		for i = 1, #p.motes do HideMoteTails(p.motes[i]) end
	end
	if not cfg.trails then
		for i = 1, #p.motes do HideMoteDustTrails(p.motes[i]) end
	end
	p.activeCount, p.tailsShown, p.trailsShown = cfg.count, cfg.tails, cfg.trails

	ns:RefreshOrbDustColors(orb)
	LayoutDustMotes(orb, 0, orb.slosh or 0, orb.time or 0)
end

function ns:AnimateOrbDust(orb, elapsed, s, t)
	LayoutDustMotes(orb, elapsed, s, t)
end

function ns:AnyOrbDustEnabled()
	if not ns.orbs then return false end
	for _, orb in pairs(ns.orbs) do
		if ns:GetOrbDustConfig(orb).enabled then return true end
	end
	return false
end

function ns:SetOrbDust(orb, field, value)
	if not (ns.db and orb) then return end
	local cfg = ns:GetOrbDustConfig(orb)
	if field == "enabled" then
		cfg.enabled = value and true or false
	elseif field == "pattern" then
		cfg.pattern = ns.NormalizeDustPattern(value)
	elseif field == "count" then
		cfg.count = ns.NormalizeDustCount(value)
	elseif field == "speed" then
		cfg.speed = ns.NormalizeDustSpeed(value)
	elseif field == "tails" then
		cfg.tails = value and true or false
	elseif field == "trails" then
		cfg.trails = value and true or false
	elseif field == "tailLength" then
		cfg.tailLength = ns.NormalizeDustTailLength(value)
	elseif field == "rotation" then
		cfg.rotation = ns.NormalizeDustRotation(value)
	elseif field == "spread" then
		cfg.spread = ns.NormalizeDustSpread(value)
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

function ns:SetAllOrbDustEnabled(enabled, fromSettings)
	SetAllOrbDustField("enabled", "dustEnabled", enabled and true or false, fromSettings, true)
end

function ns:SetAllOrbDustPattern(pattern, fromSettings)
	SetAllOrbDustField("pattern", "dustPattern", ns.NormalizeDustPattern(pattern), fromSettings, false)
end

function ns:SetAllOrbDustTails(enabled, fromSettings)
	SetAllOrbDustField("tails", "dustTails", enabled and true or false, fromSettings, false)
end

function ns:SetAllOrbDustTrails(enabled, fromSettings)
	SetAllOrbDustField("trails", "dustTrails", enabled and true or false, fromSettings, false)
end
