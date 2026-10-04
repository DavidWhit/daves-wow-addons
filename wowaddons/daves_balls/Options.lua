-- daves_balls / Options.lua
-- Options page in Blizzard's Settings panel (Esc > Options > AddOns).
-- API verified against Blizzard_Settings_Shared/Blizzard_Settings.lua on the forever branch:
--   Settings.RegisterVerticalLayoutCategory(name)
--   Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
--   Settings.CreateCheckbox(category, setting, tooltip) / Settings.CreateSlider(category, setting, options, tooltip)
--   Settings.CreateDropdown(category, setting, optionsFunc, tooltip) with Settings.CreateControlTextContainer()

local ADDON, ns = ...

function ns:InitOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end   -- very old clients

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

	local locked = Settings.RegisterAddOnSetting(category, ADDON .. "_locked", "locked", ns.db,
		Settings.VarType.Boolean, "Lock orbs", true)
	Settings.CreateCheckbox(category, locked, "Untick to drag the orbs anywhere (right-click one to reset it). They can always be moved in Edit Mode.")

	local hidePlayer = Settings.RegisterAddOnSetting(category, ADDON .. "_hidePlayerFrame", "hidePlayerFrame", ns.db,
		Settings.VarType.Boolean, "Hide Blizzard player frame", false)
	Settings.CreateCheckbox(category, hidePlayer, "Hide the default player frame. The orbs work like it: left-click to target yourself, right-click for your menu.")
	ns.hidePlayerSetting = hidePlayer

	local animate = Settings.RegisterAddOnSetting(category, ADDON .. "_animate", "animate", ns.db,
		Settings.VarType.Boolean, "Animate liquid", true)
	Settings.CreateCheckbox(category, animate, "Swirling liquid that sloshes while you move.")

	local glare = Settings.RegisterAddOnSetting(category, ADDON .. "_glare", "glare", ns.db,
		Settings.VarType.Boolean, "Cursor glare", true)
	Settings.CreateCheckbox(category, glare, "The glass highlight faces your cursor and brightens as the cursor gets closer.")

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
	else
		ns.Print("options are not available on this client.")
	end
end
