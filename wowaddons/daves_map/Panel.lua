-- daves_map / Panel.lua
-- Horizontal-split Dave's Map frame beside Blizzard's World Map:
--   * HUD Edit Mode dialog chrome (`DialogBorderTranslucentTemplate`) with the same styling options
--     as daves_sack (`Window scale`, `Background` opacity, `Background style`).
--   * Left-side tab rail (`Layers`, `Zone`, `Dungeon` + `< Back`).
--   * Right-side visual content pane (search + Find Me + Waypoint + Window Style gear, Search / Focus bar,
--     Zone progress bar, and clipped variable-height virtualized list with native MinimalScrollBar).

local _, ns = ...

local ui = ns.PanelUI
local C = ns.PANEL_CONST
local WIDTH, MIN_H, RAIL_W, LIST_PAD, SCROLL_GUTTER = C.WIDTH, C.MIN_H or 380, C.RAIL_W, C.LIST_PAD, C.SCROLL_GUTTER
local Sound = ns.Sound

local TAB_DEFS = {
	{
		key = "layers",
		label = "Base",
		icon = "tab_base",
		tip = "Toggle base POI map icons (flight masters, townsfolk, rares, treasures) and adjust Map Settings.",
	},
	{
		key = "tracker",
		label = "Tracker",
		icon = "tab_tracker",
		tip = "View your Focused, Ready to Turn In, Pinned, and Tracking quests with chain steps, starters, and rewards. Tracked quest pins stay visible on the map at every zoom level.",
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
		ui.backBtn:SetAlpha(canBack and 1 or 0.42)
		if ui.backBtn.hl then ui.backBtn.hl:SetAlpha(canBack and 0.35 or 0) end
		ui.backBtn.activeBg:SetShown(canBack and (ns.IsDungeonViewShown and ns.IsDungeonViewShown() or false))
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

	if not searching and tab == "zone" then
		ui.zoneBar:ClearAllPoints()
		ui.zoneBar:SetPoint("TOPLEFT", LIST_PAD, curY)
		ui.zoneBar:SetPoint("TOPRIGHT", -LIST_PAD, curY)
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
	local needScroll = listH > 0 and (ui.totalH or 0) > (listH + 1)
	local rightInset = needScroll and (LIST_PAD + SCROLL_GUTTER) or LIST_PAD
	ui.listTopY = curY - 5
	ui.listRightInset = rightInset
	ui.list:ClearAllPoints()
	ui.list:SetPoint("TOPLEFT", LIST_PAD, ui.listTopY)
	ui.list:SetPoint("BOTTOMRIGHT", -rightInset, LIST_PAD)
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

local function SaveFreeLayout(panel)
	if not (panel and ns.db) then return end
	local w = math.max(WIDTH, math.floor((panel:GetWidth() or WIDTH) + 0.5))
	local h = math.max(MIN_H, math.floor((panel:GetHeight() or MIN_H) + 0.5))
	ns.db.panelW = w
	ns.db.panelH = h
	local l, t = panel:GetLeft(), panel:GetTop()
	local ps = panel:GetEffectiveScale()
	local us = UIParent:GetEffectiveScale()
	if l and t and ps and us and us > 0 then
		ns.db.panelPos = {
			x = math.floor(l * ps / us + 0.5),
			y = math.floor(t * ps / us + 0.5),
		}
	end
end

local function RestoreFreeLayout(panel)
	if not (panel and ns.db and ns.db.panelPos) then return false end
	local pos = ns.db.panelPos
	if type(pos.x) ~= "number" or type(pos.y) ~= "number" then return false end
	local ps = panel:GetEffectiveScale()
	local us = UIParent:GetEffectiveScale()
	if not (ps and ps > 0 and us and us > 0) then return false end
	local w = math.max(WIDTH, ns.db.panelW or WIDTH)
	local h = math.max(MIN_H, ns.db.panelH or (WorldMapFrame and WorldMapFrame:GetHeight()) or 540)
	panel:ClearAllPoints()
	panel:SetSize(w, h)
	panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x * us / ps, pos.y * us / ps)
	ui.docked = "free"
	return true
end

local function DetachForDragOrResize(panel)
	if not panel or ui.docked == "free" then return end
	local l, t = panel:GetLeft(), panel:GetTop()
	local w = math.max(WIDTH, panel:GetWidth() or WIDTH)
	local h = math.max(MIN_H, panel:GetHeight() or MIN_H)
	panel:ClearAllPoints()
	panel:SetSize(w, h)
	if l and t then
		panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER")
	end
	ui.docked = "free"
end

local function BeginPanelMove(panel)
	if not panel or (panel:IsProtected() and InCombatLockdown()) then return end
	DetachForDragOrResize(panel)
	ui.dragging = true
	panel:StartMoving()
end

local function BeginPanelResize(panel)
	if not panel or (panel:IsProtected() and InCombatLockdown()) then return end
	DetachForDragOrResize(panel)
	local ps = panel:GetEffectiveScale() or 1
	local us = UIParent:GetEffectiveScale() or 1
	local ratio = (ps > 0) and (us / ps) or 1
	local maxW = math.max(WIDTH, math.floor((UIParent:GetWidth() or 1600) * 0.92 * ratio))
	local maxH = math.max(MIN_H, math.floor((UIParent:GetHeight() or 900) * 0.92 * ratio))
	if panel.SetResizeBounds then
		panel:SetResizeBounds(WIDTH, MIN_H, maxW, maxH)
	end
	ui.dragging = true
	panel:StartSizing("BOTTOMRIGHT")
end

local function EndPanelDragOrResize(panel)
	if not (panel and ui.dragging) then return end
	ui.dragging = false
	panel:StopMovingOrSizing()
	local w = math.max(WIDTH, panel:GetWidth() or WIDTH)
	local h = math.max(MIN_H, panel:GetHeight() or MIN_H)
	panel:SetSize(w, h)
	SaveFreeLayout(panel)
	RestoreFreeLayout(panel)
	if ns.LayoutPanelRows then ns.LayoutPanelRows() end
end

local function Dock()
	if not ui.panel or ui.dragging then return end
	if ui.pinBtn and ui.pinBtn.SetActive and ns.PinModeActive then
		ui.pinBtn:SetActive(ns.PinModeActive())
	end
	if ui.styleBtn and ui.styleBtn.SetActive and ns.IsStyleDialogOpen then
		ui.styleBtn:SetActive(ns.IsStyleDialogOpen())
	end
	if ns.db and ns.db.panelPos then
		if ui.docked ~= "free" then
			RestoreFreeLayout(ui.panel)
		end
		return
	end
	local effW = math.max(WIDTH, (ns.db and ns.db.panelW) or WIDTH)
	local s = ui.panel:GetScale() or 1
	local room = (effW * s) + 4
	local where
	if WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized() then
		where = "inside"
	elseif (WorldMapFrame:GetLeft() or 0) >= room then
		where = "left"
	else
		where = "right"
	end
	if where == ui.docked then return end
	ui.docked = where
	ui.panel:ClearAllPoints()
	ui.panel:SetWidth(effW)
	if where == "inside" then
		local sc = WorldMapFrame.ScrollContainer
		ui.panel:SetPoint("TOPLEFT", sc, "TOPLEFT", 10, -48)
		ui.panel:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 10, 10)
	elseif where == "left" then
		ui.panel:SetPoint("TOPRIGHT", WorldMapFrame, "TOPLEFT", -10, 2)
		ui.panel:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMLEFT", -10, -2)
	else
		ui.panel:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", -4, 2)
		ui.panel:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", -4, -2)
	end
