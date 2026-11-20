-- daves_balls / Options.lua
-- Options page in Blizzard's Settings panel (Esc > Options > AddOns).
-- API verified against Blizzard_Settings_Shared/Blizzard_Settings.lua on the forever branch:
--   Settings.RegisterVerticalLayoutCategory(name)
--   Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
--   Settings.CreateCheckbox(category, setting, tooltip) / Settings.CreateSlider(category, setting, options, tooltip)
--   Settings.CreateDropdown(category, setting, optionsFunc, tooltip) with Settings.CreateControlTextContainer()

local ADDON, ns = ...

local syncingSetting = false

function ns:NotifyOptionSetting(key)
	if not (key and Settings and Settings.NotifyUpdate and SettingsPanel and SettingsPanel:IsShown()) then return end
	local was = syncingSetting
	syncingSetting = true
	pcall(Settings.NotifyUpdate, ADDON .. "_" .. key)
	syncingSetting = was
end

function ns:InitOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

	local category = Settings.RegisterVerticalLayoutCategory("Dave's Balls")

	local enabled = Settings.RegisterAddOnSetting(category, ADDON .. "_enabled", "enabled", ns.db,
		Settings.VarType.Boolean, "Enabled", true)
	Settings.CreateCheckbox(category, enabled, "Show the health and power orbs.")

	local textMode = Settings.RegisterAddOnSetting(category, ADDON .. "_textMode", "textMode", ns.db,
		Settings.VarType.String, "Text", "numbers")
	local function TextOptions()
		local container = Settings.CreateControlTextContainer()
		container:Add("numbers", "Numbers")
		container:Add("percent", "Percent")
		container:Add("both", "Numbers and percent")
		container:Add("none", "Hidden")
		return container:GetData()
	end
	Settings.CreateDropdown(category, textMode, TextOptions, "What to show inside both orbs. Click an orb in Edit Mode to set each one separately.")
	textMode:SetValueChangedCallback(function() ns:SetAllOrbText(ns.db.textMode) end)

	local holder = Settings.RegisterAddOnSetting(category, ADDON .. "_holder", "holder", ns.db,
		Settings.VarType.String, "Orb holder", "none")
	local function HolderOptions()
		local container = Settings.CreateControlTextContainer()
		for _, key in ipairs(ns.HOLDER_ORDER) do
			local cfg = ns.HOLDER_STYLES[key]
			container:Add(key, cfg.label, cfg.desc)
		end
		return container:GetData()
	end
	Settings.CreateDropdown(category, holder, HolderOptions, "Optional bottom cradle holding both orbs. Click an orb in Edit Mode to pick a different holder per orb.")
	holder:SetValueChangedCallback(function()
		if syncingSetting then return end
		ns:SetAllOrbHolders(ns.db.holder, true)
	end)

	local bobEnabled = Settings.RegisterAddOnSetting(category, ADDON .. "_bobEnabled", "bobEnabled", ns.db,
		Settings.VarType.Boolean, "Orb bobbing", false)
	Settings.CreateCheckbox(category, bobEnabled, "Gently float both orbs up and down inside their holders. Adjust per-orb intensity by clicking an orb in Edit Mode.")
	bobEnabled:SetValueChangedCallback(function()
		if syncingSetting then return end
		ns:SetAllOrbBobEnabled(ns.db.bobEnabled, true)
	end)

	local castShadow = Settings.RegisterAddOnSetting(category, ADDON .. "_castShadow", "castShadow", ns.db,
		Settings.VarType.Boolean, "Cast shadow", false)
	Settings.CreateCheckbox(category, castShadow, "Cast a soft shadow underneath each orb whose angle and depth follow the light hitting it and its bob height.")
	castShadow:SetValueChangedCallback(function()
		if syncingSetting then return end
		ns:SetAllOrbShadowEnabled(ns.db.castShadow, true)
	end)

	local dustEnabled = Settings.RegisterAddOnSetting(category, ADDON .. "_dustEnabled", "dustEnabled", ns.db,
		Settings.VarType.Boolean, "Swirling dust", false)
	Settings.CreateCheckbox(category, dustEnabled, "3D orbiting dust motes wrapping behind and in front of both orbs with true sphere-rim occlusion. Pick an orbit pattern and tune count, speed, and trail style per orb in Edit Mode.")
	dustEnabled:SetValueChangedCallback(function()
		if syncingSetting then return end
		ns:SetAllOrbDustEnabled(ns.db.dustEnabled, true)
	end)

	local dustPattern = Settings.RegisterAddOnSetting(category, ADDON .. "_dustPattern", "dustPattern", ns.db,
		Settings.VarType.String, "Orbit pattern", "auto")
	local function DustPatternOptions()
		local container = Settings.CreateControlTextContainer()
		for _, key in ipairs(ns.DUST_PATTERN_ORDER) do
			local cfg = ns.DUST_PATTERNS[key]
			container:Add(key, cfg.label, cfg.desc)
		end
		return container:GetData()
	end
	Settings.CreateDropdown(category, dustPattern, DustPatternOptions, "3D orbital formation for both orbs (Auto cycles cleanly between formations; Chaos mixes them freely). Click an orb in Edit Mode to pick a different pattern per orb.")
	dustPattern:SetValueChangedCallback(function()
		if syncingSetting then return end
		ns:SetAllOrbDustPattern(ns.db.dustPattern, true)
	end)

	local dustTails = Settings.RegisterAddOnSetting(category, ADDON .. "_dustTails", "dustTails", ns.db,
		Settings.VarType.Boolean, "Particle tails", true)
	Settings.CreateCheckbox(category, dustTails, "Add curved glowing comet tails trailing behind orbiting dust particles on both orbs (works with or without shimmering dust trails). Adjust trail style and length per orb in Edit Mode.")
	dustTails:SetValueChangedCallback(function()
		if syncingSetting then return end
		ns:SetAllOrbDustTails(ns.db.dustTails, true)
	end)

	local dustTrails = Settings.RegisterAddOnSetting(category, ADDON .. "_dustTrails", "dustTrails", ns.db,
		Settings.VarType.Boolean, "Shimmering dust trails", true)
	Settings.CreateCheckbox(category, dustTrails, "Shed a sparkling, shimmering stardust wake behind orbiting particles (works with or without comet tails).")
	dustTrails:SetValueChangedCallback(function()
		if syncingSetting then return end
		ns:SetAllOrbDustTrails(ns.db.dustTrails, true)
	end)

	local locked = Settings.RegisterAddOnSetting(category, ADDON .. "_locked", "locked", ns.db,
		Settings.VarType.Boolean, "Lock orbs", true)
	Settings.CreateCheckbox(category, locked, "Untick to drag the orbs anywhere (left- or right-click one for its settings). They can always be moved in Edit Mode.")

	local hidePlayer = Settings.RegisterAddOnSetting(category, ADDON .. "_hidePlayerFrame", "hidePlayerFrame", ns.db,
		Settings.VarType.Boolean, "Hide Blizzard player frame", false)
	Settings.CreateCheckbox(category, hidePlayer, "Hide the default player frame. The orbs work like it: left-click to target yourself, right-click for your menu.")
	ns.hidePlayerSetting = hidePlayer

	local animate = Settings.RegisterAddOnSetting(category, ADDON .. "_animate", "animate", ns.db,
		Settings.VarType.Boolean, "Animate liquid", true)
	Settings.CreateCheckbox(category, animate, "Swirling liquid that sloshes while you move.")

	local glare = Settings.RegisterAddOnSetting(category, ADDON .. "_glare", "glare", ns.db,
		Settings.VarType.Boolean, "Cursor glare", true)
	Settings.CreateCheckbox(category, glare, "The glass highlight faces your cursor and brightens as the cursor gets closer, also driving the cast shadow and holder sheen.")

	local scale = Settings.RegisterAddOnSetting(category, ADDON .. "_scale", "scale", ns.db,
		Settings.VarType.Number, "Scale", 1.0)
	local sliderOptions = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
	sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return ("%.2f"):format(value)
	end)
	Settings.CreateSlider(category, scale, sliderOptions, "Size of the orbs.")

	-- Settings write straight into ns.db; react to changes here.
	for _, setting in ipairs({ enabled, locked, hidePlayer, animate, glare, scale }) do
		setting:SetValueChangedCallback(function() ns:Apply() end)
	end

	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end

function ns:OpenOptions()
	if ns.settingsCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.settingsCategory:GetID())
	end
end
