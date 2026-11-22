-- daves_map / Options.lua
-- Map Settings lived in a separate floating window in 0.7.x; in 0.8.0 all Map Settings live directly
-- inside Dave's Map's "Layers" tab beside the World Map, synced with Blizzard's Settings panel
-- (Esc > Options > AddOns) and `/dmap options`.

local ADDON, ns = ...

local syncingSettings = false

-- Sync live changes made in Dave's Map > Layers (or slash commands) into an already-open
-- Blizzard Settings window (Esc > Options > AddOns) without re-triggering value-changed callbacks.
function ns.NotifySetting(key)
	if not (key and Settings and Settings.NotifyUpdate and SettingsPanel and SettingsPanel:IsShown()) then return end
	local was = syncingSettings
	syncingSettings = true
	pcall(Settings.NotifyUpdate, ADDON .. "_" .. key)
	syncingSettings = was
end

function ns.RestoreDefaultSettings()
	local db = ns.db
	if not db then return end
	ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	db.enabled = true
	db.mapBanner = true
	db.hideCompleted = false
	db.trackMyZone = true
	db.focusQuest = true
	db.groupQuestCount = true
	db.pinScale = 1.0
	db.panelScale = 1.0
	db.background = 0.8
	db.backgroundStyle = "dark"
	if ns.SetAllOptionalLayers then
		ns.SetAllOptionalLayers(true)
	elseif type(db.layerOn) == "table" then
		wipe(db.layerOn)
	else
		db.layerOn = {}
	end
	if daves_mapCharDB then
		daves_mapCharDB.factions = ns.DefaultFactions()
		ns.factions = daves_mapCharDB.factions
	end
	local stitch = ns.OM and ns.OM:GetModule("worldmap")
	if stitch and stitch.db and not ns.OpenMapOn() then
		if stitch.db.enabled == false then
			stitch.db.enabled = true
			ns.Print("the seamless map changes after a /reload.")
		end
		stitch.db.dungeonMaps = true
		stitch.db.icons = true
		stitch.db.autoSwitch = true
		stitch.db.openZoomed = true
		if stitch.SetDungeonMaps then stitch.SetDungeonMaps(true) end
	end
	if ns.SetRefLayer then ns.SetRefLayer(nil, true) end
	if ns.OnFactionsChanged then ns.OnFactionsChanged() end
	if ns.UpdateFocus then ns.UpdateFocus(true) end
	if ns.TrackZoneQuests then ns.TrackZoneQuests() end
	if ns.RefreshGroupQuestCounts then ns.RefreshGroupQuestCounts() end
	if ns.UpdatePanel then ns.UpdatePanel() end
	if ns.ApplyPanelStyle then ns.ApplyPanelStyle() end
	if ns.RefreshStyleDialog then ns.RefreshStyleDialog() end
	if ns.RefreshControls then ns.RefreshControls() end
	if ns.Refresh then ns.Refresh() end
	for _, k in ipairs({
		"enabled", "trackMyZone", "hideCompleted", "focusQuest", "groupQuestCount", "mapBanner",
		"pinScale", "panelScale", "background", "backgroundStyle",
		"seamless", "dungeonMaps", "autoSwitch", "openZoomed",
	}) do
		ns.NotifySetting(k)
	end
end

function ns.IsOptionsOpen()
	return (WorldMapFrame ~= nil and WorldMapFrame:IsShown() and ns.db ~= nil
		and ns.db.panelTab == "layers") == true
end

function ns.RefreshOptions()
	if ns.OnLayerChanged then ns.OnLayerChanged() end
	if ns.RefreshStyleDialog then ns.RefreshStyleDialog() end
end

