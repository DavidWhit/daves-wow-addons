-- daves_map / PanelData.lua
-- Pure view-model & virtualized item builders for Dave's Map (`Layers`, `Zone`, `Dungeon`, and `Search`).
--
-- Zero frame creation or widget mutation: transforms QuestieDB Forever data (`ns.DATA`) and domain queries
-- (`Quests.lua`, `Focus.lua`) into variable-height row descriptors in `ns.PanelUI.items`.

local _, ns = ...

local ui = ns.PanelUI
local Shorten, StripCodes = ns.Shorten, ns.StripCodes
local MAX_RESULTS = ns.PANEL_CONST.MAX_RESULTS

local ZONE_SECTIONS = {
	{ key = "avail", title = "Available Quests" },
	{ key = "locked", title = "Locked (Needs Chain)" },
	{ key = "done", title = "Completed" },
}

local STATE_ORDER = { ready = 1, log = 2, avail = 3, locked = 4, done = 5 }

local ROW_HEIGHTS = {
	zsec = 25,
	qcols = 22,
	lgroup = 25,
	head = 25,
	cat = 26,
	setting_check = 26,
	reward = 24,
	cstep = 26,
	quest = 28,
	dung_open = 34,
	poi = 34,
	result = 34,
	note = 38,
}

local FACTION_ROWS = {
	{ idx = 1, label = "Alliance Quests & NPCs", hex = "ff669eff" },
	{ idx = 2, label = "Horde Quests & NPCs", hex = "ffff5959" },
	{ idx = 3, label = "Neutral Quests & NPCs", hex = "ffffd133" },
}

---------------------------------------------------------------------------
-- Formatting, Pin Metadata & Layer Group Helpers
---------------------------------------------------------------------------
local function DiffHex(lvl)
	if not lvl or lvl <= 0 then return "ffd2b48c" end
	local dc = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
	if not dc then return "ffd2b48c" end
	return ("ff%02x%02x%02x"):format(math.floor(dc.r * 255 + .5), math.floor(dc.g * 255 + .5), math.floor(dc.b * 255 + .5))
end
ns.DiffHex = DiffHex

local function PinMeta(i)
	local m = ui.metaCache[i]
	if m then return m end
	m = { start = nil, role = nil, drops = nil, spawns = nil, summary = nil }
	local raw = ns.DATA.text[i] or ""
	if raw ~= "" then
		for line in raw:gmatch("[^\n]+") do
			local clean = StripCodes(line)
			local st = clean:match("^Start:%s*(.+)$")
			local rl = clean:match("^Role:%s*(.+)$")
			local dr = clean:match("^Drops:%s*(.+)$")
			local sp = clean:match("^Spawns in area:%s*(.+)$") or clean:match("^Locations:%s*(.+)$")
			local ins = clean:match("^Instance:%s*(.+)$")
			if st then m.start = st
			elseif rl then m.role = rl
			elseif dr then m.drops = dr
			elseif sp then m.spawns = sp
			elseif ins and not m.role then m.role = "Inside " .. ins
			elseif not clean:match("^Level:") and not clean:match("^In:") and not m.summary then
				m.summary = clean
			end
		end
	end
	ui.metaCache[i] = m
	return m
end

local function QuestSubtitle(i, state, blocker, viewZone)
	local D = ns.DATA
	local m = PinMeta(i)
	local e = D.endp[i]
	local endName = e ~= 0 and D.title[e] or nil
	local endZone = e ~= 0 and ns.ZoneName(e) or nil
	local myZone = ns.ZoneName(i)
	local startTxt = m.start
	if startTxt and viewZone and myZone and myZone ~= viewZone then
		startTxt = startTxt .. " (" .. myZone .. ")"
	end
	local route
	if startTxt and endName and m.start ~= endName then
		route = startTxt .. " -> " .. endName
		if endZone and endZone ~= myZone then route = route .. " (" .. endZone .. ")" end
	elseif endName and endName ~= m.start then
		route = "-> " .. endName .. ((endZone and endZone ~= myZone) and (" (" .. endZone .. ")") or "")
	elseif startTxt then
		route = startTxt
	end
	if state == "locked" and blocker and D.title[blocker] ~= D.title[i] then
		local req = "Needs: " .. D.title[blocker]
		return Shorten(route and (req .. "  -  " .. route) or req)
	elseif route and m.summary then
		return Shorten(route .. "  -  " .. m.summary)
	end
	return Shorten(route or m.summary or m.role or "")
end

