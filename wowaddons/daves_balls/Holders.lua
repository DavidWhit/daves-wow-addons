-- daves_balls / Holders.lua
-- Optional bottom holders, subtle orb bobbing inside its container, and a live
-- cast shadow governed by the cursor light and bob height.

local ADDON, ns = ...

local sin, cos, abs, min, max, floor, random =
	math.sin, math.cos, math.abs, math.min, math.max, math.floor, math.random

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local HOLDER_W_MULT = 1.16    -- u in [-1.16, +1.16] (174 UI units at ORB_SIZE = 150)
local HOLDER_H_MULT = 0.58    -- v in [-1.14, +0.02] (87 UI units at ORB_SIZE = 150)
local HOLDER_Y_MULT = -0.28   -- vertical center at v = -0.56 (-42 UI units)
local TWO_PI = 2 * math.pi

ns.HOLDER_ORDER = { "none", "chalice", "arcane", "sanctum" }

ns.HOLDER_STYLES = {
	none = {
		label = "None",
		short = "None",
		desc = "Original floating glass orb with no holder.",
		shadowY = -0.485,
		shadowW = 0.72,
		shadowH = 0.20,
		shadowShiftX = 14,
	},
	chalice = {
		label = "Gilded Chalice",
		short = "Chalice",
		prefix = "HolderChalice",
		desc = "Wrought dark-iron and antique brass cup with a glowing liquid keystone gem.",
		liquidAlpha = 0.76,
		flowAlpha = 0.42,
		accentAlpha = 0.80,
		sheenAlpha = 0.80,
		flowSpeed = 1.0,
		shadowY = -0.415,
		shadowW = 0.62,
		shadowH = 0.17,
		shadowShiftX = 9,
	},
	arcane = {
		label = "Arcane Cradle",
		short = "Arcane",
		prefix = "HolderArcane",
		desc = "Floating levitation ring and plasma conduit prongs powered by the orb's energy.",
		liquidAlpha = 0.78,
		flowAlpha = 0.75,
		accentAlpha = 0.90,
		sheenAlpha = 0.82,
		flowSpeed = 1.65,
		shadowY = -0.468,
		shadowW = 0.68,
		shadowH = 0.18,
		shadowShiftX = 12,
	},
	sanctum = {
		label = "Sanctum Lotus",
		short = "Sanctum",
		prefix = "HolderSanctum",
		desc = "Sculpted dark-basalt altar basin and antique-gold blooming lotus petals with a concave dish for bobbing and cast shadows.",
		liquidAlpha = 0.78,
		flowAlpha = 0.52,
		accentAlpha = 0.86,
		sheenAlpha = 0.84,
		flowSpeed = 1.20,
		shadowY = -0.438,
		shadowW = 0.66,
		shadowH = 0.18,
		shadowShiftX = 12,
	},
}

local function Clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function ns.NormalizeHolderStyle(style)
	if type(style) == "string" then
		if ns.HOLDER_STYLES[style] then return style end
		local key = style:lower()
		-- Gracefully map the replaced claws variant (or lotus alias) to Sanctum Lotus.
		if key == "claws" or key == "lotus" then return "sanctum" end
		if ns.HOLDER_STYLES[key] then return key end
	end
	return "none"
end

function ns.NormalizeBobIntensity(val)
	local n = tonumber(val)
	if not n then return 35 end
	return floor(Clamp(floor(n + 0.5), 0, 100))
end

function ns:GetOrbHolder(orb)
	if not (ns.db and ns.db.orbHolder and orb) then return "none" end
	return ns.NormalizeHolderStyle(ns.db.orbHolder[orb.key])
end

function ns:GetOrbBobConfig(orb)
	if not (ns.db and orb) then return { enabled = false, intensity = 35 } end
	ns.db.orbBob = ns.db.orbBob or {}
	local cfg = ns.db.orbBob[orb.key]
	if not cfg then
		cfg = {
			enabled = ns.db.bobEnabled and true or false,
			intensity = ns.NormalizeBobIntensity(ns.db.bobIntensity),
		}
		ns.db.orbBob[orb.key] = cfg
	end
	if cfg.enabled == nil then cfg.enabled = ns.db.bobEnabled and true or false end
	cfg.intensity = ns.NormalizeBobIntensity(cfg.intensity)
	return cfg