function ns.ToggleOptions()
	if WorldMapFrame and WorldMapFrame:IsShown() and ns.db then
		ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.db.panelTab = "layers"
		if ns.SetSearchQuiet then ns.SetSearchQuiet("") end
		if ns.SetRefLayer then ns.SetRefLayer(nil, true) end
		if ns.UpdateFocus then ns.UpdateFocus(false) end
		if ns.UpdatePanel then ns.UpdatePanel() end
		if ns.Refresh then
			ns.Refresh()
		elseif ns.OnLayerChanged then
			ns.OnLayerChanged()
		end
		return
	end
	if not InCombatLockdown() and Settings and Settings.OpenToCategory and ns.settingsCategory then
		Settings.OpenToCategory(ns.settingsCategory:GetID())
		return
	end
	ns.Print("open the world map (M) for Base & Map Settings, or try again after combat.")
end

function ns:OpenOptions()
	ns.ToggleOptions()
end

-- Register a synced page in Blizzard's Settings panel (Esc > Options > AddOns).
function ns:InitOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

	local category = Settings.RegisterVerticalLayoutCategory("Dave's Map")

	local enabled = Settings.RegisterAddOnSetting(category, ADDON .. "_enabled", "enabled", ns.db,
		Settings.VarType.Boolean, "Show the map layer", true)
	Settings.CreateCheckbox(category, enabled, "Draw tracked quest objectives, optional POI layers, and Zone/Dungeon reference markers on the world map (/dmap toggle).")
	enabled:SetValueChangedCallback(function()
		if syncingSettings then return end
		ns.RefreshOptions()
		if ns.Refresh then ns.Refresh() end
	end)

	local trackZone = Settings.RegisterAddOnSetting(category, ADDON .. "_trackMyZone", "trackMyZone", ns.db,
		Settings.VarType.Boolean, "Track only my zone's quests", true)
	Settings.CreateCheckbox(category, trackZone, "The objective tracker follows the quests in your log for the zone you're in; click the pin beside any tracked quest to keep it tracked across zones.")
	trackZone:SetValueChangedCallback(function()
		if syncingSettings then return end
		ns.RefreshOptions()
		if ns.TrackZoneQuests then ns.TrackZoneQuests() end
	end)

	local hideCompleted = Settings.RegisterAddOnSetting(category, ADDON .. "_hideCompleted", "hideCompleted", ns.db,
		Settings.VarType.Boolean, "Hide completed quests", false)
	Settings.CreateCheckbox(category, hideCompleted, "Completed quests are shown with a green checkmark on the Zone / Dungeon reference layer and lists; tick to hide them.")
	hideCompleted:SetValueChangedCallback(function()
		if syncingSettings then return end
		ns.RefreshOptions()
		if ns.Refresh then ns.Refresh() end
	end)

	local focusQuest = Settings.RegisterAddOnSetting(category, ADDON .. "_focusQuest", "focusQuest", ns.db,
		Settings.VarType.Boolean, "Click a tracked quest to focus it", true)
	Settings.CreateCheckbox(category, focusQuest, "Clicking a quest in the objective tracker, quest log, or Ready to Turn In focuses the map on that quest's objectives and turn-in.")
	focusQuest:SetValueChangedCallback(function()
		if syncingSettings then return end
		if not ns.db.focusQuest then
			if ns.SetClickFocus then ns.SetClickFocus(nil) end
			if ns.ClearTrackerFocus then ns.ClearTrackerFocus() end
		end
		ns.RefreshOptions()
		if ns.UpdateFocus then ns.UpdateFocus(true) end
		if ns.Refresh then ns.Refresh() end
	end)

	local groupQuestCount = Settings.RegisterAddOnSetting(category, ADDON .. "_groupQuestCount", "groupQuestCount", ns.db,
		Settings.VarType.Boolean, "Show party quest numbers", true)
	Settings.CreateCheckbox(category, groupQuestCount, "While in a party or raid, show a brass number badge beside quests in Dave's Map and the objective tracker (hover the number to see group member names).")
	groupQuestCount:SetValueChangedCallback(function()
		if syncingSettings then return end
		if ns.RefreshGroupQuestCounts then
			ns.RefreshGroupQuestCounts()
		else
			if ns.OnGroupQuestsChanged then ns.OnGroupQuestsChanged() end
			ns.RefreshOptions()
		end
	end)

	local mapBanner = Settings.RegisterAddOnSetting(category, ADDON .. "_mapBanner", "mapBanner", ns.db,
		Settings.VarType.Boolean, "Show zone & coordinates banner", true)
	Settings.CreateCheckbox(category, mapBanner, "Shows a compact pill at the top of the map canvas with the zone's name, difficulty-coloured level range, and cursor/player coordinates.")
	mapBanner:SetValueChangedCallback(function()
		if syncingSettings then return end
		ns.RefreshOptions()
		if ns.Refresh then ns.Refresh() end
	end)

	local pinScale = Settings.RegisterAddOnSetting(category, ADDON .. "_pinScale", "pinScale", ns.db,
		Settings.VarType.Number, "Pin size", 1.0)
	local sliderOptions = Settings.CreateSliderOptions(0.5, 2.0, 0.05)
	sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return ("%d%%"):format(value * 100 + 0.5)
	end)
	Settings.CreateSlider(category, pinScale, sliderOptions, "Size of the pins on the map.")
	pinScale:SetValueChangedCallback(function()
		if syncingSettings then return end
		ns.RefreshOptions()
		if ns.Refresh then ns.Refresh() end
	end)

	local panelScale = Settings.RegisterAddOnSetting(category, ADDON .. "_panelScale", "panelScale", ns.db,
		Settings.VarType.Number, "Window scale", 1.0)
	local pScaleOpts = Settings.CreateSliderOptions(0.5, 1.5, 0.05)
	pScaleOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return ("%d%%"):format(value * 100 + 0.5)
	end)
	Settings.CreateSlider(category, panelScale, pScaleOpts, "Scale of the Dave's Map window.")
	panelScale:SetValueChangedCallback(function()
		if syncingSettings then return end
		if ns.ApplyPanelStyle then ns.ApplyPanelStyle() end
		ns.RefreshOptions()
	end)

	local bgAlpha = Settings.RegisterAddOnSetting(category, ADDON .. "_background", "background", ns.db,
		Settings.VarType.Number, "Background", 0.8)
	local bgOpts = Settings.CreateSliderOptions(0.2, 1.0, 0.05)
	bgOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return ("%d%%"):format(value * 100 + 0.5)
	end)
	Settings.CreateSlider(category, bgAlpha, bgOpts, "Opacity of the Dave's Map window background.")
	bgAlpha:SetValueChangedCallback(function()
		if syncingSettings then return end
		if ns.ApplyPanelStyle then ns.ApplyPanelStyle() end
		ns.RefreshOptions()
	end)

	if Settings.CreateDropdown and Settings.CreateControlTextContainer then
		local bgStyle = Settings.RegisterAddOnSetting(category, ADDON .. "_backgroundStyle", "backgroundStyle", ns.db,
			Settings.VarType.String, "Background style", "dark")
		local function GetBgStyleOptions()
			local container = Settings.CreateControlTextContainer()
			for _, s in ipairs(ns.BACKGROUND_STYLES) do
				container:Add(s.key, s.name)
			end
			return container:GetData()
		end
		Settings.CreateDropdown(category, bgStyle, GetBgStyleOptions, "Which of Blizzard's standard backgrounds shows behind Dave's Map (same styles as Dave's Sack).")
		bgStyle:SetValueChangedCallback(function()
			if syncingSettings then return end
			if ns.ApplyPanelStyle then ns.ApplyPanelStyle() end
			ns.RefreshOptions()
		end)
	end

	local stitch = ns.OM and ns.OM:GetModule("worldmap")
	if stitch and stitch.db and not ns.OpenMapOn() then
		local seamless = Settings.RegisterAddOnSetting(category, ADDON .. "_seamless", "enabled", stitch.db,
			Settings.VarType.Boolean, "Seamless world map", true)
		Settings.CreateCheckbox(category, seamless, "Every zone stitched into one map (OpenMap's): the wheel zooms from the whole world to street level. Takes a /reload.")
		seamless:SetValueChangedCallback(function()
			if syncingSettings then return end
			ns.RefreshOptions()
			ns.Print("the seamless map changes after a /reload.")
		end)

		local dungeons = Settings.RegisterAddOnSetting(category, ADDON .. "_dungeonMaps", "dungeonMaps", stitch.db,
			Settings.VarType.Boolean, "Dungeon & raid maps", true)
		Settings.CreateCheckbox(category, dungeons, "OpenMap's dungeon and raid maps (floors, boss pins and entrance portals).")
		dungeons:SetValueChangedCallback(function(_, v)
			if syncingSettings then return end
			stitch.db.icons = v
			if stitch.SetDungeonMaps then stitch.SetDungeonMaps(v) end
			ns.RefreshOptions()
			if ns.Refresh then ns.Refresh() end
		end)

		local follow = Settings.RegisterAddOnSetting(category, ADDON .. "_autoSwitch", "autoSwitch", stitch.db,
			Settings.VarType.Boolean, "Load the zone in view", true)
		Settings.CreateCheckbox(category, follow, "Once the seamless map stops moving, the zone you're looking at loads underneath.")
		follow:SetValueChangedCallback(function()
			if syncingSettings then return end
			ns.RefreshOptions()
		end)

		local zoomed = Settings.RegisterAddOnSetting(category, ADDON .. "_openZoomed", "openZoomed", stitch.db,
			Settings.VarType.Boolean, "Open zoomed in on me", true)
		Settings.CreateCheckbox(category, zoomed, "The map opens on you, zoomed in as far as it goes. Off: your whole zone.")
		zoomed:SetValueChangedCallback(function()
			if syncingSettings then return end
			ns.RefreshOptions()
		end)
	end

	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end