local function NonQuestSubtitle(i)
	local D = ns.DATA
	local m = PinMeta(i)
	local icon = D.cats[D.cat[i]].icon
	if icon == "rare" then
		local parts = {}
		if D.lvl[i] > 0 then parts[#parts + 1] = "Lv " .. D.lvl[i] end
		if m.drops then parts[#parts + 1] = "Drops: " .. m.drops elseif m.role then parts[#parts + 1] = m.role end
		return Shorten(table.concat(parts, "  -  "))
	elseif icon == "quest_objective" then
		local parts = {}
		if D.lvl[i] > 0 then parts[#parts + 1] = "Lv " .. D.lvl[i] end
		if m.spawns then parts[#parts + 1] = m.spawns .. " spawns"
		elseif m.role then parts[#parts + 1] = m.role
		else parts[#parts + 1] = "Quest target" end
		return Shorten(table.concat(parts, "  -  "))
	end
	return Shorten(m.role or m.drops or m.summary or D.cats[D.cat[i]].title)
end

function ns.LayerGroupState(gi)
	local D = ns.DATA
	local on, off = 0, 0
	for _, ci in ipairs(D.groups[gi].cats) do
		local cat = D.cats[ci]
		if ns.IsCategoryToggleableInLayers(cat) then
			if ns.IsLayerCatOn(cat.id) then on = on + 1 else off = off + 1 end
		end
	end
	return on, off, on + off
end

function ns.ActiveOptionalLayerCount()
	local D = ns.DATA
	if not (D and ns.db and ns.db.layerOn) then return 0, 0 end
	local count, total = 0, 0
	for _, cat in ipairs(D.cats) do
		if ns.IsCategoryToggleableInLayers(cat) then
			total = total + 1
			if ns.IsLayerCatOn(cat.id) then count = count + 1 end
		end
	end
	return count, total
end

local function IsHere(i)
	local map = ns.CurrentMap()
	return (map and ns.PinsOnMap(map).x[i] ~= nil) == true
end
ns.IsPinOnCurrentMap = IsHere

function ns.FormatPinTitle(i, selected)
	local D = ns.DATA
	local lvl = D.lvl[i]
	local prefix = (lvl and lvl > 0) and ("|c%s[%d]|r "):format(DiffHex(lvl), lvl) or ""
	local name = D.title[i]
	if selected then
		return prefix .. "|cffffd200" .. name .. "|r"
	end
	return prefix .. name
end

function ns.StateBadge(state, here, i)
	if state == "done" then return "|cff6d8f74Done|r" end
	local xpTxt = ns.PinXP and ns.FormatXP and ns.FormatXP(ns.PinXP(i)) or nil
	if state == "ready" then
		return xpTxt and ("|cffffd200Ready|r |cffe8d8a8" .. xpTxt .. "|r") or "|cffffd200Ready|r"
	elseif state == "log" then
		return xpTxt and ("|cff7fd4ffLog|r |cffe8d8a8" .. xpTxt .. "|r") or "|cff7fd4ffIn Log|r"
	elseif state == "locked" then
		return xpTxt and ("|cff888888Locked|r |cffaaaaaa" .. xpTxt .. "|r")
			or (here and "|cff888888Locked|r" or ("|cff777777" .. (ns.ZoneName(i) or "Locked") .. "|r"))
	end
	if xpTxt then return "|cffe8d8a8" .. xpTxt .. "|r" end
	return here and "|cff59ff73on map|r" or (ns.ZoneName(i) or "")
end

---------------------------------------------------------------------------
-- Shared Quest, Chain & Bottom-of-Quest Reward Row Emitter
---------------------------------------------------------------------------
function ns.ToggleQuestSort(mode)
	if not ns.db then return end
	if mode ~= "lvl" and mode ~= "xp" and mode ~= "name" and mode ~= "starter" then
		mode = "lvl"
	end
	if ns.db.questSort == mode then
		ns.db.questSortAsc = not (ns.db.questSortAsc == true)
	else
		ns.db.questSort = mode
		ns.db.questSortAsc = (mode == "lvl" or mode == "name" or mode == "starter")
	end
	if ns.Sound then ns.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON") end
	if ns.OnLayerChanged then ns.OnLayerChanged() end
end

local function StarterInfo(pin)
	local m = PinMeta(pin)
	local z = ns.ZoneName(pin)
	return (m and m.start) or z or nil, z
end

local function FormatLvlCell(lvl)
	if lvl and lvl > 0 then
		return ("|c%s%d|r"):format(DiffHex(lvl), lvl)
	end
	return "|cff666666-|r"
end

local function MakeQuestEntry(pin, _viewZone, allowAutoExpand)
	local D = ns.DATA
	local ch = ns.ChainFor(pin)
	if ch and #ch.steps > 1 then
		local starter = ch.steps[1]
		local activePin, _, inLogPin, allDone = ns.ChainProgress(ch, starter)
		local doneCnt = 0
		for _, s in ipairs(ch.steps) do
			if ns.PinDone(s) then doneCnt = doneCnt + 1 end
		end
		local state
		if allDone then
			state = "done"
		elseif inLogPin then
			state = ns.PinQuestState(inLogPin)
		else
			state = ns.PinQuestState(activePin)
		end
		local worth = ns.ChainWorth(starter, ch)
		local autoExp = (allowAutoExpand ~= false) and (inLogPin ~= nil)
		local expanded = ns.IsChainExpanded(starter, autoExp)
		local dispLvl = D.lvl[starter] ~= 0 and D.lvl[starter] or (D.lvl[activePin] ~= 0 and D.lvl[activePin] or 0)
		local xpVal = (not allDone and worth and worth.xp) or 0
		local xpFmt = (not allDone and worth) and ns.FormatXP(worth.xp, worth.exactXP) or nil
		local xpColTxt
		if allDone then
			xpColTxt = "|cff6d8f74Done|r"
		else
			if xpFmt then
				xpColTxt = "|cffe8d8a8" .. xpFmt .. "|r"
			elseif state == "ready" then
				xpColTxt = "|cffffd200Ready|r"
			elseif state == "log" then
				xpColTxt = "|cff7fd4ffIn Log|r"
			else
				xpColTxt = "|cff666666-|r"
			end
		end
		local starterName, starterZone = StarterInfo(starter)
		return {
			pin = starter,
			sortLvl = dispLvl > 0 and dispLvl or 999,
			sortXP = xpVal,
			starterName = starterName,
			starterZone = starterZone,
			lvlTxt = FormatLvlCell(dispLvl),
			xpColTxt = xpColTxt,
			state = state,
			hasChain = true,
			chainSteps = #ch.steps,
			chainDone = doneCnt,
			chain = ch,
			activePin = activePin,
			inLogPin = inLogPin,
			allDone = allDone,
			expanded = expanded,
			worth = worth,
		}
	end
	local st = ns.PinQuestState(pin)
	local dispLvl = D.lvl[pin] or 0
	local qxp, qex = 0, true
	if ns.PinXP then qxp, qex = ns.PinXP(pin) end
	local xpVal = (st ~= "done" and qxp) or 0
	local xpFmt = (st ~= "done" and ns.FormatXP) and ns.FormatXP(qxp, qex) or nil
	local xpColTxt
	if st == "done" then
		xpColTxt = "|cff6d8f74Done|r"
	elseif xpFmt then
		xpColTxt = "|cffe8d8a8" .. xpFmt .. "|r"
	elseif st == "ready" then
		xpColTxt = "|cffffd200Ready|r"
	elseif st == "log" then
		xpColTxt = "|cff7fd4ffIn Log|r"
	else
		xpColTxt = "|cff666666-|r"
	end
	local starterName, starterZone = StarterInfo(pin)
	return {
		pin = pin,
		sortLvl = dispLvl > 0 and dispLvl or 999,
		sortXP = xpVal,
		starterName = starterName,
		starterZone = starterZone,
		lvlTxt = FormatLvlCell(dispLvl),
		xpColTxt = xpColTxt,
		state = st,
		hasChain = false,
		activePin = pin,
	}
end

local function AppendRewardsForQuest(out, questPin, indent, dim, stepNum, seen)
	local rews = ns.PinRewards and ns.PinRewards(questPin) or nil
	if not (rews and #rews > 0) then return end
	for k = 1, #rews do
		local iid = rews[k]
		if not (seen and seen[iid]) then
			if seen then seen[iid] = true end
			out[#out + 1] = {
				kind = "reward",
				itemID = iid,
				questPin = questPin,
				indent = indent or 1,
				dim = dim == true,
				stepNum = stepNum,
			}
		end
	end
end

local function EmitQuestEntry(out, entry)
	local D = ns.DATA
	if entry.hasChain then
		local ch = entry.chain
		out[#out + 1] = {
			kind = "quest",
			i = entry.pin,
			activePin = entry.activePin,
			starterNavPin = entry.pin,
			starterName = entry.starterName,
			starterZone = entry.starterZone,
			state = entry.state,
			hasChain = true,
			chainSteps = entry.chainSteps or #ch.steps,
			chainDone = entry.chainDone or 0,
			chainSet = ch.set,
			expanded = entry.expanded,
			lvlTxt = entry.lvlTxt,
			xpColTxt = entry.xpColTxt,
		}
		if entry.expanded then
			for n, stepPin in ipairs(ch.steps) do
				local sst = ns.PinQuestState(stepPin)
				local isDone = sst == "done"
				local isCurrent = (not entry.allDone) and (stepPin == entry.activePin)
				local sxp, sexact = ns.PinXP(stepPin)
				local sName, sZone = StarterInfo(stepPin)
				local sLvl = D and D.lvl[stepPin] or 0
				local xpFmt = (not isDone) and ns.FormatXP(sxp, sexact) or nil
				local stepXP
				if isDone then
					stepXP = "|cff6d8f74Done|r"
				elseif xpFmt then
					stepXP = "|cffe8d8a8" .. xpFmt .. "|r"
				elseif sst == "ready" then
					stepXP = "|cffffd200Ready|r"
				elseif sst == "log" then
					stepXP = "|cff7fd4ffIn Log|r"
				else
					stepXP = "|cff666666-|r"
				end
				out[#out + 1] = {
					kind = "cstep",
					i = stepPin,
					starterPin = entry.pin,
					starterNavPin = stepPin,
					starterName = sName,
					starterZone = sZone,
					lvlTxt = FormatLvlCell(sLvl),
					n = n,
					total = #ch.steps,
					state = sst,
					isDone = isDone,
					isCurrent = isCurrent,
					xpColTxt = stepXP,
				}
				AppendRewardsForQuest(out, stepPin, 2, isDone, nil)
			end
		else
			-- Collapsed chain: show ALL item rewards from every step at the bottom (deduped by itemID).
			local seenRew = {}
			for n, stepPin in ipairs(ch.steps) do
				AppendRewardsForQuest(out, stepPin, 1, ns.PinDone(stepPin), n, seenRew)
			end
		end
	else
		out[#out + 1] = {
			kind = "quest",
			i = entry.pin,
			activePin = entry.pin,
			starterNavPin = entry.pin,
			starterName = entry.starterName,
			starterZone = entry.starterZone,
			state = entry.state,
			here = IsHere(entry.pin),
			lvlTxt = entry.lvlTxt,
			xpColTxt = entry.xpColTxt,
		}
		AppendRewardsForQuest(out, entry.pin, 1, entry.state == "done", nil)
	end
end

local function CompareLevel(la, lb, asc)
	if la == lb then return nil end
	-- Always keep unknown level (999) at the bottom regardless of sort direction.
	if la >= 999 then return false end
	if lb >= 999 then return true end
	if asc then return la < lb else return la > lb end
end

local function SortQuestEntries(list)
	local D = ns.DATA
	local mode = (ns.db and ns.db.questSort) or "lvl"
	if mode ~= "lvl" and mode ~= "xp" and mode ~= "name" and mode ~= "starter" then
		mode = "lvl"
	end
	local asc = not (ns.db and ns.db.questSortAsc == false)
	table.sort(list, function(a, b)
		-- Keep completed quests below uncompleted ones (and Ready above In Log inside active).
		local doneA, doneB = a.state == "done", b.state == "done"
		if doneA ~= doneB then return not doneA end
		if (a.state == "ready" or a.state == "log") and (b.state == "ready" or b.state == "log") then
			local oa, ob = STATE_ORDER[a.state] or 9, STATE_ORDER[b.state] or 9
			if oa ~= ob then return oa < ob end
		end
		if mode == "xp" then
			local xa, xb = a.sortXP or 0, b.sortXP or 0
			if xa ~= xb then return asc and (xa < xb) or (xa > xb) end
			local lc = CompareLevel(a.sortLvl or 999, b.sortLvl or 999, true)
			if lc ~= nil then return lc end
		elseif mode == "name" then
			local ta, tb = (D.title[a.pin] or ""):lower(), (D.title[b.pin] or ""):lower()
			if ta ~= tb then return asc and (ta < tb) or (ta > tb) end
			local lc = CompareLevel(a.sortLvl or 999, b.sortLvl or 999, true)
			if lc ~= nil then return lc end
		elseif mode == "starter" then
			local sa, sb = (a.starterName or ""):lower(), (b.starterName or ""):lower()
			if sa ~= sb then return asc and (sa < sb) or (sa > sb) end
			local lc = CompareLevel(a.sortLvl or 999, b.sortLvl or 999, true)
			if lc ~= nil then return lc end
		else
			-- "lvl": Level (asc/desc), then deterministic alphabetical title & pin ID
			-- (never tie-break by volatile liveXP so server XP preloads never jump rows around)
			local lc = CompareLevel(a.sortLvl or 999, b.sortLvl or 999, asc)
			if lc ~= nil then return lc end
		end
		local ta, tb = (D.title[a.pin] or ""):lower(), (D.title[b.pin] or ""):lower()
		if ta ~= tb then return ta < tb end
		return a.pin < b.pin
	end)
end

---------------------------------------------------------------------------
-- Tab Builders (`Layers`, `Zone`, `Dungeon`, `Search`)
---------------------------------------------------------------------------
local function BuildLayersItems()
	local D, db = ns.DATA, ns.db
	local activeCount, totalCount = ns.ActiveOptionalLayerCount()
	local allOn = totalCount > 0 and activeCount == totalCount
	ui.items[#ui.items + 1] = {
		kind = "head",
		title = "Optional Map Icon Layers",
		right = "",
		checked = allOn,
		action = "toggle_all_layers",
	}
	for gi, g in ipairs(D.groups) do
		local _, off, total = ns.LayerGroupState(gi)
		if total > 0 then
			ui.items[#ui.items + 1] = { kind = "lgroup", gi = gi, allOn = off == 0 }
			for _, ci in ipairs(g.cats) do
				if ns.IsCategoryToggleableInLayers(D.cats[ci]) then
					ui.items[#ui.items + 1] = { kind = "cat", ci = ci }
				end
			end
		end
	end

	ui.items[#ui.items + 1] = { kind = "head", title = "Quest & NPC Factions", right = "" }
	for _, fr in ipairs(FACTION_ROWS) do
		local k = fr.idx
		ui.items[#ui.items + 1] = {
			kind = "setting_check",
			skey = "fac_" .. k,
			label = "|c" .. fr.hex .. fr.label .. "|r",
			tipTitle = StripCodes(fr.label),
			tip = "Include quests and NPCs for this faction on Zone / Dungeon reference layers and lists.",
			checked = (ns.factions and ns.factions[k]) == true,
		}
	end

	ui.items[#ui.items + 1] = { kind = "head", title = "Objective Tracker & Quests", right = "" }
	ui.items[#ui.items + 1] = {
		kind = "setting_check",
		skey = "trackMyZone",
		label = "Track only my zone's quests",
		tipTitle = "Track only my zone's quests",
		tip = "The objective tracker follows the quests in your log for the zone you're in; click the pin beside any tracked quest to keep it tracked across zones.",
		checked = db.trackMyZone ~= false,
	}
	ui.items[#ui.items + 1] = {
		kind = "setting_check",
		skey = "focusQuest",
		label = "Click a tracked quest to focus it",
		tipTitle = "Click a tracked quest to focus it",
		tip = "Clicking a quest in the objective tracker, quest log, or Ready to Turn In focuses the map on that quest's objectives and turn-in (and shows its chain in Dave's Map).",
		checked = db.focusQuest ~= false,
	}
	ui.items[#ui.items + 1] = {
		kind = "setting_check",
		skey = "hideCompleted",
		label = "Hide completed quests",
		tipTitle = "Hide completed quests",
		tip = "Hide completed quests from the Zone and Dungeon reference layers and lists.",
		checked = db.hideCompleted == true,
	}

	ui.items[#ui.items + 1] = { kind = "head", title = "Map Display", right = "" }
	ui.items[#ui.items + 1] = {
		kind = "setting_check",
		skey = "enabled",
		label = "Show the map layer",
		tipTitle = "Show the map layer",
		tip = "Draw tracked quest objectives, optional POI layers, and Zone/Dungeon reference markers on the world map (/dmap toggle).",
		checked = db.enabled ~= false,
	}
	ui.items[#ui.items + 1] = {
		kind = "setting_check",
		skey = "mapBanner",
		label = "Show zone & coordinates banner",
		tipTitle = "Show zone & coordinates banner",
		tip = "Show a compact pill at the top of the map canvas with the zone's name, difficulty-coloured level bracket, and cursor/player coordinates.",
		checked = db.mapBanner ~= false,
	}

	local stitch = ns.OM and ns.OM:GetModule("worldmap")
	if stitch and stitch.db and not ns.OpenMapOn() then
		ui.items[#ui.items + 1] = { kind = "head", title = "Seamless & Dungeon Maps", right = "" }
		ui.items[#ui.items + 1] = {
			kind = "setting_check",
			skey = "stitch_enabled",
			label = "Seamless world map",
			tipTitle = "Seamless world map",
			tip = "Every zone stitched into one continuous map (OpenMap): zoom smoothly from the whole world down to street level. Takes a /reload.",
			checked = stitch.db.enabled ~= false,
		}
		ui.items[#ui.items + 1] = {
			kind = "setting_check",
			skey = "stitch_dungeonMaps",
			label = "Dungeon & raid maps",
			tipTitle = "Dungeon & raid maps",
			tip = "OpenMap's multi-floor dungeon and raid maps, boss pins, and entrance portals.",
			checked = stitch.db.dungeonMaps ~= false,
		}
		ui.items[#ui.items + 1] = {
			kind = "setting_check",
			skey = "stitch_autoSwitch",
			label = "Load the zone in view",
			tipTitle = "Load the zone in view",
			tip = "Once the seamless map stops panning, load the zone underneath so quest areas, coordinates, and Zone/Dungeon lists follow.",
			checked = stitch.db.autoSwitch ~= false,
		}
		ui.items[#ui.items + 1] = {
			kind = "setting_check",
			skey = "stitch_openZoomed",
			label = "Open zoomed in on me",
			tipTitle = "Open zoomed in on me",
			tip = "Open the seamless map zoomed in on your character. Off: open to your whole zone.",
			checked = stitch.db.openZoomed ~= false,
		}
	end
end

local function BuildZoneItems()
	local D = ns.DATA
	local viewZ = (ns.ViewZoneMap and ns.ViewZoneMap()) or ns.CurrentMap()
	local zMap = (ns.ActiveZoneContext and ns.ActiveZoneContext()) or viewZ
	ui.zoneMap = zMap
	ui.zoneDone, ui.zoneTotal = 0, 0
	if not (D and zMap and ns.Calibrate()) then return end
	local zInfo = C_Map.GetMapInfo(zMap)
	local zName = zInfo and zInfo.name or nil
	local idx = ns.PinsOnMap(zMap).idx

	local dungQuestPins = {}
	local zoneDungs = D.dungeons and D.dungeons[zMap]
	if zoneDungs then
		for _, d in ipairs(zoneDungs) do
			for _, qi in ipairs(d.quests or {}) do dungQuestPins[qi] = true end
		end
	end

	local buckets = { active = {}, avail = {}, locked = {}, done = {} }
	local seenQuestId, seenStarter = {}, {}

	for _, i in ipairs(idx) do
		local icon = D.cats[D.cat[i]].icon
		if (icon == "quest" or icon == "repeatable") and ns.PassesPlayerFilter(i) then
			local q = D.qid[i]
			if not (q ~= 0 and seenQuestId[q]) then
				if q ~= 0 then seenQuestId[q] = true end
				local rawState = ns.PinQuestState(i)
				if icon == "quest" and not dungQuestPins[i] then
					ui.zoneTotal = ui.zoneTotal + 1
					if rawState == "done" then ui.zoneDone = ui.zoneDone + 1 end
				end
				if not dungQuestPins[i] then
					local entry = MakeQuestEntry(i, zName)
					if not seenStarter[entry.pin] then
						seenStarter[entry.pin] = true
						if entry.state == "ready" or entry.state == "log" then
							buckets.active[#buckets.active + 1] = entry
						elseif entry.state == "done" then
							if not ns.db.hideCompleted then
								buckets.done[#buckets.done + 1] = entry
							end
						elseif entry.state == "locked" then
							buckets.locked[#buckets.locked + 1] = entry
						else
							buckets.avail[#buckets.avail + 1] = entry
						end
					end
				end
			end
		end
	end

	SortQuestEntries(buckets.active)
	SortQuestEntries(buckets.avail)
	SortQuestEntries(buckets.locked)
	SortQuestEntries(buckets.done)

	local fold = ns.db.zoneFold or {}
	local function PushQuestSection(key, title, entries, defaultClosed)
		if #entries == 0 then return end
		local closed = fold[key]
		if closed == nil then closed = defaultClosed == true end
		ui.items[#ui.items + 1] = { kind = "zsec", key = key, title = title, n = tostring(#entries), closed = closed }
		if not closed then
			ui.items[#ui.items + 1] = { kind = "qcols" }
			for _, entry in ipairs(entries) do
				EmitQuestEntry(ui.items, entry, zName)
			end
		end
	end

	PushQuestSection("active", "In Log & Ready", buckets.active, false)
	for _, sec in ipairs(ZONE_SECTIONS) do
		PushQuestSection(sec.key, sec.title, buckets[sec.key], sec.key == "done")
	end

	if #ui.items == 0 then
		ui.items[1] = {
			kind = "note",
			title = "No zone quests matching filters",
			sub = "Pan to a questing zone or adjust Factions / Hide Completed in Base.",
		}
	end
end

local function BuildDungeonItems()
	local D = ns.DATA
	local viewZ = (ns.ViewZoneMap and ns.ViewZoneMap()) or ns.CurrentMap()
	local zMap = (ns.ActiveDungeonZone and ns.ActiveDungeonZone()) or viewZ
	ui.zoneMap = zMap
	if not (D and zMap and ns.Calibrate()) then return end
	local zInfo = C_Map.GetMapInfo(zMap)
	local zName = zInfo and zInfo.name or "this zone"
	local zoneDungs = D.dungeons and D.dungeons[zMap]
	if not (zoneDungs and #zoneDungs > 0) then
		ui.items[1] = {
			kind = "note",
			title = "No dungeons in " .. zName,
			sub = "Pan to a zone with a dungeon or raid, or search any dungeon above.",
		}
		return
	end

	local fold = ns.db.zoneFold or {}
	local multiDungs = #zoneDungs > 1
	for _, d in ipairs(zoneDungs) do
		local qentries = {}
		local seenQid, seenTitle, seenStarter = {}, {}, {}
		local dDone, dTotal, dRemXP, dExactXP = 0, 0, 0, true
		for _, qi in ipairs(d.quests or {}) do
			if ns.PassesPlayerFilter(qi) then
				local q = D.qid[qi]
				local tkey = D.title[qi] .. "\1" .. tostring(D.lvl[qi])
				if not ((q ~= 0 and seenQid[q]) or seenTitle[tkey]) then
					if q ~= 0 then seenQid[q] = true end
					seenTitle[tkey] = true
					local st = ns.PinQuestState(qi)
					dTotal = dTotal + 1
					if st == "done" then
						dDone = dDone + 1
					else
						local qxp, qex = ns.PinXP(qi)
						if qxp > 0 then
							dRemXP = dRemXP + qxp
							if not qex then dExactXP = false end
						end
					end
					local entry = MakeQuestEntry(qi, zName, false)
					if not seenStarter[entry.pin] then
						seenStarter[entry.pin] = true
						if entry.state ~= "done" or not ns.db.hideCompleted then
							qentries[#qentries + 1] = entry
						end
					end
				end
			end
		end
		SortQuestEntries(qentries)

		local mid = (d.lo and d.hi and d.lo > 0) and math.floor((d.lo + d.hi) / 2) or 0
		local range = (d.lo and d.lo > 0) and ((d.lo == d.hi) and tostring(d.lo) or (d.lo .. "-" .. d.hi)) or nil
		local lvlTag = range and (" |c%s[%s]|r"):format(DiffHex(mid), range) or ""
		local headTitle = (d.raid and "Raid: " or "Dungeon: ") .. d.name .. lvlTag
		local xpHeader = dRemXP > 0 and ns.FormatXP(dRemXP, dExactXP) or nil
		local rightTxt = dTotal > 0 and ("%d/%d"):format(dDone, dTotal) or "Map"
		if xpHeader then rightTxt = rightTxt .. " - " .. xpHeader end

		local secKey = "dung:" .. d.name
		local closed = fold[secKey]
		if closed == nil then closed = multiDungs end
		ui.items[#ui.items + 1] = { kind = "zsec", key = secKey, title = headTitle, n = rightTxt, closed = closed }
		if not closed then
			if d.pin and d.pin ~= 0 then
				local subParts = { "Open floor map & bosses" }
				if dTotal > 0 then
					local rem = dTotal - dDone
					subParts[#subParts + 1] = rem > 0 and ("%d/%d quests left"):format(rem, dTotal) or ("%d/%d done"):format(dDone, dTotal)
				end
				if xpHeader then subParts[#subParts + 1] = "|cffe8d8a8" .. xpHeader .. "|r" end
				ui.items[#ui.items + 1] = {
					kind = "dung_open",
					i = d.pin,
					title = d.name,
					sub = table.concat(subParts, "  -  "),
				}
			end
			if #qentries > 0 then
				ui.items[#ui.items + 1] = { kind = "qcols" }
			end
			for _, entry in ipairs(qentries) do
				EmitQuestEntry(ui.items, entry, zName)
			end
		end
	end
end

local TRACKER_SECTIONS = {
	{ key = "focused", title = "Focused" },
	{ key = "ready", title = "Ready to Turn In" },
	{ key = "pinned", title = "Pinned" },
	{ key = "tracking", title = "Tracking" },
}

local function ResolveTrackerPin(q)
	local pin = ns.QuestPin and ns.QuestPin(q) or nil
	if not pin and ns.FindQuestPinsForTracker then
		local pins = ns.FindQuestPinsForTracker(q)
		pin = pins and pins[1] or nil
	end
	return pin
end

local function BuildTrackerItems()
	local D = ns.DATA
	if not (D and ns.Calibrate()) then return end
	local pinned = (ns.db and ns.db.pinned) or {}
	local focusOn = ns.db and ns.db.focusQuest ~= false
	local clickFocus = focusOn and ns.ClickFocus and ns.ClickFocus() or nil
	local uiFocus = focusOn and ns.TrackerFocusQuestID and ns.TrackerFocusQuestID() or nil
	local focusQ = (clickFocus and ns.QuestInLog(clickFocus)) and clickFocus
		or ((uiFocus and ns.QuestInLog(uiFocus)) and uiFocus or nil)

	local bucketQuests = { focused = {}, ready = {}, pinned = {}, tracking = {} }
	local seenQ = {}
	for idx = 1, ns.NumQuestLogEntries() do
		local info = ns.QuestInfo(idx)
		if info and not info.isHeader and not info.isHidden and info.questID and info.questID ~= 0 and not issecretvalue(info.questID) then
			local q = info.questID
			if not seenQ[q] then
				seenQ[q] = true
				if focusQ and q == focusQ then
					bucketQuests.focused[#bucketQuests.focused + 1] = q
				elseif ns.QuestReady(q) then
					bucketQuests.ready[#bucketQuests.ready + 1] = q
				elseif pinned[q] then
					bucketQuests.pinned[#bucketQuests.pinned + 1] = q
				elseif ns.QuestWatched(q) then
					bucketQuests.tracking[#bucketQuests.tracking + 1] = q
				end
			end
		end
	end

	-- Deduplicate chain starters in strict priority order (Focused -> Ready -> Pinned -> Tracking)
	-- so two active steps of the same branched chain never render duplicate chain blocks.
	local seenStarter = {}
	local fold = (ns.db and ns.db.zoneFold) or {}
	for _, sec in ipairs(TRACKER_SECTIONS) do
		local entries, noData = {}, {}
		for _, q in ipairs(bucketQuests[sec.key]) do
			local pin = ResolveTrackerPin(q)
			if pin then
				local entry = MakeQuestEntry(pin, nil, true)
				if entry and not seenStarter[entry.pin] then
					seenStarter[entry.pin] = true
					entries[#entries + 1] = entry
				end
			else
				noData[#noData + 1] = { q = q, title = (ns.QuestTitle and ns.QuestTitle(q)) or ("Quest #" .. tostring(q)) }
			end
		end
		local total = #entries + #noData
		if total > 0 then
			SortQuestEntries(entries)
			local fkey = "trk:" .. sec.key
			local closed = fold[fkey] == true
			ui.items[#ui.items + 1] = { kind = "zsec", key = fkey, title = sec.title, n = tostring(total), closed = closed }
			if not closed then
				if #entries > 0 then
					ui.items[#ui.items + 1] = { kind = "qcols" }
					for _, entry in ipairs(entries) do
						EmitQuestEntry(ui.items, entry)
					end
				end
				for _, nd in ipairs(noData) do
					ui.items[#ui.items + 1] = {
						kind = "note",
						title = "No map data for: " .. nd.title,
						sub = "QuestieDB Forever has no pin data for this quest yet.",
					}
				end
			end
		end
	end

	if #ui.items == 0 then
		ui.items[1] = {
			kind = "note",
			title = "No quests in tracker",
			sub = "Track, pin, or click a quest in the Objective Tracker to view its details, chain, and rewards here.",
		}
	end
end

function ns.BuildPanelItems()
	local D = ns.DATA
	if not D then return end
	if ui.lastKey and not ui.restoring then
		ui.scrollByKey[ui.lastKey] = ui.scrollPx
	end
	wipe(ui.items)
	ui.revealItemIdx = nil
	local tab = ns.db and ns.db.panelTab or "layers"
	local key
	if ui.found then
		local raw = ui.search and ui.search:GetText()
		local qtxt = (raw and not issecretvalue(raw) and raw or ""):lower():match("^%s*(.-)%s*$")
		key = "search:" .. qtxt
		local originMap = ui.searchOriginMap
		local originPins = originMap and ns.PinsOnMap(originMap) or nil
		local all = {}
		for _, i in ipairs(ui.found) do
			local icon = D.cats[D.cat[i]].icon
			local isQ = icon == "quest" or icon == "repeatable"
			local st, blk
			if isQ then st, blk = ns.PinQuestState(i) end
			all[#all + 1] = {
				kind = "result",
				i = i,
				isQuest = isQ,
				state = st,
				here = IsHere(i),
				atOrigin = (originPins and originPins.x[i] ~= nil) == true,
				sub = isQ and QuestSubtitle(i, st, blk) or NonQuestSubtitle(i),
			}
		end
		-- Sort by the frozen zone where the search began (not live CurrentMap) so clicking
		-- results in other zones never shifts or re-orders the list under your cursor.
		table.sort(all, function(a, b)
			if a.atOrigin ~= b.atOrigin then return a.atOrigin end
			local ta, tb = (D.title[a.i] or ""):lower(), (D.title[b.i] or ""):lower()
			if ta ~= tb then return ta < tb end
			return a.i < b.i
		end)
		for n = 1, math.min(#all, MAX_RESULTS) do
			local r = all[n]
			ui.items[#ui.items + 1] = r
			if r.isQuest then
				AppendRewardsForQuest(ui.items, r.i, 1, r.state == "done", nil)
			end
		end
	elseif tab == "tracker" then
		key = "tracker"
		BuildTrackerItems()
	elseif tab == "zone" then
		key = "zone:" .. tostring((ns.ActiveZoneContext and ns.ActiveZoneContext()) or (ns.ViewZoneMap and ns.ViewZoneMap()) or 0)
		BuildZoneItems()
	elseif tab == "dungeon" then
		key = "dungeon:" .. tostring((ns.ActiveDungeonZone and ns.ActiveDungeonZone()) or (ns.ViewZoneMap and ns.ViewZoneMap()) or 0)
		BuildDungeonItems()
	else
		key = "layers"
		BuildLayersItems()
	end

	local top = 0
	local wantPin = ui.revealPin
	local wantQid = (wantPin and D.qid[wantPin] ~= 0) and D.qid[wantPin] or nil
	local fallbackIdx, qidFallbackIdx = nil, nil
	for idx, item in ipairs(ui.items) do
		local h = ROW_HEIGHTS[item.kind] or 34
		item.h = h
		item.top = top
		top = top + h
		if wantPin then
			if item.kind == "cstep" and item.i == wantPin then
				ui.revealItemIdx = idx
			elseif item.kind == "quest" and (item.i == wantPin or item.activePin == wantPin) and not fallbackIdx then
				fallbackIdx = idx
			elseif wantQid and (item.kind == "cstep" or item.kind == "quest") and item.i and D.qid[item.i] == wantQid and not qidFallbackIdx then
				qidFallbackIdx = idx
			end
		end
	end
	ui.totalH = top
	if wantPin then
		ui.revealItemIdx = ui.revealItemIdx or fallbackIdx or qidFallbackIdx
		if ui.list and (ui.list:GetHeight() or 0) > 0 then
			ui.revealPin = nil
		end
	end

	if key ~= ui.lastKey then
		ui.scrollPx = ui.scrollByKey[key] or 0
		ui.lastKey = key
	end
end
