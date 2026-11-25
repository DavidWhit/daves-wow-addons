--------------------------------------------------------------------------------
-- Dungeons: their entrances on the map (ns.MapPlaces, from the game's tables), each with its level
-- range in the game's quest colours for you. Click one for its map (Blizzard's dungeon map, in the
-- same window; with several at one entrance, pick which), and back out the way you came: right-click,
-- the wheel past all the way out, or the card's Back puts the world back where you were.
-- On a dungeon's map, a card of what's in it: its bosses (the game's list, in its order) and, with
-- Questie, the quests for it. Questie knows no places inside dungeons, so they're listed, not pinned;
-- the bosses are pinned where Data/DungeonBosses.lua (or the placer, /openmap bosses) has them.
-- /openmap entrance <name>, standing in a portal: the line for tools/map-data/build.py's ENTRANCES.
--------------------------------------------------------------------------------

-- (daves_map: OpenMap's namespace is the drop-in daves_map_textures', handed over in Base.lua; without it, nothing)
local addonNs = select(2, ...)
local ns = addonNs.OM
if not ns then return end
local S = ns.MapStitch
local mod = ns:GetModule("worldmap")
local Look, Safe, L = ns.Look, ns.Safe, ns.L
mod.padRoots = mod.padRoots or {}

-- (daves_map: from OpenMap/Map/Extras.lua — level range coloured for the player's level)
mod.LevelColor = mod.LevelColor or function(lo, hi)
	local level = Safe.Value(UnitLevel("player")) or 1
	local color
	if level < lo then
		color = GetQuestDifficultyColor(lo)
	elseif level > hi then
		color = GetQuestDifficultyColor(hi - 2)
	end
	color = color or QuestDifficultyColors and QuestDifficultyColors.difficult or { r = 1, g = 0.5, b = 0.25 }
	return ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255), lo == hi and tostring(hi) or (lo .. "-" .. hi)
end

local d = mod.defaults
d.dungeonMaps = true            -- the maps of dungeons and raids (off: the world map, and an entrance's card)
d.dungeonBosses = true          -- the card lists a dungeon's bosses
d.dungeonBossList = false       -- (daves_map: optional on-map Bosses list overlay; off by default since boss/rare markers render directly on the map)
d.bossListDefaultOff = true     -- (daves_map: marks fresh saves as already migrated to dungeonBossList = false)
d.dungeonMinimap = false        -- dungeons' maps from the game's minimap pictures, where there are (else only where there's no other)
d.dungeonQuests = true          -- and its quests (questSource)
d.questSource = "auto"          -- the quests from: "questie", "journal" (Dungeon Journal), "needroll"; "auto": the first there
d.entranceClick = "map"         -- clicking an entrance: "map" (its map here) or "journal" (its Dungeon Journal page, where it has one)
d.dungeonCard = true            -- the card open (false: folded to its title)
d.dungeonLevels = true          -- each entrance's level range under its icon
d.dungeonHints = 0              -- dungeon maps opened with the how-to-leave hint (it shows for the first few)
d.dungeonTab = "floors"         -- the dungeon map's side panel: floors, bosses, quests or loot
d.dungeonInside = true          -- the map opened inside a dungeon shows its map (off: as the game would)
d.entrances = {}                -- lines /openmap entrance recorded, to paste into build.py
d.bossPlaced = {}               -- bosses placed with /openmap bosses: [instance key][boss] = { floor, x, y }

local LOOK = {
	dungeon = { atlas = "dungeon", texture = "Interface\\Minimap\\ObjectIcons", size = 26 },
	raid = { atlas = "raid", texture = "Interface\\Minimap\\ObjectIcons", size = 26 },
}
-- the floor a wing opens on: its part of the dungeon's map (the game's names for the floors)
local WING_FLOORS = {
	["Dire Maul - East"] = "Warpwood Quarter", ["Dire Maul - West"] = "Capital Gardens", ["Dire Maul - North"] = "Gordok Commons",
	["Scarlet Monastery - Graveyard"] = "Graveyard", ["Scarlet Monastery - Library"] = "Library",
	["Scarlet Monastery - Armory"] = "Armory", ["Scarlet Monastery - Cathedral"] = "Cathedral",
}
local CARD_W = 270

local map, sc, chooser, card
local entrancePins = {}
local byMap                     -- a dungeon's map (each floor) -> { insts = { ... }, u, v (its entrance) }
local returnTo                  -- the world as it was when a dungeon's map was opened: { u, v, zoom, maps = { [mapID] = true } }
local away = {}                 -- maps off the stitched world a dock has opened (Zephras Isle): [mapID] = true
local shownMap, lastMap         -- the map the window shows, and the one before it
local hiddenAt, hiddenWith      -- when the map last closed, and the view that was up then: { inst, its entrance's u, v, the floor }

local function MapsOn() return mod.db.dungeonMaps ~= false end   -- (Options' Dungeon maps)
mod.DungeonMapsOn = MapsOn

-- PadView.lua's controller view on: Blizzard's map is never changed from here then (that's OpenMap's code
-- changing it, which taints the Gamepad UI), so a dungeon opens in OpenMap's own view of it (its floors'
-- pictures, ns.MapDungeonMaps), not on Blizzard's map; and the side panel stays out of the quest log
-- (opening or docking into it would be OpenMap's doing too)
local function PadView() return mod.PadViewOn and mod.PadViewOn() or false end

local function Places() return ns.MapPlaces or {} end

-- an entrance's place on Azeroth's map (normalized): from world yards on its continent, or a spot on
-- a zone's map (Data/Places.lua's `map =`)
function S.EntranceAt(g)
	if g.map then
		if not S.Rect(g.map) then return end
		return mod.ToWorld(g.map, g[2], g[3])
	end
	return S.FromYards(g[1], g[2], g[3])
end

local function Range(inst)
	if not inst[4] or not mod.LevelColor then return end
	local code, range = mod.LevelColor(inst[4], inst[5] or inst[4])
	return code .. range .. "|r"
end

local Index

-- a dungeon's map: the game's kind, or one an entrance opens (a dungeon whose map is a micro map)
local function IsDungeonMap(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	if not info then return false end
	return info.mapType == Enum.UIMapType.Dungeon or (Index and Index()[mapID] ~= nil) or false
end

-- a dungeon's map in this client (Blizzard's, found by its name), every floor of it
local function BaseMap(inst)
	local real = GetRealZoneText and inst[1] > 0 and Safe.Call(GetRealZoneText, inst[1])
	return (real and real ~= "" and S.InstanceMap(real)) or S.InstanceMap(inst[2])
end

local function Floors(id)
	local group = C_Map.GetMapGroupID and Safe.Call(C_Map.GetMapGroupID, id)
	if not group then return {} end
	local ok, floors = pcall(C_Map.GetMapGroupMembersInfo, group)
	return ok and type(floors) == "table" and floors or {}
end

local function MapsOf(id)
	local maps = { [id] = true }
	for _, f in ipairs(Floors(id)) do maps[f.mapID] = true end
	return maps
end

-- the map an instance opens on: its wing's floor where it has one
local function DungeonMap(inst)
	local id = BaseMap(inst)
	local floor = id and WING_FLOORS[inst[2]]
	if floor then
		for _, f in ipairs(Floors(id)) do
			if f.name == floor then return f.mapID end
		end
	end
	return id
end

-- which instances each dungeon map (and floor) is, and where it's entered
Index = function()
	if byMap then return byMap end
	byMap = {}
	local function add(inst, u, v)
		local id = BaseMap(inst)
		if not id then return end
		for m in pairs(MapsOf(id)) do
			local e = byMap[m] or { insts = {} }
			byMap[m] = e
			local known = false
			for _, other in ipairs(e.insts) do known = known or other == inst end
			if not known then e.insts[#e.insts + 1] = inst end
			if u and not e.u then e.u, e.v = u, v end
		end
	end
	for _, g in ipairs(Places().instances or {}) do
		local u, v = S.EntranceAt(g)
		for _, inst in ipairs(g[4]) do add(inst, u, v) end
	end
	for _, inst in ipairs(Places().unplaced or {}) do add(inst) end
	return byMap
end

--------------------------------------------------------------------------------
-- Opening a dungeon's map, and back out to the world
--------------------------------------------------------------------------------

local portalCard                -- the dungeon whose card shows over the world map (no map of it in this client): { inst }
local RefreshCard

--------------------------------------------------------------------------------
-- The dungeon's own map, drawn here: WoW Forever's client has no dungeon maps for Blizzard's map to
-- show, but it has their art (Data/DungeonMaps.lua, each floor's 12 tiles). Over the world map in the
-- same window, fitted, at once; the wheel zooms about the cursor (out past its fit too) and dragging
-- pans; floors with the arrows, the list or the side panel's Floors. Out again (the world as it was,
-- never moved): right-click, Escape, Back.
--------------------------------------------------------------------------------

local PIC_W, PIC_H = 1002, 668  -- the picture in its 4 x 3 tiles of 256 (1024 x 768)
local HEAD_H = 40               -- the view's bar across its top: back, the floor, close
local HINTS = 3                 -- dungeon maps opened with the hint
local ZOOM_OUT = 0.5            -- the furthest out the wheel goes: half its fit
local SIDE_W = 320              -- the view's side panel: what's in the dungeon (bosses, quests, loot); the quest log's width
local LOG_TOP, LOG_BAR = 29, 22 -- the quest log's strip along its top, and its scroll bar's at its right (Blizzard's)
local INNER_TABS = 36           -- the panel's bosses / quests / loot tabs, down from its box's top
local TAB_W, TAB_H = 40, 42     -- a tab by the quest log, out from it by along it (WoW Forever's tab art; a little smaller)
local NEEDROLL_URL = "https://www.curseforge.com/wow/addons/needroll"
local view
local bossUI = {}   -- (daves_map: on-map collapsible Bosses overlay, pin highlight & header layout)
local QuestList, EnsureQuests, FillSide, Dock, PlaceTabs, PlaceMarks, PlacePins, EndMarkup   -- (below)

local function Sound(name)
	if addonNs and addonNs.Sound then addonNs.Sound(name)
	elseif PlaySound and SOUNDKIT and SOUNDKIT[name] then PlaySound(SOUNDKIT[name]) end
end

-- one of the game's atlases on a texture, if the client has it: mirrored (left for right), at its own size
-- `mirrored` true or false: turned or not from the corners the texture was first given for that atlas,
-- kept (SetAtlas again with the atlas it has changes nothing, even after SetTexture(nil), so turning
-- what it showed turned a mirrored tab back at every click; and the atlas table's own corners are
-- the 1x file's, the wrong part of the double-size one a high-resolution screen gets)
-- `turn` (true: "right", false: "left"): the side its art's flat edge goes to (the art's own is its
-- left), for a tab on that edge: "left" as it is, "right" mirrored, "top" / "bottom" turned a
-- quarter round
-- the art's l, r, t, b corners on `tex`, turned so its left (flat) side is on `turn`'s side
local function Turned(tex, l, r, t, b, turn)
	-- (corners: upper left, lower left, upper right, lower right, each from the art's)
	if turn == "right" then tex:SetTexCoord(r, l, t, b)
	elseif turn == "bottom" then tex:SetTexCoord(r, t, l, t, r, b, l, b)   -- (a quarter round anticlockwise)
	elseif turn == "top" then tex:SetTexCoord(l, b, r, b, l, t, r, t)      -- (clockwise)
	else tex:SetTexCoord(l, r, t, b) end
end

local function Atlas(tex, name, turn, ownSize)
	if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) then return false end
	tex:SetAtlas(name, ownSize and true or false)
	if turn == true then turn = "right" elseif turn == false then turn = "left" end
	if turn then
		tex.omCoords = tex.omCoords or {}
		local c = tex.omCoords[name]
		if not c then
			c = { tex:GetTexCoord() }             -- (UL x, y, LL x, y, UR x, y, LR x, y: as first set, never turned)
			tex.omCoords[name] = c
		end
		Turned(tex, c[1], c[5], c[2], c[4], turn)
	end
	return true
end

-- Blizzard's map of it, else one drawn for WoW Forever's own dungeons (Data/DungeonDrawn.lua: by
-- mapID, or by name for one the game's tables have no mapID for yet, Places.lua's 0), else one built
-- from the game's minimap pictures (Data/DungeonMinimap.lua; first, with Options' "from the minimap").
-- Its second return says which: "blizzard", "drawn" or "minimap"
local function FloorsOf(inst)
	local drawn, mini = ns.MapDungeonDrawn, ns.MapDungeonMinimap
	local m = mini and inst[1] ~= 0 and mini[inst[1]]
	if m and mod.db.dungeonMinimap then return m, "minimap" end
	local b = ns.MapDungeonMaps and ns.MapDungeonMaps[inst[1]]
	if b then return b, "blizzard" end
	local d = drawn and (drawn[inst[1]] or inst[1] == 0 and drawn[inst[2]] or nil)
	if d then return d, "drawn" end
	if m then return m, "minimap" end
end
local BLANK = { { blank = true } }    -- (the floors of a dungeon the client has no map of: one blank page)

local function LayoutView(panOnly)
	-- (no floor shown yet: showing the view can size its port before ShowFloor sets the zoom, and lays it out)
	if not view or not view:IsShown() or not view.zoom then return end
	local w, h = view.port:GetWidth(), view.port:GetHeight()
	if not w or w <= 0 or not h or h <= 0 then return end
	local s = math.min(w / PIC_W, h / PIC_H) * view.zoom
	local pw, ph = PIC_W * s, PIC_H * s
	-- (kept over the view when it's bigger; centred when it's not)
	local mx, my = math.max(0, (pw - w) / 2), math.max(0, (ph - h) / 2)
	view.ox = math.max(-mx, math.min(mx, view.ox))
	view.oy = math.max(-my, math.min(my, view.oy))
	if panOnly == true then
		view.page:ClearAllPoints()
		view.page:SetPoint("CENTER", view.port, "CENTER", view.ox, view.oy)
		return
	end
	view.page:SetSize(pw, ph)
	view.page:ClearAllPoints()
	view.page:SetPoint("CENTER", view.port, "CENTER", view.ox, view.oy)
	for i, t in ipairs(view.tiles) do
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		local tw, th = math.min(256, PIC_W - col * 256), math.min(256, PIC_H - row * 256)
		t:SetSize(tw * s, th * s)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", view.page, "TOPLEFT", col * 256 * s, -row * 256 * s)
		t:SetTexCoord(0, tw / 256, 0, th / 256)
	end
	if PlaceMarks then PlaceMarks(pw, ph) end
	if PlacePins then PlacePins(pw, ph) end
	if bossUI.LayoutHeader then bossUI.LayoutHeader() end
	if bossUI.LayoutPanel then bossUI.LayoutPanel() end
end

local function ShowFloor(i, quiet)
	local floors = view.floors
	i = ((i - 1) % #floors) + 1
	if not quiet and i ~= view.floor then Sound("IG_MAINMENU_OPTION_CHECKBOX_ON") end
	view.floor = i
	if not bossUI.keepFocus then bossUI.focusBoss = nil end
	local f = floors[i]
	for k, t in ipairs(view.tiles) do
		if f.tiles then t:SetTexture(f.tiles[k], nil, nil, "TRILINEAR") end
		t:SetShown(f.tiles and true or false)
	end
	view.blank:SetShown(f.blank and true or false)
	view.blankText:SetShown(f.blank and true or false)
	view.credit:SetText(f.credit and L["Map by %s"]:format(f.credit) or "")
	local instName = S.InstanceName(view.inst)
	local floorLabel = view.FloorName(i)
	view.floorName:SetText(("|cffffd100%s|r%s"):format(floorLabel, #floors > 1 and ("  |cff998866%d / %d|r"):format(i, #floors) or ""))
	view.wing:SetText(f.wing and (f.wing .. "   ") or "")
	view.where:SetText((#floors > 1 or floorLabel ~= instName) and instName or "")
	view.prev:SetShown(#floors > 1)
	view.next:SetShown(#floors > 1)
	view.floorButton:EnableMouse(#floors > 1)
	if view.list then view.list:Hide() end
	if view.side and view.side.LightThumbs then view.side.LightThumbs() end
	view.zoom, view.ox, view.oy = 1, 0, 0
	if bossUI.UpdatePanel then bossUI.UpdatePanel() end
	LayoutView()
end

-- out: back to the world, at once
local function CloseView()
	if not view or not view:IsShown() or view.leaving then return end
	if view.list then view.list:Hide() end
	Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
	view:Hide()
	RefreshCard()
	-- (opened as the map opened inside the dungeon: under it is the game's map of the instance, not the
	-- stitched world, and closing the view left you on that: up to the world around its entrance)
	if map and map:IsShown() and not mod.IsStitched() and not PadView() and not (mod.PadWaits and mod.PadWaits())
		and not InCombatLockdown() then   -- (daves_map: SetMapID / NavigateToParentMap blocked in combat)
		local u, v, zoom = view.fromU, view.fromV, nil
		if not u and mod.InstanceEntranceView then u, v, zoom = mod.InstanceEntranceView() end
		-- (an entrance the tables don't place: where you last were outdoors, Nav.lua's)
		local last = mod.outsideInstanceView
		if not u and last then u, v = last[1], last[2] end
		local chain = u and S.ChainAt(u, v)
		local zone = chain and chain[#chain]
		if zone then
			mod.lastSwitchAt = GetTime()   -- (daves_map: avoid Layer.lua treating CloseView's jump as manual browse-away)
			S.OpenMap(zone)
			if mod.IsStitched() then mod.ShowNow(u, v, zoom or math.max(mod.FitZoom(zone) * 2, 6)) end
		elseif map.NavigateToParentMap then
			mod.lastSwitchAt = GetTime()   -- (daves_map: avoid Layer.lua treating CloseView's jump as manual browse-away)
			map:NavigateToParentMap()
		end
	end
end

local function Wheel(delta)
	-- (out past its fit too, the picture smaller in the middle: the wheel never leaves it)
	local z = math.max(ZOOM_OUT, math.min(4, view.zoom * (delta > 0 and 1.25 or 0.8)))
	if math.abs(z - view.zoom) < 1e-3 then return end
	-- about the cursor: the point under it stays there
	local x, y = GetCursorPosition()
	local es = view:GetEffectiveScale()
	local cx, cy = view.port:GetCenter()
	local dx, dy = x / es - cx - view.ox, y / es - cy - view.oy
	view.ox, view.oy = view.ox - dx * (z / view.zoom - 1), view.oy - dy * (z / view.zoom - 1)
	view.zoom = z
	LayoutView()
end

local function BuildView()
	view = CreateFrame("Frame", "DavesMapDungeonView", sc)
	view:SetAllPoints(sc)
	view:SetFrameLevel(math.min(sc:GetFrameLevel() + 8800, 9800))   -- (over the map and its icons; under OpenMap's menu and card)
	view:EnableMouse(true)
	view:EnableMouseWheel(true)
	view:SetClipsChildren(true)
	-- (the gamepad's cursor presses its tabs and buttons, and A on it isn't the map's under it: Gamepad.lua)
	mod.padRoots[#mod.padRoots + 1] = view
	if not PadView() then tinsert(UISpecialFrames, "DavesMapDungeonView") end   -- (the Gamepad UI reads that list)
	local bg = view:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0.04, 0.03, 0.96)
	-- the picture's own clipped area: under the bar, left of the side panel (zoomed in, it stays in it)
	view.port = CreateFrame("Frame", nil, view)
	view.port:SetPoint("TOPLEFT", 0, -HEAD_H)
	view.port:SetPoint("BOTTOMRIGHT", -SIDE_W, 0)
	view.port:SetClipsChildren(true)
	view.port:SetScript("OnSizeChanged", function() LayoutView() end)
	view.page = CreateFrame("Frame", nil, view.port)
	view.tiles = {}
	for i = 1, 12 do view.tiles[i] = view.page:CreateTexture(nil, "ARTWORK") end
	-- a dungeon the client has no map of: the map's own parchment, blank, and a word on it
	view.blank = view.page:CreateTexture(nil, "ARTWORK")
	view.blank:SetAllPoints()
	view.blank:SetTexture(ns.Media.tex .. "MapPaper", "REPEAT", "REPEAT")
	view.blank:SetTexCoord(0, 3, 0, 2)          -- (the paper's grain at about the zone maps' size)
	view.blank:Hide()
	view.blankText = Look:Font(view.page:CreateFontString(nil, "OVERLAY"), 16)
	view.blankText:SetPoint("CENTER")
	view.blankText:SetTextColor(0.32, 0.22, 0.12)
	view.blankText:SetText(ns.Client == "Forever" and L["WoW Forever has no map of this dungeon yet."]
		or L["There's no map of this dungeon to show here."])
	view.blankText:Hide()
	-- who drew a map we didn't get from the game (Data/DungeonDrawn.lua): small, at the picture's foot,
	-- in the middle (its corners have OpenMap's edge tabs, or its button)
	local over = CreateFrame("Frame", nil, view)
	over:SetAllPoints(view.port)
	over:SetFrameLevel(view:GetFrameLevel() + 20)   -- (over the picture, however far in)
	view.credit = Look:Font(over:CreateFontString(nil, "OVERLAY"), 11)
	view.credit:SetPoint("BOTTOM", view.port, "BOTTOM", 0, 8)
	view.credit:SetTextColor(0.8, 0.7, 0.5)
	view.credit:SetShadowColor(0, 0, 0, 1)
	view.credit:SetShadowOffset(1, -1)
	-- the bar across the top: location on the left, the floor in the center (between two arrows,
	-- with a full floor dropdown on click), and close on the right
	local bar = CreateFrame("Frame", nil, view)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(HEAD_H)
	bar:SetFrameLevel(view:GetFrameLevel() + 20)   -- (over the picture, however far in)
	bar:EnableMouse(true)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(0.09, 0.07, 0.05, 0.97)
	local rule = bar:CreateTexture(nil, "ARTWORK")
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	rule:SetHeight(1)
	rule:SetColorTexture(0.66, 0.49, 0.28, 0.9)
	local close = CreateFrame("Button", nil, bar, "UIPanelCloseButton")
	close:SetPoint("RIGHT", -4, 0)
	close:SetScript("OnClick", function() CloseView() end)
	-- (daves_map: compact Bosses toggle pill left of Close in the dungeon map header bar)
	local bossBtn = CreateFrame("Button", nil, bar)
	bossBtn:SetSize(82, 22)
	bossBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
	if addonNs.AddBrassPillSlices then
		bossBtn.frame = addonNs.AddBrassPillSlices(bossBtn, "BACKGROUND", 11)
		addonNs.AddBrassPillSlices(bossBtn, "HIGHLIGHT", 11, "ADD", 0.35)
	else
		local bbg = bossBtn:CreateTexture(nil, "BACKGROUND")
		bbg:SetAllPoints()
		bbg:SetColorTexture(0.14, 0.11, 0.08, 0.92)
		local bhl = bossBtn:CreateTexture(nil, "HIGHLIGHT")
		bhl:SetAllPoints()
		bhl:SetColorTexture(1, 0.85, 0.4, 0.22)
	end
	bossBtn.lbl = Look:Font(bossBtn:CreateFontString(nil, "OVERLAY"), 11)
	bossBtn.lbl:SetPoint("CENTER", 0, 0)
	bossBtn.lbl:SetWordWrap(false)
	bossBtn:SetScript("OnClick", function()
		mod.db.dungeonBossList = not (mod.db.dungeonBossList == true)
		Sound(mod.db.dungeonBossList and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		if bossUI.UpdatePanel then bossUI.UpdatePanel() end
	end)
	bossBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Dungeon Bosses & Rares", 1, 0.82, 0)
		GameTooltip:AddLine("Show or hide the boss and rare list overlay on this dungeon map.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	bossBtn:SetScript("OnLeave", GameTooltip_Hide)
	bossBtn:Hide()
	view.bossBtn = bossBtn
	view.where = Look:Font(bar:CreateFontString(nil, "OVERLAY"), 12)
	view.where:SetPoint("LEFT", 12, 0)
	view.where:SetJustifyH("LEFT")
	view.where:SetWordWrap(false)
	view.where:SetTextColor(0.8, 0.7, 0.5)
	view.floorButton = CreateFrame("Button", nil, bar)
	view.floorButton:SetSize(200, 30)
	view.floorButton:SetPoint("CENTER")
	view.floorButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	view.floorName = Look:Font(view.floorButton:CreateFontString(nil, "OVERLAY"), 15)
	view.floorName:SetPoint("LEFT", 6, 4)
	view.floorName:SetPoint("RIGHT", -6, 4)
	view.floorName:SetJustifyH("CENTER")
	view.floorName:SetWordWrap(false)
	view.wing = Look:Font(view.floorButton:CreateFontString(nil, "OVERLAY"), 10)
	view.wing:SetPoint("TOP", view.floorName, "BOTTOM", 0, -1)
	view.wing:SetTextColor(0.8, 0.7, 0.5)
	function view.FloorName(i)
		local f = view.floors and view.floors[i]
		return (f and f.name) or ((not f or #view.floors > 1) and L["Floor %d"]:format(i)) or S.InstanceName(view.inst)
	end
	-- every floor by name, to go straight to one
	view.floorButton:SetScript("OnClick", function(self)
		local list = view.list
		if not list then
			list = CreateFrame("Frame", nil, view)
			list:SetFrameLevel(bar:GetFrameLevel() + 10)
			list:EnableMouse(true)
			list.pad = { Look:Dropdown(list) }    -- (the game's own dropdowns' look)
			list.rows = {}
			view.list = list
		end
		if list:IsShown() then list:Hide() return end
		local w = 180
		for i = 1, #view.floors do
			local row = list.rows[i]
			if not row then
				row = CreateFrame("Button", nil, list)
				row:SetHeight(22)
				row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
				row.text = Look:Font(row:CreateFontString(nil, "OVERLAY"), 13)
				row.text:SetPoint("LEFT", 6, 0)
				row:SetScript("OnClick", function(r) list:Hide() ShowFloor(r.floor) end)
				list.rows[i] = row
			end
			row.floor = i
			row.text:SetText((i == view.floor and "|cffffd100" or "|cffffffff") .. view.FloorName(i) .. "|r")
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", list.pad[1], -list.pad[2] - (i - 1) * 22)
			row:SetPoint("TOPRIGHT", -list.pad[3], -list.pad[2] - (i - 1) * 22)
			row:Show()
			w = math.max(w, (row.text:GetStringWidth() or 100) + 24)
		end
		for i = #view.floors + 1, #list.rows do list.rows[i]:Hide() end
		list:SetSize(w + list.pad[1] + list.pad[3], #view.floors * 22 + list.pad[2] + list.pad[4])
		list:ClearAllPoints()
		list:SetPoint("TOP", self, "BOTTOM", 0, -4)
		list:Show()
	end)
	local function Arrow(dir)
		local b = CreateFrame("Button", nil, bar)
		b:SetSize(26, 26)
		b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Up")
		b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Down")
		b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		return b
	end
	view.prev = Arrow("Prev")
	view.prev:SetPoint("RIGHT", view.floorButton, "LEFT", -4, 0)
	view.prev:SetScript("OnClick", function() ShowFloor(view.floor - 1) end)
	view.next = Arrow("Next")
	view.next:SetPoint("LEFT", view.floorButton, "RIGHT", 4, 0)
	view.next:SetScript("OnClick", function() ShowFloor(view.floor + 1) end)
	-- how to leave, for the first few dungeon maps opened
	view.hint = CreateFrame("Frame", nil, view)
	view.hint:SetSize(1, 26)
	view.hint:SetPoint("BOTTOM", view.port, "BOTTOM", 0, 14)
	view.hint:SetFrameLevel(view:GetFrameLevel() + 20)
	local hintText = Look:Font(view.hint:CreateFontString(nil, "OVERLAY"), 12)
	hintText:SetPoint("CENTER")
	hintText:SetSpacing(3)
	view.hintText = hintText
	local hintBg = view.hint:CreateTexture(nil, "BACKGROUND")
	hintBg:SetPoint("TOPLEFT", hintText, -12, 6)
	hintBg:SetPoint("BOTTOMRIGHT", hintText, 12, -6)
	hintBg:SetColorTexture(0.06, 0.05, 0.04, 0.85)
	view.hint.fade = view.hint:CreateAnimationGroup()
	local fade = view.hint.fade:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetStartDelay(5)
	fade:SetDuration(1.2)
	view.hint.fade:SetScript("OnFinished", function() view.hint:Hide() end)
	view.hint:Hide()
	-- the side panel: the quest log's own look (its strip along the top, its paper in its frame): the
	-- dungeon's name and levels along the top, then a tab each for its bosses, its quests, its loot.
	-- With the quest log open it's in the log, a tab beside the log's own (Dock)
	local side = CreateFrame("Frame", nil, view)
	view.side = side
	side:SetWidth(SIDE_W)
	side:EnableMouse(true)
	side:EnableMouseWheel(true)
	local sideBg = side:CreateTexture(nil, "BACKGROUND", nil, -8)
	sideBg:SetAllPoints()
	sideBg:SetColorTexture(0.07, 0.055, 0.04, 1)
	side.title = Look:Font(side:CreateFontString(nil, "OVERLAY"), 15)
	side.title:SetPoint("TOPLEFT", 6, -7)
	side.title:SetJustifyH("LEFT")
	side.title:SetWordWrap(false)
	side.sub = Look:Font(side:CreateFontString(nil, "OVERLAY"), 12)
	side.sub:SetPoint("TOPRIGHT", -6, -9)
	side.sub:SetJustifyH("RIGHT")
	side.title:SetPoint("RIGHT", side.sub, "LEFT", -8, 0)
	-- (the box: where the log's list is, its scroll bar in the strip at its right)
	local box = CreateFrame("Frame", nil, side)
	box:SetPoint("TOPLEFT", 0, -LOG_TOP)
	box:SetPoint("BOTTOMRIGHT", -LOG_BAR, 0)
	local paper = box:CreateTexture(nil, "BACKGROUND")
	paper:SetAllPoints()
	if not Atlas(paper, "QuestLog-main-background") then paper:SetColorTexture(0.11, 0.09, 0.07, 1) end
	local frame = CreateFrame("Frame", nil, box)
	frame:SetPoint("TOPLEFT", -3, 7)
	frame:SetPoint("BOTTOMRIGHT", 3, -6)
	frame.levelOver = 30                            -- (over the list, as the log's is)
	frame:SetFrameLevel(box:GetFrameLevel() + frame.levelOver)
	local rim = frame:CreateTexture(nil, "BORDER")
	rim:SetAllPoints()
	Atlas(rim, "questlog-frame")
	local filigree = frame:CreateTexture(nil, "ARTWORK")
	if Atlas(filigree, "questlog-frame-filigree", nil, true) then filigree:SetPoint("TOP", 0, 1) end
	local shade = frame:CreateTexture(nil, "BACKGROUND")
	if Atlas(shade, "questlog-frame-gradient-bottom", nil, true) then
		shade:SetPoint("BOTTOMLEFT", 3, 4)
		shade:SetPoint("BOTTOMRIGHT", -3, 4)
	end
	side.tabs = {}
	local tx = 8
	for i, t in ipairs({ { "floors", L["Floors"] }, { "bosses", L["Bosses"] }, { "quests", L["Quests"] }, { "loot", L["Loot"] } }) do
		local ok, b = pcall(CreateFrame, "Button", nil, box, "MinimalTabTemplate")
		if ok and b and b.Text then
			b.Text:SetText(t[2])
			b:SetWidth(math.max(62, b.Text:GetStringWidth() + 24))   -- (four across the panel)
		else
			b = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
			b:SetSize(84, 22)
			b:SetText(t[2])
		end
		b.key = t[1]
		b:SetPoint("BOTTOMLEFT", box, "TOPLEFT", tx, -INNER_TABS)
		b:SetScript("OnClick", function()
			mod.db.dungeonTab = t[1]
			Sound("IG_CHARACTER_INFO_TAB")
			FillSide()
		end)
		side.tabs[i] = b
		tx = tx + b:GetWidth() + 2
	end
	local tabRule = box:CreateTexture(nil, "ARTWORK")
	tabRule:SetPoint("TOPLEFT", 6, -INNER_TABS)
	tabRule:SetPoint("TOPRIGHT", -6, -INNER_TABS)
	tabRule:SetHeight(1)
	tabRule:SetColorTexture(0.66, 0.49, 0.28, 0.5)
	side.scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	side.scroll:SetPoint("TOPLEFT", 6, -INNER_TABS - 6)
	side.scroll:SetPoint("BOTTOMRIGHT", -2, 10)
	side.child = CreateFrame("Frame", nil, side.scroll)
	side.child:SetWidth(SIDE_W - LOG_BAR - 12)
	side.child:SetHeight(1)
	side.scroll:SetScrollChild(side.child)
	side.pool = { row = {}, text = {}, button = {}, link = {}, thumb = {} }
	-- the Floors tab's pictures: the one shown edged in gold (ShowFloor lights them again)
	function side.LightThumbs()
		for _, w in ipairs(side.pool.thumb) do
			local on = w:IsShown() and w.item and w.item.floor == view.floor
			w:SetBackdropBorderColor(on and 1 or 0.66, on and 0.82 or 0.49, on and 0.3 or 0.28, on and 1 or 0.7)
			w.name:SetTextColor(on and 1 or 0.85, on and 0.82 or 0.8, on and 0.3 or 0.7)
		end
	end
	-- (its width follows the log's, docked: laid out again for it)
	side:SetScript("OnSizeChanged", function(self, w)
		if w and math.abs((self.filledW or 0) - w) > 1 then C_Timer.After(0, FillSide) end
	end)
	-- (daves_map: OpenMap's floating quest/dungeon icon sideTabs are omitted because Dave's Map
	-- provides its own right-hand Base / Tracker & Log / Zone / Dungeon panel plus the on-map Bosses overlay.)
	if bossUI.BuildPanel then bossUI.BuildPanel() end
	-- the mouse: the wheel zooms, a drag pans, a right-click goes back to the world
	view:SetScript("OnMouseWheel", function(_, delta) Wheel(delta) end)
	-- (drawing on it for a report, the markup: a left-drag draws, a right-drag pans, a right-click stays)
	-- (placing bosses: a click places, a right-click skips, shift-click takes one back; either drag pans)
	view:SetScript("OnMouseDown", function(self, button)
		if self.markup and button == "LeftButton" then self.MarkStart() return end
		if self.placer or button == (self.markup and "RightButton" or "LeftButton") then
			local x, y = GetCursorPosition()
			self.drag = { x, y, self.ox, self.oy, button = button }
		end
	end)
	view:SetScript("OnMouseUp", function(self, button)
		local d = self.drag
		self.drag = nil
		if self.placer then
			local x, y = GetCursorPosition()
			if d and math.abs(x - d[1]) + math.abs(y - d[2]) > 6 then return end   -- (a drag: it panned)
			if button == "RightButton" then mod.BossPlacerNext()
			elseif IsShiftKeyDown() then mod.BossPlacerUndo()
			else mod.BossPlacerClick() end
		elseif self.markup then
			if button == "LeftButton" then self.MarkFinish() end
		elseif button == "RightButton" then
			CloseView()
		end
	end)
	view:SetScript("OnUpdate", function(self)
		if self.markup then self.MarkMove() end
		local d = self.drag
		if not d then return end
		if not IsMouseButtonDown(d.button) then self.drag = nil return end
		local x, y = GetCursorPosition()
		local es = self:GetEffectiveScale()
		self.ox, self.oy = d[3] + (x - d[1]) / es, d[4] + (y - d[2]) / es
		LayoutView(true)
	end)
	view:SetScript("OnSizeChanged", function() LayoutView() end)
	view:SetScript("OnHide", function()
		view.leaving = nil
		bossUI.hoverBoss, bossUI.focusBoss = nil, nil
		if view.bossPanel then view.bossPanel:Hide() end
		EndMarkup(false)                            -- (a report being drawn: no report)
		if view.placer then mod:ToggleBossPlacer() end   -- (placing bosses: done)
		if view.list then view.list:Hide() end
		Dock()                                      -- (out of the quest log, if it was in it)
		if card and card:IsShown() then C_Timer.After(0, RefreshCard) end
		if addonNs.OnDungeonViewChanged then addonNs.OnDungeonViewChanged(false, nil) end
	end)
	-- Escape: back to the world, as a right-click. Escape's own list (UISpecialFrames) closes the game's
	-- panels in the same go, the map window among them: the whole map shut, and inside a dungeon it then
	-- opened on the dungeon again, never the world. So the key is taken here, unless another window of
	-- Escape's is up (it closes that). Not in combat, where a key can't be kept from the game: the map
	-- closes then, as it did
	-- (keys are passed on except that Escape: passing them on can't be set in combat, so the keyboard is
	-- taken only while it's known to pass them on; a view holding it without would swallow every key,
	-- abilities too)
	local passing = false
	local function TakeKeys()
		if InCombatLockdown() then
			if not passing then view:EnableKeyboard(false) end
			return
		end
		view:SetPropagateKeyboardInput(true)
		passing = true
		view:EnableKeyboard(true)
	end
	if not PadView() then
		TakeKeys()
		view:HookScript("OnShow", TakeKeys)
		ns.RegisterEvent(view, "PLAYER_REGEN_ENABLED", function() if view:IsShown() then TakeKeys() end end)
		view:SetScript("OnKeyDown", function(self, key)
			if key ~= "ESCAPE" or InCombatLockdown() or self.leaving then return end
			for _, name in ipairs(UISpecialFrames) do
				local f = _G[name]
				if f and f ~= self and type(f) == "table" and f.IsShown and f:IsShown() then return end
			end
			self:SetPropagateKeyboardInput(false)
			passing = false
			CloseView()
			C_Timer.After(0, TakeKeys)
		end)
	end
	view:Hide()
end

--------------------------------------------------------------------------------
-- Markup: drawing on a dungeon's map for a report (Report.lua). Red pen lines on the floor's
-- picture, in its own measure (0..1 across and down, so they keep their place as it zooms and pans),
-- each on the floor it was drawn on. A left-drag draws, a right-drag pans; its bar: Undo, Next, Cancel.
-- The quill on a dungeon's map (a player's request: what was drawn went on the world map) is the same
-- pen, in the quill's ink, kept: the sketch's dungeons[instance] (shown with Your drawings); its bar:
-- Undo, Clear, Done.
--------------------------------------------------------------------------------

local MARK_STEP = 3             -- px the cursor moves before the pen adds a point
local MARK_MAX = 300            -- points in one line
local MARK_INK = { 0.92, 0.18, 0.14 }

-- what's kept per dungeon was by name for WoW Forever's own that the game's tables had no mapID for (0):
-- they have their instance's now (#149), so a name's entry goes to its mapID, once (`all`: the sketch's
-- dungeons, or the bosses placed)
local function ByMapID(all, inst)
	if all and inst and inst[1] ~= 0 and all[inst[2]] ~= nil and all[inst[1]] == nil then
		all[inst[1]], all[inst[2]] = all[inst[2]], nil
	end
end

-- the quill's drawings on this dungeon's map (the sketch's dungeons, by the instance's map ID)
local function Kept(make)
	local sk = mod.db.sketch
	local inst = view.inst
	local key = inst and (inst[1] ~= 0 and inst[1] or inst[2])   -- (0: WoW Forever's own, by name)
	if not (sk and key) then return end
	ByMapID(sk.dungeons, inst)
	if make then sk.dungeons = sk.dungeons or {} end
	local all = sk.dungeons
	if make and not all[key] then all[key] = {} end
	return all and all[key]
end

PlaceMarks = function(pw, ph)
	view.markLines = view.markLines or {}
	local lines = view.markLines
	local list = view.markup and view.markup.strokes or view.heldMarks
		or (mod.db.sketchShown ~= false and Kept()) or {}
	local n = 0
	for _, st in ipairs(list) do
		if st.floor == view.floor then
			local p = st.pts
			local ink = st.ink or MARK_INK
			for k = 1, #p - 3, 2 do
				n = n + 1
				local line = lines[n]
				if not line then
					line = view.page:CreateLine(nil, "OVERLAY")
					line:SetThickness(3)
					lines[n] = line
				end
				line:SetColorTexture(ink[1], ink[2], ink[3], 1)
				line:SetStartPoint("TOPLEFT", view.page, p[k] * pw, -p[k + 1] * ph)
				line:SetEndPoint("TOPLEFT", view.page, p[k + 2] * pw, -p[k + 3] * ph)
				line:Show()
			end
		end
	end
	for i = n + 1, #lines do lines[i]:Hide() end
end

local function RedrawMarks()
	local pw, ph = view.page:GetSize()
	if pw and pw > 0 then PlaceMarks(pw, ph) end
end

-- the cursor on the picture: 0..1 across and down (nil off it; `clamp`: kept to its edge)
local function PageAt(clamp)
	local x, y = GetCursorPosition()
	local es = view.page:GetEffectiveScale()
	local l, t, w, h = view.page:GetLeft(), view.page:GetTop(), view.page:GetWidth(), view.page:GetHeight()
	if not (l and t and w and h and w > 0 and h > 0) then return end
	local px, py = (x / es - l) / w, (t - y / es) / h
	if clamp then return math.max(0, math.min(1, px)), math.max(0, math.min(1, py)) end
	if px < 0 or px > 1 or py < 0 or py > 1 then return end
	return px, py
end

local function Round4(x) return math.floor(x * 1e4 + 0.5) / 1e4 end

local function MarkStart()
	local m = view.markup
	local px, py = PageAt()
	if not m or not px then return end
	local st = { floor = view.floor, pts = { Round4(px), Round4(py) }, ink = m.ink }
	m.strokes[#m.strokes + 1] = st
	local x, y = GetCursorPosition()
	m.live = { st = st, x = x, y = y }
end

local function MarkFinish()
	local m = view.markup
	local live = m and m.live
	if not live then return end
	m.live = nil
	if #live.st.pts < 4 then tremove(m.strokes) end   -- (a click: nothing drawn)
	RedrawMarks()
end

local function MarkMove()
	local live = view.markup and view.markup.live
	if not live then return end
	if not IsMouseButtonDown("LeftButton") then MarkFinish() return end
	local x, y = GetCursorPosition()
	if math.abs(x - live.x) + math.abs(y - live.y) < MARK_STEP or #live.st.pts >= MARK_MAX * 2 then return end
	live.x, live.y = x, y
	local px, py = PageAt(true)
	if not px then return end
	local p = live.st.pts
	p[#p + 1], p[#p + 2] = Round4(px), Round4(py)
	RedrawMarks()
end

-- the markup's bar, over the picture's top: what to do, Undo, Next, Cancel
local function MarkBar()
	if view.markBar then return view.markBar end
	local bar = CreateFrame("Frame", nil, view)
	bar:SetPoint("TOP", view.port, "TOP", 0, -6)
	bar:SetSize(640, 38)
	bar:SetFrameLevel(view:GetFrameLevel() + 30)
	bar:EnableMouse(true)
	Look:Panel(bar, { inset = 0, alpha = 0.92 })
	local text = Look:Font(bar:CreateFontString(nil, "OVERLAY"), 12)
	text:SetPoint("LEFT", 10, 0)
	text:SetText(L["|cffffd100Step 1 of 2:|r draw where it's wrong (right-drag pans)"])
	local function Btn(label, x, fn, w)
		local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
		b:SetSize(w or 70, 24)
		b:SetPoint("RIGHT", x, 0)
		b:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	local next = Btn(L["Next"] .. "  >", -82, function() EndMarkup(true) end, 96)
	-- (the way on: a gold glow round it, breathing)
	local glow = next:CreateTexture(nil, "BACKGROUND", nil, -1)
	glow:SetPoint("TOPLEFT", -4, 4)
	glow:SetPoint("BOTTOMRIGHT", 4, -4)
	glow:SetColorTexture(1, 0.8, 0.25, 0.55)
	local pulse = glow:CreateAnimationGroup()
	local breathe = pulse:CreateAnimation("Alpha")
	breathe:SetFromAlpha(1)
	breathe:SetToAlpha(0.2)
	breathe:SetDuration(0.8)
	breathe:SetSmoothing("IN_OUT")
	pulse:SetLooping("BOUNCE")
	pulse:Play()
	Btn(CANCEL or L["Cancel"], -8, function() EndMarkup(false) end)
	Btn(L["Undo"], -184, function()
		local m = view.markup
		if m then tremove(m.strokes) RedrawMarks() end
	end)
	mod.padRoots[#mod.padRoots + 1] = bar      -- (the gamepad's cursor presses its buttons: Gamepad.lua)
	view.markBar = bar
	return bar
end

-- the quill's bar on a dungeon's map: what to do, Undo, Clear, Done
local function DrawBar()
	if view.drawBar then return view.drawBar end
	local bar = CreateFrame("Frame", nil, view)
	bar:SetPoint("TOP", view.port, "TOP", 0, -6)
	bar:SetSize(560, 38)
	bar:SetFrameLevel(view:GetFrameLevel() + 30)
	bar:EnableMouse(true)
	Look:Panel(bar, { inset = 0, alpha = 0.92 })
	local text = Look:Font(bar:CreateFontString(nil, "OVERLAY"), 12)
	text:SetPoint("LEFT", 10, 0)
	text:SetText(L["Draw on this dungeon's map (right-drag pans)"])
	local function Btn(label, x, fn)
		local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
		b:SetSize(70, 24)
		b:SetPoint("RIGHT", x, 0)
		b:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	Btn(L["Done"], -8, function() EndMarkup(false) end)
	Btn(L["Clear"], -82, function()
		local m = view.markup
		if not m then return end
		for i = #m.strokes, 1, -1 do if m.strokes[i].floor == view.floor then tremove(m.strokes, i) end end
		RedrawMarks()
	end)
	Btn(L["Undo"], -156, function()
		local m = view.markup
		if not m then return end
		for i = #m.strokes, 1, -1 do if m.strokes[i].floor == view.floor then tremove(m.strokes, i) break end end
		RedrawMarks()
	end)
	mod.padRoots[#mod.padRoots + 1] = bar      -- (the gamepad's cursor presses its buttons: Gamepad.lua)
	view.drawBar = bar
	return bar
end

EndMarkup = function(finished)
	local m = view and view.markup
	if not m then return end
	view.markup = nil
	if view.markBar then view.markBar:Hide() end
	if view.drawBar then view.drawBar:Hide() end
	if bossUI.UpdatePanel then bossUI.UpdatePanel() end
	if m.keep then                              -- (the quill's: already kept, as drawn)
		RedrawMarks()
		if mod.OnSketchChanged then mod.OnSketchChanged() end
		if mod.RefreshPanel then mod:RefreshPanel() end
		return
	end
	view.heldMarks = finished and m.strokes or nil   -- (Next: still shown while the note's written; else gone)
	RedrawMarks()
	local place = finished and { inst = view.inst[1], u = view.fromU, v = view.fromV } or nil
	if m.onEnd then m.onEnd(finished and m.strokes or nil, place, finished and true or false) end
end

-- the lines a finished markup left on show: gone (the report's done)
function mod.DungeonMarkupRelease()
	if view and view.heldMarks then
		view.heldMarks = nil
		RedrawMarks()
	end
end

-- the quill on the dungeon's map shown (Sketch.lua's ToggleSketch, while one is): on or off
function mod.DungeonDraw(on)
	if not view then return end
	if not on then
		if view.markup and view.markup.keep then EndMarkup(false) end
		return
	end
	if not view:IsShown() then return end
	EndMarkup(false)
	view.MarkStart, view.MarkMove, view.MarkFinish = MarkStart, MarkMove, MarkFinish
	view.markup = { strokes = Kept(true), keep = true, ink = mod.SketchInk and mod.SketchInk() }
	view.hint:Hide()
	if view.bossPanel then view.bossPanel:Hide() end
	DrawBar():Show()
	RedrawMarks()
	if mod.OnSketchChanged then mod.OnSketchChanged() end
end
function mod.DungeonDrawing() return view and view.markup and view.markup.keep and true or false end

-- Report.lua's: on (with onEnd(strokes, place, finished), as the markup ends), or off (no report)
function mod.DungeonMarkup(on, onEnd)
	if not view then return end
	if not on then EndMarkup(false) return end
	if not view:IsShown() then return end
	EndMarkup(false)
	view.MarkStart, view.MarkMove, view.MarkFinish = MarkStart, MarkMove, MarkFinish
	view.markLines = view.markLines or {}
	view.markup = { strokes = {}, onEnd = onEnd }
	view.hint:Hide()
	if view.bossPanel then view.bossPanel:Hide() end
	MarkBar():Show()
	RedrawMarks()
end

-- the tabs beside the quest log: on its right, as the log's own are, or (full screen, the log at the
-- screen's edge) on its left, the art mirrored
-- one tab's art (b.bg, b.selected, b.hover; b.artH: its art's height, else the atlas's own), turned
-- or not; `on` (true / false) shows its selected edge, nil leaves that be (Panel.lua's tabs light
-- it themselves). An icon of the game's (b.on / b.off atlases) is set too; any b.icon is placed
local TOWARD = { left = { -1, 0 }, right = { 1, 0 }, top = { 0, 1 }, bottom = { 0, -1 } }   -- (each edge's way)
-- WoW Forever's own tabs' art (the "c60" set, its bronze edge) and the mask of its face. Its art is
-- 55 x 60, the tab showing 52 out from its flat side by 54 along; the face (the mask's) is 43 by 44
-- of it, 2 in from the flat side
local TAB_ART = { "common-sidetab-c60", "common-sidetab-selected-c60", "common-sidetab-hover-c60" }
local TAB_MASK = "common-sidetab-mask-c60"
local ART_OUT, ART_ALONG, SHOW_OUT, SHOW_ALONG = 55, 60, 52, 54
local FACE_OUT, FACE_ALONG, FACE_IN = 43, 44, 2
local function FaceTab(b, turn, on)
	if turn == true then turn = "right" elseif turn == false then turn = "left" end
	local w, h = b:GetWidth(), b:GetHeight()
	local upright = turn == "left" or turn == "right"
	local out, along = upright and w or h, upright and h or w
	-- the art at the tab's size, its flat side flush with the tab's (its clear strip is on its open side)
	local ao, aa = out * ART_OUT / SHOW_OUT, along * ART_ALONG / SHOW_ALONG
	local aw, ah = upright and ao or aa, upright and aa or ao
	local edge = TOWARD[turn]
	local shift = (ao - out) / 2                -- (away from the edge)
	local cx, cy = -edge[1] * shift, -edge[2] * shift
	local art = { b.bg, b.selected, b.hover }
	for i, tex in ipairs(art) do
		local ok = Atlas(tex, TAB_ART[i], turn, true) or Atlas(tex, (TAB_ART[i]:gsub("%-c60$", "")), turn, true)
		if ok then
			tex:SetSize(aw, ah)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", cx, cy)
		elseif i == 1 then
			b.bg:SetAllPoints()
			b.bg:SetColorTexture(0.1, 0.08, 0.06, 0.95)
		end
	end
	if on ~= nil then b.selected:SetShown(on) end
	if not b.icon then return end
	if b.fill and b.icon.square ~= false then
		-- (OpenMap's own: the picture filling the face, cut to its shape; the face's middle is nearer the flat side)
		if not b.mask then
			b.mask = b:CreateMaskTexture()
			if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(TAB_MASK) then
				b.mask:SetAtlas(TAB_MASK)
				b.icon:AddMaskTexture(b.mask)
			end
		end
		b.mask:SetSize(aw, ah)
		b.mask:ClearAllPoints()
		b.mask:SetPoint("CENTER", cx, cy)
		pcall(Turned, b.mask, 0, 1, 0, 1, turn)   -- (the mask is its whole file)
		local side = math.max(FACE_OUT * ao / ART_OUT, FACE_ALONG * aa / ART_ALONG)
		local toward = (ART_OUT / 2 - FACE_IN - FACE_OUT / 2) * ao / ART_OUT   -- (the face's middle from the art's)
		b.icon:SetSize(side, side)
		b.icon:ClearAllPoints()
		b.icon:SetPoint("CENTER", cx + edge[1] * toward, cy + edge[2] * toward)
		return
	end
	if b.on and Atlas(b.icon, (on or not b.off) and b.on or b.off, false, true) then
		b.icon:SetSize(b.iconSize or 24, b.iconSize or 24)
		if not b.off then                       -- (one icon for both: dimmed when it's not the one shown)
			b.icon:SetDesaturated(not on)
			b.icon:SetAlpha(on and 1 or 0.75)
		end
	end
	-- (an icon of its own size: in the face's middle)
	local toward = (ART_OUT / 2 - FACE_IN - FACE_OUT / 2) * ao / ART_OUT
	b.icon:ClearAllPoints()
	b.icon:SetPoint("CENTER", cx + edge[1] * toward, cy + edge[2] * toward)
end
mod.FaceSideTab = FaceTab

local function FaceTabs(mirrored, open)
	if not (view and view.sideTabs and view.sideTabs.list) then return end
	for _, b in ipairs(view.sideTabs.list) do
		FaceTab(b, mirrored, open and b.key == view.dockTab or false)   -- (the log put away: neither is the one shown)
	end
end

-- a frame of ours to a level, and everything in it above it as it was laid out (its frame over its list)
local function Lift(f, level)
	f:SetFrameLevel(level)
	for _, child in ipairs({ f:GetChildren() }) do Lift(child, level + (child.levelOver or 1)) end
end

-- the side panel's place: in the quest log while it's open (its own tab beside the log's, picked as
-- the dungeon's map opens), else put away with it. Never Blizzard's log's own state: only frames of ours
local DockNow
local railKnew                  -- whether OpenMap's tabs last made room for these
Dock = function()
	DockNow()
	-- (OpenMap's own tabs keep room for these over them while they show, Panel.lua: told when that changes)
	local shown = mod.DungeonTabsShown()
	if shown ~= railKnew and mod.RefreshRail then
		railKnew = shown
		mod.RefreshRail()
	end
end
function mod.DungeonTabsShown() return view and view.sideTabs and view.sideTabs:IsShown() or false end

DockNow = function()
	if not view then return end
	local side, tabs = view.side, view.sideTabs
	if view.leaving then                        -- (going: out of the log at once, not after the view's shrunk)
		if tabs then tabs:Hide() end
		if side:GetParent() ~= view then side:Hide() end
		return
	end
	local log = map.QuestLog
	local suppressed = addonNs.IsQuestMapSuppressed and addonNs.IsQuestMapSuppressed()
	local open = not PadView() and not suppressed and view:IsShown() and log and log:IsVisible() and true or false
	side:ClearAllPoints()
	view.port:SetPoint("BOTTOMRIGHT", 0, 0)
	if open then
		local anchor = log.ContentsAnchor or log
		side:SetParent(log)
		side:SetPoint("TOPLEFT", anchor, "TOPLEFT")
		side:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT")
		Lift(side, math.min(log:GetFrameLevel() + 600, 9700))   -- (over all of the log: its frames go to 100, its buttons a little past)
		side:SetShown(view.dockTab ~= "quests")
	else
		-- (the log put away: the panel with it, the dungeon's map the whole view)
		side:SetParent(view)
		side:SetPoint("TOPRIGHT", 0, -HEAD_H)
		side:SetPoint("BOTTOMRIGHT")
		side:SetWidth(SIDE_W)
		if (PadView() or view.dockTab == "dungeon") and view:IsShown() then   -- (daves_map: dock inside view when log is hidden)
			-- (the controller view: never in the quest log, so beside the picture, in the view itself)
			view.port:SetPoint("BOTTOMRIGHT", -SIDE_W, 0)
			Lift(side, view:GetFrameLevel() + 15)
			side:Show()
			LayoutView()
		else
			side:Hide()
			LayoutView()
		end
	end
	if tabs then tabs:Hide() end   -- (daves_map: floating quest/dungeon icon tabs are permanently disabled)
end

-- (daves_map: OpenMap's floating edge tabs are removed; keep no-op entrypoints for any callers)
PlaceTabs = function()
	if view and view.sideTabs then view.sideTabs:Hide() end
end
function mod.PlaceDungeonTabs()
	if view and view.sideTabs then view.sideTabs:Hide() end
end

-- a dungeon's map in the view: its wing's first floor, else its first; grown out of `pin` (the entrance)
local function OpenView(inst, pin)
	local t0 = debugprofilestop and debugprofilestop()
	-- (none in the client, WoW Forever's own dungeons: a blank page, its side panel as any other's)
	local floors, source = FloorsOf(inst)
	if not floors or #floors == 0 then floors = BLANK end
	if not view then BuildView() end
	portalCard = nil
	view.inst, view.floors, view.source = inst, floors, source
	local first = 1
	for i, f in ipairs(floors) do
		if f.wing == inst[2] or (f.name and f.name == WING_FLOORS[inst[2]]) then first = i break end
	end
	-- inside it: the floor of the sub-zone you're in, where a drawn floor names one (Dalaran's Underbelly)
	if IsInInstance and IsInInstance() and inst[1] ~= 0 and Safe.Value(select(8, GetInstanceInfo())) == inst[1] then
		local sub = Safe.Call(GetSubZoneText)
		for i, f in ipairs(floors) do
			for _, s in ipairs(f.subzones or {}) do
				if sub and s == sub then first = i break end
			end
		end
	end
	EndMarkup(false)
	view.heldMarks = nil
	bossUI.hoverBoss, bossUI.focusBoss = nil, nil
	view.fromU, view.fromV = pin and pin.u, pin and pin.v   -- (the entrance: where a report from here says it is)
	view.leaving = nil
	view:SetAlpha(1)
	view:Show()
	-- (beside the quest log, always your quests first: the dungeon's panel only when you pick its tab, for this
	-- map. It covered the quest log every time, the tab once picked being kept: players' reports)
	view.dockTab = "quests"
	Dock()
	view.floor = nil
	ShowFloor(first, true)
	Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
	if (mod.db.dungeonHints or 0) < HINTS then
		mod.db.dungeonHints = (mod.db.dungeonHints or 0) + 1
		local hint = L["|cffffd100Right-click|r or |cffffd100Esc|r to go back to the world map"]
		view.hintText:SetText(hint)
		view.hint:SetHeight((view.hintText:GetStringHeight() or 14) + 12)
		view.hint:SetAlpha(1)
		view.hint:Show()
		view.hint.fade:Stop()
		view.hint.fade:Play()
	else
		view.hint:Hide()
	end
	RefreshCard()                                 -- (fills the side panel too: once, not twice)
	if addonNs.OnDungeonViewChanged then addonNs.OnDungeonViewChanged(true, S.InstanceName(inst)) end
	if t0 then mod.dungeonOpenMs = debugprofilestop() - t0 end   -- (/openmap status)
	return true
end
function mod.DungeonViewShown() return view and view:IsShown() or false end

local function NeedRoll() return SlashCmdList and SlashCmdList.NEEDROLL end

-- (in combat with the gamepad's UI the game's own map isn't changed by OpenMap: WorldMap.lua's
-- mod.PadCombat; once a while, said why)
local padSaid = 0
local function PadWaits()
	if not (mod.PadCombat and mod.PadCombat()) then return false end
	if GetTime() - padSaid > 10 then
		padSaid = GetTime()
		ns:Print(L["With a gamepad, that map opens once you're out of combat."])
	end
	return true
end
mod.PadWaits = PadWaits      -- (Quests.lua's quest icons wait too: opening a quest's details sets the pad's buttons)

-- Dungeon Journal (by Exehn, for WoW Forever: /dj): its pages are by its own names for the
-- dungeons ("Scarlet Monastery: Graveyard", "Hall of Thanes"), matched to ours loosely
local function Journal()
	local dj = _G.ForeverDungeonJournal_NS
	if type(dj) == "table" and type(dj.DB) == "table" and type(dj.OpenBossPage) == "function" then return dj end
end
local function Plain(name)
	name = (name or ""):lower():gsub("^the ", ""):gsub("%s*[-:]%s*", ": ")
	return name
end
local function JournalName(inst)
	local dj = Journal()
	if not dj then return end
	local want = Plain(inst[2])
	for key, entry in pairs(dj.DB) do
		if type(entry) == "table" and not entry.previewOnly and Plain(key) == want then return key end
	end
end
-- its window at the dungeon's page (bosses, or `quests`); false where it has none
local function OpenJournal(inst, quests)
	local dj, key = Journal(), JournalName(inst)
	if not key then return false end
	-- (shown first: showing it puts up the page it was last on)
	local frame, toggle = _G.ForeverDungeonJournalFrame, _G.ForeverDungeonJournal_Toggle
	if not (frame and frame:IsShown()) and type(toggle) == "function" then pcall(toggle) end
	local open = quests and type(dj.OpenQuestPage) == "function" and dj.OpenQuestPage or dj.OpenBossPage
	return (pcall(open, key))
end

local function Open(inst, pin)
	if chooser then chooser:Hide() end
	if mod.db.entranceClick == "journal" and OpenJournal(inst) then return end
	local id = MapsOn() and not PadView() and DungeonMap(inst)
	if id then
		if PadWaits() or InCombatLockdown() then return end   -- (daves_map: SetMapID blocked in combat)
		local u, v, zoom = mod.ViewNow()
		returnTo = u and { u, v, zoom, maps = MapsOf(id) } or nil
		S.OpenMap(id)
		return
	end
	if MapsOn() and OpenView(inst, pin) then return end
	-- no map of it at all (WoW Forever's own dungeons), or dungeon maps turned off: its card over
	-- the world map, and down into its entrance (Close.lua), or just closer in
	portalCard = { inst }
	RefreshCard()
	local cave, u0, v0, u1, v1
	if S.CaveAt and pin.cont then cave, u0, v0, u1, v1 = S.CaveAt(pin.cont, pin.x, pin.y) end
	if cave and S.GlideToRect then S.GlideToRect(u0, v0, u1, v1, 1.1)
	elseif S.GlideToWorld then
		local _, _, zoom = mod.ViewNow()
		S.GlideToWorld(pin.u, pin.v, math.max(zoom or 1, 12))
	end
end

-- the stitched map is put up again (WorldMap.lua's view reset): out of a dungeon's map, the world as
-- it was when that map was opened, else around the dungeon's entrance
function mod.ReturnView(newMapID)
	local from = (shownMap == newMapID) and lastMap or shownMap
	local r = returnTo
	returnTo = nil
	if not from or not (IsDungeonMap(from) or away[from]) then return end
	-- (only going up out of it: a map it's part of; not the quest log or the dropdown putting up another)
	local up, steps = C_Map.GetMapInfo(from), 0
	local above = false
	while up and up.parentMapID and up.parentMapID > 0 and steps < 8 do
		if up.parentMapID == newMapID then above = true break end
		up, steps = C_Map.GetMapInfo(up.parentMapID), steps + 1
	end
	if not above then return end
	if r and r.maps[from] then return r[1], r[2], r[3] end
	local e = Index()[from]
	if e and e.u then return e.u, e.v, math.max(mod.FitZoom(newMapID) * 2, 6) end
end

-- a map off the stitched world (Zephras Isle, from the Dalaran skydock: Stitch.lua's docks), opened as
-- a dungeon's is: the game's own map of it in the window, the world as it was on the way back out
function mod.OpenAwayMap(mapID)
	if not C_Map.GetMapInfo(mapID) then return false end
	if PadView() or InCombatLockdown() then return false end   -- (daves_map: SetMapID blocked in combat)
	if PadWaits() then return true end
	local u, v, zoom = mod.ViewNow()
	away[mapID] = true
	returnTo = u and { u, v, zoom, maps = MapsOf(mapID) } or nil
	S.OpenMap(mapID)
	return true
end

local function Back()
	if view and view:IsShown() then CloseView() return end
	if map and not mod.IsStitched() and not PadWaits() and not PadView() and not InCombatLockdown() then map:NavigateToParentMap() end
end

-- for PadView.lua: Blizzard's map known here (its SetupDungeons, the usual map's, isn't run then: nothing of
-- it hooked), an entrance pressed, the view closed
function mod.PadDungeonHost(worldMap)
	if not map then map, sc = worldMap, worldMap.ScrollContainer end
end
function mod.CloseDungeonView() CloseView() end

-- Options' and the menu's Dungeon maps: off, a dungeon's map that's up goes back to the world map
function mod.SetDungeonMaps(on)
	mod.db.dungeonMaps = on
	if not on then
		if view and view:IsShown() then CloseView() end
		if map and map:IsShown() and not mod.IsStitched() and IsDungeonMap(map:GetMapID()) then Back() end
	end
	mod:Refresh()
	if ns.NotifyOptions then ns.NotifyOptions() end
end

--------------------------------------------------------------------------------
-- The entrances
--------------------------------------------------------------------------------

-- a dungeon's first floors' files asked for as the cursor comes onto its entrance, so its map shows
-- at once when it's clicked (not drawn: textures set aside, the client loads their files)
local preload
local function Preload(pin)
	if not MapsOn() then return end
	if not preload then
		preload = CreateFrame("Frame", nil, UIParent)
		preload:Hide()
		preload.tex = {}
	end
	local n = 0
	for _, inst in ipairs(pin.instances) do
		local floors = FloorsOf(inst)
		local f = floors and floors[1]
		for _, file in ipairs(f and f.tiles or {}) do
			n = n + 1
			preload.tex[n] = preload.tex[n] or preload:CreateTexture()
			preload.tex[n]:SetTexture(file)
		end
	end
end

local function Enter(pin)
	Preload(pin)
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	for _, inst in ipairs(pin.instances) do
		GameTooltip:AddDoubleLine(S.InstanceName(inst), (Range(inst) or "") .. (inst[3] and ("  " .. L["Raid"]) or ""), 1, 0.82, 0, 1, 1, 1)
	end
	local one = #pin.instances == 1 and pin.instances[1]
	local bosses = one and (Places().bosses or {})[one[1]]
	if bosses and #bosses > 0 then GameTooltip:AddLine(L["%d bosses"]:format(#bosses), 0.8, 0.8, 0.8) end
	if not MapsOn() then
		GameTooltip:AddLine(#pin.instances == 1 and L["Click to see what's inside"] or L["Click to pick one"], 0.6, 0.6, 0.6)
	elseif one then
		GameTooltip:AddLine((DungeonMap(one) or FloorsOf(one)) and L["Click to open its map"] or L["Click to see what's inside (no map of it yet)"], 0.6, 0.6, 0.6)
	else
		GameTooltip:AddLine(L["Click to pick one and open its map"], 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function Chooser()
	chooser = CreateFrame("Frame", "DavesMapDungeonChooser", map)
	chooser:SetFrameStrata("DIALOG")
	chooser:EnableMouse(true)
	chooser:SetClampedToScreen(true)
	chooser.pad = { Look:Dropdown(chooser) }      -- (the game's own dropdowns' look)
	if not PadView() then tinsert(UISpecialFrames, "DavesMapDungeonChooser") end   -- (the Gamepad UI reads that list)
	chooser.rows = {}
	chooser:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
	chooser:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
	chooser:SetScript("OnEvent", function(self) if not self:IsMouseOver() then self:Hide() end end)
	mod.padRoots[#mod.padRoots + 1] = chooser    -- (the gamepad's cursor presses its rows: Gamepad.lua)
	chooser:Hide()
end

local function Choose(pin)
	if not chooser then Chooser() end
	local w = 0
	for i, inst in ipairs(pin.instances) do
		local row = chooser.rows[i]
		if not row then
			row = CreateFrame("Button", nil, chooser)
			row:SetHeight(20)
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			row.name = Look:Font(row:CreateFontString(nil, "OVERLAY"), 13)
			row.name:SetPoint("LEFT", 6, 0)
			row.level = Look:Font(row:CreateFontString(nil, "OVERLAY"), 13)
			row.level:SetPoint("RIGHT", -6, 0)
			row:SetScript("OnClick", function(self) Open(self.inst, chooser.pin) end)
			chooser.rows[i] = row
		end
		row.inst = inst
		row.name:SetText(("|cffffd100%s|r"):format(S.InstanceName(inst)))
		row.level:SetText((Range(inst) or "") .. (inst[3] and ("  |cffbbbbbb" .. L["Raid"] .. "|r") or ""))
		row:SetHeight(24)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", chooser.pad[1], -chooser.pad[2] - (i - 1) * 24)
		row:SetPoint("TOPRIGHT", -chooser.pad[3], -chooser.pad[2] - (i - 1) * 24)
		row:Show()
		w = math.max(w, (row.name:GetStringWidth() or 100) + (row.level:GetStringWidth() or 40) + 44)
	end
	for i = #pin.instances + 1, #chooser.rows do chooser.rows[i]:Hide() end
	chooser.pin = pin
	chooser:SetSize(math.max(200, w) + chooser.pad[1] + chooser.pad[3], #pin.instances * 24 + chooser.pad[2] + chooser.pad[4])
	chooser:ClearAllPoints()
	chooser:SetPoint("TOPLEFT", pin, "BOTTOMRIGHT", 2, 2)
	chooser:Show()
end

local function Click(pin)
	GameTooltip:Hide()
	if #pin.instances == 1 then Open(pin.instances[1], pin) else Choose(pin) end
end

-- the range of levels under the icon: from its lowest to its highest (several at one entrance)
local function Label(pin)
	local lo, hi
	for _, inst in ipairs(pin.instances) do
		if inst[4] then lo, hi = math.min(lo or 99, inst[4]), math.max(hi or 0, inst[5] or inst[4]) end
	end
	if not pin.levelText then
		pin.levelText = Look:Font(pin:CreateFontString(nil, "OVERLAY"), 10, "OUTLINE")
		pin.levelText:SetPoint("TOP", pin, "BOTTOM", 0, 3)
	end
	local code, range
	if lo and mod.LevelColor then code, range = mod.LevelColor(lo, hi) end
	pin.levelText:SetText(range and mod.db.dungeonLevels and (code .. range .. "|r") or "")
end

local function Pin(set, u, v, insts, cont, x, y)
	local raid = true
	for _, inst in ipairs(insts) do raid = raid and inst[3] end
	local pin = S.AddPin(set, u, v, raid and LOOK.raid or LOOK.dungeon)
	pin.instances, pin.cont, pin.x, pin.y = insts, cont, x, y
	pin:SetScript("OnEnter", Enter)
	pin:SetScript("OnLeave", GameTooltip_Hide)
	pin.OnClick = Click
	Label(pin)
	entrancePins[#entrancePins + 1] = pin
	return pin
end

-- the entrances: the tables' (Stitch.lua's BuildPins asks); then any the client itself knows (its
-- encounter journal's, where it has one) for a dungeon the tables give no entrance
function S.BuildDungeonPins(set)
	wipe(entrancePins)
	for _, g in ipairs(Places().instances or {}) do
		local u, v = S.EntranceAt(g)
		if u then
			if g.map then Pin(set, u, v, g[4]) else Pin(set, u, v, g[4], g[1], g[2], g[3]) end
		end
	end
	local entrances = C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap
	if entrances then
		local known = {}
		for _, g in ipairs(Places().instances or {}) do
			for _, inst in ipairs(g[4]) do known[inst[2]] = true known[S.InstanceName(inst)] = true end
		end
		local unplaced = {}
		for _, inst in ipairs(Places().unplaced or {}) do unplaced[inst[2]] = inst end
		for _, zone in ipairs(C_Map.GetMapChildrenInfo(S.WORLD, Enum.UIMapType.Zone, true) or {}) do
			-- (the stitched zones': a client's world leaves some out, Khaz Algar's underground under the Isle of Dorn)
			local l, r, t, b
			if S.Stitched(zone.mapID) then l, r, t, b = S.Rect(zone.mapID) end
			local ok, list = pcall(entrances, zone.mapID)
			for _, e in ipairs(ok and l and list or {}) do
				local name = Safe.Value(e.name)
				local x, y = Safe.XY(e.position)
				if name and x and not known[name] then
					known[name] = true
					Pin(set, l + x * (r - l), t + y * (b - t), { unplaced[name] or { 0, name, false } })
				end
			end
		end
	end
	byMap = nil
	return entrancePins
end

local function Recolour()
	for _, pin in ipairs(entrancePins) do if pin.instances then Label(pin) end end
end

--------------------------------------------------------------------------------
-- Questie's quests for each dungeon (its zoneOrSort: the dungeon's area), read once
--------------------------------------------------------------------------------

local quests                    -- Questie's dungeon area -> { questID, ... } (nil: not read yet; false: it failed, tried again later)
local scanning
local dungeonOf                 -- Questie's area for part of a dungeon -> the dungeon's

local function Questie()
	local loader = _G.QuestieLoader
	if not loader then return end
	local ok, db = pcall(loader.ImportModule, loader, "QuestieDB")
	local ok2, zones = pcall(loader.ImportModule, loader, "ZoneDB")
	if ok and ok2 and db and db.QuestPointers and db.QueryQuestSingle and zones and zones.GetDungeons then return db, zones end
end

-- where a dungeon's quests come from: the one chosen, else the first there of Questie (listed here),
-- Dungeon Journal and NeedRoll (opened at them); nil with none
local function QuestSource()
	local have = { questie = _G.QuestieLoader ~= nil, journal = Journal() ~= nil, needroll = NeedRoll() ~= nil }
	local want = mod.db.questSource
	if have[want] then return want end
	return have.questie and "questie" or have.journal and "journal" or have.needroll and "needroll" or nil
end
mod.DungeonQuestSource = QuestSource
mod.HasDungeonJournal = function() return Journal() ~= nil end

-- a dungeon's area as Questie has it: its own, the dungeon its part of belongs to
local function DungeonArea(zones, areaId)
	if not dungeonOf then
		local list = zones:GetDungeons()
		if not list then return end                 -- (Questie's zones not read yet: asked again later)
		dungeonOf = {}
		for base, e in pairs(list) do
			dungeonOf[base] = base
			for _, alt in ipairs(e[2] or {}) do dungeonOf[alt] = dungeonOf[alt] or base end
		end
	end
	return dungeonOf[areaId]
end

local function Scan(done)
	local QDB, zones = Questie()
	if not QDB or not zones:GetDungeons() then return done(false) end
	local ids = {}
	for id in pairs(QDB.QuestPointers) do ids[#ids + 1] = id end
	local found, i = {}, 0
	local function Step()
		local ok, err = pcall(function()
			for _ = 1, 500 do
				i = i + 1
				local id = ids[i]
				if not id then return end
				local z = QDB.QueryQuestSingle(id, "zoneOrSort")
				local area = z and z > 0 and DungeonArea(zones, z)
				if area then
					found[area] = found[area] or {}
					tinsert(found[area], id)
				end
			end
		end)
		if not ok then geterrorhandler()(err) return done(false) end
		if ids[i] then C_Timer.After(0, Step) else done(found) end
	end
	Step()
end

-- whether you could take it: your race and class (Questie's masks: 0 is anyone)
local function ForYou(QDB, id)
	local _, _, race = UnitRace("player")
	local _, _, class = UnitClass("player")
	race, class = Safe.Value(race), Safe.Value(class)
	local races = QDB.QueryQuestSingle(id, "requiredRaces") or 0
	local classes = QDB.QueryQuestSingle(id, "requiredClasses") or 0
	if race and races ~= 0 and bit.band(races, 2 ^ (race - 1)) == 0 then return false end
	if class and classes ~= 0 and bit.band(classes, 2 ^ (class - 1)) == 0 then return false end
	return true
end

local areaOf = {}                -- dungeon map -> Questie's area for it (false: none; Questie's lookup is slow on a miss)

-- Questie's quests read, once (then `after`); again later if its database wasn't ready
EnsureQuests = function(after)
	if quests ~= nil or scanning or not Questie() then return end
	scanning = true
	Scan(function(found)
		scanning = false
		quests = found or false
		-- (Questie's database still loading, most likely: once more in a while)
		if not found then C_Timer.After(15, function() if quests == false then quests = nil after() end end) end
		C_Timer.After(0, after)
	end)
end

-- a dungeon's quests you could take, by level: { id, name, level, done, inLog }; nil while unknown
QuestList = function(mapID, inst)
	local QDB, zones = Questie()
	if not QDB or not quests then return end
	local key = mapID or (inst and inst[2])
	if not key then return end
	local area = areaOf[key]
	if area == nil then
		if mapID then
			local ok, found = pcall(zones.GetAreaIdByUiMapId, zones, mapID)
			area = ok and found and DungeonArea(zones, found)
		end
		if not area then
			local info = mapID and C_Map.GetMapInfo(mapID)
			local name = info and info.name or (inst and S.InstanceName(inst))
			local ok2, byName = pcall(zones.GetAreaIdByName, zones, name)
			area = ok2 and byName and DungeonArea(zones, byName)
		end
		areaOf[key] = area or false
	end
	local list = {}
	for _, id in ipairs(area and quests[area] or {}) do
		if ForYou(QDB, id) then
			list[#list + 1] = { id = id, name = QDB.QueryQuestSingle(id, "name") or "?", level = QDB.QueryQuestSingle(id, "questLevel") or 0 }
		end
	end
	table.sort(list, function(a, b) if a.level ~= b.level then return a.level < b.level end return a.name < b.name end)
	for _, q in ipairs(list) do
		q.done = C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q.id) or false
		q.inLog = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q.id) and true or false
	end
	return list
end

local function QuestColour(q)
	local c = q.level > 0 and GetQuestDifficultyColor(q.level)
	return q.done and "|cff808080" or c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
end

local function QuestLines(mapID, inst)
	local list = QuestList(mapID, inst)
	if not list then return end
	local lines = {}
	for _, q in ipairs(list) do
		local done, inLog = q.done, q.inLog
		local c = q.level > 0 and GetQuestDifficultyColor(q.level)
		local code = done and "|cff808080" or c and ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
		lines[#lines + 1] = ("%s[%d] %s|r%s"):format(code, q.level, q.name,
			done and ("  |cff808080" .. L["done"] .. "|r") or inLog and ("  |cff80f070" .. L["in your log"] .. "|r") or "")
	end
	return lines
end

--------------------------------------------------------------------------------
-- The card on a dungeon's map
--------------------------------------------------------------------------------


local function Card()
	card = CreateFrame("Frame", nil, map)
	card:SetWidth(CARD_W)
	-- (below Blizzard's filter and pin buttons where a client has them in that corner: retail's)
	card:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -8, ns.Client == "Forever" and -8 or -70)
	card:SetFrameLevel(math.min(sc:GetFrameLevel() + 9300, 9950))
	card:EnableMouse(true)
	Look:Panel(card, { alpha = 0.92 })
	mod.padRoots[#mod.padRoots + 1] = card
	local back = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
	back:SetSize(56, 20)
	back:SetPoint("TOPLEFT", 6, -6)
	back:SetText(L["Back"])
	back:SetScript("OnClick", Back)
	back:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Back to the world map, where you were (or right-click the map, or scroll out)"], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	back:SetScript("OnLeave", GameTooltip_Hide)
	card.back = back
	card.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	card.close:SetSize(24, 24)
	card.close:SetPoint("TOPRIGHT", 0, 0)
	card.close:SetScript("OnClick", function() portalCard = nil RefreshCard() end)
	card.fold = CreateFrame("Button", nil, card)
	card.fold:SetSize(18, 18)
	card.fold:SetPoint("TOPRIGHT", -26, -5)
	card.fold.icon = card.fold:CreateTexture(nil, "ARTWORK")
	card.fold.icon:SetAllPoints()
	card.fold:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	card.fold:SetScript("OnClick", function()
		mod.db.dungeonCard = not mod.db.dungeonCard
		RefreshCard()
	end)
	card.title = Look:Font(card:CreateFontString(nil, "OVERLAY"), 13)
	card.title:SetPoint("TOP", 0, -9)
	card.title:SetPoint("LEFT", back, "RIGHT", 8, 0)
	card.title:SetPoint("RIGHT", card.fold, "LEFT", -4, 0)
	card.title:SetJustifyH("LEFT")
	card.title:SetWordWrap(false)
	card.scroll = CreateFrame("ScrollFrame", nil, card, "UIPanelScrollFrameTemplate")
	card.scroll:SetPoint("TOPLEFT", 10, -32)
	card.scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	card.child = CreateFrame("Frame", nil, card.scroll)
	card.child:SetWidth(CARD_W - 40)
	card.text = Look:Font(card.child:CreateFontString(nil, "OVERLAY"), 12)
	card.text:SetPoint("TOPLEFT")
	card.text:SetWidth(CARD_W - 40)
	card.text:SetJustifyH("LEFT")
	card.text:SetSpacing(2)
	card.scroll:SetScrollChild(card.child)
	card:Hide()
end

local cardMap                   -- the dungeon map the card was last filled for (API.lua's callbacks)

-- what a dungeon map is, for other addons (API.lua): { mapID, instances = { { name, minLevel,
-- maxLevel, raid, bosses = { name, ... } }, ... } }
local function Info(mapID, insts)
	local list = {}
	for _, inst in ipairs(insts) do
		local bosses = {}
		for i, b in ipairs((Places().bosses or {})[inst[1]] or {}) do bosses[i] = b end
		list[#list + 1] = { name = S.InstanceName(inst), minLevel = inst[4], maxLevel = inst[5], raid = inst[3] and true or false, bosses = bosses }
	end
	return { mapID = mapID, instances = list }
end

RefreshCard = function()
	if not map then return end
	local mapID = map:GetMapID()
	-- on a dungeon's map; or over the world map, for a dungeon the client has no map of (its portal clicked)
	local onView = map:IsShown() and view and view:IsShown() or false
	local onMap = not onView and map:IsShown() and not mod.IsStitched() and IsDungeonMap(mapID)
	local onWorld = not onView and not onMap and map:IsShown() and mod.IsStitched() and portalCard ~= nil
	if not onMap and cardMap then
		cardMap = nil
		if mod.OnDungeonMap then mod.OnDungeonMap(nil) end
	end
	if onView or (not onMap and not onWorld) then
		if card then card:Hide() end
		if onView then FillSide() end
		return
	end
	if not card then Card() end
	local insts
	if onMap then
		local e = Index()[mapID]
		insts = e and e.insts or {}
	else
		insts = onView and { view.inst } or portalCard
		mapID = nil
	end
	local info = Info(mapID, insts)
	if onMap and cardMap ~= mapID then
		cardMap = mapID
		if mod.OnDungeonMap then mod.OnDungeonMap(info) end
	end
	local back = onMap or onView
	card.back:SetShown(back)
	card.close:SetShown(onWorld)
	card.title:SetPoint("LEFT", back and card.back or card, back and "RIGHT" or "LEFT", back and 8 or 10, 0)
	local head = {}
	for _, inst in ipairs(insts) do head[#head + 1] = S.InstanceName(inst) .. (Range(inst) and ("  " .. Range(inst)) or "") end
	local mapInfo = mapID and C_Map.GetMapInfo(mapID)
	card.title:SetText(#head > 0 and ("|cffffd100" .. table.concat(head, ", ") .. "|r") or ("|cffffd100" .. (mapInfo and mapInfo.name or "") .. "|r"))
	local open = mod.db.dungeonCard
	card.fold.icon:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
	local lines = {}
	if open and mod.db.dungeonBosses and insts[1] then
		local bosses = (Places().bosses or {})[insts[1][1]]
		if bosses and #bosses > 0 then
			lines[#lines + 1] = "|cffe6c27a" .. L["Bosses"] .. "|r"
			for i, name in ipairs(bosses) do lines[#lines + 1] = ("|cff998866%d.|r %s"):format(i, name) end
		end
	end
	if open and mod.db.dungeonQuests and QuestSource() == "questie" then
		EnsureQuests(RefreshCard)
		local q = QuestLines(mapID, insts[1])
		if q and #q > 0 then
			if #lines > 0 then lines[#lines + 1] = " " end
			lines[#lines + 1] = "|cffe6c27a" .. L["Quests"] .. "|r  |cff998866(Questie)|r"
			for _, line in ipairs(q) do lines[#lines + 1] = line end
		elseif scanning then
			lines[#lines + 1] = "|cff998866" .. L["Reading Questie's quests..."] .. "|r"
		end
	end
	-- other addons' sections (API.lua): a title and lines of their own, after ours
	if open and mod.CardSections then
		for _, section in ipairs(mod.CardSections()) do
			local ok, title, extra = pcall(section, info)
			if not ok then geterrorhandler()(title)
			elseif type(title) == "string" and type(extra) == "table" and #extra > 0 then
				if #lines > 0 then lines[#lines + 1] = " " end
				lines[#lines + 1] = "|cffe6c27a" .. title .. "|r"
				for i = 1, math.min(#extra, 40) do lines[#lines + 1] = tostring(extra[i]) end
			end
		end
	end
	card.text:SetText(table.concat(lines, "\n"))
	local h = #lines > 0 and math.min((card.text:GetStringHeight() or 0) + 4, math.max(80, sc:GetHeight() - 120)) or 0
	card.child:SetHeight((card.text:GetStringHeight() or 0) + 4)
	card.scroll:SetShown(#lines > 0)
	card:SetHeight(h > 0 and h + 42 or 32)
	card:Show()
end
-- the view's side panel: rows of one tab (bosses, quests, loot), each made as needed and kept
-- NeedRoll's window: at this dungeon's loot (on `boss`), or its map (`what` "map") or a quest (`quest`),
-- through NeedRoll's own calls (NeedRoll_ShowLoot ...: its API.md) where it has them; else just opened
-- (its /nr toggles: an open window is only brought up, not closed). The dungeon by its English name
-- first (a wing's, "Scarlet Monastery - Library", is NeedRoll's "Scarlet Monastery: Library": it reads
-- past punctuation), then its instance map ID (a boss then opens the wing it's in), then a boss alone
local function OpenNeedRoll(boss, what, quest)
	if quest then
		local show = _G.NeedRoll_ShowQuest
		if type(show) == "function" then
			local ok, done = pcall(show, quest)
			if ok and done then return end
		end
	end
	local show = what == "map" and _G.NeedRoll_ShowMap or _G.NeedRoll_ShowLoot
	if type(show) == "function" and view and view.inst then
		local inst = view.inst
		local tries = { { inst[2], boss } }
		if inst[1] > 0 then tries[#tries + 1] = { inst[1], boss } end
		if boss then tries[#tries + 1] = { nil, boss } end
		for _, t in ipairs(tries) do
			local ok, done = pcall(show, t[1], t[2])
			if ok and done then return end
		end
	end
	for _, name in ipairs({ "NeedRollFrame", "NeedRollNativeFrame" }) do
		local f = _G[name]
		if f and f.IsShown and f:IsShown() then
			if f.Raise then f:Raise() end
			return
		end
	end
	local open = NeedRoll()
	if open then pcall(open, "") end
end

FillSide = function()
	if not view or not view.side or not view:IsShown() then return end
	local side, inst = view.side, view.inst
	side.title:SetText("|cffffd100" .. S.InstanceName(inst) .. "|r")
	side.sub:SetText((Range(inst) and (LEVEL or "Level") .. " " .. Range(inst) or "") .. (inst[3] and ("   |cffbbbbbb" .. L["Raid"] .. "|r") or ""))
	-- the tabs there are (the menu's switches), the one shown
	local shown = { bosses = mod.db.dungeonBosses, quests = mod.db.dungeonQuests, loot = true,
		floors = view.floors and #view.floors > 1 }   -- (a dungeon of several floors: each as a picture)
	local tab = mod.db.dungeonTab
	if not shown[tab] then tab = shown.floors and "floors" or shown.bosses and "bosses" or shown.quests and "quests" or "loot" end
	local tx = 8
	for _, b in ipairs(side.tabs) do
		b:SetShown(shown[b.key] and true or false)
		if shown[b.key] then
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", b:GetParent(), "TOPLEFT", tx, -INNER_TABS)
			tx = tx + b:GetWidth() + 2
		end
		if b.SetSelected then b:SetSelected(b.key == tab) elseif b.key == tab then b:LockHighlight() else b:UnlockHighlight() end
	end
	-- what to show: { kind = "row" | "text" | "button" | "link", ... }
	local items = {}
	local function Text(t) items[#items + 1] = { kind = "text", t } end
	if tab == "bosses" then
		local bosses = (Places().bosses or {})[inst[1]] or {}
		for i, name in ipairs(bosses) do
			items[#items + 1] = { kind = "row", ("|cff998866%d.|r  %s"):format(i, name), click = NeedRoll() and function() OpenNeedRoll(name, IsShiftKeyDown() and "map" or nil) end,
				tip = function(owner)
					GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
					GameTooltip:AddLine(name, 1, 0.82, 0)
					GameTooltip:AddLine(NeedRoll() and L["Click to see loot in NeedRoll"] or L["See the Loot tab for loot"], 0.6, 0.6, 0.6)
					if _G.NeedRoll_ShowMap then GameTooltip:AddLine(L["Shift-click: where it is, on NeedRoll's map"], 0.6, 0.6, 0.6) end
					GameTooltip:Show()
				end }
		end
		if #bosses == 0 then Text("|cff998866" .. L["The game lists no bosses for it."] .. "|r") end
		if JournalName(inst) then
			items[#items + 1] = { kind = "button", L["Open in Dungeon Journal"], click = function() OpenJournal(inst) end }
		end
		-- other addons' sections (API.lua)
		for _, section in ipairs(mod.CardSections and mod.CardSections() or {}) do
			local ok, title, lines = pcall(section, Info(nil, { inst }))
			if not ok then geterrorhandler()(title)
			elseif type(title) == "string" and type(lines) == "table" and #lines > 0 then
				Text(" ")
				Text("|cffe6c27a" .. title .. "|r")
				for i = 1, math.min(#lines, 40) do Text(tostring(lines[i])) end
			end
		end
	elseif tab == "quests" then
		local source = QuestSource()
		if source == "journal" then
			if JournalName(inst) then
				Text(L["Dungeon Journal has this dungeon's quests: where each one starts, what it asks and what it gives."])
				items[#items + 1] = { kind = "button", L["Open in Dungeon Journal"], click = function() OpenJournal(inst, true) end }
			else
				Text("|cff998866" .. L["Dungeon Journal has no page for this dungeon."] .. "|r")
			end
		elseif source == "needroll" then
			Text(L["NeedRoll lists dungeon quests too: open it and pick this dungeon."])
			items[#items + 1] = { kind = "button", L["Open NeedRoll"], click = function() OpenNeedRoll() end }
		elseif not Questie() then
			local dmList = addonNs.DungeonQuestEntries and addonNs.DungeonQuestEntries(S.InstanceName(inst))
			if dmList and #dmList > 0 then
				for _, q in ipairs(dmList) do
					local badge = q.done and ("|cff808080" .. L["done"] .. "|r")
						or (q.state == "ready" and "|cffffd200Ready|r")
						or (q.inLog and ("|cff80f070" .. L["in your log"] .. "|r"))
						or (q.xpTxt and ("|cffe8d8a8" .. q.xpTxt .. "|r")) or nil
					local label = ("%s[%d] %s|r%s"):format(QuestColour(q), q.level, q.name, q.rewShort and ("  " .. q.rewShort) or "")
					items[#items + 1] = {
						kind = "row",
						label,
						right = badge,
						click = addonNs.InspectPinFromDungeonView and function()
							addonNs.InspectPinFromDungeonView(q.pin, S.InstanceName(inst))
						end,
						tip = addonNs.ShowTooltip and function(owner)
							addonNs.ShowTooltip(owner, q.pin)
						end,
					}
				end
			else
				Text("|cff998866" .. L["With Questie, Dungeon Journal or NeedRoll, this dungeon's quests are here."] .. "|r")
			end
		else
			EnsureQuests(FillSide)
			local list = QuestList(nil, inst)
			if not list then Text("|cff998866" .. L["Reading Questie's quests..."] .. "|r")
			elseif #list == 0 then Text("|cff998866" .. L["Questie lists no quests for it that you can take."] .. "|r")
			else
				local QDB = Questie()
				for _, q in ipairs(list) do
					items[#items + 1] = { kind = "row", ("%s[%d] %s|r"):format(QuestColour(q), q.level, q.name),
						right = q.done and ("|cff808080" .. L["done"] .. "|r") or q.inLog and ("|cff80f070" .. L["in your log"] .. "|r") or nil,
						click = _G.NeedRoll_ShowQuest and function() OpenNeedRoll(nil, nil, q.id) end,
						tip = function(owner)
							GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
							GameTooltip:AddLine(q.name, 1, 0.82, 0, true)
							local okText, text = pcall(QDB.QueryQuestSingle, q.id, "objectivesText")
							if okText and type(text) == "table" then
								for _, line in ipairs(text) do GameTooltip:AddLine(line, 1, 1, 1, true) end
							end
							local okReq, req = pcall(QDB.QueryQuestSingle, q.id, "requiredLevel")
							GameTooltip:AddLine((LEVEL or "Level") .. " " .. q.level .. (okReq and req and req > 0 and ("  (" .. L["from %d"]:format(req) .. ")") or ""), 0.8, 0.8, 0.8)
							GameTooltip:AddLine(q.done and L["Completed"] or q.inLog and L["In your quest log"] or "", 0.5, 0.95, 0.4)
							if _G.NeedRoll_ShowQuest then GameTooltip:AddLine(L["Click to see it in NeedRoll"], 0.6, 0.6, 0.6) end
							GameTooltip:Show()
						end }
				end
			end
		end
	elseif tab == "floors" then
		for i = 1, #view.floors do items[#items + 1] = { kind = "thumb", floor = i } end
	else
		if NeedRoll() then
			Text(L["NeedRoll lists this dungeon's loot: what every boss drops, what you've collected, and a wishlist."])
			items[#items + 1] = { kind = "button", L["Open NeedRoll"], click = function() OpenNeedRoll() end }
		elseif ns.Client ~= "Forever" then           -- (NeedRoll is WoW Forever's; another client has its own guide)
			Text(L["This dungeon's loot is in the game's Adventure Guide."])
		else
			Text(L["For loot, we recommend |cffffd100NeedRoll|r, by mikebvs: what every boss drops, what you've collected, and a wishlist, made for WoW Forever."])
			Text("|cff998866" .. L["Get it from CurseForge (click, then Ctrl-C):"] .. "|r")
			items[#items + 1] = { kind = "link", NEEDROLL_URL }
		end
	end
	-- lay them out
	for _, pool in pairs(side.pool) do for _, w in ipairs(pool) do w:Hide() end end
	local used = { row = 0, text = 0, button = 0, link = 0, thumb = 0 }
	side.filledW = side:GetWidth()
	local listW = side.scroll:GetWidth()
	local width, y = (listW and listW > 100) and (listW - 4) or (SIDE_W - LOG_BAR - 12), 0
	side.child:SetWidth(width)
	for _, it in ipairs(items) do
		used[it.kind] = used[it.kind] + 1
		local w = side.pool[it.kind][used[it.kind]]
		if not w then
			if it.kind == "row" then
				w = CreateFrame("Button", nil, side.child)
				w:SetHeight(24)
				w:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
				w.left = Look:Font(w:CreateFontString(nil, "OVERLAY"), 13)
				w.left:SetPoint("LEFT", 4, 0)
				w.left:SetJustifyH("LEFT")
				w.left:SetWordWrap(false)
				w.right = Look:Font(w:CreateFontString(nil, "OVERLAY"), 11)
				w.right:SetPoint("RIGHT", -4, 0)
				w.left:SetPoint("RIGHT", w.right, "LEFT", -6, 0)
				w:SetScript("OnEnter", function(self) if self.item.tip then self.item.tip(self) end end)
				w:SetScript("OnLeave", GameTooltip_Hide)
				w:SetScript("OnClick", function(self) if self.item.click then self.item.click() end end)
			elseif it.kind == "text" then
				w = Look:Font(side.child:CreateFontString(nil, "OVERLAY"), 13)
				w:SetJustifyH("LEFT")
				w:SetSpacing(3)
			elseif it.kind == "button" then
				w = CreateFrame("Button", nil, side.child, "UIPanelButtonTemplate")
				w:SetSize(150, 26)
				w:SetScript("OnClick", function(self) if self.item.click then self.item.click() end end)
			elseif it.kind == "thumb" then
				-- a floor's picture, small (its 12 tiles), its name under it; click: that floor
				w = CreateFrame("Button", nil, side.child, "BackdropTemplate")
				w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
				w:SetBackdropColor(0.05, 0.04, 0.03, 0.9)
				w.tiles = {}
				for k = 1, 12 do w.tiles[k] = w:CreateTexture(nil, "ARTWORK") end
				local hl = w:CreateTexture(nil, "HIGHLIGHT")
				hl:SetPoint("TOPLEFT", 1, -1)
				hl:SetPoint("BOTTOMRIGHT", -1, 1)
				hl:SetColorTexture(1, 0.85, 0.5, 0.15)
				w.name = Look:Font(w:CreateFontString(nil, "OVERLAY"), 11)
				w.name:SetPoint("TOP", w, "BOTTOM", 0, -3)
				w.name:SetWordWrap(false)
				w:SetScript("OnClick", function(self) ShowFloor(self.item.floor) end)
			else
				w = CreateFrame("EditBox", nil, side.child, "InputBoxTemplate")
				w:SetSize(width - 12, 22)
				w:SetAutoFocus(false)
				w:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.item[1]) self:HighlightText() end end)
				w:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
				w:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
			end
			side.pool[it.kind][used[it.kind]] = w
		end
		w.item = it
		w:ClearAllPoints()
		if it.kind == "row" then
			w:SetPoint("TOPLEFT", 0, -y)
			w:SetWidth(width)
			w.left:SetText(it[1])
			w.right:SetText(it.right or "")
			y = y + 24
		elseif it.kind == "text" then
			w:SetPoint("TOPLEFT", 4, -y - 4)
			w:SetWidth(width - 8)
			w:SetText(it[1])
			y = y + (w:GetStringHeight() or 14) + 10
		elseif it.kind == "button" then
			w:SetPoint("TOPLEFT", 4, -y - 2)
			w:SetText(it[1])
			y = y + 34
		elseif it.kind == "thumb" then
			-- (two across: the second beside the first, then on down)
			local tw = math.floor((width - 10) / 2)
			local th = math.floor(tw * PIC_H / PIC_W)
			local col = (used.thumb - 1) % 2
			w:SetSize(tw, th)
			w:SetPoint("TOPLEFT", 2 + col * (tw + 6), -y - 2)
			local s = (tw - 2) / PIC_W
			local f = view.floors[it.floor]
			for k, t in ipairs(w.tiles) do
				local c, r = (k - 1) % 4, math.floor((k - 1) / 4)
				local cw, ch = math.min(256, PIC_W - c * 256), math.min(256, PIC_H - r * 256)
				t:SetTexture(f.tiles and f.tiles[k], nil, nil, "TRILINEAR")
				t:SetSize(cw * s, ch * s)
				t:SetPoint("TOPLEFT", 1 + c * 256 * s, -1 - r * 256 * s)
				t:SetTexCoord(0, cw / 256, 0, ch / 256)
			end
			w.name:SetWidth(tw)
			w.name:SetText(view.FloorName(it.floor))
			if col == 1 or it.floor == #view.floors then y = y + th + 22 end
		else
			w:SetPoint("TOPLEFT", 10, -y - 2)
			w:SetText(it[1])
			w:SetCursorPosition(0)
			y = y + 30
		end
		w:Show()
	end
	side.child:SetHeight(math.max(1, y))
	side.scroll:SetVerticalScroll(0)
	side.LightThumbs()
end

--------------------------------------------------------------------------------
-- Boss pins: where each boss is on the floor shown (Data/DungeonBosses.lua, from the journals and
-- the places set by hand), numbered as the Bosses tab lists them; with "Dungeon maps: bosses".
-- The placer (/openmap bosses, on a dungeon's map): click where the boss named in its bar is, and
-- it goes on to the next; right-click skips one, shift-click takes the last one back. What it places
-- is kept in OpenMapDB (worldmap, bossPlaced), shown over the shipped places at once, and
-- tools/map-dungeons/bosses.py --import brings it into the data.
--------------------------------------------------------------------------------

local PIN_SIZE = 26

-- (as Kept's; a map built from the minimap pictures has its own floors, so its own places: "minimap:<mapID>")
local function InstKey(inst)
	local key = inst and (inst[1] ~= 0 and inst[1] or inst[2])
	if key and view and view.source == "minimap" and view.inst == inst then return "minimap:" .. key end
	return key
end

function bossUI.InstKeyFor(inst, src)
	local key = inst and (inst[1] ~= 0 and inst[1] or inst[2])
	if not key then return nil end
	if src == "minimap" then return "minimap:" .. key end
	return key
end

function bossUI.IsRare(entry)
	return type(entry) == "table" and entry.rare == true
end

function bossUI.Spots(entry)
	if type(entry) ~= "table" then return nil end
	if type(entry.spots) == "table" and #entry.spots > 0 then return entry.spots end
	if entry[1] and entry[2] and entry[3] then return { entry } end
	return nil
end

-- Pure read-only lookup of a boss/rare entry (user-placed position overrides shipped coords while preserving rare/note metadata).
function bossUI.ReadEntry(inst, name, src)
	if not (inst and name) then return nil, false, false, nil end
	local key = bossUI.InstKeyFor(inst, src)
	if not key then return nil, false, false, nil end
	local shippedTbl = ns.MapDungeonBosses and ns.MapDungeonBosses[key]
	local shipped = shippedTbl and shippedTbl[name]
	local placedTbl = mod.db and mod.db.bossPlaced
	local mineTbl = placedTbl and (placedTbl[key] or (src ~= "minimap" and inst[2] and placedTbl[inst[2]]))
	local mine = mineTbl and mineTbl[name]
	if mine then
		return mine, true, bossUI.IsRare(mine) or bossUI.IsRare(shipped), mine.note or (shipped and shipped.note)
	end
	if shipped then
		return shipped, false, bossUI.IsRare(shipped), shipped.note
	end
	return nil, false, false, nil
end

-- Pure ordered boss & rare list: guaranteed bosses in encounter order first (numbered 1..N),
-- followed by rare spawns (unnumbered, badged with R / R1..Rn).
function bossUI.BossNamesFor(inst, src)
	local regular, rares, seen = {}, {}, {}
	local key = bossUI.InstKeyFor(inst, src)
	local shipped = key and ns.MapDungeonBosses and ns.MapDungeonBosses[key]
	local placedTbl = mod.db and mod.db.bossPlaced
	local mine = key and placedTbl and (placedTbl[key] or (src ~= "minimap" and inst[2] and placedTbl[inst[2]]))
	local function IsRareName(n)
		local e = (mine and mine[n]) or (shipped and shipped[n])
		return bossUI.IsRare(e) or (shipped and bossUI.IsRare(shipped[n]))
	end
	local function Push(n)
		if seen[n] then return end
		seen[n] = true
		if IsRareName(n) then rares[#rares + 1] = n else regular[#regular + 1] = n end
	end
	for _, n in ipairs((Places().bosses or {})[inst[1]] or {}) do
		Push(n)
	end
	for _, tbl in ipairs({ shipped, mine }) do
		local extra = {}
		for n in pairs(tbl or {}) do if not seen[n] then extra[#extra + 1] = n end end
		table.sort(extra)
		for _, n in ipairs(extra) do Push(n) end
	end
	local names, bossNums = {}, {}
	for i, n in ipairs(regular) do
		names[#names + 1] = n
		bossNums[n] = i
	end
	for _, n in ipairs(rares) do
		names[#names + 1] = n
	end
	return names, bossNums
end

-- the game's bosses of the instance shown, in its order, followed by rare spawns and any placed by hand
local function BossNames(inst)
	local src = (view and view.inst == inst) and view.source or nil
	return bossUI.BossNamesFor(inst, src)
end

-- a boss's place: { floor, x, y [, rare = true] [, spots = ...] [, note = ...] }, the placer's over the shipped one; nil where it has none
local function BossAt(inst, name)
	ByMapID(mod.db.bossPlaced, inst)
	local src = (view and view.inst == inst) and view.source or nil
	return bossUI.ReadEntry(inst, name, src)
end

function bossUI.OtherFloorsText(spots, curFloor)
	if not (spots and #spots > 1) then return nil end
	local seen, list = {}, {}
	for _, sp in ipairs(spots) do
		local fl = sp[1]
		if fl and fl ~= curFloor and not seen[fl] then
			seen[fl] = true
			local fn = view and view.FloorName and view.FloorName(fl)
			if fn then
				list[#list + 1] = ("%s (F%d)"):format(fn, fl)
			else
				list[#list + 1] = "Floor " .. tostring(fl)
			end
		end
	end
	return #list > 0 and table.concat(list, ", ") or nil
end

function bossUI.StylePin(pin, isRare)
	pin.icon:SetDesaturated(false)
	pin.icon:SetTexCoord(0, 1, 0, 1)
	if isRare then
		if Atlas(pin.icon, "VignetteKillElite") or Atlas(pin.icon, "VignetteKill") then
			pin.icon:SetVertexColor(0.86, 0.96, 1, 1)
		else
			pin.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
			pin.icon:SetDesaturated(true)
			pin.icon:SetVertexColor(0.58, 0.92, 1, 1)
		end
		pin.hlRing:SetVertexColor(0.38, 0.88, 1, 0.92)
		pin.rim:SetVertexColor(0.36, 0.84, 1, 0.95)
		pin.ring:SetVertexColor(0.03, 0.08, 0.13, 0.92)
		pin.num:SetTextColor(0.58, 0.94, 1)
		pin.tag:SetBackdropColor(0.03, 0.07, 0.11, 0.90)
		pin.tag:SetBackdropBorderColor(0.36, 0.80, 0.98, 0.88)
	else
		if Atlas(pin.icon, "DungeonSkull") then
			pin.icon:SetVertexColor(1, 1, 1, 1)
		else
			pin.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
			pin.icon:SetVertexColor(1, 0.92, 0.72, 1)
		end
		pin.hlRing:SetVertexColor(1, 0.82, 0.22, 0.90)
		pin.rim:SetVertexColor(0.88, 0.68, 0.22, 0.88)
		pin.ring:SetVertexColor(0.04, 0.03, 0.02, 0.90)
		pin.num:SetTextColor(1, 0.84, 0.18)
		pin.tag:SetBackdropColor(0.05, 0.04, 0.03, 0.88)
		pin.tag:SetBackdropBorderColor(0.78, 0.60, 0.24, 0.84)
	end
end

function bossUI.PlaceTagNonOverlapping(pin, pinX, pinY, tagW, tagH, pw, ph, usedBoxes)
	local halfP = PIN_SIZE * 0.5 + 3
	local pad = 4
	local maxX = math.max(pad, pw - pad - tagW)
	local maxY = math.max(pad, ph - pad - tagH)
	local cands = {
		{ pinX - tagW * 0.5, pinY + halfP },
		{ pinX - tagW * 0.5, pinY - halfP - tagH },
		{ pinX + halfP + 2, pinY - tagH * 0.5 },
		{ pinX - halfP - 2 - tagW, pinY - tagH * 0.5 },
		{ pinX + 4, pinY + halfP },
		{ pinX + 4, pinY - halfP - tagH },
		{ pinX - tagW - 4, pinY + halfP },
		{ pinX - tagW - 4, pinY - halfP - tagH },
		{ pinX - tagW * 0.5, pinY + halfP + tagH + 3 },
		{ pinX - tagW * 0.5, pinY - halfP - tagH * 2 - 3 },
	}
	local bestX, bestY, bestScore = pad, pad, math.huge
	for _, c in ipairs(cands) do
		local x0 = math.max(pad, math.min(maxX, c[1]))
		local y0 = math.max(pad, math.min(maxY, c[2]))
		local x1, y1 = x0 + tagW, y0 + tagH
		local score = 0
		for _, b in ipairs(usedBoxes) do
			local ox = math.min(x1, b[3]) - math.max(x0, b[1])
			if ox > 0 then
				local oy = math.min(y1, b[4]) - math.max(y0, b[2])
				if oy > 0 then score = score + ox * oy end
			end
		end
		if score < bestScore then
			bestScore, bestX, bestY = score, x0, y0
			if score == 0 then break end
		end
	end
	usedBoxes[#usedBoxes + 1] = { bestX - 1, bestY - 1, bestX + tagW + 1, bestY + tagH + 1 }
	pin.tag:ClearAllPoints()
	pin.tag:SetPoint("TOPLEFT", view.page, "TOPLEFT", bestX, -bestY)
end

function bossUI.AppendBossDrops(inst, bossName, maxShown)
	if not (addonNs and addonNs.BossDrops and addonNs.ItemDisplay and inst and bossName) then return end
	local drops = addonNs.BossDrops(inst[1], inst[2], bossName)
	if not (drops and #drops >= 2) then return end
	local total = math.floor(#drops / 2)
	local lim = math.min(total, maxShown or 8)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Notable Drops:", 1, 0.82, 0)
	for idx = 1, lim do
		local k = (idx - 1) * 2 + 1
		local itemID = drops[k]
		local pctX10 = drops[k + 1] or 0
		local name, hex, icon, subLabel = addonNs.ItemDisplay(itemID)
		local leftTxt = ("|T%s:13:13:0:0:64:64:5:59:5:59|t |c%s%s|r"):format(
			tostring(icon or 134400), hex or "ffe8d8a8", name or ("Item #" .. tostring(itemID)))
		local pctTxt = addonNs.FormatDropPct and addonNs.FormatDropPct(pctX10) or nil
		local rightTxt
		if subLabel and subLabel ~= "" and pctTxt then
			rightTxt = subLabel .. " - " .. pctTxt
		else
			rightTxt = pctTxt or subLabel or ""
		end
		if rightTxt ~= "" then
			GameTooltip:AddDoubleLine(leftTxt, rightTxt, 1, 1, 1, 0.72, 0.78, 0.84)
		else
			GameTooltip:AddLine(leftTxt, 1, 1, 1)
		end
	end
	if total > lim then
		GameTooltip:AddLine(("+%d more in Dungeon tab"):format(total - lim), 0.62, 0.74, 0.86)
	end
end

local function PinTip(pin)
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	if pin.isRare then
		GameTooltip:AddLine((pin.name or "") .. "  [Rare]", 0.48, 0.88, 1)
		if pin.spotTotal and pin.spotTotal > 1 then
			GameTooltip:AddLine(("Possible spawn %d of %d (rare - not guaranteed every run)"):format(pin.spotIdx or 1, pin.spotTotal), 0.72, 0.90, 1, true)
		else
			GameTooltip:AddLine("Rare spawn (not guaranteed every run)", 0.72, 0.90, 1, true)
		end
	else
		local head = pin.bossNum and ("%d. %s"):format(pin.bossNum, pin.name) or (pin.name or "")
		GameTooltip:AddLine(head, 1, 0.82, 0)
		if pin.spotTotal and pin.spotTotal > 1 then
			GameTooltip:AddLine(("Location %d of %d"):format(pin.spotIdx or 1, pin.spotTotal), 0.55, 0.85, 1)
		end
	end
	if pin.note and pin.note ~= "" then
		GameTooltip:AddLine(pin.note, 0.88, 0.86, 0.80, true)
	end
	if pin.otherFloors then
		GameTooltip:AddLine("Also on: " .. pin.otherFloors, 0.60, 0.82, 0.98, true)
	end
	bossUI.AppendBossDrops(view and view.inst, pin.name, 8)
	if pin.mine then GameTooltip:AddLine(L["Placed by you"], 0.6, 0.6, 0.6) end
	if NeedRoll() then GameTooltip:AddLine(L["Click to see loot in NeedRoll"], 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

local function MakePin(i)
	local pin = CreateFrame("Button", nil, view.page)
	pin:SetSize(PIN_SIZE, PIN_SIZE)
	pin:SetFrameLevel(view.page:GetFrameLevel() + 5)
	pin.hlRing = pin:CreateTexture(nil, "BACKGROUND", nil, -1)
	pin.hlRing:SetPoint("CENTER")
	pin.hlRing:SetSize(PIN_SIZE + 20, PIN_SIZE + 20)
	pin.hlRing:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	pin.hlRing:SetBlendMode("ADD")
	pin.hlRing:SetVertexColor(1, 0.82, 0.22, 0.90)
	pin.hlRing:Hide()
	pin.rim = pin:CreateTexture(nil, "BACKGROUND", nil, 0)
	pin.rim:SetPoint("CENTER")
	pin.rim:SetSize(PIN_SIZE + 10, PIN_SIZE + 10)
	pin.rim:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	pin.rim:SetVertexColor(0.88, 0.68, 0.22, 0.88)
	pin.ring = pin:CreateTexture(nil, "BACKGROUND", nil, 1)
	pin.ring:SetPoint("CENTER")
	pin.ring:SetSize(PIN_SIZE + 6, PIN_SIZE + 6)
	pin.ring:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	pin.ring:SetVertexColor(0.04, 0.03, 0.02, 0.90)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetPoint("CENTER")
	pin.icon:SetSize(PIN_SIZE, PIN_SIZE)
	if not Atlas(pin.icon, "DungeonSkull") then pin.icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull") end
	pin.num = Look:Font(pin:CreateFontString(nil, "OVERLAY"), 10, "OUTLINE")
	pin.num:SetPoint("CENTER", pin, "BOTTOMRIGHT", -1, 2)
	pin.num:SetTextColor(1, 0.84, 0.18)
	-- (daves_map: crisp always-visible nameplate parented to view.page so raising a hovered tag never disturbs pin mouse focus)
	local tag = CreateFrame("Frame", nil, view.page, "BackdropTemplate")
	tag:SetHeight(17)
	tag:SetFrameLevel(view.page:GetFrameLevel() + 7)
	tag:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	tag:SetBackdropColor(0.05, 0.04, 0.03, 0.88)
	tag:SetBackdropBorderColor(0.78, 0.60, 0.24, 0.84)
	tag:EnableMouse(false)
	tag.text = Look:Font(tag:CreateFontString(nil, "OVERLAY"), 10)
	tag.text:SetPoint("CENTER", 0, 0)
	tag.text:SetWordWrap(false)
	tag:Hide()
	pin.tag = tag
	pin:SetScript("OnEnter", function(self)
		bossUI.hoverBoss = self.name
		if bossUI.RefreshHighlight then bossUI.RefreshHighlight() end
		PinTip(self)
	end)
	pin:SetScript("OnLeave", function(self)
		if bossUI.hoverBoss == self.name then
			bossUI.hoverBoss = nil
			if bossUI.RefreshHighlight then bossUI.RefreshHighlight() end
		end
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	pin:SetScript("OnClick", function(self)
		bossUI.focusBoss = self.name
		if bossUI.RefreshHighlight then bossUI.RefreshHighlight() end
		if NeedRoll() then OpenNeedRoll(self.name, IsShiftKeyDown() and "map" or nil) end
	end)
	view.bossPins[i] = pin
	return pin
end

PlacePins = function(pw, ph)
	view.bossPins = view.bossPins or {}
	local n = 0
	local placed = {}
	local usedBoxes = {}
	local inst = view.inst
	local placing = view.placer
	if inst and mod.db.dungeonBosses and view.floors and not (view.floors[view.floor] or {}).blank then
		local names, bossNums = BossNames(inst)
		for i, name in ipairs(names) do
			local entry, mine, isRare, note = BossAt(inst, name)
			local spots = bossUI.Spots(entry)
			if spots then
				local spotTotal = #spots
				local otherFloors = bossUI.OtherFloorsText(spots, view.floor)
				local bNum = bossNums[name]
				for sIdx, sp in ipairs(spots) do
					if sp[1] == view.floor then
						n = n + 1
						local pin = view.bossPins[n] or MakePin(n)
						pin.index, pin.bossNum, pin.name, pin.mine = i, bNum, name, mine
						pin.isRare, pin.note = isRare, note
						pin.spotIdx, pin.spotTotal, pin.otherFloors = sIdx, spotTotal, otherFloors
						pin.px, pin.py = sp[2], sp[3]
						bossUI.StylePin(pin, isRare)
						if isRare then
							pin.num:SetText(spotTotal > 1 and ("R" .. sIdx) or "R")
						elseif bNum then
							pin.num:SetText(tostring(bNum))
						else
							pin.num:SetText("")
						end
						local pinX, pinY = sp[2] * pw, sp[3] * ph
						pin:ClearAllPoints()
						pin:SetPoint("CENTER", view.page, "TOPLEFT", pinX, -pinY)
						if isRare then
							if spotTotal > 1 then
								pin.tag.text:SetText(("|cff7fd4ffRare %d/%d:|r %s"):format(sIdx, spotTotal, name))
							else
								pin.tag.text:SetText("|cff7fd4ffRare:|r " .. name)
							end
						else
							local prefix = bNum and ("|cffffd100%d.|r "):format(bNum) or ""
							local suffix = spotTotal > 1 and (" |cff998866(%d/%d)|r"):format(sIdx, spotTotal) or ""
							pin.tag.text:SetText(prefix .. name .. suffix)
						end
						local rawTagW = (pin.tag.text.GetUnboundedStringWidth and pin.tag.text:GetUnboundedStringWidth()) or pin.tag.text:GetStringWidth() or 40
						local tagW = math.max(50, rawTagW + 12)
						pin.tag:SetWidth(tagW)
						pin:EnableMouse(not placing)
						pin:Show()
						local boxR = PIN_SIZE * 0.5 + 3
						usedBoxes[#usedBoxes + 1] = { pinX - boxR, pinY - boxR, pinX + boxR, pinY + boxR }
						placed[#placed + 1] = { pin = pin, x = pinX, y = pinY, w = tagW, h = 17 }
					end
				end
			end
		end
	end
	if not placing then
		for _, p in ipairs(placed) do
			bossUI.PlaceTagNonOverlapping(p.pin, p.x, p.y, p.w, p.h, pw, ph, usedBoxes)
		end
	end
	for i = n + 1, #view.bossPins do
		local p = view.bossPins[i]
		p.tag:Hide()
		p.hlRing:Hide()
		p:Hide()
	end
	if bossUI.RefreshHighlight then bossUI.RefreshHighlight() end
end

local function RedrawPins()
	local pw, ph = view.page:GetSize()
	if pw and pw > 0 then PlacePins(pw, ph) end
end
mod.RedrawBossPins = function() if view and view:IsShown() then RedrawPins() end end

-- (daves_map: on-map collapsible Bosses overlay, header width management, and interactive pin highlighting)
function bossUI.LayoutHeader()
	if not (view and view.floorButton and view.where and view.prev and view.next) then return end
	local barW = view:GetWidth()
	if not barW or barW <= 0 then return end
	local floors = view.floors or {}
	local multi = #floors > 1
	local rightRes = 38 + ((view.bossBtn and view.bossBtn:IsShown()) and (view.bossBtn:GetWidth() + 10) or 0)
	local hasWhere = (view.where:GetText() or "") ~= ""
	local leftRes = hasWhere and math.min(130, math.max(58, math.floor(barW * 0.22))) or 10
	local arrowPad = multi and 32 or 4
	local maxFW = math.max(96, barW - leftRes - rightRes - arrowPad * 2)
	local rawW = (view.floorName.GetUnboundedStringWidth and view.floorName:GetUnboundedStringWidth()) or view.floorName:GetStringWidth() or 110
	local textW = rawW + 20
	local fw = math.min(maxFW, math.max(110, textW))
	view.floorButton:SetWidth(fw)
	local spanL = leftRes + arrowPad
	local spanR = barW - rightRes - arrowPad
	local half = fw * 0.5
	local mid = barW * 0.5
	local cx = 0
	if (mid + half > spanR) or (mid - half < spanL) then
		cx = ((spanL + spanR) * 0.5) - mid
	end
	view.floorButton:ClearAllPoints()
	view.floorButton:SetPoint("CENTER", view.floorButton:GetParent(), "CENTER", cx, 0)
	view.where:ClearAllPoints()
	view.where:SetPoint("LEFT", view.where:GetParent(), "LEFT", 12, 0)
	view.where:SetPoint("RIGHT", multi and view.prev or view.floorButton, "LEFT", -6, 0)
end

function bossUI.RefreshHighlight()
	if not view then return end
	local placing = view.placer
	local active = (not placing) and (bossUI.hoverBoss or bossUI.focusBoss) or nil
	local baseLvl = view.page and (view.page:GetFrameLevel() + 5) or 10
	local normalTagLvl, litTagLvl = baseLvl + 2, baseLvl + 8
	for _, pin in ipairs(view.bossPins or {}) do
		if pin:IsShown() then
			local lit = active ~= nil and pin.name == active
			pin.hlRing:SetShown(lit)
			pin.tag:SetShown(not placing)
			pin.icon:SetSize(lit and (PIN_SIZE + 5) or PIN_SIZE, lit and (PIN_SIZE + 5) or PIN_SIZE)
			pin.ring:SetSize(lit and (PIN_SIZE + 11) or (PIN_SIZE + 6), lit and (PIN_SIZE + 11) or (PIN_SIZE + 6))
			pin.rim:SetSize(lit and (PIN_SIZE + 15) or (PIN_SIZE + 10), lit and (PIN_SIZE + 15) or (PIN_SIZE + 10))
			if pin.isRare then
				pin.tag:SetBackdropBorderColor(lit and 0.54 or 0.36, lit and 0.94 or 0.80, lit and 1 or 0.98, lit and 1 or 0.88)
			else
				pin.tag:SetBackdropBorderColor(lit and 1 or 0.78, lit and 0.86 or 0.60, lit and 0.30 or 0.24, lit and 1 or 0.84)
			end
			if placing then
				pin:SetAlpha(placing.last == pin.name and 1 or 0.6)
			else
				pin:SetAlpha(1)
				pin.tag:SetAlpha(lit and 1 or 0.88)
			end
			-- Keep interactive pin Button frame levels fixed so hover never bounces OnLeave/OnEnter;
			-- only raise the mouse-transparent nameplate frame (parented to view.page).
			local wantTagLvl = lit and litTagLvl or normalTagLvl
			if pin.tag:GetFrameLevel() ~= wantTagLvl then
				pin.tag:SetFrameLevel(wantTagLvl)
			end
		end
	end
	local bp = view.bossPanel
	if bp and bp:IsShown() then
		for _, row in ipairs(bp.rows or {}) do
			if row:IsShown() then
				local lit = active ~= nil and row.bossName == active
				row.selBg:SetShown(lit)
			end
		end
	end
end

function bossUI.ApplyScroll(bp)
	if not bp then return end
	local clipH = bp.clip:GetHeight() or 1
	local maxScroll = math.max(0, (bp.contentH or 0) - clipH)
	bp.scrollY = math.max(0, math.min(bp.scrollY or 0, maxScroll))
	bp.content:ClearAllPoints()
	bp.content:SetPoint("TOPLEFT", bp.clip, "TOPLEFT", 0, bp.scrollY)
	bp.content:SetPoint("TOPRIGHT", bp.clip, "TOPRIGHT", 0, bp.scrollY)
	if maxScroll > 1 then
		local trackH = math.max(16, clipH - 4)
		local thumbH = math.max(18, math.floor(trackH * (clipH / bp.contentH)))
		local travel = math.max(1, trackH - thumbH)
		local offset = math.floor((bp.scrollY / maxScroll) * travel + 0.5)
		bp.thumb:SetHeight(thumbH)
		bp.thumb:ClearAllPoints()
		bp.thumb:SetPoint("TOPRIGHT", bp.clip, "TOPRIGHT", -1, -2 - offset)
		bp.thumb:Show()
	else
		bp.thumb:Hide()
	end
end

function bossUI.LayoutPanel()
	local bp = view and view.bossPanel
	if not (bp and bp:IsShown()) then return end
	local portH = view.port and view.port:GetHeight() or 360
	local maxH = math.max(96, math.floor(portH - 16))
	local footH = bp.foot:IsShown() and 18 or 0
	local wantH = 26 + (bp.contentH or 20) + footH + 8
	bp:SetHeight(math.min(maxH, wantH))
	bp.clip:ClearAllPoints()
	bp.clip:SetPoint("TOPLEFT", bp, "TOPLEFT", 4, -26)
	bp.clip:SetPoint("BOTTOMRIGHT", bp, "BOTTOMRIGHT", -4, 4 + footH)
	bossUI.ApplyScroll(bp)
end

function bossUI.BuildPanel()
	if not view or view.bossPanel then return end
	local bp = CreateFrame("Frame", nil, view, "BackdropTemplate")
	bp:SetWidth(214)
	bp:SetPoint("TOPRIGHT", view.port, "TOPRIGHT", -8, -8)
	bp:SetFrameLevel(view:GetFrameLevel() + 22)
	bp:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	bp:SetBackdropColor(0.05, 0.04, 0.03, 0.88)
	bp:SetBackdropBorderColor(0.66, 0.49, 0.28, 0.85)
	bp:EnableMouse(true)
	bp:EnableMouseWheel(true)
	bp.title = Look:Font(bp:CreateFontString(nil, "OVERLAY"), 12)
	bp.title:SetPoint("TOPLEFT", 8, -6)
	bp.title:SetJustifyH("LEFT")
	bp.title:SetWordWrap(false)
	local hideBtn = CreateFrame("Button", nil, bp)
	hideBtn:SetSize(18, 18)
	hideBtn:SetPoint("TOPRIGHT", -4, -3)
	local hhl = hideBtn:CreateTexture(nil, "HIGHLIGHT")
	hhl:SetAllPoints()
	hhl:SetColorTexture(1, 0.85, 0.35, 0.22)
	local htxt = Look:Font(hideBtn:CreateFontString(nil, "OVERLAY"), 12)
	htxt:SetPoint("CENTER", 0, 1)
	htxt:SetText("|cffc8b896x|r")
	hideBtn:SetScript("OnClick", function()
		mod.db.dungeonBossList = false
		Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
		bossUI.UpdatePanel()
	end)
	hideBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Hide Bosses list", 1, 0.82, 0)
		GameTooltip:Show()
	end)
	hideBtn:SetScript("OnLeave", GameTooltip_Hide)
	local div = bp:CreateTexture(nil, "ARTWORK")
	div:SetPoint("TOPLEFT", 4, -23)
	div:SetPoint("TOPRIGHT", -4, -23)
	div:SetHeight(1)
	div:SetColorTexture(0.66, 0.49, 0.28, 0.50)
	local clip = CreateFrame("Frame", nil, bp)
	clip:SetPoint("TOPLEFT", 4, -26)
	clip:SetPoint("BOTTOMRIGHT", -4, 4)
	clip:SetClipsChildren(true)
	bp.clip = clip
	bp.content = CreateFrame("Frame", nil, clip)
	bp.content:SetPoint("TOPLEFT")
	bp.content:SetPoint("TOPRIGHT")
	bp.content:SetHeight(1)
	bp.thumb = clip:CreateTexture(nil, "OVERLAY")
	bp.thumb:SetWidth(3)
	bp.thumb:SetColorTexture(0.78, 0.62, 0.34, 0.85)
	bp.thumb:Hide()
	bp.foot = Look:Font(bp:CreateFontString(nil, "OVERLAY"), 10)
	bp.foot:SetPoint("BOTTOMLEFT", 8, 5)
	bp.foot:SetPoint("BOTTOMRIGHT", -8, 5)
	bp.foot:SetJustifyH("LEFT")
	bp.foot:SetWordWrap(false)
	bp.foot:SetText("|cff8a8274Positions not mapped yet|r")
	bp.foot:Hide()
	bp.rows = {}
	bp.scrollY = 0
	bp.contentH = 0
	bp:SetScript("OnMouseWheel", function(self, delta)
		self.scrollY = (self.scrollY or 0) - delta * 24
		bossUI.ApplyScroll(self)
	end)
	bp:Hide()
	view.bossPanel = bp
end

function bossUI.ShowRowTip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	if self.isRare then
		GameTooltip:AddLine((self.bossName or "") .. "  [Rare]", 0.48, 0.88, 1)
		if self.spotCount and self.spotCount > 1 then
			GameTooltip:AddLine(("Possible spawn locations: %d (rare - not guaranteed every run)"):format(self.spotCount), 0.72, 0.90, 1, true)
		else
			GameTooltip:AddLine("Rare spawn (not guaranteed every run)", 0.72, 0.90, 1, true)
		end
	else
		local head = self.bossNum and ("%d. %s"):format(self.bossNum, self.bossName or "") or (self.bossName or "")
		GameTooltip:AddLine(head, 1, 0.82, 0)
	end
	if self.bossNote and self.bossNote ~= "" then
		GameTooltip:AddLine(self.bossNote, 0.88, 0.86, 0.80, true)
	end
	if self.bossFloor then
		if self.onThisFloor then
			GameTooltip:AddLine("Pinned on this floor", 0.35, 1, 0.45)
		else
			local fName = view.FloorName and view.FloorName(self.bossFloor) or ("Floor " .. tostring(self.bossFloor))
			GameTooltip:AddLine(("On %s (Floor %d) - Click to view"):format(fName, self.bossFloor), 0.5, 0.85, 1)
		end
	else
		GameTooltip:AddLine("No floor pin position recorded yet", 0.7, 0.7, 0.7)
	end
	bossUI.AppendBossDrops(view and view.inst, self.bossName, 8)
	if NeedRoll() then
		GameTooltip:AddLine((self.bossFloor and not self.onThisFloor) and "Shift-click: loot in NeedRoll" or "Click: loot in NeedRoll", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

function bossUI.GetRow(bp, idx)
	local row = bp.rows[idx]
	if row then return row end
	row = CreateFrame("Button", nil, bp.content)
	row:SetHeight(20)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.84, 0.28, 0.16)
	row.selBg = row:CreateTexture(nil, "BACKGROUND")
	row.selBg:SetAllPoints()
	row.selBg:SetColorTexture(1, 0.84, 0.28, 0.22)
	row.selBg:Hide()
	row.num = Look:Font(row:CreateFontString(nil, "OVERLAY"), 11)
	row.num:SetPoint("LEFT", 4, 0)
	row.num:SetWidth(22)
	row.num:SetJustifyH("RIGHT")
	row.badge = Look:Font(row:CreateFontString(nil, "OVERLAY"), 10)
	row.badge:SetPoint("RIGHT", -6, 0)
	row.badge:SetJustifyH("RIGHT")
	row.badge:SetWordWrap(false)
	row.skull = row:CreateTexture(nil, "ARTWORK")
	row.skull:SetSize(12, 12)
	row.skull:SetPoint("RIGHT", -6, 0)
	if not Atlas(row.skull, "DungeonSkull") then row.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull") end
	row.skull:Hide()
	row.name = Look:Font(row:CreateFontString(nil, "OVERLAY"), 11)
	row.name:SetPoint("LEFT", row.num, "RIGHT", 5, 0)
	row.name:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row:SetScript("OnEnter", function(self)
		bossUI.hoverBoss = self.bossName
		bossUI.RefreshHighlight()
		bossUI.ShowRowTip(self)
	end)
	row:SetScript("OnLeave", function(self)
		if bossUI.hoverBoss == self.bossName then
			bossUI.hoverBoss = nil
			bossUI.RefreshHighlight()
		end
		if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
	end)
	row:SetScript("OnClick", function(self)
		if not self.bossName then return end
		local jumped = self.bossFloor and not self.onThisFloor
		mod.FocusDungeonBoss(self.bossName)
		if jumped and GameTooltip:GetOwner() == self then
			bossUI.ShowRowTip(self)
		end
		if NeedRoll() and (not jumped or IsShiftKeyDown()) then
			OpenNeedRoll(self.bossName, IsShiftKeyDown() and "map" or nil)
		end
	end)
	bp.rows[idx] = row
	return row
end

function bossUI.UpdatePanel()
	if not view then return end
	local inst = view.inst
	local btn = view.bossBtn
	local bp = view.bossPanel
	local names, bossNums = {}, {}
	if inst and mod.db.dungeonBosses then
		names, bossNums = BossNames(inst)
	end
	local count = #names
	if btn then
		if count > 0 then
			local open = mod.db.dungeonBossList == true
			btn.lbl:SetText((open and "|cffffd100Bosses (" or "|cffe8d8a8Bosses (") .. count .. ")|r")
			if btn.frame then
				if open then btn.frame:SetVertexColor(1, 0.96, 0.80, 1) else btn.frame:SetVertexColor(0.86, 0.80, 0.66, 0.90) end
			end
			btn:SetWidth(math.max(74, math.min(106, (btn.lbl:GetStringWidth() or 60) + 18)))
			btn:Show()
		else
			btn:Hide()
		end
	end
	bossUI.LayoutHeader()
	if not bp then return end
	if count == 0 or mod.db.dungeonBossList ~= true or not view:IsShown() or view.placer or view.markup then
		bp:Hide()
		return
	end
	local multiFloor = view.floors and #view.floors > 1
	local pinnedTotal, rareTotal = 0, 0
	for i, name in ipairs(names) do
		local entry, _, isRare, note = BossAt(inst, name)
		local spots = bossUI.Spots(entry)
		local spotCount = spots and #spots or 0
		if spotCount > 0 then pinnedTotal = pinnedTotal + 1 end
		if isRare then rareTotal = rareTotal + 1 end
		local onThisFloor = false
		if spots then
			for _, sp in ipairs(spots) do
				if sp[1] == view.floor then onThisFloor = true; break end
			end
		end
		local primaryFloor = onThisFloor and view.floor or (spots and spots[1][1]) or nil
		local row = bossUI.GetRow(bp, i)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", bp.content, "TOPLEFT", 0, -(i - 1) * 20)
		row:SetPoint("TOPRIGHT", bp.content, "TOPRIGHT", 0, -(i - 1) * 20)
		row:SetAlpha(1)
		row.selBg:Hide()
		row.skull:Hide()
		row.badge:SetText("")
		row.bossName = name
		row.bossIdx = i
		row.bossNum = bossNums[name]
		row.isRare = isRare
		row.spotCount = spotCount
		row.bossNote = note
		row.bossFloor = primaryFloor
		row.onThisFloor = onThisFloor
		if isRare then
			row.selBg:SetColorTexture(0.32, 0.78, 1, 0.22)
			row.num:SetText(onThisFloor and "|cff7fd4ffR|r" or "|cff4e86a8R|r")
			row.name:SetText((onThisFloor and "|cff9ce0ff" or "|cff6f94aa") .. name .. "|r")
		else
			row.selBg:SetColorTexture(1, 0.84, 0.28, 0.22)
			local numColor = onThisFloor and "|cffffd100" or "|cff9a8b68"
			row.num:SetText(("%s%d.|r"):format(numColor, bossNums[name] or i))
			local nameColor = (onThisFloor or not primaryFloor) and "|cfff2ead8" or "|cff9a9386"
			row.name:SetText(nameColor .. name .. "|r")
		end
		row.name:ClearAllPoints()
		row.name:SetPoint("LEFT", row.num, "RIGHT", 5, 0)
		if isRare and primaryFloor then
			local tag = (multiFloor and ("F" .. primaryFloor .. (spotCount > 1 and (" - " .. spotCount .. "x") or "")) or (spotCount > 1 and (spotCount .. " spots") or "Rare"))
			row.badge:SetText((onThisFloor and "|cff7fd4ff" or "|cff56829e") .. tag .. "|r")
			row.name:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
		elseif primaryFloor and multiFloor then
			row.badge:SetText((onThisFloor and "|cffffd100F" or "|cff7fd4ffF") .. primaryFloor .. "|r")
			row.name:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
		elseif onThisFloor then
			row.skull:Show()
			row.name:SetPoint("RIGHT", row.skull, "LEFT", -4, 0)
		else
			row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
		end
		row:Show()
	end
	for i = count + 1, #bp.rows do
		bp.rows[i].bossName = nil
		bp.rows[i]:Hide()
	end
	bp.title:SetText((rareTotal > 0 and "|cffffd100Bosses & Rares|r |cff998866(%d)|r" or "|cffffd100Bosses|r |cff998866(%d)|r"):format(count))
	bp.foot:SetShown(pinnedTotal == 0)
	bp.contentH = count * 20
	bp.content:SetHeight(math.max(1, bp.contentH))
	if bp.lastInst ~= inst then
		bp.lastInst = inst
		bp.scrollY = 0
	end
	bp:Show()
	bossUI.LayoutPanel()
	bossUI.RefreshHighlight()
end

function mod.HighlightDungeonBoss(bossName)
	bossUI.hoverBoss = bossName
	if view and view:IsShown() then bossUI.RefreshHighlight() end
end

function mod.RefreshBossTooltip()
	if not (view and view:IsShown() and GameTooltip:IsShown()) then return end
	local owner = GameTooltip:GetOwner()
	if not owner then return end
	for _, pin in ipairs(view.bossPins or {}) do
		if owner == pin and pin:IsShown() then
			PinTip(pin)
			return
		end
	end
	local bp = view.bossPanel
	if bp and bp:IsShown() then
		for _, row in ipairs(bp.rows or {}) do
			if owner == row and row:IsShown() then
				bossUI.ShowRowTip(row)
				return
			end
		end
	end
end

function mod.FocusDungeonBoss(bossName)
	if not (view and view:IsShown() and view.inst and bossName) then return false end
	bossUI.focusBoss = bossName
	local entry = BossAt(view.inst, bossName)
	local spots = bossUI.Spots(entry)
	if spots then
		local targetFloor = spots[1][1]
		for _, sp in ipairs(spots) do
			if sp[1] == view.floor then targetFloor = view.floor; break end
		end
		if targetFloor and targetFloor ~= view.floor and view.floors and view.floors[targetFloor] then
			bossUI.keepFocus = true
			ShowFloor(targetFloor)
			bossUI.keepFocus = nil
		end
		if view.zoom and view.zoom > 1.05 and view.page then
			local sx, sy, cnt = 0, 0, 0
			for _, sp in ipairs(spots) do
				if sp[1] == view.floor then
					sx, sy, cnt = sx + sp[2], sy + sp[3], cnt + 1
				end
			end
			local pw, ph = view.page:GetSize()
			if cnt > 0 and pw and pw > 0 and ph and ph > 0 then
				view.ox = (0.5 - sx / cnt) * pw
				view.oy = (sy / cnt - 0.5) * ph
				LayoutView(true)
			end
		end
	end
	bossUI.RefreshHighlight()
	return true
end

-- Pure side-effect-free lookup of a dungeon instance (and optional entrance pin) by instID or name.
function bossUI.FindInst(instID, dungName)
	local function ExactMatch(cand)
		if instID and instID ~= 0 and cand[1] == instID then return true end
		if dungName and Plain(cand[2]) == Plain(dungName) then return true end
		return false
	end
	for _, pin in ipairs(entrancePins) do
		for _, cand in ipairs(pin.instances or {}) do
			if ExactMatch(cand) then return cand, pin end
		end
	end
	local places = Places()
	for _, g in ipairs(places.instances or {}) do
		for _, cand in ipairs(g[4] or {}) do
			if ExactMatch(cand) then return cand, nil end
		end
	end
	for _, cand in ipairs(places.unplaced or {}) do
		if ExactMatch(cand) then return cand, nil end
	end
	if dungName then
		local want = Plain(dungName):gsub("[^%w]+", "")
		if want ~= "" then
			for _, pin in ipairs(entrancePins) do
				for _, cand in ipairs(pin.instances or {}) do
					local have = Plain(cand[2]):gsub("[^%w]+", "")
					if have ~= "" and (have == want or have:find(want, 1, true) or want:find(have, 1, true)) then
						return cand, pin
					end
				end
			end
			for _, g in ipairs(places.instances or {}) do
				for _, cand in ipairs(g[4] or {}) do
					local have = Plain(cand[2]):gsub("[^%w]+", "")
					if have ~= "" and (have == want or have:find(want, 1, true) or want:find(have, 1, true)) then
						return cand, nil
					end
				end
			end
		end
	end
	return nil, nil
end

-- Direct multi-wing-safe boss opener: opens the dungeon's floor map without popping a wing chooser, then focuses `bossName`.
function mod.OpenDungeonBoss(instID, dungName, bossName)
	if not MapsOn() then return false end
	local inst, pin = bossUI.FindInst(instID, dungName)
	if not inst then return false end
	if not (view and view:IsShown() and view.inst and ((inst[1] ~= 0 and view.inst[1] == inst[1]) or view.inst[2] == inst[2])) then
		GameTooltip:Hide()
		Open(inst, pin)
	end
	if view and view:IsShown() then
		if bossName then mod.FocusDungeonBoss(bossName) end
		return true
	end
	return false
end

-- Pure side-effect-free lookup of a dungeon's ordered boss & rare names for Dave's Map sidebar rows.
function mod.DungeonBossList(instID, dungName)
	local inst = bossUI.FindInst(instID, dungName)
	if not inst then return nil, nil end
	local _, src = FloorsOf(inst)
	local names = bossUI.BossNamesFor(inst, src)
	return names, inst[1]
end

-- Pure side-effect-free lookup of a boss/rare's pinned floor, floor count, rare flag, spot count, and note.
function mod.DungeonBossFloor(instID, dungName, bossName)
	if not bossName then return nil, 0, false, 0, nil end
	local inst = bossUI.FindInst(instID, dungName)
	if not inst then return nil, 0, false, 0, nil end
	local floors, src = FloorsOf(inst)
	local nFloors = floors and #floors or 0
	local entry, _, isRare, note = bossUI.ReadEntry(inst, bossName, src)
	local spots = bossUI.Spots(entry)
	local spotCount = spots and #spots or 0
	return spots and spots[1][1] or nil, nFloors, isRare, spotCount, note
end

-- the placer's bar, over the picture's top: the boss to place, Skip, Undo, Done
local function PlacerBar()
	if view.placerBar then return view.placerBar end
	local bar = CreateFrame("Frame", nil, view)
	bar:SetPoint("TOP", view.port, "TOP", 0, -6)
	bar:SetSize(660, 38)
	bar:SetFrameLevel(view:GetFrameLevel() + 30)
	bar:EnableMouse(true)
	Look:Panel(bar, { inset = 0, alpha = 0.92 })
	bar.text = Look:Font(bar:CreateFontString(nil, "OVERLAY"), 12)
	bar.text:SetPoint("LEFT", 10, 0)
	bar.text:SetPoint("RIGHT", -240, 0)
	bar.text:SetJustifyH("LEFT")
	bar.text:SetWordWrap(false)
	local function Btn(label, x, fn)
		local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
		b:SetSize(70, 24)
		b:SetPoint("RIGHT", x, 0)
		b:SetText(label)
		b:SetScript("OnClick", fn)
		return b
	end
	Btn(L["Done"], -8, function() mod:ToggleBossPlacer() end)
	Btn(L["Undo"], -82, function() mod.BossPlacerUndo() end)
	Btn(L["Skip"], -156, function() mod.BossPlacerNext() end)
	mod.padRoots[#mod.padRoots + 1] = bar      -- (the gamepad's cursor presses its buttons: Gamepad.lua)
	view.placerBar = bar
	return bar
end

local function PlacerShow()
	local pl = view.placer
	if not pl then return end
	local name = pl.names[pl.at]
	if name then
		local p = BossAt(view.inst, name)
		local where = p and (" |cff998866" .. L["(placed: click to move it)"] .. "|r") or ""
		PlacerBar().text:SetText(("|cffffd100%d / %d|r  %s%s  |cff998866%s|r"):format(pl.at, #pl.names, name, where,
			L["click where it is; right-click skips"]))
	else
		PlacerBar().text:SetText("|cffffd100" .. L["Every boss gone through: Done, or Undo"] .. "|r")
	end
	RedrawPins()
end

local function Placed(make)
	local key = InstKey(view.inst)
	mod.db.bossPlaced = mod.db.bossPlaced or {}
	if make and not mod.db.bossPlaced[key] then mod.db.bossPlaced[key] = {} end
	return mod.db.bossPlaced[key]
end

local function PlacerClick()
	local pl = view.placer
	local name = pl and pl.names[pl.at]
	local px, py = PageAt()
	if not (name and px) then return end
	local mine = Placed(true)
	pl.undo[#pl.undo + 1] = { at = pl.at, name = name, was = mine[name] }
	mine[name] = { view.floor, Round4(px), Round4(py) }
	pl.last = name
	Sound("U_CHAT_SCROLL_BUTTON")
	pl.at = pl.at + 1
	PlacerShow()
end

function mod.BossPlacerNext()
	local pl = view and view.placer
	if not pl or pl.at > #pl.names then return end
	pl.undo[#pl.undo + 1] = { at = pl.at, skip = true }
	pl.at = pl.at + 1
	PlacerShow()
end

function mod.BossPlacerUndo()
	local pl = view and view.placer
	local u = pl and tremove(pl.undo)
	if not u then return end
	if not u.skip then
		local mine = Placed(true)
		mine[u.name] = u.was
		if not next(mine) then mod.db.bossPlaced[InstKey(view.inst)] = nil end
	end
	pl.at, pl.last = u.at, nil
	PlacerShow()
end

-- /openmap bosses: the placer on the dungeon's map shown, or off
function mod:ToggleBossPlacer()
	if view and view.placer then
		view.placer = nil
		if view.placerBar then view.placerBar:Hide() end
		RedrawPins()
		if bossUI.UpdatePanel then bossUI.UpdatePanel() end
		ns:Print(L["Boss places saved in OpenMapDB (worldmap, bossPlaced) once you /reload or log out; tools/map-dungeons/bosses.py --import adds them to OpenMap's data."])
		return
	end
	if not (view and view:IsShown() and view.inst) or (view.floors[view.floor] or {}).blank then
		ns:Print(L["Open a dungeon's map first: /openmap bosses places its bosses on it."])
		return
	end
	EndMarkup(false)
	local names = BossNames(view.inst)
	if #names == 0 then
		ns:Print(L["The game lists no bosses for it."])
		return
	end
	if not mod.db.dungeonBosses then mod.db.dungeonBosses = true end   -- (placing them: shown)
	view.placer = { names = names, at = 1, undo = {} }
	view.hint:Hide()
	if view.bossPanel then view.bossPanel:Hide() end
	PlacerBar():Show()
	PlacerShow()
end
mod.BossPlacing = function() return view and view.placer and true or false end
mod.BossPlacerClick = function() PlacerClick() end

mod.RefreshDungeonCard = function() Recolour() RefreshCard() FillSide() mod.RedrawBossPins() if bossUI.UpdatePanel then bossUI.UpdatePanel() end end   -- (settings changed: mod:Refresh)
mod.RefreshSideQuests = function()
	if view and view:IsShown() and view.side and view.side:IsShown() and mod.db.dungeonTab == "quests" then
		FillSide()
	end
end

-- /openmap dungeons: which map each entrance opens (none: the client has no map of it by that name)
function mod:DungeonDiag()
	local found, total = 0, 0
	for _, g in ipairs(Places().instances or {}) do
		for _, inst in ipairs(g[4]) do
			total = total + 1
			local id = DungeonMap(inst)
			local info = id and C_Map.GetMapInfo(id)
			if id then found = found + 1 end
			ns:Print(("%s: %s"):format(S.InstanceName(inst), id and ("map %d, %s"):format(id, info and info.name or "?") or "|cffff6060no map|r"))
		end
	end
	ns:Print(("Dungeon maps: %d of %d entrances open one."):format(found, total))
end

--------------------------------------------------------------------------------
-- /openmap entrance <name>: where you stand, as the line for build.py's ENTRANCES
--------------------------------------------------------------------------------

function mod:Entrance(name)
	name = name and strtrim(name) or ""
	if name == "" then
		ns:Print(L["Stand in the portal and say which: /openmap entrance Dire Maul - East (the name as OpenMap lists it)."])
		return
	end
	local mapID = C_Map.GetBestMapForUnit and Safe.Call(C_Map.GetBestMapForUnit, "player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	local x, y = Safe.XY(pos)
	local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, pos)
	local wx, wy = Safe.XY(world)
	if not (x and ok and wx and S.Rect(mapID)) then
		ns:Print(L["Where you are isn't on the world map here."])
		return
	end
	-- the tables' order of the two (S.FromYards'): the one that lands where you are
	local u, v = mod.ToWorld(mapID, x, y)
	local best, bestD
	for _, try in ipairs({ { wx, wy }, { wy, wx } }) do
		local tu, tv = S.FromYards(cont, try[1], try[2])
		local dist = tu and ((tu - u) ^ 2 + (tv - v) ^ 2)
		if dist and (not bestD or dist < bestD) then best, bestD = try, dist end
	end
	if not best then
		ns:Print(L["Where you are isn't on the world map here."])
		return
	end
	local line = ('"%s": [(%d, %.1f, %.1f)],'):format(name, cont, best[1], best[2])
	tinsert(mod.db.entrances, line)
	ns:Print(line)
	ns:Print(L["Saved too (OpenMapDB: worldmap, entrances) once you /reload or log out."])
end

--------------------------------------------------------------------------------

-- (daves_map) Opens the dungeon map (or multi-wing chooser) matching a Map Genie Instance pin on Layer.lua,
-- matched first by world-map proximity to OpenMap's entrance pins, then by normalized name.
function mod.OpenInstanceNear(title, u, v, anchor)
	if not MapsOn() then return false end
	local best, bestD, matched
	if title then
		local want = Plain(title):gsub("[^%w]+", "")
		for _, pin in ipairs(entrancePins) do
			for _, inst in ipairs(pin.instances or {}) do
				local have = Plain(inst[2]):gsub("[^%w]+", "")
				if have == want then
					best, matched = pin, { inst }
					break
				end
			end
			if best then break end
		end
		if not best then
			for _, pin in ipairs(entrancePins) do
				local hits = {}
				for _, inst in ipairs(pin.instances or {}) do
					local have = Plain(inst[2]):gsub("[^%w]+", "")
					if have:find(want, 1, true) or want:find(have, 1, true) then
						hits[#hits + 1] = inst
					end
				end
				if #hits > 0 then
					best, matched = pin, hits
					break
				end
			end
		end
	end
	if not best and u and v then
		for _, pin in ipairs(entrancePins) do
			if pin.u and pin.v then
				local d2 = (pin.u - u) ^ 2 + (pin.v - v) ^ 2
				if d2 < 0.001 and (not bestD or d2 < bestD) then
					best, bestD = pin, d2
				end
			end
		end
	end
	if not best then return false end
	GameTooltip:Hide()
	local list = matched or best.instances
	if #list == 1 then
		Open(list[1], best)
	else
		Choose(best)
		if anchor and chooser then
			chooser:ClearAllPoints()
			chooser:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", 2, 2)
		end
	end
	return true
end

-- the dungeon you're in, as Places.lua has it (nil: not in one, or one it doesn't list); one with no
-- entrance yet (unplaced) too. (WoW Forever's own the tables had no mapID for were never found: The
-- Drowned City's map didn't open inside it; they have their instance's mapID now, #149)
local function InstanceHere()
	if not IsInInstance or not IsInInstance() then return end
	local instID = Safe.Value(select(8, GetInstanceInfo()))
	if not instID or instID == 0 then return end   -- (0: no instance, never one of the name-keyed)
	local places = Places()
	for _, g in ipairs(places.instances or {}) do
		for _, inst in ipairs(g[4]) do
			if inst[1] == instID then return inst end
		end
	end
	for _, inst in ipairs(places.unplaced or {}) do
		if inst[1] == instID then return inst end
	end
end

function mod.HasCurrentInstanceMap()
	return MapsOn() and InstanceHere() ~= nil
end

function mod.OpenCurrentInstance()
	local inst = InstanceHere()
	if not inst or not MapsOn() then return false end
	if view and view:IsShown() and view.inst and view.inst[1] == inst[1] then
		return true
	end
	local id = DungeonMap(inst)
	if not id then
		return OpenView(inst, nil) and true or false
	elseif not InCombatLockdown() then
		S.OpenMap(id)
		return true
	end
	return false
end

-- a dungeon you've been inside counts as found ("Only places you've found"), remembered per character:
-- an entrance whose ground the map's explored pieces don't cover (Blackfathom Deeps, under the Zoram
-- Strand's water; or reached by the group finder) never showed, done or not (#256)
local function NoteEntered()
	local inst = InstanceHere()
	if not inst or inst[1] == 0 or not mod.char then return end
	mod.char.entered = mod.char.entered or {}
	if mod.char.entered[inst[1]] then return end
	mod.char.entered[inst[1]] = true
	if S.RefreshFound then S.RefreshFound() end
end
-- the first dungeon you're in, once per account: where OpenMap's map of it can be turned off (players hunted
-- for the switch). Not where Dungeon Journal's or NeedRoll's map is left to them, nor with it off already
local function NoteDungeonMap()
	local inst = InstanceHere()
	if not inst or mod.db.dungeonMapNoted or not MapsOn() or mod.db.dungeonInside == false then return end
	if JournalName(inst) or NeedRoll() then return end
	mod.db.dungeonMapNoted = true
	ns:Print("Opening the map in a dungeon shows its dungeon map. To turn that off: /dmap options > Dungeon maps.")   -- (daves_map)
end
function S.Entered(pin)
	local seen = mod.char and mod.char.entered
	if not seen or not pin.instances then return false end
	for _, inst in ipairs(pin.instances) do
		if seen[inst[1]] then return true end
	end
	return false
end

-- The outdoor entrance is a useful world position while the player's coordinates are indoors.
function mod.InstanceEntranceView()
	local instanceID = Safe.Value(select(8, GetInstanceInfo()))
	if not instanceID or instanceID == 0 then return end
	for _, g in ipairs(Places().instances or {}) do
		for _, inst in ipairs(g[4]) do
			if inst[1] == instanceID then
				local u, v = S.EntranceAt(g)
				if not u then return end
				local chain = S.ChainAt(u, v)
				local zone = chain[#chain]
				return u, v, math.min(mod.FitZoom(zone), mod.db.maxZoom or math.huge)
			end
		end
	end
end

-- The dungeon you're in, kept warm: the game lets go of a closed map's files, so every opening of its
-- map read each floor's 12 tiles again (the floor shown and the Floors tab's pictures of every floor:
-- 84 files in Shadowfang Keep), a second or two each time. Inside a dungeon its floors' files are
-- drawn on a frame that stays shown, a pixel across at almost no alpha (as Extras.lua keeps the world
-- map's art), a few a frame so going in doesn't hitch; let go on the way out. /openmap warm: off too
local HOLD_STEP = 6             -- files set a frame
local holdFrame, holdTex, holdFiles, holdNext = nil, {}, {}, 1
local function HoldStep(self)
	local last = math.min(#holdFiles, holdNext + HOLD_STEP - 1)
	for i = holdNext, last do
		local t = holdTex[i]
		if not t then
			t = self:CreateTexture(nil, "BACKGROUND")
			t:SetAllPoints(self)
			t:SetAlpha(0.01)
			t:SetBlendMode("ADD")         -- (added as black: stacked, they showed as a dot, as in #45)
			t:SetVertexColor(0, 0, 0)
			holdTex[i] = t
		end
		t:SetTexture(holdFiles[i])
		t:Show()
	end
	holdNext = last + 1
	if holdNext > #holdFiles then self:SetScript("OnUpdate", nil) end
end
function mod.HoldDungeonHere()
	local files = {}
	local inst = mod.db.keepWarm ~= false and MapsOn() and InstanceHere()
	local floors = inst and not DungeonMap(inst) and FloorsOf(inst)
	for _, f in ipairs(floors or {}) do
		for _, file in ipairs(f.tiles or {}) do files[#files + 1] = file end
	end
	if #files == 0 and not holdFrame then return end
	if not holdFrame then
		holdFrame = CreateFrame("Frame")
		holdFrame:SetFrameStrata("BACKGROUND")
		holdFrame:SetSize(1, 1)
		holdFrame:SetPoint("BOTTOMLEFT", 0, 0)
	end
	for i = #files + 1, #holdTex do holdTex[i]:SetTexture(nil) holdTex[i]:Hide() end
	holdFiles, holdNext = files, 1
	if #files == 0 then
		holdFrame:SetScript("OnUpdate", nil)
		holdFrame:Hide()
		return
	end
	holdFrame:Show()
	holdFrame:SetScript("OnUpdate", HoldStep)
end

function mod:SetupDungeons(worldMap)
	map, sc = worldMap, worldMap.ScrollContainer
	-- (the map before this one: the event comes before Blizzard resets the view, so ReturnView knows it)
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("MapCanvas.MapSet", function(_, mapID)
			if sc.mapID == mapID and mapID ~= shownMap then lastMap, shownMap = shownMap, mapID end
		end, mod)
	end
	hooksecurefunc(map, "OnMapChanged", function()
		-- (the stitched map's own switch underneath, a moment after the view stopped: it stays; it closed
		-- a dungeon's map clicked just after zooming in)
		if not (S.Switching and S.Switching()) then
			if chooser then chooser:Hide() end
			if view and view:IsShown() then view:Hide() end   -- (another map put up: the quest log, the dropdown)
		end
		RefreshCard()
	end)
	-- the quest log opened or closed over a dungeon's map: the side panel into it (its tab picked) or out
	local function Redock(pick)
		if not (view and view:IsShown()) then return end
		if pick then
			-- (opened from one of the tabs: that one, kept; else the tab last picked)
			view.dockTab = view.wantTab or view.dockTab or "quests"
		end
		Dock()
		FillSide()
	end
	if map.QuestLog then
		map.QuestLog:HookScript("OnShow", function() Redock(true) end)
		map.QuestLog:HookScript("OnHide", function() Redock(false) end)
	end
	for _, method in ipairs({ "Maximize", "Minimize" }) do
		if map[method] then hooksecurefunc(map, method, function() C_Timer.After(0, function() Redock(false) end) end) end
	end
	map:HookScript("OnShow", RefreshCard)
	-- the map opened inside a dungeon the client has no map of (WoW Forever: none of them): its own
	-- map, as its entrance would open it, not the world with no one on it
	map:HookScript("OnShow", function()
		-- (shown again a moment after it was hidden: another addon laying the window out again with a
		-- hide and a show (ClassicUI Forever's World map does), not the map opened: it stays as it was,
		-- the dungeon's view back if it was up, the world if you'd gone back to it, never forced back in)
		if hiddenAt and GetTime() - hiddenAt < 0.25 then
			local was = hiddenWith
			hiddenAt, hiddenWith = nil, nil
			if was and MapsOn() and not (view and view:IsShown()) then
				OpenView(was[1], was[2] and { u = was[2], v = was[3] } or nil)
				if was[4] and was[4] ~= view.floor then ShowFloor(was[4], true) end
			end
			return
		end
		C_Timer.After(0.1, function()
			if not map:IsShown() or (view and view:IsShown()) then return end
			-- on a map off the stitched world (Zephras Isle): its own map, as its airship opens it, not
			-- the world with no one on it
			local here = Safe.Call(C_Map.GetBestMapForUnit, "player")
			for _ = 1, 8 do
				local info = here and C_Map.GetMapInfo(here)
				if not info then break end
				for _, awayID in pairs(S.AWAY_MAP or {}) do
					if here == awayID then
						if map:GetMapID() ~= awayID then mod.OpenAwayMap(awayID) end
						return
					end
				end
				here = info.parentMapID
			end
			local inst = InstanceHere()
			if not inst or not MapsOn() or mod.db.dungeonInside == false then return end   -- (Dungeon maps inside dungeons)
			-- (Dungeon Journal shows its own map of the dungeon you're in, its bosses on it: OpenMap's isn't put
			-- over it as the map opens there, #302. An entrance clicked on the world map still opens OpenMap's)
			if JournalName(inst) or NeedRoll() then return end   -- (and NeedRoll's, its own map in dungeons: #267)
			local id = DungeonMap(inst)
			if not id then OpenView(inst, nil) elseif map:GetMapID() ~= id and not InCombatLockdown() then S.OpenMap(id) end
		end)
	end)
	map:HookScript("OnHide", function()
		hiddenAt, hiddenWith = GetTime(), view and view:IsShown() and { view.inst, view.fromU, view.fromV, view.floor } or nil
		returnTo, shownMap, lastMap, portalCard = nil, nil, nil, nil
		bossUI.hoverBoss, bossUI.focusBoss = nil, nil
		if chooser then chooser:Hide() end
		if view then
			if view.sideTabs then view.sideTabs:Hide() end
			view:Hide()
		end
		RefreshCard()                               -- (the map's gone: the card too, and other addons told)
	end)
	-- the wheel past all the way out on a dungeon's map: back to the world
	sc:HookScript("OnMouseWheel", function(_, delta)
		if delta < 0 and not mod.IsStitched() and IsDungeonMap(map:GetMapID()) and sc:IsAtMinZoom() and not sc:IsZoomingOut() then Back() end
	end)
	-- (a resize: the card's height once the drag's frame is done, not on every size change in it)
	local sizing = false
	sc:HookScript("OnSizeChanged", function()
		if sizing or not (card and card:IsShown()) then return end
		sizing = true
		C_Timer.After(0, function() sizing = false RefreshCard() end)
	end)
	local events = {}
	ns.RegisterEvent(events, "PLAYER_LEVEL_UP", function()
		C_Timer.After(0, function() Recolour() RefreshCard() end)   -- (UnitLevel catches up after the event)
	end)
	-- (into a dungeon or out: its floors held, or let go; a moment after the loading screen)
	local function Rehold() C_Timer.After(2, function() mod.HoldDungeonHere() NoteEntered() NoteDungeonMap() end) end
	ns.RegisterEvent(events, "PLAYER_ENTERING_WORLD", Rehold)
	ns.RegisterEvent(events, "ZONE_CHANGED_NEW_AREA", Rehold)
	Rehold()                                      -- (set up already inside one)
	ns.RegisterEvent(events, "QUEST_TURNED_IN", function() if card and card:IsShown() then C_Timer.After(0.5, RefreshCard) end end)
end
