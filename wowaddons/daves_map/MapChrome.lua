-- daves_map / MapChrome.lua
-- Removes Blizzard's default Quest Log side panel (`QuestMapFrame`), `SidePanelToggle`, portrait border chrome,
-- bulky `WorldMapFrame.NavBar`, and canvas tracking buttons cleanly without tainting `WorldMapFrame` or
-- `UIPanelWindows` in combat.
-- Turns `WorldMapFrame` into a single unified HUD Edit Mode window (`DavesMapWorldChrome`, `DialogBorderTranslucentTemplate`)
-- hosting `[ Map Column (Dropdowns + Centered Map Stage) | Vertical Splitter | Middle 46px Tab Rail | Right Content Pane ]`,
-- redirects `TOGGLEQUESTLOG` (`L`) to open the unified window cleanly, and exposes Blizzard's Forever map tracking filters
-- (`questPOI`, `showQuestLevel`, `showQuestDifficultyColor`, `showDungeonEntrancesOnMap`, `trivialQuests`,
-- `contentTrackingFilter`) inside Map Settings.

local _, ns = ...

local L = {
	CHROME_LEFT = -6,
	CHROME_TOP = 6,
	OUTER_PAD = 12,
	TOP_CONTENT_Y = -6,      -- CHROME_TOP - OUTER_PAD (no title bar gap!)
	NAV_BAR_H = 26,          -- matches Search/toolbar & WowStyle1DropdownTemplate height
	NAV_GAP = 6,             -- gap between map nav dropdowns and map stage
	STAGE_TOP_Y = -38,       -- TOP_CONTENT_Y - NAV_BAR_H - NAV_GAP
	MAP_MAT_PAD = 1,         -- 1px inset inside mapStage's subtle outer hairline (no inner map border)
	MAP_LEFT_X = 6,          -- CHROME_LEFT + OUTER_PAD (map is now on the LEFT!)
	SPLITTER_W = 8,          -- draggable divider between Map column and Middle Tab Rail
	RAIL_W = 46,             -- middle Tab Rail (`B`, `T`, `Z`, `D`) left of text/content pane
	RAIL_CONTENT_GAP = 4,    -- tight seam between Tab Rail and Right Content Pane
	MAP_MIN_W = 460,
	MAP_DEFAULT_W = 697,
	MAP_MAX_W = 900,
	MAP_MIN_H = 320,
	MAP_DEFAULT_H = 465,
	MAP_MAX_H = 900,         -- ScrollContainer fills mapStage full height so map backdrop extends seamlessly
	CONTENT_MIN_W = 480,
	CONTENT_DEFAULT_W = 516,
	CONTENT_MAX_W = 1000,
	BODY_MIN_H = 322,        -- MAP_MIN_H + 2 * MAP_MAT_PAD
	BODY_DEFAULT_H = 467,    -- MAP_DEFAULT_H + 2 * MAP_MAT_PAD
	BODY_MAX_H = 900,
}
ns.UNIFIED_LAYOUT = L

local function SafeNum(v)
	return (type(v) == "number" and not issecretvalue(v)) and v or nil
end

