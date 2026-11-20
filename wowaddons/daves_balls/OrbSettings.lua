-- daves_balls / OrbSettings.lua
-- Per-orb settings dialog, opened by clicking an orb while it is movable (Blizzard's Edit Mode,
-- or unlocked): colours, number/percent text, accent pattern, bottom holder, bobbing intensity,
-- light-driven cast shadow, 3D swirling dust (orbit pattern, count, speed, trail style, tail
-- length), and position reset. Built with the kit's shared Edit Mode dialog (EditModeDialog.lua).

local _, ns = ...

local dialog

local function CreateDialog(initialOrb)
	dialog = ns.EditMode.CreateDialog("DavesBallsOrbSettings")
	dialog.orb = initialOrb
	local function Orb() return dialog.orb or (ns.orbs and ns.orbs.health) end
	-- Colours get the orb the colour picker was opened for, so a change can't land on the other orb.
	local function SavedColor(field)
		return function(orb) return ns.db.colors[(orb or Orb()).key][field] end
	end
	local function SetColor(field)
		return function(c, orb)
			orb = orb or Orb()
			ns.db.colors[orb.key][field] = c
			ns:RefreshOrbColors(orb)
		end
	end

	dialog:AddColor({ label = "Liquid colour", saved = SavedColor("liquid"), set = SetColor("liquid"),
		get = function(orb) return (ns:GetOrbColors(orb or Orb())) end })
	dialog:AddColor({ label = "Accent colour (core and gold veins)", saved = SavedColor("accent"), set = SetColor("accent"),
		get = function(orb) local _, accent = ns:GetOrbColors(orb or Orb()); return accent end })

	-- Text: compact 1-row grid controlling number/percent flags independently per orb.
	local textButtons = {
		{ key = "none",    text = "Off" },
		{ key = "numbers", text = "Numbers" },
		{ key = "percent", text = "Percent" },
		{ key = "both",    text = "Both" },
	}
	dialog:AddButtonGrid({ label = "Orb text", columns = 4, buttons = textButtons,
		onClick = function(key)
			local t = ns.db.orbText[Orb().key]
			t.number = (key == "numbers" or key == "both")
			t.percent = (key == "percent" or key == "both")
			ns:Apply()
		end,
		isActive = function(key)
			local t = ns.db.orbText[Orb().key]
			if key == "none" then return not t.number and not t.percent end
			if key == "numbers" then return t.number and not t.percent end
			if key == "percent" then return not t.number and t.percent end
			return t.number and t.percent
		end })

	-- Accent pattern: steady flowing veins, or random re-forming arcs (per orb).
	dialog:AddCheckbox({ label = "Random accent pattern",
		tooltip = "On: the gold veins jump to a new random pattern every few seconds and the core flashes. Off: one pattern flows steadily.",
		get = function() return ns.db.accentRandom[Orb().key] end,
		set = function(v) ns.db.accentRandom[Orb().key] = v or nil end })

	-- Optional bottom holder (compact 1-row grid per orb so you can compare looks side by side).
	local holderButtons = {}
	for _, key in ipairs(ns.HOLDER_ORDER) do
		holderButtons[#holderButtons + 1] = { key = key, text = ns.HOLDER_STYLES[key].short }
	end
	dialog:AddButtonGrid({ label = "Bottom holder", columns = 4, buttons = holderButtons,
		onClick = function(key) ns:SetOrbHolder(Orb(), key) end,
		isActive = function(key) return ns:GetOrbHolder(Orb()) == key end })

	-- Subtle vertical bobbing inside the holder container (0% = Off, 5%-100% = float amplitude).
	dialog:AddSlider({ label = "Bob intensity", min = 0, max = 100, step = 5,
		format = function(v) return v <= 0 and "Off" or ("%d%%"):format(v) end,
		get = function()
			local cfg = ns:GetOrbBobConfig(Orb())
			return cfg.enabled and math.max(5, cfg.intensity) or 0
		end,
		set = function(v)
			local orb = Orb()
			if v <= 0 then
				ns:SetOrbBob(orb, "enabled", false)
			else
				ns:SetOrbBob(orb, "intensity", v)
				ns:SetOrbBob(orb, "enabled", true)
			end
		end })

	-- Cast shadow governed by the cursor glare light already hitting the orb and bob height.
	dialog:AddCheckbox({ label = "Cast shadow",
		tooltip = "Cast a soft shadow underneath the orb whose angle, spread, and depth follow the light hitting the glass and its bob height.",
		get = function() return ns:GetOrbShadowEnabled(Orb()) end,
		set = function(v) ns:SetOrbShadow(Orb(), v) end })

	-- 3D swirling dust: selectable orbit pattern, count (0 = Off), speed, rotation, spread & trail style.
	local patternButtons = {}
	for _, key in ipairs(ns.DUST_PATTERN_ORDER) do
		patternButtons[#patternButtons + 1] = { key = key, text = ns.DUST_PATTERNS[key].short }
	end
	dialog:AddButtonGrid({ label = "Orbit pattern", columns = 4, buttons = patternButtons,
		onClick = function(key) ns:SetOrbDust(Orb(), "pattern", key) end,
		isActive = function(key) return ns:GetOrbDustConfig(Orb()).pattern == key end })

	dialog:AddSlider({ label = "Particle count", min = 0, max = 40, step = 2,
		format = function(v) return v <= 0 and "Off" or ("%d"):format(v) end,
		get = function()
			local cfg = ns:GetOrbDustConfig(Orb())
			return cfg.enabled and cfg.count or 0
		end,
		set = function(v)
			local orb = Orb()
			if v <= 0 then
				ns:SetOrbDust(orb, "enabled", false)
			else
				ns:SetOrbDust(orb, "count", v)
				ns:SetOrbDust(orb, "enabled", true)
			end
		end })
	dialog:AddSlider({ label = "Dust speed", min = 0.2, max = 2.5, step = 0.1, format = "%.1fx",
		get = function() return ns:GetOrbDustConfig(Orb()).speed end,
		set = function(v) ns:SetOrbDust(Orb(), "speed", v) end })
	dialog:AddSlider({ label = "Pattern rotation", min = -180, max = 180, step = 15, format = "%d deg",
		get = function() return ns:GetOrbDustConfig(Orb()).rotation end,
		set = function(v) ns:SetOrbDust(Orb(), "rotation", v) end })
	dialog:AddSlider({ label = "Particle spread", min = 0, max = 100, step = 5, format = "%d%%",
		get = function() return ns:GetOrbDustConfig(Orb()).spread end,
		set = function(v) ns:SetOrbDust(Orb(), "spread", v) end })

	local trailButtons = {
		{ key = "none",  text = "Off" },
		{ key = "tails", text = "Tails" },
		{ key = "dust",  text = "Dust" },
		{ key = "both",  text = "Both" },
	}
	dialog:AddButtonGrid({ label = "Trail style", columns = 4, buttons = trailButtons,
		onClick = function(key)
			local orb = Orb()
			if key == "none" then
				ns:SetOrbDust(orb, "tails", false)
				ns:SetOrbDust(orb, "trails", false)
			elseif key == "tails" then
				ns:SetOrbDust(orb, "tails", true)
				ns:SetOrbDust(orb, "trails", false)
			elseif key == "dust" then
				ns:SetOrbDust(orb, "tails", false)
				ns:SetOrbDust(orb, "trails", true)
			else
				ns:SetOrbDust(orb, "tails", true)
				ns:SetOrbDust(orb, "trails", true)
			end
		end,
		isActive = function(key)
			local cfg = ns:GetOrbDustConfig(Orb())
			if key == "none" then return not cfg.tails and not cfg.trails end
			if key == "tails" then return cfg.tails and not cfg.trails end
			if key == "dust" then return not cfg.tails and cfg.trails end
			return cfg.tails and cfg.trails
		end })

	dialog:AddSlider({ label = "Tail length", min = 20, max = 100, step = 10, format = "%d%%",
		get = function() return ns:GetOrbDustConfig(Orb()).tailLength end,
		set = function(v) ns:SetOrbDust(Orb(), "tailLength", v) end })

	-- Global: hide Blizzard's player frame. Goes through the Settings object when there is one,
	-- so the options panel stays in step (its callback runs ns:Apply).
	dialog:AddCheckbox({ label = "Hide Blizzard player frame",
		get = function() return ns.db.hidePlayerFrame end,
		set = function(v)
			if ns.hidePlayerSetting then
				ns.hidePlayerSetting:SetValue(v)
			else
				ns.db.hidePlayerFrame = v
				ns:Apply()
			end
		end })

	dialog:AddNote({ text = function()
		if Orb().key == "power" and not ns.db.colors.power.liquid then
			return "Liquid follows your power type until you pick a colour."
		end
		return ""
	end })

	dialog:AddButton({ text = "Default colours", onClick = function()
		ns.db.colors[Orb().key] = {}
		ns:RefreshOrbColors(Orb())
	end })
	dialog:AddButton({ text = "Reset position", onClick = function() ns:ResetOrbPosition(Orb()) end })
end

function ns:OpenOrbSettings(orb)
	if not dialog then CreateDialog(orb) end
	dialog.orb = orb
	dialog:OpenFor(orb, orb.label .. " Orb")
end

-- Let ApplyOrb close it when the orbs lock again.
ns.orbSettingsDialog = function() return dialog end
