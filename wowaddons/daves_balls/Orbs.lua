-- daves_balls / Orbs.lua
-- Diablo-style health and power orbs for the player.
--
-- Health and power can be secret values on Forever/Midnight, so the fill is a vertical
-- StatusBar clipped to a circle by a mask texture: the values go straight into
-- SetMinMaxValues/SetValue/SetFormattedText and are never compared or used in math.

local ADDON, ns = ...

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local ORB_SIZE = 150
local GLASS_RADIUS = 0.4   -- glass radius as a fraction of ORB_SIZE (OrbMask.tga's circle)
local WAVE_SPAN = 1.5   -- surface width in orb widths; OrbWave.tga holds 2 periods of one orb width each

ns.ORB_DEFAULTS = {
	health = { point = "BOTTOM", x = -540, y = 10 },   -- clear of the action bars
	power  = { point = "BOTTOM", x = 540,  y = 10 },
}

local HEALTH_COLOR = { 0.75, 0.05, 0.05 }

-- Own table so we don't depend on PowerBarColor's location or shape.
local POWER_COLORS = {
	MANA        = { 0.10, 0.25, 0.95 },
	RAGE        = { 0.50, 0.02, 0.03 },   -- dark red, so it reads apart from the health orb
	FOCUS       = { 0.90, 0.50, 0.15 },
	ENERGY      = { 0.55, 0.15, 0.85 },   -- purple
	RUNIC_POWER = { 0.00, 0.75, 1.00 },
	LUNAR_POWER = { 0.30, 0.52, 0.90 },
	MAELSTROM   = { 0.00, 0.50, 1.00 },
	INSANITY    = { 0.40, 0.00, 0.80 },
	FURY        = { 0.79, 0.26, 0.99 },
	PAIN        = { 1.00, 0.61, 0.00 },
}
local DEFAULT_POWER_COLOR = POWER_COLORS.MANA
local GOLD = { 1.0, 0.72, 0.30 }   -- default accent: second vein colour and the core

-- Colours: each orb has a liquid colour and an accent colour. Saved choices live in
-- ns.db.colors[key].liquid / .accent as {r, g, b}; nil means the default (red for health,
-- the power type's colour for power, gold for the accent).
local function DefaultLiquid(orb)
	if orb.key == "health" then return HEALTH_COLOR end
	local _, token = UnitPowerType("player")
	return (token and not issecretvalue(token) and POWER_COLORS[token]) or DEFAULT_POWER_COLOR
end

function ns:GetOrbColors(orb)
	local saved = ns.db.colors[orb.key]
	return saved.liquid or DefaultLiquid(orb), saved.accent or GOLD
end

-- The liquid colour drives a deep version for the liquid and a lighter one for the glow.
function ns:RefreshOrbColors(orb)
	local c, a = ns:GetOrbColors(orb)
	local r, g, b = c[1], c[2], c[3]
	orb.liquidBase:SetVertexColor(r * 0.35, g * 0.35, b * 0.35)
	local gr, gg, gb = r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35
	for _, t in ipairs({ orb.nebula.tex, orb.veins.tex, orb.wave, orb.halo }) do
		t:SetVertexColor(gr, gg, gb)
	end
	orb.veins2.tex:SetVertexColor(a[1], a[2], a[3])
	orb.veins3.tex:SetVertexColor(a[1], a[2], a[3])
	orb.core:SetVertexColor(a[1], a[2], a[3])
end

local orbs = {}
ns.orbs = orbs

---------------------------------------------------------------------------
-- Building an orb
---------------------------------------------------------------------------
local function CreateOrb(key, label)
	local orb = CreateFrame("Frame", "DavesBalls" .. label .. "Orb", UIParent)
	orb.key = key
	orb.label = label
	orb:SetSize(ORB_SIZE, ORB_SIZE)
	orb:SetFrameStrata("MEDIUM")
	orb:SetMovable(true)
	orb:SetClampedToScreen(true)
	-- Clamp the glass, not the frame: the frame has a margin for the halo, and without this
	-- the glass could never reach the very edge of the screen.
	local margin = ORB_SIZE * (0.5 - GLASS_RADIUS)
	orb:SetClampRectInsets(margin, -margin, -margin, margin)
	-- Place it now, before the secure child below makes it protected, so a /reload in
	-- combat still shows the orbs where they belong.
	local pos = ns.db.orbs[key]
	orb:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
	orb:SetScale(ns.db.scale)

	local back = orb:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetTexture(MEDIA .. "OrbBack")

	-- Level: an invisible vertical StatusBar. Its fill texture's top edge marks the liquid
	-- level; we only anchor to that edge and never read its size, so secret values are fine.
	local fill = CreateFrame("StatusBar", nil, orb)
	fill:SetAllPoints()
	fill:SetOrientation("VERTICAL")
	fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	fill:SetStatusBarColor(0, 0, 0, 0)
	fill:SetMinMaxValues(0, 1)
	fill:SetValue(1)
	orb.fill = fill
	local barTex = fill:GetStatusBarTexture()

	-- Liquid: full-orb layers cut by two masks: the glass circle, and a half-plane "level"
	-- mask whose edge sits on the bar's top and rotates when the liquid sloshes, so the whole
	-- body of liquid tilts (not just the foam line). Masks live in the frame they mask.
	local liquid = CreateFrame("Frame", nil, fill)
	liquid:SetAllPoints(orb)
	local circleMask = liquid:CreateMaskTexture()
	circleMask:SetAllPoints(orb)
	circleMask:SetTexture(MEDIA .. "OrbMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	local levelMask = liquid:CreateMaskTexture()
	levelMask:SetSize(ORB_SIZE * 2.2, ORB_SIZE * 2.2)
	levelMask:SetPoint("CENTER", barTex, "TOP")
	levelMask:SetTexture(MEDIA .. "OrbLevel", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	orb.levelMask = levelMask

	-- Energy inside the liquid (inspired by a glass plasma sphere): a deep base colour, glowing
	-- nebula wisps, electric veins in the orb's colour and in gold, drifting sparks and a pulsing
	-- core. Every layer is cut by both masks.
	local function Layer(subLevel, blend, alpha)
		local t = liquid:CreateTexture(nil, "ARTWORK", nil, subLevel)
		t:SetAllPoints(orb)
		t:SetBlendMode(blend)
		t:SetAlpha(alpha)
		t:AddMaskTexture(circleMask)
		t:AddMaskTexture(levelMask)
		return t
	end
	local base = Layer(-8, "BLEND", 1)
	base:SetColorTexture(1, 1, 1)
	orb.liquidBase = base

	-- span: how much of the texture covers the orb (smaller = bigger features).
	-- vx/vy: drift in texture units per second at rest; it speeds up while moving.
	local function Flow(file, subLevel, alpha, span, vx, vy)
		local t = Layer(subLevel, "ADD", alpha)
		t:SetTexture(MEDIA .. file, "REPEAT", "REPEAT")
		local ox, oy = math.random(), math.random()
		t:SetTexCoord(ox, ox + span, oy, oy + span)
		return { tex = t, span = span, vx = vx, vy = vy, ox = ox, oy = oy, alpha = alpha }
	end
	orb.nebula = Flow("OrbCloud", 1, 0.45, 0.8, -0.010, 0.006)
	orb.veins  = Flow("OrbVeins", 2, 0.90, 0.55, 0.012, 0.018)
	orb.veins2 = Flow("OrbVeins", 3, 0.70, 0.45, -0.016, -0.010)
	orb.sparks = Flow("OrbSparks", 4, 0.80, 1.0, 0.004, 0.022)
	-- Second accent layer, used only in "random" accent mode to crossfade to new patterns.
	orb.veins3 = Flow("OrbVeins", 3, 0.70, 0.45, 0.010, -0.014)
	orb.veins3.tex:SetAlpha(0)
	orb.flows = { orb.nebula, orb.veins, orb.veins2, orb.veins3, orb.sparks }
	orb.accentA, orb.accentB = orb.veins2, orb.veins3
	orb.accentFade, orb.accentTimer = nil, 1

	local core = Layer(5, "ADD", 0.8)
	core:SetTexture(MEDIA .. "OrbCore")
	orb.core = core

	-- Soft glow just outside the glass, behind everything.
	local halo = orb:CreateTexture(nil, "BACKGROUND", nil, -1)
	halo:SetAllPoints()
	halo:SetTexture(MEDIA .. "OrbHalo")
	halo:SetBlendMode("ADD")
	orb.halo = halo

	-- Surface: a foam line riding on the liquid level. It scrolls by texture coordinates and
	-- tilts with SetRotation, both driven from OnUpdate (see AnimateSurface) so speed and
	-- slosh ease in and out instead of restarting.
	local surface = CreateFrame("Frame", nil, fill)
	surface:SetAllPoints(orb)
	surface:SetFrameLevel(liquid:GetFrameLevel() + 1)
	local surfaceMask = surface:CreateMaskTexture()
	surfaceMask:SetAllPoints(orb)
	surfaceMask:SetTexture(MEDIA .. "OrbMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

	local wave = surface:CreateTexture(nil, "ARTWORK")
	wave:SetSize(ORB_SIZE * WAVE_SPAN, 36)   -- wider than the orb so the tilted ends stay hidden
	wave:SetPoint("CENTER", barTex, "TOP")   -- rides on the liquid level
	wave:SetTexture(MEDIA .. "OrbWave", "REPEAT", "CLAMP")
	wave:SetBlendMode("ADD")
	wave:SetAlpha(0.6)
	wave:AddMaskTexture(surfaceMask)
	orb.wave = wave
	orb.scroll, orb.phase, orb.slosh = 0, 0, 0

	-- Art on top of the liquid, in its own frame so it sits above the bar.
	local art = CreateFrame("Frame", nil, orb)
	art:SetAllPoints()
	art:SetFrameLevel(fill:GetFrameLevel() + 2)

	local shade = art:CreateTexture(nil, "ARTWORK", nil, 1)
	shade:SetAllPoints()
	shade:SetTexture(MEDIA .. "OrbShade")

	local gloss = art:CreateTexture(nil, "ARTWORK", nil, 2)
	gloss:SetAllPoints()
	gloss:SetTexture(MEDIA .. "OrbGloss")
	gloss:SetBlendMode("ADD")
	orb.gloss = gloss

	local glass = art:CreateTexture(nil, "ARTWORK", nil, 3)
	glass:SetAllPoints()
	glass:SetTexture(MEDIA .. "OrbGlass")

	local text = art:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	text:SetPoint("CENTER", 0, -4)
	text:SetShadowOffset(1, -1)
	orb.text = text

	-- Edit Mode overlay: shown only while Blizzard's Edit Mode is open.
	local sel = CreateFrame("Frame", nil, orb)
	sel:SetAllPoints()
	sel:SetFrameLevel(art:GetFrameLevel() + 5)
	sel:Hide()
	local tint = sel:CreateTexture(nil, "OVERLAY")
	tint:SetAllPoints()
	tint:SetTexture(MEDIA .. "OrbMask")
	tint:SetVertexColor(0.25, 0.6, 1.0, 0.35)
	local name = sel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	name:SetPoint("BOTTOM", sel, "TOP", 0, 2)
	name:SetText(label .. " Orb")
	orb.selection = sel

	-- Player-frame clicks: a secure unit button over the glass. Left-click targets you,
	-- right-click opens your unit menu (SECURE_ACTIONS.togglemenu, SecureTemplates.lua).
	-- Attributes are set once here, out of combat. It is hidden while the orbs are movable.
	local click = CreateFrame("Button", "DavesBalls" .. label .. "OrbButton", orb, "SecureUnitButtonTemplate")
	click:SetSize(ORB_SIZE * 0.8, ORB_SIZE * 0.8)   -- the glass
	click:SetPoint("CENTER")
	click:SetFrameLevel(sel:GetFrameLevel() + 1)
	click:SetAttribute("unit", "player")
	click:SetAttribute("*type1", "target")
	click:SetAttribute("*type2", "togglemenu")
	click:RegisterForClicks("AnyUp")
	click:SetScript("OnEnter", function(self)
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetUnit("player")
		GameTooltip:Show()
	end)
	click:SetScript("OnLeave", function() GameTooltip:Hide() end)
	orb.clickButton = click

	-- While movable (Edit Mode or unlocked): drag to move, click for the orb's settings,
	-- right-click to reset the position.
	-- Dragging is done by hand (not StartMoving) so the orb can snap to Edit Mode's grid
	-- live while it moves. Everything is in screen pixels.
	orb:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		self.dragged = true
		local scale = self:GetEffectiveScale()
		local ox, oy = self:GetCenter()
		local cx, cy = GetCursorPosition()
		self.grabX, self.grabY = cx - ox * scale, cy - oy * scale
		self:SetScript("OnUpdate", ns.DragUpdate)
	end)
	orb:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		if InCombatLockdown() then return end   -- already stopped by PLAYER_REGEN_DISABLED
		ns:SaveOrbPosition(self)
	end)
	orb.StopDrag = orb:GetScript("OnDragStop")
	orb:SetScript("OnMouseUp", function(self, button)
		if not ns:CanMoveOrbs() then return end
		if self.dragged then
			self.dragged = nil
		elseif button == "LeftButton" then
			ns:OpenOrbSettings(self)
		elseif button == "RightButton" then
			ns:ResetOrbPosition(self)
		end
	end)
	orb:SetScript("OnEnter", function(self)
		if not ns:CanMoveOrbs() then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(self.label .. " Orb")
		GameTooltip:AddLine("Click for colours. Drag to move (snaps to the Edit Mode grid; hold Shift to place freely). Right-click to reset position.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	orb:SetScript("OnLeave", function() GameTooltip:Hide() end)

	return orb
end

---------------------------------------------------------------------------
-- Updates (secret-safe: values only ever reach widget setters)
---------------------------------------------------------------------------
-- Percentages come from Blizzard's curve API: with CurveConstants.ScaleTo100
-- (Blizzard_SharedXMLBase/CurveConstants.lua) UnitHealthPercent/UnitPowerPercent return 0-100,
-- possibly secret, which SetFormattedText accepts. If the curve is missing, show numbers.
-- Each orb has its own text flags: ns.db.orbText[key] = { number = bool, percent = bool }.
local function ShowText(orb, cur, getPercent)
	local flags = ns.db.orbText[orb.key]
	local curve = CurveConstants and CurveConstants.ScaleTo100
	local number, percent = flags.number, flags.percent and curve ~= nil
	if number and percent then
		orb.text:SetFormattedText("%d\n%.0f%%", cur, getPercent(curve))
	elseif percent then
		orb.text:SetFormattedText("%.0f%%", getPercent(curve))
	elseif number or flags.percent then   -- percent wanted but no curve API: fall back to the number
		orb.text:SetFormattedText("%d", cur)
	end
end

local TEXT_MODES = {
	numbers = { number = true,  percent = false },
	percent = { number = false, percent = true },
	both    = { number = true,  percent = true },
	none    = { number = false, percent = false },
}

-- The options-panel dropdown sets both orbs at once.
function ns:SetAllOrbText(mode)
	local m = TEXT_MODES[mode] or TEXT_MODES.numbers
	for key in pairs(ns.ORB_DEFAULTS) do
		ns.db.orbText[key] = { number = m.number, percent = m.percent }
	end
	ns:Apply()
end

function ns:OrbTextShown(orb)
	local flags = ns.db.orbText[orb.key]
	return flags.number or flags.percent
end

local function HealthPercent(curve) return UnitHealthPercent("player", true, curve) end
local function PowerPercent(curve) return UnitPowerPercent("player", nil, false, curve) end

local function UpdateHealth(orb)
	local cur, max = UnitHealth("player"), UnitHealthMax("player")
	orb.fill:SetMinMaxValues(0, max)
	orb.fill:SetValue(cur)
	ShowText(orb, cur, HealthPercent)
end

local function UpdatePowerColor(orb)
	ns:RefreshOrbColors(orb)   -- the default power colour follows the power type
end

local function UpdatePower(orb)
	local cur, max = UnitPower("player"), UnitPowerMax("player")
	orb.fill:SetMinMaxValues(0, max)
	orb.fill:SetValue(cur)
	ShowText(orb, cur, PowerPercent)
end

local function OnHealthEvent(self) UpdateHealth(self) end

local function OnPowerEvent(self, event)
	if event == "UNIT_DISPLAYPOWER" or event == "PLAYER_ENTERING_WORLD" then UpdatePowerColor(self) end
	UpdatePower(self)
end

---------------------------------------------------------------------------
-- Position, scale and visibility
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Snap to Edit Mode's grid. Blizzard draws the grid lines every Grid.gridSpacing units out
-- from the Grid frame's centre, and snaps when the grid is shown and "Snap" is ticked
-- (EditModeManagerFrameMixin:IsSnapEnabled, EditModeGridMixin:UpdateGrid in
-- Blizzard_EditMode/Shared/EditModeManager.lua, forever branch). The orb's centre or
-- either edge of its glass snaps to the nearest line, whichever is closer.
---------------------------------------------------------------------------
local function GridSnapInfo()
	local manager = EditModeManagerFrame
	if not (ns.inEditMode and manager and manager.IsSnapEnabled and manager:IsSnapEnabled()) then return end
	local grid = manager.Grid
	if not (grid and grid:IsShown() and grid.gridSpacing) then return end
	local gx, gy = grid:GetCenter()
	if not gx then return end
	local scale = grid:GetEffectiveScale()
	return gx * scale, gy * scale, grid.gridSpacing * scale
end

local function SnapAxis(center, radius, gridCenter, spacing)
	local best
	for _, p in ipairs({ center, center - radius, center + radius }) do
		local line = gridCenter + math.floor((p - gridCenter) / spacing + 0.5) * spacing
		local delta = line - p
		if not best or math.abs(delta) < math.abs(best) then best = delta end
	end
	return center + best
end

-- Screen edges: when the glass comes within EDGE_SNAP pixels of an edge it sits flush
-- against it. This wins over the grid, and works whenever the orbs are being dragged.
local EDGE_SNAP = 16

local function SnapToEdge(center, radius, size)
	if math.abs(center - radius) <= EDGE_SNAP then return radius end
	if math.abs(size - (center + radius)) <= EDGE_SNAP then return size - radius end
end

function ns.DragUpdate(orb)
	local scale = orb:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local x, y = cx - orb.grabX, cy - orb.grabY
	if not IsShiftKeyDown() then                 -- hold Shift to place freely
		local radius = ORB_SIZE * GLASS_RADIUS * scale   -- the glass, not the halo
		local gx, gy, spacing = GridSnapInfo()
		if gx then
			x = SnapAxis(x, radius, gx, spacing)
			y = SnapAxis(y, radius, gy, spacing)
		end
		local uiScale = UIParent:GetEffectiveScale()
		local rawX, rawY = cx - orb.grabX, cy - orb.grabY
		x = SnapToEdge(rawX, radius, UIParent:GetWidth() * uiScale) or x
		y = SnapToEdge(rawY, radius, UIParent:GetHeight() * uiScale) or y
	end
	orb:ClearAllPoints()
	orb:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

function ns:SaveOrbPosition(orb)
	local point, _, relPoint, x, y = orb:GetPoint(1)
	local pos = ns.db.orbs[orb.key]
	pos.point, pos.relPoint, pos.x, pos.y = point, relPoint, x, y
end

function ns:ResetOrbPosition(orb)
	local d = ns.ORB_DEFAULTS[orb.key]
	ns.db.orbs[orb.key] = { point = d.point, x = d.x, y = d.y }
	ns:ApplyOrb(orb)
end

-- The orbs contain a secure button, so they can't be shown, hidden, moved or rescaled in
-- combat. Changes made in combat wait for PLAYER_REGEN_ENABLED.
function ns:ApplyOrb(orb)
	if InCombatLockdown() then
		ns.pendingApply = true
		ns.events:RegisterEvent("PLAYER_REGEN_ENABLED")
		orb.text:SetShown(ns:OrbTextShown(orb))
		return
	end
	local pos = ns.db.orbs[orb.key]
	orb:ClearAllPoints()
	orb:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
	orb:SetScale(ns.db.scale)
	orb.text:SetShown(ns:OrbTextShown(orb))
	orb:SetShown(ns.db.enabled or ns.inEditMode)

	-- Movable in Edit Mode, or any time when unlocked; click-through otherwise.
	local movable = ns:CanMoveOrbs()
	orb.selection:SetShown(movable)
	orb:EnableMouse(movable)
	if movable then orb:RegisterForDrag("LeftButton") else orb:RegisterForDrag() end
	orb.clickButton:SetShown(not movable)
	local settings = ns.orbSettingsDialog and ns.orbSettingsDialog()
	if not movable and settings and settings.orb == orb then settings:Hide() end
end

-- Fires just before combat lockdown starts: finish any drag while the orb can still move.
function ns:PLAYER_REGEN_DISABLED()
	for _, orb in pairs(orbs) do
		if orb:GetScript("OnUpdate") then orb:StopDrag() end
	end
end

function ns:PLAYER_REGEN_ENABLED()
	ns.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if ns.pendingApply then
		ns.pendingApply = nil
		for _, orb in pairs(orbs) do ns:ApplyOrb(orb) end
		ns:ApplyPlayerFrame()
	end
end

-- Blizzard player frame: hidden with a secure visibility driver (SecureStateDriver.lua), which
-- keeps it hidden through combat and Edit Mode. Only undone if we were the ones hiding it.
function ns:ApplyPlayerFrame()
	if not PlayerFrame then return end
	if InCombatLockdown() then
		ns.pendingApply = true
		ns.events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if ns.db.hidePlayerFrame and not ns.playerFrameHidden then
		RegisterStateDriver(PlayerFrame, "visibility", "hide")
		ns.playerFrameHidden = true
	elseif not ns.db.hidePlayerFrame and ns.playerFrameHidden then
		UnregisterStateDriver(PlayerFrame, "visibility")
		PlayerFrame:Show()
		ns.playerFrameHidden = nil
	end
end

function ns:CanMoveOrbs()
	return ns.inEditMode or not ns.db.locked
end

function ns:Apply()
	for _, orb in pairs(orbs) do ns:ApplyOrb(orb) end
	ns:ApplyPlayerFrame()
	if orbs.health then UpdateHealth(orbs.health) end
	if orbs.power then UpdatePowerColor(orbs.power); UpdatePower(orbs.power) end
	ns.SetMoving(IsPlayerMoving())
end

---------------------------------------------------------------------------
-- Animation, driven every frame: `slosh` eases toward 1 while moving and back to 0
-- when still, and scales the drift speed and the tilt, so starting and stopping blend
-- smoothly. The tilt rotates the level mask (the liquid body) and the foam line together.
---------------------------------------------------------------------------
local TILT_REST = math.rad(1.5)   -- gentle rocking when standing still
local TILT_MOVE = math.rad(7)     -- extra rocking at full slosh

-- Accent (gold veins + core), two modes per orb, ns.db.accentRandom[key]:
--   flowing: one pattern drifting steadily, like the rest of the liquid;
--   random:  every few seconds the veins crossfade to a new random arrangement (position,
--            scale, rotation) and the core flashes, like arcs re-forming. Quicker while moving.
local ACCENT_FADE = 0.5   -- seconds per crossfade

local function RandomizeFlow(f)
	f.ox, f.oy = math.random(), math.random()
	f.span = 0.38 + math.random() * 0.2
	f.tex:SetRotation(math.random() * 2 * math.pi)
end

local function AnimateAccent(orb, elapsed, flicker, s)
	local a, b = orb.accentA, orb.accentB
	if not ns.db.accentRandom[orb.key] then
		a.tex:SetAlpha(a.alpha * flicker)
		b.tex:SetAlpha(0)
		orb.accentFlash = 0
		return
	end

	orb.accentFlash = math.max(0, (orb.accentFlash or 0) - elapsed * 3)
	if orb.accentFade then
		orb.accentFade = orb.accentFade + elapsed / ACCENT_FADE
		if orb.accentFade >= 1 then
			orb.accentA, orb.accentB = b, a          -- the new pattern is now the main one
			a, b = b, a
			orb.accentFade = nil
			orb.accentTimer = (1.5 + math.random() * 2.5) / (1 + s)
		end
	else
		orb.accentTimer = orb.accentTimer - elapsed
		if orb.accentTimer <= 0 then
			RandomizeFlow(b)
			orb.accentFade = 0
			orb.accentFlash = 1
		end
	end
	local f = orb.accentFade or 0
	a.tex:SetAlpha(a.alpha * flicker * (1 - f))
	b.tex:SetAlpha(b.alpha * flicker * f)
end

local function AnimateSurface(orb, elapsed)
	local target = ns.moving and 1 or 0
	orb.slosh = orb.slosh + (target - orb.slosh) * math.min(1, elapsed * 2.5)
	local s = orb.slosh

	orb.scroll = (orb.scroll + elapsed * (0.12 + 0.22 * s)) % 1
	orb.phase = (orb.phase + elapsed * (2.2 + 2.0 * s)) % (2 * math.pi)

	local tilt = (TILT_REST + TILT_MOVE * s) * math.sin(orb.phase)
	orb.wave:SetTexCoord(orb.scroll, orb.scroll + WAVE_SPAN / 2, 0, 1)
	orb.wave:SetRotation(tilt)
	orb.levelMask:SetRotation(tilt)

	-- Liquid body drifts faster while moving and sways in step with the surface tilt.
	local speed = 1 + 2.5 * s
	local sway = 0.025 * s * math.sin(orb.phase)
	for _, f in ipairs(orb.flows) do
		f.ox = (f.ox + elapsed * f.vx * speed) % 1
		f.oy = (f.oy + elapsed * f.vy * speed) % 1
		local x = f.ox + sway
		f.tex:SetTexCoord(x, x + f.span, f.oy, f.oy + f.span)
	end

	-- Energy: the core breathes, the veins flicker a little, both livelier while moving.
	orb.time = (orb.time or math.random() * 10) + elapsed
	local t = orb.time
	orb.core:SetAlpha(math.min(1, 0.65 + (0.15 + 0.1 * s) * math.sin(t * 2.1) + 0.35 * (orb.accentFlash or 0)))
	orb.veins.tex:SetAlpha(orb.veins.alpha * (0.85 + 0.15 * math.sin(t * 7.3) * math.sin(t * 3.1)))
	AnimateAccent(orb, elapsed, 0.85 + 0.15 * math.sin(t * 5.7 + 1) * math.sin(t * 2.3), s)
end

---------------------------------------------------------------------------
-- Cursor glare: the cursor acts as the light. The crescent on the rim turns to face it,
-- and is brightest when the cursor is on or near the orb, fading with distance.
-- Each orb works this out for itself, in screen pixels.
---------------------------------------------------------------------------
local TWO_PI = 2 * math.pi
local GLOSS_BASE = math.pi / 2     -- OrbGloss.tga's crescent points straight up
local GLARE_MIN = 0.15             -- brightness when the cursor is far away
local GLARE_FALLOFF = 250          -- pixels beyond the rim over which it fades

local function AnimateGlare(orb, elapsed)
	local ox, oy = orb:GetCenter()
	if issecretvalue(ox) or issecretvalue(oy) or not ox then return end
	local scale = orb:GetEffectiveScale()
	ox, oy = ox * scale, oy * scale
	local cx, cy = GetCursorPosition()          -- already in screen pixels
	local dx, dy = cx - ox, cy - oy

	local targetAngle = math.atan2(dy, dx) - GLOSS_BASE
	local beyondRim = math.max(0, math.sqrt(dx * dx + dy * dy) - ORB_SIZE * GLASS_RADIUS * scale)
	local targetBright = GLARE_MIN + (1 - GLARE_MIN) * math.exp(-beyondRim / GLARE_FALLOFF)

	-- Ease along the shortest way round the circle so it glides rather than snaps.
	orb.glareAngle = orb.glareAngle or targetAngle
	orb.glareBright = orb.glareBright or targetBright
	local k = math.min(1, elapsed * 8)
	local diff = (targetAngle - orb.glareAngle + math.pi) % TWO_PI - math.pi
	orb.glareAngle = (orb.glareAngle + diff * k) % TWO_PI
	orb.glareBright = orb.glareBright + (targetBright - orb.glareBright) * k

	orb.gloss:SetRotation(orb.glareAngle)
	orb.gloss:SetAlpha(orb.glareBright)
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
	local db = ns.db
	for _, orb in pairs(orbs) do
		if orb:IsVisible() then
			if db.animate then AnimateSurface(orb, elapsed) end
			if db.glare then AnimateGlare(orb, elapsed) end
		end
	end
end)
driver:Hide()

local function SetMoving(moving)
	ns.moving = moving
	local animate = ns.db.animate
	for _, orb in pairs(orbs) do
		orb.wave:SetShown(animate)   -- the liquid layers stay, frozen, when animation is off
		if not animate then orb.levelMask:SetRotation(0) end
		if not ns.db.glare then
			orb.gloss:SetRotation(0)
			orb.gloss:SetAlpha(1)
		end
	end
	driver:SetShown(animate or ns.db.glare)
end
ns.SetMoving = SetMoving

function ns:PLAYER_STARTED_MOVING() SetMoving(true) end
function ns:PLAYER_STOPPED_MOVING() SetMoving(false) end

---------------------------------------------------------------------------
-- Edit Mode: EventRegistry "EditMode.Enter"/"EditMode.Exit" are fired by
-- EditModeManagerFrameMixin (Blizzard_EditMode/Shared/EditModeManager.lua, forever branch).
---------------------------------------------------------------------------
local function SetEditMode(active)
	ns.inEditMode = active
	for _, orb in pairs(orbs) do ns:ApplyOrb(orb) end
	if not active then GameTooltip:Hide() end
end

function ns:InitOrbs()
	ns.db.orbs = ns.db.orbs or {}
	ns.db.colors = ns.db.colors or {}
	ns.db.orbText = ns.db.orbText or {}
	ns.db.accentRandom = ns.db.accentRandom or {}
	local startText = TEXT_MODES[ns.db.textMode] or TEXT_MODES.numbers
	for key, d in pairs(ns.ORB_DEFAULTS) do
		ns.db.orbs[key] = ns.db.orbs[key] or { point = d.point, x = d.x, y = d.y }
		ns.db.colors[key] = ns.db.colors[key] or {}
		ns.db.orbText[key] = ns.db.orbText[key] or { number = startText.number, percent = startText.percent }
	end

	local health = CreateOrb("health", "Health")
	ns:RefreshOrbColors(health)
	health:RegisterUnitEvent("UNIT_HEALTH", "player")
	health:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
	health:RegisterEvent("PLAYER_ENTERING_WORLD")
	health:SetScript("OnEvent", OnHealthEvent)
	orbs.health = health

	local power = CreateOrb("power", "Power")
	power:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	power:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	power:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	power:RegisterEvent("PLAYER_ENTERING_WORLD")
	power:SetScript("OnEvent", OnPowerEvent)
	orbs.power = power

	SetEditMode(false)
	SetMoving(IsPlayerMoving())
	ns.events:RegisterEvent("PLAYER_REGEN_DISABLED")
	ns.events:RegisterEvent("PLAYER_STARTED_MOVING")
	ns.events:RegisterEvent("PLAYER_STOPPED_MOVING")

	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Enter", function() SetEditMode(true) end, ns)
		EventRegistry:RegisterCallback("EditMode.Exit", function() SetEditMode(false) end, ns)
	end
end
