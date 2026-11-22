-- daves_map / PanelNav.lua
-- Sidebar state owner, left-rail tab controller (`Layers`, `Zone`, `Dungeon`), inline chain-expansion state,
-- `< Back` navigation history, Dungeon View sync, and full-text search controller.

local _, ns = ...

local Sound = ns.Sound

ns.PANEL_CONST = {
	WIDTH = 588,
	MIN_H = 380,
	RAIL_W = 46,
	PAD = 12,
	LIST_PAD = 4,
	ROW_PAD = 4,
	SCROLL_GUTTER = 16,
	ROW_H = 34,
	MAX_RESULTS = 500,
	MAX_HISTORY = 24,
}

local MAX_HISTORY = ns.PANEL_CONST.MAX_HISTORY

local ui = {
	rows = {},
	items = {},
	counts = {},
	metaCache = {},
	tabs = {},
	history = {},
	scrollByKey = {},
	expandedChains = {},   -- [starterPin] = true | false (nil = auto-expand when player is currently on a step)
	scrollPx = 0,
	totalH = 0,
	lastKey = nil,
	restoring = false,
	quietSearch = false,
	dungeonOpenPin = nil,
	dungeonOpenName = nil,
	zoneContextLock = nil,
	dungeonZoneLock = nil,
	haystack = nil,
	trackerPinCache = {},
	found = nil,
	searchOriginMap = nil,
	trackerFocusQ = nil,
	revealPin = nil,
	revealItemIdx = nil,
	syncingScroll = false,
	ready = false,
	dirtyHidden = false,
	dragging = false,
}
ns.PanelUI = ui

---------------------------------------------------------------------------
-- Shared Text Sanitizers
---------------------------------------------------------------------------
local function Shorten(s, maxLen)
	if not s or s == "" then return "" end
	s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	local lim = maxLen or 200
	if #s <= lim then return s end
	-- Cut safely on UTF-8 boundaries and never leave an incomplete WoW |c color code or unclosed color escape.
	local cut = math.max(1, lim - 3)
	while cut > 1 do
		local b = s:byte(cut)
		if b and b >= 128 and b < 192 then
			cut = cut - 1
		else
			break
		end
	end
	if cut > 1 then
		local b = s:byte(cut)
		if b and b >= 192 then
			local seqLen = b >= 240 and 4 or (b >= 224 and 3 or 2)
			if cut + seqLen - 1 > lim - 3 then cut = cut - 1 end
		end
	end
	local out = s:sub(1, cut)
	out = out:gsub("|c%x?%x?%x?%x?%x?%x?%x?$", ""):gsub("|$", ""):gsub("%s+$", "")
	local _, nOpen = out:gsub("|c%x%x%x%x%x%x%x%x", "")
	local _, nClose = out:gsub("|r", "")
	if nOpen > nClose then out = out .. "|r" end
	return out .. "..."
end
ns.Shorten = Shorten

local function StripCodes(s)
	if not s or s == "" then return "" end
	return s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end
ns.StripCodes = StripCodes

-- 3-slice beveled brass pill backdrop (`Media/pill.tga`, 128x64): preserves exact 1:1 rounded caps and
-- identical border thickness on all 4 sides at any button width (no horizontal edge stretching).
function ns.AddBrassPillSlices(parent, layer, capW, blend, alpha, r, g, b)
	local tex = ns.MEDIA .. "pill"
	local left = parent:CreateTexture(nil, layer)
	left:SetTexture(tex)
	left:SetTexCoord(0, 0.25, 0, 1)
	left:SetWidth(capW)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")

	local right = parent:CreateTexture(nil, layer)
	right:SetTexture(tex)
	right:SetTexCoord(0.75, 1, 0, 1)
	right:SetWidth(capW)
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")

	local mid = parent:CreateTexture(nil, layer)
	mid:SetTexture(tex)
	mid:SetTexCoord(0.25, 0.75, 0, 1)
	mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
	mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")

	local parts = { left, mid, right }
	for _, t in ipairs(parts) do
		if blend then t:SetBlendMode(blend) end
		if r then t:SetVertexColor(r, g, b, alpha or 1) elseif alpha then t:SetAlpha(alpha) end
	end
	return {
		SetShown = function(_, on) for _, t in ipairs(parts) do t:SetShown(on) end end,
		Show = function() for _, t in ipairs(parts) do t:Show() end end,
		Hide = function() for _, t in ipairs(parts) do t:Hide() end end,
		SetAlpha = function(_, a) for _, t in ipairs(parts) do t:SetAlpha(a) end end,
		SetVertexColor = function(_, vr, vg, vb, va)
			for _, t in ipairs(parts) do t:SetVertexColor(vr, vg, vb, va) end
		end,
	}
end