local state = {
	initialized = false,
	questMapSuppressed = false,
	hiddenFrames = {},
	keyOwner = nil,
	questLogKeys = {},
	mapChrome = nil,
	mapBorder = nil,
	mapOverlay = nil,
	mapW = nil,
	contentW = nil,
	bodyH = nil,
	inLayout = false,
	navHooked = false,
	microHooked = false,
	detailsHooked = false,
	pendingKeybindSync = false,
	pendingProviderRefresh = false,
	pendingLayout = false,
	pendingCanvasResize = false,
	pendingReset = false,
	pendingScale = nil,
	pendingPosRestore = false,
	hideScheduled = false,
	drag = {
		active = false,
		moved = false,
		startCX = 0,
		startCY = 0,
		startX = 0,
		startY = 0,
		lastX = nil,
		lastY = nil,
		watcher = nil,
	},
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

local LayoutUnifiedMapRegion, SyncMapChromeStrata, RestoreWindowPosition, StopWindowDrag

local bindEvents = CreateFrame("Frame")
bindEvents:RegisterEvent("PLAYER_LOGIN")
bindEvents:RegisterEvent("UPDATE_BINDINGS")
bindEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
bindEvents:RegisterEvent("DISPLAY_SIZE_CHANGED")
bindEvents:RegisterEvent("UI_SCALE_CHANGED")
bindEvents:SetScript("OnEvent", function(_, event)
	if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
		if StopWindowDrag then StopWindowDrag(true) end
		if RestoreWindowPosition then RestoreWindowPosition() end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		if state.pendingKeybindSync then SyncQuestLogKeybind() end
		if state.pendingScale then ns.ApplyUnifiedScale(state.pendingScale) end
		if state.pendingReset then
			local keepPos = (state.pendingReset == "size")
			state.pendingReset = false
			if ns.ResetPanelPosition then
				ns.ResetPanelPosition(keepPos)
			elseif ns.ResetUnifiedLayout then
				ns.ResetUnifiedLayout(keepPos)
			end
		elseif state.pendingLayout then
			state.pendingLayout = false
			if LayoutUnifiedMapRegion then LayoutUnifiedMapRegion(true) end
			if SyncMapChromeStrata then SyncMapChromeStrata() end
		end
		if state.pendingPosRestore and RestoreWindowPosition then
			state.pendingPosRestore = false
			RestoreWindowPosition()
		end
		if state.pendingCanvasResize and WorldMapFrame and WorldMapFrame:IsShown() then
			local sc = WorldMapFrame.ScrollContainer
			if sc and sc.mapID and sc.OnCanvasSizeChanged then
				state.pendingCanvasResize = false
				if ns.PrepareNonStitchedResize then ns.PrepareNonStitchedResize() end
				sc:OnCanvasSizeChanged()
			end
		elseif ns.EnsureNonStitchedViewportFit then
			ns.EnsureNonStitchedViewportFit()
		end
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
-- Single Unified HUD Edit Mode Window (`DavesMapWorldChrome`)
-- Layout: [ Map Column (Dropdowns + Centered Map Stage) | Splitter | Middle Tab Rail | Right Content Pane ]
---------------------------------------------------------------------------
local function TryTemplate(kind, name, parent, template)
	local ok, f = pcall(CreateFrame, kind, name, parent, template)
	return ok and f or nil
end

local function ClampMapWidth(w)
	if type(w) ~= "number" then w = L.MAP_DEFAULT_W end
	return math.max(L.MAP_MIN_W, math.min(L.MAP_MAX_W, math.floor(w + 0.5)))
end

local function ClampContentWidth(w)
	if type(w) ~= "number" then w = L.CONTENT_DEFAULT_W end
	return math.max(L.CONTENT_MIN_W, math.min(L.CONTENT_MAX_W, math.floor(w + 0.5)))
end

local function ClampBodyHeight(h)
	if type(h) ~= "number" then h = L.BODY_DEFAULT_H end
	return math.max(L.BODY_MIN_H, math.min(L.BODY_MAX_H, math.floor(h + 0.5)))
end

local function MapHeightForBody(bodyH)
	return math.max(L.MAP_MIN_H, math.min(L.MAP_MAX_H, bodyH - 2 * L.MAP_MAT_PAD))
end

function ns.GetUnifiedWindowSize()
	local mw = state.mapW or ClampMapWidth(ns.db and ns.db.mapW)
	local cw = state.contentW or ClampContentWidth(ns.db and ns.db.contentW)
	local bh = state.bodyH or ClampBodyHeight(ns.db and ns.db.bodyH)
	return mw, MapHeightForBody(bh), cw, bh
end

function ns.GetUnifiedContentWidth()
	local _, _, cw = ns.GetUnifiedWindowSize()
	return cw
end

local function UpdateChromeBounds()
	local chrome = state.mapChrome
	if not (chrome and WorldMapFrame) then return end
	local mw, _, cw, bh = ns.GetUnifiedWindowSize()
	chrome:ClearAllPoints()
	chrome:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", L.CHROME_LEFT, L.CHROME_TOP)
	chrome:SetPoint("BOTTOMRIGHT", WorldMapFrame, "TOPLEFT",
		L.MAP_LEFT_X + mw + L.SPLITTER_W + L.RAIL_W + L.RAIL_CONTENT_GAP + cw + L.OUTER_PAD,
		L.STAGE_TOP_Y - bh - L.OUTER_PAD)
	if ns.LayoutMapStage then
		ns.LayoutMapStage(L.MAP_LEFT_X, L.TOP_CONTENT_Y, L.NAV_BAR_H, L.STAGE_TOP_Y, mw, bh)
	end
	if ns.SyncPanelDock then
		ns.SyncPanelDock()
	end
end

local function ApplySpacerAndScrollBounds(mw, mh, bh)
	local spacer = WorldMapFrame and WorldMapFrame.TitleCanvasSpacerFrame
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	if not (spacer and sc) then return end
	local extraY = math.floor((bh - mh) / 2)
	local scTopY = L.STAGE_TOP_Y - extraY
	spacer:ClearAllPoints()
	spacer:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", L.MAP_LEFT_X, 0)
	spacer:SetPoint("BOTTOMRIGHT", WorldMapFrame, "TOPLEFT", L.MAP_LEFT_X + mw, L.STAGE_TOP_Y)
	sc:ClearAllPoints()
	sc:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", L.MAP_LEFT_X + L.MAP_MAT_PAD, scTopY)
	sc:SetPoint("BOTTOMRIGHT", WorldMapFrame, "TOPLEFT", L.MAP_LEFT_X + mw - L.MAP_MAT_PAD, scTopY - mh)
end

function ns.SetUnifiedWindowSize(mapW, contentW, bodyH, save)
	local curMW, curMH, curCW, curBH = ns.GetUnifiedWindowSize()
	local cw = ClampContentWidth(contentW ~= nil and contentW or curCW)
	local mw = curMW
	local bh = curBH
	if not InCombatLockdown() then
		state.pendingReset = false
		mw = ClampMapWidth(mapW ~= nil and mapW or curMW)
		bh = ClampBodyHeight(bodyH ~= nil and bodyH or curBH)
	end
	local mh = MapHeightForBody(bh)
	local mapChanged = (mw ~= curMW) or (mh ~= curMH)
	local stageChanged = mapChanged or (bh ~= curBH)
	state.mapW = mw
	state.contentW = cw
	state.bodyH = bh
	if save and ns.db then
		ns.db.mapW = mw
		ns.db.contentW = cw
		ns.db.bodyH = bh
	end
	if stageChanged and not InCombatLockdown() and not (WorldMapFrame and WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()) then
		ApplySpacerAndScrollBounds(mw, mh, bh)
	end
	UpdateChromeBounds()
	return mw, mh, cw, bh, mapChanged
end

function ns.SetUnifiedContentWidth(w, save)
	local _, _, cw = ns.SetUnifiedWindowSize(nil, w, nil, save)
	return cw
end

function ns.CommitUnifiedMapResize(mapChanged)
	local stitch = ns.StitchWorld and ns.StitchWorld() or nil
	if mapChanged then
		local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
		if not InCombatLockdown() and WorldMapFrame and WorldMapFrame:IsShown() and sc and sc.mapID and sc.OnCanvasSizeChanged then
			state.pendingCanvasResize = false
			if ns.PrepareNonStitchedResize then ns.PrepareNonStitchedResize() end
			sc:OnCanvasSizeChanged()
		else
			state.pendingCanvasResize = true
		end
	end
	if stitch and stitch.EndResize then
		stitch.EndResize()
	end
end

local function DefaultWindowPosition(s)
	local uiTop = SafeNum(UIParent and UIParent:GetTop()) or 768
	local _, _, _, bh = ns.GetUnifiedWindowSize()
	local frameH = (-L.STAGE_TOP_Y + bh + L.OUTER_PAD) * s
	local yOffset = -116
	local bottomPos = uiTop + yOffset - frameH
	if bottomPos < 80 then
		yOffset = yOffset + (80 - bottomPos)
	end
	local maxTop = -math.ceil(L.CHROME_TOP * s) - 2
	if yOffset > maxTop then
		yOffset = maxTop
	end
	local leftX = math.max(16, math.ceil(-L.CHROME_LEFT * s) + 4)
	return leftX, yOffset
end

local function ClampWindowPosition(x, y, s)
	local mw, _, cw, bh = ns.GetUnifiedWindowSize()
	local uiW = SafeNum(UIParent and UIParent:GetWidth()) or 1365
	local uiH = SafeNum(UIParent and UIParent:GetHeight()) or 768
	local chromeRight = L.MAP_LEFT_X + mw + L.SPLITTER_W + L.RAIL_W + L.RAIL_CONTENT_GAP + cw + L.OUTER_PAD
	local chromeBottom = L.STAGE_TOP_Y - bh - L.OUTER_PAD
	local chromeW = (chromeRight - L.CHROME_LEFT) * s
	local chromeH = (L.CHROME_TOP - chromeBottom) * s

	local maxY = -L.CHROME_TOP * s - 2
	local minY
	if chromeH <= uiH - 8 then
		minY = -uiH + 4 - chromeBottom * s
	else
		minY = -uiH + 64 - L.CHROME_TOP * s
	end
	if minY > maxY then minY = maxY end

	local minX, maxX
	if chromeW <= uiW - 8 then
		minX = 4 - L.CHROME_LEFT * s
		maxX = uiW - 4 - chromeRight * s
	else
		minX = 160 - chromeRight * s
		maxX = uiW - 160 - L.CHROME_LEFT * s
	end
	if minX > maxX then
		local mid = (minX + maxX) / 2
		minX, maxX = mid, mid
	end
	return math.max(minX, math.min(maxX, x)), math.max(minY, math.min(maxY, y))
end

local function ApplyWindowPosition(x, y)
	if not WorldMapFrame then return nil, nil end
	if WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() then return nil, nil end
	if InCombatLockdown() then
		state.pendingPosRestore = true
		return nil, nil
	end
	state.pendingPosRestore = false
	local s = SafeNum(WorldMapFrame:GetScale()) or 1
	if s <= 0 then s = 1 end
	local cx, cy = ClampWindowPosition(x, y, s)
	WorldMapFrame:ClearAllPoints()
	WorldMapFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cx / s, cy / s)
	return cx, cy
end

RestoreWindowPosition = function()
	if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
	if state.drag.active then return end
	if WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() then return end
	local pos = ns.db and ns.db.windowPos
	if type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then return end
	ApplyWindowPosition(pos.x, pos.y)
end
ns.RestoreWindowPosition = RestoreWindowPosition

StopWindowDrag = function(save)
	if not state.drag.active then return end
	state.drag.active = false
	if state.drag.watcher then state.drag.watcher:SetScript("OnUpdate", nil) end
	if save and state.drag.moved and state.drag.lastX and state.drag.lastY and ns.db then
		ns.db.windowPos = {
			x = math.floor(state.drag.lastX + 0.5),
			y = math.floor(state.drag.lastY + 0.5),
		}
	end
end
ns.StopWindowDrag = StopWindowDrag

local function OnDragUpdate()
	if not state.drag.active
		or InCombatLockdown()
		or not (WorldMapFrame and WorldMapFrame:IsShown())
		or (WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized())
		or (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then
		StopWindowDrag(true)
		return
	end
	local cx, cy = GetCursorPosition()
	local uiScale = SafeNum(UIParent and UIParent:GetEffectiveScale()) or 1
	if uiScale <= 0 then uiScale = 1 end
	local dx = (cx - state.drag.startCX) / uiScale
	local dy = (cy - state.drag.startCY) / uiScale
	if not state.drag.moved and (dx * dx + dy * dy) < 9 then return end
	state.drag.moved = true
	local nx, ny = ApplyWindowPosition(state.drag.startX + dx, state.drag.startY + dy)
	if nx and ny then
		state.drag.lastX = nx
		state.drag.lastY = ny
	end
end

function ns.StartWindowDrag()
	if not (WorldMapFrame and WorldMapFrame:IsShown()) or InCombatLockdown() then return end
	if WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() then return end
	if ns.PanelUI and ns.PanelUI.dragging then return end
	if state.drag.active then StopWindowDrag(true) end
	local left = SafeNum(WorldMapFrame:GetLeft())
	local top = SafeNum(WorldMapFrame:GetTop())
	local s = SafeNum(WorldMapFrame:GetScale()) or 1
	if s <= 0 then s = 1 end
	local uiH = SafeNum(UIParent and UIParent:GetHeight()) or 768
	if not (left and top) then return end
	local cx, cy = GetCursorPosition()
	state.drag.active = true
	state.drag.moved = false
	state.drag.startCX = cx
	state.drag.startCY = cy
	state.drag.startX = left * s
	state.drag.startY = top * s - uiH
	state.drag.lastX = state.drag.startX
	state.drag.lastY = state.drag.startY
	if not state.drag.watcher then
		state.drag.watcher = CreateFrame("Frame")
	end
	state.drag.watcher:SetScript("OnUpdate", OnDragUpdate)
end

function ns.AttachWindowDrag(frame)
	if not (frame and frame.HookScript) then return end
	frame:HookScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then ns.StartWindowDrag() end
	end)
	frame:HookScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then StopWindowDrag(true) end
	end)