end

function ns:GetOrbShadowEnabled(orb)
	if not (ns.db and orb) then return false end
	ns.db.orbShadow = ns.db.orbShadow or {}
	if ns.db.orbShadow[orb.key] == nil then
		ns.db.orbShadow[orb.key] = ns.db.castShadow and true or false
	end
	return ns.db.orbShadow[orb.key] and true or false
end

function ns:AttachOrbHolder(orb, visual, holderFront, orbSize)
	local w = orbSize * HOLDER_W_MULT
	local h = orbSize * HOLDER_H_MULT
	local yOff = orbSize * HOLDER_Y_MULT

	local function MakeTex(parent, layer, subLevel, blend)
		local tex = parent:CreateTexture(nil, layer, nil, subLevel)
		tex:SetSize(w, h)
		tex:SetPoint("CENTER", visual, "CENTER", 0, yOff)
		if blend then tex:SetBlendMode(blend) end
		tex:Hide()
		return tex
	end

	-- Back sits on stationary visual behind dustBack, castShadow, and bobFrame.
	local back = MakeTex(visual, "BACKGROUND", -5, "BLEND")

	-- Cast shadow sits above Holder Back (BACKGROUND -5, on top of the Sanctum dish floor)
	-- and below rear airborne dust motes (ARTWORK -2) and bobFrame.
	local castShadow = visual:CreateTexture(nil, "BACKGROUND", nil, -1)
	castShadow:SetTexture(MEDIA .. "OrbCastShadow")
	castShadow:SetBlendMode("BLEND")
	castShadow:SetPoint("CENTER", visual, "CENTER", 0, 0)
	castShadow:Hide()

	-- Front sits on stationary holderFront above bobFrame's glass and below textFrame's numbers.
	local front = MakeTex(holderFront, "ARTWORK", 1, "BLEND")
	local liquid = MakeTex(holderFront, "ARTWORK", 2, "ADD")

	-- Scrolling plasma veins clipped to the holder's liquid energy channel (reuses OrbVeins.tga).
	local flowMask = holderFront:CreateMaskTexture()
	flowMask:SetSize(w, h)
	flowMask:SetPoint("CENTER", visual, "CENTER", 0, yOff)
	local flow = MakeTex(holderFront, "ARTWORK", 2, "ADD")
	flow:SetTexture(MEDIA .. "OrbVeins", "REPEAT", "REPEAT")
	flow:AddMaskTexture(flowMask)

	local accent = MakeTex(holderFront, "ARTWORK", 3, "ADD")
	local sheenL = MakeTex(holderFront, "ARTWORK", 4, "ADD")
	sheenL:SetTexCoord(0, 1, 0, 1)
	local sheenR = MakeTex(holderFront, "ARTWORK", 4, "ADD")
	sheenR:SetTexCoord(1, 0, 0, 1)

	orb.bobPhase = (orb.key == "power") and 2.1 or 0
	orb.bobY = 0
	orb.bobNorm = 0

	orb.holder = {
		style = nil,
		orbSize = orbSize,
		visual = visual,
		back = back,
		castShadow = castShadow,
		front = front,
		liquid = liquid,
		flowMask = flowMask,
		flow = flow,
		accent = accent,
		sheenL = sheenL,
		sheenR = sheenR,
		ox = random(),
		oy = random(),
		bobEnabled = nil,
		bobFrac = 0.35,
		lastBobY = 0,
		shadowEnabled = nil,
		shadowShown = false,
		shX = 9999, shY = 9999, shW = -1, shH = -1, shA = -1,
		regions = { back, front, liquid, flow, accent, sheenL, sheenR },
	}
end

