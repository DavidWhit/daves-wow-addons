-- daves_map / MapStage.lua
-- Compact WowStyle1DropdownTemplate map navigation bar replacing WorldMapFrame.NavBar,
-- and full-bleed subtly zone-tinted map backdrop filling the entire map stage behind
-- ScrollContainer (no inner frame border around the map).

local _, ns = ...

local L = ns.UNIFIED_LAYOUT or {}
local DEFAULT_MAP_LEFT_X = L.MAP_LEFT_X or 6
local DEFAULT_NAV_TOP_Y = L.TOP_CONTENT_Y or -6
local DEFAULT_NAV_H = L.NAV_BAR_H or 26
local DEFAULT_STAGE_TOP_Y = L.STAGE_TOP_Y or -38
local DEFAULT_MAP_W = L.MAP_DEFAULT_W or 697
local DEFAULT_BODY_H = L.BODY_DEFAULT_H or 467
local DD_GAP = 6
local DD_HEIGHT = 24
local FALLBACK_WORLD_ID = 947

local function SafeNum(v)
	return (type(v) == "number" and not issecretvalue(v)) and v or nil
end

local function SafeStr(v)
	return (type(v) == "string" and not issecretvalue(v) and v ~= "") and v or nil
end

local function TryTemplate(kind, name, parent, template)
	local ok, f = pcall(CreateFrame, kind, name, parent, template)
	return ok and f or nil
end

---------------------------------------------------------------------------
-- Muted Zone Biome Palettes
-- `tile` gently shifts the native dark map backdrop (AdventureMap_TileBg)
-- without crushing its brightness; `base`/`top`/`bot` add a quiet wash.
---------------------------------------------------------------------------
local BIOMES = {
	world    = { base = { 0.09, 0.07, 0.05 }, top = { 0.16, 0.13, 0.09 }, bot = { 0.08, 0.06, 0.04 }, tile = { 0.96, 0.94, 0.90 } },
	forest   = { base = { 0.06, 0.08, 0.06 }, top = { 0.11, 0.16, 0.12 }, bot = { 0.05, 0.08, 0.06 }, tile = { 0.84, 0.94, 0.84 } },
	snow     = { base = { 0.07, 0.09, 0.11 }, top = { 0.15, 0.19, 0.24 }, bot = { 0.07, 0.09, 0.12 }, tile = { 0.84, 0.92, 1.00 } },
	desert   = { base = { 0.10, 0.08, 0.05 }, top = { 0.21, 0.16, 0.10 }, bot = { 0.10, 0.07, 0.05 }, tile = { 1.00, 0.92, 0.80 } },
	volcanic = { base = { 0.10, 0.05, 0.05 }, top = { 0.20, 0.09, 0.07 }, bot = { 0.11, 0.05, 0.04 }, tile = { 1.00, 0.82, 0.78 } },
	swamp    = { base = { 0.06, 0.08, 0.07 }, top = { 0.11, 0.15, 0.13 }, bot = { 0.05, 0.09, 0.07 }, tile = { 0.80, 0.92, 0.86 } },
	shadow   = { base = { 0.07, 0.06, 0.09 }, top = { 0.13, 0.11, 0.18 }, bot = { 0.06, 0.05, 0.09 }, tile = { 0.86, 0.82, 0.96 } },
	coast    = { base = { 0.06, 0.08, 0.10 }, top = { 0.12, 0.16, 0.21 }, bot = { 0.05, 0.08, 0.10 }, tile = { 0.82, 0.92, 1.00 } },
	autumn   = { base = { 0.10, 0.07, 0.05 }, top = { 0.20, 0.14, 0.09 }, bot = { 0.09, 0.06, 0.04 }, tile = { 1.00, 0.88, 0.76 } },
	city     = { base = { 0.08, 0.08, 0.08 }, top = { 0.16, 0.15, 0.14 }, bot = { 0.08, 0.07, 0.07 }, tile = { 0.94, 0.92, 0.90 } },
}

