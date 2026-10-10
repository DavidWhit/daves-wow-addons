-- daves_outofmyway / Options.lua
-- Options page in Blizzard's Settings panel (Esc > Options > AddOns).
-- API verified against Blizzard_Settings_Shared/Blizzard_Settings.lua on the forever branch:
--   Settings.RegisterVerticalLayoutCategory(name)
--   Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
--   Settings.CreateCheckbox(category, setting, tooltip) / Settings.CreateSlider(category, setting, options, tooltip)

local ADDON, ns = ...

function ns:InitOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end   -- very old clients

	local category = Settings.RegisterVerticalLayoutCategory("Dave's Out Of My Way")

	local enabled = Settings.RegisterAddOnSetting(category, ADDON .. "_enabled", "enabled", ns.db,
		Settings.VarType.Boolean, "Move the loot rolls", true)
	Settings.CreateCheckbox(category, enabled, "Off: the loot rolls go back where Blizzard puts them (your position is kept for when you turn it on again).")

	local scale = Settings.RegisterAddOnSetting(category, ADDON .. "_scale", "scale", ns.db,
		Settings.VarType.Number, "Loot roll scale", 1.0)
	local sliderOptions = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
	sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return ("%.2f"):format(value)
	end)
	Settings.CreateSlider(category, scale, sliderOptions, "Size of the loot roll frames once moved (also in Edit Mode).")

	local buffs = Settings.RegisterAddOnSetting(category, ADDON .. "_showAllBuffs", "showAllBuffs", ns.db,
		Settings.VarType.Boolean, "Show all buffs (never collapse)", true)
	Settings.CreateCheckbox(category, buffs, "Every buff shows (up to 32) and the buff frame never collapses: turns off buff consolidation and the collapse arrow, two settings Forever's options don't show. Asks for one reload to finish. Off puts back what you had. Edit Mode's Icon Limit only sets how many buffs per row.")
	buffs:SetValueChangedCallback(function() ns.RetryBuffs() end)

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