end

function ns.ResetUnifiedLayout(keepPos)
	StopWindowDrag(false)
	if ns.db then
		ns.db.mapW = nil
		ns.db.contentW = nil
		ns.db.bodyH = nil
		if not keepPos then ns.db.windowPos = nil end
		ns.db.panelPos = nil
		ns.db.panelW = nil
		ns.db.panelH = nil
	end
	if InCombatLockdown() then
		if state.pendingReset ~= "all" then
			state.pendingReset = keepPos and "size" or "all"
		end
		ns.SetUnifiedWindowSize(nil, L.CONTENT_DEFAULT_W, nil, false)
		return
	end
	state.pendingReset = false
	local _, _, _, _, mapChanged = ns.SetUnifiedWindowSize(L.MAP_DEFAULT_W, L.CONTENT_DEFAULT_W, L.BODY_DEFAULT_H, false)
	if mapChanged then
		ns.CommitUnifiedMapResize(true)
	end
	if WorldMapFrame and WorldMapFrame:IsShown() and not (WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()) then
		if keepPos then
			RestoreWindowPosition()
		else
			local s = SafeNum(WorldMapFrame:GetScale()) or 1
			if s <= 0 then s = 1 end
			ApplyWindowPosition(DefaultWindowPosition(s))
		end
	end