function ns:RefreshOrbHolderColors(orb)
	local h = orb and orb.holder
	if not h then return end
	local c, a = ns:GetOrbColors(orb)
	local r, g, b = c[1], c[2], c[3]
	local gr, gg, gb = r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35
	h.liquid:SetVertexColor(gr, gg, gb)
	h.flow:SetVertexColor(gr, gg, gb)
	h.accent:SetVertexColor(a[1], a[2], a[3])
	h.sheenL:SetVertexColor(1, 1, 1)
	h.sheenR:SetVertexColor(1, 1, 1)
end

function ns:ResetOrbHolderAnim(orb)
	local h = orb and orb.holder
	if not h then return end
	local cfg = h.style and ns.HOLDER_STYLES[h.style]
	if cfg and cfg.prefix then
		if not ns.db.animate then
			h.liquid:SetAlpha(cfg.liquidAlpha * 0.82)
			h.flow:SetAlpha(cfg.flowAlpha * 0.40)
			h.flow:SetTexCoord(h.ox, h.ox + 0.72, h.oy, h.oy + 0.36)
			h.accent:SetAlpha(cfg.accentAlpha * 0.85)
		end
		if not ns.db.glare then
			h.sheenL:SetAlpha(cfg.sheenAlpha * 0.56)
			h.sheenR:SetAlpha(cfg.sheenAlpha * 0.40)
		end
	end
	ns:AnimateOrbShadow(orb)
end

function ns:ApplyOrbBob(orb)
	if not (orb and orb.bobFrame) then return end
	local cfg = ns:GetOrbBobConfig(orb)
	local h = orb.holder
	if h then
		h.bobEnabled = cfg.enabled
		h.bobFrac = cfg.intensity * 0.01
	end
	if not cfg.enabled then
		orb.bobY = 0
		orb.bobNorm = 0
		orb.bobFrame:SetPointsOffset(0, 0)
		if h then h.lastBobY = 0 end
	end
	ns:AnimateOrbShadow(orb)
end

function ns:ApplyOrbShadow(orb)
	local h = orb and orb.holder
	if not h then return end
	local on = ns:GetOrbShadowEnabled(orb)
	h.shadowEnabled = on
	if not on then
		if h.shadowShown then
			h.castShadow:Hide()
			h.shadowShown = false
		end
		return
	end
	h.shX = 9999   -- force layout write after style or toggle change
	ns:AnimateOrbShadow(orb)
end

