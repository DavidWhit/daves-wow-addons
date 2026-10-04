-- daves_castbar / Options.lua
-- Options page in Blizzard's Settings panel (Esc > Options > AddOns).
-- API verified against Blizzard_Settings_Shared/Blizzard_Settings.lua on the forever branch:
--   Settings.RegisterVerticalLayoutCategory(name)
--   Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, variableType, name, defaultValue)
--   Settings.CreateCheckbox / Settings.CreateSlider / Settings.CreateDropdown

local ADDON, ns = ...

function ns:InitOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end   -- very old clients

	local category = Settings.RegisterVerticalLayoutCategory("Dave's Cast Bar")
	local settings = {}
	local function Check(key, name, default, tooltip)
		local s = Settings.RegisterAddOnSetting(category, ADDON .. "_" .. key, key, ns.db, Settings.VarType.Boolean, name, default)
		Settings.CreateCheckbox(category, s, tooltip)
		settings[#settings + 1] = s
	end
	local function Slider(key, name, default, min, max, step, fmt, tooltip)
		local s = Settings.RegisterAddOnSetting(category, ADDON .. "_" .. key, key, ns.db, Settings.VarType.Number, name, default)
		local options = Settings.CreateSliderOptions(min, max, step)
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmt:format(v) end)
		Settings.CreateSlider(category, s, options, tooltip)
		settings[#settings + 1] = s
	end

	Check("enabled", "Enabled", true, "Show the elemental cast bar when you cast.")
	Check("borderless", "Borderless (soft edges)", true, "On: the bar's edges fade out raggedly. Off: a thin frame in the element's colour.")
	Check("hideBlizzard", "Hide Blizzard's cast bar", true, "Hide the default player cast bar while this one is enabled.")
	Check("showName", "Show spell name", true)
	Check("showTime", "Show time left", true)
	Check("showIcon", "Show spell icon", false, "The spell's icon, just left of the bar.")
	Check("locked", "Lock bar", true, "Untick to drag and resize the bar any time (right-click it to reset). It can always be moved in Edit Mode.")
	Slider("width", "Width", 300, 80, 800, 2, "%d")
	Slider("height", "Height", 26, 10, 80, 1, "%d")
	Slider("scale", "Scale", 1.0, .5, 2, .05, "%.2f")

	local fallback = Settings.RegisterAddOnSetting(category, ADDON .. "_fallback", "fallback", ns.db, Settings.VarType.String, "Other casts", "arcane")
	Settings.CreateDropdown(category, fallback, function()
		local container = Settings.CreateControlTextContainer()
		for _, key in ipairs(ns.ELEMENT_ORDER) do container:Add(key, ns.ELEMENTS[key].label) end
		return container:GetData()
	end, "The look for casts that don't match an element and your class has no default: professions, hearthstone, mounts. Pick one for a single spell with /castbar set <element> right after casting it.")
	settings[#settings + 1] = fallback

	-- Settings write straight into ns.db; react to changes here.
	for _, s in ipairs(settings) do
		s:SetValueChangedCallback(function() ns:Apply() end)
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
