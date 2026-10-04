-- {{NAME}} / Options.lua
-- Options page in Blizzard's Settings panel (Esc > Options > AddOns).
-- API verified against Blizzard_Settings_Shared/Blizzard_Settings.lua on the forever branch:
--   Settings.RegisterVerticalLayoutCategory(name)
--   Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
--   Settings.CreateCheckbox(category, setting, tooltip) / Settings.CreateSlider(category, setting, options, tooltip)

local ADDON, ns = ...

function ns:InitOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end   -- very old clients

	local category = Settings.RegisterVerticalLayoutCategory("{{TITLEPLAIN}}")

	local enabled = Settings.RegisterAddOnSetting(category, ADDON .. "_enabled", "enabled", ns.db,
		Settings.VarType.Boolean, "Enabled", true)
	Settings.CreateCheckbox(category, enabled, "Turn {{TITLEPLAIN}} on or off.")

	local scale = Settings.RegisterAddOnSetting(category, ADDON .. "_scale", "scale", ns.db,
		Settings.VarType.Number, "Scale", 1.0)
	local sliderOptions = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
	sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return ("%.2f"):format(value)
	end)
	Settings.CreateSlider(category, scale, sliderOptions, "Size of {{TITLEPLAIN}}'s window.")

	-- Settings write straight into ns.db; react to changes here.
	enabled:SetValueChangedCallback(function() if ns.Apply then ns:Apply() end end)
	scale:SetValueChangedCallback(function() if ns.Apply then ns:Apply() end end)

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
