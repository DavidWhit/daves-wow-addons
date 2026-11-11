-- daves_sack / Market.lua
-- Companion Market Analysis & Insights window opened from the gavel button
-- beside the trash can in the bag toolbar (or /sack market). Styled in the
-- same HUD Edit Mode dialog chrome as DavesSackFrame and Bag Settings.

local _, ns = ...
local M = ns.MEDIA
local C_Item = C_Item
local GetItemInfo = C_Item and C_Item.GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant
local GetQualityByID = C_Item and C_Item.GetItemQualityByID
local RequestLoadItemData = C_Item and C_Item.RequestLoadItemDataByID
local floor, max, min, abs, sort, find, format =
	math.floor, math.max, math.min, math.abs, table.sort, string.find, string.format
local ipairs, pairs, wipe = ipairs, pairs, wipe
local Group = BreakUpLargeNumbers or tostring

local WIDTH, MIN_HEIGHT, MAX_HEIGHT = 640, 440, 620
local PAD = 16
local ROW_H, HEADER_H, ROW_GAP = 40, 24, 3
local MAX_ROWS = 60

local TRIM = { 0.23, 0.23, 0.25, 1 }
local SLOTBG = { 0.08, 0.08, 0.09, 1 }
local AH_CUT = 0.95 -- 5% standard Auction House cut

local SMALL_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t"
local SMALL_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t"
local SMALL_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t"

local TABS = {
	{ id = 1, label = "Margin",      title = "Market Flip Margin Opportunities" },
	{ id = 2, label = "Scarce",      title = "Scarce Market Supply (1–5 Left)" },
	{ id = 3, label = "Professions", title = "Profession Cost to Make & Top Trades" },
	{ id = 4, label = "Bag Advisor", title = "Bag Market Advisor (Your Items)" },
}

local SUB_FILTERS = {
	[3] = {
		{ key = "alch",   label = "Alchemy",        name = "Alchemy" },
		{ key = "bs",     label = "Blacksmithing",  name = "Blacksmithing" },
		{ key = "ench",   label = "Enchanting",     name = "Enchanting" },
		{ key = "engi",   label = "Engineering",    name = "Engineering" },
		{ key = "lw",     label = "Leatherworking", name = "Leatherworking" },
		{ key = "tailor", label = "Tailoring",      name = "Tailoring" },
		{ key = "cook",   label = "Cooking",        name = "Cooking" },
		{ key = "fa",     label = "First Aid",      name = "First Aid" },
		{ key = "mining", label = "Mining",         name = "Mining" },
	},
}

---------------------------------------------------------------------------
-- Profession Vendor Reagents, Built-in Recipes & Trade Goods
---------------------------------------------------------------------------
-- Standard NPC trade-supply buy prices in copper (used when cheaper than AH or uncached on AH).
local VENDOR_BUY = {
	[159]   = 5,    -- Refreshing Spring Water
	[1179]  = 25,   -- Ice Cold Milk
	[2320]  = 10,   -- Coarse Thread
	[2321]  = 100,  -- Fine Thread
	[2324]  = 25,   -- Bleach
	[2325]  = 1000, -- Black Dye
	[2604]  = 50,   -- Red Dye
	[2605]  = 100,  -- Green Dye
	[2678]  = 10,   -- Mild Spices
	[2692]  = 40,   -- Hot Spices
	[2880]  = 10,   -- Weak Flux
	[3371]  = 4,    -- Empty Vial
	[3372]  = 40,   -- Leaded Vial
	[3466]  = 200,  -- Strong Flux
	[3713]  = 160,  -- Soothing Spices
	[3857]  = 500,  -- Coal
	[4289]  = 50,   -- Salt
	[4291]  = 500,  -- Silken Thread
	[4340]  = 350,  -- Gray Dye
	[4341]  = 500,  -- Yellow Dye
	[4342]  = 2500, -- Purple Dye
	[4399]  = 200,  -- Wooden Stock
	[4400]  = 2000, -- Heavy Stock
	[4470]  = 38,   -- Simple Wood
	[6260]  = 50,   -- Blue Dye
	[6261]  = 1000, -- Orange Dye
	[8343]  = 2000, -- Heavy Silken Thread
	[8925]  = 500,  -- Crystal Vial
	[10290] = 2500, -- Pink Dye
	[11291] = 4500, -- Star Wood
	[14341] = 5000, -- Rune Thread
	[17034] = 20,   -- Maple Seed
	[18256] = 3000, -- Imbued Vial
}

