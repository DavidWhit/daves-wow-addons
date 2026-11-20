-- daves_map / Tooltip.lua
-- Rich map pin tooltip (`ns.ShowTooltip`), top-center Zone Level & Coordinates Banner, clickable
-- Reference Layer HUD pill (`ns.UpdateMapBanner`), and unmapped-quest HUD veil (`ns.ShowUnmappedQuestFallback`).

local _, ns = ...

local FACTION_NAME = { "Alliance", "Horde", "Neutral" }
local FACTION_COLOR = { { .3, .55, 1 }, { 1, .3, .3 }, { 1, .82, .2 } }

local state = {
	tipOwner = nil,
	tipPin = nil,
	tipDone = nil,
	tipLocked = nil,
	tipTrackedQ = nil,
	banner = nil,
	bannerAt = nil,
	bannerLine = nil,
	mapByName = nil,
	veil = nil,
	toldNoMap = {},
}

---------------------------------------------------------------------------
-- Map Pin Tooltip
---------------------------------------------------------------------------
function ns.InvalidatePinTooltip()
	state.tipPin = nil
end

function ns.HidePinTooltipIfOwned(owner)
	if owner and GameTooltip:GetOwner() == owner then
		state.tipOwner = nil
		GameTooltip:Hide()
	end
end

