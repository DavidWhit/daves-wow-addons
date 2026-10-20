-- daves_frames / Unit.lua
-- Fills the frame from the unit: health, resource, heals and shields, name, level, colour, portrait,
-- who they target, dead. Health, absorbs and heals are secret on Forever: they go straight into bars and
-- text setters (and Blizzard's AbbreviateNumbers), never into our own maths or comparisons.

local _, ns = ...

local EASE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local SNAP = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
local SCALE100 = CurveConstants and CurveConstants.ScaleTo100
-- Whether percents exist is decided from the functions: the percent itself is always secret, and a
-- secret is never tested with if / not / and / or.
local HAS_HPCT = SCALE100 ~= nil and UnitHealthPercent ~= nil
local HAS_PPCT = SCALE100 ~= nil and UnitPowerPercent ~= nil

local function Secret(v) return issecretvalue and issecretvalue(v) end

-- Short numbers, three figures from 1,000 up: 1.23k, 12.3k, 123k, 1.23m, 12.3m, 123m, 1.23b... At most two
-- decimals and four characters plus the letter, so they fit the portrait even at the smallest Scale.
-- Blizzard's AbbreviateNumbers with our own breakpoints (LocalizationSharedDocumentation.lua); each pair of
-- divisors multiplies to its named order. Korean and Chinese count in 10,000s (万/만), so those clients keep
-- Blizzard's own abbreviation. Falls back to it too if the game refuses ours.
local ABBREV
do
	local locale = GetLocale and GetLocale()
	if locale ~= "koKR" and locale ~= "zhCN" and locale ~= "zhTW" then
		local data = {}
		for _, u in ipairs({ { 1e9, "b" }, { 1e6, "m" }, { 1e3, "k" } }) do
			local order, letter = u[1], u[2]
			-- 123b / 12.3b / 1.23b: breakpoint, significand divisor, fraction divisor
			for _, step in ipairs({ { 100, 1 }, { 10, 10 }, { 1, 100 } }) do
				data[#data + 1] = { breakpoint = order * step[1], abbreviation = letter, abbreviationIsGlobal = false,
					significandDivisor = order / step[2], fractionDivisor = step[2] }
			end
		end
		ABBREV = { breakpointData = data }
		if CreateAbbreviateConfig then
			local ok, config = pcall(CreateAbbreviateConfig, data)
			-- Rejected: Blizzard's own abbreviation from then on, rather than a failing try on every update.
			if ok and config then ABBREV = { config = config } else ABBREV = nil end
		end
	end
end
local function Short(v)
	if ABBREV then
		local ok, s = pcall(AbbreviateNumbers, v, ABBREV)
		if ok then return s end
		ABBREV = nil   -- refused once: stop trying
	end
	return AbbreviateNumbers(v)
end

-- The unit shown: the target, or yourself while previewing (Edit Mode or /davesframes test).
function ns:CurrentUnit()
	if UnitExists("target") then return "target" end
	if ns.preview then return "player" end
end

-- Puts value and/or percent into a font string, per the Numbers / % / Both setting.
local function SetNumbers(fs, value, pct, hasPct)
	local fmt = ns.db.format
	if fmt == "num" or not hasPct then fs:SetText(value)
	elseif fmt == "pct" then fs:SetFormattedText("%.0f%%", pct)
	else fs:SetFormattedText("%s  \194\183  %.0f%%", value, pct) end
end

function ns:Refresh()
	local f = ns.frame
	if not f then return end
	local unit = ns:CurrentUnit()
	-- A new unit (or none): nothing from the last one carries over.
	ns.token = (ns.token or 0) + 1   -- stale delayed updates (the damage trail) check this
	ns.trailPending, ns.castFinishing, ns.cast = nil, nil, nil
	if not unit or not (ns.db.enabled or ns.editing) then
		ns.unit = nil
		f:Hide()
		return
	end
	ns.unit = unit
	f:Show()
	ns:UpdateIdentity()
	ns:UpdateHealth(true)
	ns:UpdatePower(true)
	ns:UpdatePrediction()
	ns:UpdatePortrait()
	ns:UpdateTargetOfTarget()
	ns:RefreshCast()
	ns:RefreshAuras(true)
end

function ns:UpdateHealth(snap)
	local f, unit = ns.frame, ns.unit
	if not unit then return end
	local hp, max = UnitHealth(unit), UnitHealthMax(unit)
	local bars = f.healthBars
	if not bars then bars = { f.health, f.trail, f.heal, f.absorb }; f.healthBars = bars end
	for _, bar in ipairs(bars) do bar:SetMinMaxValues(0, max) end
	f.health:SetValue(hp, snap and SNAP or EASE)
	if snap then
		f.trail:SetValue(hp, SNAP)
	elseif ns.trailPending ~= ns.token then
		-- The pale trail catches up half a second after a hit (for this unit only).
		local token = ns.token
		ns.trailPending = token
		C_Timer.After(0.55, function()
			if ns.trailPending == token then ns.trailPending = nil end
			if ns.unit and token == ns.token then f.trail:SetValue(UnitHealth(ns.unit), EASE) end
		end)
	end

	local dead = UnitIsDeadOrGhost(unit) and true or false
	if dead ~= ns.isDead then ns:SetDead(dead) end
	local pct
	if HAS_HPCT then pct = UnitHealthPercent(unit, false, SCALE100) end
	local value = Short(hp)
	SetNumbers(f.pnHealth, value, pct, HAS_HPCT)
	f.numHealthValue:SetText(value)
	if HAS_HPCT then f.numHealthPct:SetFormattedText("%.0f%%", pct) end
end

function ns:UpdatePrediction()
	local f, unit = ns.frame, ns.unit
	if not unit then return end
	-- Pass straight through; only a plain nil (no data at all) is replaced.
	local heal = UnitGetIncomingHeals(unit)
	if Secret(heal) or heal ~= nil then f.heal:SetValue(heal) else f.heal:SetValue(0) end
	local absorb = UnitGetTotalAbsorbs(unit)
	if Secret(absorb) or absorb ~= nil then f.absorb:SetValue(absorb) else f.absorb:SetValue(0) end
end

function ns:UpdatePower(snap)
	local f, unit = ns.frame, ns.unit
	if not unit then return end
	local ptype, token = UnitPowerType(unit)
	local max = UnitPowerMax(unit, ptype)
	local none = not Secret(max) and max == 0
	f.power:SetMinMaxValues(0, none and 1 or max)
	f.power:SetValue(none and 0 or UnitPower(unit, ptype), snap and SNAP or EASE)

	if token ~= ns.powerToken then
		ns.powerToken = token
		local c = (PowerBarColor and (PowerBarColor[token] or PowerBarColor[ptype]))
		local shades = c and ns.ShadesOf(c.r, c.g, c.b) or ns.COLORS.mana
		if token == "MANA" then shades = ns.COLORS.mana end
		ns.Paint(f.power:GetStatusBarTexture(), shades)
		ns.PaintTrough(f.clipR.trough, shades)
		ns.powerShades = shades
	end

	if none then
		f.pnPower:SetText(""); f.numPowerPct:SetText(""); f.numPowerValue:SetText("")
		return
	end
	local pct
	if HAS_PPCT then pct = UnitPowerPercent(unit, ptype, false, SCALE100) end
	local value = Short(UnitPower(unit, ptype))
	SetNumbers(f.pnPower, value, pct, HAS_PPCT)
	f.numPowerValue:SetText(value)
	if HAS_PPCT then f.numPowerPct:SetFormattedText("%.0f%%", pct) end
end

-- Health colour: class colour for players you can't attack, else reaction; grey when tapped by others.
local function HealthShades(unit)
	if UnitIsPlayer(unit) and not UnitCanAttack("player", unit) then
		local _, class = UnitClass(unit)
		if not Secret(class) and class ~= nil and RAID_CLASS_COLORS then
			local c = RAID_CLASS_COLORS[class]
			if c then return ns.ShadesOf(c.r, c.g, c.b) end
		end
	end
	if UnitIsTapDenied(unit) then return ns.COLORS.tapped end
	local reaction = UnitReaction(unit, "player")
	if reaction == nil or Secret(reaction) then return ns.COLORS.hostile end
	if reaction <= 3 then return ns.COLORS.hostile elseif reaction == 4 then return ns.COLORS.neutral end
	return ns.COLORS.friendly
end

function ns:UpdateIdentity()
	local f, unit = ns.frame, ns.unit
	if not unit then return end
	local shades = HealthShades(unit)
	ns.healthShades = shades
	ns.Paint(f.health:GetStatusBarTexture(), shades)
	ns.PaintTrough(f.clipL.trough, shades)

	f.name:SetText(UnitName(unit))
	if ns.Stacked() then f.name:SetTextColor(unpack(shades[1])) else f.name:SetTextColor(1, 1, 1) end

	local level = UnitLevel(unit)
	if Secret(level) then
		f.level:SetText(level); f.level:SetTextColor(1, 0.82, 0)
	elseif level <= 0 then
		f.level:SetText("??"); f.level:SetTextColor(1, 0.23, 0.19)
	else
		f.level:SetText(level)
		local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(level)
		if c then f.level:SetTextColor(c.r, c.g, c.b) else f.level:SetTextColor(1, 0.82, 0) end
	end
end

function ns:UpdatePortrait()
	if ns.unit then SetPortraitTexture(ns.frame.portrait, ns.unit) end
end

function ns:UpdateTargetOfTarget()
	local f, unit = ns.frame, ns.unit
	if not unit then return end
	local tt = unit .. "target"
	if UnitExists(tt) then f.tot:SetFormattedText("on %s", UnitName(tt)) else f.tot:SetText("") end
end

-- Dead: grey art and portrait, health reads Dead, boards fade (Auras.lua checks ns.isDead).
function ns:SetDead(dead)
	local f = ns.frame
	ns.isDead = dead
	f.art:SetDesaturated(dead)
	f.art:SetVertexColor(dead and 0.72 or 1, dead and 0.72 or 1, dead and 0.72 or 1)
	f.portrait:SetDesaturated(dead)
	f.dead:SetShown(dead)
	f.pnHealth:SetAlpha(dead and 0 or 1); f.pnPower:SetAlpha(dead and 0 or 1)
	f.numHealthValue:SetAlpha(dead and 0 or 1); f.numHealthPct:SetAlpha(dead and 0 or 1)
end