-- { profKey, outputItemID, outputQty, { { reagentItemID, reagentQty }, ... } }
local BUILTIN_RECIPES = {
	-- ALCHEMY
	{ "alch", 118,   1, { { 2447, 1 }, { 765, 1 }, { 3371, 1 } } },              -- Minor Healing Potion
	{ "alch", 858,   1, { { 118, 1 }, { 2450, 1 } } },                           -- Lesser Healing Potion
	{ "alch", 929,   1, { { 2450, 1 }, { 2453, 1 }, { 3372, 1 } } },             -- Healing Potion
	{ "alch", 1710,  1, { { 3357, 1 }, { 3356, 1 }, { 3372, 1 } } },             -- Greater Healing Potion
	{ "alch", 3928,  1, { { 3821, 1 }, { 3818, 1 }, { 8925, 1 } } },             -- Superior Healing Potion
	{ "alch", 13446, 1, { { 13464, 2 }, { 13465, 1 }, { 8925, 1 } } },           -- Major Healing Potion
	{ "alch", 2455,  1, { { 785, 1 }, { 765, 1 }, { 3371, 1 } } },               -- Minor Mana Potion
	{ "alch", 3385,  1, { { 785, 1 }, { 3820, 1 }, { 3371, 1 } } },              -- Lesser Mana Potion
	{ "alch", 3827,  1, { { 3820, 1 }, { 3356, 1 }, { 3372, 1 } } },             -- Mana Potion
	{ "alch", 6149,  1, { { 3358, 1 }, { 3821, 1 }, { 3372, 1 } } },             -- Greater Mana Potion
	{ "alch", 13443, 1, { { 8838, 2 }, { 8839, 2 }, { 8925, 1 } } },             -- Superior Mana Potion
	{ "alch", 13444, 1, { { 13463, 3 }, { 13467, 2 }, { 8925, 1 } } },           -- Major Mana Potion
	{ "alch", 5997,  1, { { 765, 2 }, { 3371, 1 } } },                           -- Elixir of Minor Defense
	{ "alch", 2458,  1, { { 2449, 2 }, { 2447, 1 }, { 3371, 1 } } },             -- Elixir of Minor Fortitude
	{ "alch", 2457,  1, { { 2452, 1 }, { 765, 1 }, { 3371, 1 } } },              -- Elixir of Minor Agility
	{ "alch", 3383,  1, { { 785, 1 }, { 2450, 2 }, { 3371, 1 } } },              -- Elixir of Wisdom
	{ "alch", 3388,  1, { { 2450, 1 }, { 2449, 1 }, { 3372, 1 } } },             -- Lesser Troll's Blood Elixir
	{ "alch", 3389,  1, { { 2453, 2 }, { 3820, 1 }, { 3372, 1 } } },             -- Elixir of Defense
	{ "alch", 3825,  1, { { 3355, 1 }, { 3821, 1 }, { 3372, 1 } } },             -- Elixir of Fortitude
	{ "alch", 2459,  1, { { 2452, 1 }, { 2450, 1 }, { 3371, 1 } } },             -- Swiftness Potion
	{ "alch", 5631,  1, { { 5635, 1 }, { 2450, 1 }, { 3371, 1 } } },             -- Rage Potion
	{ "alch", 5633,  1, { { 1288, 1 }, { 3356, 1 }, { 3372, 1 } } },             -- Great Rage Potion
	{ "alch", 6372,  1, { { 2452, 1 }, { 6370, 1 }, { 3371, 1 } } },             -- Swim Speed Potion
	{ "alch", 6373,  1, { { 6371, 2 }, { 3356, 1 }, { 3372, 1 } } },             -- Elixir of Firepower
	{ "alch", 3390,  1, { { 3355, 1 }, { 2452, 1 }, { 3372, 1 } } },             -- Elixir of Lesser Agility
	{ "alch", 3391,  1, { { 2449, 1 }, { 3356, 1 }, { 3372, 1 } } },             -- Elixir of Ogre's Strength
	{ "alch", 8951,  1, { { 3355, 1 }, { 3821, 1 }, { 3372, 1 } } },             -- Elixir of Greater Defense
	{ "alch", 8949,  1, { { 3820, 1 }, { 3821, 1 }, { 3372, 1 } } },             -- Elixir of Agility
	{ "alch", 9187,  1, { { 8838, 1 }, { 3821, 1 }, { 8925, 1 } } },             -- Elixir of Greater Agility
	{ "alch", 13445, 1, { { 8838, 2 }, { 3821, 1 }, { 8925, 1 } } },             -- Elixir of Superior Defense
	{ "alch", 9155,  1, { { 8839, 1 }, { 3821, 1 }, { 8925, 1 } } },             -- Arcane Elixir
	{ "alch", 13454, 1, { { 13463, 3 }, { 13465, 1 }, { 8925, 1 } } },           -- Greater Arcane Elixir
	{ "alch", 9264,  1, { { 8845, 3 }, { 8925, 1 } } },                          -- Elixir of Shadow Power
	{ "alch", 9206,  1, { { 8838, 1 }, { 13466, 1 }, { 8925, 1 } } },            -- Elixir of Giants
	{ "alch", 13452, 1, { { 13465, 2 }, { 13466, 2 }, { 8925, 1 } } },           -- Elixir of the Mongoose
	{ "alch", 5634,  1, { { 6370, 2 }, { 3820, 1 }, { 3372, 1 } } },             -- Free Action Potion
	{ "alch", 3387,  1, { { 8839, 2 }, { 8845, 1 }, { 8925, 1 } } },             -- Limited Invulnerability Potion
	{ "alch", 3823,  1, { { 3818, 1 }, { 3355, 1 }, { 3372, 1 } } },             -- Lesser Invisibility Potion
	{ "alch", 9172,  1, { { 8845, 1 }, { 8838, 1 }, { 8925, 1 } } },             -- Invisibility Potion
	{ "alch", 6048,  1, { { 3369, 1 }, { 3356, 1 }, { 3372, 1 } } },             -- Shadow Protection Potion
	{ "alch", 6049,  1, { { 4402, 1 }, { 6371, 1 }, { 3372, 1 } } },             -- Fire Protection Potion
	{ "alch", 6050,  1, { { 3819, 1 }, { 3821, 1 }, { 3372, 1 } } },             -- Frost Protection Potion
	{ "alch", 6052,  1, { { 3357, 1 }, { 3820, 1 }, { 3372, 1 } } },             -- Nature Protection Potion
	{ "alch", 6370,  1, { { 6358, 2 }, { 3371, 1 } } },                          -- Blackmouth Oil
	{ "alch", 6371,  1, { { 6359, 2 }, { 3371, 1 } } },                          -- Fire Oil
	{ "alch", 13423, 1, { { 13422, 1 }, { 3372, 1 } } },                         -- Stonescale Oil
	{ "alch", 3829,  1, { { 3358, 4 }, { 3819, 2 }, { 3372, 1 } } },             -- Frost Oil
	{ "alch", 3824,  1, { { 3818, 4 }, { 3369, 4 }, { 3372, 1 } } },             -- Shadow Oil
	{ "alch", 8956,  1, { { 4625, 1 }, { 3821, 1 }, { 8925, 1 } } },             -- Oil of Immolation
	{ "alch", 9210,  1, { { 8845, 2 }, { 4342, 1 }, { 8925, 1 } } },             -- Ghost Dye
	{ "alch", 12360, 1, { { 12359, 1 }, { 12363, 1 } } },                        -- Arcanite Bar

	-- MINING (Smelting)
	{ "mining", 2840,  1, { { 2770, 1 } } },                                     -- Copper Bar
	{ "mining", 3576,  1, { { 2771, 1 } } },                                     -- Tin Bar
	{ "mining", 2841,  2, { { 2840, 1 }, { 3576, 1 } } },                        -- Bronze Bar (x2)
	{ "mining", 2842,  1, { { 2775, 1 } } },                                     -- Silver Bar
	{ "mining", 3575,  1, { { 2772, 1 } } },                                     -- Iron Bar
	{ "mining", 3577,  1, { { 2776, 1 } } },                                     -- Gold Bar
	{ "mining", 3859,  1, { { 3575, 1 }, { 3857, 1 } } },                        -- Steel Bar
	{ "mining", 3860,  1, { { 3858, 1 } } },                                     -- Mithril Bar
	{ "mining", 6037,  1, { { 7911, 1 } } },                                     -- Truesilver Bar
	{ "mining", 12359, 1, { { 10620, 1 } } },                                    -- Thorium Bar
	{ "mining", 11371, 1, { { 11370, 8 } } },                                    -- Dark Iron Bar

	-- BLACKSMITHING
	{ "bs", 2862,  1, { { 2835, 1 } } },                                         -- Rough Sharpening Stone
	{ "bs", 2863,  1, { { 2836, 1 } } },                                         -- Coarse Sharpening Stone
	{ "bs", 2871,  1, { { 2838, 1 } } },                                         -- Heavy Sharpening Stone
	{ "bs", 7964,  1, { { 7912, 1 } } },                                         -- Solid Sharpening Stone
	{ "bs", 12404, 1, { { 12365, 1 } } },                                        -- Dense Sharpening Stone
	{ "bs", 3239,  1, { { 2835, 1 }, { 2589, 1 } } },                            -- Rough Weightstone
	{ "bs", 3240,  1, { { 2836, 1 }, { 2592, 1 } } },                            -- Coarse Weightstone
	{ "bs", 3241,  1, { { 2838, 1 }, { 2592, 1 } } },                            -- Heavy Weightstone
	{ "bs", 7965,  1, { { 7912, 1 }, { 4306, 1 } } },                            -- Solid Weightstone
	{ "bs", 12643, 1, { { 12365, 1 }, { 14047, 1 } } },                          -- Dense Weightstone
	{ "bs", 3470,  1, { { 2835, 2 } } },                                         -- Rough Grinding Stone
	{ "bs", 3478,  1, { { 2836, 2 } } },                                         -- Coarse Grinding Stone
	{ "bs", 3486,  1, { { 2838, 3 } } },                                         -- Heavy Grinding Stone
	{ "bs", 7966,  1, { { 7912, 4 } } },                                         -- Solid Grinding Stone
	{ "bs", 12644, 1, { { 12365, 4 } } },                                        -- Dense Grinding Stone
	{ "bs", 6217,  1, { { 2840, 1 }, { 3470, 1 } } },                            -- Copper Rod
	{ "bs", 6338,  1, { { 2842, 1 }, { 3470, 2 } } },                            -- Silver Rod
	{ "bs", 11128, 1, { { 3577, 1 }, { 3478, 2 } } },                            -- Golden Rod
	{ "bs", 11144, 1, { { 6037, 1 }, { 3486, 1 } } },                            -- Truesilver Rod
	{ "bs", 16206, 1, { { 12360, 3 }, { 12644, 1 } } },                          -- Arcanite Rod
	{ "bs", 7071,  2, { { 3575, 1 } } },                                         -- Iron Buckle (x2)
	{ "bs", 15869, 2, { { 2842, 1 }, { 3470, 1 } } },                            -- Silver Skeleton Key (x2)
	{ "bs", 15870, 2, { { 3577, 1 }, { 3486, 1 } } },                            -- Golden Skeleton Key (x2)
	{ "bs", 15871, 2, { { 6037, 1 }, { 7966, 1 } } },                            -- Truesilver Skeleton Key (x2)
	{ "bs", 15872, 2, { { 12360, 1 }, { 12644, 1 } } },                          -- Arcanite Skeleton Key (x2)
	{ "bs", 6042,  1, { { 3575, 4 }, { 3478, 2 } } },                            -- Iron Shield Spike
	{ "bs", 6041,  1, { { 3859, 8 }, { 3486, 2 }, { 4234, 4 } } },               -- Steel Weapon Chain
	{ "bs", 6043,  1, { { 3575, 4 }, { 3466, 2 }, { 1210, 1 } } },               -- Iron Counterweight
	{ "bs", 7967,  1, { { 3860, 4 }, { 6037, 2 }, { 7966, 4 } } },               -- Mithril Shield Spike
	{ "bs", 7969,  1, { { 3860, 4 }, { 7966, 3 } } },                            -- Mithril Spurs
	{ "bs", 2853,  1, { { 2840, 2 } } },                                         -- Copper Bracers
	{ "bs", 2851,  1, { { 2840, 6 } } },                                         -- Copper Chain Belt
	{ "bs", 2852,  1, { { 2840, 4 } } },                                         -- Copper Chain Pants
	{ "bs", 2854,  1, { { 2840, 6 } } },                                         -- Runed Copper Bracers
	{ "bs", 2857,  1, { { 2840, 10 } } },                                        -- Runed Copper Belt
	{ "bs", 3472,  1, { { 2840, 8 }, { 3470, 2 } } },                            -- Runed Copper Gauntlets
	{ "bs", 2865,  1, { { 2841, 6 } } },                                         -- Rough Bronze Leggings
	{ "bs", 2866,  1, { { 2841, 7 } } },                                         -- Rough Bronze Cuirass
	{ "bs", 2868,  1, { { 2841, 5 }, { 3478, 2 } } },                            -- Patterned Bronze Bracers
	{ "bs", 3482,  1, { { 2841, 6 }, { 2842, 1 }, { 3478, 2 } } },               -- Silvered Bronze Boots
	{ "bs", 3483,  1, { { 2841, 8 }, { 2842, 1 }, { 3478, 2 } } },               -- Silvered Bronze Gauntlets
	{ "bs", 3835,  1, { { 3575, 6 }, { 2605, 1 } } },                            -- Green Iron Bracers
	{ "bs", 3840,  1, { { 3575, 7 }, { 3486, 1 }, { 2605, 1 } } },               -- Green Iron Shoulders
	{ "bs", 3842,  1, { { 3575, 8 }, { 3486, 1 }, { 2605, 1 } } },               -- Green Iron Leggings
	{ "bs", 7918,  1, { { 3860, 8 }, { 4234, 6 } } },                            -- Heavy Mithril Shoulder
	{ "bs", 7919,  1, { { 3860, 6 }, { 4338, 4 } } },                            -- Heavy Mithril Gauntlet

	-- ENCHANTING (Wands, Oils, Enchanted Mats & Essence Conversions)
	{ "ench", 11287,  1, { { 10938, 1 }, { 4470, 1 } } },                        -- Lesser Magic Wand
	{ "ench", 11288,  1, { { 10939, 1 }, { 4470, 1 } } },                        -- Greater Magic Wand
	{ "ench", 11289,  1, { { 11134, 1 }, { 11291, 1 } } },                       -- Lesser Mystic Wand
	{ "ench", 217287, 1, { { 11135, 1 }, { 11291, 1 } } },                       -- Greater Mystic Wand
	{ "ench", 20744,  1, { { 10940, 2 }, { 17034, 1 }, { 3371, 1 } } },          -- Minor Wizard Oil
	{ "ench", 20745,  1, { { 11083, 3 }, { 17034, 2 }, { 3371, 1 } } },          -- Minor Mana Oil
	{ "ench", 20746,  1, { { 11137, 3 }, { 3820, 2 }, { 3372, 1 } } },           -- Lesser Wizard Oil
	{ "ench", 20747,  1, { { 11176, 3 }, { 8831, 2 }, { 8925, 1 } } },           -- Lesser Mana Oil
	{ "ench", 20748,  1, { { 16204, 2 }, { 14344, 3 }, { 18256, 1 } } },         -- Brilliant Mana Oil
	{ "ench", 20749,  1, { { 16204, 3 }, { 4625, 2 }, { 18256, 1 } } },          -- Brilliant Wizard Oil
	{ "ench", 12810,  1, { { 8170, 1 }, { 16202, 1 } } },                        -- Enchanted Leather
	{ "ench", 12655,  1, { { 12359, 1 }, { 11176, 3 } } },                       -- Enchanted Thorium Bar
	{ "ench", 10939,  1, { { 10938, 3 } } },                                     -- Greater Magic Essence (from 3x Lesser)
	{ "ench", 10938,  3, { { 10939, 1 } } },                                     -- Lesser Magic Essence x3 (from 1x Greater)
	{ "ench", 11082,  1, { { 10998, 3 } } },                                     -- Greater Astral Essence (from 3x Lesser)
	{ "ench", 10998,  3, { { 11082, 1 } } },                                     -- Lesser Astral Essence x3 (from 1x Greater)
	{ "ench", 11135,  1, { { 11134, 3 } } },                                     -- Greater Mystic Essence (from 3x Lesser)
	{ "ench", 11134,  3, { { 11135, 1 } } },                                     -- Lesser Mystic Essence x3 (from 1x Greater)
	{ "ench", 11175,  1, { { 11174, 3 } } },                                     -- Greater Nether Essence (from 3x Lesser)
	{ "ench", 11174,  3, { { 11175, 1 } } },                                     -- Lesser Nether Essence x3 (from 1x Greater)
	{ "ench", 16203,  1, { { 16202, 3 } } },                                     -- Greater Eternal Essence (from 3x Lesser)
	{ "ench", 16202,  3, { { 16203, 1 } } },                                     -- Lesser Eternal Essence x3 (from 1x Greater)

	-- ENGINEERING
	{ "engi", 4357,  1,   { { 2835, 1 } } },                                     -- Rough Blasting Powder
	{ "engi", 4364,  1,   { { 2836, 1 } } },                                     -- Coarse Blasting Powder
	{ "engi", 4377,  1,   { { 2838, 1 } } },                                     -- Heavy Blasting Powder
	{ "engi", 10505, 2,   { { 7912, 1 } } },                                     -- Solid Blasting Powder (x2)
	{ "engi", 15992, 2,   { { 12365, 1 } } },                                    -- Dense Blasting Powder (x2)
	{ "engi", 4358,  2,   { { 4357, 2 }, { 2589, 1 } } },                        -- Rough Dynamite (x2)
	{ "engi", 4365,  2,   { { 4364, 3 }, { 2589, 1 } } },                        -- Coarse Dynamite (x2)
	{ "engi", 4378,  3,   { { 4377, 2 }, { 2592, 1 } } },                        -- Heavy Dynamite (x3)
	{ "engi", 10507, 2,   { { 10505, 1 }, { 4306, 1 } } },                       -- Solid Dynamite (x2)
	{ "engi", 18641, 2,   { { 15992, 2 }, { 14047, 3 } } },                      -- Dense Dynamite (x2)
	{ "engi", 8067,  200, { { 4357, 1 }, { 2840, 1 } } },                        -- Crafted Light Shot (x200)
	{ "engi", 8068,  200, { { 4364, 1 }, { 2840, 1 } } },                        -- Crafted Heavy Shot (x200)
	{ "engi", 8069,  200, { { 4377, 1 }, { 2841, 1 } } },                        -- Crafted Solid Shot (x200)
	{ "engi", 10512, 200, { { 3860, 1 }, { 10505, 1 } } },                       -- Hi-Impact Mithril Slugs (x200)
	{ "engi", 4404,  5,   { { 2842, 1 } } },                                     -- Silver Contact (x5)
	{ "engi", 4359,  1,   { { 2840, 1 } } },                                     -- Handful of Copper Bolts
	{ "engi", 4361,  1,   { { 2840, 2 }, { 2880, 1 } } },                        -- Copper Tube
	{ "engi", 4360,  2,   { { 2840, 1 }, { 4359, 1 }, { 4357, 2 }, { 2589, 1 } } }, -- Rough Copper Bomb (x2)
	{ "engi", 4370,  3,   { { 2840, 3 }, { 4364, 4 }, { 2589, 1 } } },           -- Large Copper Bomb (x3)
	{ "engi", 4374,  2,   { { 4364, 4 }, { 2841, 2 }, { 2592, 1 } } },           -- Small Bronze Bomb (x2)
	{ "engi", 4380,  3,   { { 4377, 4 }, { 2841, 3 }, { 2320, 1 } } },           -- Big Bronze Bomb (x3)
	{ "engi", 4390,  3,   { { 3575, 1 }, { 4377, 1 }, { 4306, 1 } } },           -- Iron Grenade (x3)
	{ "engi", 4394,  2,   { { 3575, 3 }, { 4377, 3 }, { 2842, 1 } } },           -- Big Iron Bomb (x2)
	{ "engi", 10514, 3,   { { 10561, 1 }, { 10560, 1 }, { 10505, 1 } } },        -- Mithril Frag Bomb (x3)
	{ "engi", 10562, 2,   { { 10561, 2 }, { 10560, 1 }, { 10505, 2 } } },        -- Hi-Explosive Bomb (x2)
	{ "engi", 15993, 3,   { { 16000, 1 }, { 12359, 3 }, { 15992, 3 }, { 14047, 3 } } }, -- Thorium Grenade (x3)
	{ "engi", 4371,  1,   { { 2841, 2 }, { 2880, 1 } } },                        -- Bronze Tube
	{ "engi", 4375,  1,   { { 2841, 2 }, { 2592, 1 } } },                        -- Whirring Bronze Gizmo
	{ "engi", 4382,  1,   { { 2841, 2 }, { 2319, 1 }, { 2592, 1 } } },           -- Bronze Framework
	{ "engi", 4387,  1,   { { 3575, 2 } } },                                     -- Iron Strut
	{ "engi", 4389,  1,   { { 3575, 1 }, { 10558, 1 } } },                       -- Gyrochronatom
	{ "engi", 10558, 3,   { { 3577, 1 } } },                                     -- Gold Power Core (x3)
	{ "engi", 10559, 1,   { { 3860, 3 } } },                                     -- Mithril Tube
	{ "engi", 10560, 1,   { { 3860, 1 }, { 4338, 1 }, { 10505, 1 } } },          -- Unstable Trigger
	{ "engi", 10561, 1,   { { 3860, 3 } } },                                     -- Mithril Casing
	{ "engi", 16000, 1,   { { 12359, 3 }, { 14047, 1 } } },                      -- Thorium Widget
	{ "engi", 16006, 1,   { { 12360, 1 }, { 14227, 1 } } },                      -- Delicate Arcanite Converter
	{ "engi", 6712,  1,   { { 2841, 1 }, { 4359, 2 }, { 2880, 1 } } },           -- Practice Lock
	{ "engi", 4366,  1,   { { 4375, 1 }, { 2841, 2 }, { 2592, 1 } } },           -- Target Dummy
	{ "engi", 4392,  1,   { { 4387, 2 }, { 4382, 1 }, { 4389, 1 }, { 4234, 4 } } }, -- Advanced Target Dummy
	{ "engi", 4405,  1,   { { 4361, 1 }, { 774, 1 }, { 4359, 1 } } },            -- Crude Scope
	{ "engi", 4406,  1,   { { 4371, 1 }, { 1206, 1 } } },                        -- Standard Scope
	{ "engi", 4407,  1,   { { 4371, 1 }, { 1529, 1 }, { 3864, 1 } } },           -- Accurate Scope
	{ "engi", 10546, 1,   { { 10559, 1 }, { 7909, 2 }, { 4304, 2 } } },          -- Deadly Scope
	{ "engi", 10548, 1,   { { 16000, 2 }, { 7910, 1 }, { 6037, 1 } } },          -- Sniper Scope
	{ "engi", 4368,  1,   { { 2318, 6 }, { 818, 2 } } },                         -- Flying Tiger Goggles

	-- LEATHERWORKING
	{ "lw", 2318,  1, { { 2934, 3 } } },                                         -- Light Leather
	{ "lw", 2319,  1, { { 2318, 4 } } },                                         -- Medium Leather
	{ "lw", 4234,  1, { { 2319, 5 } } },                                         -- Heavy Leather
	{ "lw", 4304,  1, { { 4234, 6 } } },                                         -- Thick Leather
	{ "lw", 8170,  1, { { 4304, 6 } } },                                         -- Rugged Leather
	{ "lw", 4231,  1, { { 783, 1 }, { 4289, 1 } } },                             -- Cured Light Hide
	{ "lw", 4233,  1, { { 4232, 1 }, { 4289, 1 } } },                            -- Cured Medium Hide
	{ "lw", 4236,  1, { { 4235, 1 }, { 4289, 3 } } },                            -- Cured Heavy Hide
	{ "lw", 8172,  1, { { 8169, 1 }, { 8150, 1 } } },                            -- Cured Thick Hide
	{ "lw", 15407, 1, { { 8171, 1 }, { 15409, 1 } } },                           -- Cured Rugged Hide
	{ "lw", 2304,  1, { { 2318, 1 }, { 2320, 1 } } },                            -- Light Armor Kit
	{ "lw", 2313,  1, { { 2319, 4 }, { 2320, 1 } } },                            -- Medium Armor Kit
	{ "lw", 4265,  1, { { 4234, 5 }, { 2321, 1 } } },                            -- Heavy Armor Kit
	{ "lw", 8173,  1, { { 4304, 5 }, { 4291, 1 } } },                            -- Thick Armor Kit
	{ "lw", 15564, 1, { { 8170, 5 } } },                                         -- Rugged Armor Kit
	{ "lw", 4239,  1, { { 2318, 3 }, { 2320, 2 } } },                            -- Embossed Leather Gloves
	{ "lw", 2309,  1, { { 2318, 8 }, { 2320, 5 } } },                            -- Embossed Leather Boots
	{ "lw", 2310,  1, { { 2318, 5 }, { 2320, 2 } } },                            -- Embossed Leather Cloak
	{ "lw", 5957,  1, { { 2318, 3 }, { 2320, 1 } } },                            -- Handstitched Leather Vest
	{ "lw", 2315,  1, { { 2319, 4 }, { 2321, 2 }, { 4340, 1 } } },               -- Gray Leather Boots
	{ "lw", 2316,  1, { { 2319, 8 }, { 2321, 1 }, { 4340, 1 } } },               -- Dark Leather Cloak
	{ "lw", 4249,  1, { { 4233, 1 }, { 2321, 2 }, { 4340, 1 } } },               -- Dark Leather Belt
	{ "lw", 4251,  1, { { 2319, 4 }, { 4233, 1 }, { 2321, 1 } } },               -- Hillman's Shoulders

	-- TAILORING
	{ "tailor", 2996,  1, { { 2589, 2 } } },                                     -- Bolt of Linen Cloth
	{ "tailor", 2997,  1, { { 2592, 3 } } },                                     -- Bolt of Woolen Cloth
	{ "tailor", 4305,  1, { { 4306, 4 } } },                                     -- Bolt of Silk Cloth
	{ "tailor", 4339,  1, { { 4338, 5 } } },                                     -- Bolt of Mageweave
	{ "tailor", 14048, 1, { { 14047, 5 } } },                                    -- Bolt of Runecloth
	{ "tailor", 14342, 1, { { 14256, 2 } } },                                    -- Mooncloth
	{ "tailor", 4238,  1, { { 2996, 3 }, { 2320, 3 } } },                        -- Linen Bag
	{ "tailor", 5762,  1, { { 2996, 4 }, { 2604, 2 }, { 2320, 3 } } },           -- Red Linen Bag
	{ "tailor", 4240,  1, { { 2997, 3 }, { 2321, 1 } } },                        -- Woolen Bag
	{ "tailor", 4245,  1, { { 4305, 3 }, { 4234, 2 }, { 2321, 3 } } },           -- Small Silk Pack
	{ "tailor", 5764,  1, { { 4305, 4 }, { 4234, 3 }, { 2321, 4 }, { 2605, 1 } } }, -- Green Silk Pack
	{ "tailor", 5765,  1, { { 4305, 5 }, { 2321, 4 }, { 2325, 1 } } },           -- Black Silk Pack
	{ "tailor", 10050, 1, { { 4339, 4 }, { 4291, 2 } } },                        -- Mageweave Bag
	{ "tailor", 14046, 1, { { 14048, 5 }, { 8170, 2 }, { 14341, 1 } } },         -- Runecloth Bag
	{ "tailor", 7026,  1, { { 2996, 1 }, { 2320, 1 } } },                        -- Linen Belt
	{ "tailor", 2580,  1, { { 2996, 2 }, { 2320, 3 } } },                        -- Reinforced Linen Cape
	{ "tailor", 2584,  1, { { 2997, 1 }, { 2321, 1 } } },                        -- Woolen Cape
	{ "tailor", 4314,  1, { { 2997, 3 }, { 2321, 2 } } },                        -- Double-Stitched Woolen Shoulders
	{ "tailor", 4318,  1, { { 2997, 4 }, { 2321, 3 } } },                        -- Gloves of Meditation
	{ "tailor", 7048,  1, { { 4305, 2 }, { 6260, 2 }, { 2321, 1 } } },           -- Azure Silk Hood
	{ "tailor", 4324,  1, { { 4305, 5 }, { 6260, 4 } } },                        -- Azure Silk Vest
	{ "tailor", 7046,  1, { { 4305, 4 }, { 6260, 2 }, { 2321, 3 } } },           -- Azure Silk Pants
	{ "tailor", 7058,  1, { { 4305, 4 }, { 2604, 2 }, { 2321, 2 } } },           -- Crimson Silk Vest
	{ "tailor", 10008, 1, { { 4339, 1 }, { 2324, 1 }, { 8343, 1 } } },           -- White Bandit Mask

	-- COOKING
	{ "cook", 2679,  1, { { 2672, 1 } } },                                       -- Charred Wolf Meat
	{ "cook", 2681,  1, { { 769, 1 } } },                                        -- Roasted Boar Meat
	{ "cook", 2680,  1, { { 2672, 1 }, { 2678, 1 } } },                          -- Spiced Wolf Meat
	{ "cook", 6888,  1, { { 6889, 1 }, { 2678, 1 } } },                          -- Herb Baked Egg
	{ "cook", 1081,  1, { { 1080, 1 } } },                                       -- Crisp Spider Meat
	{ "cook", 5472,  1, { { 5465, 1 } } },                                       -- Kaldorei Spider Kabob
	{ "cook", 6890,  1, { { 3173, 1 } } },                                       -- Smoked Bear Meat
	{ "cook", 5525,  1, { { 5503, 1 }, { 159, 1 } } },                           -- Boiled Clams
	{ "cook", 5526,  1, { { 5503, 1 }, { 1179, 1 }, { 2678, 1 } } },             -- Clam Chowder
	{ "cook", 724,   1, { { 723, 1 }, { 2678, 1 } } },                           -- Goretusk Liver Pie
	{ "cook", 3220,  1, { { 769, 1 }, { 3172, 1 }, { 731, 1 } } },               -- Blood Sausage
	{ "cook", 2684,  1, { { 2673, 1 } } },                                       -- Coyote Steak
	{ "cook", 2683,  1, { { 2674, 1 }, { 2678, 1 } } },                          -- Crab Cake
	{ "cook", 2682,  1, { { 2675, 1 }, { 2678, 1 } } },                          -- Cooked Crab Claw
	{ "cook", 2687,  1, { { 769, 1 }, { 2678, 1 } } },                           -- Dry Pork Ribs
	{ "cook", 3662,  1, { { 2924, 1 }, { 2678, 1 } } },                          -- Crocolisk Steak
	{ "cook", 3663,  1, { { 1468, 2 }, { 2692, 1 } } },                          -- Murloc Fin Soup
	{ "cook", 1017,  1, { { 1015, 2 }, { 2678, 1 } } },                          -- Seasoned Wolf Kabob
	{ "cook", 5527,  1, { { 5504, 1 }, { 2692, 1 } } },                          -- Goblin Deviled Clams
	{ "cook", 3665,  1, { { 3685, 1 }, { 2692, 1 } } },                          -- Curiously Tasty Omelet
	{ "cook", 3726,  1, { { 3730, 1 }, { 2692, 1 } } },                          -- Big Bear Steak
	{ "cook", 3727,  1, { { 3731, 1 }, { 2692, 1 } } },                          -- Hot Lion Chops
	{ "cook", 3728,  1, { { 3731, 2 }, { 3713, 1 } } },                          -- Tasty Lion Steak
	{ "cook", 3729,  1, { { 3712, 1 }, { 3713, 1 } } },                          -- Soothing Turtle Bisque
	{ "cook", 4457,  1, { { 3404, 1 }, { 2692, 1 } } },                          -- Barbecued Buzzard Wing
	{ "cook", 6038,  1, { { 4655, 1 }, { 2692, 1 } } },                          -- Giant Clam Scorcho
	{ "cook", 12212, 2, { { 12202, 1 }, { 159, 1 } } },                          -- Jungle Stew (x2)
	{ "cook", 12210, 1, { { 12184, 1 }, { 2692, 1 } } },                         -- Roast Raptor
	{ "cook", 12217, 1, { { 12037, 1 }, { 4402, 1 }, { 2692, 1 } } },            -- Dragonbreath Chili
	{ "cook", 12218, 1, { { 12207, 1 }, { 3713, 2 } } },                         -- Monster Omelet
	{ "cook", 12216, 1, { { 12206, 1 }, { 2692, 2 } } },                         -- Spiced Chili Crab
	{ "cook", 16766, 2, { { 7974, 2 }, { 2692, 1 }, { 1179, 1 } } },             -- Undermine Clam Chowder (x2)
	{ "cook", 18045, 1, { { 12208, 1 }, { 3713, 1 } } },                         -- Tender Wolf Steak
	{ "cook", 6657,  1, { { 6522, 1 }, { 2678, 1 } } },                          -- Savory Deviate Delight
	{ "cook", 7676,  1, { { 2452, 1 }, { 159, 1 } } },                           -- Thistle Tea
	{ "cook", 6290,  1, { { 6291, 1 } } },                                       -- Brilliant Smallfish
	{ "cook", 4592,  1, { { 6289, 1 } } },                                       -- Longjaw Mud Snapper
	{ "cook", 787,   1, { { 6303, 1 } } },                                       -- Slitherskin Mackerel
	{ "cook", 4593,  1, { { 6308, 1 } } },                                       -- Bristle Whisker Catfish
	{ "cook", 4594,  1, { { 6362, 1 } } },                                       -- Rockscale Cod
	{ "cook", 21072, 1, { { 21071, 1 }, { 2678, 1 } } },                         -- Smoked Sagefish
	{ "cook", 21217, 1, { { 21153, 1 }, { 2692, 1 } } },                         -- Sagefish Delight
	{ "cook", 8364,  1, { { 8365, 1 } } },                                       -- Mithril Head Trout
	{ "cook", 6887,  1, { { 4603, 1 } } },                                       -- Spotted Yellowtail
	{ "cook", 13927, 1, { { 13754, 1 }, { 3713, 1 } } },                         -- Cooked Glossy Mightfish
	{ "cook", 13928, 1, { { 13756, 1 }, { 2692, 1 } } },                         -- Grilled Squid
	{ "cook", 13930, 1, { { 13758, 1 } } },                                      -- Filet of Redgill
	{ "cook", 13931, 1, { { 13759, 1 }, { 159, 1 } } },                          -- Nightfin Soup

	-- FIRST AID
	{ "fa", 1251,  1, { { 2589, 1 } } },                                         -- Linen Bandage
	{ "fa", 2581,  1, { { 2589, 2 } } },                                         -- Heavy Linen Bandage
	{ "fa", 3530,  1, { { 2592, 1 } } },                                         -- Wool Bandage
	{ "fa", 3531,  1, { { 2592, 2 } } },                                         -- Heavy Wool Bandage
	{ "fa", 6450,  1, { { 4306, 1 } } },                                         -- Silk Bandage
	{ "fa", 6451,  1, { { 4306, 2 } } },                                         -- Heavy Silk Bandage
	{ "fa", 8544,  1, { { 4338, 1 } } },                                         -- Mageweave Bandage
	{ "fa", 8545,  1, { { 4338, 2 } } },                                         -- Heavy Mageweave Bandage
	{ "fa", 14529, 1, { { 14047, 1 } } },                                        -- Runecloth Bandage
	{ "fa", 14530, 1, { { 14047, 2 } } },                                        -- Heavy Runecloth Bandage
	{ "fa", 6452,  1, { { 1475, 1 } } },                                         -- Anti-Venom
	{ "fa", 6453,  1, { { 1288, 1 } } },                                         -- Strong Anti-Venom
	{ "fa", 19440, 1, { { 19441, 1 } } },                                        -- Powerful Anti-Venom
}