-- Compact beveled brass number pill matching the chain step pill (`Media/pill.tga`),
-- used in both Dave's Map quest rows and the on-screen Objective Tracker to show how many
-- group members currently have a quest, with a hover tooltip listing those group members.
local function ResolveTooltipAnchor(owner, anchorSide)
	if anchorSide ~= "AUTO" then return anchorSide or "ANCHOR_RIGHT" end
	local cx = owner and owner.GetCenter and owner:GetCenter()
	local os = owner and owner.GetEffectiveScale and owner:GetEffectiveScale()
	local uw = UIParent and UIParent.GetWidth and UIParent:GetWidth()
	local us = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
	if type(cx) == "number" and not issecretvalue(cx)
		and type(os) == "number" and not issecretvalue(os)
		and type(uw) == "number" and not issecretvalue(uw) and uw > 0
		and type(us) == "number" and not issecretvalue(us) and us > 0 then
		return (cx * os) >= (uw * us * 0.5) and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
	end
	return "ANCHOR_LEFT"
end

function ns.ShowGroupQuestTooltip(owner, questID, anchorSide)
	if not (owner and not issecretvalue(questID) and type(questID) == "number" and questID ~= 0) then
		if owner and GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
		return
	end
	local units = ns.GroupQuestMembers and ns.GroupQuestMembers(questID) or nil
	if not (units and #units > 0) then
		if GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
		return
	end
	GameTooltip:SetOwner(owner, ResolveTooltipAnchor(owner, anchorSide))
	local qTitle = ns.QuestTitle and ns.QuestTitle(questID)
	if (type(qTitle) ~= "string" or issecretvalue(qTitle) or qTitle == "") and ns.DATA and ns.QuestPin then
		local pin = ns.QuestPin(questID)
		qTitle = pin and ns.DATA.title and ns.DATA.title[pin] or nil
	end
	if type(qTitle) == "string" and not issecretvalue(qTitle) and qTitle ~= "" then
		GameTooltip:AddLine(qTitle, 1, 0.82, 0.2, true)
	end
	GameTooltip:AddLine(("Group members on quest (%d):"):format(#units), 0.5, 0.83, 1)
	for _, unit in ipairs(units) do
		local name = UnitName and UnitName(unit)
		local classFile
		if UnitClass then
			_, classFile = UnitClass(unit)
		end
		local r, g, b = 1, 1, 1
		if type(classFile) == "string" and not issecretvalue(classFile) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
			local cc = RAID_CLASS_COLORS[classFile]
			r, g, b = cc.r, cc.g, cc.b
		end
		if not issecretvalue(name) then
			if type(name) == "string" and name ~= "" then
				GameTooltip:AddLine(unit == "player" and (name .. " (You)") or name, r, g, b)
			else
				GameTooltip:AddLine(unit == "player" and "You" or "Group member", r, g, b)
			end
		else
			if not pcall(GameTooltip.AddLine, GameTooltip, name, r, g, b) then
				GameTooltip:AddLine("Group member", r, g, b)
			end
		end
	end
	GameTooltip:Show()
end

function ns.CreateGroupCountPill(parent, height, capW, fontObj, anchorSide, clickable)
	local h = height or 21
	local c = capW or 10
	local f = CreateFrame(clickable and "Button" or "Frame", nil, parent)
	f:SetSize(h + 4, h)
	f:EnableMouse(true)
	if clickable then
		f:RegisterForClicks("LeftButtonUp", "Button4Up")
	end
	f.baseH = h
	f.anchorSide = anchorSide or "ANCHOR_RIGHT"
	f.frame = ns.AddBrassPillSlices(f, "BACKGROUND", c)
	f.hl = ns.AddBrassPillSlices(f, "ARTWORK", c, "ADD", 0.28)
	f.hl:Hide()
	f.lbl = f:CreateFontString(nil, "OVERLAY")
	if type(fontObj) == "table" then
		f.lbl:SetFontObject(fontObj)
	else
		f.lbl:SetFontObject(fontObj or "GameFontHighlightSmall")
	end
	f.lbl:SetPoint("CENTER", 0, 0)
	f.lbl:SetJustifyH("CENTER")
	f.lbl:SetJustifyV("MIDDLE")
	f.lbl:SetWordWrap(false)
	f:SetScript("OnEnter", function(self)
		if self.hl then self.hl:Show() end
		if self.questID and ns.ShowGroupQuestTooltip then
			ns.ShowGroupQuestTooltip(self, self.questID, self.anchorSide)
		end
	end)
	f:SetScript("OnLeave", function(self)
		if self.hl then self.hl:Hide() end
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	f:SetScript("OnHide", function(self)
		if self.hl then self.hl:Hide() end
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	f:Hide()
	return f
end

function ns.StyleGroupCountPill(badge, count)
	if not badge then return 0 end
	local n = tonumber(count) or 0
	local txt = tostring(n)
	local w = (badge.baseH or 21) + (#txt >= 2 and 10 or 4)
	badge:SetWidth(w)
	if n >= 2 then
		badge.frame:SetVertexColor(0.90, 0.86, 0.72, 0.96)
		badge.lbl:SetText("|cff7fd4ff" .. txt .. "|r")
	else
		badge.frame:SetVertexColor(0.74, 0.70, 0.60, 0.80)
		badge.lbl:SetText("|cff9ea4b0" .. txt .. "|r")
	end
	return w
end

function ns.RefreshIfMapHidden()
	if WorldMapFrame and not WorldMapFrame:IsVisible() and ns.OnLayerChanged then
		ns.OnLayerChanged()
	end
end

---------------------------------------------------------------------------
-- Inline Chain Expansion State (`Zone` & `Dungeon` Reference Lists)
---------------------------------------------------------------------------
function ns.IsChainExpanded(starterPin, hasInLogStep)
	local explicit = ui.expandedChains[starterPin]
	if explicit ~= nil then return explicit end
	return hasInLogStep == true
end

function ns.ToggleChainExpanded(starterPin, currentlyExpanded)
	if not starterPin then return false end
	local nextVal = not currentlyExpanded
	ui.expandedChains[starterPin] = nextVal
	return nextVal
end

---------------------------------------------------------------------------
-- Full-Text Search (Titles, Descriptions, Reward Items, Categories & Zones)
---------------------------------------------------------------------------
local function Haystack(i)
	local D = ns.DATA
	if not ui.haystack then ui.haystack = {} end
	local h = ui.haystack[i]
	if not h then
		local text = StripCodes(D.text[i])
		local rewNames = ""
		if D.rew and D.rew[i] and D.iname then
			local rparts = {}
			for _, iid in ipairs(D.rew[i]) do
				if D.iname[iid] then rparts[#rparts + 1] = D.iname[iid] end
			end
			if #rparts > 0 then rewNames = " " .. table.concat(rparts, " ") end
		end
		h = (D.title[i] .. " " .. text .. rewNames .. " " .. D.cats[D.cat[i]].title .. " " .. (ns.ZoneName(i) or "")):lower()
		if ns.IsCalibrated() then ui.haystack[i] = h end
	end
	return h
end

local function ApplySearchText(raw)
	local D = ns.DATA
	local text = (raw and not issecretvalue(raw) and raw or ""):lower():match("^%s*(.-)%s*$")
	if #text < 2 or not D then
		ui.found = nil
		ui.searchOriginMap = nil
		ns.SetSearch(nil)
	else
		if not ui.searchOriginMap then
			ui.searchOriginMap = (ns.ViewZoneMap and ns.ViewZoneMap()) or (ns.CurrentMap and ns.CurrentMap())
		end
		local words = {}
		for w in text:gmatch("%S+") do words[#words + 1] = w end
		local set = {}
		ui.found = {}
		for i = 1, #D.x do
			local h = Haystack(i)
			local ok = true
			for _, w in ipairs(words) do
				if not h:find(w, 1, true) then ok = false; break end
			end
			if ok then
				set[i] = true
				ui.found[#ui.found + 1] = i
			end
		end
		ns.SetSearch(set)
	end
end

local function SetSearchQuiet(text)
	if not ui.search then return end
	ui.quietSearch = true
	ui.search:SetText(text or "")
	if ui.search.Instructions then
		ui.search.Instructions:SetShown((text or "") == "")
	end
	if ui.search.clearButton then
		ui.search.clearButton:SetShown((text or "") ~= "")
	end
	ApplySearchText(text or "")
	ui.quietSearch = false
end
ns.SetSearchQuiet = SetSearchQuiet

function ns.RunSearch()
	if ui.quietSearch or not ui.search then return end
	ns.Calibrate()
	ApplySearchText(ui.search:GetText())
	ns.RefreshIfMapHidden()
end

---------------------------------------------------------------------------
-- Objective Tracker Under-the-Hood Quest Lookup & Focused View
---------------------------------------------------------------------------
local function MatchWords(text, words)
	for _, w in ipairs(words) do
		if not text:find(w, 1, true) then return false end
	end
	return true
end

function ns.FindQuestPinsForTracker(q)
	local D = ns.DATA
	local title = ns.QuestTitle and ns.QuestTitle(q) or nil
	if not (D and ns.Calibrate()) then return {}, title end

	local clean = type(title) == "string" and title:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ") or ""
	local f = ns.factions
	local facKey = f and ((f[1] and "1" or "0") .. (f[2] and "1" or "0") .. (f[3] and "1" or "0")) or "all"
	local qMap = ns.QuestUiMapID and ns.QuestUiMapID(q) or 0
	if type(qMap) ~= "number" or issecretvalue(qMap) then qMap = 0 end
	local ckey = tostring(q or 0) .. "\1" .. clean .. "\1" .. facKey .. "\1" .. tostring(qMap)
	local cached = ui.trackerPinCache[ckey]
	if cached then return cached, title end

	local out, seen = {}, {}
	local function AddPin(i)
		if i and not seen[i] then
			seen[i] = true
			out[#out + 1] = i
		end
	end

	-- 1. Direct questID / normalized title index lookup (`Quests.lua`)
	local direct = ns.PinsOfQuest and ns.PinsOfQuest(q) or nil
	if direct and #direct > 0 then
		for _, i in ipairs(direct) do
			local ic = D.cats[D.cat[i]] and D.cats[D.cat[i]].icon
			if (ic == "quest" or ic == "repeatable") and ns.PassesPlayerFilter(i) then AddPin(i) end
		end
		if #out == 0 then
			for _, i in ipairs(direct) do AddPin(i) end
		end
	end

	-- 2. Fallback: under-the-hood search by the quest's title (exact title, then title words, then haystack)
	if #out == 0 and #clean >= 2 then
		local words = {}
		for w in clean:gmatch("%S+") do words[#words + 1] = w end
		local exactMatch, titleWords, hayWords = {}, {}, {}
		local exactAny, titleAny, hayAny = {}, {}, {}
		for i = 1, #D.x do
			local ic = D.cats[D.cat[i]] and D.cats[D.cat[i]].icon
			if ic == "quest" or ic == "repeatable" then
				local dt = (D.title[i] or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
				local passFac = ns.PassesPlayerFilter(i)
				if dt == clean then
					exactAny[#exactAny + 1] = i
					if passFac then exactMatch[#exactMatch + 1] = i end
				elseif MatchWords(dt, words) then
					titleAny[#titleAny + 1] = i
					if passFac then titleWords[#titleWords + 1] = i end
				elseif MatchWords(Haystack(i), words) then
					hayAny[#hayAny + 1] = i
					if passFac then hayWords[#hayWords + 1] = i end
				end
			end
		end
		local pick = (#exactMatch > 0 and exactMatch)
			or (#titleWords > 0 and titleWords)
			or (#hayWords > 0 and hayWords)
			or (#exactAny > 0 and exactAny)
			or (#titleAny > 0 and titleAny)
			or hayAny
		for _, i in ipairs(pick) do AddPin(i) end
	end

	-- Prefer pins on the quest's active objective map when multiple candidates match
	if #out > 1 and qMap ~= 0 then
		table.sort(out, function(a, b)
			local ma = (D.map and D.map[a] == qMap)
			local mb = (D.map and D.map[b] == qMap)
			if ma ~= mb then return ma end
			return a < b
		end)
	end

	ui.trackerPinCache[ckey] = out
	return out, title
end

function ns.ClearTrackerFocus()
	ui.trackerFocusQ = nil
end

function ns.TrackerFocusQuestID()
	return ui.trackerFocusQ
end

function ns.OpenTrackerTab(q, preferredPin)
	local D = ns.DATA
	if not (ns.db and D) then return end
	if ns.PushNavState then ns.PushNavState("tracker") end
	if ns.IsDungeonViewShown and ns.IsDungeonViewShown() and ns.CloseDungeonView then
		ns.CloseDungeonView()
	end
	if ui.found then SetSearchQuiet("") end
	ui.zoneContextLock = nil
	ui.dungeonZoneLock = nil
	ui.trackerFocusQ = q
	ns.db.panelTab = "tracker"
	if ns.SetRefLayer then ns.SetRefLayer(nil, true, true) end
	if ns.db.zoneFold then
		ns.db.zoneFold["trk:focused"] = false
	end
	local pin = preferredPin
	if not pin and q then
		local pins = ns.FindQuestPinsForTracker(q)
		pin = pins and pins[1] or nil
	end
	if pin and ns.ChainFor then
		local ch = ns.ChainFor(pin)
		if ch and #ch.steps > 1 then
			ui.expandedChains[ch.steps[1]] = true
		end
	end
	ui.scrollPx = 0
	if ns.UpdateFocus then ns.UpdateFocus(false) end
	if ns.UpdatePanel then ns.UpdatePanel() end
	if ns.Refresh then
		ns.Refresh()
	elseif ns.OnLayerChanged then
		ns.OnLayerChanged()
	end
end

---------------------------------------------------------------------------
-- Navigation History (< Back), Tab Selection & Tracker Reveal
---------------------------------------------------------------------------
local TAB_NAMES = {
	layers = "Base",
	tracker = "Tracker",
	zone = "Zone",
	dungeon = "Dungeon",
}

local function CaptureNavEntry(reason)
	local rawSearch = ui.search and ui.search:GetText()
	local sTxt = (rawSearch and not issecretvalue(rawSearch)) and rawSearch or ""
	local zMap = (ns.ViewZoneMap and ns.ViewZoneMap()) or ns.CurrentMap()
	local zInfo = zMap and C_Map.GetMapInfo(zMap)
	return {
		reason = reason,
		tab = ns.db and ns.db.panelTab or "layers",
		refMode = ns.RefLayerMode and ns.RefLayerMode() or nil,
		pin = ns.FocusedPin(),
		search = sTxt,
		key = ui.lastKey,
		scrollPx = ui.scrollPx or 0,
		mapState = ns.CaptureMapState and ns.CaptureMapState() or nil,
		zoneName = zInfo and zInfo.name or nil,
		dungeonOpen = ns.IsDungeonViewShown and ns.IsDungeonViewShown() or false,
		dungeonPin = ui.dungeonOpenPin,
		dungeonTitle = ui.dungeonOpenName,
		zoneContextLock = ui.zoneContextLock,
		dungeonZoneLock = ui.dungeonZoneLock,
		trackerFocusQ = ui.trackerFocusQ,
	}
end

local function PushNavState(reason)
	if ui.restoring or not ns.db then return end
	if ui.lastKey then ui.scrollByKey[ui.lastKey] = ui.scrollPx end
	local entry = CaptureNavEntry(reason)
	local top = ui.history[#ui.history]
	if top and top.tab == entry.tab and top.refMode == entry.refMode and top.pin == entry.pin
		and top.search == entry.search and top.dungeonOpen == entry.dungeonOpen
		and top.zoneContextLock == entry.zoneContextLock
		and top.dungeonZoneLock == entry.dungeonZoneLock
		and top.trackerFocusQ == entry.trackerFocusQ
		and ((not top.mapState and not entry.mapState) or (top.mapState and entry.mapState and top.mapState.map == entry.mapState.map)) then
		top.scrollPx = entry.scrollPx
		top.mapState = entry.mapState
		return
	end
	ui.history[#ui.history + 1] = entry
	if #ui.history > MAX_HISTORY then table.remove(ui.history, 1) end
end
ns.PushNavState = PushNavState

local function PruneSameHistoryTop()
	local rawSearch = ui.search and ui.search:GetText()
	local sTxt = (rawSearch and not issecretvalue(rawSearch)) and rawSearch or ""
	local curTab = ns.db and ns.db.panelTab or "layers"
	local curRef = ns.RefLayerMode and ns.RefLayerMode() or nil
	local curPin = ns.FocusedPin()
	local dungShown = ns.IsDungeonViewShown and ns.IsDungeonViewShown() or false
	while #ui.history > 0 do
		local top = ui.history[#ui.history]
		if top.tab == curTab and top.refMode == curRef and top.pin == curPin
			and (top.search or "") == sTxt and top.dungeonOpen == dungShown
			and top.zoneContextLock == ui.zoneContextLock
			and top.dungeonZoneLock == ui.dungeonZoneLock
			and top.trackerFocusQ == ui.trackerFocusQ then
			table.remove(ui.history)
		else
			break
		end
	end
end

local function DescribeBackTarget()
	local D = ns.DATA
	local dungShown = ns.IsDungeonViewShown and ns.IsDungeonViewShown() or false
	PruneSameHistoryTop()
	local top = ui.history[#ui.history]
	if dungShown and (not top or not top.dungeonOpen) then
		local dName = ui.dungeonOpenName or "dungeon"
		local where = (top and top.zoneName) or "the world map"
		return true, "Back to World Map", ("Close %s floor map and return to %s (or right-click map / press Esc)."):format(dName, where)
	end
	if not top then
		return false, "Back", "After switching tabs, searching, or opening a dungeon floor map, click here (or press Mouse Back) to return right where you were."
	end
	if top.dungeonOpen and top.dungeonTitle then
		return true, "Back to " .. top.dungeonTitle .. " Map", "Re-open the dungeon floor map."
	end
	if top.search and top.search ~= "" then
		return true, ("Back to Search \"%s\""):format(Shorten(top.search, 22)), "Restore your previous search results and scroll position."
	end
	if top.pin and D and D.title[top.pin] and top.pin ~= ns.FocusedPin() then
		return true, "Back to " .. Shorten(D.title[top.pin], 28), "Return to the previously highlighted quest."
	end
	local tabLbl = TAB_NAMES[top.tab] or "Base"
	local zSuffix = top.zoneName and (" (" .. top.zoneName .. ")") or ""
	return true, "Back to " .. tabLbl .. zSuffix, "Restore your previous tab, reference layer, map position, and scroll offset."
end
ns.DescribeBackTarget = DescribeBackTarget

function ns.GoBack()
	local canBack = DescribeBackTarget()
	if not canBack then return false end
	local dungShown = ns.IsDungeonViewShown and ns.IsDungeonViewShown() or false
	Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	local top = ui.history[#ui.history]
	if dungShown and (not top or not top.dungeonOpen) then
		if top and top.reason == "dungeon" then
			table.remove(ui.history)
		end
		if ns.CloseDungeonView then ns.CloseDungeonView() end
		if ns.RefreshControls then ns.RefreshControls() end
		return true
	end
	if not top then return false end
	local entry = table.remove(ui.history)
	ui.restoring = true
	ns.db.panelTab = entry.tab or "layers"
	local wantRef = (ns.db.panelTab == "zone" or ns.db.panelTab == "dungeon") and ns.db.panelTab or nil
	SetSearchQuiet(entry.search or "")
	if entry.key then ui.scrollByKey[entry.key] = entry.scrollPx or 0 end
	if ns.SetRefLayer then ns.SetRefLayer(wantRef, true) end
	ui.zoneContextLock = wantRef == "zone" and entry.zoneContextLock or nil
	ui.dungeonZoneLock = wantRef == "dungeon" and entry.dungeonZoneLock or nil
	if wantRef == "zone" and ui.zoneContextLock and ns.PinRefZone then
		ns.PinRefZone(ui.zoneContextLock, true)
	elseif wantRef == "dungeon" and ui.dungeonZoneLock and ns.PinRefZone then
		ns.PinRefZone(ui.dungeonZoneLock, false)
	end
	ns.SetFocusedPin(entry.pin, true)
	ui.trackerFocusQ = entry.trackerFocusQ
	if not wantRef and ns.UpdateFocus then ns.UpdateFocus(false) end
	if entry.pin then
		if ns.SyncQuestDetailsPane then
			ns.SyncQuestDetailsPane(ns.FocusedPin(), entry.mapState and entry.mapState.map)
		end
	elseif ns.CloseQuestDetailsIfShown then
		ns.CloseQuestDetailsIfShown()
	end
	if entry.dungeonOpen and (entry.dungeonPin or entry.dungeonTitle) and ns.OpenInstancePin then
		ui.dungeonOpenPin, ui.dungeonOpenName = entry.dungeonPin, entry.dungeonTitle
		if not ns.OpenInstancePin(entry.dungeonPin, ui.panel, entry.dungeonTitle, true) and ns.RestoreMapState then
			ui.dungeonOpenPin, ui.dungeonOpenName = nil, nil
			ns.RestoreMapState(entry.mapState)
		end
	elseif ns.RestoreMapState then
		ns.RestoreMapState(entry.mapState)
	end
	if ns.Refresh then
		ns.Refresh()
	elseif ns.OnLayerChanged then
		ns.OnLayerChanged()
	end
	if entry.scrollPx then
		ui.scrollPx = entry.scrollPx
		if ns.RenderPanelRows then ns.RenderPanelRows() end
	end
	ui.restoring = false
	return true
end

function ns.IsRestoringNav()
	return ui.restoring == true
end

function ns.HasZoneContextLock()
	return ui.zoneContextLock ~= nil
end

function ns.HasDungeonContextLock()
	return ui.dungeonZoneLock ~= nil
end

function ns.HasRefContextLock()
	return ui.zoneContextLock ~= nil or ui.dungeonZoneLock ~= nil
end

function ns.ActiveZoneContext()
	local pinned = (ns.RefLayerMode and ns.RefLayerMode() == "zone" and ns.PinnedRefZone and ns.PinnedRefZone()) or nil
	if pinned then return pinned end
	if ui.zoneContextLock then return ui.zoneContextLock end
	return (ns.ViewZoneMap and ns.ViewZoneMap()) or ns.CurrentMap()
end

function ns.ActiveDungeonZone()
	local pinned = (ns.RefLayerMode and ns.RefLayerMode() == "dungeon" and ns.PinnedRefZone and ns.PinnedRefZone()) or nil
	if pinned then return pinned end
	if ui.dungeonZoneLock then return ui.dungeonZoneLock end
	return (ns.ViewZoneMap and ns.ViewZoneMap()) or ns.CurrentMap()
end

function ns.LockDungeonContext(mapID)
	local D = ns.DATA
	local zMap = mapID or ui.zoneMap or (ns.ViewZoneMap and ns.ViewZoneMap()) or ns.CurrentMap()
	if zMap and D and D.dungeons and D.dungeons[zMap] and #D.dungeons[zMap] > 0 then
		ui.dungeonZoneLock = zMap
		if ns.PinRefZone then ns.PinRefZone(zMap, false) end
	end
end

function ns.LockRefContext(tabKey, mapID, targetPin)
	if tabKey == "dungeon" then
		ns.LockDungeonContext(mapID)
	elseif tabKey == "zone" then
		local zMap = mapID or ui.zoneMap or (ns.ViewZoneMap and ns.ViewZoneMap()) or ns.CurrentMap()
		if zMap then
			ui.zoneContextLock = zMap
			if ns.PinRefZone then ns.PinRefZone(zMap, true) end
		end
	end
	if targetPin and ns.NoteSidebarNavTarget then
		ns.NoteSidebarNavTarget(targetPin)
	end
end

function ns.ClearRefContext()
	ui.zoneContextLock = nil
	ui.dungeonZoneLock = nil
	if ns.PinRefZone then ns.PinRefZone(nil) end
end

function ns.ClearDungeonContext()
	ui.dungeonZoneLock = nil
	if (not ns.RefLayerMode or ns.RefLayerMode() ~= "zone") and ns.PinRefZone then
		ns.PinRefZone(nil)
	end
end

function ns.SwitchZoneContext(mapID)
	if not mapID then return end
	PushNavState("zone_ctx")
	Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	ui.zoneContextLock = nil
	if ns.PinRefZone then ns.PinRefZone(nil) end
	if ns.RefLayerMode and ns.RefLayerMode() == "zone" and ns.Refresh then
		ns.Refresh()
	elseif ns.OnLayerChanged then
		ns.OnLayerChanged()
	end
end

function ns.SwitchDungeonZone(mapID)
	if not mapID then return end
	PushNavState("dung_zone")
	Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	ui.dungeonZoneLock = nil
	if ns.PinRefZone then ns.PinRefZone(nil) end
	if ns.RefLayerMode and ns.RefLayerMode() == "dungeon" and ns.Refresh then
		ns.Refresh()
	elseif ns.OnLayerChanged then
		ns.OnLayerChanged()
	end
end

function ns.SelectSidebarTab(tabKey)
	if not ns.db then return end
	local curTab = ns.db.panelTab or "layers"
	local searching = ui.found ~= nil
	local dungShown = ns.IsDungeonViewShown and ns.IsDungeonViewShown() or false

	if not searching and curTab == tabKey then
		if dungShown and ns.CloseDungeonView then
			Sound("IG_CHARACTER_INFO_TAB")
			ns.CloseDungeonView()
			if ns.RefreshControls then ns.RefreshControls() end
			return
		end
		if (tabKey == "zone" or tabKey == "dungeon") and ns.HasRefContextLock and ns.HasRefContextLock() then
			Sound("IG_CHARACTER_INFO_TAB")
			if ns.OnUserMapNavigate then ns.OnUserMapNavigate(false) end
			return
		end
		Sound("IG_CHARACTER_INFO_TAB")
		if ui.scrollPx > 0 then
			ui.scrollPx = 0
			if ui.lastKey then ui.scrollByKey[ui.lastKey] = 0 end
			if ns.RenderPanelRows then ns.RenderPanelRows() end
		end
		return
	end

	PushNavState("tab")
	if dungShown and ns.CloseDungeonView then ns.CloseDungeonView() end
	ns.db.panelTab = tabKey
	if searching then SetSearchQuiet("") end
	Sound("IG_CHARACTER_INFO_TAB")
	ui.zoneContextLock = nil
	ui.dungeonZoneLock = nil
	if tabKey == "zone" or tabKey == "dungeon" then
		if not ns.SetRefLayer(tabKey, true) and ns.OnLayerChanged then
			ns.OnLayerChanged()
		end
	else
		-- Both `Base` and `Tracker` stay on the Base map layer (with all Tracker tab quests always visible at any zoom).
		if ns.UpdateFocus then ns.UpdateFocus(false) end
		if not ns.SetRefLayer(nil, true) then
			if ns.Refresh then
				ns.Refresh()
			elseif ns.OnLayerChanged then
				ns.OnLayerChanged()
			end
		end
	end
end

function ns.RevealQuestInPanel(pin, forceTab, _enableRefLayer, exactPin)
	local D = ns.DATA
	if not (ns.db and D and pin) then return end
	PushNavState(exactPin and "map_pin" or "tracker")
	if ns.IsDungeonViewShown and ns.IsDungeonViewShown() and ns.CloseDungeonView then
		ns.CloseDungeonView()
	end
	if ui.found then SetSearchQuiet("") end
	local zMap = (ns.P and ns.P.zone[pin]) or (ns.ViewZoneMap and ns.ViewZoneMap()) or ns.CurrentMap()
	local viewZ = (ns.ViewZoneMap and ns.ViewZoneMap()) or ns.CurrentMap()
	local targetTab = forceTab
	if not targetTab then
		targetTab = (ns.IsDungeonQuestPin and ns.IsDungeonQuestPin(pin, zMap)) and "dungeon" or "zone"
	end
	ns.db.panelTab = targetTab
	local dMap, dName
	if targetTab == "dungeon" and ns.DungeonContextForPin then
		ui.zoneContextLock = nil
		dMap, dName = ns.DungeonContextForPin(pin, zMap)
		ui.dungeonZoneLock = (dMap and dMap ~= viewZ) and dMap or nil
	else
		ui.dungeonZoneLock = nil
		ui.zoneContextLock = (zMap and zMap ~= viewZ) and zMap or nil
	end
	local ch = ns.ChainFor and ns.ChainFor(pin)
	local bucketState = ns.PinQuestState and ns.PinQuestState(pin) or nil
	if ch and #ch.steps > 1 then
		ui.expandedChains[ch.steps[1]] = true
		local activePin, _, inLogPin, allDone = ns.ChainProgress(ch, ch.steps[1])
		if allDone then
			bucketState = "done"
		elseif inLogPin then
			bucketState = ns.PinQuestState(inLogPin)
		else
			bucketState = ns.PinQuestState(activePin)
		end
	end
	if ns.db.zoneFold then
		if bucketState == "ready" or bucketState == "log" then
			ns.db.zoneFold.active = false
		elseif bucketState == "locked" then
			ns.db.zoneFold.locked = false
		elseif bucketState == "done" then
			ns.db.zoneFold.done = false
		else
			ns.db.zoneFold.avail = false
		end
		if dName then ns.db.zoneFold["dung:" .. dName] = false end
	end
	ui.revealPin = exactPin and pin or ((ns.ResolveActiveChainPin and ns.ResolveActiveChainPin(pin)) or pin)
	local lockMap = targetTab == "dungeon" and ui.dungeonZoneLock or ui.zoneContextLock
	if lockMap and ns.NoteSidebarNavTarget then
		ns.NoteSidebarNavTarget(lockMap)
	end
	if ns.UpdatePanel then ns.UpdatePanel() end
	if not ns.SetRefLayer(targetTab, true) then
		if lockMap and ns.SwitchRefZone then
			ns.SwitchRefZone(lockMap)
		elseif ns.PinRefZone then
			ns.PinRefZone(nil)
		end
	end
	if ns.OnLayerChanged then ns.OnLayerChanged() end
end

---------------------------------------------------------------------------
-- Dungeon Floor Map Navigation Hooks (Stitch/Dungeons.lua)
---------------------------------------------------------------------------
function ns.BeforeOpenDungeonMap(pin, title)
	PushNavState("dungeon")
	ui.dungeonOpenPin = pin
	ui.dungeonOpenName = title
end

function ns.CancelOpenDungeonMap()
	local top = ui.history[#ui.history]
	if top and top.reason == "dungeon" then
		table.remove(ui.history)
	end
	ui.dungeonOpenPin, ui.dungeonOpenName = nil, nil
end

local function MatchDungeonPin(instName)
	local D = ns.DATA
	if not (instName and D and D.dungeons and ns.NormDungKey) then return nil end
	local want = ns.NormDungKey(instName)
	if want == "" then return nil end
	for _, dlist in pairs(D.dungeons) do
		for _, d in ipairs(dlist) do
			if d.pin and d.pin ~= 0 then
				local k = ns.NormDungKey(d.name)
				if k == want or want:find(k, 1, true) or k:find(want, 1, true) then
					return d.pin
				end
			end
		end
	end
	return nil
end

function ns.OnDungeonViewChanged(shown, instName)
	local D = ns.DATA
	if shown then
		if instName then
			ui.dungeonOpenName = instName
			if ui.dungeonOpenPin and D and D.title[ui.dungeonOpenPin] and ns.NormDungKey then
				local pk = ns.NormDungKey(D.title[ui.dungeonOpenPin])
				local ik = ns.NormDungKey(instName)
				if pk ~= ik and not ik:find(pk, 1, true) and not pk:find(ik, 1, true) then
					ui.dungeonOpenPin = nil
				end
			end
			if not ui.dungeonOpenPin then
				ui.dungeonOpenPin = MatchDungeonPin(instName)
			end
		end
	else
		ui.dungeonOpenPin, ui.dungeonOpenName = nil, nil
	end
	if ui.ready and ns.RefreshControls then
		ns.RefreshControls()
	end
end

function ns.InspectPinFromDungeonView(pin, instName)
	if not (ns.DATA and pin) then return end
	Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	if instName then
		ui.dungeonOpenName = instName
		ui.dungeonOpenPin = MatchDungeonPin(instName) or ui.dungeonOpenPin
	end
	local activePin = (ns.ResolveActiveChainPin and ns.ResolveActiveChainPin(pin)) or pin
	ns.SetFocusedPin(activePin, true)
	ns.RevealQuestInPanel(activePin, "dungeon", true)
	local target = ns.ActivePinTarget and ns.ActivePinTarget(activePin) or activePin
	if ns.SyncQuestDetailsPane then ns.SyncQuestDetailsPane(activePin) end
	ns.ShowPinMap(target, true)
end
