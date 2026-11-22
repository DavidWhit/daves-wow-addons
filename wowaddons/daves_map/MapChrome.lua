-- daves_map / MapChrome.lua
-- Removes Blizzard's default Quest Log side panel (`QuestMapFrame`), `SidePanelToggle`, portrait border chrome,
-- and canvas tracking buttons cleanly without tainting `WorldMapFrame` or `UIPanelWindows` in combat.
-- Wraps `WorldMapFrame`'s map canvas in matching HUD Edit Mode translucent dialog chrome (`DialogBorderTranslucentTemplate`),
-- redirects `TOGGLEQUESTLOG` (`L`) to open the unified map cleanly, and exposes Blizzard's Forever map tracking
-- filters (`questPOI`, `showQuestLevel`, `showQuestDifficultyColor`, `showDungeonEntrancesOnMap`, `trivialQuests`,
-- `contentTrackingFilter`) so they live inside Dave's Map Settings.

local _, ns = ...

local state = {
	initialized = false,
	questMapSuppressed = false,
	hiddenFrames = {},
	keyOwner = nil,
	questLogKeys = {},
	mapChrome = nil,
	mapBorder = nil,
	mapOverlay = nil,
	mapTitle = nil,
	canvasRim = nil,
	navHooked = false,
	microHooked = false,
	detailsHooked = false,
	pendingKeybindSync = false,
	pendingProviderRefresh = false,
	hideScheduled = false,
}