-- Extra profession trade goods (dusts, shards, essences, herbs, ores, gems, hides) included in Top Trades.
local PROF_EXTRA_REAGENTS = {
	alch   = { 2447, 765, 2449, 785, 2450, 2452, 2453, 3820, 3355, 3369, 3356, 3357, 3818, 3821, 3358, 3819, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468, 7067, 7068, 7069, 7070, 10286 },
	bs     = { 2840, 3576, 2841, 2842, 3575, 3577, 3859, 3860, 6037, 12359, 12360, 11371, 2835, 2836, 2838, 7912, 12365, 774, 818, 1210, 1206, 1529, 3864, 7909, 7910, 12361, 12364, 12799, 12800 },
	ench   = { 10940, 11083, 11137, 11176, 16204, 10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203, 10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725, 6217, 6338, 11128, 11144, 16206, 5500, 5498, 7971, 13926 },
	engi   = { 2835, 2836, 2838, 7912, 12365, 2840, 2841, 2842, 3575, 3577, 3859, 3860, 6037, 12359, 774, 818, 1206, 1529, 3864, 7909, 7910, 10592, 7191 },
	lw     = { 2934, 2318, 2319, 4234, 4304, 8170, 783, 4232, 4235, 8169, 8171, 8150, 15409, 5784, 5785, 7286, 7287, 8154, 8165, 8167, 15408, 15410, 15412, 15414, 15415, 15416, 15417, 15419 },
	tailor = { 2589, 2592, 4306, 4338, 14047, 14256, 14227, 10285, 7070, 7067, 7068, 7069 },
	cook   = { 2672, 769, 6889, 1080, 5465, 3173, 5503, 723, 3172, 731, 2673, 2674, 2675, 2924, 1468, 1015, 5504, 3685, 3730, 3731, 3712, 3404, 4655, 12202, 12184, 12037, 12207, 12206, 7974, 12208, 6522, 6291, 6289, 6303, 6308, 6362, 21071, 21153, 8365, 4603, 13754, 13756, 13758, 13759 },
	fa     = { 2589, 2592, 4306, 4338, 14047, 1475, 1288, 19441 },
	mining = { 2770, 2771, 2775, 2772, 2776, 3858, 7911, 10620, 11370, 3340, 2835, 2836, 2838, 7912, 12365, 774, 818, 1210, 1206, 1529, 3864, 7909, 7910, 12361, 12364, 12799, 12800, 12363 },
}