end

function ns.ApplyUnifiedScale(scale)
	if not WorldMapFrame then return end
	local s = math.max(0.5, math.min(1.5, scale or 1.0))
	if InCombatLockdown() then
		state.pendingScale = s
		return
	end
	state.pendingScale = nil
	local cur = SafeNum(WorldMapFrame:GetScale()) or 1
	if math.abs(cur - s) > 0.001 then
		WorldMapFrame:SetScale(s)
		if WorldMapFrame:IsShown() and not (WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()) then
			local pos = ns.db and ns.db.windowPos
			if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
				ApplyWindowPosition(pos.x, pos.y)
			else
				ApplyWindowPosition(DefaultWindowPosition(s))
			end
		end
	end
end

local function LayoutCloseButton()
	if not WorldMapFrame then return end
	local close = WorldMapFrame.BorderFrame and WorldMapFrame.BorderFrame.CloseButton
	if close and state.mapChrome then
		close:ClearAllPoints()
		close:SetPoint("TOPRIGHT", state.mapChrome, "TOPRIGHT", -2, -2)
		if close.SetFrameLevel and not (close:IsProtected() and InCombatLockdown()) then
			local base = (state.mapOverlay and SafeNum(state.mapOverlay:GetFrameLevel())) or 11
			close:SetFrameLevel(math.max(SafeNum(close:GetFrameLevel()) or 1, base + 35, 45))
		end
	end