local ZONE_BIOME = {
	[947]  = "world",    [1414] = "world",    [1415] = "world",    [1411] = "desert",   [1412] = "forest",   [1413] = "desert",
	[1416] = "snow",     [1417] = "autumn",   [1418] = "desert",   [1419] = "volcanic", [1420] = "shadow",   [1421] = "shadow",
	[1422] = "autumn",   [1423] = "shadow",   [1424] = "forest",   [1425] = "forest",   [1426] = "snow",     [1427] = "volcanic",
	[1428] = "volcanic", [1429] = "forest",   [1430] = "shadow",   [1431] = "shadow",   [1432] = "autumn",   [1433] = "autumn",
	[1434] = "forest",   [1435] = "swamp",    [1436] = "autumn",   [1437] = "swamp",    [1438] = "forest",   [1439] = "coast",
	[1440] = "forest",   [1441] = "desert",   [1442] = "autumn",   [1443] = "desert",   [1444] = "forest",   [1445] = "swamp",
	[1446] = "desert",   [1447] = "autumn",   [1448] = "shadow",   [1449] = "swamp",    [1450] = "forest",   [1451] = "desert",
	[1452] = "snow",     [1453] = "city",     [1454] = "city",     [1455] = "city",     [1456] = "city",     [1457] = "city",
	[1458] = "city",     [1459] = "snow",     [2482] = "volcanic", [2521] = "coast",    [2548] = "coast",    [2652] = "shadow",
}

local STYLE_ALPHAS = {
	marble = { 0.90, 0.20, 0.22, 0.90, 0.30, 0.32 },
	dialog = { 0.92, 0.20, 0.22, 0.92, 0.30, 0.30 },
	dark   = { 0.94, 0.18, 0.20, 0.94, 0.28, 0.28 },
}

local state = {
	initialized = false,
	chrome = nil,
	overlay = nil,
	mapStage = nil,
	mapNavBar = nil,
	stageBase = nil,
	stageGrad = nil,
	stageTile = nil,
	vignettes = {},
	stageBorder = {},
	slots = {},
	navW = 0,
	lastMapID = nil,
	lastNavW = nil,
	lastAtlas = nil,
	inSelect = false,
	biome = "world",
	styleKey = "dark",
	styleAlpha = 0.8,
}

local function ResolveBiome(mapID)
	local id, guard = SafeNum(mapID), 0
	while id and id > 0 and guard < 12 do
		local hit = ZONE_BIOME[id]
		if hit then return hit end
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
		id = info and SafeNum(info.parentMapID) or nil
		guard = guard + 1
	end
	return "world"
end

---------------------------------------------------------------------------
-- Crisp 1px Outer Stage Hairline Builder
---------------------------------------------------------------------------
local function MakeLine(parent, layer, subLevel, r, g, b, a)
	local t = parent:CreateTexture(nil, layer, nil, subLevel)
	t:SetColorTexture(r, g, b, a)
	t:SetVertexColor(1, 1, 1, 1)
	if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
	if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
	return t
end

local function AddBorderRect(parent, layer, subLevel, inset, r, g, b, a, out)
	local edges = {
		{ "TOPLEFT",    "TOPRIGHT",    inset,      -inset,       -inset,      -inset,      nil, 1 },
		{ "BOTTOMLEFT", "BOTTOMRIGHT", inset,       inset,       -inset,       inset,      nil, 1 },
		{ "TOPLEFT",    "BOTTOMLEFT",  inset,      -(inset + 1),  inset,       inset + 1,  1,   nil },
		{ "TOPRIGHT",   "BOTTOMRIGHT", -inset,     -(inset + 1), -inset,       inset + 1,  1,   nil },
	}
	for _, e in ipairs(edges) do
		local t = MakeLine(parent, layer, subLevel, r, g, b, a)
		if e[7] then t:SetWidth(e[7]) end
		if e[8] then t:SetHeight(e[8]) end
		t:SetPoint(e[1], parent, e[1], e[3], e[4])
		t:SetPoint(e[2], parent, e[2], e[5], e[6])
		if out then out[#out + 1] = t end
	end
end

---------------------------------------------------------------------------
-- Stage Backdrop Styling, Native Map Backdrop Sync & Biome Tinting
---------------------------------------------------------------------------
local function SilenceNativeTiledBackground()
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	local tiled = sc and sc.Child and sc.Child.TiledBackground
	if tiled and tiled.SetAlpha then
		tiled:SetAlpha(0)
	end
	local osbg = WorldMapFrame and WorldMapFrame.OverscrollBG
	if osbg and osbg.SetAlpha then
		osbg:SetAlpha(0)
	end
end

local function ApplyStageAtlas(mapID)
	local tile = state.stageTile
	if not tile then return end
	local atlas = (mapID and C_Map and C_Map.GetMapArtBackgroundAtlas)
		and SafeStr(C_Map.GetMapArtBackgroundAtlas(mapID)) or nil
	local info = (atlas and C_Texture and C_Texture.GetAtlasInfo) and C_Texture.GetAtlasInfo(atlas) or nil
	if not info then
		atlas = "AdventureMap_TileBg"
		info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) or nil
	end
	if not info then
		atlas = "gamepad-mapquestlog-bgtile-2k"
		info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) or nil
	end
	if info then
		if state.lastAtlas ~= atlas then
			state.lastAtlas = atlas
			tile:SetHorizTile(true)
			tile:SetVertTile(true)
			tile:SetAtlas(atlas, false)
			tile:SetHorizTile(true)
			tile:SetVertTile(true)
		end
	elseif state.lastAtlas ~= "marble" then
		state.lastAtlas = "marble"
		tile:SetHorizTile(true)
		tile:SetVertTile(true)
		tile:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
	end
