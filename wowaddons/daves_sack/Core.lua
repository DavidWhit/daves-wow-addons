-- daves_sack / Core.lua
-- API helpers, item categorisation and saved settings for WoW: Forever (16001).

local ADDON, ns = ...

ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

---------------------------------------------------------------------------
-- API helpers
---------------------------------------------------------------------------
local C_Container, C_Item = C_Container, C_Item

ns.GetNumSlots  = C_Container.GetContainerNumSlots
ns.GetCooldown  = C_Container.GetContainerItemCooldown
ns.SortBags     = C_Container.SortBags
ns.GetQuestInfo = C_Container.GetContainerItemQuestInfo

local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetQualityByID     = C_Item.GetItemQualityByID
local GetItemInfo        = C_Item.GetItemInfo
local GetSlotInfo        = C_Container.GetContainerItemInfo
local match, lower, select = string.match, string.lower, select

-- Items whose full info isn't cached yet; UI re-categorises them when it arrives.
ns.waiting = {}

-- Reads one bag slot into a reusable record table. Returns true if the item
-- identity changed, i.e. the slot needs re-categorising / re-layout rather than
-- just a visual refresh.
function ns.ReadSlot(bag, slot, rec)
	local tex, count, locked, quality, link, id, bound
	local i = GetSlotInfo(bag, slot)
	if i then
		tex, count, locked, quality, link, id, bound = i.iconFileID, i.stackCount, i.isLocked, i.quality, i.hyperlink, i.itemID, i.isBound
	end

	if id and (not quality or quality < 0) then
		quality = (GetQualityByID and GetQualityByID(id)) or (link and select(3, GetItemInfo(link))) or 1
	end

	local changed = rec.id ~= id or rec.quality ~= quality
	if link ~= rec.link then                 -- e.g. "of the Bear" variants swapping slots
		local n = link and match(link, "%[(.-)%]")
		rec.name = n and lower((n:gsub("|A.-|a", ""):gsub("|T.-|t", ""))) or nil
	end
	rec.texture, rec.count, rec.locked, rec.link, rec.bound = tex, count or 0, locked, link, bound and true or false
	if changed then
		rec.id, rec.quality = id, quality
		if id then
			local _, _, _, _, _, classID, subclassID = GetItemInfoInstant(id)
			rec.classID, rec.subclassID = classID, subclassID
		else
			rec.classID, rec.subclassID = nil, nil
		end
	end
	return changed
end

-- Fallback icon and quality for a cursor item when it didn't come from a scanned bag slot.
function ns.ItemSummary(id, link)
	local icon = id and GetItemInfoInstant and select(5, GetItemInfoInstant(id)) or nil
	local quality = id and ((GetQualityByID and GetQualityByID(link or id)) or (link and GetItemInfo and select(3, GetItemInfo(link)))) or 1
	return icon, quality
end

---------------------------------------------------------------------------
-- Categories (display order)
---------------------------------------------------------------------------
local EQUIP, CONSUME, PROF, CAMP, REAGENT, QUEST, KEYS, MISC, JUNK = 1, 2, 3, 4, 5, 6, 7, 8, 9
ns.CATEGORY_NAMES = { "Equipment", "Consumables", "Professions", "Camping", "Reagents", "Quest", "Keys", "Miscellaneous", "Junk" }
ns.NUM_CATEGORIES = #ns.CATEGORY_NAMES

-- Enum.ItemClass values have been stable since vanilla.
local CLASS_TO_CAT = {
	[2] = EQUIP, [4] = EQUIP,               -- weapon, armor
	[0] = CONSUME, [8] = CONSUME,           -- consumable, item enhancement
	[9] = PROF, [19] = PROF,                -- recipes, profession tools & gear
	[5] = REAGENT, [7] = REAGENT,           -- reagents, trade goods (cloth, ore, herbs…)
	[12] = QUEST,
}

