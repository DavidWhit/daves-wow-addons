-- daves_map / Quests.lua
-- Quest progression, completion indexing, sequential quest-chain graph, XP & item reward model.
--
-- Pure domain/data module (zero UI frames or canvas widgets):
--   * Indexes QuestieDB Forever pins by questID and normalized title, handling multi-ID & multi-part quests.
--   * Builds clean sequential quest chains (`ns.ChainFor`, `ns.IsChainEdge`), filtering out hub-unlock gates
--     (quests unlocking 3+ unrelated village/class quests) and opposite-faction twin branches.
--   * Resolves quest XP (live client XP when preloaded, accurate Classic/Forever level formula otherwise),
--     item rewards (`D.rew` + live `questRewards`), chain worthiness (`ns.ChainWorth`), zone storylines,
--     and dungeon quest summaries (`ns.DungeonQuestEntries`).
--   * Read getters stay side-effect-free unless `preload == true` (hovered tooltip or single inspected quest).

local _, ns = ...

local MAX_CHAIN = 48

local BASE_XP = {
	80, 170, 250, 350, 450, 550, 625, 700, 775, 840,
	900, 960, 1020, 1080, 1150, 1230, 1310, 1390, 1470, 1550,
	1640, 1730, 1820, 1910, 2000, 2090, 2180, 2270, 2360, 2450,
	2540, 2640, 2740, 2840, 2940, 3040, 3140, 3240, 3340, 3450,
	3580, 3710, 3850, 3990, 4130, 4270, 4410, 4550, 4700, 4850,
	5010, 5170, 5340, 5510, 5680, 5860, 6040, 6220, 6410, 6600,
}

