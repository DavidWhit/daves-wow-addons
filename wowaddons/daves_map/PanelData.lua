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

local STATE_ORDER = { ready = 1, log = 2, avail = 3, locked = 3, done = 4 }

local ROW_HEIGHTS = {
	zsec = 25,
	zsub = 23,
	qcols = 22,
	lgroup = 25,
	head = 25,
	cat = 26,
	setting_check = 26,
	reward = 24,
	cstep = 26,
	quest = 28,
	logquest = 28,
	dung_open = 34,
	boss = 24,
	boss_drop = 23,
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

local function MinimalInfo()
	return (ns.db and ns.db.minimalQuestInfo == true) == true
end

local function MakeQuestEntry(pin, _viewZone, allowAutoExpand, liveQid)
	local D = ns.DATA
	local ch = (not MinimalInfo()) and ns.ChainFor(pin) or nil
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
			liveQid = liveQid,
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
		liveQid = liveQid,
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

local function EmitQuestEntry(out, entry, showTrackCheck)
	local D = ns.DATA
	local wantCheck = showTrackCheck == true
	local inGroup = IsInGroup and IsInGroup()
	if entry.hasChain then
		local ch = entry.chain
		local headLogQ = entry.liveQid
			or (entry.inLogPin and ns.LogQuestIDForPin and ns.LogQuestIDForPin(entry.inLogPin))
			or (ns.LogQuestIDForPin and ns.LogQuestIDForPin(entry.pin))
		local headTrackQ = (wantCheck and headLogQ and ns.QuestInLog(headLogQ)) and headLogQ or nil
		local headGCnt, headGQid = nil, nil
		if not entry.expanded and inGroup and ns.GroupQuestCountForPin then
			local gCnt, gQid = ns.GroupQuestCountForPin(entry.inLogPin or entry.activePin, entry.liveQid)
			if gCnt == 0 then
				for _, s in ipairs(ch.steps) do
					local sc, sq = ns.GroupQuestCountForPin(s)
					if sc > gCnt then gCnt, gQid = sc, sq end
				end
			end
			if gCnt > 0 then headGCnt, headGQid = gCnt, gQid end
		end
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
			inLogQuestID = headLogQ,
			trackQuestID = headTrackQ,
			watched = headTrackQ and ns.QuestWatched(headTrackQ) or nil,
			groupCount = headGCnt,
			groupQuestID = headGQid,
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
				local stepLiveQ = (entry.liveQid and stepPin == entry.inLogPin) and entry.liveQid or nil
				local stepLogQ = stepLiveQ or (ns.LogQuestIDForPin and ns.LogQuestIDForPin(stepPin)) or nil
				local stepTrackQ = (wantCheck and stepLogQ and ns.QuestInLog(stepLogQ)) and stepLogQ or nil
				local stepGCnt, stepGQid = 0, nil
				if inGroup and ns.GroupQuestCountForPin then
					stepGCnt, stepGQid = ns.GroupQuestCountForPin(stepPin, stepLiveQ)
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
					inLogQuestID = stepLogQ,
					trackQuestID = stepTrackQ,
					watched = stepTrackQ and ns.QuestWatched(stepTrackQ) or nil,
					groupCount = stepGCnt > 0 and stepGCnt or nil,
					groupQuestID = stepGCnt > 0 and stepGQid or nil,
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
		local logQ = entry.liveQid or (ns.LogQuestIDForPin and ns.LogQuestIDForPin(entry.pin)) or nil
		local trackQ = (wantCheck and logQ and ns.QuestInLog(logQ)) and logQ or nil
		local gCnt, gQid = 0, nil
		if inGroup and ns.GroupQuestCountForPin then
			gCnt, gQid = ns.GroupQuestCountForPin(entry.pin, entry.liveQid)
		end
		out[#out + 1] = {
			kind = "quest",
			i = entry.pin,
			activePin = entry.pin,
			starterNavPin = entry.pin,
			starterName = entry.starterName,
			starterZone = entry.starterZone,
			state = entry.state,
			here = IsHere(entry.pin),
			inLogQuestID = logQ,
			trackQuestID = trackQ,
			watched = trackQ and ns.QuestWatched(trackQ) or nil,
			groupCount = gCnt > 0 and gCnt or nil,
			groupQuestID = gCnt > 0 and gQid or nil,
			lvlTxt = entry.lvlTxt,
			xpColTxt = entry.xpColTxt,
		}
		if not MinimalInfo() then
			AppendRewardsForQuest(out, entry.pin, 1, entry.state == "done", nil)
		end
	end
end

local function CompareDirected(va, vb, asc)
	if va == vb then return nil end
	if asc then return va < vb else return va > vb end
end

local function CompareLevel(la, lb, asc)
	-- Always keep unknown level (999) at the bottom regardless of sort direction.
	local ua, ub = la >= 999, lb >= 999
	if ua or ub then
		if ua == ub then return nil end
		return not ua
	end
	return CompareDirected(la, lb, asc)
end

local function SortQuestEntries(list)
	if #list < 2 then return end
	local D = ns.DATA
	local mode = (ns.db and ns.db.questSort) or "lvl"
	if mode ~= "lvl" and mode ~= "xp" and mode ~= "name" and mode ~= "starter" then
		mode = "lvl"
	end
	if MinimalInfo() and (mode == "xp" or mode == "starter") then
		mode = "lvl"
	end
	local asc = not (ns.db and ns.db.questSortAsc == false)
	table.sort(list, function(a, b)
		if a == b then return false end
		-- Strict weak order by state group: Ready -> In Log -> Available/Locked -> Completed.
		local oa, ob = STATE_ORDER[a.state] or 3, STATE_ORDER[b.state] or 3
		if oa ~= ob then return oa < ob end
		if mode == "xp" then
			local xc = CompareDirected(a.sortXP or 0, b.sortXP or 0, asc)
			if xc ~= nil then return xc end
			local lc = CompareLevel(a.sortLvl or 999, b.sortLvl or 999, true)
			if lc ~= nil then return lc end
		elseif mode == "name" then
			local tc = CompareDirected((D.title[a.pin] or ""):lower(), (D.title[b.pin] or ""):lower(), asc)
			if tc ~= nil then return tc end
			local lc = CompareLevel(a.sortLvl or 999, b.sortLvl or 999, true)
			if lc ~= nil then return lc end
		elseif mode == "starter" then
			local sa, sb = (a.starterName or ""):lower(), (b.starterName or ""):lower()
			local emptyA, emptyB = sa == "", sb == ""
			if emptyA ~= emptyB then return not emptyA end
			local sc = CompareDirected(sa, sb, asc)
			if sc ~= nil then return sc end
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
		return (a.pin or 0) < (b.pin or 0)
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
		skey = "groupQuestCount",
		label = "Show party quest numbers",
		tipTitle = "Show party quest numbers",
		tip = "While in a party or raid, show a brass number badge beside quests in Dave's Map and the objective tracker (hover the number to see group member names).",
		checked = db.groupQuestCount ~= false,
	}
	ui.items[#ui.items + 1] = {
		kind = "setting_check",
		skey = "hideCompleted",
		label = "Hide completed quests",
		tipTitle = "Hide completed quests",
		tip = "Hide completed quests from the Zone and Dungeon reference layers and lists.",
		checked = db.hideCompleted == true,
	}
	ui.items[#ui.items + 1] = {
		kind = "setting_check",
		skey = "trackerTrackedOnly",
		label = "Show only tracked quests",
		tipTitle = "Show only tracked quests",
		tip = "In Tracker & Log, hide untracked Quest Log quests and show only currently tracked, pinned, focused, and ready quests.",
		checked = db.trackerTrackedOnly == true,
	}
	ui.items[#ui.items + 1] = {
		kind = "setting_check",
		skey = "minimalQuestInfo",
		label = "Minimal quest info",
		tipTitle = "Minimal quest info",
		tip = "Show only the quest row itself in quest lists (hides quest chains, chain steps, reward items, boss drops by default, and extra Starter/XP columns).",
		checked = db.minimalQuestInfo == true,
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
	ui.items[#ui.items + 1] = {
		kind = "setting_check",
		skey = "nodeShimmer",
		label = "Shimmer nearby harvest nodes",
		tipTitle = "Shimmer nearby harvest nodes",
		tip = "Add a golden loot-style sparkle shimmer to nearby herbs, mining veins, and chests when facing them (uses Blizzard's soft-interact icon; restores your original settings when turned off).",
		checked = db.nodeShimmer == true,
	}

	if ns.BLIZZ_MAP_FILTERS and ns.GetBlizzMapFilter then
		ui.items[#ui.items + 1] = { kind = "head", title = "Blizzard Map Tracking & Filters", right = "" }
		for _, fdef in ipairs(ns.BLIZZ_MAP_FILTERS) do
			if fdef.cvar or fdef.minimapFilter then
				ui.items[#ui.items + 1] = {
					kind = "setting_check",
					skey = fdef.key,
					label = fdef.label,
					tipTitle = fdef.label,
					tip = fdef.tip,
					checked = ns.GetBlizzMapFilter(fdef.key) == true,
				}
			end
		end
	end

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
				EmitQuestEntry(ui.items, entry, false)
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
	local zMap, activeDung
	if ns.ActiveDungeonContext then
		zMap, activeDung = ns.ActiveDungeonContext()
	else
		zMap = (ns.ActiveDungeonZone and ns.ActiveDungeonZone()) or viewZ
	end
	ui.zoneMap = zMap
	if not (D and ns.Calibrate()) then return end

	local zoneDungs
	if activeDung and activeDung.dungeon then
		zoneDungs = { activeDung.dungeon }
	elseif zMap and D.dungeons and D.dungeons[zMap] and #D.dungeons[zMap] > 0 then
		zoneDungs = D.dungeons[zMap]
	end
	if not (zoneDungs and #zoneDungs > 0) then
		local zInfo = zMap and C_Map.GetMapInfo(zMap)
		local zName = zInfo and zInfo.name or "this zone"
		ui.items[1] = {
			kind = "note",
			title = "No dungeons in " .. zName,
			sub = "Pan to a zone with a dungeon or raid, or search any dungeon above.",
		}
		return
	end

	local zInfo = zMap and C_Map.GetMapInfo(zMap)
	local zName = zInfo and zInfo.name or (activeDung and activeDung.dungeon and activeDung.dungeon.name) or "this zone"
	local fold = ns.db.zoneFold or {}
	local multiDungs = #zoneDungs > 1
	local isActiveInst = activeDung ~= nil and activeDung.dungeon ~= nil
	local isInsideInst = isActiveInst and not activeDung.fromView
	local dungViewShown = (ns.IsDungeonViewShown and ns.IsDungeonViewShown()) == true
	local minimal = MinimalInfo()
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

		if isActiveInst then
			ui.inDungeonInfo = {
				name = d.name,
				lo = d.lo,
				hi = d.hi,
				raid = d.raid == true,
				done = dDone,
				total = dTotal,
				remXP = dRemXP,
				exactXP = dExactXP,
				isInside = isInsideInst,
			}
		end

		local hi = (d.hi and d.hi > 0) and d.hi or d.lo
		local mid = (d.lo and hi and d.lo > 0) and math.floor((d.lo + hi) / 2) or 0
		local range = (d.lo and d.lo > 0) and ((d.lo == hi) and tostring(d.lo) or (d.lo .. "-" .. hi)) or nil
		local lvlTag = range and (" |c%s[%s]|r"):format(DiffHex(mid), range) or ""
		local headTitle = (d.raid and "Raid: " or "Dungeon: ") .. d.name .. lvlTag
		local xpHeader = dRemXP > 0 and ns.FormatXP(dRemXP, dExactXP) or nil
		local rightTxt = dTotal > 0 and ("%d/%d"):format(dDone, dTotal) or "Map"
		if xpHeader then rightTxt = rightTxt .. " - " .. xpHeader end

		local secKey = isActiveInst and ("in:dung:" .. d.name) or ("dung:" .. d.name)
		local closed = fold[secKey]
		if closed == nil then closed = (not isActiveInst) and multiDungs or false end
		ui.items[#ui.items + 1] = { kind = "zsec", key = secKey, title = headTitle, n = rightTxt, closed = closed }
		if not closed then
			local hasPin = d.pin and d.pin ~= 0
			local canOpenCur = isInsideInst and ns.HasCurrentInstanceMap and ns.HasCurrentInstanceMap()
			local inViewNow = false
			if dungViewShown then
				if hasPin and ui.dungeonOpenPin and ui.dungeonOpenPin == d.pin then
					inViewNow = true
				elseif ui.dungeonOpenName then
					local matchedD = ns.MatchDungeon and select(1, ns.MatchDungeon(ui.dungeonOpenName)) or nil
					if matchedD == d then
						inViewNow = true
					elseif ns.NormDungKey then
						local ok = ns.NormDungKey(ui.dungeonOpenName)
						local dk = ns.NormDungKey(d.name)
						if ok ~= "" and dk ~= "" and (ok == dk or ok:find(dk, 1, true) or dk:find(ok, 1, true)) then
							inViewNow = true
						end
					end
				end
			end
			if hasPin or canOpenCur then
				local subParts = { inViewNow and "Floor map open" or "Open floor map & bosses" }
				if dTotal > 0 then
					local rem = dTotal - dDone
					subParts[#subParts + 1] = rem > 0 and ("%d/%d quests left"):format(rem, dTotal) or ("%d/%d done"):format(dDone, dTotal)
				end
				if xpHeader then subParts[#subParts + 1] = "|cffe8d8a8" .. xpHeader .. "|r" end
				ui.items[#ui.items + 1] = {
					kind = "dung_open",
					i = hasPin and d.pin or 0,
					title = d.name,
					sub = table.concat(subParts, "  -  "),
					isCurrentInstance = isInsideInst,
					inView = inViewNow,
				}
			end
			if #qentries > 0 then
				ui.items[#ui.items + 1] = { kind = "qcols" }
				for _, entry in ipairs(qentries) do
					EmitQuestEntry(ui.items, entry, false)
				end
			elseif isActiveInst then
				ui.items[#ui.items + 1] = {
					kind = "note",
					title = dTotal > 0 and "All dungeon quests completed" or "No QuestieDB quests listed",
					sub = dTotal > 0 and "Uncheck Hide Completed in Base to view completed quests." or "Bosses and floor map details are still available below.",
				}
			end
			local bosses, bossInstID = nil, (isActiveInst and activeDung.instID) or nil
			if isActiveInst and activeDung.bosses and #activeDung.bosses > 0 then
				bosses = activeDung.bosses
			elseif ns.DungeonBosses then
				bosses, bossInstID = ns.DungeonBosses(bossInstID, d.name)
			end
			if bosses and #bosses > 0 then
				local bKey = "bosses:" .. d.name
				local bClosed = fold[bKey]
				if bClosed == nil then
					bClosed = (not isActiveInst and not inViewNow and (multiDungs or minimal)) and true or false
				end
				local bossRows, rareCount, regCount = {}, 0, 0
				for bIdx, bossName in ipairs(bosses) do
					local floorNum, numFloors, isRare, spotCount, bossNote
					if ns.DungeonBossFloor then
						floorNum, numFloors, isRare, spotCount, bossNote = ns.DungeonBossFloor(bossInstID, d.name, bossName)
					end
					if isRare then
						rareCount = rareCount + 1
					else
						regCount = regCount + 1
					end
					local drops = ns.BossDrops and ns.BossDrops(bossInstID, d.name, bossName) or nil
					local dropCount = drops and math.floor(#drops / 2) or 0
					local lootKey = tostring(bossInstID or d.name) .. ":" .. bossName
					local lootExpanded = dropCount > 0 and ns.IsBossLootExpanded and ns.IsBossLootExpanded(lootKey, minimal) or false
					bossRows[#bossRows + 1] = {
						kind = "boss",
						num = bIdx,
						bossNum = not isRare and regCount or nil,
						title = bossName,
						instID = bossInstID,
						dungeonName = d.name,
						dungeonPin = hasPin and d.pin or 0,
						isCurrentInstance = isInsideInst,
						inView = inViewNow,
						floorNum = floorNum,
						numFloors = numFloors,
						isRare = isRare == true,
						spotCount = spotCount or 0,
						bossNote = bossNote,
						dropCount = dropCount,
						drops = drops,
						lootKey = lootKey,
						lootExpanded = lootExpanded,
					}
				end
				ui.items[#ui.items + 1] = {
					kind = "zsec",
					key = bKey,
					title = rareCount > 0 and "Bosses & Rares" or "Bosses",
					n = rareCount > 0 and ("%d + %dR"):format(regCount, rareCount) or tostring(#bosses),
					closed = bClosed,
				}
				if not bClosed then
					for _, br in ipairs(bossRows) do
						ui.items[#ui.items + 1] = br
						if br.lootExpanded and br.drops then
							local drops = br.drops
							for k = 1, #drops, 2 do
								ui.items[#ui.items + 1] = {
									kind = "boss_drop",
									itemID = drops[k],
									dropPct = drops[k + 1] or 0,
									bossName = br.title,
									bossNum = br.bossNum,
									isRare = br.isRare,
									instID = br.instID,
									dungeonName = br.dungeonName,
									dungeonPin = br.dungeonPin,
									isCurrentInstance = br.isCurrentInstance,
									inView = br.inView,
									floorNum = br.floorNum,
									numFloors = br.numFloors,
								}
							end
						end
					end
				end
			end
		end
	end
end

local TRACKER_SECTIONS = {
	{ key = "focused", title = "Focused" },
	{ key = "ready", title = "Ready to Turn In" },
	{ key = "pinned", title = "Pinned" },
	{ key = "tracking", title = "Tracking" },
	{ key = "log", title = "Quest Log" },
}

local function ResolveTrackerPin(q)
	local pin = ns.QuestPin and ns.QuestPin(q) or nil
	if not pin and ns.FindQuestPinsForTracker then
		local pins = ns.FindQuestPinsForTracker(q)
		pin = pins and pins[1] or nil
	end
	return pin
end

local function BuildLogMetaMap()
	local meta = {}
	local header = nil
	local nEntries = ns.NumQuestLogEntries and ns.NumQuestLogEntries() or 0
	for idx = 1, nEntries do
		local info = ns.QuestInfo and ns.QuestInfo(idx)
		if info then
			if info.isHeader then
				header = (type(info.title) == "string" and not issecretvalue(info.title) and info.title ~= "") and info.title or nil
			elseif not info.isHidden and info.questID and info.questID ~= 0 and not issecretvalue(info.questID) then
				local t = (type(info.title) == "string" and not issecretvalue(info.title) and info.title ~= "") and info.title or nil
				local lvl = (type(info.level) == "number" and not issecretvalue(info.level)) and info.level or 0
				meta[info.questID] = {
					title = t,
					level = lvl,
					zone = header,
				}
			end
		end
	end
	return meta
end

local function CurrentPlayerZoneSet()
	local set = {}
	local function Add(name)
		if type(name) == "string" and not issecretvalue(name) and name ~= "" then
			set[name:lower()] = true
		end
	end
	Add(GetRealZoneText and GetRealZoneText() or nil)
	local best = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if type(best) == "number" and not issecretvalue(best) and best ~= 0 and C_Map.GetMapInfo then
		local m, hops = best, 0
		while m and m ~= 0 and hops < 4 do
			local info = C_Map.GetMapInfo(m)
			if not info then break end
			if info.mapType and info.mapType >= Enum.UIMapType.Zone then
				Add(info.name)
			end
			if info.mapType and info.mapType <= Enum.UIMapType.Zone then break end
			m = info.parentMapID
			hops = hops + 1
		end
	end
	return set
end

local function SortLogOnlyEntries(list)
	if #list < 2 then return end
	local mode = (ns.db and ns.db.questSort) or "lvl"
	if MinimalInfo() and (mode == "xp" or mode == "starter") then
		mode = "lvl"
	end
	local asc = not (ns.db and ns.db.questSortAsc == false)
	table.sort(list, function(a, b)
		if a == b then return false end
		if mode == "name" then
			local tc = CompareDirected((a.title or ""):lower(), (b.title or ""):lower(), asc)
			if tc ~= nil then return tc end
		elseif mode == "starter" then
			local sa, sb = (a.zone or ""):lower(), (b.zone or ""):lower()
			local ea, eb = sa == "", sb == ""
			if ea ~= eb then return not ea end
			local sc = CompareDirected(sa, sb, asc)
			if sc ~= nil then return sc end
		else
			local la = (a.level and a.level > 0) and a.level or 999
			local lb = (b.level and b.level > 0) and b.level or 999
			local lc = CompareLevel(la, lb, asc)
			if lc ~= nil then return lc end
		end
		local ta, tb = (a.title or ""):lower(), (b.title or ""):lower()
		if ta ~= tb then return ta < tb end
		return (a.q or 0) < (b.q or 0)
	end)
end

local function EmitLogOnlyRow(out, lq)
	local gCnt = (IsInGroup and IsInGroup() and ns.GroupQuestCount) and ns.GroupQuestCount(lq.q) or 0
	local isReady = ns.QuestReady(lq.q) or ns.QuestComplete(lq.q) == true
	out[#out + 1] = {
		kind = "logquest",
		questID = lq.q,
		inLogQuestID = lq.q,
		trackQuestID = lq.q,
		watched = ns.QuestWatched(lq.q),
		title = lq.title,
		zone = lq.zone,
		lvlTxt = FormatLvlCell(lq.level),
		state = isReady and "ready" or "log",
		groupCount = gCnt > 0 and gCnt or nil,
		groupQuestID = gCnt > 0 and lq.q or nil,
		xpColTxt = isReady and "|cffffd200Ready|r" or "|cff7fd4ffIn Log|r",
	}
end

local function BuildTrackerItems()
	local D = ns.DATA
	if not (D and ns.Calibrate() and ns.CollectTrackerQuests) then return end
	local bucketQuests = ns.CollectTrackerQuests()
	local logMeta = BuildLogMetaMap()

	-- Deduplicate chain starters in strict priority order (Focused -> Ready -> Pinned -> Tracking -> Quest Log)
	-- so two active steps of the same branched chain never render duplicate chain blocks.
	local seenStarter = {}
	local fold = (ns.db and ns.db.zoneFold) or {}
	local trackedOnly = ns.db and ns.db.trackerTrackedOnly == true
	local curZones = (not trackedOnly) and CurrentPlayerZoneSet() or nil
	for _, sec in ipairs(TRACKER_SECTIONS) do
		local entries, logOnly = {}, {}
		if not (trackedOnly and sec.key == "log") then
			for _, q in ipairs(bucketQuests[sec.key] or {}) do
				local lm = logMeta[q]
				local pin = ResolveTrackerPin(q)
				if pin then
					local entry = MakeQuestEntry(pin, nil, true, q)
					if entry and not seenStarter[entry.pin] then
						seenStarter[entry.pin] = true
						entry.logZone = (lm and lm.zone) or (ns.ZoneName and ns.ZoneName(pin)) or entry.starterZone or "Other"
						entries[#entries + 1] = entry
					end
				else
					logOnly[#logOnly + 1] = {
						q = q,
						title = (lm and lm.title) or (ns.QuestTitle and ns.QuestTitle(q)) or ("Quest #" .. tostring(q)),
						level = lm and lm.level or 0,
						zone = (lm and lm.zone) or nil,
					}
				end
			end
		end
		local total = #entries + #logOnly
		if total > 0 then
			local fkey = "trk:" .. sec.key
			local closed = fold[fkey] == true
			ui.items[#ui.items + 1] = { kind = "zsec", key = fkey, title = sec.title, n = tostring(total), closed = closed }
			if not closed then
				ui.items[#ui.items + 1] = { kind = "qcols" }
				if sec.key == "log" then
					local byZone, zoneOrder = {}, {}
					local function ZoneGroup(zName)
						local z = (zName and zName ~= "") and zName or "Other"
						local grp = byZone[z]
						if not grp then
							grp = { name = z, entries = {}, logOnly = {} }
							byZone[z] = grp
							zoneOrder[#zoneOrder + 1] = z
						end
						return grp
					end
					for _, entry in ipairs(entries) do
						local grp = ZoneGroup(entry.logZone)
						grp.entries[#grp.entries + 1] = entry
					end
					for _, lq in ipairs(logOnly) do
						local grp = ZoneGroup(lq.zone)
						grp.logOnly[#grp.logOnly + 1] = lq
					end
					table.sort(zoneOrder, function(a, b)
						if a == b then return false end
						local al, bl = a:lower(), b:lower()
						if curZones then
							local ac, bc = curZones[al] == true, curZones[bl] == true
							if ac ~= bc then return ac end
						end
						local ao, bo = a == "Other", b == "Other"
						if ao ~= bo then return not ao end
						return al < bl
					end)
					for _, zName in ipairs(zoneOrder) do
						local grp = byZone[zName]
						local zCount = #grp.entries + #grp.logOnly
						local zKey = "trk:log:z:" .. zName
						local zClosed = fold[zKey] == true
						ui.items[#ui.items + 1] = {
							kind = "zsub",
							key = zKey,
							title = zName,
							n = tostring(zCount),
							closed = zClosed,
						}
						if not zClosed then
							SortQuestEntries(grp.entries)
							SortLogOnlyEntries(grp.logOnly)
							for _, entry in ipairs(grp.entries) do
								EmitQuestEntry(ui.items, entry, true)
							end
							for _, lq in ipairs(grp.logOnly) do
								EmitLogOnlyRow(ui.items, lq)
							end
						end
					end
				else
					SortQuestEntries(entries)
					SortLogOnlyEntries(logOnly)
					for _, entry in ipairs(entries) do
						EmitQuestEntry(ui.items, entry, true)
					end
					for _, lq in ipairs(logOnly) do
						EmitLogOnlyRow(ui.items, lq)
					end
				end
			end
		end
	end

	if #ui.items == 0 then
		local logCount = (ns.QuestLogCounts and ns.QuestLogCounts()) or 0
		if trackedOnly and logCount > 0 then
			ui.items[1] = {
				kind = "note",
				title = "No tracked quests",
				sub = "Click Tracked in the top bar (or Map Settings) to show all Quest Log quests.",
			}
		else
			ui.items[1] = {
				kind = "note",
				title = "Your Quest Log is empty",
				sub = "Accept quests in the world or browse the Zone / Dungeon tabs to see available quests.",
			}
		end
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
	ui.inDungeonInfo = nil
	local tab = ns.db and ns.db.panelTab or "layers"
	local key
	if ui.found then
		local raw = ui.search and ui.search:GetText()
		local qtxt = (raw and not issecretvalue(raw) and raw or ""):lower():match("^%s*(.-)%s*$")
		key = "search:" .. qtxt
		local originMap = ui.searchOriginMap
		local originPins = originMap and ns.PinsOnMap(originMap) or nil
		local all = {}
		local minimal = MinimalInfo()
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
				sub = isQ and ((not minimal) and QuestSubtitle(i, st, blk) or nil) or NonQuestSubtitle(i),
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
			if r.isQuest and not minimal then
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
		BuildDungeonItems()
		if ui.inDungeonInfo then
			key = "dungeon:in:" .. tostring(ui.inDungeonInfo.name or 0)
		else
			key = "dungeon:" .. tostring(ui.zoneMap or 0)
		end
	else
		key = "layers"
		BuildLayersItems()
	end

	local top = 0
	local wantPin = ui.revealPin
	local wantQid = (wantPin and D.qid[wantPin] ~= 0) and D.qid[wantPin] or nil
	local fallbackIdx, qidFallbackIdx = nil, nil
	for idx, item in ipairs(ui.items) do
		local h = (item.kind == "result" and not item.sub) and 28 or (ROW_HEIGHTS[item.kind] or 34)
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
