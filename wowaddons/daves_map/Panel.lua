-- daves_map / Panel.lua
-- The search and filter panel beside the world map, laid out like Map Genie's sidebar and dressed like the map it sits
-- next to: the map's own metal frame (NineSlice layout "ButtonFrameTemplateNoPortrait", as Blizzard's button frames)
-- and flat panel background, a gold title, then the quest log's pieces (Blizzard_UIPanels_Game QuestMapFrame.xml):
-- its divider, its parchment list background, its tick boxes and yellow checkmarks, and the list headers its quest
-- log uses (ListHeaderVisualTemplate).
--
-- The list shows one of three things:
--   the selected quest chain: its steps numbered in order, as on the map (click a step on another map to open that
--   map, one on this map for a waypoint)
--   search results: matches on this map first (click to select it, draw its chain and open its map, shift-click for a
--   waypoint)
--   the categories: groups and categories with a tick and how many of their pins are on this map
-- Parented to WorldMapFrame (it shows and hides with it) but never registered with it: nothing of Blizzard's map is
-- written. Windowed it docks beside the map (left if there's room, else right, else inside); maximized it sits inside.

local _, ns = ...

local D
local panel, tab, search, list, status, factionTicks, checks
local rows = {}
local items = {}
local offset = 0
local lastMode
local counts = {}            -- [category index] = pins on this map
local haystack               -- [pin] = lower-case text to search (built on the first search)
local found                  -- the pins matching the current search, or nil
local ROW_H, PAD, WIDTH = 20, 12, 260
local MAX_RESULTS = 500
local FACTIONS = { { "Alliance", .4, .62, 1 }, { "Horde", 1, .35, .35 }, { "Neutral", 1, .82, .2 } }

---------------------------------------------------------------------------
-- The quest log's tick box: a square with a yellow checkmark
---------------------------------------------------------------------------
local function Tick(parent)
	local box = parent:CreateTexture(nil, "ARTWORK")
	box:SetAtlas("questlog-icon-ticksquare", true)
	local mark = parent:CreateTexture(nil, "OVERLAY")
	mark:SetAtlas("questlog-icon-checkmark-yellow", true)
	mark:SetPoint("CENTER", box, "CENTER", 1, 1)
	return {
		box = box,
		SetChecked = function(_, on) mark:SetShown(on and true or false) end,
		SetShown = function(_, on) box:SetShown(on); if not on then mark:Hide() end end,
	}
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function GroupState(gi)
	local on, off = 0, 0
	for _, ci in ipairs(D.groups[gi].cats) do
		if ns.db.hidden[D.cats[ci].id] then off = off + 1 else on = on + 1 end
	end
	return on, off
end

-- a search result is "on map" when its pin is drawn on this map (a table lookup, and the same as the map shows)
local function IsHere(i)
	local map = ns.CurrentMap()
	return map and ns.PinsOnMap(map).x[i] ~= nil or false
end
-- a chain step also counts when it lies inside this map's rectangle (the map draws neighbouring-zone steps there)
local function StepHere(i)
	local x, y = ns.ProjectPin(ns.CurrentMap(), i)
	return x and x >= 0 and x <= 1 and y >= 0 and y <= 1 or false
end
-- the map rebuilds and calls ns.OnLayerChanged itself while it's open; refresh the list directly only when it isn't
local function RefreshIfMapHidden()
	if not WorldMapFrame:IsVisible() then ns.OnLayerChanged() end
end

-- what the list shows now: the chain, the search results or the categories
local function BuildItems()
	wipe(items)
	local chain = ns.Chain()
	local mode
	if chain and #chain.steps > 1 then
		mode = "chain"
		items[1] = { kind = "chainhead", n = #chain.steps }
		for n, i in ipairs(chain.steps) do items[#items + 1] = { kind = "step", i = i, n = n, here = StepHere(i) } end
	elseif found then
		mode = "search"
		local all = {}
		for _, i in ipairs(found) do all[#all + 1] = { kind = "result", i = i, here = IsHere(i) } end
		table.sort(all, function(a, b)
			if a.here ~= b.here then return a.here end
			if D.title[a.i] ~= D.title[b.i] then return D.title[a.i] < D.title[b.i] end
			return a.i < b.i
		end)
		for n = 1, math.min(#all, MAX_RESULTS) do items[n] = all[n] end
	else
		mode = "cats"
		for gi, g in ipairs(D.groups) do
			items[#items + 1] = { kind = "group", gi = gi }
			for _, ci in ipairs(g.cats) do items[#items + 1] = { kind = "cat", ci = ci } end
		end
	end
	if mode ~= lastMode then offset = 0; lastMode = mode end
end

local function LabelAt(row, x)
	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", x, 0)
	row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
end

local function RenderRow(row, item)
	row.item = item
	if not item then row:Hide() return end
	row:Show()
	local header = item.kind == "group" or item.kind == "chainhead"
	row.header:SetShown(header)
	row.tick:SetShown(item.kind == "cat")
	row.icon:SetShown(item.kind == "cat" or item.kind == "result" or item.kind == "step")
	row.num:SetText("")
	row.label:SetText("")
	row.count:SetText("")
	if item.kind == "group" then
		local _, off = GroupState(item.gi)
		row.header:SetText(D.groups[item.gi].title)
		row.header.right:SetText(off == 0 and "Hide all" or "Show all")
	elseif item.kind == "chainhead" then
		row.header:SetText(("Quest chain, %d steps"):format(item.n))
		row.header.right:SetText("Clear")
	elseif item.kind == "cat" then
		local c = D.cats[item.ci]
		row.tick:SetChecked(not ns.db.hidden[c.id])
		row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", 26, 0)
		ns.PaintCategoryIcon(row.icon, item.ci)
		LabelAt(row, 46)
		row.label:SetText(c.title)
		local n = counts[item.ci] or 0
		row.count:SetText(n > 0 and n or "|cff6666660|r")
	else
		local i = item.i
		local x = 6
		if item.kind == "step" then
			-- in the step's colour, the colour of its badge and the line into it on the map
			local chain = ns.Chain()
			row.num:SetText(("|c%s%d.|r"):format(ns.StepHex(item.n, chain and #chain.steps or 1), item.n))
			x = 30
		end
		row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", x, 0)
		ns.PaintCategoryIcon(row.icon, D.cat[i])
		LabelAt(row, x + 20)
		local selected = ns.FocusedPin() == i
		row.label:SetText(selected and ("|cffffd200" .. D.title[i] .. "|r") or D.title[i])
		row.count:SetText(item.here and "|cff59ff73on map|r" or (ns.ZoneName(i) or ""))
	end
end

local function Render()
	if not list then return end
	local n = rows.n or 0
	offset = math.max(0, math.min(offset, #items - n))
	for r = 1, n do RenderRow(rows[r], items[offset + r]) end
	list.more:SetShown(offset + n < #items)
end

-- Every click sounds, as in Blizzard's quest log: a tick for the filters, the quest list's select for a step or a
-- result (a click that turns the map, or sets a waypoint, adds its own map sound in Layer.lua).
local Sound = ns.Sound   -- (Layer.lua, loaded before this: one sound a click)

local function OnRowClick(row)
	local item = row.item
	if not item then return end
	local hidden = ns.db.hidden
	if item.kind == "group" then
		local _, off = GroupState(item.gi)
		for _, ci in ipairs(D.groups[item.gi].cats) do hidden[D.cats[ci].id] = (off == 0) or nil end
		Sound(off == 0 and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.Refresh()
	elseif item.kind == "cat" then
		local id = D.cats[item.ci].id
		hidden[id] = not hidden[id] or nil
		Sound(hidden[id] and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.Refresh()
	elseif item.kind == "chainhead" then
		ns.Focus(ns.FocusedPin())   -- toggles it off (with its own sound)
	elseif item.kind == "step" then   -- the seamless map flies there, zoomed in on it; shift-click: a waypoint
		Sound("IG_QUEST_LIST_SELECT")   -- (without the seamless map: a step on another map opens that map; on this one, a waypoint)
		if IsShiftKeyDown() or not ns.ShowPinMap(item.i, true) then ns.SetWaypoint(item.i) end
	else   -- a search result: select it (its chain is drawn and listed) and open its map; shift-click for a waypoint
		Sound("IG_QUEST_LIST_SELECT")
		if IsShiftKeyDown() then ns.SetWaypoint(item.i) else ns.Focus(item.i); ns.ShowPinMap(item.i) end
	end
	RefreshIfMapHidden()   -- Refresh / Focus already update the list while the map is open
end

local function MakeRow(r)
	local row = CreateFrame("Button", nil, list)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 0, -(r - 1) * ROW_H)
	row:SetPoint("RIGHT")
	row:RegisterForClicks("LeftButtonUp")
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAtlas("questlog-quest-glow-yellow")
	hl:SetAllPoints()
	hl:SetAlpha(.5)
	hl:SetBlendMode("ADD")
	-- group and chain headers: the quest log's list header
	row.header = CreateFrame("Button", nil, row, "ListHeaderVisualTemplate")
	row.header:SetAllPoints()
	row.header:SetFrameLevel(row:GetFrameLevel() + 1)
	row.header.CollapseButton:Hide()
	row.header.right = row.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.header.right:SetPoint("RIGHT", -8, 0)
	row.header:SetScript("OnClick", function() OnRowClick(row) end)
	row.tick = Tick(row)
	row.tick.box:SetPoint("LEFT", 6, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(15, 15)
	row.num = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.num:SetPoint("RIGHT", row, "LEFT", 26, 0)
	row.num:SetJustifyH("RIGHT")
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetJustifyH("LEFT"); row.label:SetWordWrap(false)
	row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.count:SetPoint("RIGHT", -6, 0)
	row.count:SetJustifyH("RIGHT")
	row:SetScript("OnClick", OnRowClick)
	row:SetScript("OnEnter", function(self)
		local item = self.item
		if not item then return end
		if item.kind == "result" or item.kind == "step" then
			ns.ShowTooltip(self, item.i)
		elseif item.kind == "cat" and D.cats[item.ci].info ~= "" then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(D.cats[item.ci].title, 1, 1, 1)
			GameTooltip:AddLine(D.cats[item.ci].info, .9, .9, .9, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end)
	rows[r] = row
	return row
end

local function LayoutRows()
	local n = math.max(1, math.floor(list:GetHeight() / ROW_H))
	for r = 1, n do if not rows[r] then MakeRow(r) end end
	-- spare rows from a taller panel are kept (hidden) for when it grows again
	for r = n + 1, #rows do rows[r]:Hide(); rows[r].item = nil end
	rows.n = n
	Render()
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------
local function Haystack(i)
	if not haystack then haystack = {} end
	local h = haystack[i]
	if not h then
		local text = D.text[i]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		h = (D.title[i] .. " " .. text .. " " .. D.cats[D.cat[i]].title .. " " .. (ns.ZoneName(i) or "")):lower()
		if ns.IsCalibrated() then haystack[i] = h end   -- kept only once the zone names are known
	end
	return h
end

local function RunSearch()
	ns.Calibrate()   -- the zone names, even while the layer is off
	local text = (search:GetText() or ""):lower():match("^%s*(.-)%s*$")
	if #text < 2 then
		found = nil
		ns.SetSearch(nil)
	else
		local words = {}
		for w in text:gmatch("%S+") do words[#words + 1] = w end
		local set = {}
		found = {}
		for i = 1, #D.x do
			local h = Haystack(i)
			local ok = true
			for _, w in ipairs(words) do if not h:find(w, 1, true) then ok = false break end end
			if ok then set[i] = true; found[#found + 1] = i end
		end
		ns.SetSearch(set)
	end
	RefreshIfMapHidden()   -- SetSearch -> Refresh rebuilds the map, which updates the list, while the map is open
end

---------------------------------------------------------------------------
-- Status, counts, docking
---------------------------------------------------------------------------
function ns.OnLayerChanged()
	if not panel then return end
	local map = ns.CurrentMap()
	wipe(counts)
	local onMap = 0
	if map then
		local idx = ns.PinsOnMap(map).idx
		onMap = #idx
		for _, i in ipairs(idx) do counts[D.cat[i]] = (counts[D.cat[i]] or 0) + 1 end
	end
	BuildItems()
	local chain = ns.Chain()
	local s
	if not ns.db.enabled then
		s = "Layer off (/dmap toggle)."
	elseif not ns.IsCalibrated() then
		s = "|cffff6060Couldn't place the pins: no flight points matched. /dmap calib|r"
	elseif lastMode == "chain" then
		s = ("Quest chain: %d steps, numbered on the map."):format(#chain.steps)
	elseif not found and ns.Focused and ns.Focused() then   -- (a search still shows its matches)
		s = ("Focused quest: %d of its pins shown. Click it again to see all."):format(ns.ShownCount())
	elseif ns.IsSeamless and ns.IsSeamless() then   -- the seamless map: the pins round the view, whatever their zone
		s = found and ("%d matches, %d in view."):format(#found, ns.ShownCount()) or ("%d pins in view."):format(ns.ShownCount())
	elseif found then
		s = ("%d matches, %d on this map."):format(#found, ns.ShownCount())
	else
		s = ("%d of %d pins on this map shown."):format(ns.ShownCount(), onMap)
	end
	status:SetText(s .. "\n|cff888888Map Genie data, " .. D.source.fetched .. "|r")
	Render()
end

local docked
local function Dock()
	local room = WIDTH + 8
	local where
	if WorldMapFrame:IsMaximized() then
		where = "inside"
	elseif (WorldMapFrame:GetLeft() or 0) >= room then
		where = "left"
	elseif (UIParent:GetRight() or 0) - (WorldMapFrame:GetRight() or 0) >= room then
		where = "right"
	else
		where = "inside"
	end
	if where == docked then return end
	docked = where
	panel:ClearAllPoints()
	if where == "inside" then
		local sc = WorldMapFrame.ScrollContainer
		panel:SetPoint("TOPLEFT", sc, "TOPLEFT", 10, -48)
		panel:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 10, 10)
	elseif where == "left" then
		panel:SetPoint("TOPRIGHT", WorldMapFrame, "TOPLEFT", -8, 0)
		panel:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMLEFT", -8, 0)
	else
		panel:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 8, 0)
		panel:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT", 8, 0)
	end
end

-- above every pin on the map (Blizzard's run from 2000 to about 2900), so the panel and tab keep their clicks
local function AbovePins()
	return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST") + 10
end

function ns.UpdatePanel()
	if not panel then return end
	panel:SetShown(ns.db.panelOpen)
	tab:SetAlpha(ns.db.panelOpen and .6 or 1)
end

local function RefreshControls()
	if not checks then return end   -- no panel: the map data isn't loaded
	local f = ns.db.factions or {}
	for k, t in ipairs(factionTicks) do t:SetChecked(f[k]) end
	for key, t in pairs(checks) do t:SetChecked(ns.db[key]) end
	local low = checks.hideLowLevel
	if low then
		low.text:SetText(ns.LowLevelLabel())
		low.text:GetParent():SetWidth(low.text:GetStringWidth() + 26)
	end
end
ns.RefreshControls = RefreshControls

-- a line of the quest log's tick box and a label, clickable as a whole
local function TickLine(parent, label, r, g, b, onClick, tooltip)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetHeight(20)
	local t = Tick(btn)
	t.box:SetPoint("LEFT", 0, 0)
	local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT", t.box, "RIGHT", 4, 0)
	text:SetText(label)
	if r then text:SetTextColor(r, g, b) end
	btn:SetWidth(text:GetStringWidth() + 26)
	t.text = text
	btn:SetScript("OnClick", onClick)
	if tooltip then
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(text:GetText(), 1, 1, 1); GameTooltip:AddLine(tooltip, .9, .9, .9, true); GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	return btn, t
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function ns.InitPanel()
	D = ns.DATA
	panel = CreateFrame("Frame", nil, WorldMapFrame)
	panel:SetWidth(WIDTH)
	panel:SetFrameStrata(WorldMapFrame:GetFrameStrata())
	panel:SetFrameLevel(AbovePins())
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:SetScript("OnUpdate", Dock)
	local level = panel:GetFrameLevel()

	-- the map's flat panel background and metal frame
	local bg = CreateFrame("Frame", nil, panel, "FlatPanelBackgroundTemplate")
	bg:SetPoint("TOPLEFT", 0, -2)
	bg:SetPoint("BOTTOMRIGHT", 0, 2)
	bg:SetFrameLevel(level - 1)   -- under the panel's own regions (title, divider, status); still above the map's pins
	local border = CreateFrame("Frame", nil, panel, "NineSlicePanelTemplate")
	border:SetFrameLevel(level + 30)   -- the template's own level (500) is under ours
	NineSliceUtil.ApplyLayoutByName(border, "ButtonFrameTemplateNoPortrait")

	-- the title on a frame of its own above the border, as Blizzard's TitleContainer (the metal top edge would cover it)
	local titleBar = CreateFrame("Frame", nil, panel)
	titleBar:SetAllPoints()
	titleBar:SetFrameLevel(level + 31)
	local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -5)
	title:SetText("Dave's Map")
	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButtonDefaultAnchors")
	close:SetFrameLevel(level + 31)
	close:SetScript("OnClick", function() ns.db.panelOpen = false; ns.UpdatePanel() end)

	search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	search:SetHeight(20)
	search:SetPoint("TOPLEFT", PAD + 6, -32)
	search:SetPoint("TOPRIGHT", -PAD, -32)
	search:HookScript("OnTextChanged", RunSearch)

	-- factions, on one line
	factionTicks = {}
	local prev
	for k, fdef in ipairs(FACTIONS) do
		local btn, t = TickLine(panel, fdef[1], fdef[2], fdef[3], fdef[4], function()
			ns.db.factions[k] = not ns.db.factions[k]
			RefreshControls(); ns.Refresh()
		end)
		if prev then btn:SetPoint("LEFT", prev, "RIGHT", 10, 0) else btn:SetPoint("TOPLEFT", PAD, -58) end
		prev = btn
		factionTicks[k] = t
	end

	-- quest filters
	checks = {}
	local CHECKS = {
		{ "trackMyZone", "Track only my zone's quests", "The quest tracker follows the quests in your log for the zone you're in; the rest are untracked (they stay in your log). It changes as you enter a new zone; on a flight it waits until you land. The map's markers are not affected." },
		{ "hideCompleted", "Hide completed quests", "Completed quests are dimmed; tick to hide them. (Matched to the game's quest IDs through pfQuest.)" },
		{ "otherClasses", "Other classes' quests", "Show quests only other classes can take." },
		{ "hideHighLevel", "Hide quests >5 levels above me", "Hide quests whose required level is more than 5 above yours. Quests up to 5 levels above you still show." },
		{ "hideLowLevel", ns.LowLevelLabel(), "Hide quests whose required level is more than this many levels below yours. Set how many (1 to 5) in /dmap options." },
	}
	for n, def in ipairs(CHECKS) do
		local btn, t = TickLine(panel, def[2], nil, nil, nil, function()
			ns.db[def[1]] = not ns.db[def[1]]
			RefreshControls(); ns.Refresh()
			if def[1] == "trackMyZone" then ns.TrackZoneQuests() end   -- ticked on: follow this zone now
		end, def[3])
		btn:SetPoint("TOPLEFT", PAD, -80 - (n - 1) * 20)
		checks[def[1]] = t
	end

	-- the quest log's divider, then the list on its parchment
	local divider = panel:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas("QuestLog-frame-devider")
	divider:SetPoint("TOPLEFT", 4, -182)
	divider:SetPoint("TOPRIGHT", -4, -182)
	divider:SetHeight(8)
	status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	status:SetPoint("BOTTOMLEFT", PAD, PAD)
	status:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	status:SetJustifyH("LEFT")
	list = CreateFrame("Frame", nil, panel)
	list:SetPoint("TOPLEFT", 6, -190)
	list:SetPoint("BOTTOMRIGHT", -6, PAD + 34)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 3; Render() end)
	local parchment = list:CreateTexture(nil, "BACKGROUND")
	parchment:SetAtlas("QuestLog-main-background")
	parchment:SetAllPoints()
	list.more = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	list.more:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -4, -2)
	list.more:SetText("scroll for more")
	list:SetScript("OnSizeChanged", LayoutRows)

	-- the tab on the map that brings the panel back
	tab = CreateFrame("Button", nil, WorldMapFrame.ScrollContainer)
	tab:SetSize(30, 30)
	tab:SetPoint("BOTTOMLEFT", 6, 6)
	tab:SetFrameLevel(AbovePins())
	local tex = tab:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
	tex:SetTexCoord(.08, .92, .08, .92)
	local tabBorder = CreateFrame("Frame", nil, tab, "NineSlicePanelTemplate")
	tabBorder:SetFrameLevel(tab:GetFrameLevel() + 1)
	NineSliceUtil.ApplyLayoutByName(tabBorder, "InsetFrameTemplate")
	tab:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
	tab:GetHighlightTexture():SetVertexColor(1, 1, 1, .15)
	tab:SetScript("OnClick", function() ns.db.panelOpen = not ns.db.panelOpen; ns.UpdatePanel() end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Dave's Map"); GameTooltip:AddLine("Search and filters", .9, .9, .9); GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip:Hide() end)

	BuildItems()
	RefreshControls()
	ns.UpdatePanel()
	panel:SetScript("OnShow", RefreshControls)
end