end

local function ApplyStageColors()
	if not state.mapStage then return end
	local pal = BIOMES[state.biome] or BIOMES.world
	local aScale = 0.70 + 0.30 * math.max(0.2, math.min(1.0, state.styleAlpha or 0.8))
	local sa = STYLE_ALPHAS[state.styleKey] or STYLE_ALPHAS.dark

	if state.stageBase then
		state.stageBase:SetColorTexture(pal.base[1], pal.base[2], pal.base[3], sa[1] * aScale)
		state.stageBase:SetVertexColor(1, 1, 1, 1)
	end
	if state.stageTile then
		state.stageTile:SetVertexColor(pal.tile[1], pal.tile[2], pal.tile[3], sa[4] * aScale)
	end
	if state.stageGrad and CreateColor then
		state.stageGrad:SetGradient(
			"VERTICAL",
			CreateColor(pal.bot[1], pal.bot[2], pal.bot[3], sa[2] * aScale),
			CreateColor(pal.top[1], pal.top[2], pal.top[3], sa[3] * aScale)
		)
	end
	local vigA = sa[5] * aScale
	for _, v in ipairs(state.vignettes) do
		v:SetVertexColor(0.04, 0.04, 0.03, vigA)
	end
	for _, edge in ipairs(state.stageBorder) do
		edge:SetColorTexture(0.38, 0.31, 0.19, sa[6])
		edge:SetVertexColor(1, 1, 1, 1)
	end
end

function ns.ApplyMapStageStyle(alpha, style)
	local a = SafeNum(alpha)
	if a then state.styleAlpha = a end
	if type(style) == "table" and type(style.key) == "string" then
		state.styleKey = style.key
	elseif type(style) == "string" then
		state.styleKey = style
	end
	if state.initialized then ApplyStageColors() end
end

---------------------------------------------------------------------------
-- Map Navigation Dropdown Bar
---------------------------------------------------------------------------
local function NavigateToMap(targetID)
	local id = SafeNum(targetID)
	if not id then return end
	if InCombatLockdown() then
		if ns.Print then ns.Print("can't change the map in combat.") end
		state.lastMapID = nil
		ns.RefreshMapStage()
		return
	end
	local prevMap = WorldMapFrame and WorldMapFrame.GetMapID and SafeNum(WorldMapFrame:GetMapID())
	state.inSelect = true
	state.lastMapID = nil
	if ns.CloseDungeonView then ns.CloseDungeonView() end
	local unlocked = ns.OnUserMapNavigate and ns.OnUserMapNavigate(true) or false
	if prevMap == id then
		local handled = false
		if ns.IsStitched and ns.IsStitched() and ns.StitchWorld then
			local stitch, S = ns.StitchWorld()
			if stitch and S and S.Rect and S.Rect(id) and stitch.FitZoom and stitch.ShowNow then
				local l, r, t, b = S.Rect(id)
				stitch.ShowNow((l + r) / 2, (t + b) / 2, stitch.FitZoom(id))
				handled = true
			end
		end
		if not handled and WorldMapFrame and WorldMapFrame.ScrollContainer
			and WorldMapFrame.ScrollContainer.ResetZoom then
			WorldMapFrame.ScrollContainer:ResetZoom()
		end
		if unlocked and ns.Refresh then ns.Refresh() end
	elseif WorldMapFrame and WorldMapFrame.SetMapID then
		WorldMapFrame:SetMapID(id)
	end
	state.inSelect = false
	if state.lastMapID == nil then ns.RefreshMapStage(id) end
	if ns.Sound then ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON") end