end

LayoutUnifiedMapRegion = function(fromSpacerHook)
	if state.inLayout or not WorldMapFrame then return end
	if WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() then return end
	local spacer = WorldMapFrame.TitleCanvasSpacerFrame
	local sc = WorldMapFrame.ScrollContainer
	if not (spacer and sc) then return end
	if InCombatLockdown() then
		state.pendingLayout = true
		return
	end
	state.pendingLayout = false
	state.inLayout = true
	local prevW = SafeNum(sc:GetWidth()) or 0
	local prevH = SafeNum(sc:GetHeight()) or 0
	local mw, mh, _, bh = ns.GetUnifiedWindowSize()
	ApplySpacerAndScrollBounds(mw, mh, bh)
	UpdateChromeBounds()
	LayoutCloseButton()
	state.inLayout = false
	local scW = mw - 2 * L.MAP_MAT_PAD
	if fromSpacerHook and (math.abs(prevW - scW) > 1 or math.abs(prevH - mh) > 1) then
		if WorldMapFrame:IsShown() and sc.mapID and sc.OnCanvasSizeChanged then
			state.pendingCanvasResize = false
			if ns.PrepareNonStitchedResize then ns.PrepareNonStitchedResize() end
			sc:OnCanvasSizeChanged()
		else
			state.pendingCanvasResize = true
		end
	end
