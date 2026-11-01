-- daves_map / Options.lua
-- Options page in Blizzard's Settings panel (Esc > Options > AddOns). The filters live on the map's own panel.
-- API verified against Blizzard_Settings_Shared/Blizzard_Settings.lua on the forever branch:
--   Settings.RegisterVerticalLayoutCategory(name)
--   Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
--   Settings.CreateCheckbox(category, setting, tooltip) / Settings.CreateSlider(category, setting, options, tooltip)

local ADDON, ns = ...

function ns.LowLevelLabel()
	local n = ns.db.lowLevelGap
	return ("Hide quests >%d level%s below me"):format(n, n == 1 and "" or "s")
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
		return (">%d"):format(value)
	end)
	Settings.CreateSlider(category, lowLevelGap, gapOptions, "Hide quests more than this many levels below yours: 1 hides everything 2 or more under your level, 5 only the far lower ones.")

	local focusQuest = Settings.RegisterAddOnSetting(category, ADDON .. "_focusQuest", "focusQuest", ns.db,
		Settings.VarType.Boolean, "Click a tracked quest to focus it", true)
	Settings.CreateCheckbox(category, focusQuest, "A click on a quest anywhere (its name or \"...\" icon in the objective tracker, its \"...\" icon on the map, the quest log's list, a Ready to Turn In row) focuses it, opens its details beside the map (out of combat) and centres it on the map; clicking it again lets it go. While a quest you focused that way is focused, Dave's Map shows only its pins: where it's picked up, turned in and where it sends you. Nothing focused: every pin in the area. Off: Blizzard's clicks as they are.")
	focusQuest:SetValueChangedCallback(function()
		if ns.UpdateFocus then ns.UpdateFocus() end
		if ns.Refresh then ns.Refresh() end
	end)

	-- the seamless map (Stitch\): only with the drop-in daves_map_textures; its settings are OpenMap's own keys
	local stitch = ns.OM and ns.OM:GetModule("worldmap")
	local seamless
	if stitch and stitch.db and not ns.OpenMapOn() then   -- (with OpenMap itself on, ours stays off: no switches for it)
		seamless = Settings.RegisterAddOnSetting(category, ADDON .. "_seamless", "enabled", stitch.db,
			Settings.VarType.Boolean, "Seamless world map", true)
		Settings.CreateCheckbox(category, seamless, "Every zone stitched into one map (OpenMap's): the wheel zooms from the whole world to street level, out of one zone into the next. Takes a /reload.")
		local follow = Settings.RegisterAddOnSetting(category, ADDON .. "_autoSwitch", "autoSwitch", stitch.db,
			Settings.VarType.Boolean, "Load the zone in view", true)
		Settings.CreateCheckbox(category, follow, "Once the seamless map stops moving, the zone you're looking at loads underneath: its quest areas, coordinates and name.")
		local zoomed = Settings.RegisterAddOnSetting(category, ADDON .. "_openZoomed", "openZoomed", stitch.db,
			Settings.VarType.Boolean, "Open zoomed in on me", true)
		Settings.CreateCheckbox(category, zoomed, "The map opens on you, zoomed in as far as it goes. Off: your whole zone, as Blizzard's.")
	end

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
	if seamless then seamless:SetValueChangedCallback(function() ns.Print("the seamless map changes after a /reload.") end) end

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