local function LinkLine(label, list, base)
	if #list == 0 then return end
	local D = ns.DATA
	local here = ns.ZoneName(base)
	local names = {}
	for n, j in ipairs(list) do
		if n > 4 then names[#names + 1] = ("+%d more"):format(#list - 4); break end
		local z = ns.ZoneName(j)
		names[#names + 1] = D.title[j] .. ((z and z ~= here) and (" (" .. z .. ")") or "")
	end
	GameTooltip:AddLine(label .. table.concat(names, ", "), .8, .8, .8, true)
end

function ns.ShowTooltip(owner, i)
	local D = ns.DATA
	if not (D and i) then return end
	local stitch = ns.StitchWorld()
	local completed = ns.PinDone(i)
	local selPin = ns.FocusedPin()
	local isLocked = selPin ~= nil and selPin == i
	local trackedQ, trackedOwnerPin = nil, nil
	if ns.TrackedQuestForPin then
		trackedQ, trackedOwnerPin = ns.TrackedQuestForPin(i)
	end
	if GameTooltip:IsShown() and GameTooltip:GetOwner() == owner
		and state.tipOwner == owner and state.tipPin == i and state.tipDone == completed
		and state.tipLocked == isLocked and state.tipTrackedQ == trackedQ then
		return
	end
	state.tipOwner, state.tipPin, state.tipDone = owner, i, completed
	state.tipLocked, state.tipTrackedQ = isLocked, trackedQ

	local c = D.cats[D.cat[i]]
	local s = ns.CategoryStyle(D.cat[i])
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(D.title[i], 1, 1, 1, true)
	local zone = ns.ZoneName(i)
	GameTooltip:AddDoubleLine(c.title, zone or "", s.r, s.g, s.b, .7, .7, .7)
	if trackedQ then
		local qTitle = ns.QuestTitle(trackedQ) or (trackedOwnerPin and D.title[trackedOwnerPin]) or ("Quest #" .. tostring(trackedQ))
		local ready = ns.QuestReady(trackedQ) or ns.QuestComplete(trackedQ) == true
		GameTooltip:AddLine((ready and "|cffffd200Ready to Turn In:|r " or "|cff59ff73Tracked Quest:|r ") .. qTitle, .95, .95, .95, true)
	end
	local f = D.fac[i]
	if f ~= 0 then
		local fc = FACTION_COLOR[f]
		GameTooltip:AddLine(FACTION_NAME[f], fc[1], fc[2], fc[3])
	end
	local text = D.text[i]
	local rawDropsLine = nil
	if text ~= "" then
		for line in text:gmatch("[^\n]+") do
			if not line:find("Faction:") and not line:find("Side:") then
				if c.icon == "rare" and line:find("Drops:", 1, true) then
					rawDropsLine = line
				else
					GameTooltip:AddLine(line, .9, .9, .9, true)
				end
			end
		end
	end
	if c.icon == "rare" then
		local drops = D.drops and D.drops[i]
		if drops and #drops >= 2 then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Potential Known Drops:", 1, .82, .2)
			for k = 1, #drops, 2 do
				local itemID = drops[k]
				local rate10 = drops[k + 1] or 0
				local name, hex, icon, subLabel = ns.ItemDisplay(itemID)
				local leftTxt = ("|T%s:14:14:0:0:64:64:5:59:5:59|t |c%s%s|r"):format(
					tostring(icon or 134400), hex or "ffe8d8a8", name or ("Item #" .. tostring(itemID)))
				local rateTxt
				if rate10 > 0 then
					rateTxt = rate10 >= 100 and ("%d%%"):format(math.floor(rate10 / 10 + 0.5)) or ("%.1f%%"):format(rate10 / 10)
				end
				local rightTxt
				if subLabel and subLabel ~= "" and rateTxt then
					rightTxt = subLabel .. " - " .. rateTxt
				else
					rightTxt = rateTxt or subLabel or ""
				end
				if rightTxt ~= "" then
					GameTooltip:AddDoubleLine(leftTxt, rightTxt, 1, 1, 1, .72, .78, .84)
				else
					GameTooltip:AddLine(leftTxt, 1, 1, 1)
				end
			end
		elseif rawDropsLine then
			local listTxt = rawDropsLine:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s*Drops:%s*", "")
			if listTxt ~= "" then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Potential Known Drops:", 1, .82, .2)
				for itemName in listTxt:gmatch("[^,]+") do
					local clean = itemName:match("^%s*(.-)%s*$")
					if clean ~= "" then
						GameTooltip:AddLine("  - " .. clean, .92, .92, .92, true)
					end
				end
			end
		else
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Potential Known Drops: |cff888888None listed in QuestieDB|r", 1, .82, .2)
		end
	end
	if completed then GameTooltip:AddLine("Completed", .4, 1, .4) end
	local nextList = ns.NextOf(i)
	if c.icon == "quest" or c.icon == "repeatable" then
		local xp, exact = ns.PinXP(i, true)
		local xpTxt = ns.FormatXP(xp, exact)
		if xpTxt then
			GameTooltip:AddLine("|cffffd200Experience:|r " .. xpTxt .. (exact and "" or " |cff999999(est.)|r"), .95, .95, .95)
		end
		local rews = ns.PinRewards(i, true)
		local rewTxt = ns.FormatRewardSummary(rews, 4)
		if rewTxt then
			GameTooltip:AddLine("|cffffd200Rewards:|r " .. rewTxt, .95, .95, .95, true)
		end
		if (D.pre[i] and #D.pre[i] > 0) or (nextList and #nextList > 0) then
			local w = ns.ChainWorth(i)
			if w and w.totalSteps > 1 then
				local parts = {}
				if w.remSteps > 0 then
					parts[#parts + 1] = ("%d/%d steps left"):format(w.remSteps, w.totalSteps)
				else
					parts[#parts + 1] = ("Chain complete (%d steps)"):format(w.totalSteps)
				end
				local cxp = ns.FormatXP(w.xp, w.exactXP)
				if cxp then parts[#parts + 1] = cxp end
				local futTxt = ns.FormatRewardSummary(w.futureRewards, 3)
				GameTooltip:AddLine("|cff59ff73Chain worth:|r " .. table.concat(parts, "  -  "), .9, .95, .9, true)
				if futTxt then
					GameTooltip:AddLine("|cff59ff73Chain loot:|r " .. futTxt, .9, .95, .9, true)
				end
			end
		end
	end
	LinkLine("|cffff8c33Objectives:|r ", D.obj and D.obj[i] or {}, i)
	if D.endp[i] ~= 0 then LinkLine("|cffffd200Turn in:|r ", { D.endp[i] }, i) end
	LinkLine("|cff8ca6ffRequires:|r ", ns.EligiblePre(i), i)
	LinkLine("|cff59ff73Leads to:|r ", ns.EligibleNext(i), i)
	if D.dest[i] ~= 0 then LinkLine("|cff4de6ffTravels to:|r ", { D.dest[i] }, i) end

	local hint
	local fromCanvas = owner == (ns.HotButton and ns.HotButton())
	if c.icon == "instance" and stitch and stitch.enabled and stitch.DungeonMapsOn and stitch.DungeonMapsOn() then
		hint = "Click: open dungeon map"
	elseif not fromCanvas and (c.icon == "quest" or c.icon == "repeatable") and #ns.ChainFor(i).steps > 1 then
		hint = "Click: expand/collapse chain & show on map"
	elseif isLocked then
		hint = fromCanvas and "Click: clear highlight" or "Click: fly to location on map"
	elseif trackedQ or (ns.LogQuestIDForPin and ns.LogQuestIDForPin(i)) then
		hint = "Click: open quest text & highlight"
	else
		hint = fromCanvas and "Click: highlight on map" or "Click: fly to location on map"
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(hint .. "\nShift/Ctrl-click: set a waypoint", .5, .8, 1)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Top-Center Zone Banner & Active Reference Layer HUD Pill
---------------------------------------------------------------------------
local function EnsureBanner()
	if state.banner then return state.banner end
	local b = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer, "BackdropTemplate")
	b:SetHeight(22)
	b:SetPoint("TOP", 0, -8)
	b:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST") + 6)
	b:EnableMouse(false)
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	b:SetBackdropColor(0.05, 0.05, 0.07, 0.86)
	b:SetBackdropBorderColor(0.62, 0.48, 0.25, 0.85)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("CENTER", 0, 0)
	state.banner = b
	return b
end

function ns.UpdateMapBanner(inDungeon)
	if not (ns.db and ns.db.mapBanner and ns.db.enabled and not inDungeon) then
		if state.banner then state.banner:Hide() end
		return
	end
	local now = GetTime()
	if state.bannerAt and now - state.bannerAt < 0.05 then
		return
	end
	state.bannerAt = now
	local stitch, S = ns.StitchWorld()
	local over = ns.IsHoveringCanvas and ns.IsHoveringCanvas() or false
	local zMap, cx, cy
	if ns.IsSeamless() and stitch and S and S.ChainAt then
		local u, v
		if over then u, v = stitch.CursorWorld() end
		if not u then u, v = stitch.ViewNow() end
		if u then
			local list = S.ChainAt(u, v)
			for k = #list, 1, -1 do
				local id = list[k]
				local info = C_Map.GetMapInfo(id)
				if info and info.mapType >= Enum.UIMapType.Zone then
					zMap = id
					if over then cx, cy = stitch.FromWorld(id, u, v) end
					break
				end
			end
		end
	end
	if not zMap then
		zMap = ns.CurrentMap()
		if zMap and over then
			cx, cy = WorldMapFrame:GetNormalizedCursorPosition()
		end
	end
	local info = zMap and C_Map.GetMapInfo(zMap)
	if not (info and info.name) then
		if state.banner then state.banner:Hide() end
		return
	end
	local parts = { "|cffffe6b3" .. info.name .. "|r" }
	local D = ns.DATA
	local zl = D and D.zones and D.zones[zMap]
	if zl and info.mapType == Enum.UIMapType.Zone then
		local mid = math.floor((zl[1] + zl[2]) / 2)
		local dc = GetQuestDifficultyColor and GetQuestDifficultyColor(mid)
		local hex = dc and ("ff%02x%02x%02x"):format(math.floor(dc.r * 255 + .5), math.floor(dc.g * 255 + .5), math.floor(dc.b * 255 + .5)) or "ffd2b48c"
		local range = zl[1] == zl[2] and tostring(zl[1]) or (zl[1] .. "-" .. zl[2])
		parts[#parts + 1] = ("|c%s(%s)|r"):format(hex, range)
	end
	if cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
		parts[#parts + 1] = ("|cff888888-|r  %.1f, %.1f"):format(cx * 100, cy * 100)
	end
	local ppos = C_Map.GetPlayerMapPosition(zMap, "player")
	if ppos then
		local px, py = ppos.x, ppos.y
		if ppos.GetXY then px, py = ppos:GetXY() end
		if px and py and not issecretvalue(px) and not issecretvalue(py) and (px ~= 0 or py ~= 0) then
			parts[#parts + 1] = ("|cff888888-|r  |cff7fd4ffYou %.1f, %.1f|r"):format(px * 100, py * 100)
		end
	end
	local line = table.concat(parts, " ")
	local b = EnsureBanner()
	if line ~= state.bannerLine then
		state.bannerLine = line
		b.text:SetText(line)
		b:SetWidth(math.max(120, b.text:GetStringWidth() + 22))
	end
	b:Show()
end

---------------------------------------------------------------------------
-- Unmapped-Quest Zone Lookup & HUD Veil Overlay
---------------------------------------------------------------------------
local function QuestHeader(q)
	local idx = ns.QuestLogIndex(q)
	for k = idx or 0, 1, -1 do
		local info = ns.QuestInfo(k)
		if info and info.isHeader then return info.title end
	end
	return nil
end

local function MapNamed(name)
	if not state.mapByName then
		state.mapByName = {}
		local roots = { C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID() or 0, 946 }
		for _, root in ipairs(roots) do
			for _, info in ipairs(root ~= 0 and C_Map.GetMapChildrenInfo(root, nil, true) or {}) do
				if info.name and not state.mapByName[info.name] then state.mapByName[info.name] = info.mapID end
			end
		end
	end
	return state.mapByName[name]
end

local function ShowVeil(title, zone)
	if not state.veil then
		local v = CreateFrame("Button", nil, WorldMapFrame.ScrollContainer)
		v:SetAllPoints()
		v:SetFrameLevel(WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST") + 5)
		local bg = v:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, .82)
		v.title = v:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		v.title:SetPoint("BOTTOM", v, "CENTER", 0, 14)
		v.title:SetWidth(520)
		v.text = v:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		v.text:SetPoint("TOP", v, "CENTER", 0, 0)
		v.text:SetWidth(460)
		v.hint = v:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		v.hint:SetPoint("TOP", v.text, "BOTTOM", 0, -12)
		v.hint:SetText("Click to close")
		v:SetScript("OnClick", function(self) self:Hide() end)
		v:SetScript("OnHide", function(self) self:Hide() end)
		state.veil = v
	end
	state.veil.title:SetText(title)
	state.veil.text:SetText("No map location: the game has none for this quest, and QuestieDB doesn't list a spawn for it"
		.. (zone and (".\nThe quest log files it under " .. zone .. ", which has no map of its own.") or "."))
	state.veil.mapID = WorldMapFrame:GetMapID()
	state.veil:Show()
end

function ns.HideVeilIfMoved(curMap)
	if state.veil and state.veil:IsShown() and state.veil.mapID ~= curMap then
		state.veil:Hide()
	end
end

function ns.ShowUnmappedQuestFallback(q)
	local zone = QuestHeader(q)
	local mapID = zone and MapNamed(zone)
	local title = ns.QuestTitle(q) or tostring(q)
	if not mapID then
		ShowVeil(title, zone)
		return
	end
	if ns.ShowMapByID then ns.ShowMapByID(mapID) end
	if not state.toldNoMap[q] then
		state.toldNoMap[q] = true
		ns.Print(("no exact spot for \"%s\": showing its zone, %s."):format(title, zone))
	end
end