local QUALITY_HEX = {
	[0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd",
	[4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff",
}

local state = {
	graphBuilt = false, nextOf = {}, done = {}, recentTurnIn = {}, inLogIds = {}, inLogByTitle = {},
	pinsOfQuest = nil, pinsByTitle = nil, questPinsByTitle = nil, isMultiStepTitle = nil,
	syncedDone = false, inLogStale = true, rewardRefreshQueued = false,
	qlogPending = false, qlogDirty = false,
	liveXP = {}, reqReward = {}, pendReward = {}, mergedRew = {}, reqItem = {}, pendItem = {},
	chainCache = {}, worthCache = {}, dungQuestSet = nil, dungByNorm = nil,
	groupQuestCount = {}, groupRefreshQueued = false, questsInited = false,
}

---------------------------------------------------------------------------
-- Formatting & Key Helpers
---------------------------------------------------------------------------
local function NormTitle(s)
	if type(s) ~= "string" or issecretvalue(s) or s == "" then return nil end
	s = s:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	return s ~= "" and s or nil
end

local function FormatNumber(n)
	local s = tostring(math.floor((n or 0) + 0.5))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
ns.FormatNumber = FormatNumber

function ns.FormatXP(xp, exact)
	if not xp or xp <= 0 then return nil end
	return (exact and "%s XP" or "~%s XP"):format(FormatNumber(xp))
end

local function NormDungKey(s)
	s = (s or ""):lower():gsub("^the%s+", ""):gsub("[^%w]+", "")
	if s == "stockade" or s == "stormwindstockades" then return "stormwindstockade" end
	if s == "templeofatalhakkar" or s == "atalhakkar" then return "sunkentemple" end
	if s == "ahnqirajtemple" or s == "ahnqiraj" then return "templeofahnqiraj" end
	return s
end
ns.NormDungKey = NormDungKey

-- Canonical WoW Classic & Forever instanceID -> normalized D.dungeons key (deterministic across locales/wings).
local INSTANCE_ID_TO_KEY = {
	[33] = "shadowfangkeep",
	[34] = "stormwindstockade",
	[36] = "deadmines",
	[43] = "wailingcaverns",
	[47] = "razorfenkraul",
	[48] = "blackfathomdeeps",
	[70] = "uldaman",
	[90] = "gnomeregan",
	[109] = "sunkentemple",
	[129] = "razorfendowns",
	[189] = "scarletmonastery",
	[209] = "zulfarrak",
	[229] = "blackrockspire",
	[230] = "blackrockdepths",
	[249] = "onyxiaslair",
	[289] = "scholomance",
	[309] = "zulgurub",
	[329] = "stratholme",
	[349] = "maraudon",
	[389] = "ragefirechasm",
	[409] = "moltencore",
	[429] = "diremaul",
	[469] = "blackwinglair",
	[509] = "ruinsofahnqiraj",
	[531] = "templeofahnqiraj",
	[533] = "naxxramas",
	[2959] = "cityofdalaran",
	[2970] = "drownedcity",
	[2974] = "blackmawhold",
	[2994] = "alcazprison",
	[2998] = "excavationsitewetlands",
	[2999] = "ruinsoflordaeron",
	[3001] = "shapersterrace",
	[3039] = "kroldokstronghold",
	[3065] = "hallofthanes",
}

---------------------------------------------------------------------------
-- Quest Indices & Completion Tracking
---------------------------------------------------------------------------
local function EnsureQuestGraph()
	local data = ns.DATA
	if state.graphBuilt or not data then return end
	state.graphBuilt = true
	for i, list in pairs(data.pre) do
		for _, p in ipairs(list) do
			local bucket = state.nextOf[p]
			if not bucket then
				bucket = {}
				state.nextOf[p] = bucket
			end
			bucket[#bucket + 1] = i
		end
	end
end

local function IsDone(q)
	if ns.QuestInLog(q) then return false end
	local rt = state.recentTurnIn[q]
	if rt then
		if (GetTime() - rt) < 3 then return true end
		state.recentTurnIn[q] = nil
	end
	local v = state.done[q]
	if v == nil then
		v = ns.IsCharQuestCompleted(q)
		state.done[q] = v
	end
	return v
end

local function ReachesPre(pre, target, cur, depth)
	if depth > 4 then return false end
	for _, p in ipairs(pre[cur] or {}) do
		if p == target or ReachesPre(pre, target, p, depth + 1) then return true end
	end
	return false
end

local function BuildQuestIndices()
	if state.pinsOfQuest or not ns.DATA then return end
	EnsureQuestGraph()
	local pinsOfQuest, pinsByTitle, questPinsByTitle, isMultiStepTitle = {}, {}, {}, {}
	state.pinsOfQuest = pinsOfQuest
	state.pinsByTitle = pinsByTitle
	state.questPinsByTitle = questPinsByTitle
	state.isMultiStepTitle = isMultiStepTitle

	local data = ns.DATA
	local qid, cat, cats, title, pre, endp, lvl = data.qid, data.cat, data.cats, data.title, data.pre, data.endp, data.lvl
	for i = 1, #qid do
		local id = qid[i]
		if id ~= 0 then
			pinsOfQuest[id] = pinsOfQuest[id] or {}
			table.insert(pinsOfQuest[id], i)
		end
		local icon = cats[cat[i]] and cats[cat[i]].icon
		if icon == "quest" or icon == "repeatable" then
			local nt = NormTitle(title[i])
			if nt then
				pinsByTitle[nt] = pinsByTitle[nt] or {}
				table.insert(pinsByTitle[nt], i)
				if icon == "quest" then
					questPinsByTitle[nt] = questPinsByTitle[nt] or {}
					table.insert(questPinsByTitle[nt], i)
				end
			end
		end
	end
	for nt, pins in pairs(questPinsByTitle) do
		if #pins > 1 then
			local pset, firstLvl, diffLvl, isLinked = {}, nil, false, false
			for _, i in ipairs(pins) do
				pset[i] = true
				local l = lvl[i]
				if l ~= 0 then
					if not firstLvl then firstLvl = l elseif l ~= firstLvl then diffLvl = true end
				end
			end
			for _, i in ipairs(pins) do
				if pset[endp[i]] then isLinked = true; break end
				for _, j in ipairs(pins) do
					if i ~= j and ReachesPre(pre, j, i, 1) then isLinked = true; break end
				end
				if isLinked then break end
			end
			if isLinked or diffLvl or nt:find("^a donation of ") then
				isMultiStepTitle[nt] = true
				local rank = {}
				for _, i in ipairs(pins) do
					local r = 0
					for _, j in ipairs(pins) do
						if i ~= j and (endp[j] == i or ReachesPre(pre, j, i, 1)) then r = r + 1 end
					end
					rank[i] = r
				end
				table.sort(pins, function(a, b)
					if a == b then return false end
					if rank[a] ~= rank[b] then return rank[a] < rank[b] end
					local la = lvl[a] ~= 0 and lvl[a] or 999
					local lb = lvl[b] ~= 0 and lvl[b] or 999
					if la ~= lb then return la < lb end
					local qa = qid[a] ~= 0 and qid[a] or 9999999
					local qb = qid[b] ~= 0 and qid[b] or 9999999
					if qa ~= qb then return qa < qb end
					return a < b
				end)
			end
		end
	end
end

local function RecomputeInLog()
	state.inLogStale = false
	wipe(state.inLogByTitle)
	wipe(state.worthCache)
	wipe(state.groupQuestCount)
	local data = ns.DATA
	if not data then return false end
	BuildQuestIndices()
	local qt = ns.db and ns.db.questTitles
	local curIds, logChanged = {}, false
	for idx = 1, ns.NumQuestLogEntries() do
		local info = ns.QuestInfo(idx)
		if info and not info.isHeader and info.questID and info.questID ~= 0 and not issecretvalue(info.questID) then
			local q = info.questID
			curIds[q] = true
			if not state.inLogIds[q] then logChanged = true end
			local t = info.title
			if qt and type(t) == "string" and not issecretvalue(t) and t ~= "" then qt[q] = t end
			if not info.isHidden then
				local nt = NormTitle(t or ns.QuestTitle(q))
				if nt and not state.pinsOfQuest[q] and not state.inLogByTitle[nt] then
					state.inLogByTitle[nt] = q
				end
			end
		end
	end
	for q in pairs(state.inLogIds) do
		if not curIds[q] then logChanged = true; break end
	end
	state.inLogIds = curIds
	return logChanged
end

function ns.SyncDoneQuests()
	if not (ns.DATA and ns.db) then return end
	BuildQuestIndices()
	if not state.syncedDone or state.inLogStale then
		state.syncedDone = true
		RecomputeInLog()
	end
end

-- Strict per-character completion check by exact Forever questID (never overridden by title matching).
local function PinDone(i)
	local q = ns.DATA.qid[i]
	if not q or q == 0 then return false end
	return IsDone(q)
end
ns.PinDone = PinDone

function ns.PassesPlayerFilter(i)
	local data = ns.DATA
	if not data then return true end
	local f = data.fac[i]
	if f ~= 0 and ns.factions and not ns.factions[f] then return false end
	return true
end

function ns.LogQuestIDForPin(i)
	local data = ns.DATA
	if not (data and i) then return nil end
	local q = data.qid[i]
	if q and q ~= 0 and ns.QuestInLog(q) then return q end
	local c = data.cats[data.cat[i]]
	if not (c and (c.icon == "quest" or c.icon == "repeatable") and ns.PassesPlayerFilter(i)) then return nil end
	if not state.syncedDone or state.inLogStale then ns.SyncDoneQuests() end
	local nt = NormTitle(data.title[i])
	local lq = nt and state.inLogByTitle[nt]
	if not (lq and not (state.pinsOfQuest and state.pinsOfQuest[lq]) and ns.QuestInLog(lq)) then return nil end
	if state.isMultiStepTitle and state.isMultiStepTitle[nt] then
		for _, p in ipairs(state.questPinsByTitle[nt] or {}) do
			if ns.PassesPlayerFilter(p) and not PinDone(p) then return p == i and lq or nil end
		end
	end
	return lq
end

function ns.PinQuestState(i)
	local data = ns.DATA
	if not data then return "avail", nil end
	if not state.syncedDone then ns.SyncDoneQuests() end
	if PinDone(i) then return "done", nil end
	local q = ns.LogQuestIDForPin(i)
	if q then return ns.QuestReady(q) and "ready" or "log", nil end
	for _, p in ipairs(data.pre[i] or {}) do
		if ns.PassesPlayerFilter(p) and not PinDone(p) then return "locked", p end
	end
	return "avail", nil
end

function ns.PinsOfQuest(q)
	if type(q) ~= "number" or q == 0 or issecretvalue(q) or not ns.DATA then return nil end
	BuildQuestIndices()
	if state.pinsOfQuest[q] then return state.pinsOfQuest[q] end
	local nt = NormTitle(ns.QuestTitle(q))
	local list = nt and state.pinsByTitle[nt]
	if not list then return nil end
	if #list == 1 then return list end
	if not state.syncedDone then ns.SyncDoneQuests() end
	local factions = ns.factions
	local fac = ns.DATA.fac
	local active, byFac = {}, {}
	for _, i in ipairs(list) do
		local f = fac[i]
		if f == 0 or not factions or factions[f] then
			byFac[#byFac + 1] = i
			if not PinDone(i) then active[#active + 1] = i end
		end
	end
	if #active > 0 then return active end
	if #byFac > 0 then return byFac end
	return list
end

function ns.QuestPin(q)
	local list = ns.DATA and ns.PinsOfQuest(q)
	if not list then return nil end
	if #list > 1 and ns.QuestUiMapID then
		local qMap = ns.QuestUiMapID(q)
		if type(qMap) == "number" and qMap ~= 0 and not issecretvalue(qMap) then
			local mapArr = ns.DATA.map
			for _, i in ipairs(list) do
				if mapArr and mapArr[i] == qMap then return i end
			end
		end
	end
	return list[1]
end

---------------------------------------------------------------------------
-- Sequential Quest-Chain Graph
---------------------------------------------------------------------------
local function FacCompatible(a, b)
	local data = ns.DATA
	if not (data and ns.PassesPlayerFilter(a) and ns.PassesPlayerFilter(b)) then return false end
	local fa, fb = data.fac[a], data.fac[b]
	if (fa == 1 and fb == 2) or (fa == 2 and fb == 1) then return false end
	return true
end

function ns.NextOf(i)
	EnsureQuestGraph()
	return state.nextOf[i]
end

local function EligibleNext(u)
	EnsureQuestGraph()
	local out = {}
	for _, w in ipairs(state.nextOf[u] or {}) do
		if FacCompatible(u, w) then out[#out + 1] = w end
	end
	return out
end
ns.EligibleNext = EligibleNext

local function EligiblePre(v)
	local data = ns.DATA
	local out = {}
	if not data then return out end
	for _, p in ipairs(data.pre[v] or {}) do
		if FacCompatible(p, v) then out[#out + 1] = p end
	end
	return out
end
ns.EligiblePre = EligiblePre

local function SharesFollowup(a, b)
	local setA = {}
	for _, w in ipairs(state.nextOf[a] or {}) do setA[w] = true end
	for _, w in ipairs(state.nextOf[b] or {}) do
		if setA[w] then return true end
	end
	return false
end

local function SharesPrereq(a, b)
	local pre = ns.DATA.pre
	local setA = {}
	for _, p in ipairs(pre[a] or {}) do setA[p] = true end
	for _, p in ipairs(pre[b] or {}) do
		if setA[p] then return true end
	end
	return false
end

local function IsChainEdge(u, v)
	local data = ns.DATA
	if not (data and FacCompatible(u, v)) then return false end
	EnsureQuestGraph()
	local en = EligibleNext(u)
	local nu = data.nxt and data.nxt[u]
	if #en >= 3 then
		-- Hub-unlock gate (opens 3+ quests at once): only follow an explicit same-named multi-part continuation
		if not (nu == v and NormTitle(data.title[u]) == NormTitle(data.title[v])) then return false end
	elseif #en == 2 then
		if nu == en[1] or nu == en[2] then
			if nu ~= v then return false end
		elseif NormTitle(data.title[en[1]]) == NormTitle(data.title[en[2]]) then
			if v ~= en[1] then return false end
		else
			local tu = NormTitle(data.title[u])
			local t1, t2 = NormTitle(data.title[en[1]]), NormTitle(data.title[en[2]])
			if t1 == tu or t2 == tu then
				if NormTitle(data.title[v]) ~= tu then return false end
			elseif not SharesFollowup(en[1], en[2]) then
				return false
			end
		end
	end

	local ep = EligiblePre(v)
	if #ep >= 3 then
		return false
	elseif #ep == 2 then
		if NormTitle(data.title[ep[1]]) == NormTitle(data.title[ep[2]]) then
			if u ~= ep[1] then return false end
		elseif nu ~= v and NormTitle(data.title[u]) ~= NormTitle(data.title[v]) and not SharesPrereq(ep[1], ep[2]) then
			return false
		end
	end
	return true
end
ns.IsChainEdge = IsChainEdge

local function BuildChain(root)
	local data = ns.DATA
	if not (data and root) then return nil end
	EnsureQuestGraph()
	local icon = data.cats[data.cat[root]] and data.cats[data.cat[root]].icon
	if icon ~= "quest" and icon ~= "repeatable" then
		return { root = root, steps = { root }, num = { [root] = 1 }, set = { [root] = true } }
	end
	local cached = state.chainCache[root]
	if cached then
		return { root = root, steps = cached.steps, num = cached.num, set = cached.set }
	end
	local set, queue = { [root] = true }, { root }
	local head = 1
	while head <= #queue and #queue < MAX_CHAIN do
		local cur = queue[head]
		head = head + 1
		for _, p in ipairs(data.pre[cur] or {}) do
			if not set[p] and #queue < MAX_CHAIN and IsChainEdge(p, cur) then
				set[p] = true
				queue[#queue + 1] = p
			end
		end
		for _, j in ipairs(state.nextOf[cur] or {}) do
			if not set[j] and #queue < MAX_CHAIN and IsChainEdge(cur, j) then
				set[j] = true
				queue[#queue + 1] = j
			end
		end
	end
	local depth = {}
	local function Depth(i, guard)
		if depth[i] then return depth[i] end
		local d = 1
		if guard < 32 then
			for _, p in ipairs(data.pre[i] or {}) do
				if set[p] and IsChainEdge(p, i) then d = math.max(d, Depth(p, guard + 1) + 1) end
			end
		end
		depth[i] = d
		return d
	end
	local steps = {}
	for i in pairs(set) do Depth(i, 0); steps[#steps + 1] = i end
	table.sort(steps, function(a, b)
		if depth[a] ~= depth[b] then return depth[a] < depth[b] end
		if data.lvl[a] ~= data.lvl[b] then return data.lvl[a] < data.lvl[b] end
		if data.title[a] ~= data.title[b] then return data.title[a] < data.title[b] end
		return a < b
	end)
	local num = {}
	for n, i in ipairs(steps) do num[i] = n end
	local comp = { steps = steps, num = num, set = set }
	if #queue < MAX_CHAIN then
		for _, s in ipairs(steps) do state.chainCache[s] = comp end
	else
		state.chainCache[root] = comp
	end
	return { root = root, steps = steps, num = num, set = set }
end

function ns.ChainFor(root)
	return root and BuildChain(root) or nil
end

-- Returns `activePin, activeIdx, inLogPin, allDone` for chain `ch`, resolving the single currently active step
-- (preferring the step in the player's quest book, else the next available step, else the earliest uncompleted step).
function ns.ChainProgress(ch, fallbackPin)
	if not (ch and ch.steps and #ch.steps > 0) then return fallbackPin, 1, nil, false end
	if not state.syncedDone then ns.SyncDoneQuests() end
	local inLogPin, availPin, undonePin
	for _, s in ipairs(ch.steps) do
		if not PinDone(s) then
			undonePin = undonePin or s
			if not inLogPin and ns.LogQuestIDForPin and ns.LogQuestIDForPin(s) then
				inLogPin = s
			end
			if not availPin and ns.PinQuestState(s) == "avail" then
				availPin = s
			end
		end
	end
	local allDone = undonePin == nil
	local activePin = inLogPin or availPin or undonePin
		or (fallbackPin and ch.set and ch.set[fallbackPin] and fallbackPin)
		or ch.steps[#ch.steps]
	return activePin, (ch.num and ch.num[activePin]) or 1, inLogPin, allDone
end

function ns.ResolveActiveChainPin(pin)
	if not pin then return nil, nil, false end
	local ch = BuildChain(pin)
	if not (ch and #ch.steps > 1) then return pin, ch, false end
	local activePin, _, _, allDone = ns.ChainProgress(ch, pin)
	return activePin or pin, ch, allDone
end

---------------------------------------------------------------------------
-- Quest XP, Item Rewards, Chain Worthiness & Storylines
---------------------------------------------------------------------------
local function GetMapPlaces()
	return ns.OM and ns.OM.MapPlaces or nil
end

local function FindPlaceByInstID(instID)
	local places = instID and GetMapPlaces()
	if not places then return nil end
	for _, g in ipairs(places.instances or {}) do
		for _, inst in ipairs(g[4] or {}) do
			if inst[1] == instID then return inst end
		end
	end
	for _, inst in ipairs(places.unplaced or {}) do
		if inst[1] == instID then return inst end
	end
	return nil
end

local function EnsureDungeonIndex()
	if not state.instIdByNorm then
		state.instIdByNorm = {}
		for id, key in pairs(INSTANCE_ID_TO_KEY) do
			if not state.instIdByNorm[key] then state.instIdByNorm[key] = id end
		end
		local places = GetMapPlaces()
		if places then
			for _, g in ipairs(places.instances or {}) do
				for _, inst in ipairs(g[4] or {}) do
					local k = NormDungKey(inst[2])
					if k ~= "" and inst[1] and inst[1] ~= 0 and not state.instIdByNorm[k] then
						state.instIdByNorm[k] = inst[1]
					end
				end
			end
			for _, inst in ipairs(places.unplaced or {}) do
				local k = NormDungKey(inst[2])
				if k ~= "" and inst[1] and inst[1] ~= 0 and not state.instIdByNorm[k] then
					state.instIdByNorm[k] = inst[1]
				end
			end
		end
	end
	if state.dungQuestSet or not (ns.DATA and ns.DATA.dungeons) then return end
	state.dungQuestSet, state.dungByNorm, state.dungZoneByNorm = {}, {}, {}
	local zMaps = {}
	for zMap in pairs(ns.DATA.dungeons) do zMaps[#zMaps + 1] = zMap end
	table.sort(zMaps)
	for _, zMap in ipairs(zMaps) do
		for _, d in ipairs(ns.DATA.dungeons[zMap]) do
			local k = NormDungKey(d.name)
			if k ~= "" and not state.dungByNorm[k] then
				state.dungByNorm[k] = d
				state.dungZoneByNorm[k] = zMap
			end
			for _, qi in ipairs(d.quests or {}) do state.dungQuestSet[qi] = true end
		end
	end
end

function ns.FindDungeonPlace(instName, instID)
	if type(instID) == "number" and instID ~= 0 then
		local byId = FindPlaceByInstID(instID)
		if byId then return byId end
	end
	local places = instName and GetMapPlaces()
	if not places then return nil end
	local want = NormDungKey(instName)
	if want == "" then return nil end
	local partial
	local function Scan(list)
		for _, inst in ipairs(list or {}) do
			local k = NormDungKey(inst[2])
			if k == want then return inst end
			if not partial and k ~= "" and (k:find(want, 1, true) or want:find(k, 1, true)) then
				partial = inst
			end
		end
		return nil
	end
	for _, g in ipairs(places.instances or {}) do
		local hit = Scan(g[4])
		if hit then return hit end
	end
	return Scan(places.unplaced) or partial
end

function ns.DungeonBosses(instID, dungName)
	EnsureDungeonIndex()
	local id = instID
	if not (type(id) == "number" and id ~= 0) and dungName then
		local k = NormDungKey(dungName)
		id = state.instIdByNorm and state.instIdByNorm[k] or nil
		if not id and k ~= "" then
			for nk, nid in pairs(state.instIdByNorm or {}) do
				if k:find(nk, 1, true) or nk:find(k, 1, true) then id = nid; break end
			end
		end
	end
	if ns.DungeonBossList then
		local list, resolvedID = ns.DungeonBossList(id, dungName)
		if list and #list > 0 then return list, resolvedID or id end
	end
	local places = GetMapPlaces()
	if not (places and places.bosses) then return nil, id end
	return (id and places.bosses[id]) or nil, id
end

function ns.FormatDropPct(pctX10)
	if type(pctX10) ~= "number" or pctX10 <= 0 then return nil end
	local pct = pctX10 / 10
	if pct >= 10 then
		return ("%d%%"):format(math.floor(pct + 0.5))
	end
	return ("%.1f%%"):format(pct)
end

function ns.BossDrops(instID, dungName, bossName)
	local bDrops = ns.DATA and ns.DATA.bossDrops
	if not (bDrops and type(bossName) == "string" and bossName ~= "") then return nil end
	EnsureDungeonIndex()
	local id = instID
	if not (type(id) == "number" and id ~= 0) and dungName then
		local k = NormDungKey(dungName)
		id = state.instIdByNorm and state.instIdByNorm[k] or nil
		if not id and k ~= "" then
			for nk, nid in pairs(state.instIdByNorm or {}) do
				if k:find(nk, 1, true) or nk:find(k, 1, true) then id = nid; break end
			end
		end
	end
	local instTbl = id and bDrops[id] or nil
	if not instTbl then return nil end
	local exact = instTbl[bossName]
	if exact and #exact > 0 then return exact end
	local low = bossName:lower()
	for k, v in pairs(instTbl) do
		if type(k) == "string" and k:lower() == low and type(v) == "table" and #v > 0 then
			return v
		end
	end
	return nil
end

function ns.MatchDungeon(instName, instID)
	EnsureDungeonIndex()
	local byNorm = state.dungByNorm
	if not byNorm then return nil, nil, instID end
	local function TryKey(k)
		if k and k ~= "" and byNorm[k] then
			return byNorm[k], state.dungZoneByNorm[k], instID or (state.instIdByNorm and state.instIdByNorm[k])
		end
		return nil
	end
	if type(instID) == "number" and instID ~= 0 then
		local d, z, id = TryKey(INSTANCE_ID_TO_KEY[instID])
		if d then return d, z, id end
		local place = FindPlaceByInstID(instID)
		if place and place[2] then
			local pk = NormDungKey(place[2])
			d, z, id = TryKey(pk)
			if d then return d, z, instID end
			if pk ~= "" then
				local bestK, bestLen = nil, 0
				for k in pairs(byNorm) do
					if #k > bestLen and (pk:find(k, 1, true) or k:find(pk, 1, true)) then
						bestK, bestLen = k, #k
					end
				end
				if bestK then return byNorm[bestK], state.dungZoneByNorm[bestK], instID end
			end
		end
	end
	if type(instName) == "string" and instName ~= "" then
		local key = NormDungKey(instName)
		local d, z, id = TryKey(key)
		if d then return d, z, id end
		if key ~= "" then
			local bestK, bestLen = nil, 0
			for k in pairs(byNorm) do
				if #k > bestLen and (key:find(k, 1, true) or k:find(key, 1, true)) then
					bestK, bestLen = k, #k
				end
			end
			if bestK then
				return byNorm[bestK], state.dungZoneByNorm[bestK], instID or (state.instIdByNorm and state.instIdByNorm[bestK])
			end
		end
	end
	return nil, nil, instID
end

function ns.CurrentPlayerDungeon()
	if not IsInInstance then return nil end
	local inInst, instType = IsInInstance()
	if issecretvalue(inInst) or issecretvalue(instType) or not inInst then return nil end
	if instType == "none" or instType == "pvp" or instType == "arena" then return nil end
	local rawName, rawType, _, _, _, _, _, rawInstID
	if GetInstanceInfo then
		rawName, rawType, _, _, _, _, _, rawInstID = GetInstanceInfo()
	end
	local instName = (type(rawName) == "string" and not issecretvalue(rawName) and rawName ~= "") and rawName or nil
	local instID = (type(rawInstID) == "number" and not issecretvalue(rawInstID) and rawInstID ~= 0) and rawInstID or nil
	local isRaid = (instType == "raid") or (not issecretvalue(rawType) and rawType == "raid")
	local drec, zMap, resolvedID = ns.MatchDungeon(instName, instID)
	local place = instID and FindPlaceByInstID(instID) or nil
	if not drec then
		if not (place or instName) then return nil end
		drec = {
			name = (place and place[2]) or instName,
			lo = (place and place[4]) or 0,
			hi = (place and (place[5] or place[4])) or 0,
			raid = (place and place[3] == true) or isRaid,
			pin = 0,
			quests = {},
		}
	end
	local finalID = resolvedID or instID
	return {
		dungeon = drec,
		zoneMap = zMap,
		instID = finalID,
		instName = instName or drec.name,
		bosses = ns.DungeonBosses(finalID, drec.name),
	}
end

local function RequestQuestRewardPreload(qid)
	if type(qid) ~= "number" or qid == 0 or issecretvalue(qid) or state.reqReward[qid] then return end
	state.reqReward[qid] = true
	state.pendReward[qid] = true
	ns.events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
	if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
		C_TaskQuest.RequestPreloadRewardData(qid)
	end
	if C_QuestLog.RequestLoadQuestByID then
		C_QuestLog.RequestLoadQuestByID(qid)
	end
end

local function BuildItemSubLabel(equipLoc, itemSubType, iLvl)
	local parts = {}
	if type(equipLoc) == "string" and not issecretvalue(equipLoc) and equipLoc ~= "" and _G[equipLoc] then
		parts[#parts + 1] = _G[equipLoc]
	end
	if type(itemSubType) == "string" and not issecretvalue(itemSubType) and itemSubType ~= "" and itemSubType ~= parts[1] then
		parts[#parts + 1] = itemSubType
	end
	if type(iLvl) == "number" and not issecretvalue(iLvl) and iLvl > 1 then
		parts[#parts + 1] = "Lvl " .. iLvl
	end
	return table.concat(parts, " - ")
end

function ns.ItemDisplay(itemID)
	local data = ns.DATA
	if type(itemID) ~= "number" or itemID <= 0 or issecretvalue(itemID) then return nil end
	local name, link, quality, iLvl, _, _, itemSubType, _, equipLoc, icon = C_Item.GetItemInfo(itemID)
	if type(name) == "string" and not issecretvalue(name) and name ~= "" then
		local q = (type(quality) == "number" and not issecretvalue(quality)) and quality or 1
		local safeLink = (type(link) == "string" and not issecretvalue(link)) and link or nil
		local safeIcon = (icon and not issecretvalue(icon)) and icon or 134400
		return name, QUALITY_HEX[q] or "ffffffff", safeIcon, BuildItemSubLabel(equipLoc, itemSubType, iLvl), safeLink
	end
	if C_Item.RequestLoadItemDataByID and not state.reqItem[itemID] then
		state.reqItem[itemID], state.pendItem[itemID] = true, true
		ns.events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
		C_Item.RequestLoadItemDataByID(itemID)
	end
	local _, _, subT, eqLoc, instIcon = C_Item.GetItemInfoInstant(itemID)
	local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
	local hex = (type(q) == "number" and not issecretvalue(q) and QUALITY_HEX[q]) or "ffe8d8a8"
	local fallbackName = (data and data.iname and data.iname[itemID]) or ("Item #" .. itemID)
	local safeIcon = (instIcon and not issecretvalue(instIcon)) and instIcon
		or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)) or 134400
	return fallbackName, hex, safeIcon, BuildItemSubLabel(eqLoc, subT, nil), nil
end

function ns.FormatRewardSummary(ids, maxShown)
	if not ids or #ids == 0 then return nil end
	local lim = maxShown or 2
	local out = {}
	for idx = 1, math.min(#ids, lim) do
		local name, hex = ns.ItemDisplay(ids[idx])
		if name then out[#out + 1] = ("|c%s[%s]|r"):format(hex, name) end
	end
	if #out == 0 then return nil end
	local txt = table.concat(out, ", ")
	if #ids > lim then txt = txt .. (" |cffbbbbbb+%d|r"):format(#ids - lim) end
	return txt
end

local function CollectLiveRewards(countFn, infoFn, qid, live)
	if not (countFn and infoFn) then return live end
	local n = countFn(qid)
	if type(n) == "number" and not issecretvalue(n) and n > 0 then
		for k = 1, n do
			local _, _, _, _, _, iid = infoFn(k, qid)
			if type(iid) == "number" and not issecretvalue(iid) and iid > 0 then
				live = live or {}; live[#live + 1] = iid
			end
		end
	end
	return live
end

function ns.PinRewards(i, preload)
	local data = ns.DATA
	if not (data and i) then return nil end
	local qid = data.qid[i] or 0
	local static = data.rew and data.rew[i]
	local saved = (qid ~= 0 and ns.db and ns.db.questRewards) and ns.db.questRewards[qid] or nil
	if qid ~= 0 and not saved and preload then
		RequestQuestRewardPreload(qid)
		if not HaveQuestRewardData or HaveQuestRewardData(qid) then
			local live = CollectLiveRewards(GetNumQuestLogChoices, GetQuestLogChoiceInfo, qid, nil)
			live = CollectLiveRewards(GetNumQuestLogRewards, GetQuestLogRewardInfo, qid, live)
			if live and ns.db and ns.db.questRewards then
				ns.db.questRewards[qid] = live
				saved = live
				wipe(state.mergedRew); wipe(state.worthCache)
			end
		end
	end
	if not saved then return static end
	if not static then return saved end
	if state.mergedRew[i] then return state.mergedRew[i] end
	local merged, seen = {}, {}
	for _, id in ipairs(static) do merged[#merged + 1] = id; seen[id] = true end
	for _, id in ipairs(saved) do
		if not seen[id] and #merged < 8 then merged[#merged + 1] = id; seen[id] = true end
	end
	state.mergedRew[i] = merged
	return merged
end

function ns.PinXP(i, preload)
	local data = ns.DATA
	if not (data and i) then return 0, true end
	local icon = data.cats[data.cat[i]] and data.cats[data.cat[i]].icon
	if icon ~= "quest" and icon ~= "repeatable" then return 0, true end
	if state.syncedDone and PinDone(i) then return 0, true end
	if not state.syncedDone and data.qid[i] ~= 0 and IsDone(data.qid[i]) then return 0, true end
	local pLvl = UnitLevel and UnitLevel("player")
	pLvl = (type(pLvl) == "number" and not issecretvalue(pLvl) and pLvl > 0) and pLvl or 1
	local maxLvl = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or MAX_PLAYER_LEVEL or 60
	maxLvl = (type(maxLvl) == "number" and not issecretvalue(maxLvl) and maxLvl > 0) and maxLvl or 60
	if pLvl >= maxLvl then return 0, true end

	local qid = data.qid[i] or 0
	if qid ~= 0 then
		if preload then RequestQuestRewardPreload(qid) end
		local cached = state.liveXP[qid]
		if not cached and preload and GetQuestLogRewardXP then
			local totalXp, baseXp = GetQuestLogRewardXP(qid)
			local v = (type(totalXp) == "number" and not issecretvalue(totalXp) and totalXp > 0 and totalXp)
				or (type(baseXp) == "number" and not issecretvalue(baseXp) and baseXp > 0 and baseXp) or nil
			if v then
				state.liveXP[qid] = v
				wipe(state.worthCache)
				cached = v
			end
		end
		if cached then return cached, true end
	end

	local lvl = data.lvl[i] or 0
	if lvl <= 0 then return 0, false end
	EnsureDungeonIndex()
	local base = BASE_XP[math.min(60, math.max(1, lvl))] or 0
	local mult = 1.0
	if state.dungQuestSet and state.dungQuestSet[i] then
		mult = 1.25
	elseif not (data.obj and data.obj[i]) then
		local t = (data.text[i] or ""):lower()
		if not (t:find("kill") or t:find("slay") or t:find("collect") or t:find("bring") or t:find("gather") or t:find("destroy") or t:find("defeat")) then
			mult = 0.25
		end
	end
	if pLvl > lvl + 5 then
		mult = mult * math.max(0.1, 1 - 0.2 * (pLvl - (lvl + 5)))
	end
	local raw = base * mult
	local step = raw >= 200 and 10 or 5
	return math.max(5, math.floor(raw / step + 0.5) * step), false
end

function ns.ChainWorth(root, chOpt)
	if not (ns.DATA and root) then return nil end
	local cached = state.worthCache[root]
	if cached then return cached end
	local ch = chOpt or BuildChain(root)
	local myNum = ch.num[root] or 1
	local remSteps, xp, exactXP = 0, 0, true
	local remRewards, allRewards, futureRewards, stepOfItem = {}, {}, {}, {}
	local seenRem, seenAll, seenFut = {}, {}, {}
	local ownSet = {}
	for _, id in ipairs(ns.PinRewards(root) or {}) do ownSet[id] = true end

	for n, s in ipairs(ch.steps) do
		local isDone = PinDone(s)
		if not isDone then
			remSteps = remSteps + 1
			local sxp, sexact = ns.PinXP(s)
			if sxp > 0 then
				xp = xp + sxp
				if not sexact then exactXP = false end
			end
		end
		for _, id in ipairs(ns.PinRewards(s) or {}) do
			if not stepOfItem[id] then stepOfItem[id] = n end
			if not seenAll[id] then seenAll[id] = true; allRewards[#allRewards + 1] = id end
			if not isDone and not seenRem[id] then seenRem[id] = true; remRewards[#remRewards + 1] = id end
			if n > myNum and not isDone and not ownSet[id] and not seenFut[id] then
				seenFut[id] = true
				futureRewards[#futureRewards + 1] = id
			end
		end
	end
	local res = {
		totalSteps = #ch.steps, remSteps = remSteps, xp = xp, exactXP = exactXP,
		rewards = #remRewards > 0 and remRewards or allRewards,
		futureRewards = futureRewards, stepOfItem = stepOfItem,
	}
	state.worthCache[root] = res
	return res
end

function ns.DungeonQuestEntries(instName)
	local data = ns.DATA
	if not (data and instName) then return nil end
	EnsureDungeonIndex()
	local key = NormDungKey(instName)
	local drec = state.dungByNorm[key]
	if not drec then
		for k, d in pairs(state.dungByNorm) do
			if key:find(k, 1, true) or k:find(key, 1, true) then drec = d; break end
		end
	end
	if not drec then return nil end
	if not state.syncedDone then ns.SyncDoneQuests() end
	local out, seenQ, seenT = {}, {}, {}
	for _, qi in ipairs(drec.quests or {}) do
		if ns.PassesPlayerFilter(qi) then
			local q = data.qid[qi]
			local tkey = data.title[qi] .. "\1" .. tostring(data.lvl[qi])
			if not ((q ~= 0 and seenQ[q]) or seenT[tkey]) then
				if q ~= 0 then seenQ[q] = true end
				seenT[tkey] = true
				local st = ns.PinQuestState(qi)
				local xp, exact = ns.PinXP(qi)
				out[#out + 1] = {
					pin = qi, id = q, name = data.title[qi], level = data.lvl[qi],
					state = st, done = st == "done", inLog = st == "log" or st == "ready",
					xpTxt = ns.FormatXP(xp, exact), rewShort = ns.FormatRewardSummary(ns.PinRewards(qi), 1),
				}
			end
		end
	end
	return out
end

function ns.DungeonContextForPin(pin, preferMap)
	local data = ns.DATA
	if not (data and data.dungeons and pin) then return nil, nil end
	local ch = BuildChain(pin)
	local function MatchInZone(zMap)
		local list = zMap and data.dungeons[zMap]
		if not list then return nil end
		for _, d in ipairs(list) do
			for _, qi in ipairs(d.quests or {}) do
				if qi == pin or (ch and ch.set and ch.set[qi]) then
					return d.name
				end
			end
		end
		return nil
	end
	if preferMap then
		local nm = MatchInZone(preferMap)
		if nm then return preferMap, nm end
	end
	for zMap in pairs(data.dungeons) do
		if zMap ~= preferMap then
			local nm = MatchInZone(zMap)
			if nm then return zMap, nm end
		end
	end
	return nil, nil
end

function ns.IsDungeonQuestPin(pin, zMap)
	local data = ns.DATA
	if not (data and pin) then return false end
	EnsureDungeonIndex()
	local ch = BuildChain(pin)
	if zMap and data.dungeons and data.dungeons[zMap] then
		for _, d in ipairs(data.dungeons[zMap]) do
			for _, qi in ipairs(d.quests or {}) do
				if qi == pin or (ch and ch.set and ch.set[qi]) then return true end
			end
		end
	end
	if state.dungQuestSet and state.dungQuestSet[pin] then return true end
	if ch and #ch.steps > 1 and state.dungQuestSet then
		for _, s in ipairs(ch.steps) do
			if state.dungQuestSet[s] then return true end
		end
	end
	return false
end

local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
local RAID_UNITS = {}
for idx = 1, 40 do RAID_UNITS[idx] = "raid" .. idx end

function ns.InvalidateGroupQuestCounts()
	wipe(state.groupQuestCount)
end

-- Total users in the player's current party or raid who have `questID` (0 when solo).
function ns.GroupQuestCount(questID)
	if ns.ShowGroupQuestCount and not ns.ShowGroupQuestCount() then return 0 end
	if not (IsInGroup and IsInGroup()) then return 0 end
	if issecretvalue(questID) or type(questID) ~= "number" or questID == 0 then return 0 end
	local cached = state.groupQuestCount[questID]
	if cached ~= nil then return cached end
	local total = 0
	local hasSelf = ns.QuestInLog(questID)
	if C_QuestLog and C_QuestLog.IsUnitOnQuest then
		if IsInRaid and IsInRaid() then
			local n = GetNumGroupMembers and GetNumGroupMembers() or 0
			local sawSelf = false
			if type(n) == "number" and not issecretvalue(n) then
				if n > 40 then n = 40 end
				for idx = 1, n do
					local u = RAID_UNITS[idx]
					local isSelf = UnitIsUnit and UnitIsUnit(u, "player")
					if not issecretvalue(isSelf) and isSelf == true then
						sawSelf = true
					else
						local on = C_QuestLog.IsUnitOnQuest(u, questID)
						if not issecretvalue(on) and on == true then
							total = total + 1
						end
					end
				end
			end
			if sawSelf then
				if hasSelf then total = total + 1 end
			elseif hasSelf and total < 1 then
				total = 1
			end
		else
			local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
			if type(n) == "number" and not issecretvalue(n) then
				if n > 4 then n = 4 end
				for idx = 1, n do
					local on = C_QuestLog.IsUnitOnQuest(PARTY_UNITS[idx], questID)
					if not issecretvalue(on) and on == true then
						total = total + 1
					end
				end
			end
			if hasSelf then
				total = total + 1
			end
		end
	elseif hasSelf then
		total = 1
	end
	state.groupQuestCount[questID] = total
	return total
end

function ns.GroupQuestMembers(questID)
	local units = {}
	if ns.ShowGroupQuestCount and not ns.ShowGroupQuestCount() then return units end
	if not (IsInGroup and IsInGroup()) then return units end
	if issecretvalue(questID) or type(questID) ~= "number" or questID == 0 then return units end
	local hasSelf = ns.QuestInLog(questID)
	if C_QuestLog and C_QuestLog.IsUnitOnQuest then
		if IsInRaid and IsInRaid() then
			local n = GetNumGroupMembers and GetNumGroupMembers() or 0
			local sawSelf = false
			if type(n) == "number" and not issecretvalue(n) then
				if n > 40 then n = 40 end
				for idx = 1, n do
					local u = RAID_UNITS[idx]
					local isSelf = UnitIsUnit and UnitIsUnit(u, "player")
					if not issecretvalue(isSelf) and isSelf == true then
						sawSelf = true
					else
						local on = C_QuestLog.IsUnitOnQuest(u, questID)
						if not issecretvalue(on) and on == true then
							units[#units + 1] = u
						end
					end
				end
			end
			if (sawSelf and hasSelf) or (not sawSelf and hasSelf and #units == 0) then
				table.insert(units, 1, "player")
			end
		else
			if hasSelf then
				units[1] = "player"
			end
			local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
			if type(n) == "number" and not issecretvalue(n) then
				if n > 4 then n = 4 end
				for idx = 1, n do
					local u = PARTY_UNITS[idx]
					local on = C_QuestLog.IsUnitOnQuest(u, questID)
					if not issecretvalue(on) and on == true then
						units[#units + 1] = u
					end
				end
			end
		end
	elseif hasSelf then
		units[1] = "player"
	end
	return units
end

function ns.GroupQuestCountForPin(pin, fallbackQid)
	if ns.ShowGroupQuestCount and not ns.ShowGroupQuestCount() then return 0, nil end
	if not (IsInGroup and IsInGroup()) then return 0, nil end
	if not issecretvalue(fallbackQid) and type(fallbackQid) == "number" and fallbackQid ~= 0 then
		return ns.GroupQuestCount(fallbackQid), fallbackQid
	end
	if not pin then return 0, nil end
	local q = ns.LogQuestIDForPin and ns.LogQuestIDForPin(pin) or nil
	if not q and ns.DATA and ns.DATA.qid then
		local dq = ns.DATA.qid[pin]
		if dq and dq ~= 0 then q = dq end
	end
	if not q then return 0, nil end
	return ns.GroupQuestCount(q), q
end

---------------------------------------------------------------------------
-- Cache Invalidation & Quest/Item Data Events
---------------------------------------------------------------------------
function ns.OnFactionsChanged()
	wipe(state.chainCache)
	wipe(state.worthCache)
	if ns.RevalidateFocusOnFilterChange then ns.RevalidateFocusOnFilterChange() end
	RecomputeInLog()
	if ns.Refresh then ns.Refresh() end
end

function ns.FlushQuestLogOnMapShow()
	local changed = false
	if state.qlogDirty then
		state.qlogDirty = false
		wipe(state.done)
		RecomputeInLog()
		if ns.SyncActiveChainStep then ns.SyncActiveChainStep() end
		changed = true
	elseif ns.UpdateFocus and ns.UpdateFocus() then
		changed = true
	end
	return changed
end

function ns.InitQuests()
	if state.questsInited then return end
	state.questsInited = true
	ns.events:RegisterEvent("PLAYER_ENTERING_WORLD")
	ns.events:RegisterEvent("QUEST_TURNED_IN")
	ns.events:RegisterEvent("QUEST_LOG_UPDATE")
	ns.events:RegisterEvent("PLAYER_LEVEL_UP")
	ns.events:RegisterEvent("GROUP_ROSTER_UPDATE")
	ns.events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
end

function ns.RefreshGroupQuestCounts()
	wipe(state.groupQuestCount)
	if ns.OnGroupQuestsChanged then ns.OnGroupQuestsChanged() end
	if ns.OnLayerChanged then ns.OnLayerChanged() end
end

local function QueueGroupQuestRefresh()
	wipe(state.groupQuestCount)
	if ns.ShowGroupQuestCount and not ns.ShowGroupQuestCount() then return end
	if state.groupRefreshQueued then return end
	state.groupRefreshQueued = true
	C_Timer.After(0.15, function()
		state.groupRefreshQueued = false
		ns.RefreshGroupQuestCounts()
	end)
end

function ns:GROUP_ROSTER_UPDATE()
	QueueGroupQuestRefresh()
end

function ns:UNIT_QUEST_LOG_CHANGED()
	if not (IsInGroup and IsInGroup()) then return end
	QueueGroupQuestRefresh()
end

local function ResetCharCompletionCache()
	wipe(state.done)
	wipe(state.worthCache)
	wipe(state.groupQuestCount)
	state.inLogStale = true
	if (not ns.ShowGroupQuestCount or ns.ShowGroupQuestCount()) and IsInGroup and IsInGroup() and ns.OnGroupQuestsChanged then
		ns.OnGroupQuestsChanged()
	end
	if WorldMapFrame and WorldMapFrame:IsVisible() then
		RecomputeInLog()
		if ns.UpdateFocus then ns.UpdateFocus(false) end
		if ns.Refresh then ns.Refresh() end
	else
		state.qlogDirty = true
	end
end

function ns:PLAYER_ENTERING_WORLD()
	if ns.OnInstanceChanged then ns.OnInstanceChanged() end
	ResetCharCompletionCache()
	-- Re-sync shortly after login/loading screen in case the server's per-character quest bitset finishes hydrating late.
	C_Timer.After(1.5, ResetCharCompletionCache)
end

local function QueueItemDisplayRefresh()
	if state.itemRefreshQueued then return end
	state.itemRefreshQueued = true
	C_Timer.After(0.12, function()
		state.itemRefreshQueued = false
		if ns.RefreshHoverTooltip then ns.RefreshHoverTooltip() end
		local stitch = ns.StitchModule and ns.StitchModule()
		if stitch and stitch.RefreshBossTooltip then stitch.RefreshBossTooltip() end
		if ns.RenderPanelRows then ns.RenderPanelRows() end
	end)
end

local function QueueRewardRefresh()
	if state.rewardRefreshQueued then return end
	state.rewardRefreshQueued = true
	C_Timer.After(0.12, function()
		state.rewardRefreshQueued = false
		wipe(state.worthCache)
		if ns.RefreshHoverTooltip then ns.RefreshHoverTooltip() end
		local stitch = ns.StitchModule and ns.StitchModule()
		if stitch and stitch.RefreshSideQuests then stitch.RefreshSideQuests() end
		if ns.OnLayerChanged then ns.OnLayerChanged() end
	end)
end

function ns:ITEM_DATA_LOAD_RESULT(itemID, success)
	if not (itemID and not issecretvalue(itemID) and state.pendItem[itemID]) then return end
	state.pendItem[itemID] = nil
	if not next(state.pendItem) then ns.events:UnregisterEvent("ITEM_DATA_LOAD_RESULT") end
	if success and not issecretvalue(success) then
		QueueItemDisplayRefresh()
	end
end

function ns:QUEST_DATA_LOAD_RESULT(questID, success)
	if not (questID and not issecretvalue(questID)) then return end
	if not state.pendReward[questID] then return end
	state.pendReward[questID] = nil
	if not next(state.pendReward) then
		ns.events:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
	end
	if success then QueueRewardRefresh() end
end

function ns:QUEST_TURNED_IN(questID)
	if questID and not issecretvalue(questID) then
		BuildQuestIndices()
		if daves_mapCharDB and daves_mapCharDB.doneQuests then
			daves_mapCharDB.doneQuests[questID] = true
		end
		state.recentTurnIn[questID] = GetTime()
		wipe(state.done)
		state.done[questID] = true
		RecomputeInLog()
		if ns.SyncActiveChainStep then ns.SyncActiveChainStep() end
	end
	if ns.Refresh then ns.Refresh() end
end

function ns:PLAYER_LEVEL_UP()
	wipe(state.liveXP)
	wipe(state.worthCache)
	if ns.RefreshHoverTooltip then ns.RefreshHoverTooltip() end
	if ns.Refresh then ns.Refresh() end
end

function ns:QUEST_LOG_UPDATE()
	state.inLogStale = true
	wipe(state.done)
	wipe(state.worthCache)
	wipe(state.groupQuestCount)
	if WorldMapFrame and WorldMapFrame:IsVisible() then
		if not state.qlogPending then
			state.qlogPending = true
			C_Timer.After(0.15, function()
				state.qlogPending = false
				state.qlogDirty = false
				local changed = RecomputeInLog()
				if ns.SyncActiveChainStep and ns.SyncActiveChainStep() then changed = true end
				if changed then
					if ns.Refresh then ns.Refresh() end
				elseif ns.OnLayerChanged then
					ns.OnLayerChanged()
				end
			end)
		end
	else
		state.qlogDirty = true
	end
end