---------------------------------------------------------------------------
-- Blizzard Map Tracking & Filter Options (moved into Dave's Map Settings)
---------------------------------------------------------------------------
ns.BLIZZ_MAP_FILTERS = {
	{
		key = "blizz_questPOI",
		cvar = "questPOI",
		default = true,
		label = "Show Blizzard quest objectives",
		tip = "Toggle Blizzard's built-in quest objective areas and pins on the world map (questPOI).",
	},
	{
		key = "blizz_showQuestLevel",
		cvar = "showQuestLevel",
		default = true,
		label = "Show quest levels on map",
		tip = "Display quest levels on Blizzard's quest labels and tracker (showQuestLevel).",
	},
	{
		key = "blizz_showQuestDifficultyColor",
		cvar = "showQuestDifficultyColor",
		default = true,
		label = "Color quests by difficulty",
		tip = "Color quest titles by difficulty relative to your level (showQuestDifficultyColor).",
	},
	{
		key = "blizz_showDungeonEntrances",
		cvar = "showDungeonEntrancesOnMap",
		default = true,
		label = "Show Blizzard dungeon entrances",
		tip = "Show Blizzard's built-in dungeon and raid entrance icons on the map (showDungeonEntrancesOnMap).",
	},
	{
		key = "blizz_trivialQuests",
		minimapFilter = Enum and Enum.MinimapTrackingFilter and Enum.MinimapTrackingFilter.TrivialQuests or nil,
		default = false,
		label = "Track low-level quests",
		tip = "Show low-level (grey) quests on the minimap and world map.",
	},
	{
		key = "blizz_contentTracking",
		cvar = "contentTrackingFilter",
		default = true,
		label = "Show tracked content pins",
		tip = "Show tracked items, achievements, and content pins on the world map (contentTrackingFilter).",
	},
}

local FILTER_BY_KEY = {}
for _, def in ipairs(ns.BLIZZ_MAP_FILTERS) do
	FILTER_BY_KEY[def.key] = def
end

function ns.GetBlizzMapFilter(key)
	local def = FILTER_BY_KEY[key]
	if not def then return false end
	if def.cvar then
		return GetCVarBool and (GetCVarBool(def.cvar) == true) or false
	end
	if def.minimapFilter and C_Minimap and C_Minimap.IsFilteredOut then
		return not C_Minimap.IsFilteredOut(def.minimapFilter)
	end
	return false
end

function ns.SetBlizzMapFilter(key, on)
	local def = FILTER_BY_KEY[key]
	if not def then return false end
	local val = on == true
	if InCombatLockdown() then
		ns.Print("can't change Blizzard map filters during combat.")
		return false
	end
	if def.cvar then
		if C_CVar and C_CVar.SetCVar then
			C_CVar.SetCVar(def.cvar, val and "1" or "0")
		end
	elseif def.minimapFilter then
		if MinimapUtil and MinimapUtil.SetTrackingFilterByFilterID then
			pcall(MinimapUtil.SetTrackingFilterByFilterID, def.minimapFilter, val)
		elseif C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingFilter and C_Minimap.SetTracking then
			for i = 1, C_Minimap.GetNumTrackingTypes() do
				local tf = C_Minimap.GetTrackingFilter(i)
				if tf and tf.filterID == def.minimapFilter then
					C_Minimap.SetTracking(i, val)
					break
				end
			end
		end
	end
	if WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.RefreshAllDataProviders then
		if InCombatLockdown() then
			state.pendingProviderRefresh = true
		else
			WorldMapFrame:RefreshAllDataProviders()
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Persistent Visual Hiding & Blizzard QuestMapFrame Suppression
---------------------------------------------------------------------------
local function KeepHidden(frame)
	if not frame then return end
	if not state.hiddenFrames[frame] then
		state.hiddenFrames[frame] = true
		if frame.HookScript and frame.HasScript and frame:HasScript("OnShow") then
			frame:HookScript("OnShow", function(self)
				if not (self:IsProtected() and InCombatLockdown()) then
					self:Hide()
				end
			end)
		end
	end
	if frame.SetAlpha and not frame.HookScript then
		frame:SetAlpha(0)
	end
	if not (frame:IsProtected() and InCombatLockdown()) then
		frame:Hide()
	end
end

local function DisableRegionMouse(frame)
	if not frame then return end
	if frame.EnableMouse and not (frame:IsProtected() and InCombatLockdown()) then
		frame:EnableMouse(false)
	end
end

function ns.IsQuestMapSuppressed()
	return state.questMapSuppressed == true
end

local function SilenceQuestMapFrame()
	if not QuestMapFrame then return end
	QuestMapFrame:SetAlpha(0)
	if not (QuestMapFrame:IsProtected() and InCombatLockdown()) then
		QuestMapFrame:SetScale(0.001)
		QuestMapFrame:EnableMouse(false)
	end
	DisableRegionMouse(QuestMapFrame.QuestsTab)
	DisableRegionMouse(QuestMapFrame.EventsTab)
	DisableRegionMouse(QuestMapFrame.MapLegendTab)
	DisableRegionMouse(QuestMapFrame.DetailsFrame)
	DisableRegionMouse(QuestMapFrame.QuestsFrame)
	if QuestFrame_HideQuestPortrait then
		pcall(QuestFrame_HideQuestPortrait)
	end
	-- Defer Hide() one tick so Focus.lua finishes reading DetailsFrame.questMapID synchronously,
	-- while keeping QuestMapFrame:IsShown() false so M closes the map on the very first keypress
	-- without ever touching WorldMapFrame:SetWidth or SetUIPanelAttribute.
	if QuestMapFrame:IsShown() and not state.hideScheduled then
		state.hideScheduled = true
		C_Timer.After(0, function()
			state.hideScheduled = false
			if QuestMapFrame and QuestMapFrame:IsShown() and not (QuestMapFrame:IsProtected() and InCombatLockdown()) then
				QuestMapFrame:Hide()
			end
		end)
	end
end

local function SuppressQuestMapFrame()
	if not QuestMapFrame then return end
	SilenceQuestMapFrame()
	if not state.questMapSuppressed then
		state.questMapSuppressed = true
		QuestMapFrame:HookScript("OnShow", function()
			SilenceQuestMapFrame()
		end)
	end
	if not state.detailsHooked and QuestMapFrame_ShowQuestDetails then
		state.detailsHooked = true
		hooksecurefunc("QuestMapFrame_ShowQuestDetails", function()
			SilenceQuestMapFrame()
		end)
	end
end

---------------------------------------------------------------------------
-- `TOGGLEQUESTLOG` (L) Keybind & Micro Button Integration (Taint-Free)
---------------------------------------------------------------------------
local function SyncQuestLogKeybind()
	if InCombatLockdown() then
		state.pendingKeybindSync = true
		return
	end
	state.pendingKeybindSync = false
	if not (SetOverrideBinding and ClearOverrideBindings and GetBindingKey) then return end
	if not state.keyOwner then
		state.keyOwner = CreateFrame("Frame")
	end
	ClearOverrideBindings(state.keyOwner)
	wipe(state.questLogKeys)
	for i = 1, 2 do
		local key = select(i, GetBindingKey("TOGGLEQUESTLOG"))
		if type(key) == "string" and key ~= "" then
			state.questLogKeys[#state.questLogKeys + 1] = key
			SetOverrideBinding(state.keyOwner, false, key, "TOGGLEWORLDMAP")
		end
	end
end
ns.SyncQuestLogKeybind = SyncQuestLogKeybind

local function IsBindingChordDown(binding)
	local needShift, needCtrl, needAlt = false, false, false
	local rest = binding
	while true do
		local mod, tail = rest:match("^(%u+)%-(.+)$")
		if mod == "SHIFT" then
			needShift = true
			rest = tail
		elseif mod == "CTRL" then
			needCtrl = true
			rest = tail
		elseif mod == "ALT" then
			needAlt = true
			rest = tail
		else
			break
		end
	end
	if needShift and not (IsShiftKeyDown and IsShiftKeyDown()) then return false end
	if needCtrl and not (IsControlKeyDown and IsControlKeyDown()) then return false end
	if needAlt and not (IsAltKeyDown and IsAltKeyDown()) then return false end
	local ok, down = pcall(IsKeyDown, rest)
	return ok and down and not issecretvalue(down) or false
end

function ns.WasQuestLogKeyPressed()
	if not (IsKeyDown and state.questLogKeys) then return false end
	for _, key in ipairs(state.questLogKeys) do
		if IsBindingChordDown(key) then
			return true
		end
	end
	return false
end

local bindEvents = CreateFrame("Frame")
bindEvents:RegisterEvent("PLAYER_LOGIN")
bindEvents:RegisterEvent("UPDATE_BINDINGS")
bindEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
bindEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_ENABLED" then
		if state.pendingKeybindSync then SyncQuestLogKeybind() end
		if state.pendingProviderRefresh then
			state.pendingProviderRefresh = false
			if WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.RefreshAllDataProviders then
				WorldMapFrame:RefreshAllDataProviders()
			end
		end
		return
	end
	SyncQuestLogKeybind()
end)

---------------------------------------------------------------------------
-- Unified HUD Edit Mode World Map Chrome (`DavesMapWorldChrome`)
---------------------------------------------------------------------------
local function TryTemplate(kind, name, parent, template)
	local ok, f = pcall(CreateFrame, kind, name, parent, template)
	return ok and f or nil
end

local function StripNavBarChrome(navBar)
	if not navBar then return end
	for _, key in ipairs({
		"InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderBottom",
		"InsetBorderLeft", "InsetBorderRight", "overlay",
	}) do
		if navBar[key] then KeepHidden(navBar[key]) end
	end
	local regions = { navBar:GetRegions() }
	for _, r in ipairs(regions) do
		if r and r.GetObjectType and r:GetObjectType() == "Texture" then
			r:SetAlpha(0)
		end
	end
end

local function LayoutNavBarAndClose()
	if not WorldMapFrame then return end
	local nav = WorldMapFrame.NavBar
	local spacer = WorldMapFrame.TitleCanvasSpacerFrame
	if nav and spacer then
		StripNavBarChrome(nav)
		nav:ClearAllPoints()
		nav:SetPoint("TOPLEFT", spacer, "TOPLEFT", 6, -28)
		nav:SetPoint("BOTTOMRIGHT", spacer, "BOTTOMRIGHT", -6, 6)
	end
	local close = WorldMapFrame.BorderFrame and WorldMapFrame.BorderFrame.CloseButton
	if close and state.mapChrome then
		close:ClearAllPoints()
		close:SetPoint("TOPRIGHT", state.mapChrome, "TOPRIGHT", -2, -2)
		if state.mapOverlay and close.SetFrameLevel then
			close:SetFrameLevel(math.max(close:GetFrameLevel() or 1, (state.mapOverlay:GetFrameLevel() or 1) + 2))
		end
	end
end

local function SyncMapChromeStrata()
	if not (WorldMapFrame and state.mapChrome) then return end
	local mapStrata = WorldMapFrame:GetFrameStrata() or "MEDIUM"
	local scLevel = (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer:GetFrameLevel()) or 2
	state.mapChrome:SetFrameStrata(mapStrata)
	state.mapChrome:SetFrameLevel(math.max(0, scLevel - 1))
	if state.mapBorder then
		state.mapBorder:SetFrameLevel(state.mapChrome:GetFrameLevel())
	end
	if state.mapOverlay and WorldMapFrame.BorderFrame then
		state.mapOverlay:SetFrameStrata(WorldMapFrame.BorderFrame:GetFrameStrata() or "HIGH")
		state.mapOverlay:SetFrameLevel((WorldMapFrame.BorderFrame:GetFrameLevel() or 10) + 1)
	end
end

local function UpdateMapTitle()
	if not (state.mapTitle and WorldMapFrame) then return end
	local mapID = WorldMapFrame:GetMapID()
	local info = (mapID and C_Map and C_Map.GetMapInfo) and C_Map.GetMapInfo(mapID) or nil
	local name = info and info.name
	if type(name) == "string" and not issecretvalue(name) and name ~= "" then
		state.mapTitle:SetText("World Map - " .. name)
	else
		state.mapTitle:SetText("World Map")
	end
end
ns.UpdateMapChromeTitle = UpdateMapTitle

function ns.WorldMapChrome()
	return state.mapChrome
end

function ns.ApplyMapChromeStyle(alpha, style)
	if not (state.mapBorder and ns.ApplyDialogBackground) then return end
	ns.ApplyDialogBackground(state.mapBorder, alpha, style)
end

local function HideDefaultWorldMapChrome()
	if not WorldMapFrame then return end
	local bf = WorldMapFrame.BorderFrame
	if bf then
		if bf.EnableMouseWheel and not (bf:IsProtected() and InCombatLockdown()) then
			bf:EnableMouseWheel(false)
		end
		KeepHidden(bf.NineSlice)
		KeepHidden(bf.PortraitContainer)
		KeepHidden(bf.Bg)
		KeepHidden(bf.TopTileStreaks)
		KeepHidden(bf.InsetBorderTop)
		KeepHidden(bf.TitleContainer)
		KeepHidden(bf.Tutorial)
		KeepHidden(bf.MaximizeMinimizeFrame)
	end
	KeepHidden(WorldMapFrame.SidePanelToggle)
	KeepHidden(WorldMapFrame.WorldMapTrackingOptionsButton)
	KeepHidden(WorldMapFrame.WorldMapTrackingPinButton)
end

function ns.InitMapChrome()
	if not WorldMapFrame then return end
	SuppressQuestMapFrame()
	HideDefaultWorldMapChrome()

	if state.initialized then
		SyncMapChromeStrata()
		LayoutNavBarAndClose()
		UpdateMapTitle()
		return
	end
	state.initialized = true

	-- Unified HUD Edit Mode translucent dialog frame tightly framing the World Map canvas + header.
	local spacer = WorldMapFrame.TitleCanvasSpacerFrame
	local sc = WorldMapFrame.ScrollContainer
	local chrome = CreateFrame("Frame", "DavesMapWorldChrome", WorldMapFrame)
	state.mapChrome = chrome
	chrome:EnableMouse(false)
	chrome:SetPoint("TOPLEFT", spacer, "TOPLEFT", -10, 6)
	chrome:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 10, -10)

	local border = TryTemplate("Frame", nil, chrome, "DialogBorderTranslucentTemplate")
	if border then
		border:SetAllPoints()
	else
		border = CreateFrame("Frame", nil, chrome, BackdropTemplateMixin and "BackdropTemplate" or nil)
		border:SetAllPoints()
		border:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		border:SetBackdropColor(0, 0, 0, 0.8)
	end
	state.mapBorder = border

	-- Non-interactive overlay above the canvas for the crisp header title and canvas hairline border.
	local overlay = CreateFrame("Frame", nil, WorldMapFrame)
	state.mapOverlay = overlay
	overlay:EnableMouse(false)
	overlay:SetAllPoints(chrome)

	local title = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOP", overlay, "TOP", 0, -12)
	title:SetText("World Map")
	state.mapTitle = title

	local rim = CreateFrame("Frame", nil, overlay, BackdropTemplateMixin and "BackdropTemplate" or nil)
	state.canvasRim = rim
	rim:EnableMouse(false)
	rim:SetPoint("TOPLEFT", sc, "TOPLEFT", -1, 1)
	rim:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 1, -1)
	if rim.SetBackdrop then
		rim:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		rim:SetBackdropBorderColor(0.45, 0.36, 0.20, 0.72)
	end

	SyncMapChromeStrata()
	LayoutNavBarAndClose()
	UpdateMapTitle()

	if not state.navHooked then
		state.navHooked = true
		hooksecurefunc(WorldMapFrame, "Minimize", function()
			HideDefaultWorldMapChrome()
			LayoutNavBarAndClose()
			SyncMapChromeStrata()
		end)
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
			UpdateMapTitle()
		end)
		WorldMapFrame:HookScript("OnShow", function()
			SuppressQuestMapFrame()
			HideDefaultWorldMapChrome()
			SyncMapChromeStrata()
			LayoutNavBarAndClose()
			UpdateMapTitle()
			if ns.WasQuestLogKeyPressed() and ns.OpenTrackerTab then
				ns.OpenTrackerTab(nil, nil, true)
			end
		end)
	end

	if not state.microHooked and QuestLogMicroButton and QuestLogMicroButton.HookScript then
		state.microHooked = true
		QuestLogMicroButton:HookScript("OnClick", function()
			if WorldMapFrame and WorldMapFrame:IsShown() and ns.OpenTrackerTab then
				ns.OpenTrackerTab(nil, nil, true)
			end
		end)
	end

	if ns.ApplyPanelStyle then
		ns.ApplyPanelStyle()
	end
end