---------------------------------------------------------------------------
-- Window Style Dialog (same HUD Edit Mode controls & look as Dave's Sack)
---------------------------------------------------------------------------
do
	local STYLE_W, STYLE_H = 288, 354
	local PAD_X, INNER_W = 24, 240
	local opt, controls

	local function TryTemplate(kind, name, parent, template)
		local ok, f = pcall(CreateFrame, kind, name, parent, template)
		return ok and f or nil
	end

	local function Label(parent, text, font)
		local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
		fs:SetText(text)
		return fs
	end

	local function AddTip(region, text)
		if not text then return end
		region:HookScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(text, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		region:HookScript("OnLeave", GameTooltip_Hide)
	end

	local function Header(parent, text, x, y, w)
		local fs = Label(parent, text, "GameFontNormal")
		fs:SetPoint("TOPLEFT", x, y)
		local line = parent:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(1, 1, 1, 0.14)
		line:SetPoint("TOPLEFT", x, y - 16)
		line:SetSize(w, 1)
	end

	local function StyleSlider(parent, x, y, width, label, minV, maxV, step, fmt, get, set, tip)
		local f = CreateFrame("Frame", nil, parent)
		f:SetSize(width, 40)
		f:SetPoint("TOPLEFT", x, y)
		f.label = Label(f, label, "GameFontHighlight")
		f.label:SetPoint("TOPLEFT")
		f.value = Label(f, "", "GameFontNormal")
		f.value:SetPoint("TOPRIGHT")

		local s = CreateFrame("Slider", nil, f)
		f.slider = s
		s:SetOrientation("HORIZONTAL")
		s:SetHeight(20)
		s:SetPoint("BOTTOMLEFT")
		s:SetPoint("BOTTOMRIGHT")
		s:SetMinMaxValues(minV, maxV)
		s:SetValueStep(step)
		if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Minimal_SliderBar_Button") then
			local th = s:CreateTexture(nil, "OVERLAY")
			th:SetAtlas("Minimal_SliderBar_Button", true)
			s:SetThumbTexture(th)
		else
			s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
			local th = s:GetThumbTexture()
			if th then th:SetSize(20, 20) end
		end
		local edge = s:CreateTexture(nil, "BACKGROUND", nil, -1)
		edge:SetColorTexture(0.35, 0.35, 0.38, 1)
		edge:SetPoint("LEFT", -1, 0)
		edge:SetPoint("RIGHT", 1, 0)
		edge:SetHeight(8)
		local bg = s:CreateTexture(nil, "BACKGROUND")
		bg:SetColorTexture(0, 0, 0, 0.85)
		bg:SetPoint("LEFT")
		bg:SetPoint("RIGHT")
		bg:SetHeight(6)

		s:EnableMouseWheel(true)
		s:SetScript("OnMouseWheel", function(self, d)
			local nextV = math.max(minV, math.min(maxV, self:GetValue() + d * step))
			self:SetValue(nextV)
		end)
		s:SetScript("OnValueChanged", function(_, v)
			v = math.max(minV, math.min(maxV, math.floor(v / step + 0.5) * step))
			f.value:SetText(fmt(v))
			if not f.syncing and math.abs(v - (get() or minV)) > 0.0001 then
				set(v)
			end
		end)
		AddTip(s, tip)

		function f:Refresh()
			self.syncing = true
			local v = math.max(minV, math.min(maxV, get() or minV))
			s:SetValue(v)
			self.value:SetText(fmt(v))
			self.syncing = false
		end
		controls[#controls + 1] = f
		return f
	end

	local function StyleDropdown(parent, x, y, width, label, items, get, set, tip)
		local f = CreateFrame("Frame", nil, parent)
		f:SetSize(width, 46)
		f:SetPoint("TOPLEFT", x, y)
		f.label = Label(f, label, "GameFontHighlight")
		f.label:SetPoint("TOPLEFT")
		local function Current()
			local cur = get()
			for _, it in ipairs(items) do
				if it.key == cur then return it end
			end
			return items[1]
		end
		local dd = TryTemplate("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		if dd and dd.SetupMenu then
			dd:SetPoint("BOTTOMLEFT", 0, 0)
			dd:SetWidth(width)
			local function Show()
				if dd.SetDefaultText then dd:SetDefaultText(Current().name) end
			end
			dd:SetupMenu(function(_, root)
				for _, it in ipairs(items) do
					root:CreateRadio(it.name, function() return get() == it.key end, function()
						set(it.key)
						Show()
					end)
				end
			end)
			function f:Refresh()
				Show()
				dd:GenerateMenu()
			end
			Show()
			AddTip(dd, tip)
		else
			local b = TryTemplate("Button", nil, f, "UIPanelButtonTemplate") or CreateFrame("Button", nil, f)
			b:SetPoint("BOTTOMLEFT", 0, 0)
			b:SetSize(width, 22)
			if not b.SetText then
				b.text = Label(b, "", "GameFontHighlight")
				b.text:SetPoint("CENTER")
				b.SetText = function(_, t) b.text:SetText(t) end
			end
			b:SetScript("OnClick", function()
				local cur = Current()
				for i, it in ipairs(items) do
					if it == cur then
						set(items[(i % #items) + 1].key)
						break
					end
				end
				b:SetText(Current().name)
			end)
			function f:Refresh() b:SetText(Current().name) end
			AddTip(b, tip)
		end
		AddTip(f.label, tip)
		controls[#controls + 1] = f
		return f
	end

	local function PanelButton(parent, text, width)
		local b = TryTemplate("Button", nil, parent, "UIPanelButtonTemplate")
		if not b then
			b = CreateFrame("Button", nil, parent)
			local t = b:CreateTexture(nil, "BACKGROUND")
			t:SetColorTexture(0.45, 0.08, 0.06, 1)
			t:SetAllPoints()
			b:SetNormalFontObject("GameFontNormal")
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetColorTexture(1, 1, 1, 0.08)
			hl:SetAllPoints()
		end
		b:SetText(text)
		b:SetSize(width, 22)
		return b
	end

	local function RefreshAll()
		if not controls then return end
		for _, c in ipairs(controls) do c:Refresh() end
	end

	local function PlaceStyleDialog()
		if not opt then return end
		opt:ClearAllPoints()
		local p = ns.PanelFrame and ns.PanelFrame()
		if p and p:IsShown() then
			local pr, pl, pt = p:GetRight(), p:GetLeft(), p:GetTop()
			local ps = p:GetEffectiveScale()
			local os = opt:GetEffectiveScale()
			local sw = UIParent:GetWidth() * UIParent:GetEffectiveScale()
			local sh = UIParent:GetHeight() * UIParent:GetEffectiveScale()
			if pr and pl and pt and ps and os and os > 0 then
				-- Anchor to UIParent (never to `p`) so dragging the Window scale slider
				-- never shifts this dialog underneath the cursor.
				local topY = math.min(-16, (pt * ps - sh) / os)
				if (pr * ps + (STYLE_W + 14) * os) <= sw then
					opt:SetPoint("TOPLEFT", UIParent, "TOPLEFT", (pr * ps) / os + 6, topY)
					return
				elseif (pl * ps - (STYLE_W + 14) * os) >= 0 then
					opt:SetPoint("TOPLEFT", UIParent, "TOPLEFT", (pl * ps) / os - STYLE_W - 6, topY)
					return
				end
			end
		end
		opt:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end

	local function BuildStyleDialog()
		controls = {}
		opt = CreateFrame("Frame", "DavesMapStyleOptions", UIParent)
		opt:SetSize(STYLE_W, STYLE_H)
		opt:SetFrameStrata("DIALOG")
		opt:SetClampedToScreen(true)
		opt:EnableMouse(true)
		opt:SetMovable(true)
		opt:RegisterForDrag("LeftButton")
		if opt.SetDontSavePosition then opt:SetDontSavePosition(true) end
		opt:SetScript("OnDragStart", opt.StartMoving)
		opt:SetScript("OnDragStop", opt.StopMovingOrSizing)
		opt:Hide()
		tinsert(UISpecialFrames, "DavesMapStyleOptions")

		local border = TryTemplate("Frame", nil, opt, "DialogBorderTranslucentTemplate")
		if border then
			border:SetAllPoints()
		else
			border = CreateFrame("Frame", nil, opt, BackdropTemplateMixin and "BackdropTemplate" or nil)
			border:SetAllPoints()
			border:SetFrameLevel(opt:GetFrameLevel())
			border:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8X8",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 },
			})
			border:SetBackdropColor(0, 0, 0, 0.8)
		end
		ns.styleDialogBorder = border

		local title = Label(opt, "Window Style", "GameFontHighlightLarge")
		title:SetPoint("TOP", 0, -15)

		local close = TryTemplate("Button", nil, opt, "UIPanelCloseButton")
		if close then
			close:SetPoint("TOPRIGHT")
		else
			close = CreateFrame("Button", nil, opt)
			close:SetSize(32, 32)
			close:SetPoint("TOPRIGHT", 2, 2)
			close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
			close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
			close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
		end
		close:SetFrameLevel(opt:GetFrameLevel() + 5)
		close:SetScript("OnClick", function() opt:Hide() end)

		local db = ns.db
		Header(opt, "Size & Pins", PAD_X, -48, INNER_W)
		StyleSlider(opt, PAD_X, -70, INNER_W, "Window scale", 0.5, 1.5, 0.05,
			function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
			function() return db.panelScale or 1.0 end,
			function(v)
				db.panelScale = v
				if ns.NotifySetting then ns.NotifySetting("panelScale") end
				if ns.ApplyPanelStyle then ns.ApplyPanelStyle() end
				if ns.OnLayerChanged then ns.OnLayerChanged() end
			end,
			"Scale of the Dave's Map window (50% to 150%).")

		StyleSlider(opt, PAD_X, -118, INNER_W, "Pin size", 0.5, 2.0, 0.05,
			function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
			function() return db.pinScale or 1.0 end,
			function(v)
				db.pinScale = v
				if ns.NotifySetting then ns.NotifySetting("pinScale") end
				if ns.Refresh then ns.Refresh() end
			end,
			"Size of the pins on the world map (50% to 200%).")

		Header(opt, "Look", PAD_X, -168, INNER_W)
		StyleSlider(opt, PAD_X, -190, INNER_W, "Background", 0.2, 1.0, 0.05,
			function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
			function() return db.background or 0.8 end,
			function(v)
				db.background = v
				if ns.NotifySetting then ns.NotifySetting("background") end
				if ns.ApplyPanelStyle then ns.ApplyPanelStyle() end
				if ns.OnLayerChanged then ns.OnLayerChanged() end
			end,
			"Opacity / darkness of the window background (20% to 100%). This dialog follows the same setting.")

		StyleDropdown(opt, PAD_X, -236, INNER_W, "Background style", ns.BACKGROUND_STYLES,
			function() return db.backgroundStyle or "dark" end,
			function(key)
				db.backgroundStyle = key
				if ns.NotifySetting then ns.NotifySetting("backgroundStyle") end
				if ns.ApplyPanelStyle then ns.ApplyPanelStyle() end
				if ns.OnLayerChanged then ns.OnLayerChanged() end
			end,
			"Which of Blizzard's standard backgrounds shows behind Dave's Map (same styles as Dave's Sack).")

		local dockBtn = PanelButton(opt, "Dock to Map (Reset Size)", INNER_W)
		dockBtn:SetPoint("BOTTOMLEFT", PAD_X, 46)
		dockBtn:SetScript("OnClick", function()
			ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			if ns.ResetPanelPosition then ns.ResetPanelPosition() end
		end)

		local resetBtn = PanelButton(opt, "Reset Look", 114)
		resetBtn:SetPoint("BOTTOMLEFT", PAD_X, 18)
		resetBtn:SetScript("OnClick", function()
			ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			db.panelScale = 1.0
			db.background = 0.8
			db.backgroundStyle = "dark"
			db.pinScale = 1.0
			for _, k in ipairs({ "panelScale", "background", "backgroundStyle", "pinScale" }) do
				ns.NotifySetting(k)
			end
			if ns.ApplyPanelStyle then ns.ApplyPanelStyle() end
			RefreshAll()
			if ns.Refresh then ns.Refresh() end
		end)

		local allBtn = PanelButton(opt, "All Settings", 114)
		allBtn:SetPoint("BOTTOMRIGHT", -PAD_X, 18)
		allBtn:SetScript("OnClick", function()
			ns.ToggleOptions()
		end)

		opt:SetScript("OnShow", function()
			ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			if ns.ApplyPanelStyle then ns.ApplyPanelStyle() end
			RefreshAll()
			if ns.SyncStyleButton then ns.SyncStyleButton() end
		end)
		opt:SetScript("OnHide", function()
			if ns.SyncStyleButton then ns.SyncStyleButton() end
		end)
	end

	function ns.IsStyleDialogOpen()
		return (opt ~= nil and opt:IsShown()) == true
	end

	function ns.RefreshStyleDialog()
		if opt and opt:IsShown() then
			RefreshAll()
		end
	end

	function ns.HideStyleDialog()
		if opt and opt:IsShown() then opt:Hide() end
	end

	function ns.ToggleStyleDialog()
		if not ns.db then return end
		if not opt then BuildStyleDialog() end
		if opt:IsShown() then
			ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
			opt:Hide()
		else
			PlaceStyleDialog()
			opt:Show()
		end
	end
end
