-- daves_map / Panel.lua
-- Single unified Dave's Map window layout inside `DavesMapWorldChrome` (`MapChrome.lua`):
--   * Layout: `[ Left: Map Column (Dropdowns + Centered Map Stage) | Vertical Splitter | Middle: 46px Tab Rail | Right: Content Pane ]`.
--   * `ui.panel` is a mouse-transparent container matching `DavesMapWorldChrome` so the left map nav
--     dropdowns and live World Map canvas stay 100% interactive while `splitter`, `leftRail`, and `content` capture clicks.
--   * Top content toolbar: `[ <- Back | Search... | Find Me | Drop Waypoint | Map Settings ]` (leaving top-right clear for Blizzard's CloseButton).
--   * Bottom-right grip resizes the unified window in 2D: the map column & ScrollContainer grow/shrink
--     inside `460..900` width and full window height (`322..900`, centering fixed-aspect maps vertically
--     over the full-bleed stage backdrop with no inner map border) while extra width overflows into the
--     right content pane; the vertical splitter trades width between map & panel directly.

local _, ns = ...

local ui = ns.PanelUI
local C = ns.PANEL_CONST
local L = ns.UNIFIED_LAYOUT or {}
local OUTER_PAD = L.OUTER_PAD or 12
local TOP_CONTENT_Y = L.TOP_CONTENT_Y or -6
local NAV_BAR_H = L.NAV_BAR_H or 26
local NAV_GAP = L.NAV_GAP or 6
local SPLITTER_W = L.SPLITTER_W or 8
local RAIL_W = L.RAIL_W or C.RAIL_W or 46
local RAIL_CONTENT_GAP = L.RAIL_CONTENT_GAP or 4
local MAP_MIN_W = L.MAP_MIN_W or 460
local MAP_MAX_W = L.MAP_MAX_W or 900
local CONTENT_MIN_W = L.CONTENT_MIN_W or 480
local CONTENT_MAX_W = L.CONTENT_MAX_W or 1000
local BODY_MIN_H = L.BODY_MIN_H or 322
local BODY_DEFAULT_H = L.BODY_DEFAULT_H or 467
local BODY_MAX_H = L.BODY_MAX_H or 900
local LIST_PAD, SCROLL_GUTTER = C.LIST_PAD, C.SCROLL_GUTTER
local Sound = ns.Sound

local resizeState = {
	active = false,
	mode = nil,
	btn = nil,
	startX = 0,
	startY = 0,
	startMapW = L.MAP_DEFAULT_W or 697,
	startMapH = L.MAP_DEFAULT_H or 465,
	startContentW = L.CONTENT_DEFAULT_W or 516,
	startBodyH = BODY_DEFAULT_H,
	lastMapW = L.MAP_DEFAULT_W or 697,
	lastMapH = L.MAP_DEFAULT_H or 465,
	lastContentW = L.CONTENT_DEFAULT_W or 516,
	lastBodyH = BODY_DEFAULT_H,
	mapChanged = false,
}

local function SafeNum(v)
	return (type(v) == "number" and not issecretvalue(v)) and v or nil
end

local function PollPinMode(btn)
	if not (ns.PinModeActive and ns.PinModeActive()) then
		btn:SetActive(false)
	end
end

local TAB_DEFS = {
	{
		key = "layers",
		label = "Base",
		icon = "tab_base",
		tip = "Toggle base POI map icons (flight masters, townsfolk, rares, treasures) and adjust Map Settings.",
	},
	{
		key = "tracker",
		label = "Tracker & Log",
		icon = "tab_tracker",
		tip = "Your merged Quest Log & Tracker (Focused, Ready to Turn In, Pinned, Tracking, and all Quest Log quests) with track checkboxes and built-in Quest Text.",
	},
	{
		key = "zone",
		label = "Zone",
		icon = "tab_zone",
		tip = "Browse zone quests & inline quest chains for your zone or the zone you navigate to on the map.",
	},
	{
		key = "dungeon",
		label = "Dungeon",
		icon = "tab_dungeon",
		tip = "View dungeons, floor maps, and dungeon quests for your zone or the zone you navigate to on the map.",
	},
}

---------------------------------------------------------------------------
-- Chrome Layout & Prominent Reference-Layer Status Bar
---------------------------------------------------------------------------
local function UpdateChromeLayout()
	local D = ns.DATA
	if not (ui.ready and D) then return end

	local canBack = ns.DescribeBackTarget()
	if ui.backBtn then
		ui.backBtn.isDisabled = not canBack
		ui.backBtn:SetAlpha(canBack and 1 or 0.36)
		if ui.backBtn.hl then ui.backBtn.hl:SetAlpha(canBack and 0.45 or 0) end
		if ui.backBtn.activeGlow then
			ui.backBtn.activeGlow:SetShown(canBack and (ns.IsDungeonViewShown and ns.IsDungeonViewShown() or false))
		end
	end
	if ui.pinBtn and ui.pinBtn.SetActive and ns.PinModeActive then
		ui.pinBtn:SetActive(ns.PinModeActive())
	end
	if ui.styleBtn and ui.styleBtn.SetActive and ns.IsStyleDialogOpen then
		ui.styleBtn:SetActive(ns.IsStyleDialogOpen())
	end

	local tab = ns.db.panelTab or "layers"
	local searching = ui.found ~= nil

	for k, b in pairs(ui.tabs) do
		local selected = (not searching) and (k == tab)
		b.activeBar:SetShown(selected)
		b.activeGlow:SetShown(selected)
		if selected then
			b.frame:SetVertexColor(1, 0.96, 0.78, 1)
			b.icon:SetAlpha(1)
		else
			b.frame:SetVertexColor(0.76, 0.70, 0.56, 0.90)
			b.icon:SetAlpha(0.76)
		end
	end

	local curY = -30
	ui.layerBar:Hide()
	ui.zoneBar:Hide()

	local onBaseLayer = tab == "layers" or tab == "tracker"
	local clickQ = (onBaseLayer and ns.ActiveFocusQuest) and ns.ActiveFocusQuest() or nil
	local focused = onBaseLayer and ((ns.Focused and ns.Focused()) or (clickQ ~= nil))
	if searching then
		ui.layerBar:ClearAllPoints()
		ui.layerBar:SetPoint("TOPLEFT", LIST_PAD, curY)
		ui.layerBar:SetPoint("TOPRIGHT", -LIST_PAD, curY)
		ui.layerBar:SetBackdropColor(0.11, 0.10, 0.07, 0.92)
		ui.layerBar:SetBackdropBorderColor(0.68, 0.54, 0.25, 0.85)
		ui.layerBar.label:ClearAllPoints()
		ui.layerBar.label:SetPoint("LEFT", 10, 0)
		ui.layerBar.label:SetPoint("RIGHT", ui.layerBar.actionBtn, "LEFT", -8, 0)
		ui.layerBar.label:SetText(("|cffffd200Search:|r %d match%s"):format(#ui.found, #ui.found == 1 and "" or "es"))
		ui.layerBar.actionBtn.text:SetText("|cffe8d8a8Clear|r")
		ui.layerBar.actionBtn:SetWidth(62)
		ui.layerBar.actionBtn.mode = "search"
		ui.layerBar:Show()
		curY = curY - 34
	elseif focused then
		ui.layerBar:ClearAllPoints()
		ui.layerBar:SetPoint("TOPLEFT", LIST_PAD, curY)
		ui.layerBar:SetPoint("TOPRIGHT", -LIST_PAD, curY)
		ui.layerBar:SetBackdropColor(0.11, 0.10, 0.07, 0.92)
		ui.layerBar:SetBackdropBorderColor(0.68, 0.54, 0.25, 0.85)
		ui.layerBar.label:ClearAllPoints()
		ui.layerBar.label:SetPoint("LEFT", 10, 0)
		ui.layerBar.label:SetPoint("RIGHT", ui.layerBar.actionBtn, "LEFT", -8, 0)
		local fTitle = clickQ and ns.QuestTitle and ns.QuestTitle(clickQ) or nil
		if fTitle then
			ui.layerBar.label:SetText(("|cffffd200Focused:|r %s"):format(ns.Shorten(fTitle, 48)))
		else
			ui.layerBar.label:SetText("|cffffd200Focused tracked quest|r")
		end
		ui.layerBar.actionBtn.text:SetText("|cffe8d8a8Show All|r")
		ui.layerBar.actionBtn:SetWidth(76)
		ui.layerBar.actionBtn.mode = "unfocus"
		ui.layerBar:Show()
		curY = curY - 34
	end

	local inDetails = (not searching) and (ui.detailQuestID ~= nil) and ns.QuestInLog and ns.QuestInLog(ui.detailQuestID)
	if ui.detailQuestID and not inDetails and not searching then
		ui.detailQuestID = nil
		ui.detailPin = nil
	end

	if not searching and not inDetails and tab == "tracker" then
		ui.zoneBar:ClearAllPoints()
		ui.zoneBar:SetPoint("TOPLEFT", LIST_PAD, curY)
		ui.zoneBar:SetPoint("TOPRIGHT", -LIST_PAD, curY)
		ui.zoneBar:SetStatusBarColor(0.66, 0.50, 0.22, 0.85)
		local numQ, maxQ = 0, 25
		if ns.QuestLogCounts then numQ, maxQ = ns.QuestLogCounts() end
		local nWatched = (C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches()) or 0
		if issecretvalue(nWatched) then nWatched = 0 end
		ui.zoneBar:SetMinMaxValues(0, math.max(1, maxQ))
		ui.zoneBar:SetValue(numQ)
		ui.zoneBar.left:SetText(nWatched > 0 and ("Quest Log  -  %d tracked"):format(nWatched) or "Quest Log")
		ui.zoneBar.right:SetText(("%d / %d"):format(numQ, maxQ))
		ui.zoneBar:Show()
		curY = curY - 26
	elseif not searching and not inDetails and tab == "zone" then
		ui.zoneBar:ClearAllPoints()
		ui.zoneBar:SetPoint("TOPLEFT", LIST_PAD, curY)
		ui.zoneBar:SetPoint("TOPRIGHT", -LIST_PAD, curY)
		ui.zoneBar:SetStatusBarColor(0.28, 0.68, 0.34, 0.85)
		local zMap = ui.zoneMap or (ns.ActiveZoneContext and ns.ActiveZoneContext()) or (ns.ViewZoneMap and ns.ViewZoneMap())
		local info = zMap and C_Map.GetMapInfo(zMap)
		local zName = info and info.name or "World"
		local zl = zMap and D.zones and D.zones[zMap]
		if zl then
			local mid = math.floor((zl[1] + zl[2]) / 2)
			local range = zl[1] == zl[2] and tostring(zl[1]) or (zl[1] .. "-" .. zl[2])
			zName = ("%s |c%s(%s)|r"):format(zName, ns.DiffHex(mid), range)
		end
		local done, total = ui.zoneDone or 0, ui.zoneTotal or 0
		ui.zoneBar:SetMinMaxValues(0, math.max(1, total))
		ui.zoneBar:SetValue(total > 0 and done or 0)
		local pct = total > 0 and math.floor(done * 100 / total + .5) or 0
		ui.zoneBar.left:SetText(zName)
		ui.zoneBar.right:SetText(total > 0 and ("%d/%d (%d%%)"):format(done, total, pct) or "No quests")
		ui.zoneBar:Show()
		curY = curY - 26
	end

	ui.divider:ClearAllPoints()
	ui.divider:SetPoint("TOPLEFT", LIST_PAD, curY - 1)
	ui.divider:SetPoint("TOPRIGHT", -LIST_PAD, curY - 1)
	local listH = ui.list and ui.list:GetHeight() or 0
	local needScroll = (not inDetails) and listH > 0 and (ui.totalH or 0) > (listH + 1)
	local rightInset = needScroll and (LIST_PAD + SCROLL_GUTTER) or LIST_PAD
	ui.listTopY = curY - 5
	ui.listRightInset = rightInset
	ui.list:ClearAllPoints()
	ui.list:SetPoint("TOPLEFT", LIST_PAD, ui.listTopY)
	ui.list:SetPoint("BOTTOMRIGHT", -rightInset, LIST_PAD)

	if inDetails and ui.detailsPane then
		local wasShown = ui.detailsPane:IsShown()
		ui.list:Hide()
		if ui.scrollBar then ui.scrollBar:Hide() end
		if ui.scrollTrack then ui.scrollTrack:Hide() end
		if ui.scrollThumb then ui.scrollThumb:Hide() end
		if ns.LayoutQuestDetailsPane then ns.LayoutQuestDetailsPane(true) end
		if wasShown then
			if ns.RefreshQuestDetails then ns.RefreshQuestDetails(false) end
		else
			ui.detailsPane:Show()
		end
	else
		if ui.detailsPane then ui.detailsPane:Hide() end
		ui.list:Show()
		if ui.nativeScrollBar and ui.scrollBar then
			ui.scrollBar:Show()
		end
	end
end

---------------------------------------------------------------------------
-- Docking & Public Refresh Hooks
---------------------------------------------------------------------------
function ns.OnLayerChanged()
	local D = ns.DATA
	if not (ui.ready and D) then return end
	if not (ui.panel and ui.panel:IsVisible()) then
		ui.dirtyHidden = true
		return
	end
	ui.dirtyHidden = false
	local tab = ns.db and ns.db.panelTab or "layers"
	if tab == "layers" and not ui.found then
		local map = (ns.ViewZoneMap and ns.ViewZoneMap()) or ns.CurrentMap()
		wipe(ui.counts)
		if map then
			local idx = ns.PinsOnMap(map).idx
			for _, i in ipairs(idx) do ui.counts[D.cat[i]] = (ui.counts[D.cat[i]] or 0) + 1 end
		end
	end
	ns.BuildPanelItems()
	UpdateChromeLayout()
	ns.LayoutPanelRows()
end

local function TryTemplate(kind, name, parent, template)
	local ok, f = pcall(CreateFrame, kind, name, parent, template)
	return ok and f or nil
end

local function SetBackground(border, a, style)
	if not border then return end
	local bg = border.Bg
	if bg then
		if style and style.file then
			local wrap = style.tile and "REPEAT" or "CLAMP"
			bg:SetTexture(style.file, wrap, wrap)
			bg:SetTexCoord(0, 1, 0, 1)
			bg:SetHorizTile(style.tile or false)
			bg:SetVertTile(style.tile or false)
			bg:SetVertexColor(1, 1, 1, a)
		else
			bg:SetHorizTile(false)
			bg:SetVertTile(false)
			bg:SetColorTexture(0, 0, 0, a)
			bg:SetVertexColor(1, 1, 1, 1)
		end
	elseif border.SetBackdrop then
		local file = style and style.file
		border:SetBackdrop({
			bgFile = file or "Interface\\Buttons\\WHITE8X8",
			tile = (style and style.tile) or false,
			tileSize = 256,
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		if file then
			border:SetBackdropColor(1, 1, 1, a)
		else
			border:SetBackdropColor(0, 0, 0, a)
		end
	end
end
ns.ApplyDialogBackground = SetBackground

local function AbovePins()
	return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST") + 10
end

local function ComputeScreenResizeCaps()
	local chrome = ns.WorldMapChrome and ns.WorldMapChrome()
	local maxTotalW = MAP_MAX_W + CONTENT_MAX_W
	local maxBodyH = BODY_MAX_H
	if not chrome then return maxTotalW, maxBodyH end
	local chromeL = SafeNum(chrome:GetLeft())
	local chromeT = SafeNum(chrome:GetTop())
	local effScale = SafeNum(chrome:GetEffectiveScale())
	local uw = SafeNum(UIParent:GetWidth()) or 1365
	local us = SafeNum(UIParent:GetEffectiveScale()) or 1
	local uiW = uw * us
	if effScale and effScale > 0 then
		if chromeL then
			local fixedW = OUTER_PAD + SPLITTER_W + RAIL_W + RAIL_CONTENT_GAP + OUTER_PAD
			local availW = math.floor((uiW - 6) / effScale - chromeL - fixedW)
			maxTotalW = math.max(MAP_MIN_W + CONTENT_MIN_W, math.min(MAP_MAX_W + CONTENT_MAX_W, availW))
		end
		if chromeT then
			local fixedH = OUTER_PAD + NAV_BAR_H + NAV_GAP + OUTER_PAD
			local availH = math.floor(chromeT - (6 / effScale) - fixedH)
			maxBodyH = math.max(BODY_MIN_H, math.min(BODY_MAX_H, availH))
		end
	end
	return maxTotalW, maxBodyH
end

local function EnsureResizePreview()
	if ui.resizePreview or not WorldMapFrame then return ui.resizePreview end
	local p = CreateFrame("Frame", nil, WorldMapFrame)
	p:SetFrameStrata("DIALOG")
	p:SetFrameLevel(50)
	p:EnableMouse(false)

	local function CrispTex(parent, layer, subLevel, r, g, b, a)
		local t = parent:CreateTexture(nil, layer, nil, subLevel)
		t:SetColorTexture(r, g, b, a)
		t:SetVertexColor(1, 1, 1, 1)
		if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
		if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
		return t
	end

	local function AddOutline(parent, thickness, inset, subLevel, r, g, b, a)
		local top = CrispTex(parent, "BORDER", subLevel, r, g, b, a)
		top:SetHeight(thickness)
		top:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
		top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, -inset)
		local bot = CrispTex(parent, "BORDER", subLevel, r, g, b, a)
		bot:SetHeight(thickness)
		bot:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", inset, inset)
		bot:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
		local left = CrispTex(parent, "BORDER", subLevel, r, g, b, a)
		left:SetWidth(thickness)
		left:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -(inset + thickness))
		left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", inset, inset + thickness)
		local right = CrispTex(parent, "BORDER", subLevel, r, g, b, a)
		right:SetWidth(thickness)
		right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, -(inset + thickness))
		right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset + thickness)
	end

	local box = CreateFrame("Frame", nil, p)
	box:EnableMouse(false)
	local fill = CrispTex(box, "BACKGROUND", 0, 0.08, 0.06, 0.04, 0.14)
	fill:SetAllPoints()
	AddOutline(box, 2, 0, 2, 0.84, 0.68, 0.30, 0.92)
	AddOutline(box, 1, 2, 1, 0, 0, 0, 0.65)
	local guide = CrispTex(box, "ARTWORK", 1, 0.84, 0.68, 0.30, 0.55)
	guide:SetWidth(1)
	box.splitGuide = guide
	p.box = box

	local splitBar = CreateFrame("Frame", nil, p)
	splitBar:EnableMouse(false)
	splitBar:SetWidth(4)
	local sL = CrispTex(splitBar, "BACKGROUND", 0, 0, 0, 0, 0.70)
	sL:SetWidth(1)
	sL:SetPoint("TOPLEFT")
	sL:SetPoint("BOTTOMLEFT")
	local sM = CrispTex(splitBar, "ARTWORK", 1, 0.84, 0.68, 0.30, 0.92)
	sM:SetWidth(2)
	sM:SetPoint("TOP")
	sM:SetPoint("BOTTOM")
	local sR = CrispTex(splitBar, "BACKGROUND", 0, 0, 0, 0, 0.70)
	sR:SetWidth(1)
	sR:SetPoint("TOPRIGHT")
	sR:SetPoint("BOTTOMRIGHT")
	p.splitBar = splitBar

	p:Hide()
	ui.resizePreview = p
	return p
end

local function HideResizePreview()
	if ui.resizePreview then ui.resizePreview:Hide() end
end

local function UpdateResizePreview(mode, mw, cw, bh)
	local p = EnsureResizePreview()
	if not (p and WorldMapFrame) then return end
	local chromeL = L.CHROME_LEFT or -6
	local chromeT = L.CHROME_TOP or 6
	local mapL = L.MAP_LEFT_X or 6
	local stageTopY = L.STAGE_TOP_Y or -38
	local splitCenter = mapL + mw + math.floor(SPLITTER_W / 2)
	if mode == "split" then
		p.box:Hide()
		p.splitBar:ClearAllPoints()
		p.splitBar:SetPoint("TOP", WorldMapFrame, "TOPLEFT", splitCenter, TOP_CONTENT_Y)
		p.splitBar:SetPoint("BOTTOM", WorldMapFrame, "TOPLEFT", splitCenter, stageTopY - bh)
		p.splitBar:Show()
	else
		p.splitBar:Hide()
		p.box:ClearAllPoints()
		p.box:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", chromeL, chromeT)
		p.box:SetPoint("BOTTOMRIGHT", WorldMapFrame, "TOPLEFT",
			mapL + mw + SPLITTER_W + RAIL_W + RAIL_CONTENT_GAP + cw + OUTER_PAD,
			stageTopY - bh - OUTER_PAD)
		p.box.splitGuide:ClearAllPoints()
		p.box.splitGuide:SetPoint("TOP", p.box, "TOPLEFT", splitCenter - chromeL, -OUTER_PAD)
		p.box.splitGuide:SetPoint("BOTTOM", p.box, "BOTTOMLEFT", splitCenter - chromeL, OUTER_PAD)
		p.box:Show()
	end
	p:Show()
end

local function StopResize(btn, commit)
	if not resizeState.active then return end
	local activeBtn = btn or resizeState.btn
	local mode = resizeState.mode
	if mode == "split" and InCombatLockdown() then
		commit = false
	end
	local nextMW, nextCW, nextBH = resizeState.lastMapW, resizeState.lastContentW, resizeState.lastBodyH
	local changed = (nextMW ~= resizeState.startMapW)
		or (nextCW ~= resizeState.startContentW)
		or (nextBH ~= resizeState.startBodyH)
	resizeState.active = false
	resizeState.mode = nil
	resizeState.btn = nil
	resizeState.mapChanged = false
	ui.dragging = false
	if activeBtn then activeBtn:SetScript("OnUpdate", nil) end
	HideResizePreview()
	if commit and changed and ns.SetUnifiedWindowSize then
		local _, _, _, _, mapChanged = ns.SetUnifiedWindowSize(nextMW, nextCW, nextBH, true)
		if mapChanged and ns.CommitUnifiedMapResize then
			ns.CommitUnifiedMapResize(true)
		end
		if ui.detailsPane and ui.detailsPane:IsShown() then
			if ns.LayoutQuestDetailsPane then ns.LayoutQuestDetailsPane() end
		elseif ns.LayoutPanelRows then
			ns.LayoutPanelRows()
		end
	end
end

local function OnResizeUpdate(self)
	if not resizeState.active or (IsMouseButtonDown and not IsMouseButtonDown("LeftButton")) then
		StopResize(self, true)
		return
	end
	local cx, cy = GetCursorPosition()
	local effScale = (ui.panel and SafeNum(ui.panel:GetEffectiveScale())) or 1
	if effScale <= 0 then effScale = 1 end
	local dx = (cx - resizeState.startX) / effScale
	local dy = (resizeState.startY - cy) / effScale
	local maxTotalW, maxBodyH = ComputeScreenResizeCaps()
	local nextMapW = resizeState.lastMapW
	local nextContentW = resizeState.lastContentW
	local nextBodyH = resizeState.lastBodyH

	if resizeState.mode == "split" then
		if InCombatLockdown() then
			StopResize(self, false)
			return
		end
		local totalW = resizeState.startMapW + resizeState.startContentW
		local maxMapForSplit = math.min(MAP_MAX_W, totalW - CONTENT_MIN_W)
		local minMapForSplit = math.max(MAP_MIN_W, totalW - CONTENT_MAX_W)
		if maxMapForSplit >= minMapForSplit then
			nextMapW = math.max(minMapForSplit, math.min(maxMapForSplit, math.floor(resizeState.startMapW + dx + 0.5)))
			nextContentW = totalW - nextMapW
		end
	else
		if InCombatLockdown() then
			nextMapW = resizeState.startMapW
			nextBodyH = resizeState.startBodyH
			local maxCW = math.max(CONTENT_MIN_W, math.min(CONTENT_MAX_W, maxTotalW - nextMapW))
			local wantTotalW = math.floor(resizeState.startMapW + resizeState.startContentW + dx + 0.5)
			nextContentW = math.max(CONTENT_MIN_W, math.min(maxCW, wantTotalW - nextMapW))
		else
			local startTotalW = resizeState.startMapW + resizeState.startContentW
			local wantTotalW = math.max(MAP_MIN_W + CONTENT_MIN_W, math.min(maxTotalW, math.floor(startTotalW + dx + 0.5)))
			local effDx = wantTotalW - startTotalW
			nextMapW = math.max(MAP_MIN_W, math.min(MAP_MAX_W, math.floor(resizeState.startMapW + effDx * 0.57 + 0.5)))
			nextContentW = wantTotalW - nextMapW
			if nextContentW < CONTENT_MIN_W then
				nextContentW = CONTENT_MIN_W
				nextMapW = math.max(MAP_MIN_W, math.min(MAP_MAX_W, wantTotalW - nextContentW))
			elseif nextContentW > CONTENT_MAX_W then
				nextContentW = CONTENT_MAX_W
				nextMapW = math.max(MAP_MIN_W, math.min(MAP_MAX_W, wantTotalW - nextContentW))
			end
			nextBodyH = math.max(BODY_MIN_H, math.min(maxBodyH, math.floor(resizeState.startBodyH + dy + 0.5)))
		end
	end

	if nextMapW ~= resizeState.lastMapW or nextContentW ~= resizeState.lastContentW or nextBodyH ~= resizeState.lastBodyH then
		resizeState.lastMapW = nextMapW
		resizeState.lastContentW = nextContentW
		resizeState.lastBodyH = nextBodyH
		UpdateResizePreview(resizeState.mode, nextMapW, nextContentW, nextBodyH)
	end
end

local function StartResize(btn, mode)
	if not (ui.panel and ns.GetUnifiedWindowSize) then return end
	if mode == "split" and InCombatLockdown() then return end
	if resizeState.active then StopResize(resizeState.btn, false) end
	local cx, cy = GetCursorPosition()
	local mw, mh, cw, bh = ns.GetUnifiedWindowSize()
	resizeState.active = true
	resizeState.mode = mode or "corner"
	resizeState.btn = btn
	resizeState.startX = cx
	resizeState.startY = cy
	resizeState.startMapW = mw
	resizeState.startMapH = mh
	resizeState.startContentW = cw
	resizeState.startBodyH = bh
	resizeState.lastMapW = mw
	resizeState.lastMapH = mh
	resizeState.lastContentW = cw
	resizeState.lastBodyH = bh
	resizeState.mapChanged = false
	ui.dragging = true
	UpdateResizePreview(resizeState.mode, mw, cw, bh)
	btn:SetScript("OnUpdate", OnResizeUpdate)
end

local function AnchorPanelToChrome()
	if not (ui.panel and WorldMapFrame) then return end
	local chrome = ns.WorldMapChrome and ns.WorldMapChrome()
	local lvl = AbovePins()
	ui.panel:SetFrameStrata(WorldMapFrame:GetFrameStrata() or "MEDIUM")
	ui.panel:SetFrameLevel(lvl)
	if ui.splitter then ui.splitter:SetFrameLevel(lvl + 8) end
	if ui.resizeBtn then ui.resizeBtn:SetFrameLevel(lvl + 10) end
	ui.panel:ClearAllPoints()
	if chrome then
		ui.panel:SetAllPoints(chrome)
	else
		ui.panel:SetAllPoints(WorldMapFrame)
	end
	if ui.pinBtn and ui.pinBtn.SetActive and ns.PinModeActive then
		ui.pinBtn:SetActive(ns.PinModeActive())
	end
	if ui.styleBtn and ui.styleBtn.SetActive and ns.IsStyleDialogOpen then
		ui.styleBtn:SetActive(ns.IsStyleDialogOpen())
	end
end
ns.SyncPanelDock = AnchorPanelToChrome

function ns.ResetPanelPosition(keepPos)
	if resizeState.active then
		StopResize(resizeState.btn, false)
	end
	if ns.ResetUnifiedLayout then
		ns.ResetUnifiedLayout(keepPos)
	elseif ns.db then
		ns.db.mapW = nil
		ns.db.contentW = nil
		ns.db.bodyH = nil
		ns.db.panelPos = nil
		ns.db.panelW = nil
		ns.db.panelH = nil
	end
	AnchorPanelToChrome()
	if ui.detailsPane and ui.detailsPane:IsShown() then
		if ns.LayoutQuestDetailsPane then ns.LayoutQuestDetailsPane() end
	elseif ns.LayoutPanelRows then
		ns.LayoutPanelRows()
	end
end

function ns.ApplyPanelStyle()
	if not ns.db then return end
	local a = math.max(0.2, math.min(1.0, ns.db.background or 0.8))
	local style = ns.BackgroundStyle and ns.BackgroundStyle(ns.db.backgroundStyle) or { key = "dark", name = "Dark" }
	local scale = math.max(0.5, math.min(1.5, ns.db.panelScale or 1.0))
	SetBackground(ns.styleDialogBorder, a, style)
	if ns.ApplyMapChromeStyle then ns.ApplyMapChromeStyle(a, style) end
	if ns.ApplyDetailsStyle then ns.ApplyDetailsStyle(a, style) end
	if ns.ApplyUnifiedScale then ns.ApplyUnifiedScale(scale) end
	if not ui.panel then return end
	local railA, listA
	if style.key == "marble" then
		railA, listA = 0.50, 0.48
	elseif style.key == "dialog" then
		railA, listA = 0.24, 0.18
	else
		railA, listA = 0.10, 0.08
	end
	if ui.leftRail then
		ui.leftRail:SetBackdropColor(0.03, 0.03, 0.05, railA)
	end
	if ui.listBg then
		ui.listBg:SetColorTexture(0, 0, 0, listA)
	end
	local curScale = SafeNum(ui.panel:GetScale()) or 1
	if math.abs(curScale - 1) > 0.001 then
		ui.panel:SetScale(1)
	end
end

function ns.SyncStyleButton()
	if ui.styleBtn and ui.styleBtn.SetActive and ns.IsStyleDialogOpen then
		ui.styleBtn:SetActive(ns.IsStyleDialogOpen())
	end
end

function ns.SyncPanelScrollBar(scrollPx, listH, totalH)
	if ui.detailsPane and ui.detailsPane:IsShown() then return end
	local sb = ui.scrollBar
	if not sb then return end
	local maxScroll = math.max(0, (totalH or 0) - (listH or 0))
	local showScroll = maxScroll > 1 and listH ~= nil and listH > 0 and totalH ~= nil and totalH > 0
	local wantInset = showScroll and (LIST_PAD + SCROLL_GUTTER) or LIST_PAD
	if ui.list and ui.listTopY and ui.listRightInset ~= wantInset then
		ui.listRightInset = wantInset
		ui.list:ClearAllPoints()
		ui.list:SetPoint("TOPLEFT", LIST_PAD, ui.listTopY)
		ui.list:SetPoint("BOTTOMRIGHT", -wantInset, LIST_PAD)
	end
	ui.syncingScroll = true
	if ui.nativeScrollBar then
		if not showScroll then
			sb:SetVisibleExtentPercentage(1)
			sb:SetScrollPercentage(0, true)
		else
			local visPct = math.max(0.05, math.min(0.99, listH / totalH))
			local panPct = math.max(0.01, math.min(0.5, 48 / maxScroll))
			sb:SetPanExtentPercentage(panPct)
			sb:SetVisibleExtentPercentage(visPct)
			sb:SetScrollPercentage(math.max(0, math.min(1, (scrollPx or 0) / maxScroll)), true)
		end
	else
		ui.scrollTrack:SetShown(showScroll)
		ui.scrollThumb:SetShown(showScroll)
		if showScroll then
			local trackH = ui.scrollTrack:GetHeight()
			if trackH and trackH > 0 then
				local thumbH = math.max(22, math.min(trackH, math.floor(trackH * (listH / totalH) + 0.5)))
				local free = math.max(0, trackH - thumbH)
				local pct = math.max(0, math.min(1, (scrollPx or 0) / maxScroll))
				ui.scrollThumb:SetHeight(thumbH)
				ui.scrollThumb:ClearAllPoints()
				ui.scrollThumb:SetPoint("TOP", ui.scrollTrack, "TOP", 0, -math.floor(free * pct + 0.5))
			end
		end
	end
	ui.syncingScroll = false
end

function ns.IsPanelDockedInside()
	return false
end

function ns.PanelFrame()
	return ui.panel
end

function ns.UpdatePanel()
	if not ui.panel then return end
	ui.panel:Show()
end

local function RefreshControls()
	if not ui.ready then return end
	UpdateChromeLayout()
	ns.LayoutPanelRows()
end
ns.RefreshControls = RefreshControls

---------------------------------------------------------------------------
-- Widget Helpers & Horizontal-Split Panel Construction
---------------------------------------------------------------------------
local function ToolbarIconButton(parent, texturePath, tipTitle, tipBody, onClick, rightClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(22, 22)
	if rightClick then
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	else
		b:RegisterForClicks("LeftButtonUp")
	end
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("CENTER")
	b.icon:SetSize(18, 18)
	b.icon:SetTexture(texturePath)
	b.icon:SetAlpha(0.78)
	b.activeGlow = b:CreateTexture(nil, "OVERLAY")
	b.activeGlow:SetPoint("CENTER")
	b.activeGlow:SetSize(18, 18)
	b.activeGlow:SetTexture(texturePath)
	b.activeGlow:SetBlendMode("ADD")
	b.activeGlow:SetAlpha(0.35)
	b.activeGlow:Hide()
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetPoint("CENTER")
	hl:SetSize(18, 18)
	hl:SetTexture(texturePath)
	hl:SetBlendMode("ADD")
	hl:SetAlpha(0.45)
	function b:SetActive(on)
		local active = on == true
		self.icon:SetAlpha(active and 1 or 0.78)
		self.activeGlow:SetShown(active)
	end
	b:SetScript("OnClick", function(_, button) onClick(button) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(tipTitle, 1, .82, .2)
		GameTooltip:AddLine(tipBody, .9, .9, .9, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	return b
end

local function SmallPillButton(parent, label, width, onClick, tip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 21)
	local capW = 11
	b.frame = ns.AddBrassPillSlices(b, "BACKGROUND", capW, nil, 0.96, 0.92, 0.86, 0.72)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("CENTER", 0, 0)
	b.text:SetText(label)
	b.hl = ns.AddBrassPillSlices(b, "HIGHLIGHT", capW, "ADD", 0.35)
	b:SetScript("OnClick", function(self, button)
		if self.isDisabled then return end
		onClick(self, button)
	end)
	if tip then
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(ns.StripCodes and ns.StripCodes(b.text:GetText() or "") or (b.text:GetText() or ""), 1, .82, .2)
			GameTooltip:AddLine(tip, .9, .9, .9, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
	end
	return b
end

function ns.InitPanel()
	local panel = CreateFrame("Frame", nil, WorldMapFrame)
	ui.panel = panel
	panel:EnableMouse(false)
	AnchorPanelToChrome()
	local level = panel:GetFrameLevel()

	-- Bottom-right 2D resize grip: grows/shrinks map within its min/max bounds and overflows into the right panel.
	local resizeBtn = CreateFrame("Button", nil, panel)
	ui.resizeBtn = resizeBtn
	resizeBtn:SetSize(14, 14)
	resizeBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
	resizeBtn:SetFrameLevel(level + 10)
	resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resizeBtn:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then StartResize(self, "corner") end
	end)
	resizeBtn:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then
			StopResize(self, true)
		elseif button == "Button4" and ns.GoBack then
			ns.GoBack()
		end
	end)
	resizeBtn:SetScript("OnDoubleClick", function(self, button)
		if button ~= "LeftButton" then return end
		StopResize(self, false)
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.ResetPanelPosition(true)
	end)
	resizeBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Resize Window", 1, .82, .2)
		GameTooltip:AddLine("Drag to resize both the map and right panel (the map scales to fit within its min/max bounds while further resizing grows the right panel).\nDouble-click to reset to default size.", .9, .9, .9, true)
		GameTooltip:Show()
	end)
	resizeBtn:SetScript("OnLeave", GameTooltip_Hide)

	-----------------------------------------------------------------------
	-- Right Visual Content Pane (anchored after Map + Splitter + Tab Rail)
	-----------------------------------------------------------------------
	local content = CreateFrame("Frame", nil, panel)
	ui.content = content
	content:EnableMouse(true)
	content:EnableMouseWheel(true)
	content:SetScript("OnMouseUp", function(_, button)
		if button == "Button4" then ns.GoBack() end
	end)
	if ns.AttachWindowDrag then ns.AttachWindowDrag(content) end
	local spacer = WorldMapFrame and WorldMapFrame.TitleCanvasSpacerFrame
	if spacer then
		content:SetPoint("TOPLEFT", spacer, "TOPRIGHT", SPLITTER_W + RAIL_W + RAIL_CONTENT_GAP, TOP_CONTENT_Y)
	else
		content:SetPoint("TOPLEFT", panel, "TOPLEFT", OUTER_PAD + MAP_MIN_W + SPLITTER_W + RAIL_W + RAIL_CONTENT_GAP, -OUTER_PAD)
	end
	content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -OUTER_PAD, OUTER_PAD)

	-----------------------------------------------------------------------
	-- Middle Skill-Icon Tab Rail (`Base`, `Tracker`, `Zone`, `Dungeon`)
	-- Anchored flush to `content`'s left edge so it tracks all resizes automatically.
	-----------------------------------------------------------------------
	local leftRail = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	ui.leftRail = leftRail
	leftRail:EnableMouse(true)
	leftRail:EnableMouseWheel(true)
	leftRail:SetScript("OnMouseUp", function(_, button)
		if button == "Button4" then ns.GoBack() end
	end)
	if ns.AttachWindowDrag then ns.AttachWindowDrag(leftRail) end
	leftRail:SetWidth(RAIL_W)
	leftRail:SetPoint("TOPRIGHT", content, "TOPLEFT", -RAIL_CONTENT_GAP, 0)
	leftRail:SetPoint("BOTTOMRIGHT", content, "BOTTOMLEFT", -RAIL_CONTENT_GAP, 0)
	leftRail:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	leftRail:SetBackdropColor(0.03, 0.03, 0.05, 0.50)
	leftRail:SetBackdropBorderColor(0.35, 0.28, 0.18, 0.55)

	local slotTex = ns.MEDIA .. "slot"
	for idx, td in ipairs(TAB_DEFS) do
		local b = CreateFrame("Button", nil, leftRail)
		b:SetSize(34, 34)
		if idx == 1 then
			b:SetPoint("TOP", leftRail, "TOP", 0, -6)
		else
			b:SetPoint("TOP", ui.tabs[TAB_DEFS[idx - 1].key], "BOTTOM", 0, -6)
		end
		b:RegisterForClicks("LeftButtonUp", "Button4Up")

		b.frame = b:CreateTexture(nil, "BACKGROUND")
		b.frame:SetAllPoints()
		b.frame:SetTexture(slotTex)
		b.frame:SetVertexColor(0.76, 0.70, 0.56, 0.90)

		b.activeGlow = b:CreateTexture(nil, "BORDER")
		b.activeGlow:SetAllPoints()
		b.activeGlow:SetTexture(slotTex)
		b.activeGlow:SetBlendMode("ADD")
		b.activeGlow:SetAlpha(0.28)
		b.activeGlow:Hide()

		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(22, 22)
		b.icon:SetPoint("CENTER", 0, 0)
		b.icon:SetTexture(ns.MEDIA .. td.icon)
		b.icon:SetAlpha(0.76)

		b.activeBar = b:CreateTexture(nil, "OVERLAY")
		b.activeBar:SetWidth(3)
		b.activeBar:SetPoint("TOPLEFT", -4, -3)
		b.activeBar:SetPoint("BOTTOMLEFT", -4, 3)
		b.activeBar:SetColorTexture(1, 0.84, 0.25, 1)
		b.activeBar:Hide()

		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetTexture(slotTex)
		hl:SetBlendMode("ADD")
		hl:SetAlpha(0.35)

		b:SetScript("OnClick", function(_, button)
			if button == "Button4" then
				ns.GoBack()
				return
			end
			ns.SelectSidebarTab(td.key)
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(td.label, 1, .82, .2)
			GameTooltip:AddLine(td.tip, .9, .9, .9, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		ui.tabs[td.key] = b
	end

	-- Vertical divider handle between the left Map Column and middle Tab Rail (drag left/right to trade width).
	local splitter = CreateFrame("Button", nil, panel)
	ui.splitter = splitter
	splitter:SetWidth(SPLITTER_W)
	splitter:SetPoint("TOPRIGHT", leftRail, "TOPLEFT", 0, 0)
	splitter:SetPoint("BOTTOMRIGHT", leftRail, "BOTTOMLEFT", 0, 0)
	splitter:SetFrameLevel(level + 8)
	local splitLine = splitter:CreateTexture(nil, "ARTWORK")
	splitLine:SetWidth(1)
	splitLine:SetPoint("TOP", 0, -4)
	splitLine:SetPoint("BOTTOM", 0, 4)
	splitLine:SetColorTexture(0.55, 0.44, 0.24, 0.28)
	local splitHL = splitter:CreateTexture(nil, "HIGHLIGHT")
	splitHL:SetWidth(2)
	splitHL:SetPoint("TOP", 0, -4)
	splitHL:SetPoint("BOTTOM", 0, 4)
	splitHL:SetColorTexture(1, 0.84, 0.25, 0.72)
	splitter:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then StartResize(self, "split") end
	end)
	splitter:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then
			StopResize(self, true)
		elseif button == "Button4" and ns.GoBack then
			ns.GoBack()
		end
	end)
	splitter:SetScript("OnDoubleClick", function(self, button)
		if button ~= "LeftButton" then return end
		StopResize(self, false)
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.ResetPanelPosition(true)
	end)
	splitter:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Resize Map / Panel Split", 1, .82, .2)
		GameTooltip:AddLine("Drag left or right to adjust the balance between the map and right panel.\nDouble-click to reset to default size.", .9, .9, .9, true)
		GameTooltip:Show()
	end)
	splitter:SetScript("OnLeave", GameTooltip_Hide)

	ui.styleBtn = ToolbarIconButton(content, ns.MEDIA .. "gear", "Map Settings", "Customize Map Tracking & Filters, Window scale, Pin size, Background opacity, and Background style.", function()
		if ns.ToggleStyleDialog then ns.ToggleStyleDialog() end
	end)
	ui.styleBtn:SetPoint("TOPRIGHT", -LIST_PAD - 22, -2)

	ui.pinBtn = ToolbarIconButton(content, ns.MEDIA .. "waypoint", "Drop Waypoint", "Left-click: arm map pin placement (or Ctrl-click the map anytime).\nRight-click: clear active waypoint.", function(button)
		ns.TogglePinMode(button == "RightButton")
		RefreshControls()
	end, true)
	ui.pinBtn:SetPoint("RIGHT", ui.styleBtn, "LEFT", -4, 0)
	local origPinSetActive = ui.pinBtn.SetActive
	function ui.pinBtn:SetActive(on)
		origPinSetActive(self, on)
		if on then
			if self:GetScript("OnUpdate") ~= PollPinMode then
				self:SetScript("OnUpdate", PollPinMode)
			end
		else
			if self:GetScript("OnUpdate") ~= nil then
				self:SetScript("OnUpdate", nil)
			end
		end
	end

	ui.findBtn = ToolbarIconButton(content, ns.MEDIA .. "findme", "Find Me", "Glide the map to your character's current position.", function()
		ns.FindPlayer()
	end)
	ui.findBtn:SetPoint("RIGHT", ui.pinBtn, "LEFT", -4, 0)

	local backBtn = CreateFrame("Button", nil, content)
	ui.backBtn = backBtn
	backBtn:SetSize(22, 22)
	backBtn:SetPoint("TOPLEFT", LIST_PAD, -2)
	backBtn:RegisterForClicks("LeftButtonUp", "Button4Up")
	backBtn.icon = backBtn:CreateTexture(nil, "ARTWORK")
	backBtn.icon:SetPoint("CENTER")
	backBtn.icon:SetSize(18, 18)
	backBtn.icon:SetTexture(ns.MEDIA .. "back")
	backBtn.icon:SetAlpha(0.85)
	backBtn.activeGlow = backBtn:CreateTexture(nil, "OVERLAY")
	backBtn.activeGlow:SetPoint("CENTER")
	backBtn.activeGlow:SetSize(18, 18)
	backBtn.activeGlow:SetTexture(ns.MEDIA .. "back")
	backBtn.activeGlow:SetBlendMode("ADD")
	backBtn.activeGlow:SetAlpha(0.35)
	backBtn.activeGlow:Hide()
	backBtn.hl = backBtn:CreateTexture(nil, "HIGHLIGHT")
	backBtn.hl:SetPoint("CENTER")
	backBtn.hl:SetSize(18, 18)
	backBtn.hl:SetTexture(ns.MEDIA .. "back")
	backBtn.hl:SetBlendMode("ADD")
	backBtn.hl:SetAlpha(0.45)
	backBtn:SetScript("OnClick", function(self)
		if self.isDisabled then return end
		ns.GoBack()
		if GameTooltip:IsShown() and GameTooltip:GetOwner() == self then
			local onEnter = self:GetScript("OnEnter")
			if onEnter then onEnter(self) end
		end
	end)
	backBtn:SetScript("OnEnter", function(self)
		local _, tTitle, tBody = ns.DescribeBackTarget()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(tTitle, 1, .82, .2)
		GameTooltip:AddLine(tBody, .9, .9, .9, true)
		GameTooltip:Show()
	end)
	backBtn:SetScript("OnLeave", GameTooltip_Hide)

	local search = CreateFrame("EditBox", nil, content, "SearchBoxTemplate")
	ui.search = search
	search:SetHeight(20)
	search:SetPoint("LEFT", backBtn, "RIGHT", 9, 0)
	search:SetPoint("RIGHT", ui.findBtn, "LEFT", -6, 0)
	search:HookScript("OnTextChanged", ns.RunSearch)

	local layerBar = CreateFrame("Frame", nil, content, "BackdropTemplate")
	ui.layerBar = layerBar
	layerBar:SetHeight(30)
	layerBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	layerBar:SetBackdropColor(0.11, 0.10, 0.07, 0.92)
	layerBar:SetBackdropBorderColor(0.68, 0.54, 0.25, 0.85)
	layerBar.actionBtn = SmallPillButton(layerBar, "|cffe8d8a8Clear|r", 62, function(self)
		if self.mode == "search" then
			ns.SetSearchQuiet("")
			ns.OnLayerChanged()
		elseif self.mode == "unfocus" then
			ns.ClearQuestFocus()
		end
	end, "Clear search or focused quest filter.")
	layerBar.actionBtn:SetPoint("RIGHT", -6, 0)
	layerBar.label = layerBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	layerBar.label:SetPoint("LEFT", 10, 0)
	layerBar.label:SetPoint("RIGHT", layerBar.actionBtn, "LEFT", -8, 0)
	layerBar.label:SetJustifyH("LEFT")
	layerBar.label:SetWordWrap(false)
	layerBar:Hide()

	local zoneBar = CreateFrame("StatusBar", nil, content, "BackdropTemplate")
	ui.zoneBar = zoneBar
	zoneBar:SetHeight(22)
	zoneBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	zoneBar:SetStatusBarColor(0.28, 0.68, 0.34, 0.85)
	zoneBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	zoneBar:SetBackdropColor(0.05, 0.05, 0.07, 0.9)
	zoneBar:SetBackdropBorderColor(0.5, 0.4, 0.22, 0.85)
	zoneBar.right = zoneBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	zoneBar.right:SetPoint("RIGHT", -8, 0)
	zoneBar.right:SetJustifyH("RIGHT")
	zoneBar.left = zoneBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	zoneBar.left:SetPoint("LEFT", 8, 0)
	zoneBar.left:SetPoint("RIGHT", zoneBar.right, "LEFT", -6, 0)
	zoneBar.left:SetJustifyH("LEFT")
	zoneBar.left:SetWordWrap(false)
	zoneBar:Hide()

	ui.divider = content:CreateTexture(nil, "ARTWORK")
	ui.divider:SetColorTexture(1, 1, 1, 0.14)
	ui.divider:SetHeight(1)

	local list = CreateFrame("Frame", nil, content)
	ui.list = list
	list:SetClipsChildren(true)
	list:EnableMouse(true)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseUp", function(_, button)
		if button == "Button4" then ns.GoBack() end
	end)
	list:SetScript("OnMouseWheel", function(_, delta)
		ui.scrollPx = (ui.scrollPx or 0) - delta * 48
		ns.RenderPanelRows()
		if ui.lastKey then ui.scrollByKey[ui.lastKey] = ui.scrollPx end
	end)
	local listBg = list:CreateTexture(nil, "BACKGROUND")
	listBg:SetColorTexture(0, 0, 0, 0.08)
	listBg:SetAllPoints()
	ui.listBg = listBg
	list:SetScript("OnSizeChanged", ns.LayoutPanelRows)

	-- Right-side Blizzard MinimalScrollBar (same scrollbar as Dave's Sack's ScrollFrameTemplate),
	-- with a slim draggable-thumb fallback if the template isn't available.
	local sb = TryTemplate("EventFrame", nil, content, "MinimalScrollBar")
	if sb and sb.RegisterCallback and sb.SetVisibleExtentPercentage then
		ui.scrollBar = sb
		ui.nativeScrollBar = true
		sb:SetPoint("TOPLEFT", list, "TOPRIGHT", 4, -2)
		sb:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 4, 2)
		if sb.SetHideIfUnscrollable then sb:SetHideIfUnscrollable(true) end
		sb:RegisterCallback("OnScroll", function(_, pct)
			if ui.syncingScroll then return end
			local listH = list:GetHeight() or 0
			local maxScroll = math.max(0, (ui.totalH or 0) - listH)
			ui.scrollPx = math.max(0, math.min(maxScroll, (pct or 0) * maxScroll))
			if ui.lastKey then ui.scrollByKey[ui.lastKey] = ui.scrollPx end
			ns.RenderPanelRows()
		end, list)
	else
		local track = content:CreateTexture(nil, "ARTWORK")
		track:SetWidth(4)
		track:SetPoint("TOP", list, "TOPRIGHT", 8, -2)
		track:SetPoint("BOTTOM", list, "BOTTOMRIGHT", 8, 2)
		track:SetColorTexture(1, 1, 1, 0.14)
		local thumb = CreateFrame("Button", nil, content)
		thumb:SetWidth(10)
		thumb:SetFrameLevel(content:GetFrameLevel() + 6)
		local tt = thumb:CreateTexture(nil, "ARTWORK")
		tt:SetPoint("TOP"); tt:SetPoint("BOTTOM"); tt:SetWidth(4)
		tt:SetColorTexture(0.55, 0.55, 0.58, 0.95)
		local th = thumb:CreateTexture(nil, "HIGHLIGHT")
		th:SetPoint("TOP"); th:SetPoint("BOTTOM"); th:SetWidth(4)
		th:SetColorTexture(1, 0.82, 0, 0.6)
		local function DragThumb(self)
			if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
				self:SetScript("OnUpdate", nil)
				return
			end
			local _, cy = GetCursorPosition()
			cy = cy / self:GetEffectiveScale()
			local free = (track:GetHeight() or 0) - (self:GetHeight() or 0)
			local maxScroll = math.max(0, (ui.totalH or 0) - (list:GetHeight() or 0))
			if free > 0 and maxScroll > 0 then
				ui.scrollPx = math.max(0, math.min(maxScroll, self.startScroll + (self.startY - cy) * maxScroll / free))
				if ui.lastKey then ui.scrollByKey[ui.lastKey] = ui.scrollPx end
				ns.RenderPanelRows()
			end
		end
		thumb:SetScript("OnMouseDown", function(self)
			local _, cy = GetCursorPosition()
			self.startY = cy / self:GetEffectiveScale()
			self.startScroll = ui.scrollPx or 0
			self:SetScript("OnUpdate", DragThumb)
		end)
		thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
		thumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
		ui.scrollBar = thumb
		ui.scrollTrack = track
		ui.scrollThumb = thumb
		ui.nativeScrollBar = false
		track:Hide()
		thumb:Hide()
	end

	if ns.InitQuestDetailsPane then
		ns.InitQuestDetailsPane(content)
	end

	ui.ready = true
	panel:SetScript("OnShow", function()
		AnchorPanelToChrome()
		if ui.dirtyHidden or #ui.items == 0 or ui.detailQuestID then
			ns.OnLayerChanged()
		else
			RefreshControls()
		end
	end)
	panel:SetScript("OnHide", function()
		if resizeState.active then StopResize(resizeState.btn, false) end
		if ui.pinBtn then ui.pinBtn:SetActive(false) end
		if ns.DisarmPinMode then ns.DisarmPinMode() end
		if ns.HideStyleDialog then ns.HideStyleDialog() end
	end)
	ns.ApplyPanelStyle()
	ns.UpdatePanel()
	if panel:IsVisible() then ns.OnLayerChanged() end
end