end
ns.SyncPanelDock = Dock

function ns.ResetPanelPosition()
	if not ns.db then return end
	ns.db.panelPos = nil
	ns.db.panelW = nil
	ns.db.panelH = nil
	ui.docked = nil
	if ui.panel then
		ui.panel:SetWidth(WIDTH)
		Dock()
		if ns.LayoutPanelRows then ns.LayoutPanelRows() end
	end
end

function ns.ApplyPanelStyle()
	if not ns.db then return end
	local a = math.max(0.2, math.min(1.0, ns.db.background or 0.8))
	local style = ns.BackgroundStyle and ns.BackgroundStyle(ns.db.backgroundStyle) or { key = "dark", name = "Dark" }
	local scale = math.max(0.5, math.min(1.5, ns.db.panelScale or 1.0))
	SetBackground(ns.styleDialogBorder, a, style)
	if not ui.panel then return end
	SetBackground(ui.border, a, style)
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
	if math.abs((ui.panel:GetScale() or 1) - scale) > 0.001 then
		ui.panel:SetScale(scale)
		ui.docked = nil
		Dock()
	end
end

function ns.SyncStyleButton()
	if ui.styleBtn and ui.styleBtn.SetActive and ns.IsStyleDialogOpen then
		ui.styleBtn:SetActive(ns.IsStyleDialogOpen())
	end