function ns:ApplyOrbHolder(orb)
	local h = orb and orb.holder
	if not h then return end
	local style = ns:GetOrbHolder(orb)
	local cfg = ns.HOLDER_STYLES[style]
	if not (cfg and cfg.prefix) then
		h.style = "none"
		for _, region in ipairs(h.regions) do region:Hide() end
		ns:ApplyOrbBob(orb)
		ns:ApplyOrbShadow(orb)
		return
	end

	local styleChanged = (h.style ~= style)
	if styleChanged then
		local prefix = MEDIA .. cfg.prefix
		h.back:SetTexture(prefix .. "Back")
		h.front:SetTexture(prefix .. "Front")
		h.liquid:SetTexture(prefix .. "Liquid")
		h.flowMask:SetTexture(prefix .. "Liquid", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		h.accent:SetTexture(prefix .. "Accent")
		h.sheenL:SetTexture(prefix .. "Sheen")
		h.sheenR:SetTexture(prefix .. "Sheen")
		h.style = style
	end

	for _, region in ipairs(h.regions) do region:Show() end
	ns:RefreshOrbHolderColors(orb)
	if styleChanged then
		-- Apply resting alphas immediately so switching holders looks crisp on frame 1
		-- without snapping live animations during unrelated ns:Apply() calls.
		h.liquid:SetAlpha(cfg.liquidAlpha * 0.85)
		h.flow:SetAlpha(cfg.flowAlpha * 0.55)
		h.flow:SetTexCoord(h.ox, h.ox + 0.72, h.oy, h.oy + 0.36)
		h.accent:SetAlpha(cfg.accentAlpha * 0.86)
		h.sheenL:SetAlpha(cfg.sheenAlpha * 0.56)
		h.sheenR:SetAlpha(cfg.sheenAlpha * 0.40)
		orb.glareApplied, orb.glareSettled = nil, false
	end
	ns:ApplyOrbBob(orb)
	ns:ApplyOrbShadow(orb)
	ns:ResetOrbHolderAnim(orb)
end

function ns:SetOrbHolder(orb, style)
	if not (ns.db and orb) then return end
	local key = ns.NormalizeHolderStyle(style)
	ns.db.orbHolder = ns.db.orbHolder or {}
	ns.db.orbHolder[orb.key] = key
	ns:ApplyOrbHolder(orb)

	-- Keep the global Options dropdown aligned whenever both orbs use the same holder.
	local allSame = true
	for orbKey in pairs(ns.ORB_DEFAULTS) do
		if ns.NormalizeHolderStyle(ns.db.orbHolder[orbKey]) ~= key then
			allSame = false
			break
		end
	end
	if allSame then
		ns.db.holder = key
		if ns.NotifyOptionSetting then ns:NotifyOptionSetting("holder") end
	end
end

function ns:SetAllOrbHolders(style, fromSettings)
	if not ns.db then return end
	local key = ns.NormalizeHolderStyle(style)
	ns.db.holder = key
	ns.db.orbHolder = ns.db.orbHolder or {}
	for orbKey in pairs(ns.ORB_DEFAULTS) do
		ns.db.orbHolder[orbKey] = key
	end
	if ns.orbs then
		for _, orb in pairs(ns.orbs) do ns:ApplyOrbHolder(orb) end
	end
	if not fromSettings and ns.NotifyOptionSetting then ns:NotifyOptionSetting("holder") end
	local dlg = ns.orbSettingsDialog and ns.orbSettingsDialog()
	if dlg and dlg:IsShown() then dlg:Refresh() end
end

function ns:SetOrbBob(orb, field, value)
	if not (ns.db and orb) then return end
	local cfg = ns:GetOrbBobConfig(orb)
	if field == "enabled" then
		cfg.enabled = value and true or false
	elseif field == "intensity" then
		cfg.intensity = ns.NormalizeBobIntensity(value)
	end
	ns:ApplyOrbBob(orb)
	if ns.UpdateDriverState then ns:UpdateDriverState() end

	if field == "enabled" then
		local allSame = true
		for orbKey in pairs(ns.ORB_DEFAULTS) do
			local other = ns.orbs and ns.orbs[orbKey]
			if other and ns:GetOrbBobConfig(other).enabled ~= cfg.enabled then
				allSame = false
				break
			end
		end
		if allSame then
			ns.db.bobEnabled = cfg.enabled
			if ns.NotifyOptionSetting then ns:NotifyOptionSetting("bobEnabled") end
		end
	end
end

function ns:SetAllOrbBobEnabled(enabled, fromSettings)
	if not ns.db then return end
	local on = enabled and true or false
	ns.db.bobEnabled = on
	if ns.orbs then
		for _, orb in pairs(ns.orbs) do
			local cfg = ns:GetOrbBobConfig(orb)
			cfg.enabled = on
			ns:ApplyOrbBob(orb)
		end
	end
	if ns.UpdateDriverState then ns:UpdateDriverState() end
	if not fromSettings and ns.NotifyOptionSetting then ns:NotifyOptionSetting("bobEnabled") end
	local dlg = ns.orbSettingsDialog and ns.orbSettingsDialog()
	if dlg and dlg:IsShown() then dlg:Refresh() end
end

function ns:SetOrbShadow(orb, enabled)
	if not (ns.db and orb) then return end
	local on = enabled and true or false
	ns.db.orbShadow = ns.db.orbShadow or {}
	ns.db.orbShadow[orb.key] = on
	ns:ApplyOrbShadow(orb)

	local allSame = true
	for orbKey in pairs(ns.ORB_DEFAULTS) do
		local other = ns.orbs and ns.orbs[orbKey]
		if other and ns:GetOrbShadowEnabled(other) ~= on then
			allSame = false
			break
		end
	end
	if allSame then
		ns.db.castShadow = on
		if ns.NotifyOptionSetting then ns:NotifyOptionSetting("castShadow") end
	end
end

function ns:SetAllOrbShadowEnabled(enabled, fromSettings)
	if not ns.db then return end
	local on = enabled and true or false
	ns.db.castShadow = on
	ns.db.orbShadow = ns.db.orbShadow or {}
	for orbKey in pairs(ns.ORB_DEFAULTS) do
		ns.db.orbShadow[orbKey] = on
	end
	if ns.orbs then
		for _, orb in pairs(ns.orbs) do ns:ApplyOrbShadow(orb) end
	end
	if not fromSettings and ns.NotifyOptionSetting then ns:NotifyOptionSetting("castShadow") end
	local dlg = ns.orbSettingsDialog and ns.orbSettingsDialog()
	if dlg and dlg:IsShown() then dlg:Refresh() end
end

function ns:AnyOrbBobEnabled()
	if not ns.orbs then return false end
	for _, orb in pairs(ns.orbs) do
		if orb.holder and orb.holder.bobEnabled ~= nil then
			if orb.holder.bobEnabled then return true end
		elseif ns:GetOrbBobConfig(orb).enabled then
			return true
		end
	end
	return false
end

function ns:AnimateOrbBob(orb, elapsed, s)
	local h = orb and orb.holder
	if not (orb and orb.bobFrame and h) then return end
	if h.bobEnabled == nil then
		local cfg = ns:GetOrbBobConfig(orb)
		h.bobEnabled = cfg.enabled
		h.bobFrac = cfg.intensity * 0.01
	end
	if not h.bobEnabled then
		if orb.bobY ~= 0 then
			orb.bobY = 0
			orb.bobNorm = 0
			orb.bobFrame:SetPointsOffset(0, 0)
			h.lastBobY = 0
		end
		return
	end

	-- Multi-harmonic buoyancy feels organic rather than mechanical; livelier while moving.
	local freq = 1.40 + 0.55 * s
	orb.bobPhase = ((orb.bobPhase or 0) + elapsed * freq) % TWO_PI
	local wave = 0.82 * sin(orb.bobPhase) + 0.18 * sin(orb.bobPhase * 2 + 0.9)
	local norm = Clamp(wave, -1, 1)
	-- Subtlety scale: 0% = whisper-gentle 0.6px hover, 35% = ~2.8px, 100% = 7.0px float.
	local amp = (0.6 + 6.4 * h.bobFrac) * (1 + 0.16 * s)
	-- Lift resting center slightly upward so the orb hovers cleanly above its cradle seat.
	local bobY = amp * (0.62 + norm)
	orb.bobNorm = norm
	orb.bobY = bobY

	if abs(bobY - h.lastBobY) > 0.05 then
		orb.bobFrame:SetPointsOffset(0, bobY)
		h.lastBobY = bobY
	end
end

function ns:AnimateOrbShadow(orb)
	local h = orb and orb.holder
	if not h then return end
	if h.shadowEnabled == nil then
		h.shadowEnabled = ns:GetOrbShadowEnabled(orb)
	end
	local sh = h.castShadow
	if not h.shadowEnabled then
		if h.shadowShown then
			sh:Hide()
			h.shadowShown = false
		end
		return
	end

	local cfg = (h.style and ns.HOLDER_STYLES[h.style]) or ns.HOLDER_STYLES.none
	local size = h.orbSize

	-- Light direction & intensity from the cursor glare already hitting the orb:
	-- orb.glareAngle = atan2(dy, dx) - pi/2 -> lightX = -sin(a), lightY = cos(a).
	local lightX, lightY, lightBright
	if ns.db.glare then
		lightX = orb.lightX
		lightY = orb.lightY
		if not lightX then
			local a = orb.glareAngle or 0
			lightX = -sin(a)
			lightY = cos(a)
		end
		lightBright = orb.glareBright or 0.55
	else
		lightX = 0
		lightY = 1
		lightBright = 0.72
	end

	-- Light hitting from above deepens the downward cast shadow; distant/dim light softens it.
	local overhead = 0.55 + 0.45 * Clamp((lightY + 0.35) / 1.35, 0, 1)
	local lightDepth = (0.24 + 0.76 * lightBright) * overhead

	-- Proximity to the dish (1.0 when dipped low, 0.0 at bob peak) tightens & darkens the shadow.
	local prox = h.bobEnabled and (0.5 - 0.5 * (orb.bobNorm or 0)) or 0.72
	local lift = 1 - prox

	local offX = -lightX * cfg.shadowShiftX
	local offY = size * cfg.shadowY - lightY * 2.4
	local sw = size * cfg.shadowW * (0.88 + 0.24 * lift + 0.10 * abs(lightX))
	local shH = size * cfg.shadowH * (0.86 + 0.22 * lift)
	local alpha = Clamp(lightDepth * (0.64 + 0.38 * prox), 0.12, 0.96)

	if not h.shadowShown then
		sh:SetSize(sw, shH)
		sh:SetPointsOffset(offX, offY)
		sh:SetAlpha(alpha)
		sh:Show()
		h.shadowShown = true
		h.shW, h.shH, h.shX, h.shY, h.shA = sw, shH, offX, offY, alpha
	else
		if abs(sw - h.shW) > 0.15 or abs(shH - h.shH) > 0.15 then
			sh:SetSize(sw, shH)
			h.shW, h.shH = sw, shH
		end
		if abs(offX - h.shX) > 0.08 or abs(offY - h.shY) > 0.08 then
			sh:SetPointsOffset(offX, offY)
			h.shX, h.shY = offX, offY
		end
		if abs(alpha - h.shA) > 0.005 then
			sh:SetAlpha(alpha)
			h.shA = alpha
		end
	end
end

function ns:AnimateOrbHolder(orb, elapsed, s, t, accentFlicker)
	local h = orb and orb.holder
	if not h then return end
	local cfg = h.style and ns.HOLDER_STYLES[h.style]
	if not (cfg and cfg.prefix) then return end

	local flash = orb.accentFlash or 0
	-- Subtle proximity bounce: the basin & inner petals glow slightly warmer when the orb dips lower.
	local bobProx = 1.0 - 0.14 * (orb.bobNorm or 0)
	local pulse = 0.78 + (0.16 + 0.14 * s) * (orb.coreSin or sin(t * 2.1))
	h.liquid:SetAlpha(min(1, cfg.liquidAlpha * (pulse + 0.20 * s) * bobProx))

	-- Scroll OrbVeins through the holder's liquid energy channel in step with the orb's slosh sway.
	local speed = (1 + 2.5 * s) * cfg.flowSpeed
	h.ox = (h.ox + elapsed * 0.014 * speed) % 1
	h.oy = (h.oy + elapsed * 0.022 * speed) % 1
	local sway = 0.030 * s * (orb.sinPhase or sin(orb.phase or 0))
	local u0 = h.ox + sway
	h.flow:SetTexCoord(u0, u0 + 0.72, h.oy, h.oy + 0.36)
	h.flow:SetAlpha(min(1, cfg.flowAlpha * (0.68 + 0.32 * s + 0.28 * flash) * bobProx))

	h.accent:SetAlpha(min(1, cfg.accentAlpha * accentFlicker * (0.86 + 0.18 * s) + 0.32 * flash))
end

function ns:AnimateOrbHolderGlare(orb)
	local h = orb and orb.holder
	if not h then return end
	local cfg = h.style and ns.HOLDER_STYLES[h.style]
	if not (cfg and cfg.prefix) then return end

	local dirX = orb.lightX or (-sin(orb.glareAngle or 0))
	local bright = orb.glareBright or 0.55
	local leftW = 0.24 + 0.76 * max(0, (1 - dirX) * 0.5)
	local rightW = 0.24 + 0.76 * max(0, (1 + dirX) * 0.5)
	h.sheenL:SetAlpha(min(1, cfg.sheenAlpha * bright * leftW))
	h.sheenR:SetAlpha(min(1, cfg.sheenAlpha * bright * rightW))
end