end
ns.LayoutUnifiedMapRegion = LayoutUnifiedMapRegion

SyncMapChromeStrata = function()
	if not (WorldMapFrame and state.mapChrome) then return end
	local mapStrata = WorldMapFrame:GetFrameStrata() or "MEDIUM"
	local scLevel = (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer:GetFrameLevel()) or 2
	state.mapChrome:SetFrameStrata(mapStrata)
	state.mapChrome:SetFrameLevel(math.max(0, scLevel - 2))
	if state.mapBorder then
		state.mapBorder:SetFrameLevel(state.mapChrome:GetFrameLevel())
	end
	if state.mapOverlay and WorldMapFrame.BorderFrame then
		state.mapOverlay:SetFrameStrata(WorldMapFrame.BorderFrame:GetFrameStrata() or "HIGH")
		state.mapOverlay:SetFrameLevel((WorldMapFrame.BorderFrame:GetFrameLevel() or 10) + 1)
	end
	local close = WorldMapFrame.BorderFrame and WorldMapFrame.BorderFrame.CloseButton
	if close and close.SetFrameLevel and not (close:IsProtected() and InCombatLockdown()) then
		local base = (state.mapOverlay and SafeNum(state.mapOverlay:GetFrameLevel())) or 11
		close:SetFrameLevel(math.max(SafeNum(close:GetFrameLevel()) or 1, base + 35, 45))
	end
	if ns.SyncMapStageStrata then
		ns.SyncMapStageStrata()
	end
	if ns.SyncPanelDock then
		ns.SyncPanelDock()
	end
end

local function RefreshStage(overrideMapID)
	if ns.RefreshMapStage then
		ns.RefreshMapStage(overrideMapID)
	end
end
ns.UpdateMapChromeTitle = RefreshStage

function ns.WorldMapChrome()
	return state.mapChrome
end

function ns.ApplyMapChromeStyle(alpha, style)
	if state.mapBorder and ns.ApplyDialogBackground then
		ns.ApplyDialogBackground(state.mapBorder, alpha, style)
	end
	if ns.ApplyMapStageStyle then
		ns.ApplyMapStageStyle(alpha, style)
	end
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
	KeepHidden(WorldMapFrame.OverscrollBG)
	KeepHidden(WorldMapFrame.NavBar)
	KeepHidden(WorldMapFrame.SidePanelToggle)
	KeepHidden(WorldMapFrame.WorldMapTrackingOptionsButton)
	KeepHidden(WorldMapFrame.WorldMapTrackingPinButton)
	if type(WorldMapFrame.overlayFrames) == "table" then
		for _, f in ipairs(WorldMapFrame.overlayFrames) do
			if f and f.RefreshMenu and f.ShouldShowTrackingIconOnFloor then
				KeepHidden(f)
			end
		end
	end