local mkt
local activeTab = 1
local activeSub = { [3] = "alch" }
local widthMeasured = false
local searchFilter = nil
local userDragged = false
local rows, tabBtns, subBtns, statCards = {}, {}, {}, {}
local bagHoldings = {}
local entries, entryPool = {}, {}
local pendingItemLoad = {}
local profMeta

local function AcquireEntry(idx)
	local e = entryPool[idx]
	if not e then
		e = {}
		entryPool[idx] = e
	else
		wipe(e)
	end
	return e
end

local function TryTemplate(kind, name, parent, template)
	local ok, f = pcall(CreateFrame, kind, name, parent, template)
	if ok and f then return f end
end

local function Sound(kit)
	if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

local function Money(copper)
	if ns.MoneyString then return ns.MoneyString(floor((copper or 0) + 0.5)) end
	return tostring(copper or 0)
end

-- Concise 12x12 coin format (at most 2 denominations) so subtitles never overflow or truncate.
local function CompactMoney(copper)
	copper = floor((copper or 0) + 0.5)
	local g = floor(copper / 10000)
	local s = floor((copper % 10000) / 100)
	local c = copper % 100
	if g >= 100 then
		return Group(g) .. SMALL_GOLD
	elseif g > 0 then
		if s > 0 then return Group(g) .. SMALL_GOLD .. " " .. s .. SMALL_SILVER end
		return Group(g) .. SMALL_GOLD
	elseif s > 0 then
		if c > 0 and s < 10 then return s .. SMALL_SILVER .. " " .. c .. SMALL_COPPER end
		return s .. SMALL_SILVER
	end
	return c .. SMALL_COPPER
end

local function QualityColor(q)
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c then return c.r, c.g, c.b, c.hex or "" end
	if q == 0 then return 0.62, 0.62, 0.62, "|cff9d9d9d" end
	return 1, 1, 1, "|cffffffff"
end

-- Resolves item metadata from GetItemInfo / GetItemInfoInstant / cached market record.
local function ResolveItemMeta(id, m, bagRec)
	local name, link, quality, _, _, _, _, _, _, icon, vendorPrice, classID
	if GetItemInfo then
		name, link, quality, _, _, _, _, _, _, icon, vendorPrice, classID = GetItemInfo(id)
	end
	if not icon and GetItemInfoInstant then
		local _, _, _, _, instIcon, instClass = GetItemInfoInstant(id)
		icon, classID = instIcon, classID or instClass
	end
	if m then
		if name and name ~= "" then m.nm = name else name = m.nm end
		if quality and quality >= 0 then m.qu = quality else quality = m.qu end
	end
	if bagRec then
		name = name or (bagRec.link and string.match(bagRec.link, "%[(.-)%]"))
		link = link or bagRec.link
		quality = quality or bagRec.quality
		icon = icon or bagRec.icon
		classID = classID or bagRec.classID
	end
	if not quality and GetQualityByID then
		quality = GetQualityByID(link or id)
	end
	return name, link, quality or 1, icon or 134400, vendorPrice or 0, classID
end

-- Rejects grey vendor trash, white vendor armor/weapons, and absurd gold-seller / prank price walls.
local function IsNoiseItem(m, quality, vendorPrice, classID)
	local q = quality or (m and m.qu) or 1
	if q == 0 then return true end
	if q == 1 and (classID == 2 or classID == 4) then return true end
	local p = m and m.p or 0
	local posts = m and m.n or 1
	if q <= 1 and posts <= 2 and p >= 500000 and (not vendorPrice or vendorPrice == 0 or p > vendorPrice * 250) then
		return true
	end
	return false
end

local function GetReagentCost(rID, market, prices)
	local m = market[rID]
	local ahP = (m and m.p) or prices[rID]
	local venP = VENDOR_BUY[rID]
	if ahP and ahP > 0 and venP and venP > 0 then
		if venP <= ahP then return venP, "Vendor" end
		return ahP, "AH"
	elseif venP and venP > 0 then
		return venP, "Vendor"
	elseif ahP and ahP > 0 then
		return ahP, "AH"
	end
	return nil, nil
end

