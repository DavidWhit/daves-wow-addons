-- daves_map / Options.lua
-- Options page in Blizzard's Settings panel (Esc > Options > AddOns). The filters live on the map's own panel.
-- API verified against Blizzard_Settings_Shared/Blizzard_Settings.lua on the forever branch:
--   Settings.RegisterVerticalLayoutCategory(name)
--   Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
--   Settings.CreateCheckbox(category, setting, tooltip) / Settings.CreateSlider(category, setting, options, tooltip)

local ADDON, ns = ...

function ns.LowLevelLabel()
	local n = ns.db.lowLevelGap
	return ("Hide quests %d+ level%s below me"):format(n, n == 1 and "" or "s")
end

function ns:InitOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end   -- very old clients

	local category = Settings.RegisterVerticalLayoutCategory("Dave's Map")

	local enabled = Settings.RegisterAddOnSetting(category, ADDON .. "_enabled", "enabled", ns.db,
		Settings.VarType.Boolean, "Show the map layer", true)
	Settings.CreateCheckbox(category, enabled, "Draw Map Genie's pins on the world map (/dmap toggle).")

	local panelOpen = Settings.RegisterAddOnSetting(category, ADDON .. "_panelOpen", "panelOpen", ns.db,
		Settings.VarType.Boolean, "Show the search panel", true)
	Settings.CreateCheckbox(category, panelOpen, "The search and filter panel beside the world map (also the map icon at the map's bottom left).")

	local pinScale = Settings.RegisterAddOnSetting(category, ADDON .. "_pinScale", "pinScale", ns.db,
		Settings.VarType.Number, "Pin size", 1.0)
	local sliderOptions = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
	sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return ("%d%%"):format(value * 100 + 0.5)
	end)
	Settings.CreateSlider(category, pinScale, sliderOptions, "Size of the pins on the map.")

	local hideLowLevel = Settings.RegisterAddOnSetting(category, ADDON .. "_hideLowLevel", "hideLowLevel", ns.db,
		Settings.VarType.Boolean, "Hide low-level quests", false)
	Settings.CreateCheckbox(category, hideLowLevel, "Hide quests whose required level is well below yours (also on the map's panel).")

	local lowLevelGap = Settings.RegisterAddOnSetting(category, ADDON .. "_lowLevelGap", "lowLevelGap", ns.db,
		Settings.VarType.Number, "Levels below me", 5)
	local gapOptions = Settings.CreateSliderOptions(1, 5, 1)
	gapOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return ("%d+"):format(value)
	end)
	Settings.CreateSlider(category, lowLevelGap, gapOptions, "Hide quests this many levels or more below yours: 1 hides everything under your level, 5 only the far lower ones.")

	-- Settings write straight into ns.db; react to changes here.
	enabled:SetValueChangedCallback(function() if ns.Refresh then ns.Refresh() end end)
	panelOpen:SetValueChangedCallback(function() if ns.UpdatePanel then ns.UpdatePanel() end end)
	pinScale:SetValueChangedCallback(function() if ns.Refresh then ns.Refresh() end end)
	local function LevelChanged()
		if ns.RefreshControls then ns.RefreshControls() end
		if ns.Refresh then ns.Refresh() end
	end
	hideLowLevel:SetValueChangedCallback(LevelChanged)
	lowLevelGap:SetValueChangedCallback(LevelChanged)

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