end

local function CreateDropdownSlot(parent)
	local slot = { items = {}, selectedID = nil, defaultText = "", shown = false, native = false, btn = nil }
	local dd = TryTemplate("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if dd and dd.SetupMenu then
		slot.native, slot.btn = true, dd
		dd:SetHeight(DD_HEIGHT)
		if not InCombatLockdown() and dd.RegisterForMouse then
			dd:RegisterForMouse("LeftButtonDown", "LeftButtonUp", "Button4Up")
		end
		dd:HookScript("OnMouseUp", function(_, button)
			if button == "Button4" and ns.GoBack then ns.GoBack() end
		end)
		local function IsSel(targetID) return slot.selectedID == targetID end
		local function OnSel(targetID) NavigateToMap(targetID) end
		dd:SetupMenu(function(_, root)
			if #slot.items > 18 and root.SetScrollMode then root:SetScrollMode(360) end
			for _, item in ipairs(slot.items) do
				root:CreateRadio(item.name, IsSel, OnSel, item.id)
			end
		end)
	else
		local b = TryTemplate("Button", nil, parent, "UIPanelButtonTemplate") or CreateFrame("Button", nil, parent)
		slot.btn = b
		b:SetHeight(DD_HEIGHT)
		if not b.SetText then
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			b.text:SetPoint("CENTER")
			b.SetText = function(_, t) b.text:SetText(t) end
		end
		if not InCombatLockdown() and b.RegisterForClicks then
			b:RegisterForClicks("LeftButtonUp", "Button4Up")
		end
		b:SetScript("OnClick", function(_, button)
			if button == "Button4" then
				if ns.GoBack then ns.GoBack() end
				return
			end
			if #slot.items == 0 then return end
			local nextIdx = 1
			for i, item in ipairs(slot.items) do
				if item.id == slot.selectedID then nextIdx = (i % #slot.items) + 1; break end
			end
			NavigateToMap(slot.items[nextIdx].id)
		end)
	end
	slot.btn:Hide()
	return slot
end

local function SyncSlotDisplay(slot)
	local btn = slot.btn
	if not btn then return end
	if slot.native and not state.inSelect and btn.IsMenuOpen and btn:IsMenuOpen() and btn.CloseMenu then
		btn:CloseMenu()
	end
	if not slot.shown then
		btn:Hide()
		return
	end
	if slot.native then
		if btn.SetDefaultText then btn:SetDefaultText(slot.defaultText) end
		local wasShown = btn:IsShown()
		local isOpen = btn.IsMenuOpen and btn:IsMenuOpen()
		btn:Show()
		if wasShown and btn.GenerateMenu then
			if isOpen then
				C_Timer.After(0, function()
					if slot.shown and btn:IsShown() and not (btn.IsMenuOpen and btn:IsMenuOpen()) then
						btn:GenerateMenu()
					end
				end)
			else
				btn:GenerateMenu()
			end
		end
	else
		local text = slot.defaultText
		for _, item in ipairs(slot.items) do
			if item.id == slot.selectedID then text = item.name; break end
		end
		btn:SetText(text)
		btn:Show()
	end
end

local function LayoutDropdowns()
	if not state.mapNavBar then return end
	local navW = math.max(200, state.navW or DEFAULT_MAP_W)
	local vis = {}
	for i = 1, 3 do
		local slot = state.slots[i]
		if slot and slot.shown and slot.btn then vis[#vis + 1] = slot.btn end
	end
	local count = #vis
	if count == 0 then return end

	local widths = {}
	if count == 1 then
		widths[1] = math.min(navW, math.min(200, math.max(120, math.floor(navW * 0.34))))
	elseif count == 2 then
		local avail = math.max(160, navW - DD_GAP)
		local w1 = math.min(185, math.max(115, math.floor(avail * 0.36)))
		local w2 = math.min(240, math.max(130, math.floor(avail * 0.46)))
		if w1 + w2 > avail then w1 = math.floor(avail * 0.44); w2 = avail - w1 end
		widths[1], widths[2] = w1, w2
	else
		local avail = math.max(210, navW - DD_GAP * 2)
		local w1 = math.min(165, math.max(105, math.floor(avail * 0.30)))
		local w2 = math.min(195, math.max(115, math.floor(avail * 0.35)))
		local w3 = math.min(210, math.max(115, math.floor(avail * 0.35)))
		if w1 + w2 + w3 > avail then
			w1 = math.floor(avail * 0.30)
			w2 = math.floor(avail * 0.35)
			w3 = avail - w1 - w2
		end
		widths[1], widths[2], widths[3] = w1, w2, w3
	end
	for i = 1, count do
		local btn = vis[i]
		btn:ClearAllPoints()
		btn:SetSize(widths[i], DD_HEIGHT)
		if i == 1 then
			btn:SetPoint("LEFT", state.mapNavBar, "LEFT", 0, 0)
		else
			btn:SetPoint("LEFT", vis[i - 1], "RIGHT", DD_GAP, 0)
		end
	end
end

local function CollectNavChildren(parentMapID, excludeID)
	local out = {}
	local children = (parentMapID and C_Map and C_Map.GetMapChildrenInfo) and C_Map.GetMapChildrenInfo(parentMapID) or nil
	if not children then return out end
	local validFn = C_Map.IsMapValidForNavBarDropdown
	for _, child in ipairs(children) do
		local cid = child and SafeNum(child.mapID)
		local cname = child and SafeStr(child.name)
		if cid and cname and cid ~= excludeID and (not validFn or validFn(cid)) then
			out[#out + 1] = { id = cid, name = cname }
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

local function PopulateNavSlots(mapID)
	local s1, s2, s3 = state.slots[1], state.slots[2], state.slots[3]
	if not (s1 and s2 and s3 and C_Map and C_Map.GetMapInfo) then return end

	local MT = Enum and Enum.UIMapType or {}
	local curInfo = C_Map.GetMapInfo(mapID)
	local worldInfo = (MapUtil and MapUtil.GetMapParentInfo and MT.World)
		and MapUtil.GetMapParentInfo(mapID, MT.World, true) or nil
	local worldID = (worldInfo and SafeNum(worldInfo.mapID))
		or (C_Map.GetFallbackWorldMapID and SafeNum(C_Map.GetFallbackWorldMapID()))
		or FALLBACK_WORLD_ID
	if not worldInfo then
		worldInfo = C_Map.GetMapInfo(worldID)
		if not (worldInfo and worldInfo.mapType == MT.World) then
			worldID = FALLBACK_WORLD_ID
			worldInfo = C_Map.GetMapInfo(worldID)
		end
	end
	local worldName = SafeStr(worldInfo and worldInfo.name) or "Azeroth"

	local contInfo, zoneInfo, subInfo
	local walk, guard = curInfo, 0
	while walk and guard < 12 do
		if walk.mapType == MT.Continent and not contInfo then
			contInfo = walk
		elseif walk.mapType == MT.Zone then
			if not zoneInfo then zoneInfo = walk else subInfo = zoneInfo; zoneInfo = walk end
		end
		local pid = SafeNum(walk.parentMapID)
		walk = (pid and pid > 0) and C_Map.GetMapInfo(pid) or nil
		guard = guard + 1
	end
	local parentID = curInfo and SafeNum(curInfo.parentMapID) or nil
	local parentInfo = (parentID and parentID > 0) and C_Map.GetMapInfo(parentID) or nil
	if curInfo and parentInfo and parentInfo.mapType == MT.Zone then
		zoneInfo, subInfo = parentInfo, curInfo
	elseif curInfo and curInfo.mapType and MT.Zone and curInfo.mapType > MT.Zone and not zoneInfo then
		zoneInfo = curInfo
	end

	-- Slot 1: Azeroth + continents.
	local worldItems = CollectNavChildren(worldID, worldID)
	table.insert(worldItems, 1, { id = worldID, name = worldName })
	local contID = contInfo and SafeNum(contInfo.mapID) or nil
	local curID = (curInfo and SafeNum(curInfo.mapID)) or mapID
	local s1Sel, s1Def = worldID, worldName
	if contID then
		s1Sel, s1Def = contID, SafeStr(contInfo.name) or worldName
	elseif curInfo and parentID == worldID and curID ~= worldID then
		for _, it in ipairs(worldItems) do
			if it.id == curID then s1Sel, s1Def = curID, it.name; break end
		end
	elseif curInfo and curID ~= worldID and curInfo.mapType ~= MT.World then
		s1Sel, s1Def = nil, SafeStr(curInfo.name) or worldName
	end
	s1.items, s1.selectedID, s1.defaultText, s1.shown = worldItems, s1Sel, s1Def, true

	-- Slot 2: Zones of current continent.
	local zoneItems = contID and CollectNavChildren(contID, contID) or {}
	local zoneID = zoneInfo and SafeNum(zoneInfo.mapID) or nil
	if contID and #zoneItems > 0 then
		s2.items, s2.selectedID = zoneItems, zoneID
		s2.defaultText = (zoneInfo and SafeStr(zoneInfo.name)) or "Select Zone..."
		s2.shown = true
	else
		s2.items, s2.selectedID, s2.defaultText, s2.shown = {}, nil, "Select Zone...", false
	end

	-- Slot 3: Multi-floor group (>1 floor) or sibling subzones under a Zone.
	local s3Items, s3Sel, s3Def = {}, nil, ""
	local groupID = C_Map.GetMapGroupID and SafeNum(C_Map.GetMapGroupID(mapID)) or nil
	local members = (groupID and C_Map.GetMapGroupMembersInfo) and C_Map.GetMapGroupMembersInfo(groupID) or nil
	if members and #members > 1 then
		for idx, m in ipairs(members) do
			local mid = m and SafeNum(m.mapID)
			if mid then
				local mName = SafeStr(m.name) or ("Floor " .. idx)
				s3Items[#s3Items + 1] = { id = mid, name = mName }
				if mid == mapID then s3Sel, s3Def = mid, mName end
			end
		end
	elseif subInfo and zoneID then
		s3Items = CollectNavChildren(zoneID, zoneID)
		local subID = SafeNum(subInfo.mapID)
		local subName = SafeStr(subInfo.name) or ""
		local found = false
		for _, it in ipairs(s3Items) do
			if it.id == subID then found = true; break end
		end
		if not found and subID and subName ~= "" then
			s3Items[#s3Items + 1] = { id = subID, name = subName }
			table.sort(s3Items, function(a, b) return a.name < b.name end)
		end
		s3Sel, s3Def = subID, subName
	end
	s3.items, s3.selectedID, s3.defaultText, s3.shown = s3Items, s3Sel, s3Def, (#s3Items > 0)

	SyncSlotDisplay(s1)
	SyncSlotDisplay(s2)
	SyncSlotDisplay(s3)
end

---------------------------------------------------------------------------
-- Public Lifecycle API
---------------------------------------------------------------------------
function ns.SyncMapStageStrata()
	if not WorldMapFrame then return end
	local sc = WorldMapFrame.ScrollContainer
	local chrome, overlay = state.chrome, state.overlay
	local mapStrata = (chrome and chrome:GetFrameStrata()) or WorldMapFrame:GetFrameStrata() or "MEDIUM"
	local scLevel = (sc and SafeNum(sc:GetFrameLevel())) or 2
	if state.mapStage then
		state.mapStage:SetFrameStrata(mapStrata)
		state.mapStage:SetFrameLevel(math.max(0, scLevel - 1))
	end
	if state.mapNavBar then
		local bf = WorldMapFrame.BorderFrame
		local navStrata = (overlay and overlay:GetFrameStrata()) or (bf and bf:GetFrameStrata()) or "HIGH"
		local overlayLevel = (overlay and SafeNum(overlay:GetFrameLevel())) or (((bf and SafeNum(bf:GetFrameLevel())) or 10) + 1)
		state.mapNavBar:SetFrameStrata(navStrata)
		state.mapNavBar:SetFrameLevel(math.max(scLevel + 2, overlayLevel + 1))
	end
end

function ns.LayoutMapStage(mapLeftX, navTopY, navH, stageTopY, mapW, bodyH)
	if not (state.initialized and WorldMapFrame) then return end
	local mx = SafeNum(mapLeftX) or DEFAULT_MAP_LEFT_X
	local ny = SafeNum(navTopY) or DEFAULT_NAV_TOP_Y
	local nh = SafeNum(navH) or DEFAULT_NAV_H
	local sy = SafeNum(stageTopY) or DEFAULT_STAGE_TOP_Y
	local mw = SafeNum(mapW) or DEFAULT_MAP_W
	local bh = SafeNum(bodyH) or DEFAULT_BODY_H

	state.navW = mw
	if state.mapNavBar then
		state.mapNavBar:ClearAllPoints()
		state.mapNavBar:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", mx, ny)
		state.mapNavBar:SetSize(mw, nh)
	end
	if state.mapStage then
		state.mapStage:ClearAllPoints()
		state.mapStage:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", mx, sy)
		state.mapStage:SetSize(mw, bh)
	end
	if state.lastNavW ~= mw then
		LayoutDropdowns()
		state.lastNavW = mw
	end
end

function ns.RefreshMapStage(overrideMapID)
	if not (state.initialized and WorldMapFrame) then return end
	SilenceNativeTiledBackground()
	local mapID = SafeNum(overrideMapID)
		or (WorldMapFrame.GetMapID and SafeNum(WorldMapFrame:GetMapID()))
		or (C_Map and C_Map.GetFallbackWorldMapID and SafeNum(C_Map.GetFallbackWorldMapID()))
		or FALLBACK_WORLD_ID
	local curW = state.navW
	if mapID == state.lastMapID and curW == state.lastNavW then return end
	if mapID ~= state.lastMapID then
		state.lastMapID = mapID
		state.biome = ResolveBiome(mapID)
		ApplyStageAtlas(mapID)
		ApplyStageColors()
		PopulateNavSlots(mapID)
	end
	LayoutDropdowns()
	state.lastNavW = curW
end

function ns.InitMapStage(chrome, overlay)
	if not WorldMapFrame then return end
	state.chrome = chrome or state.chrome
	state.overlay = overlay or state.overlay
	if state.initialized then
		SilenceNativeTiledBackground()
		ns.SyncMapStageStrata()
		ns.RefreshMapStage()
		return
	end
	state.initialized = true

	-- Full-bleed subtly zone-tinted map backdrop filling mapStage behind ScrollContainer.
	local stage = CreateFrame("Frame", nil, WorldMapFrame)
	state.mapStage = stage
	stage:SetClipsChildren(true)
	stage:EnableMouse(false)

	state.stageBase = stage:CreateTexture(nil, "BACKGROUND", nil, -7)
	state.stageBase:SetAllPoints()

	local tile = stage:CreateTexture(nil, "BACKGROUND", nil, -6)
	tile:SetAllPoints()
	state.stageTile = tile

	state.stageGrad = stage:CreateTexture(nil, "BACKGROUND", nil, -5)
	state.stageGrad:SetAllPoints()
	state.stageGrad:SetColorTexture(1, 1, 1, 1)

	local vigInfo = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("gamepad-mapquestlog-bg-vignette")
	if vigInfo then
		local uL, uR = vigInfo.leftTexCoord or 0, vigInfo.rightTexCoord or 1
		local vT, vB = vigInfo.topTexCoord or 0, vigInfo.bottomTexCoord or 1
		for _, c in ipairs({
			{ "TOPLEFT",     "BOTTOMRIGHT", uL, uR, vT, vB },
			{ "TOPRIGHT",    "BOTTOMLEFT",  uR, uL, vT, vB },
			{ "BOTTOMLEFT",  "TOPRIGHT",    uL, uR, vB, vT },
			{ "BOTTOMRIGHT", "TOPLEFT",     uR, uL, vB, vT },
		}) do
			local v = stage:CreateTexture(nil, "BACKGROUND", nil, -4)
			v:SetAtlas("gamepad-mapquestlog-bg-vignette", false)
			v:SetTexCoord(c[3], c[4], c[5], c[6])
			v:SetPoint(c[1], stage, c[1], 0, 0)
			v:SetPoint(c[2], stage, "CENTER", 0, 0)
			state.vignettes[#state.vignettes + 1] = v
		end
	end
	AddBorderRect(stage, "BORDER", 1, 0, 0.38, 0.31, 0.19, 0.28, state.stageBorder)

	-- Compact WowStyle1DropdownTemplate navigation bar above the map.
	local navBar = CreateFrame("Frame", nil, WorldMapFrame)
	state.mapNavBar = navBar
	navBar:EnableMouse(true)
	navBar:SetScript("OnMouseUp", function(_, button)
		if button == "Button4" and ns.GoBack then ns.GoBack() end
	end)
	for i = 1, 3 do state.slots[i] = CreateDropdownSlot(navBar) end

	SilenceNativeTiledBackground()
	ns.ApplyMapStageStyle(ns.db and ns.db.background, ns.db and ns.db.backgroundStyle)
	ns.LayoutMapStage(DEFAULT_MAP_LEFT_X, DEFAULT_NAV_TOP_Y, DEFAULT_NAV_H, DEFAULT_STAGE_TOP_Y, DEFAULT_MAP_W, DEFAULT_BODY_H)
	ns.SyncMapStageStrata()
	ns.RefreshMapStage()
end