end

function ns.SyncPanelScrollBar(scrollPx, listH, totalH)
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
	return ui.docked == "inside"
end

local function AbovePins()
	return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST") + 10
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
	panel:SetWidth(math.max(WIDTH, (ns.db and ns.db.panelW) or WIDTH))
	panel:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	panel:SetFrameLevel(AbovePins())
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:SetResizable(true)
	if panel.SetResizeBounds then
		panel:SetResizeBounds(WIDTH, MIN_H, 1400, 1000)
	end
	if panel.SetDontSavePosition then
		panel:SetDontSavePosition(true)
	end
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", BeginPanelMove)
	panel:SetScript("OnDragStop", EndPanelDragOrResize)
	panel:SetScript("OnSizeChanged", function(self, w, h)
		if ui.dragging then return end
		local needW = w and w < WIDTH - 0.5
		local needH = ui.docked == "free" and h and h < MIN_H - 0.5
		if needW or needH then
			self:SetSize(needW and WIDTH or (w or WIDTH), needH and MIN_H or (h or MIN_H))
		end
	end)
	panel:SetScript("OnUpdate", Dock)
	local level = panel:GetFrameLevel()

	local border = TryTemplate("Frame", nil, panel, "DialogBorderTranslucentTemplate")
	if border then
		border:SetAllPoints()
	else
		border = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
		border:SetAllPoints()
		border:SetFrameLevel(level)
		border:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		border:SetBackdropColor(0, 0, 0, 0.8)
	end
	ui.border = border

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -15)
	title:SetText("Dave's Map")

	-- Title-bar drag strip: drag anywhere along the top header to move freely (double-click to re-dock beside map).
	local dragBar = CreateFrame("Button", nil, panel)
	dragBar:SetPoint("TOPLEFT", 12, -4)
	dragBar:SetPoint("TOPRIGHT", -12, -4)
	dragBar:SetHeight(32)
	dragBar:SetFrameLevel(level + 2)
	dragBar:RegisterForDrag("LeftButton")
	dragBar:SetScript("OnDragStart", function() BeginPanelMove(panel) end)
	dragBar:SetScript("OnDragStop", function() EndPanelDragOrResize(panel) end)
	dragBar:SetScript("OnDoubleClick", function()
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.ResetPanelPosition()
	end)

	-- Bottom-right resize grip (enforces current width 628px as minimum width).
	local resizeBtn = CreateFrame("Button", nil, panel)
	resizeBtn:SetSize(14, 14)
	resizeBtn:SetPoint("BOTTOMRIGHT", -3, 3)
	resizeBtn:SetFrameLevel(level + 10)
	resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	resizeBtn:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then BeginPanelResize(panel) end
	end)
	resizeBtn:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then EndPanelDragOrResize(panel) end
	end)

	-----------------------------------------------------------------------
	-- Slim Left Skill-Icon Tab Rail (`Base`, `Tracker`, `Zone`, `Dungeon` + `Back`)
	-----------------------------------------------------------------------
	local leftRail = CreateFrame("Frame", nil, panel, "BackdropTemplate")
	ui.leftRail = leftRail
	leftRail:SetWidth(RAIL_W)
	leftRail:SetPoint("TOPLEFT", 12, -38)
	leftRail:SetPoint("BOTTOMLEFT", 12, 12)
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

	local backBtn = CreateFrame("Button", nil, leftRail)
	ui.backBtn = backBtn
	backBtn:SetSize(34, 34)
	backBtn:SetPoint("BOTTOM", leftRail, "BOTTOM", 0, 6)
	backBtn:RegisterForClicks("LeftButtonUp", "Button4Up")
	backBtn.frame = backBtn:CreateTexture(nil, "BACKGROUND")
	backBtn.frame:SetAllPoints()
	backBtn.frame:SetTexture(slotTex)
	backBtn.frame:SetVertexColor(0.86, 0.80, 0.66, 0.94)
	backBtn.activeBg = backBtn:CreateTexture(nil, "BORDER")
	backBtn.activeBg:SetAllPoints()
	backBtn.activeBg:SetTexture(slotTex)
	backBtn.activeBg:SetBlendMode("ADD")
	backBtn.activeBg:SetAlpha(0.28)
	backBtn.activeBg:Hide()
	backBtn.icon = backBtn:CreateTexture(nil, "ARTWORK")
	backBtn.icon:SetSize(20, 20)
	backBtn.icon:SetPoint("CENTER", 0, 0)
	backBtn.icon:SetTexture(ns.MEDIA .. "back")
	backBtn.hl = backBtn:CreateTexture(nil, "HIGHLIGHT")
	backBtn.hl:SetAllPoints()
	backBtn.hl:SetTexture(slotTex)
	backBtn.hl:SetBlendMode("ADD")
	backBtn.hl:SetAlpha(0.35)
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

	-----------------------------------------------------------------------
	-- Right Visual Content Pane
	-----------------------------------------------------------------------
	local content = CreateFrame("Frame", nil, panel)
	ui.content = content
	content:SetPoint("TOPLEFT", leftRail, "TOPRIGHT", 2, 0)
	content:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 12)

	ui.styleBtn = ToolbarIconButton(content, ns.MEDIA .. "gear", "Window Style", "Customize Window scale, Background opacity, Background style, and Pin size (same styling options as Dave's Sack).", function()
		if ns.ToggleStyleDialog then ns.ToggleStyleDialog() end
	end)
	ui.styleBtn:SetPoint("TOPRIGHT", -LIST_PAD, -4)

	ui.pinBtn = ToolbarIconButton(content, ns.MEDIA .. "waypoint", "Drop Waypoint", "Left-click: arm map pin placement (or Ctrl-click the map anytime).\nRight-click: clear active waypoint.", function(button)
		ns.TogglePinMode(button == "RightButton")
		RefreshControls()
	end, true)
	ui.pinBtn:SetPoint("RIGHT", ui.styleBtn, "LEFT", -4, 0)

	ui.findBtn = ToolbarIconButton(content, ns.MEDIA .. "findme", "Find Me", "Glide the map to your character's current position.", function()
		ns.FindPlayer()
	end)
	ui.findBtn:SetPoint("RIGHT", ui.pinBtn, "LEFT", -4, 0)

	local search = CreateFrame("EditBox", nil, content, "SearchBoxTemplate")
	ui.search = search
	search:SetHeight(20)
	search:SetPoint("TOPLEFT", LIST_PAD + 4, -5)
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

	ui.ready = true
	panel:SetScript("OnMouseUp", function(_, button)
		if button == "Button4" then ns.GoBack() end
	end)
	panel:SetScript("OnShow", function()
		Dock()
		if ui.dirtyHidden or #ui.items == 0 then
			ns.OnLayerChanged()
		else
			RefreshControls()
		end
	end)
	panel:SetScript("OnHide", function()
		if ui.dragging then EndPanelDragOrResize(panel) end
		if ns.HideStyleDialog then ns.HideStyleDialog() end
	end)
	ns.ApplyPanelStyle()
	ns.UpdatePanel()
	if panel:IsVisible() then ns.OnLayerChanged() end
end