local function EnsureProfMeta()
	if profMeta then return profMeta end
	profMeta = {}
	for _, spec in ipairs(SUB_FILTERS[3]) do
		profMeta[spec.key] = { name = spec.name, recipes = {}, outputs = {}, reagents = {} }
	end
	for i = 1, #BUILTIN_RECIPES do
		local r = BUILTIN_RECIPES[i]
		local p = profMeta[r[1]]
		if p then
			p.recipes[#p.recipes + 1] = { outID = r[2], qty = r[3], reags = r[4] }
			if not p.outputs[r[2]] then
				p.outputs[r[2]] = { outID = r[2], qty = r[3], reags = r[4] }
			end
			for j = 1, #r[4] do
				local rID = r[4][j][1]
				if not VENDOR_BUY[rID] then
					p.reagents[rID] = true
				end
			end
		end
	end
	for k, list in pairs(PROF_EXTRA_REAGENTS) do
		local p = profMeta[k]
		if p then
			for i = 1, #list do
				if not VENDOR_BUY[list[i]] then
					p.reagents[list[i]] = true
				end
			end
		end
	end
	return profMeta
end

---------------------------------------------------------------------------
-- Data analysis builders for the 4 tabs
---------------------------------------------------------------------------
-- Only reports a % price trend when we have a genuine multi-scan baseline (m.prev or m.avg from >=2 scans).
local function ComputeTrendPct(m)
	if not (m and m.p and m.p > 0) then return 0, nil end
	local base = (m.prev and m.prev > 0 and m.prev ~= m.p and m.prev)
		or ((m.s or 1) >= 2 and m.avg and m.avg > 0 and m.avg ~= m.p and m.avg)
		or nil
	if base and base > 0 then
		local pct = ((m.p - base) / base) * 100
		if pct > 400 and (m.n or 1) <= 2 then
			return 0, base
		end
		return pct, base
	end
	return 0, m.avg or m.p
end

-- Computes Market Flip opportunities by comparing the lowest buyout offer (m.p)
-- directly against the next highest offer of the same item currently on the AH (m.p2).
local function ComputeMarketFlip(m, quality, vendorPrice, classID)
	if not (m and m.p and m.p > 0) then return nil end
	if IsNoiseItem(m, quality, vendorPrice, classID) then return nil end
	local buy = m.p
	local target = m.p2
	if not (target and target > buy) then return nil end
	local posts = m.n or 1
	local totalQty = m.q or 1
	local floorQty = m.mq or totalQty
	local isGear = (classID == 2 or classID == 4)

	-- Compare suggested buy price (p) against the next highest offer of the same item (p2)
	-- on non-gear commodities with liquid depth:
	if not isGear and target <= buy * 3.5 and posts >= 5 and totalQty >= 6 and floorQty <= 40 and floorQty <= totalQty * 0.35 then
		local netTarget = floor(target * AH_CUT)
		local prof = netTarget - buy
		if prof >= 100 then
			local pct = (prof / buy) * 100
			if pct >= 12 and pct <= 250 then
				return prof, pct, target, "flip", floorQty
			end
		end
	end

	return nil
end

local function MatchesSearch(name, id)
	if not searchFilter then return true end
	if name and find(string.lower(name), searchFilter, 1, true) then return true end
	if tostring(id) == searchFilter then return true end
	return false
end

local function RecordTrades(m)
	if not m then return 0, 0, 0, 0, 0 end
	local qty = m.q or 0
	local prevQty = m.pq or 0
	local cleared = (prevQty > qty) and (prevQty - qty) or 0
	local bids = m.b or 0
	local bidQty = m.bq or 0
	local posts = m.n or 1
	local turn = max(m.turn or 0, cleared + bidQty)
	return turn, bids, bidQty, posts, qty
end

local function BuildEntries()
	wipe(entries)
	if ns.CollectBagHoldings then
		ns.CollectBagHoldings(bagHoldings)
	else
		wipe(bagHoldings)
	end

	local market = ns.db and ns.db.ahMarket or {}
	local prices = ns.db and ns.db.ahPrices or {}
	local poolIdx = 0

	if activeTab == 1 then
		-- Tab 1: Margin (Market Flips default, no child sub-tabs)
		for id, m in pairs(market) do
			local p = m.p or prices[id]
			if p and p > 0 then
				local bagRec = bagHoldings[id]
				local name, link, quality, icon, vendorPrice, classID = ResolveItemMeta(id, m, bagRec)
				if MatchesSearch(name, id) then
					local profit, pct, target, kind, buyQty = ComputeMarketFlip(m, quality, vendorPrice, classID)
					if kind then
						local turn, bids, _, posts, qty = RecordTrades(m)
						local depthBoost = min(3, max(1, posts / 8))
						local score = profit * depthBoost * (1 + min(1.5, pct / 80))
						poolIdx = poolIdx + 1
						local e = AcquireEntry(poolIdx)
						e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice = id, m, name, link, quality, icon, vendorPrice
						e.bagCount = bagRec and bagRec.count or 0
						e.price, e.buyout, e.profit, e.pct, e.target, e.kind, e.buyQty, e.score =
							p, p, profit, pct, target, kind, buyQty or 1, score
						e.turn, e.bids, e.posts, e.qty = turn, bids, posts, qty
						entries[#entries + 1] = e
					end
				end
			end
		end
		sort(entries, function(a, b)
			if a.score ~= b.score then return a.score > b.score end
			return (a.profit or 0) > (b.profit or 0)
		end)
		while #entries > 30 do entries[#entries] = nil end

	elseif activeTab == 2 then
		-- Tab 2: Scarce (Top-level tab for scarce market supply: 1-5 units left)
		for id, m in pairs(market) do
			local p = m.p or prices[id]
			if p and p > 0 then
				local bagRec = bagHoldings[id]
				local name, link, quality, icon, vendorPrice, classID = ResolveItemMeta(id, m, bagRec)
				if not IsNoiseItem(m, quality, vendorPrice, classID) and MatchesSearch(name, id) then
					local turn, bids, _, posts, qty = RecordTrades(m)
					if posts > 0 and qty > 0 and qty <= 5 and quality >= 1 and classID ~= 2 and classID ~= 4 then
						local pct, basePrice = ComputeTrendPct(m)
						local score = (6 - qty) * 1000 + turn * 25 + bids * 80 + min(500, floor(p / 100))
						poolIdx = poolIdx + 1
						local e = AcquireEntry(poolIdx)
						e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice = id, m, name, link, quality, icon, vendorPrice
						e.bagCount = bagRec and bagRec.count or 0
						e.price, e.basePrice, e.pct, e.qty, e.posts, e.turn, e.bids, e.score =
							p, basePrice, pct, qty, posts, turn, bids, score
						entries[#entries + 1] = e
					end
				end
			end
		end
		sort(entries, function(a, b)
			if a.qty ~= b.qty then return a.qty < b.qty end
			if (a.turn or 0) ~= (b.turn or 0) then return (a.turn or 0) > (b.turn or 0) end
			return (a.price or 0) > (b.price or 0)
		end)

	elseif activeTab == 3 then
		-- Tab 3: Professions (Buyout Opportunity: Cost to Make vs Sell Price + Top Trades)
		local pMetaAll = EnsureProfMeta()
		local profKey = activeSub[3] or "alch"
		local pMeta = pMetaAll[profKey] or pMetaAll.alch
		local learned = ns.db and ns.db.ahRecipes or nil

		-- Merge built-in recipes with any live-learned C_TradeSkillUI recipes for this profession
		local recipeList = {}
		local outputRecipe = {}
		for i = 1, #pMeta.recipes do
			local r = pMeta.recipes[i]
			recipeList[#recipeList + 1] = r
			if not outputRecipe[r.outID] then outputRecipe[r.outID] = r end
		end
		if learned then
			for outID, lr in pairs(learned) do
				if type(lr) == "table" and lr.prof == profKey and not outputRecipe[outID] and type(lr.reags) == "table" then
					local r = { outID = outID, qty = lr.qty or 1, reags = lr.reags }
					recipeList[#recipeList + 1] = r
					outputRecipe[outID] = r
				end
			end
		end

		local buyoutList = {}
		local profitableCount = 0
		for i = 1, #recipeList do
			local r = recipeList[i]
			local id = r.outID
			local m = market[id]
			local unitSell = (m and m.p) or prices[id]
			if unitSell and unitSell > 0 then
				local bagRec = bagHoldings[id]
				local name, link, quality, icon, vendorPrice = ResolveItemMeta(id, m, bagRec)
				if MatchesSearch(name, id) then
					local craftCost = 0
					local allKnown = true
					for j = 1, #r.reags do
						local rg = r.reags[j]
						local rCost = GetReagentCost(rg[1], market, prices)
						if not rCost then
							allKnown = false
							break
						end
						craftCost = craftCost + rCost * rg[2]
					end
					if allKnown and craftCost > 0 then
						local outQty = r.qty or 1
						local sellGross = unitSell * outQty
						local sellNet = floor(sellGross * AH_CUT)
						local profit = sellNet - craftCost
						local pct = (profit / craftCost) * 100
						local turn, bids, _, posts, qty = RecordTrades(m)
						if profit > 0 then profitableCount = profitableCount + 1 end
						poolIdx = poolIdx + 1
						local e = AcquireEntry(poolIdx)
						e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice = id, m, name, link, quality, icon, vendorPrice
						e.bagCount = bagRec and bagRec.count or 0
						e.price, e.outQty, e.craftCost, e.sellGross, e.sellNet, e.profit, e.pct =
							unitSell, outQty, craftCost, sellGross, sellNet, profit, pct
						e.reags, e.turn, e.bids, e.posts, e.qty = r.reags, turn, bids, posts, qty
						e.profSection = "buyout"
						buyoutList[#buyoutList + 1] = e
					end
				end
			end
		end
		sort(buyoutList, function(a, b)
			if a.profit ~= b.profit then return a.profit > b.profit end
			return (a.turn or 0) > (b.turn or 0)
		end)

		-- Section 1 Header: Cost to Make vs. Sell
		poolIdx = poolIdx + 1
		local h1 = AcquireEntry(poolIdx)
		h1.isHeader = true
		h1.title = "Cost to Make vs. Sell"
		h1.rightText = format("%d profitable (%d recipes)", profitableCount, #buyoutList)
		entries[#entries + 1] = h1

		local showBuyouts = min(#buyoutList, max(8, min(18, profitableCount)))
		for i = 1, showBuyouts do
			buyoutList[i].displayRank = i
			entries[#entries + 1] = buyoutList[i]
		end

		-- Section 2: Top Trades for this profession (Crafted outputs + Profession reagents)
		local tradesList = {}
		for id, m in pairs(market) do
			if not VENDOR_BUY[id] then
				local isCraft = outputRecipe[id] ~= nil
				local isReag = pMeta.reagents[id] == true
				if isCraft or isReag then
					local p = m.p or prices[id]
					if p and p > 0 then
						local bagRec = bagHoldings[id]
						local name, link, quality, icon, vendorPrice = ResolveItemMeta(id, m, bagRec)
						if MatchesSearch(name, id) then
							local turn, bids, bidQty, posts, qty = RecordTrades(m)
							if turn > 0 or bids > 0 or posts >= 2 or qty >= 3 then
								local score = turn * 100 + bids * 200 + bidQty * 25 + posts * 6 + min(400, qty)
								poolIdx = poolIdx + 1
								local e = AcquireEntry(poolIdx)
								e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice = id, m, name, link, quality, icon, vendorPrice
								e.bagCount = bagRec and bagRec.count or 0
								e.price, e.turn, e.bids, e.posts, e.qty, e.score = p, turn, bids, posts, qty, score
								e.isCraft = isCraft
								e.profSection = "trades"
								local rec = outputRecipe[id]
								if rec then
									local cCost, okCost = 0, true
									for j = 1, #rec.reags do
										local rc = GetReagentCost(rec.reags[j][1], market, prices)
										if not rc then okCost = false; break end
										cCost = cCost + rc * rec.reags[j][2]
									end
									if okCost and cCost > 0 then
										local oQty = rec.qty or 1
										local sGross = p * oQty
										local sNet = floor(sGross * AH_CUT)
										e.outQty, e.craftCost, e.sellGross, e.sellNet = oQty, cCost, sGross, sNet
										e.profit = sNet - cCost
										e.pct = (e.profit / cCost) * 100
										e.reags = rec.reags
									end
								end
								tradesList[#tradesList + 1] = e
							end
						end
					end
				end
			end
		end
		sort(tradesList, function(a, b)
			if (a.turn or 0) ~= (b.turn or 0) then return (a.turn or 0) > (b.turn or 0) end
			if a.score ~= b.score then return a.score > b.score end
			return (a.price or 0) > (b.price or 0)
		end)

		local showTrades = min(15, #tradesList)
		poolIdx = poolIdx + 1
		local h2 = AcquireEntry(poolIdx)
		h2.isHeader = true
		h2.title = format("Top Trades — %s", pMeta.name)
		h2.rightText = format("Top %d active", showTrades)
		entries[#entries + 1] = h2

		for i = 1, showTrades do
			tradesList[i].displayRank = i
			entries[#entries + 1] = tradesList[i]
		end

	elseif activeTab == 4 then
		-- Tab 4: Bag Market Advisor (all tradeable items currently in your bags)
		local hasFullScan = (ns.db and (ns.db.ahScanCount or 0) > 0)
		for id, bagRec in pairs(bagHoldings) do
			local m = market[id]
			local p = (m and m.p) or prices[id]
			local name, link, quality, icon, vendorPrice = ResolveItemMeta(id, m, bagRec)
			if MatchesSearch(name, id) then
				local count = bagRec.count or 1
				local pct = m and ComputeTrendPct(m) or 0
				local posts = m and m.n or nil
				local qty = m and m.q or nil
				local netUnit = p and floor(p * AH_CUT) or 0
				local netStack = netUnit * count
				local vendorStack = (vendorPrice or 0) * count

				local advice = "fair"
				if not p or p <= 0 then
					advice = (hasFullScan and quality >= 1) and "monopoly" or "uncached"
				elseif vendorPrice and vendorPrice > 0 and netUnit <= vendorPrice then
					advice = "vendor"
				elseif pct >= 10 or (posts and posts <= 3 and quality >= 1) then
					advice = "sell"
				elseif pct <= -15 then
					advice = "hold"
				end

				local priority = (advice == "sell" and 4)
					or (advice == "monopoly" and 3)
					or (advice == "vendor" and 2)
					or (advice == "fair" and 1)
					or 0
				poolIdx = poolIdx + 1
				local e = AcquireEntry(poolIdx)
				e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice = id, m, name, link, quality, icon, vendorPrice
				e.bagCount, e.price, e.netUnit, e.netStack = count, p or 0, netUnit, max(netStack, vendorStack)
				e.pct, e.posts, e.qty, e.advice, e.priority = pct, posts, qty, advice, priority
				entries[#entries + 1] = e
			end
		end
		sort(entries, function(a, b)
			if a.priority ~= b.priority then return a.priority > b.priority end
			if a.netStack ~= b.netStack then return a.netStack > b.netStack end
			return (a.bagCount or 0) > (b.bagCount or 0)
		end)
	end
end

---------------------------------------------------------------------------
-- Row Tooltip & Click
---------------------------------------------------------------------------
local function ShowRowTooltip(row)
	local e = row.entry
	if not e or e.isHeader then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if e.link and GameTooltip.SetHyperlink then
		GameTooltip:SetHyperlink(e.link)
	elseif e.id and GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(e.id)
	else
		GameTooltip:SetText(e.name or ("Item #" .. tostring(e.id)), 1, 1, 1)
	end

	local m = e.m
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Dave's Sack Market Analysis", 0.83, 0.66, 0.31)
	if e.price and e.price > 0 then
		GameTooltip:AddDoubleLine("Lowest AH Buyout (each)", Money(e.price), 1, 0.82, 0, 1, 1, 1)
		if m and m.mq and m.mq > 0 then
			GameTooltip:AddDoubleLine("Units at Lowest Price", Group(m.mq), 0.75, 0.75, 0.75, 1, 1, 1)
		end
		if m and m.p2 and m.p2 > e.price then
			GameTooltip:AddDoubleLine("Next Highest Offer", Money(m.p2), 0.75, 0.75, 0.75, 1, 1, 1)
		end
		if e.kind == "flip" and e.target and e.profit and e.profit > 0 then
			GameTooltip:AddDoubleLine("Next Offer Net (After 5% Cut)", Money(floor(e.target * AH_CUT)), 0.75, 0.75, 0.75, 0.9, 0.9, 0.9)
			GameTooltip:AddDoubleLine("Real Flip Margin (each)", "+" .. Money(e.profit) .. format(" (+%.0f%%)", e.pct or 0), 0.36, 0.84, 0.36, 0.36, 0.84, 0.36)
		end
		if m and m.avg and m.avg > 0 then
			local scans = m.s or 1
			GameTooltip:AddDoubleLine(format("Historical Avg (%d %s)", scans, scans == 1 and "scan" or "scans"), Money(m.avg), 0.75, 0.75, 0.75, 1, 1, 1)
		end
		if m and m.low and m.high and m.low < m.high then
			GameTooltip:AddDoubleLine("Seen Range (Low - High)", CompactMoney(m.low) .. " - " .. CompactMoney(m.high), 0.75, 0.75, 0.75, 0.9, 0.9, 0.9)
		end
		if m and (m.q or m.n) then
			GameTooltip:AddDoubleLine("Active AH Supply", format("%s units (%s posts)", Group(m.q or 0), Group(m.n or 1)), 0.75, 0.75, 0.75, 1, 1, 1)
		end
		local turn = e.turn or (m and m.turn) or 0
		if turn > 0 then
			GameTooltip:AddDoubleLine("Recorded Trades (Volume)", format("%s units", Group(turn)), 0.36, 0.84, 0.36, 1, 1, 1)
		end
		if m and (m.b or 0) > 0 then
			GameTooltip:AddDoubleLine("Auctions with Live Bids", format("%d (%s units)", m.b, Group(m.bq or m.b)), 0.4, 0.9, 0.5, 1, 1, 1)
		end
		GameTooltip:AddDoubleLine("Net Payout After 5% Cut", Money(floor(e.price * AH_CUT)), 0.75, 0.75, 0.75, 0.9, 0.9, 0.9)
	end
	if e.reags and e.craftCost then
		GameTooltip:AddLine(" ")
		local outQty = e.outQty or 1
		GameTooltip:AddLine(outQty > 1 and format("Profession Recipe (makes x%d)", outQty) or "Profession Recipe (Cost to Make)", 0.83, 0.66, 0.31)
		local market = ns.db and ns.db.ahMarket or {}
		local prices = ns.db and ns.db.ahPrices or {}
		for i = 1, #e.reags do
			local rg = e.reags[i]
			local rID, rQty = rg[1], rg[2]
			local unitCost, src = GetReagentCost(rID, market, prices)
			local rName = (GetItemInfo and select(1, GetItemInfo(rID))) or (market[rID] and market[rID].nm) or ("Item #" .. tostring(rID))
			if not (GetItemInfo and select(1, GetItemInfo(rID))) and RequestLoadItemData and not pendingItemLoad[rID] then
				pendingItemLoad[rID] = true
				pcall(RequestLoadItemData, rID)
			end
			local costTxt = unitCost and format("%s |cff8c8c8c(%s)|r", Money(unitCost * rQty), src) or "|cffff6b6bUncached|r"
			GameTooltip:AddDoubleLine(format("  %dx %s", rQty, rName), costTxt, 0.85, 0.85, 0.88, 1, 1, 1)
		end
		GameTooltip:AddDoubleLine("Total Cost to Make", Money(e.craftCost), 1, 0.82, 0, 1, 1, 1)
		if e.sellGross and e.sellGross > 0 then
			GameTooltip:AddDoubleLine(outQty > 1 and format("Selling For (x%d AH Buyout)", outQty) or "Selling For (AH Buyout)", Money(e.sellGross), 1, 0.82, 0, 1, 1, 1)
			GameTooltip:AddDoubleLine("Net Payout (After 5% Cut)", Money(e.sellNet or floor(e.sellGross * AH_CUT)), 0.75, 0.75, 0.75, 0.9, 0.9, 0.9)
			local prof = e.profit or 0
			if prof > 0 then
				GameTooltip:AddDoubleLine("Net Buyout Profit", "+" .. Money(prof) .. format(" (+%.0f%%)", e.pct or 0), 0.36, 0.84, 0.36, 0.36, 0.84, 0.36)
			else
				GameTooltip:AddDoubleLine("Net Craft Margin", "-" .. Money(abs(prof)) .. format(" (%.0f%%)", e.pct or 0), 1, 0.42, 0.42, 1, 0.42, 0.42)
			end
		end
	end
	if e.vendorPrice and e.vendorPrice > 0 then
		GameTooltip:AddDoubleLine("Vendor Sell Price (each)", Money(e.vendorPrice), 0.75, 0.75, 0.75, 1, 1, 1)
	end
	if e.bagCount and e.bagCount > 0 then
		GameTooltip:AddDoubleLine("In Your Bags", format("x%d", e.bagCount), 0.35, 0.88, 0.45, 0.35, 0.88, 0.45)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Click to highlight in bags • Shift-click to link item", 0.55, 0.55, 0.58, true)
	GameTooltip:Show()
end

local function OnRowClick(row)
	if CursorHasItem and CursorHasItem() then
		if ns.StoreCursorItem then ns.StoreCursorItem() end
		return
	end
	local e = row.entry
	if not e or e.isHeader then return end
	if IsModifiedClick and IsModifiedClick("CHATLINK") then
		local link = e.link or (GetItemInfo and select(2, GetItemInfo(e.id)))
		local insertLink = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
		if link and insertLink and insertLink(link) then return end
	end
	if e.name and ns.SetBagSearch then
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
		ns.SetBagSearch(e.name)
	end
end

---------------------------------------------------------------------------
-- Row Widget Pool & Painting
---------------------------------------------------------------------------
local function GetRow(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, mkt.content)
	r:SetHeight(ROW_H)
	r:RegisterForClicks("LeftButtonUp")

	local bg = r:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0.05)
	r.bg = bg

	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.82, 0, 0.09)
	r.hl = hl

	local rank = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	rank:SetPoint("LEFT", 5, 0)
	rank:SetWidth(24)
	rank:SetJustifyH("CENTER")
	r.rank = rank

	local slotBox = CreateFrame("Frame", nil, r)
	slotBox:SetSize(30, 30)
	slotBox:SetPoint("LEFT", 31, 0)
	local slotBg = slotBox:CreateTexture(nil, "BACKGROUND")
	slotBg:SetTexture(M .. "slot")
	slotBg:SetVertexColor(SLOTBG[1], SLOTBG[2], SLOTBG[3], 1)
	slotBg:SetAllPoints()
	local icon = slotBox:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if slotBox.CreateMaskTexture and icon.AddMaskTexture then
		local mask = slotBox:CreateMaskTexture()
		mask:SetTexture(M .. "slot", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
	end
	local edge = slotBox:CreateTexture(nil, "OVERLAY")
	edge:SetTexture(M .. "slotedge")
	edge:SetAllPoints()
	r.slotBox, r.icon, r.edge = slotBox, icon, edge

	local nameFS = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	nameFS:SetPoint("TOPLEFT", slotBox, "TOPRIGHT", 8, -3)
	nameFS:SetWidth(235)
	nameFS:SetJustifyH("LEFT")
	if nameFS.SetWordWrap then nameFS:SetWordWrap(false) end
	r.nameFS = nameFS

	local subFS = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	subFS:SetPoint("BOTTOMLEFT", slotBox, "BOTTOMRIGHT", 8, 3)
	subFS:SetWidth(265)
	subFS:SetJustifyH("LEFT")
	if subFS.SetWordWrap then subFS:SetWordWrap(false) end
	r.subFS = subFS

	local rightTop = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	rightTop:SetPoint("TOPRIGHT", -8, -4)
	rightTop:SetJustifyH("RIGHT")
	r.rightTop = rightTop

	local rightBot = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	rightBot:SetPoint("BOTTOMRIGHT", -8, 4)
	rightBot:SetJustifyH("RIGHT")
	r.rightBot = rightBot

	r:SetScript("OnEnter", ShowRowTooltip)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", OnRowClick)
	r:SetScript("OnReceiveDrag", function() if ns.StoreCursorItem then ns.StoreCursorItem() end end)

	rows[i] = r
	return r
end

local function FormatRankBadge(i)
	if i == 1 then return "|cffffd100#1|r" end
	if i == 2 then return "|cffd8d8e2#2|r" end
	if i == 3 then return "|cffd99058#3|r" end
	return format("|cff8c8c8c#%d|r", i)
end

local function PaintRow(r, idx, e, rowW, yOffset)
	r.entry = e
	r:SetWidth(rowW)
	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", mkt.content, "TOPLEFT", 0, -yOffset)

	if e.isHeader then
		r:SetHeight(HEADER_H)
		r:EnableMouse(false)
		r.bg:SetColorTexture(0.83, 0.66, 0.31, 0.16)
		r.hl:SetAlpha(0)
		r.rank:Hide()
		r.slotBox:Hide()
		r.subFS:SetText("")
		r.rightBot:SetText("")
		r.rightTop:ClearAllPoints()
		r.rightTop:SetPoint("RIGHT", r, "RIGHT", -8, 0)
		r.rightTop:SetText("|cffd4a94e" .. (e.rightText or "") .. "|r")
		local rightW = (r.rightTop:GetStringWidth() or 120) + 20
		r.nameFS:ClearAllPoints()
		r.nameFS:SetPoint("LEFT", r, "LEFT", 8, 0)
		r.nameFS:SetWidth(max(120, rowW - rightW))
		r.nameFS:SetText("|cffffd100" .. (e.title or "") .. "|r")
		r:Show()
		return HEADER_H
	end

	r:SetHeight(ROW_H)
	r:EnableMouse(true)
	r.bg:SetColorTexture(1, 1, 1, (idx % 2 == 0) and 0.025 or 0.05)
	r.hl:SetAlpha(1)
	r.rank:Show()
	r.slotBox:Show()
	r.nameFS:ClearAllPoints()
	r.nameFS:SetPoint("TOPLEFT", r.slotBox, "TOPRIGHT", 8, -3)
	r.nameFS:SetWidth(rowW - 150)
	r.subFS:SetWidth(rowW - 135)
	r.rightTop:ClearAllPoints()
	r.rightTop:SetPoint("TOPRIGHT", -8, -4)

	r.rank:SetText(FormatRankBadge(e.displayRank or idx))
	r.icon:SetTexture(e.icon or 134400)

	local qr, qg, qb, qHex = QualityColor(e.quality)
	if (e.quality or 1) >= 2 then
		r.edge:SetVertexColor(qr, qg, qb, 0.9)
	else
		r.edge:SetVertexColor(TRIM[1], TRIM[2], TRIM[3], 1)
	end

	local dispName = e.name
	if not dispName then
		dispName = "Item #" .. tostring(e.id)
		if RequestLoadItemData and not pendingItemLoad[e.id] then
			pendingItemLoad[e.id] = true
			pcall(RequestLoadItemData, e.id)
		end
	end
	local qtyTag = (e.outQty and e.outQty > 1 and e.profSection == "buyout") and format(" |cffd4a94e(x%d)|r", e.outQty) or ""
	local bagTag = (e.bagCount and e.bagCount > 0) and format(" |cff5cd65c[x%d]|r", e.bagCount) or ""
	r.nameFS:SetText(qHex .. dispName .. "|r" .. qtyTag .. bagTag)

	if activeTab == 1 then
		-- Margin (lowest buyout offer vs. next highest offer of the same item)
		local tradeTag = (e.turn and e.turn > 0) and format(" • %s trades", Group(e.turn)) or ""
		r.subFS:SetText(format("|cff5cd65c[Flip x%d]|r Buy %s -> Next %s%s", e.buyQty or 1, CompactMoney(e.price), CompactMoney(e.target), tradeTag))
		r.rightTop:SetText("|cff5cd65c+" .. CompactMoney(e.profit) .. "|r")
		r.rightBot:SetText(format("|cff5cd65c+%.0f%% net|r", min(999, e.pct or 0)))

	elseif activeTab == 2 then
		-- Scarce
		local parts = {}
		if e.basePrice and e.basePrice > 0 and e.basePrice ~= e.price then
			parts[#parts + 1] = "Avg: " .. CompactMoney(e.basePrice)
		end
		parts[#parts + 1] = format("%s listed (%s %s)", Group(e.qty or 1), Group(e.posts or 1), (e.posts == 1) and "post" or "posts")
		if e.turn and e.turn > 0 then
			parts[#parts + 1] = format("|cff5cd65cTrades: %s|r", Group(e.turn))
		end
		r.subFS:SetText(table.concat(parts, " • "))
		r.rightTop:SetText(CompactMoney(e.price))
		r.rightBot:SetText(format("|cffffd100Scarce (%d left)|r", e.qty or 1))

	elseif activeTab == 3 then
		-- Professions (Buyout Opportunity & Top Trades)
		if e.profSection == "buyout" then
			local tradeStr
			if e.turn and e.turn > 0 then
				tradeStr = format("|cff5cd65cTrades: %s|r", Group(e.turn))
			elseif e.bids and e.bids > 0 then
				tradeStr = format("|cffffd100%d %s|r", e.bids, e.bids == 1 and "bid" or "bids")
			else
				tradeStr = format("%s %s", Group(e.posts or 1), (e.posts == 1) and "post" or "posts")
			end
			r.subFS:SetText(format("Make: %s -> Sell: %s • %s", CompactMoney(e.craftCost), CompactMoney(e.sellGross), tradeStr))
			if (e.profit or 0) > 0 then
				r.rightTop:SetText("|cff5cd65c+" .. CompactMoney(e.profit) .. "|r")
				r.rightBot:SetText(format("|cff5cd65c+%.0f%% net|r", min(999, e.pct or 0)))
			else
				r.rightTop:SetText("|cffff6b6b-" .. CompactMoney(abs(e.profit or 0)) .. "|r")
				r.rightBot:SetText(format("|cffff6b6b%.0f%% loss|r", max(-999, e.pct or 0)))
			end
		else
			-- Top Trades section
			if e.craftCost and e.sellGross then
				local pStr = (e.profit and e.profit > 0)
					and ("|cff5cd65c+" .. CompactMoney(e.profit) .. "|r")
					or ("|cffff6b6b-" .. CompactMoney(abs(e.profit or 0)) .. "|r")
				r.subFS:SetText(format("|cff66ccff[Craft]|r Make: %s -> Sell: %s (%s)", CompactMoney(e.craftCost), CompactMoney(e.sellGross), pStr))
			else
				local tag = e.isCraft and "|cff66ccff[Craft]|r" or "|cffd4a94e[Reagent]|r"
				local bidStr = (e.bids and e.bids > 0) and format(" • |cffffd100%d %s|r", e.bids, e.bids == 1 and "bid" or "bids") or ""
				r.subFS:SetText(format("%s %s listed (%s %s)%s", tag, Group(e.qty or 1), Group(e.posts or 1), (e.posts == 1) and "post" or "posts", bidStr))
			end
			r.rightTop:SetText(CompactMoney(e.price))
			if e.turn and e.turn > 0 then
				r.rightBot:SetText(format("|cff5cd65cTrades: %s|r", Group(e.turn)))
			elseif e.bids and e.bids > 0 then
				r.rightBot:SetText(format("|cffffd100%d %s|r", e.bids, e.bids == 1 and "bid" or "bids"))
			else
				r.rightBot:SetText(format("|cff8c8c8c%s posts|r", Group(e.posts or 1)))
			end
		end

	elseif activeTab == 4 then
		-- Bag Advisor
		if e.advice == "sell" then
			local why = (e.pct >= 10) and format("+%.0f%% above avg", e.pct) or format("Low supply (%d posts)", e.posts or 1)
			r.subFS:SetText(format("|cff5cd65c[Sell Now]|r %s • %s/ea", why, CompactMoney(e.price)))
			r.rightTop:SetText(CompactMoney(e.netStack))
			r.rightBot:SetText("|cff5cd65cPeak AH Value|r")
		elseif e.advice == "monopoly" then
			r.subFS:SetText("|cffffd100[Monopoly]|r 0 Listed on AH!")
			r.rightTop:SetText(e.vendorPrice and e.vendorPrice > 0 and CompactMoney(e.vendorPrice * e.bagCount) or "Unlisted")
			r.rightBot:SetText("|cffffd100Set Your Price|r")
		elseif e.advice == "vendor" then
			r.subFS:SetText(format("|cffff9933[Vendor]|r NPC %s > AH Net %s", CompactMoney(e.vendorPrice), CompactMoney(e.netUnit)))
			r.rightTop:SetText(CompactMoney((e.vendorPrice or 0) * e.bagCount))
			r.rightBot:SetText("|cffff9933Sell to Vendor|r")
		elseif e.advice == "hold" then
			r.subFS:SetText(format("|cffff6b6b[Hold]|r Down %.0f%% vs avg • %s/ea", abs(e.pct), CompactMoney(e.price)))
			r.rightTop:SetText(CompactMoney(e.netStack))
			r.rightBot:SetText("|cffff6b6bHold / Wait|r")
		elseif e.advice == "uncached" then
			r.subFS:SetText("|cff8c8c8cVisit Auction House to scan price|r")
			r.rightTop:SetText(e.vendorPrice and e.vendorPrice > 0 and CompactMoney(e.vendorPrice * e.bagCount) or "—")
			r.rightBot:SetText("|cff8c8c8cUncached|r")
		else
			r.subFS:SetText(format("Unit: %s • Net stack (95%%)", CompactMoney(e.price)))
			r.rightTop:SetText(CompactMoney(e.netStack))
			r.rightBot:SetText("|cff8c8c8cFair Market|r")
		end
	end

	r:Show()
	return ROW_H
end

---------------------------------------------------------------------------
-- Header Pulse & Refresh
---------------------------------------------------------------------------
function ns.UpdateMarketScanProgressOnly()
	if not (mkt and mkt:IsShown() and mkt.stat1Val) then return end
	if ns.ahScanning then
		mkt.stat1Val:SetText(ns.ahScanProgress and format("|cffd4a94eScanning %d%%…|r", ns.ahScanProgress) or "|cffd4a94eScanning AH…|r")
	end
end

local function UpdatePulseSummary()
	local market = ns.db and ns.db.ahMarket or {}
	local totalItems, totalPosts, totalTrades = 0, 0, 0
	for _, m in pairs(market) do
		totalItems = totalItems + 1
		totalPosts = totalPosts + (m.n or 0)
		totalTrades = totalTrades + (m.turn or 0)
	end
	local cached = max(totalItems, ns.ahCachedCount or 0)
	local age = (ns.db and ns.db.ahUpdated and ns.FormatAge and ns.FormatAge(ns.db.ahUpdated)) or nil
	if ns.ahScanning then
		mkt.stat1Val:SetText(ns.ahScanProgress and format("|cffd4a94eScanning %d%%…|r", ns.ahScanProgress) or "|cffd4a94eScanning AH…|r")
	else
		mkt.stat1Val:SetText(format("%s items", Group(cached)))
	end
	mkt.stat1Sub:SetText(age and ("Updated " .. age) or "Visit AH to scan")

	if totalTrades > 0 then
		mkt.stat2Val:SetText(format("|cff5cd65c%s trades|r", Group(totalTrades)))
	elseif cached > 0 then
		mkt.stat2Val:SetText("|cffd4a94eSnapshot Ready|r")
	else
		mkt.stat2Val:SetText("|cff8c8c8cNo Data|r")
	end
	mkt.stat2Sub:SetText(totalPosts > 0 and format("%s active posts", Group(totalPosts)) or "Market Activity")

	local bagVal = ns.GetBagAhSummary and select(1, ns.GetBagAhSummary()) or 0
	local netBag = floor(bagVal * AH_CUT + 0.5)
	mkt.stat3Val:SetText(CompactMoney(netBag))
	mkt.stat3Sub:SetText("Your Bags (95% net)")
end

local function SyncHeight()
	if not mkt then return end
	local bags = ns.frame
	local bagH = (bags and bags:IsShown() and bags:GetHeight()) or 480
	local h = max(MIN_HEIGHT, min(MAX_HEIGHT, floor(bagH + 0.5)))
	mkt:SetSize(WIDTH, h)
	local hasSub = SUB_FILTERS[activeTab] ~= nil
	local topShift = hasSub and 0 or 26
	if mkt.secTitle and mkt.secLine and mkt.scroll then
		mkt.secTitle:SetPoint("TOPLEFT", PAD, -166 + topShift)
		mkt.secTitle:SetPoint("TOPRIGHT", -PAD, -166 + topShift)
		mkt.secLine:SetPoint("TOPLEFT", PAD, -184 + topShift)
		mkt.secLine:SetPoint("TOPRIGHT", -PAD, -184 + topShift)
		mkt.scroll:SetPoint("TOPLEFT", PAD, -190 + topShift)
		local scrollH = max(140, h - (198 - topShift) - 30)
		mkt.scroll:SetSize(WIDTH - PAD * 2 - 14, scrollH)
	end
end

local function EnsureSubBtn(i)
	local b = subBtns[i]
	if b then return b end
	b = CreateFrame("Button", nil, mkt.subBar)
	b:SetHeight(18)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	b.bg = bg
	local fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	fs:SetPoint("CENTER", 0, 0)
	b.fs = fs
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 0.82, 0, 0.12)
	subBtns[i] = b
	return b
end

local function ApplyWindowWidth()
	if not mkt then return end
	mkt:SetWidth(WIDTH)
	local cardW = floor((WIDTH - PAD * 2 - 12) / 3)
	for i = 1, 3 do
		local c = statCards[i]
		if c then
			c:SetSize(cardW, 38)
			c:SetPoint("TOPLEFT", PAD + (i - 1) * (cardW + 6), -40)
		end
	end
	local tabW = floor((WIDTH - PAD * 2 - 9) / 4)
	for i = 1, #TABS do
		local b = tabBtns[i]
		if b then
			b:SetSize(tabW, 24)
			b:SetPoint("TOPLEFT", PAD + (i - 1) * (tabW + 3), -110)
		end
	end
	if mkt.subBar then mkt.subBar:SetWidth(WIDTH - PAD * 2) end
	if mkt.emptyFS then mkt.emptyFS:SetWidth(WIDTH - PAD * 2 - 40) end
	SyncHeight()
end

local function EnsureMinWidthForProfTabs()
	if widthMeasured or not (mkt and mkt.subBar) then return end
	local profList = SUB_FILTERS[3]
	if not profList then return end
	local minW, padW, gap = 46, 12, 4
	local reqBarW = 0
	for i = 1, #profList do
		local b = EnsureSubBtn(i)
		b.fs:SetText(profList[i].label)
		local sw = b.fs:GetStringWidth() or 0
		if sw > 0 then widthMeasured = true end
		local w = max(minW, floor(sw + padW + 0.5))
		reqBarW = reqBarW + w + (i > 1 and gap or 0)
	end
	local reqW = reqBarW + PAD * 2
	if reqW > WIDTH then
		WIDTH = reqW
		ApplyWindowWidth()
	end
end

local function RefreshSubFilterBar()
	EnsureMinWidthForProfTabs()
	local list = SUB_FILTERS[activeTab]
	if not list or #list == 0 then
		mkt.subBar:Hide()
		for i = 1, #subBtns do subBtns[i]:Hide() end
		SyncHeight()
		return
	end
	mkt.subBar:Show()
	SyncHeight()

	local cur = activeSub[activeTab] or list[1].key
	local minW, padW, gap = 46, 12, 4
	local x = 0
	for i = 1, #list do
		local spec = list[i]
		local b = EnsureSubBtn(i)
		b.fs:SetText(spec.label)
		local w = max(minW, floor((b.fs:GetStringWidth() or 38) + padW + 0.5))
		b:SetWidth(w)
		b:ClearAllPoints()
		b:SetPoint("LEFT", mkt.subBar, "LEFT", x, 0)
		local selected = (spec.key == cur)
		if selected then
			b.bg:SetColorTexture(0.83, 0.66, 0.31, 0.28)
			b.fs:SetTextColor(1, 0.86, 0.35)
		else
			b.bg:SetColorTexture(1, 1, 1, 0.06)
			b.fs:SetTextColor(0.78, 0.78, 0.80)
		end
		b:SetScript("OnClick", function()
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			activeSub[activeTab] = spec.key
			if mkt.scroll and mkt.scroll.SetVerticalScroll then
				mkt.scroll:SetVerticalScroll(0)
			end
			ns.RefreshMarket()
		end)
		b:Show()
		x = x + w + gap
	end
	for i = #list + 1, #subBtns do subBtns[i]:Hide() end
end

local function RefreshTabButtons()
	for i, spec in ipairs(TABS) do
		local b = tabBtns[i]
		if b then
			local on = (i == activeTab)
			if on then
				b.bg:SetColorTexture(0.83, 0.66, 0.31, 0.30)
				b.edge:SetColorTexture(0.85, 0.68, 0.25, 0.9)
				b.fs:SetTextColor(1, 0.86, 0.35)
			else
				b.bg:SetColorTexture(0.12, 0.12, 0.14, 0.75)
				b.edge:SetColorTexture(1, 1, 1, 0.14)
				b.fs:SetTextColor(0.82, 0.82, 0.85)
			end
		end
		if i == activeTab and mkt.secTitle then
			if activeTab == 3 then
				local pMetaAll = EnsureProfMeta()
				local pMeta = pMetaAll[activeSub[3] or "alch"] or pMetaAll.alch
				mkt.secTitle:SetText(format("%s — Cost to Make & Top Trades", pMeta.name))
			else
				mkt.secTitle:SetText(spec.title)
			end
		end
	end
end

function ns.RefreshMarket()
	if not (mkt and mkt:IsShown()) then return end
	UpdatePulseSummary()
	RefreshTabButtons()
	RefreshSubFilterBar()
	BuildEntries()

	local count = min(#entries, MAX_ROWS)
	local rowW = mkt.scroll:GetWidth() or (WIDTH - PAD * 2 - 14)
	local yOffset = 0
	for i = 1, count do
		local r = GetRow(i)
		local h = PaintRow(r, i, entries[i], rowW, yOffset)
		yOffset = yOffset + h + ROW_GAP
	end
	for i = count + 1, #rows do
		rows[i]:Hide()
		rows[i].entry = nil
	end

	local totalH = max(1, yOffset - ROW_GAP)
	mkt.content:SetSize(rowW, totalH)
	if mkt.scroll and mkt.scroll.GetVerticalScroll and mkt.scroll.SetVerticalScroll then
		local maxS = max(0, totalH - (mkt.scroll:GetHeight() or 280))
		if (mkt.scroll:GetVerticalScroll() or 0) > maxS then
			mkt.scroll:SetVerticalScroll(maxS)
		end
	end

	if count == 0 then
		local cached = ns.ahCachedCount or 0
		if cached == 0 then
			mkt.emptyFS:SetText("No Auction House data cached yet.\n\nOpen the Auction House in any city and Dave's Sack will automatically scan and cache market prices, supply, and margins.")
		elseif activeTab == 1 then
			mkt.emptyFS:SetText("No liquid items currently match the Market Flip margin filter.\n\n(Trash items and low-volume random-stat BoE gear are automatically filtered out.)")
		elseif activeTab == 2 then
			mkt.emptyFS:SetText("No scarce market items (1–5 units left) match your current search.")
		else
			mkt.emptyFS:SetText("No matching items found for this filter.")
		end
		mkt.emptyFS:Show()
	else
		mkt.emptyFS:Hide()
	end

	if activeTab == 1 then
		mkt.footHint:SetText("Compares lowest buyout vs. next highest offer (minus 5% AH cut). Click to find in bags.")
	elseif activeTab == 2 then
		mkt.footHint:SetText("Shows commodities with only 1–5 total units left on the Auction House.")
	elseif activeTab == 3 then
		mkt.footHint:SetText("Compares ingredient cost (AH/Vendor) vs. 95% net sell price. Hover for full recipe.")
	else
		mkt.footHint:SetText("Compares tradeable items in your bags against live AH prices & vendor value.")
	end
end

---------------------------------------------------------------------------
-- Positioning beside DavesSackFrame
---------------------------------------------------------------------------
local function DockToBags(force)
	if not mkt then return end
	if userDragged and not force then
		SyncHeight()
		return
	end
	userDragged = false
	SyncHeight()
	mkt:ClearAllPoints()
	local bags = ns.frame
	local left = bags and bags:IsShown() and bags:GetLeft()
	if left then
		local roomLeft = left * bags:GetEffectiveScale() / mkt:GetEffectiveScale()
		if roomLeft > WIDTH + 16 then
			mkt:SetPoint("TOPRIGHT", bags, "TOPLEFT", -8, 0)
		else
			mkt:SetPoint("TOPLEFT", bags, "TOPRIGHT", 8, 0)
		end
	else
		mkt:SetPoint("CENTER")
	end
end

function ns.SyncMarketAnchor()
	if mkt and mkt:IsShown() then
		DockToBags(false)
		ns.RefreshMarket()
	end
end

---------------------------------------------------------------------------
-- Build Window (lazy: created on first open)
---------------------------------------------------------------------------
local function Build()
	mkt = CreateFrame("Frame", "DavesSackMarket", UIParent)
	ns.marketFrame = mkt
	mkt:SetSize(WIDTH, 490)
	mkt:SetScale((ns.db and ns.db.scale) or 1)
	mkt:SetFrameStrata("HIGH")
	mkt:SetFrameLevel(12)
	mkt:SetClampedToScreen(true)
	mkt:EnableMouse(true)
	mkt:SetMovable(true)
	mkt:RegisterForDrag("LeftButton")
	if mkt.SetDontSavePosition then mkt:SetDontSavePosition(true) end
	mkt:SetScript("OnDragStart", function(self)
		if not (CursorHasItem and CursorHasItem()) then
			userDragged = true
			self:StartMoving()
		end
	end)
	mkt:SetScript("OnDragStop", mkt.StopMovingOrSizing)
	mkt:SetScript("OnReceiveDrag", function() if ns.StoreCursorItem then ns.StoreCursorItem() end end)
	mkt:Hide()
	tinsert(UISpecialFrames, "DavesSackMarket")

	local border = TryTemplate("Frame", nil, mkt, "DialogBorderTranslucentTemplate")
	if border then
		border:SetAllPoints()
	else
		border = CreateFrame("Frame", nil, mkt, BackdropTemplateMixin and "BackdropTemplate" or nil)
		border:SetAllPoints()
		border:SetFrameLevel(mkt:GetFrameLevel())
		border:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		border:SetBackdropColor(0, 0, 0, 0.8)
	end
	ns.marketBorder = border
	if ns.ApplyBackground then ns.ApplyBackground() end

	-- Header Title + Gavel Icon
	local title = mkt:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOP", 10, -15)
	title:SetText("Market Analysis")
	local titleIcon = mkt:CreateTexture(nil, "ARTWORK")
	titleIcon:SetSize(18, 18)
	titleIcon:SetPoint("RIGHT", title, "LEFT", -6, 0)
	titleIcon:SetTexture(M .. "gavel")

	local close = TryTemplate("Button", nil, mkt, "UIPanelCloseButton")
	if close then
		close:SetPoint("TOPRIGHT")
	else
		close = CreateFrame("Button", nil, mkt)
		close:SetSize(32, 32)
		close:SetPoint("TOPRIGHT", 2, 2)
		close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
		close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
		close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
	end
	close:SetFrameLevel(mkt:GetFrameLevel() + 5)
	close:SetScript("OnClick", function() mkt:Hide() end)

	-- 3 Market Pulse Summary Cards (y = -40)
	local cardW = floor((WIDTH - PAD * 2 - 12) / 3)
	local function MakeStatCard(idx, label)
		local c = CreateFrame("Frame", nil, mkt)
		c:SetSize(cardW, 38)
		c:SetPoint("TOPLEFT", PAD + (idx - 1) * (cardW + 6), -40)
		statCards[idx] = c
		local bg = c:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.045)
		local topLine = c:CreateTexture(nil, "ARTWORK")
		topLine:SetHeight(1)
		topLine:SetPoint("TOPLEFT"); topLine:SetPoint("TOPRIGHT")
		topLine:SetColorTexture(0.83, 0.66, 0.31, 0.35)
		local val = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		val:SetPoint("TOP", 0, -6)
		local sub = c:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		sub:SetPoint("BOTTOM", 0, 5)
		sub:SetText(label)
		return val, sub
	end
	mkt.stat1Val, mkt.stat1Sub = MakeStatCard(1, "AH Database")
	mkt.stat2Val, mkt.stat2Sub = MakeStatCard(2, "Market Pulse")
	mkt.stat3Val, mkt.stat3Sub = MakeStatCard(3, "Your Bags (95%)")

	-- Single Search Bar above the main tabs (y = -84)
	local mSearch = TryTemplate("EditBox", "DavesSackMarketSearch", mkt, "SearchBoxTemplate")
	if mSearch then
		mSearch:SetHeight(20)
		mSearch:SetPoint("TOPLEFT", PAD + 6, -84)
		mSearch:SetPoint("TOPRIGHT", -PAD, -84)
	else
		mSearch = CreateFrame("EditBox", "DavesSackMarketSearch", mkt, "InputBoxTemplate")
		mSearch:SetAutoFocus(false)
		mSearch:SetHeight(20)
		mSearch:SetPoint("TOPLEFT", PAD + 4, -84)
		mSearch:SetPoint("TOPRIGHT", -PAD, -84)
	end
	local function OnMarketSearch(self)
		local t = self:GetText()
		searchFilter = (t and t ~= "") and string.lower(t) or nil
		if mkt.scroll and mkt.scroll.SetVerticalScroll then
			mkt.scroll:SetVerticalScroll(0)
		end
		ns.RefreshMarket()
	end
	if mSearch.HookScript then
		mSearch:HookScript("OnTextChanged", OnMarketSearch)
	else
		mSearch:SetScript("OnTextChanged", OnMarketSearch)
	end
	mSearch:SetScript("OnEnterPressed", mSearch.ClearFocus)
	mkt.search = mSearch

	-- 4 Primary Mode Tabs (y = -110)
	local tabW = floor((WIDTH - PAD * 2 - 9) / 4)
	for i, spec in ipairs(TABS) do
		local b = CreateFrame("Button", nil, mkt)
		b:SetSize(tabW, 24)
		b:SetPoint("TOPLEFT", PAD + (i - 1) * (tabW + 3), -110)
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		b.bg = bg
		local edge = b:CreateTexture(nil, "ARTWORK")
		edge:SetHeight(2)
		edge:SetPoint("BOTTOMLEFT"); edge:SetPoint("BOTTOMRIGHT")
		b.edge = edge
		local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		fs:SetPoint("CENTER", 0, 1)
		fs:SetText(spec.label)
		b.fs = fs
		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.08)
		b:SetScript("OnClick", function()
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			activeTab = i
			if mkt.scroll and mkt.scroll.SetVerticalScroll then mkt.scroll:SetVerticalScroll(0) end
			ns.RefreshMarket()
		end)
		tabBtns[i] = b
	end

	-- Sub-filter bar (y = -140, fits all profession tabs side-by-side without arrows)
	local subBar = CreateFrame("Frame", nil, mkt)
	subBar:SetSize(WIDTH - PAD * 2, 20)
	subBar:SetPoint("TOPLEFT", PAD, -140)
	mkt.subBar = subBar

	-- Section Header + Divider
	local secTitle = mkt:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	secTitle:SetPoint("TOPLEFT", PAD, -166)
	secTitle:SetPoint("TOPRIGHT", -PAD, -166)
	secTitle:SetJustifyH("LEFT")
	mkt.secTitle = secTitle

	local secLine = mkt:CreateTexture(nil, "ARTWORK")
	secLine:SetHeight(1)
	secLine:SetColorTexture(1, 1, 1, 0.14)
	secLine:SetPoint("TOPLEFT", PAD, -184)
	secLine:SetPoint("TOPRIGHT", -PAD, -184)
	mkt.secLine = secLine

	-- Scrollable List Area (y = -190 when subBar visible, -164 when subBar hidden)
	local scroll = TryTemplate("ScrollFrame", "DavesSackMarketScroll", mkt, "ScrollFrameTemplate")
	local nativeBar = scroll and scroll.ScrollBar
	if not nativeBar then
		scroll = scroll or CreateFrame("ScrollFrame", "DavesSackMarketScroll", mkt)
	end
	scroll:SetPoint("TOPLEFT", PAD, -190)
	scroll:SetSize(WIDTH - PAD * 2 - 14, 280)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(WIDTH - PAD * 2 - 14, 1)
	scroll:SetScrollChild(content)
	if nativeBar then
		if nativeBar.SetHideIfUnscrollable then nativeBar:SetHideIfUnscrollable(true) end
		nativeBar:ClearAllPoints()
		nativeBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
		nativeBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
		if scroll.SetPanExtent then scroll:SetPanExtent(ROW_H + ROW_GAP) end
	else
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local cur = self:GetVerticalScroll() or 0
			local maxS = max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
			self:SetVerticalScroll(max(0, min(maxS, cur - delta * (ROW_H + ROW_GAP))))
		end)
	end
	mkt.scroll, mkt.content = scroll, content

	local emptyFS = mkt:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyFS:SetPoint("CENTER", scroll, "CENTER", 0, 10)
	emptyFS:SetWidth(WIDTH - PAD * 2 - 40)
	emptyFS:SetJustifyH("CENTER")
	if emptyFS.SetWordWrap then emptyFS:SetWordWrap(true) end
	emptyFS:Hide()
	mkt.emptyFS = emptyFS

	-- Footer divider & hint
	local footLine = mkt:CreateTexture(nil, "ARTWORK")
	footLine:SetHeight(1)
	footLine:SetColorTexture(1, 1, 1, 0.14)
	footLine:SetPoint("BOTTOMLEFT", PAD, 28)
	footLine:SetPoint("BOTTOMRIGHT", -PAD, 28)

	local footHint = mkt:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	footHint:SetPoint("BOTTOM", 0, 11)
	mkt.footHint = footHint

	-- Refresh item names when uncached item info arrives from the server
	mkt:SetScript("OnEvent", function(_, event, itemID)
		if event == "GET_ITEM_INFO_RECEIVED" and itemID and pendingItemLoad[itemID] then
			pendingItemLoad[itemID] = nil
			ns.RefreshMarket()
		end
	end)

	mkt:SetScript("OnShow", function(self)
		pcall(self.RegisterEvent, self, "GET_ITEM_INFO_RECEIVED")
		Sound("IG_MAINMENU_OPEN")
		if ns.SyncMarketButton then ns.SyncMarketButton() end
		ns.RefreshMarket()
	end)
	mkt:SetScript("OnHide", function(self)
		pcall(self.UnregisterEvent, self, "GET_ITEM_INFO_RECEIVED")
		if mkt.search then mkt.search:ClearFocus() end
		if ns.SyncMarketButton then ns.SyncMarketButton() end
		Sound("IG_MAINMENU_CLOSE")
	end)
end

function ns.IsMarketOpen()
	return mkt ~= nil and mkt:IsShown()
end

function ns.HideMarket()
	if mkt and mkt:IsShown() then
		mkt:Hide()
	end
end

function ns.ToggleMarket()
	if not mkt then Build() end
	if mkt:IsShown() then
		mkt:Hide()
	else
		DockToBags(true)
		mkt:Show()
	end
end
