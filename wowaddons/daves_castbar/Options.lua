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
	Check("hideBlizzard", "Hide Blizzard's cast bar", true, "Hide the default player cast bar while this one is enabled.")
	Check("showName", "Show spell name", true)
	Check("showTime", "Show time left", true)
	Check("showIcon", "Show spell icon", false, "The spell's icon, just left of the bar.")
	Check("locked", "Lock bar", true, "Untick to drag and resize the bar any time (right-click it to reset). It can always be moved in Edit Mode.")
	Slider("width", "Width", 300, ns.MIN_W, ns.MAX_W, 1, "%d")
	Slider("height", "Height", 26, ns.MIN_H, ns.MAX_H, 1, "%d")
	Slider("scale", "Scale", 1.0, .5, 2, .05, "%.2f")
	Slider("textScale", "Text size", 1.0, .6, 2, .05, "%.2f")   -- relative to the default bar size; it scales with the bar
	Check("textOutline", "Outline text", true, "A dark outline around the spell name and time, so they stand out against every element.")

	local function Placement(key, name, default, tooltip)
		local s = Settings.RegisterAddOnSetting(category, ADDON .. "_" .. key, key, ns.db, Settings.VarType.String, name, default)
		Settings.CreateDropdown(category, s, function()
			local container = Settings.CreateControlTextContainer()
			container:Add("left", "Left")
			container:Add("center", "Center")
			container:Add("right", "Right")
			return container:GetData()
		end, tooltip)
		settings[#settings + 1] = s
	end
	local style = Settings.RegisterAddOnSetting(category, ADDON .. "_style", "style", ns.db, Settings.VarType.String, "Style", "framed")
	Settings.CreateDropdown(category, style, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("framed", "Framed")
		container:Add("borderless", "Borderless")
		return container:GetData()
	end, "Framed draws a thin line around the bar in the look's colour; borderless leaves it out. Both have clean edges.")
	settings[#settings + 1] = style
	local function Choice(key, name, default, items, tooltip)
		local s = Settings.RegisterAddOnSetting(category, ADDON .. "_" .. key, key, ns.db, Settings.VarType.String, name, default)
		Settings.CreateDropdown(category, s, function()
			local container = Settings.CreateControlTextContainer()
			for _, it in ipairs(items) do container:Add(it[1], it[2]) end
			return container:GetData()
		end, tooltip)
		settings[#settings + 1] = s
	end
	Choice("corners", "Corners", "soft", { { "square", "Square" }, { "soft", "Soft" }, { "rounded", "Rounded" } },
		"Square, soft (slightly rounded) or rounded corners. Every look and the frame follow them.")
	Choice("depth", "Depth", "flat", { { "flat", "Flat" }, { "bevel", "Bevel" } },
		"Flat, or a bevel: light along the top edge, shade along the bottom and a shadow just inside the frame, so the bar looks set into it.")

	Placement("namePos", "Spell name position", "left", "Where the spell name sits on the bar.")
	Placement("timePos", "Time left position", "right", "Where the time left sits on the bar. The time and the spell name each keep their own part of the bar; with both set to center, the time moves to the right.")

	local fallback = Settings.RegisterAddOnSetting(category, ADDON .. "_fallback", "fallback", ns.db, Settings.VarType.String, "Other casts", "plain")
	Settings.CreateDropdown(category, fallback, function()
		local container = Settings.CreateControlTextContainer()
		for _, key in ipairs(ns.ELEMENT_ORDER) do container:Add(key, ns.ELEMENTS[key].label) end
		return container:GetData()
	end, "The look for casts that don't match an element and your class has no default: other professions, hearthstone, mounts. Plain is Blizzard's own cast bar. Pick one for a single spell with /castbar set <element> right after casting it.")
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