end

function ns.InitMapChrome()
	if not WorldMapFrame then return end
	SuppressQuestMapFrame()
	HideDefaultWorldMapChrome()

	if state.initialized then
		LayoutUnifiedMapRegion(false)
		RestoreWindowPosition()
		SyncMapChromeStrata()
		RefreshStage()
		return
	end
	state.initialized = true
	state.mapW = ClampMapWidth(ns.db and ns.db.mapW)
	state.contentW = ClampContentWidth(ns.db and ns.db.contentW)
	state.bodyH = ClampBodyHeight(ns.db and ns.db.bodyH)

	-- Single unified HUD Edit Mode translucent dialog frame spanning:
	-- [ Map Column (Dropdowns + Centered Map Stage) | Splitter | Middle Tab Rail | Right Content Pane ].
	local chrome = CreateFrame("Frame", "DavesMapWorldChrome", WorldMapFrame)
	state.mapChrome = chrome
	chrome:EnableMouse(true)
	chrome:EnableMouseWheel(true)
	chrome:SetScript("OnMouseUp", function(_, button)
		if button == "Button4" and ns.GoBack then ns.GoBack() end
	end)
	ns.AttachWindowDrag(chrome)

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

	-- Non-interactive overlay above the canvas anchoring CloseButton and map nav dropdown strata (`MapStage.lua`).
	local overlay = CreateFrame("Frame", nil, WorldMapFrame)
	state.mapOverlay = overlay
	overlay:EnableMouse(false)
	overlay:SetAllPoints(chrome)

	if ns.InitMapStage then
		ns.InitMapStage(chrome, overlay)
	end

	LayoutUnifiedMapRegion(false)
	RestoreWindowPosition()
	SyncMapChromeStrata()
	RefreshStage()

	if not state.navHooked then
		state.navHooked = true
		ns.AttachWindowDrag(WorldMapFrame)
		if type(UpdateUIPanelPositions) == "function" then
			hooksecurefunc("UpdateUIPanelPositions", RestoreWindowPosition)
		end
		if type(UpdateScaleForFitForOpenPanels) == "function" then
			hooksecurefunc("UpdateScaleForFitForOpenPanels", RestoreWindowPosition)
		end
		if WorldMapFrame.SynchronizeDisplayState then
			hooksecurefunc(WorldMapFrame, "SynchronizeDisplayState", RestoreWindowPosition)
		end
		if WorldMapFrame.UpdateSpacerFrameAnchoring then
			hooksecurefunc(WorldMapFrame, "UpdateSpacerFrameAnchoring", function()
				LayoutUnifiedMapRegion(true)
				SyncMapChromeStrata()
			end)
		end
		hooksecurefunc(WorldMapFrame, "Minimize", function()
			HideDefaultWorldMapChrome()
			LayoutUnifiedMapRegion(true)
			RestoreWindowPosition()
			SyncMapChromeStrata()
		end)
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
			RefreshStage()
		end)
		WorldMapFrame:HookScript("OnShow", function()
			SuppressQuestMapFrame()
			HideDefaultWorldMapChrome()
			LayoutUnifiedMapRegion(false)
			RestoreWindowPosition()
			if state.pendingCanvasResize and not InCombatLockdown() then
				local mapSC = WorldMapFrame.ScrollContainer
				if mapSC and mapSC.mapID and mapSC.OnCanvasSizeChanged then
					state.pendingCanvasResize = false
					mapSC:OnCanvasSizeChanged()
				end
			elseif ns.EnsureNonStitchedViewportFit then
				ns.EnsureNonStitchedViewportFit()
			end
			SyncMapChromeStrata()
			RefreshStage()
			if ns.WasQuestLogKeyPressed() and ns.OpenTrackerTab then
				ns.OpenTrackerTab(nil, nil, true)
			end
		end)
		WorldMapFrame:HookScript("OnHide", function()
			StopWindowDrag(true)
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