-- Profession tools that the game files as weapons or junk.
local PROFESSION_TOOLS = {
	[2901] = true,  -- Mining Pick
	[7005] = true,  -- Skinning Knife
	[5956] = true,  -- Blacksmith Hammer
	[6219] = true,  -- Arclight Spanner
	[10498] = true, -- Gyromatic Micro-Adjustor
	[6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true, -- Runed Enchanting Rods
	[9149] = true,  -- Philosopher's Stone
	[20815] = true, -- Jeweler's Kit
	[40772] = true, -- Gnomish Army Knife
	[6256] = true,  -- Fishing Pole
}
local FISHING_POLE = 20  -- weapon subclass

-- Reagents are split into profession groups by their trade-goods subclass
-- (Enum.ItemTradeGoodsSubclass).
--
-- Primary professions always win over secondary ones (Cooking, First Aid,
-- Fishing): linen is Tailoring, not First Aid; a fish Alchemy turns into oil is
-- Alchemy, not Cooking. Secondary groups only get what no primary uses, and
-- they're listed after every primary group.
ns.CAT_REAGENT, ns.CAT_CONSUME, ns.CAT_QUEST = REAGENT, CONSUME, QUEST

-- Sub-category ids are global; a section only ever shows its own. Their order
-- here is the order they're drawn in.
ns.GROUP_NAMES = {
	-- Reagents: primary professions…
	"Tailoring", "Leatherworking", "Mining", "Herbalism", "Alchemy", "Enchanting",
	"Engineering", "Jewelcrafting", "Inscription", "Elemental",
	-- …then secondary professions, then the rest
	"Cooking", "Other Reagents",
	-- Consumables
	"Alchemy", "Food & Drink", "First Aid", "Scrolls", "Enhancements", "Other Consumables",
}
local G_TAILOR, G_LEATHER, G_MINING, G_HERB, G_ALCHEMY, G_ENCHANT, G_ENGI, G_JC, G_INSCR, G_ELEM, G_COOK =
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
local OTHER_GROUP = 12
local C_ALCHEMY, C_FOOD, C_FIRSTAID, C_SCROLL, C_ENHANCE, C_OTHER = 13, 14, 15, 16, 17, 18
-- Consumable groups that can be switched off one by one in Settings (their
-- items then join "Other Consumables").
ns.CONSUMABLE_GROUPS = { C_ALCHEMY, C_FOOD, C_FIRSTAID, C_SCROLL, C_ENHANCE }
function ns.OtherGroupFor(g) return g <= OTHER_GROUP and OTHER_GROUP or C_OTHER end

local TRADEGOODS_TO_GROUP = {
	[5] = G_TAILOR,                   -- cloth (also First Aid → Tailoring wins)
	[6] = G_LEATHER,                  -- leather
	[7] = G_MINING,                   -- metal & stone
	[9] = G_HERB,                     -- herbs
	[12] = G_ENCHANT,                 -- enchanting
	[1] = G_ENGI, [2] = G_ENGI, [3] = G_ENGI, [17] = G_ENGI, -- parts, explosives, devices
	[4] = G_JC,                       -- jewelcrafting
	[16] = G_INSCR,                   -- inscription
	[10] = G_ELEM,                    -- elemental
	[8] = G_COOK,                     -- meat (secondary: only if no primary claims it)
}

-- Items the game files under a secondary profession that a primary also uses.
local PRIMARY_OVERRIDE = {
	[6358] = G_ALCHEMY,   -- Oily Blackmouth  (Blackmouth Oil)
	[6359] = G_ALCHEMY,   -- Firefin Snapper  (Fire Oil)
	[13422] = G_ALCHEMY,  -- Stonescale Eel   (Stonescale Oil)
	-- cooking-only vendor goods the game files as generic trade goods
	[2678] = G_COOK,      -- Mild Spices
	[2692] = G_COOK,      -- Hot Spices
	[3713] = G_COOK,      -- Soothing Spices
	[30817] = G_COOK,     -- Simple Flour
}

local function ReagentGroup(rec)
	local o = PRIMARY_OVERRIDE[rec.id]
	if o then return o end
	if rec.classID == 7 then return TRADEGOODS_TO_GROUP[rec.subclassID or -1] or OTHER_GROUP end
	return OTHER_GROUP
end

-- Consumables by Enum.ItemConsumableSubclass.
local CONSUMABLE_TO_GROUP = {
	[1] = C_ALCHEMY, [2] = C_ALCHEMY, [3] = C_ALCHEMY,  -- potions, elixirs, flasks & phials
	[5] = C_FOOD, [7] = C_FIRSTAID, [4] = C_SCROLL, [6] = C_ENHANCE,   -- 7 = bandages
}
-- First Aid: what First Aid makes, i.e. bandages (above) plus anti-venoms.
-- The cloth it uses (linen, wool…) stays under Reagents → Tailoring.
local FIRST_AID_ITEMS = {
	[6452] = true,    -- Anti-Venom
	[6453] = true,    -- Strong Anti-Venom
	[19440] = true,   -- Powerful Anti-Venom
}
local FIRST_AID_WORDS = { "bandage", "anti-venom", "antivenom" }
-- Older item data files many consumables as plain "Consumable"
-- (subclass 0); for those, fall back to the item's name / use-effect.
local ALCHEMY_WORDS = { "potion", "elixir", "flask", "phial", "draught", "philter" }
local GetItemSpell = C_Item.GetItemSpell
local FOOD_SPELLS = { Food = true, Drink = true, ["Food & Drink"] = true, Refreshment = true }

local function ConsumableGroup(rec)
	if rec.classID == 8 then return C_ENHANCE end
	if FIRST_AID_ITEMS[rec.id] then return C_FIRSTAID end
	local name = rec.name or ""
	for i = 1, #FIRST_AID_WORDS do                      -- before subclasses: an anti-venom
		if name:find(FIRST_AID_WORDS[i], 1, true) then return C_FIRSTAID end   -- is First Aid, not a potion
	end
	local g = CONSUMABLE_TO_GROUP[rec.subclassID or -1]
	if g then return g end
	for i = 1, #ALCHEMY_WORDS do
		if name:find(ALCHEMY_WORDS[i], 1, true) then return C_ALCHEMY end
	end
	local spell = GetItemSpell and GetItemSpell(rec.id)
	if spell and FOOD_SPELLS[spell] then return C_FOOD end
	return C_OTHER
end

-- WoW: Forever camping. Its item data has no camping item type (checked in
-- Blizzard's Forever UI source, 1.60.1), so camping gear is recognised by item
-- ID (campfire materials) and by name: camp objects, blueprints, sleeping bags.
local CAMPING_ITEMS = { [4470] = true, [4471] = true }   -- Simple Wood, Flint and Tinder
local CAMPING_WORDS = {
	"%f[%a]camps?%f[%A]", "%f[%a]camping", "campfire", "sleeping bag", "blueprint",
	"mana well", "fish bowl", "lodestone", "incense candle", "enchanted lute", "faction banner",
	"greenhouse", "seed hybridizer", "rock garden", "molten foundry", "fishing rack",
	"fermenter", "alchemy laboratory", "master forge", "first aid kit",
}
local find = string.find
local function IsCamping(rec)
	if CAMPING_ITEMS[rec.id] then return true end
	local c = rec.classID
	if c == 2 or c == 4 or c == 12 then return false end   -- never weapons, armor or quest items
	local name = rec.name
	if not name then return false end
	for i = 1, #CAMPING_WORDS do
		if find(name, CAMPING_WORDS[i]) then return true end
	end
	return false
end

-- The reagent bag slot (bag 5 on Forever: Enum.BagIndex.ReagentBag).
local REAGENT_BAGS = NUM_REAGENTBAG_SLOTS or 0
ns.REAGENT_BAG = REAGENT_BAGS > 0 and ((Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or (NUM_BAG_SLOTS or 4) + 1) or nil

local function IsReagentBag(bag)
	local first = (NUM_BAG_SLOTS or 4) + 1
	return bag >= first and bag < first + REAGENT_BAGS
end
ns.IsReagentBag = IsReagentBag

-- Can this item go into a bag of that family? Same test the game applies for
-- quivers, herb bags and the reagent bag: the item's family bits must overlap
-- the bag's (C_Item.GetItemFamily / C_Container.GetContainerNumFreeSlots, both
-- documented on Forever). A plain bag (family 0) takes anything.
local GetItemFamily = C_Item.GetItemFamily
local band = bit and bit.band
function ns.FitsBagFamily(itemID, bagFamily)
	if (bagFamily or 0) == 0 then return true end
	if not (itemID and GetItemFamily and band) then return false end
	local fam = GetItemFamily(itemID)
	return fam ~= nil and band(fam, bagFamily) ~= 0
end

function ns.Categorize(bag, slot, rec)
	local id = rec.id
	if not id then return nil end
	-- Keys shows the keyring only. A key in an ordinary bag is sorted like anything else there (Quest, Junk…):
	-- the section is a view of the keyring, never a reason to move an item into or out of it.
	if bag == KEYRING_CONTAINER then return KEYS end
	if rec.quality == 0 then return JUNK end
	if ns.GetQuestInfo then
		local q = ns.GetQuestInfo(bag, slot)
		if q and (q.isQuestItem or q.questID) then return QUEST end
	end
	if IsCamping(rec) then return CAMP end
	if PROFESSION_TOOLS[id] or (rec.classID == 2 and rec.subclassID == FISHING_POLE) then return PROF end
	if rec.classID == 5 and (rec.subclassID or 0) ~= 0 then return MISC end   -- keystones, context tokens
	if IsReagentBag(bag) then return REAGENT, ReagentGroup(rec) end

	local cat = CLASS_TO_CAT[rec.classID or -1]
	if cat == REAGENT then return REAGENT, ReagentGroup(rec) end
	if cat == CONSUME then return CONSUME, ConsumableGroup(rec) end
	if cat then return cat end

	-- Anything else that a recipe uses (e.g. vendor-bought reagents filed as misc)
	local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, isCraftingReagent = GetItemInfo(id)
	if not name then ns.waiting[id] = true end
	if isCraftingReagent then return REAGENT, OTHER_GROUP end
	return MISC
end

---------------------------------------------------------------------------
-- Which containers make up "your bags" on this client
---------------------------------------------------------------------------
function ns.BuildBagList(t)
	for i = #t, 1, -1 do t[i] = nil end
	local bags = NUM_BAG_SLOTS or 4
	for i = 0, bags do t[#t + 1] = i end
	for i = 1, (NUM_REAGENTBAG_SLOTS or 0) do t[#t + 1] = bags + i end   -- reagent bag
	if KEYRING_CONTAINER and HasKey and HasKey() then t[#t + 1] = KEYRING_CONTAINER end
	return t
end

---------------------------------------------------------------------------
-- Auction House local price cache & item tooltips
---------------------------------------------------------------------------
do
	local floor, max, min, format = math.floor, math.max, math.min, string.format
	local Now = GetServerTime or time
	local issecretvalue = issecretvalue
	local BATCH_SIZE = 50           -- max ItemKeys per C_AuctionHouse.SearchForItemKeys call
	local REPLICATE_COOLDOWN = 900  -- 15-minute server throttle on C_AuctionHouse.ReplicateItems
	local REPLICATE_SLICE = 500     -- auctions processed per 0.03s background tick

	function ns.FormatAge(ts)
		if not (ts and Now) then return nil end
		local d = max(0, Now() - ts)
		if d < 60 then return "just now" end
		if d < 3600 then return format("%dm ago", floor(d / 60)) end
		if d < 86400 then return format("%dh ago", floor(d / 3600)) end
		return format("%dd ago", floor(d / 86400))
	end

	local ahEvents
	local ahOpen, wantReplicate = false, false
	local pendingBatches, batchIndex = nil, 0
	local replicateTicker = nil
	local batchMin, repBuyMin, repBidMin = {}, {}, {}

	local function NotifyUpdated(changed)
		if changed and Now then
			ns.db.ahUpdated = Now()
		end
		if ns.RefreshAuctionFooter then ns.RefreshAuctionFooter() end
	end

	local function FinishScan(changed, showComplete)
		ns.ahScanning = false
		if showComplete and GetTime then
			ns.ahScanProgress = 100
			ns.ahScanDoneUntil = GetTime() + 1.2
			NotifyUpdated(changed)
			C_Timer.After(1.25, function()
				if not ns.ahScanning and ns.ahScanDoneUntil and GetTime() >= ns.ahScanDoneUntil - 0.05 then
					ns.ahScanDoneUntil = nil
					ns.ahScanProgress = nil
					if ns.RefreshAuctionFooter then ns.RefreshAuctionFooter() end
				end
			end)
		else
			ns.ahScanDoneUntil = nil
			ns.ahScanProgress = nil
			NotifyUpdated(changed)
		end
	end

	local function SetCachedPrice(prices, id, price)
		if not (id and id > 0 and price and price > 0) then return false end
		if prices[id] == nil then
			ns.ahCachedCount = (ns.ahCachedCount or 0) + 1
		end
		prices[id] = price
		return true
	end

	local function CommitBatch(prices, minTbl, fallbackTbl)
		local any = false
		for id, price in pairs(minTbl) do
			if SetCachedPrice(prices, id, price) then any = true end
		end
		if fallbackTbl then
			for id, price in pairs(fallbackTbl) do
				if not minTbl[id] and SetCachedPrice(prices, id, price) then any = true end
			end
		end
		return any
	end

	local function CommitPartialBatch(prices, minTbl, fallbackTbl)
		local any = false
		for id, price in pairs(minTbl) do
			local cur = prices[id]
			if (not cur or price < cur) and SetCachedPrice(prices, id, price) then any = true end
		end
		if fallbackTbl then
			for id, price in pairs(fallbackTbl) do
				if not minTbl[id] and not prices[id] and SetCachedPrice(prices, id, price) then any = true end
			end
		end
		return any
	end

	local function HasPendingBatches()
		return pendingBatches ~= nil and batchIndex <= #pendingBatches
	end

	local function ClearPendingBatches()
		pendingBatches, batchIndex = nil, 0
	end

	local function StopReplicateTicker(commitPartial)
		if ahEvents then
			pcall(ahEvents.UnregisterEvent, ahEvents, "REPLICATE_ITEM_LIST_UPDATE")
		end
		if replicateTicker then
			replicateTicker:Cancel()
			replicateTicker = nil
			if commitPartial and ns.db and ns.db.ahPrices then
				local changed = CommitPartialBatch(ns.db.ahPrices, repBuyMin, repBidMin)
				wipe(repBuyMin); wipe(repBidMin)
				FinishScan(changed, false)
				return
			end
		end
		wipe(repBuyMin); wipe(repBidMin)
		ns.ahScanProgress = nil
		ns.ahScanDoneUntil = nil
	end

	local function UserStartedSearch()
		local f = AuctionHouseFrame
		if f and f.activeSearches then
			local allBids = AuctionHouseSearchContext and AuctionHouseSearchContext.AllBids
			for k in pairs(f.activeSearches) do
				if not (allBids and k == allBids) then
					return true
				end
			end
		end
		return false
	end

	local function RecordBrowseList(list)
		if not (list and ns.db and ns.db.ahPrices) then return end
		wipe(batchMin)
		for i = 1, #list do
			local r = list[i]
			local key = r and r.itemKey
			local id = key and key.itemID
			local p = r and r.minPrice
			if id and id > 0 and p and p > 0 and (r.totalQuantity or 0) > 0 then
				local cur = batchMin[id]
				if not cur or p < cur then batchMin[id] = p end
			end
		end
		local changed = CommitBatch(ns.db.ahPrices, batchMin)
		if not HasPendingBatches() and not wantReplicate and not replicateTicker then
			if ns.ahScanning then
				FinishScan(changed, true)
				return
			end
		elseif ns.ahScanning and pendingBatches and #pendingBatches > 0 then
			local done = max(1, batchIndex - 1)
			local totalSteps = #pendingBatches + (wantReplicate and 4 or 0)
			ns.ahScanProgress = floor((done / totalSteps) * 100 + 0.5)
		end
		if changed or not ns.ahScanning then NotifyUpdated(changed) end
	end

	local function RecordCommodityResults(itemID)
		local A = C_AuctionHouse
		if not (A and itemID and itemID > 0 and ns.db and ns.db.ahPrices) then return end
		local n = A.GetNumCommoditySearchResults and A.GetNumCommoditySearchResults(itemID) or 0
		local best
		for i = 1, n do
			local r = A.GetCommoditySearchResultInfo(itemID, i)
			local p = r and r.unitPrice
			if p and p > 0 and (r.quantity or 0) > 0 and (not best or p < best) then
				best = p
			end
		end
		if best and SetCachedPrice(ns.db.ahPrices, itemID, best) then
			NotifyUpdated(true)
		end
	end

	local function RecordItemResults(itemKey)
		local A = C_AuctionHouse
		local id = itemKey and itemKey.itemID
		if not (A and id and id > 0 and ns.db and ns.db.ahPrices) then return end
		local n = A.GetNumItemSearchResults and A.GetNumItemSearchResults(itemKey) or 0
		local bestBuyout, bestBid
		for i = 1, n do
			local r = A.GetItemSearchResultInfo(itemKey, i)
			local qty = r and r.quantity or 0
			if qty > 0 then
				local buyout = r.buyoutAmount
				if buyout and buyout > 0 then
					local unit = floor(buyout / qty + 0.5)
					if unit > 0 and (not bestBuyout or unit < bestBuyout) then bestBuyout = unit end
				else
					local bid = (r.bidAmount and r.bidAmount > 0) and r.bidAmount or r.minBid
					if bid and bid > 0 then
						local unit = floor(bid / qty + 0.5)
						if unit > 0 and (not bestBid or unit < bestBid) then bestBid = unit end
					end
				end
			end
		end
		local best = bestBuyout or bestBid
		if best and SetCachedPrice(ns.db.ahPrices, id, best) then
			NotifyUpdated(true)
		end
	end

	-- Slices GetReplicateItemInfo across background ticks after unregistering
	-- REPLICATE_ITEM_LIST_UPDATE so uncached-item callbacks never re-trigger the scan.
	local function StartReplicateSlice()
		if ahEvents then
			pcall(ahEvents.UnregisterEvent, ahEvents, "REPLICATE_ITEM_LIST_UPDATE")
		end
		local A = C_AuctionHouse
		if not (ahOpen and A and A.GetNumReplicateItems and A.GetReplicateItemInfo and ns.db and ns.db.ahPrices) then
			ns.ahScanProgress = nil
			ns.ahScanning = false
			NotifyUpdated(false)
			return
		end
		local total = A.GetNumReplicateItems() or 0
		if total <= 0 then
			ns.ahScanProgress = nil
			ns.ahScanning = false
			NotifyUpdated(false)
			return
		end
		if replicateTicker then replicateTicker:Cancel() end
		wipe(repBuyMin); wipe(repBidMin)
		local idx = 1
		ns.ahScanning = true
		ns.ahScanDoneUntil = nil
		ns.ahScanProgress = 25
		NotifyUpdated(false)

		replicateTicker = C_Timer.NewTicker(0.03, function()
			if not (ahOpen and A and ns.db and ns.db.ahPrices and ns.db.showAuctionPrices ~= false)
				or (AuctionHouseFrame and not AuctionHouseFrame:IsShown()) then
				StopReplicateTicker(true)
				return
			end
			local n = A.GetNumReplicateItems() or 0
			if n <= 0 then
				StopReplicateTicker(true)
				return
			end
			local stop = min(n, idx + REPLICATE_SLICE - 1)
			for i = idx, stop do
				local _, _, count, _, _, _, _, minBid, _, buyoutPrice, bidAmount, _, _, _, _, saleStatus, itemID = A.GetReplicateItemInfo(i)
				if (not saleStatus or saleStatus == 0) and itemID and itemID > 0 and count and count > 0 then
					if buyoutPrice and buyoutPrice > 0 then
						local unit = floor(buyoutPrice / count + 0.5)
						if unit > 0 then
							local cur = repBuyMin[itemID]
							if not cur or unit < cur then repBuyMin[itemID] = unit end
						end
					else
						local bid = (bidAmount and bidAmount > 0) and bidAmount or minBid
						if bid and bid > 0 then
							local unit = floor(bid / count + 0.5)
							if unit > 0 then
								local cur = repBidMin[itemID]
								if not cur or unit < cur then repBidMin[itemID] = unit end
							end
						end
					end
				end
			end
			idx = stop + 1
			if idx > n then
				if replicateTicker then replicateTicker:Cancel(); replicateTicker = nil end
				local changed = CommitBatch(ns.db.ahPrices, repBuyMin, repBidMin)
				wipe(repBuyMin); wipe(repBidMin)
				if Now then ns.db.ahLastReplicate = Now() end
				FinishScan(changed, true)
			else
				local pct = 25 + floor((stop / max(1, n)) * 75 + 0.5)
				if pct ~= ns.ahScanProgress then
					ns.ahScanProgress = pct
					if ns.RefreshAuctionFooter then ns.RefreshAuctionFooter() end
				end
			end
		end)
	end

	local function StepAutoScan()
		local A = C_AuctionHouse
		if not (ahOpen and A and ns.db and ns.db.showAuctionPrices ~= false) then
			ClearPendingBatches()
			wantReplicate = false
			StopReplicateTicker(false)
			if ns.ahScanning then
				ns.ahScanning = false
				NotifyUpdated(false)
			end
			return
		end
		if A.IsThrottledMessageSystemReady and not A.IsThrottledMessageSystemReady() then return end

		if HasPendingBatches() then
			if (A.HasFavorites and A.HasFavorites()) or UserStartedSearch() or not A.SearchForItemKeys then
				ClearPendingBatches()
			else
				local totalBatches = #pendingBatches
				local curBatch = batchIndex
				local batch = pendingBatches[batchIndex]
				batchIndex = batchIndex + 1
				if not HasPendingBatches() then
					ClearPendingBatches()
				end
				if batch and #batch > 0 then
					ns.ahScanning = true
					ns.ahScanDoneUntil = nil
					local totalSteps = totalBatches + (wantReplicate and 4 or 0)
					ns.ahScanProgress = max(10, floor(((curBatch - 0.5) / max(1, totalSteps)) * 100 + 0.5))
					NotifyUpdated(false)
					local sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
					pcall(A.SearchForItemKeys, batch, { { sortOrder = sortOrder, reverseSort = false } })
					C_Timer.After(5, function()
						if ns.ahScanning and not HasPendingBatches() and not wantReplicate and not replicateTicker then
							FinishScan(false, true)
						end
					end)
					return   -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY will advance to next batch or wantReplicate
				end
			end
		end

		if wantReplicate then
			wantReplicate = false
			if A.ReplicateItems and ahEvents then
				ns.ahScanning = true
				ns.ahScanDoneUntil = nil
				ns.ahScanProgress = 20
				NotifyUpdated(false)
				if Now then ns.db.ahLastReplicate = Now() end
				pcall(ahEvents.RegisterEvent, ahEvents, "REPLICATE_ITEM_LIST_UPDATE")
				pcall(A.ReplicateItems)
				C_Timer.After(15, function()
					if ns.ahScanning and not replicateTicker and not HasPendingBatches() then
						pcall(ahEvents.UnregisterEvent, ahEvents, "REPLICATE_ITEM_LIST_UPDATE")
						FinishScan(false, false)
					end
				end)
				return
			end
		end

		if ns.ahScanning and not replicateTicker then
			FinishScan(false, true)
		end
	end

	local function StartAutoScan()
		local A = C_AuctionHouse
		if not (ahOpen and A and ns.db and ns.db.showAuctionPrices ~= false) then return end
		if not (A.HasFavorites and A.HasFavorites()) and not UserStartedSearch()
			and A.SearchForItemKeys and A.MakeItemKey and ns.BuildTradeableItemKeys then
			local keys = ns.BuildTradeableItemKeys(A.MakeItemKey)
			if keys and #keys > 0 then
				pendingBatches = {}
				for i = 1, #keys, BATCH_SIZE do
					local b = {}
					for j = i, min(#keys, i + BATCH_SIZE - 1) do
						b[#b + 1] = keys[j]
					end
					pendingBatches[#pendingBatches + 1] = b
				end
				batchIndex = 1
			end
		end
		StepAutoScan()
	end

	local function TooltipStackCount(tooltip, itemID)
		local owner = tooltip.GetOwner and tooltip:GetOwner()
		if not owner then return 1 end
		if owner.fbRec and owner.fbRec.id == itemID then
			return owner.fbRec.count or 1
		end
		if owner.GetBagID and owner.GetID then
			local bag, slot = owner:GetBagID(), owner:GetID()
			if type(bag) == "number" and type(slot) == "number"
				and (not issecretvalue or (not issecretvalue(bag) and not issecretvalue(slot))) then
				local info = GetSlotInfo(bag, slot)
				if info and info.stackCount then return info.stackCount end
			end
		end
		local c = owner.count
		if type(c) == "number" and (not issecretvalue or not issecretvalue(c)) and c > 1 then
			return c
		end
		return 1
	end

	local function OnItemTooltip(tooltip, data)
		if not (ns.db and ns.db.showAuctionPrices ~= false and ns.db.ahPrices and ns.MoneyString) then return end
		if not (tooltip and tooltip.AddDoubleLine and data) then return end
		local id = data.id
		if not id or (issecretvalue and issecretvalue(id)) or type(id) ~= "number" then return end
		local unitPrice = ns.db.ahPrices[id]
		if not unitPrice or unitPrice <= 0 then return end
		local count = TooltipStackCount(tooltip, id)
		if count and count > 1 then
			tooltip:AddDoubleLine("Auction Price (each)", ns.MoneyString(unitPrice), 1, 0.82, 0, 1, 1, 1)
			tooltip:AddDoubleLine(format("Auction Price (x%d)", count), ns.MoneyString(unitPrice * count), 1, 0.82, 0, 1, 1, 1)
		else
			tooltip:AddDoubleLine("Auction Price", ns.MoneyString(unitPrice), 1, 0.82, 0, 1, 1, 1)
		end
	end

	function ns.InitAuctionCache()
		local prices = ns.db.ahPrices
		local cnt = 0
		for _ in pairs(prices) do cnt = cnt + 1 end
		ns.ahCachedCount = cnt

		ahEvents = CreateFrame("Frame")
		for _, e in ipairs({
			"AUCTION_HOUSE_SHOW",
			"AUCTION_HOUSE_CLOSED",
			"AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
			"AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
			"COMMODITY_SEARCH_RESULTS_UPDATED",
			"ITEM_SEARCH_RESULTS_UPDATED",
			"AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
		}) do
			pcall(ahEvents.RegisterEvent, ahEvents, e)
		end
		ahEvents:SetScript("OnEvent", function(_, event, arg1)
			if event == "AUCTION_HOUSE_SHOW" then
				ahOpen = true
				ClearPendingBatches()
				StopReplicateTicker(false)
				wantReplicate = (ns.db and ns.db.showAuctionPrices ~= false)
					and (not Now or (Now() - (ns.db.ahLastReplicate or 0)) >= REPLICATE_COOLDOWN)
				C_Timer.After(0.25, StartAutoScan)
			elseif event == "AUCTION_HOUSE_CLOSED" then
				ahOpen = false
				wantReplicate = false
				ClearPendingBatches()
				StopReplicateTicker(true)
				if ns.ahScanning then
					ns.ahScanning = false
					NotifyUpdated(false)
				end
			elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
				if ahOpen and (HasPendingBatches() or wantReplicate) then
					StepAutoScan()
				end
			elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
				local list = (C_AuctionHouse and C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults()) or arg1
				RecordBrowseList(list)
			elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
				RecordCommodityResults(arg1)
			elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
				RecordItemResults(arg1)
			elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
				StartReplicateSlice()
			end
		end)

		if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
			TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
		end
	end
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
local CATEGORY_VERSION = 4  -- bump when category numbering changes
local DEFAULTS = {
	columns = 10, scale = 1, collapsed = {}, startFolded = {}, offGroups = {},   -- startFolded = "Start collapsed"
	oneBag = false,                                  -- show all bag slots as one single uncategorised grid
	splitReagents = true, splitConsumables = true,
	showCurrencies = true, showFreeSpace = true,     -- Free Space: drop target for split stacks
	showAuctionPrices = true,                        -- AH price tooltips + bag footer summary & cache timestamp
	ahPrices = {},                                   -- [itemID] = lowest unit price in copper from Auction House
	autoPlaceSplit = true,                           -- split stacks go straight into a free slot
	preferReagentBag = true,                         -- reagents dropped on the window go into the reagent bag first
	confirmDestroy = true,                           -- ask before destroying an item dropped on the delete button
	background = 0.8,                                -- window background darkness (0.8 = Blizzard's translucent dialog)
	backgroundStyle = "dark",                        -- which Blizzard background shows at that darkness (UI.lua BACKGROUND_STYLES)
}

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, name)
	if event == "PLAYER_LOGIN" then   -- also fires on /reload
		print(("|cffd4a94eDave's Sack|r v%s loaded. Type /sack options for settings."):format(ns.VERSION))
		return
	end
	if name ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")
	DavesSackDB = DavesSackDB or {}
	for k, v in pairs(DEFAULTS) do
		if DavesSackDB[k] == nil then DavesSackDB[k] = type(v) == "table" and {} or v end
	end
	if DavesSackDB.catVersion ~= CATEGORY_VERSION then
		DavesSackDB.collapsed, DavesSackDB.startFolded = {}, {}
		DavesSackDB.catVersion = CATEGORY_VERSION
	end
	DavesSackDB.maxHeight = nil            -- replaced by viewHeight (set by resizing)
	ns.db = DavesSackDB
	if ns.InitAuctionCache then ns.InitAuctionCache() end
	if ns.OnLoad then ns.OnLoad() end
	if ns.InitSettingsPanel then ns.InitSettingsPanel() end
end)

---------------------------------------------------------------------------
-- /sack opens your bags; /sack options opens the Options window.
---------------------------------------------------------------------------
SLASH_DAVESSACK1, SLASH_DAVESSACK2 = "/sack", "/davessack"
SlashCmdList.DAVESSACK = function(msg)
	local cmd = match(lower(msg or ""), "^(%S*)")
	if cmd == "options" or cmd == "config" or cmd == "settings" then
		if ns.ToggleOptions then ns.ToggleOptions() end
	else
		ns.Toggle()
	end
end
