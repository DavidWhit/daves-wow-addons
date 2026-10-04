-- daves_sack / Core.lua
-- Version-proof API layer, item categorisation and saved settings.
-- Everything that differs between Forever, Classic and Retail clients is resolved
-- once here, so the UI code never has to branch on game version.

local ADDON, ns = ...

ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- WoW: Forever's client identifies itself as project "Camelot" (Blizzard's
-- Forever UI source: WOW_PROJECT_CAMELOT = 18, WOW_PROJECT_ID = WOW_PROJECT_CAMELOT).
ns.IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT

---------------------------------------------------------------------------
-- API compatibility (feature detection, never version numbers)
---------------------------------------------------------------------------
local C_Container, C_Item = C_Container, C_Item

ns.GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
ns.GetCooldown = (C_Container and C_Container.GetContainerItemCooldown) or GetContainerItemCooldown
ns.SortBags    = (C_Container and C_Container.SortBags) or SortBags            -- may be nil
ns.GetQuestInfo = C_Container and C_Container.GetContainerItemQuestInfo       -- may be nil

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetQualityByID     = C_Item and C_Item.GetItemQualityByID
local GetItemInfo        = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local ModernSlotInfo     = C_Container and C_Container.GetContainerItemInfo
local LegacySlotInfo     = GetContainerItemInfo
local match, lower, select = string.match, string.lower, select

-- Items whose full info isn't cached yet; UI re-categorises them when it arrives.
ns.waiting = {}

-- Reads one bag slot into a reusable record table (no per-update garbage on
-- legacy clients). Returns true if the item identity changed, i.e. the slot needs
-- re-categorising / re-layout rather than just a visual refresh.
function ns.ReadSlot(bag, slot, rec)
	local tex, count, locked, quality, link, id
	if ModernSlotInfo then
		local i = ModernSlotInfo(bag, slot)
		if i then
			tex, count, locked, quality, link, id = i.iconFileID, i.stackCount, i.isLocked, i.quality, i.hyperlink, i.itemID
		end
	else
		local _
		tex, count, locked, quality, _, _, link, _, _, id = LegacySlotInfo(bag, slot)
	end

	if id and (not quality or quality < 0) then
		quality = (GetQualityByID and GetQualityByID(id)) or (link and select(3, GetItemInfo(link))) or 1
	end

	local changed = rec.id ~= id or rec.quality ~= quality
	if link ~= rec.link then                 -- e.g. "of the Bear" variants swapping slots
		local n = link and match(link, "%[(.-)%]")
		rec.name = n and lower((n:gsub("|A.-|a", ""):gsub("|T.-|t", ""))) or nil
	end
	rec.texture, rec.count, rec.locked, rec.link = tex, count or 0, locked, link
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

---------------------------------------------------------------------------
-- Categories (display order)
---------------------------------------------------------------------------
local EQUIP, CONSUME, PROF, CAMP, REAGENT, QUEST, MISC, JUNK = 1, 2, 3, 4, 5, 6, 7, 8
ns.CATEGORY_NAMES = { "Equipment", "Consumables", "Professions", "Camping", "Reagents", "Quest", "Miscellaneous", "Junk" }
ns.NUM_CATEGORIES = #ns.CATEGORY_NAMES

-- Enum.ItemClass values have been stable since vanilla.
local CLASS_TO_CAT = {
	[2] = EQUIP, [4] = EQUIP,               -- weapon, armor
	[0] = CONSUME, [8] = CONSUME,           -- consumable, item enhancement
	[9] = PROF, [19] = PROF,                -- recipes, profession tools & gear
	[5] = REAGENT, [7] = REAGENT,           -- reagents, trade goods (cloth, ore, herbs…)
	[12] = QUEST,
}

-- Classic-era profession tools that the game files as weapons or junk.
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
-- (Enum.ItemTradeGoodsSubclass; same numbering on Classic and Retail).
--
-- Primary professions always win over secondary ones (Cooking, First Aid,
-- Fishing): linen is Tailoring, not First Aid; a fish Alchemy turns into oil is
-- Alchemy, not Cooking. Secondary groups only get what no primary uses, and
-- they're listed after every primary group.
ns.CAT_REAGENT, ns.CAT_CONSUME = REAGENT, CONSUME

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

-- Consumables by Enum.ItemConsumableSubclass (same numbering everywhere).
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
-- Very old item data files lots of consumables as plain "Consumable"
-- (subclass 0); for those, fall back to the item's name / use-effect.
local ALCHEMY_WORDS = { "potion", "elixir", "flask", "phial", "draught", "philter" }
local GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
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
-- Only on Forever (elsewhere "Blueprint:" etc. mean other things), and the
-- names only match English clients.
local CAMPING_ITEMS = { [4470] = true, [4471] = true }   -- Simple Wood, Flint and Tinder
local CAMPING_WORDS = {
	"%f[%a]camps?%f[%A]", "%f[%a]camping", "campfire", "sleeping bag", "blueprint",
	"mana well", "fish bowl", "lodestone", "incense candle", "enchanted lute", "faction banner",
	"greenhouse", "seed hybridizer", "rock garden", "molten foundry", "fishing rack",
	"fermenter", "alchemy laboratory", "master forge", "first aid kit",
}
local find = string.find
local function IsCamping(rec)
	if not ns.IS_FOREVER then return false end
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

local function IsReagentBag(bag)
	local first = (NUM_BAG_SLOTS or 4) + 1
	return bag >= first and bag < first + (NUM_REAGENTBAG_SLOTS or 0)
end

function ns.Categorize(bag, slot, rec)
	local id = rec.id
	if not id then return nil end
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
	for i = 1, (NUM_REAGENTBAG_SLOTS or 0) do t[#t + 1] = bags + i end   -- retail reagent bag
	if KEYRING_CONTAINER and HasKey and HasKey() then t[#t + 1] = KEYRING_CONTAINER end
	return t
end

---------------------------------------------------------------------------
-- Saved settings
---------------------------------------------------------------------------
local CATEGORY_VERSION = 3   -- bump when category numbering changes
local DEFAULTS = {
	columns = 10, scale = 1, collapsed = {}, startFolded = {}, offGroups = {},   -- startFolded = "Start collapsed"
	splitReagents = true, splitConsumables = true,
	showCurrencies = true, showFreeSpace = true,     -- Free Space: drop target for split stacks
	autoPlaceSplit = true,                           -- split stacks go straight into a free slot
}

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = GetAddOnMetadata(ADDON, "Version") or "dev"

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
	if ns.OnLoad then ns.OnLoad() end
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
