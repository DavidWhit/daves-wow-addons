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

local WIDTH, MIN_HEIGHT, MAX_HEIGHT = 716, 480, 620
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
	{ id = 1, label = "Margin",       title = "Market Flip Margin Opportunities" },
	{ id = 2, label = "Scarce",       title = "Scarce Market Supply (1–5 Left)" },
	{ id = 3, label = "Professions",  title = "Profession Cost to Make & Top Trades" },
	{ id = 4, label = "Bag Advisor",  title = "Bag Market Advisor (Your Items)" },
	{ id = 5, label = "Bait & Snipe", title = "Material Bait & Counter-Snipe" },
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
local searchRaw = nil
local totalSearchMatches = 0
local userDragged = false
local rows, tabBtns, subBtns, statCards = {}, {}, {}, {}
local bagHoldings = {}
local bagHoldingsReady = false
local entries, entryPool = {}, {}
local searchMatches, searchPool = {}, {}
local searchIndex = {}
local metaCache = {}
local pendingItemLoad = {}
local profMeta

local function AcquireSearchCandidate(idx)
	local c = searchPool[idx]
	if not c then
		c = {}
		searchPool[idx] = c
	end
	return c
end

local function GetSearchLower(id, m, bagRec)
	local low = searchIndex[id]
	if low ~= nil then
		if low == false and m and m.nm and m.nm ~= "" then
			low = string.lower(m.nm)
			searchIndex[id] = low
			return low
		end
		return low or nil
	end
	local nm = (m and m.nm) or (metaCache[id] and metaCache[id].name)
	if (not nm or nm == "") and bagRec and bagRec.link then
		nm = string.match(bagRec.link, "%[(.-)%]")
	end
	if (not nm or nm == "") and GetItemInfo then
		nm = GetItemInfo(id)
		if m and nm and nm ~= "" then m.nm = nm end
	end
	if nm and nm ~= "" then
		low = string.lower(nm)
		searchIndex[id] = low
		return low
	end
	searchIndex[id] = false
	return nil
end

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

-- Resolves item metadata from in-memory cache / GetItemInfo / GetItemInfoInstant / cached market record.
local function ResolveItemMeta(id, m, bagRec)
	local c = metaCache[id]
	if c and (c.ready or (c.cached and not bagRec and (c.name or not (m and m.nm)))) then
		if m then
			if not m.nm and c.name then m.nm = c.name end
			if not m.qu and c.quality then m.qu = c.quality end
		end
		return c.name, c.link, c.quality, c.icon, c.vendorPrice, c.classID
	end
	local name, link, quality, _, _, _, _, _, _, icon, vendorPrice, classID
	local fullLoaded = false
	if GetItemInfo then
		name, link, quality, _, _, _, _, _, _, icon, vendorPrice, classID = GetItemInfo(id)
		if name and name ~= "" then fullLoaded = true end
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
	quality = quality or 1
	icon = icon or 134400
	vendorPrice = vendorPrice or 0
	if not c then
		c = {}
		metaCache[id] = c
	end
	c.name, c.link, c.quality, c.icon, c.vendorPrice, c.classID =
		name, link, quality, icon, vendorPrice, classID
	c.ready, c.cached = fullLoaded, true
	if name and name ~= "" then searchIndex[id] = string.lower(name) end
	return name, link, quality, icon, vendorPrice, classID
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
	local allOut = {}
	profMeta = { _allOutputs = allOut }
	for _, spec in ipairs(SUB_FILTERS[3]) do
		profMeta[spec.key] = { name = spec.name, recipes = {}, outputs = {}, reagents = {}, tradeIDs = {}, seenTradeID = {} }
	end
	for i = 1, #BUILTIN_RECIPES do
		local r = BUILTIN_RECIPES[i]
		local p = profMeta[r[1]]
		if p then
			local rec = { outID = r[2], qty = r[3], reags = r[4] }
			p.recipes[#p.recipes + 1] = rec
			if not p.outputs[r[2]] then
				p.outputs[r[2]] = rec
			end
			if not allOut[r[2]] then
				allOut[r[2]] = rec
			end
			if not VENDOR_BUY[r[2]] and not p.seenTradeID[r[2]] then
				p.seenTradeID[r[2]] = true
				p.tradeIDs[#p.tradeIDs + 1] = r[2]
			end
			for j = 1, #r[4] do
				local rID = r[4][j][1]
				if not VENDOR_BUY[rID] then
					p.reagents[rID] = true
					if not p.seenTradeID[rID] then
						p.seenTradeID[rID] = true
						p.tradeIDs[#p.tradeIDs + 1] = rID
					end
				end
			end
		end
	end
	for k, list in pairs(PROF_EXTRA_REAGENTS) do
		local p = profMeta[k]
		if p then
			for i = 1, #list do
				local rID = list[i]
				if not VENDOR_BUY[rID] then
					p.reagents[rID] = true
					if not p.seenTradeID[rID] then
						p.seenTradeID[rID] = true
						p.tradeIDs[#p.tradeIDs + 1] = rID
					end
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

local function BuildEntries(keepBags)
	wipe(entries)
	if not keepBags or not bagHoldingsReady then
		if ns.CollectBagHoldings then
			ns.CollectBagHoldings(bagHoldings)
		else
			wipe(bagHoldings)
		end
		bagHoldingsReady = true
	end

	local market = ns.db and ns.db.ahMarket or {}
	local prices = ns.db and ns.db.ahPrices or {}
	local poolIdx = 0

	if searchFilter then
		-- Global Market Search across all cached AH items and bag items (temporarily replaces main tabs)
		wipe(searchMatches)
		totalSearchMatches = 0
		local searchID = tonumber(searchFilter)
		local candIdx = 0

		for id, m in pairs(market) do
			local p = m.p or prices[id]
			if p and p > 0 then
				local bagRec = bagHoldings[id]
				local low = GetSearchLower(id, m, bagRec)
				local pos = low and find(low, searchFilter, 1, true) or nil
				if pos or (searchID and id == searchID) then
					totalSearchMatches = totalSearchMatches + 1
					local score
					if (searchID and id == searchID) or low == searchFilter then
						score = 1000000
					elseif pos == 1 then
						score = 300000
					else
						score = max(1000, (100 - min(98, pos or 99)) * 1000)
					end
					if bagRec then score = score + 80000 end
					score = score + min(40000, (m.turn or 0) * 60 + (m.n or 1) * 25)
					candIdx = candIdx + 1
					local c = AcquireSearchCandidate(candIdx)
					c.id, c.m, c.p, c.score = id, m, p, score
					searchMatches[#searchMatches + 1] = c
				end
			end
		end

		for id, bagRec in pairs(bagHoldings) do
			local m = market[id]
			local p = (m and m.p) or prices[id]
			if not (m and p and p > 0) then
				local low = GetSearchLower(id, m, bagRec)
				local pos = low and find(low, searchFilter, 1, true) or nil
				if pos or (searchID and id == searchID) then
					totalSearchMatches = totalSearchMatches + 1
					local score = ((searchID and id == searchID) or low == searchFilter) and 950000
						or (pos == 1 and 280000)
						or max(1000, (100 - min(98, pos or 99)) * 1000)
					score = score + 80000
					candIdx = candIdx + 1
					local c = AcquireSearchCandidate(candIdx)
					c.id, c.m, c.p, c.score = id, m, p or 0, score
					searchMatches[#searchMatches + 1] = c
				end
			end
		end

		sort(searchMatches, function(a, b)
			if a.score ~= b.score then return a.score > b.score end
			return (a.p or 0) > (b.p or 0)
		end)

		local pMetaAll = EnsureProfMeta()
		local allOut = pMetaAll._allOutputs
		local learned = ns.db and ns.db.ahRecipes or nil
		local topCount = min(#searchMatches, MAX_ROWS)
		for i = 1, topCount do
			local c = searchMatches[i]
			local id, m, p = c.id, c.m, c.p
			local bagRec = bagHoldings[id]
			local name, link, quality, icon, vendorPrice, classID = ResolveItemMeta(id, m, bagRec)
			local turn, bids, _, posts, qty = RecordTrades(m)
			local pct, basePrice = ComputeTrendPct(m)
			poolIdx = poolIdx + 1
			local e = AcquireEntry(poolIdx)
			e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice, e.classID =
				id, m, name, link, quality, icon, vendorPrice, classID
			e.bagCount = bagRec and bagRec.count or 0
			e.price, e.basePrice, e.pct, e.turn, e.bids, e.posts, e.qty =
				p, basePrice, pct, turn, bids, posts, qty

			if m and p and p > 0 then
				local flipProf, flipPct, flipTarget, kind, buyQty = ComputeMarketFlip(m, quality, vendorPrice, classID)
				if kind then
					e.kind, e.profit, e.pct, e.flipProfit, e.flipPct, e.target, e.buyQty =
						kind, flipProf, flipPct, flipProf, flipPct, flipTarget, buyQty or 1
				end
				local rec = allOut[id] or (learned and type(learned[id]) == "table" and learned[id])
				if rec and type(rec.reags) == "table" then
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
						e.craftProfit = sNet - cCost
						e.craftPct = (e.craftProfit / cCost) * 100
						if not e.profit then
							e.profit, e.pct = e.craftProfit, e.craftPct
						end
						e.reags = rec.reags
					end
				end
			end
			entries[#entries + 1] = e
		end

	elseif activeTab == 1 then
		-- Tab 1: Margin (Market Flips default, no child sub-tabs)
		for id, m in pairs(market) do
			local p = m.p or prices[id]
			local target = m.p2
			if p and p > 0 and target and target > p and target <= p * 3.5 then
				local posts = m.n or 1
				local totalQty = m.q or 1
				local floorQty = m.mq or totalQty
				if posts >= 5 and totalQty >= 6 and floorQty <= 40 and floorQty <= totalQty * 0.35 and (floor(target * AH_CUT) - p) >= 100 then
					local bagRec = bagHoldings[id]
					local name, link, quality, icon, vendorPrice, classID = ResolveItemMeta(id, m, bagRec)
					local profit, pct, flipTarget, kind, buyQty = ComputeMarketFlip(m, quality, vendorPrice, classID)
					if kind then
						local turn, bids, _, _, qty = RecordTrades(m)
						local depthBoost = min(3, max(1, posts / 8))
						local score = profit * depthBoost * (1 + min(1.5, pct / 80))
						poolIdx = poolIdx + 1
						local e = AcquireEntry(poolIdx)
						e.id, e.m, e.name, e.link, e.quality, e.icon, e.vendorPrice = id, m, name, link, quality, icon, vendorPrice
						e.bagCount = bagRec and bagRec.count or 0
						e.price, e.buyout, e.profit, e.pct, e.target, e.kind, e.buyQty, e.score =
							p, p, profit, pct, flipTarget, kind, buyQty or 1, score
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
			local posts = m.n or 1
			local qty = m.q or 0
			if p and p > 0 and posts > 0 and qty > 0 and qty <= 5 then
				local bagRec = bagHoldings[id]
				local name, link, quality, icon, vendorPrice, classID = ResolveItemMeta(id, m, bagRec)
				if quality >= 1 and classID ~= 2 and classID ~= 4 and not IsNoiseItem(m, quality, vendorPrice, classID) then
					local turn, bids = RecordTrades(m)
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
					if not VENDOR_BUY[outID] and not pMeta.seenTradeID[outID] then
						pMeta.seenTradeID[outID] = true
						pMeta.tradeIDs[#pMeta.tradeIDs + 1] = outID
					end
					for j = 1, #lr.reags do
						local rID = lr.reags[j] and lr.reags[j][1]
						if rID and not VENDOR_BUY[rID] then
							pMeta.reagents[rID] = true
							if not pMeta.seenTradeID[rID] then
								pMeta.seenTradeID[rID] = true
								pMeta.tradeIDs[#pMeta.tradeIDs + 1] = rID
							end
						end
					end
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
		local tradeIDs = pMeta.tradeIDs
		for i = 1, #tradeIDs do
			local id = tradeIDs[i]
			local m = market[id]
			if m then
				local p = m.p or prices[id]
				if p and p > 0 then
					local turn, bids, bidQty, posts, qty = RecordTrades(m)
					if turn > 0 or bids > 0 or posts >= 2 or qty >= 3 then
						local bagRec = bagHoldings[id]
						local name, link, quality, icon, vendorPrice = ResolveItemMeta(id, m, bagRec)
						local isCraft = outputRecipe[id] ~= nil
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
			local prof = e.craftProfit or e.profit or 0
			local cpct = e.craftPct or e.pct or 0
			if prof > 0 then
				GameTooltip:AddDoubleLine("Net Buyout Profit", "+" .. Money(prof) .. format(" (+%.0f%%)", cpct), 0.36, 0.84, 0.36, 0.36, 0.84, 0.36)
			else
				GameTooltip:AddDoubleLine("Net Craft Margin", "-" .. Money(abs(prof)) .. format(" (%.0f%%)", cpct), 1, 0.42, 0.42, 1, 0.42, 0.42)
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

	if searchFilter then
		-- Global Market Search row (across all AH & bag items)
		if e.kind == "flip" then
			local tradeTag = (e.turn and e.turn > 0) and format(" • %s trades", Group(e.turn)) or format(" • %s listed", Group(e.qty or 1))
			r.subFS:SetText(format("|cff5cd65c[Flip x%d]|r Buy %s -> Next %s%s", e.buyQty or 1, CompactMoney(e.price), CompactMoney(e.target), tradeTag))
			r.rightTop:SetText(CompactMoney(e.price))
			r.rightBot:SetText(format("|cff5cd65c+%s (+%.0f%%)|r", CompactMoney(e.flipProfit or e.profit), min(999, e.flipPct or e.pct or 0)))
		elseif e.craftCost and e.sellGross then
			local cp = e.craftProfit or e.profit or 0
			local cpct = e.craftPct or e.pct or 0
			local pStr = (cp > 0)
				and ("|cff5cd65c+" .. CompactMoney(cp) .. "|r")
				or ("|cffff6b6b-" .. CompactMoney(abs(cp)) .. "|r")
			r.subFS:SetText(format("|cff66ccff[Craft]|r Make: %s -> Sell: %s (%s) • %s listed", CompactMoney(e.craftCost), CompactMoney(e.sellGross), pStr, Group(e.qty or 1)))
			r.rightTop:SetText(CompactMoney(e.price))
			if cp > 0 then
				r.rightBot:SetText(format("|cff5cd65c+%.0f%% craft|r", min(999, cpct)))
			else
				r.rightBot:SetText(format("|cffff6b6b%.0f%% craft|r", max(-999, cpct)))
			end
		elseif e.price and e.price > 0 then
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
			if e.qty and e.qty > 0 and e.qty <= 5 and e.classID ~= 2 and e.classID ~= 4 then
				r.rightBot:SetText(format("|cffffd100Scarce (%d left)|r", e.qty))
			elseif e.turn and e.turn > 0 then
				r.rightBot:SetText(format("|cff5cd65cTrades: %s|r", Group(e.turn)))
			else
				r.rightBot:SetText(format("|cff8c8c8c%s %s|r", Group(e.posts or 1), (e.posts == 1) and "post" or "posts"))
			end
		else
			r.subFS:SetText("|cff8c8c8cIn your bags (not currently listed on AH)|r")
			r.rightTop:SetText(e.vendorPrice and e.vendorPrice > 0 and CompactMoney(e.vendorPrice * (e.bagCount or 1)) or "Unlisted")
			r.rightBot:SetText("|cff8c8c8cIn Bags|r")
		end

	elseif activeTab == 1 then
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
	local topShift
	if searchFilter then
		topShift = 54
	else
		local hasSub = SUB_FILTERS[activeTab] ~= nil
		topShift = hasSub and 0 or 26
	end
	if mkt.secTitle and mkt.secLine and mkt.scroll then
		mkt.secTitle:SetPoint("TOPLEFT", PAD, -166 + topShift)
		mkt.secTitle:SetPoint("TOPRIGHT", -PAD, -166 + topShift)
		mkt.secLine:SetPoint("TOPLEFT", PAD, -184 + topShift)
		mkt.secLine:SetPoint("TOPRIGHT", -PAD, -184 + topShift)
		mkt.scroll:SetPoint("TOPLEFT", PAD, -190 + topShift)
		local scrollH = max(140, h - (198 - topShift) - 30)
		mkt.scroll:SetSize(WIDTH - PAD * 2 - 14, scrollH)
	end
	if ns.SyncBaitHeight then
		ns.SyncBaitHeight(WIDTH, h, topShift)
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
	local tabW = floor((WIDTH - PAD * 2 - (#TABS - 1) * 3) / #TABS)
	for i = 1, #TABS do
		local b = tabBtns[i]
		if b then
			b:SetSize(tabW, 24)
			b:SetPoint("TOPLEFT", PAD + (i - 1) * (tabW + 3), -110)
		end
	end
	if mkt.subBar then mkt.subBar:SetWidth(WIDTH - PAD * 2) end
	if mkt.content then mkt.content:SetWidth(WIDTH - PAD * 2 - 14) end
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
	local maxMainTabW = 0
	for i = 1, #TABS do
		local tb = tabBtns[i]
		local sw = (tb and tb.fs and tb.fs:GetStringWidth()) or 0
		if sw > 0 then widthMeasured = true end
		local tw = floor(sw + 24 + 0.5)
		if tw > maxMainTabW then maxMainTabW = tw end
	end
	local reqMainW = maxMainTabW * #TABS + (#TABS - 1) * 3
	local reqW = max(reqBarW, reqMainW) + PAD * 2
	if reqW > WIDTH then
		WIDTH = reqW
		ApplyWindowWidth()
	end
end

local function RefreshSubFilterBar()
	EnsureMinWidthForProfTabs()
	if searchFilter then
		mkt.subBar:Hide()
		for i = 1, #subBtns do subBtns[i]:Hide() end
		SyncHeight()
		return
	end
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
	EnsureMinWidthForProfTabs()
	if searchFilter then
		for i = 1, #tabBtns do
			if tabBtns[i] then tabBtns[i]:Hide() end
		end
		return
	end
	for i, spec in ipairs(TABS) do
		local b = tabBtns[i]
		if b then
			b:Show()
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

local function RefreshMarketList(keepBags)
	if not (mkt and mkt:IsShown()) then return end
	if activeTab == 5 and not searchFilter then
		mkt.scroll:Hide()
		mkt.emptyFS:Hide()
		if mkt.footHint then
			mkt.footHint:SetText("Post 1 bait or turn ON Counter-Snipe Top 50 -> click the green Snipe banner (or macro) to buy!")
		end
		if ns.ShowBaitPanel then ns.ShowBaitPanel(mkt, WIDTH) end
		return
	end
	if ns.HideBaitPanel then ns.HideBaitPanel() end
	mkt.scroll:Show()
	BuildEntries(keepBags)

	if searchFilter and mkt.secTitle then
		mkt.secTitle:SetText(format("Global Market Search — %q (%s %s)", searchRaw or searchFilter, Group(totalSearchMatches), totalSearchMatches == 1 and "match" or "matches"))
	end

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
		elseif searchFilter then
			mkt.emptyFS:SetText(format("No cached Auction House or bag items match %q.", searchRaw or searchFilter))
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

	if searchFilter then
		mkt.footHint:SetText("Showing all matching AH & bag items across all categories. Clear search (X) to return to tabs.")
	elseif activeTab == 1 then
		mkt.footHint:SetText("Compares lowest buyout vs. next highest offer (minus 5% AH cut). Click to find in bags.")
	elseif activeTab == 2 then
		mkt.footHint:SetText("Shows commodities with only 1–5 total units left on the Auction House.")
	elseif activeTab == 3 then
		mkt.footHint:SetText("Compares ingredient cost (AH/Vendor) vs. 95% net sell price. Hover for full recipe.")
	else
		mkt.footHint:SetText("Compares tradeable items in your bags against live AH prices & vendor value.")
	end
end

function ns.RefreshMarket()
	if not (mkt and mkt:IsShown()) then return end
	UpdatePulseSummary()
	RefreshTabButtons()
	RefreshSubFilterBar()
	RefreshMarketList(false)
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
		local nextFilter = (t and t ~= "") and string.lower(t) or nil
		if nextFilter == searchFilter then return end
		local modeChanged = (nextFilter == nil) ~= (searchFilter == nil)
		searchFilter = nextFilter
		searchRaw = (t and t ~= "") and t or nil
		if not (mkt and mkt:IsShown()) then return end
		if modeChanged then
			RefreshTabButtons()
			RefreshSubFilterBar()
		end
		if mkt.scroll and mkt.scroll.SetVerticalScroll then
			mkt.scroll:SetVerticalScroll(0)
		end
		RefreshMarketList(true)
	end
	if mSearch.HookScript then
		mSearch:HookScript("OnTextChanged", OnMarketSearch)
	else
		mSearch:SetScript("OnTextChanged", OnMarketSearch)
	end
	mSearch:SetScript("OnEnterPressed", mSearch.ClearFocus)
	mkt.search = mSearch

	-- Primary Mode Tabs (y = -110)
	local tabW = floor((WIDTH - PAD * 2 - (#TABS - 1) * 3) / #TABS)
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
		if event == "GET_ITEM_INFO_RECEIVED" and itemID then
			metaCache[itemID] = nil
			searchIndex[itemID] = nil
			if ns.MarkBaitBagsDirty then ns.MarkBaitBagsDirty() end
			if pendingItemLoad[itemID] then
				pendingItemLoad[itemID] = nil
				RefreshMarketList(true)
			end
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
		if ns.HideBaitPanel then ns.HideBaitPanel() end
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

function ns.OpenMarketTab(tabId)
	if not mkt then Build() end
	if mkt.search and searchFilter then
		mkt.search:SetText("")
		searchFilter, searchRaw = nil, nil
	end
	activeTab = tabId or 1
	if not mkt:IsShown() then
		DockToBags(true)
		mkt:Show()
	else
		ns.RefreshMarket()
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

---------------------------------------------------------------------------
-- Tab 5: Material Bait & Snipe (isolated in its own do ... end scope)
-- Posts 1 single commodity unit at a deep undercut so sellers using Blizzard's
-- auto-fill price post stacks onto it, watches live order-book tiers every 2s,
-- and buys all non-owner units at <= Max Snipe % in a single hardware click
-- (WoW's Commodity AH skips your own 1 bait unit via numOwnerItems).
---------------------------------------------------------------------------
do
	local BAIT_PCTS = { 25, 35, 50, 65 }
	local SNIPE_PCTS = { 60, 75, 85 }
	local DECK_H = 118
	local B_ROW_H, B_HEAD_H, B_GAP = 34, 22, 2
	local GetMaxStack = C_Item and C_Item.GetItemMaxStackSizeByID
	local GetSlotInfo = C_Container and C_Container.GetContainerItemInfo
	local GetNumSlots = ns.GetNumSlots
	local issecretvalue = issecretvalue

	local bait = {
		panel = nil,
		evFrame = nil,
		ticker = nil,
		itemID = nil,
		baseline = {},        -- [itemID] = pre-bait real market floor in copper
		postedByUs = {},      -- [itemID] = true while our bait is live/pending (protects ahPrices)
		ownAuctionID = {},    -- [itemID] = auctionID for 1-click CancelAuction
		postingItemID = nil,
		postSeq = 0,
		pendingPost = nil,    -- { loc, dur, qty, price, itemID } awaiting ConfirmPostCommodity click
		pendingBuy = nil,     -- { itemID, qty, maxUnit, previewAvg, realFloor, quoteConfirmed, lockedUnit, lockedTotal }
		needSeparateQuery = false,
		queriedSeparate = false,
		ownQty = 0,
		ownUnit = nil,
		snipeQty = 0,
		snipeCost = 0,
		snipeAvg = 0,
		lastAlertItem = nil,
		lastAlertQty = 0,
		snipedUnits = 0,
		snipedProfit = 0,
		statusMsg = nil,
		statusColor = nil,
		actMode = "none",
		bagsDirty = true,
		lastOrderSig = nil,
		dismissedItem = nil,
		dismissedQty = 0,
		previewUntil = nil,
		previewConfirmed = false,
		hoverSnipeRow = false,
		lastMacroAt = 0,
		cancelingAt = 0,
		cancelingItem = nil,
		lastSoldAt = 0,
		internalQueryID = nil,
		internalQueryAt = 0,
		alert = nil,          -- standalone floating SNIPE FOUND! popup banner
		tiers = {},
		bagMats = {},
		bagHold = {},
		rows = {},
		baitPills = {},
		snipePills = {},
		cs = {                -- Counter-Snipe Top 50 Traded Materials radar
			enabled = false,
			btn = nil,
			keys = {},
			ids = {},
			idSet = {},
			refFloor = {},
			ignoreUntil = {},
			builtStamp = nil,
			awaitBrowse = false,
			browseActive = false,
			queryAt = nil,
			verifyID = nil,
			verifyAt = nil,
			verifySent = false,
			pauseUntil = nil,
			sweeps = 0,
			tickParity = 0,
			isCounterHit = false,
			returnTrapID = nil,
			pool = {},
		},
	}

	function ns.MarkBaitBagsDirty()
		bait.bagsDirty = true
	end

	local function PlaySnipeChime()
		if SOUNDKIT and SOUNDKIT.RAID_WARNING then
			local ok = pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
			if not ok then PlaySound(SOUNDKIT.RAID_WARNING) end
		end
		Sound("MAP_PING")
	end

	function ns.IsBaitProtectedItem(itemID)
		if itemID == nil then return false end
		if bait.postedByUs[itemID] == true or (bait.itemID == itemID and bait.ownQty > 0) then
			return true
		end
		if bait.cs.verifyID == itemID or (bait.cs.isCounterHit and bait.itemID == itemID) then
			return true
		end
		return false
	end

	function ns.IsBaitInternalQuery(itemID)
		if not (itemID and bait.internalQueryID == itemID) then return false end
		local now = (GetTime and GetTime()) or 0
		return (now - (bait.internalQueryAt or 0)) < 4.0
	end

	local function NotSecret(v)
		return v ~= nil and (not issecretvalue or not issecretvalue(v))
	end

	local function SanitizeUnitPrice(raw)
		local p = max(1, floor((raw or 1) + 0.5))
		if C_AuctionHouse and C_AuctionHouse.SupportsCopperValues and not C_AuctionHouse.SupportsCopperValues() then
			p = max(100, floor((p + 99) / 100) * 100)
		end
		return p
	end

	local function IsCommodityMaterial(id, classID)
		if not id or id <= 0 then return false end
		local cls = classID or (GetItemInfoInstant and select(6, GetItemInfoInstant(id)))
		if cls == 1 or cls == 2 or cls == 4 or cls == 11 or cls == 12 then
			return false -- exclude containers, weapons, armor, quivers, quest items
		end
		local ms = (GetMaxStack and GetMaxStack(id)) or (GetItemInfo and select(8, GetItemInfo(id)))
		if ms ~= nil then return ms > 1 end
		return cls == 0 or cls == 5 or cls == 6 or cls == 7 or cls == 8 or cls == 9
	end

	local function CountAndFindStack(itemID)
		if not (itemID and GetSlotInfo and GetNumSlots) then return 0, nil end
		local total, bestLoc, bestCount = 0, nil, nil
		local commEnum = (Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity) or 2
		local A = C_AuctionHouse
		local maxBag = NUM_BAG_SLOTS or 4
		for step = 0, maxBag + 1 do
			local bag = (step <= maxBag) and step or ns.REAGENT_BAG
			if bag then
				for slot = 1, (GetNumSlots(bag) or 0) do
					local info = GetSlotInfo(bag, slot)
					if info and info.itemID == itemID and not info.isBound and (info.stackCount or 0) > 0 then
						total = total + info.stackCount
						if not info.isLocked and not (ns.IsSlotAddonLocked and ns.IsSlotAddonLocked(bag, slot))
							and ItemLocation and ItemLocation.CreateFromBagAndSlot then
							local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
							if loc and loc:IsValid() then
								local okC = not (A and A.GetItemCommodityStatus) or A.GetItemCommodityStatus(loc) == commEnum
								local okS = not (A and A.IsSellItemValid) or A.IsSellItemValid(loc, false)
								-- Prefer smallest stack in bags so posting 1 unit peels from a partial stack first
								if okC and okS and (not bestCount or info.stackCount < bestCount) then
									bestLoc, bestCount = loc, info.stackCount
								end
							end
						end
					end
				end
			end
		end
		return total, bestLoc
	end

	local function SetStatus(msg, r, g, b)
		bait.statusMsg = msg
		bait.statusColor = msg and { r or 0.78, g or 0.78, b or 0.82 } or nil
	end

	local RefreshBaitUI

	local function QueryLiveItem(itemID, separateOwner)
		local A = C_AuctionHouse
		if not (itemID and ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen() and A and A.MakeItemKey) then return false end
		if A.IsThrottledMessageSystemReady and not A.IsThrottledMessageSystemReady() then return false end
		local key = A.MakeItemKey(itemID)
		bait.internalQueryID = itemID
		bait.internalQueryAt = (GetTime and GetTime()) or 0
		if not separateOwner and A.HasSearchResults and A.RefreshCommoditySearchResults and A.HasSearchResults(key) then
			bait.queriedSeparate = false
			pcall(A.RefreshCommoditySearchResults, itemID)
			return true
		elseif A.SendSearchQuery then
			bait.queriedSeparate = separateOwner and true or false
			local sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
			pcall(A.SendSearchQuery, key, { { sortOrder = sortOrder, reverseSort = false } }, separateOwner and true or false)
			return true
		end
		return false
	end

	local function HasBackgroundRadar()
		local hasTrap = (bait.itemID ~= nil and (bait.ownQty > 0 or bait.postedByUs[bait.itemID] == true))
			or (bait.cs.returnTrapID ~= nil and bait.postedByUs[bait.cs.returnTrapID] == true)
		return hasTrap or bait.cs.enabled
	end

	local function EnsureCounterWatchlist()
		local cs = bait.cs
		local db = ns.db
		local A = C_AuctionHouse
		if not (db and db.ahPrices and A and A.MakeItemKey) then return 0 end
		local stamp = (db.ahUpdated or 0) + (db.ahLastReplicate or 0) + (ns.ahCachedCount or 0)
		if cs.builtStamp == stamp and #cs.keys > 0 then
			return #cs.keys
		end
		cs.builtStamp = stamp
		wipe(cs.keys); wipe(cs.ids); wipe(cs.idSet); wipe(cs.pool)

		local prices = db.ahPrices
		local market = db.ahMarket or {}
		local function CollectCandidates(minPosts, minCopper)
			wipe(cs.pool)
			for id, rawP in pairs(prices) do
				if type(id) == "number" and id > 0 and type(rawP) == "number" and rawP > 0 and not VENDOR_BUY[id] then
					local m = market[id]
					local qu = m and m.qu
					if qu ~= 0 and IsCommodityMaterial(id, nil) then
						local posts = (m and m.n) or 1
						local qty = (m and m.q) or 0
						local turn = (m and m.turn) or 0
						local wallHint = (m and m.p2 and m.p2 > rawP * 1.35 and (m.mq or 0) <= 3) and m.p2 or rawP
						if m and m.avg and m.avg > 0 and wallHint > m.avg * 2.5 then
							wallHint = max(rawP, m.avg)
						end
						if (posts >= minPosts or qty >= minPosts * 5) and wallHint >= minCopper then
							local activity = (turn * 3) + (posts * 6) + min(300, qty)
							local score = activity * ((wallHint / 100) ^ 0.55)
							cs.pool[#cs.pool + 1] = { id = id, floor = wallHint, score = score }
						end
					end
				end
			end
		end

		CollectCandidates(3, 100)
		if #cs.pool < 25 then
			CollectCandidates(1, 20)
		end
		sort(cs.pool, function(a, b)
			if a.score ~= b.score then return a.score > b.score end
			return a.id < b.id
		end)

		local limit = min(50, #cs.pool)
		for i = 1, limit do
			local c = cs.pool[i]
			cs.ids[i] = c.id
			cs.keys[i] = A.MakeItemKey(c.id)
			cs.idSet[c.id] = true
			if not ns.IsBaitProtectedItem(c.id) or not cs.refFloor[c.id] or cs.refFloor[c.id] <= 0 then
				cs.refFloor[c.id] = c.floor
			end
		end
		wipe(cs.pool)
		return #cs.keys
	end

	local function RestoreTrapAfterCounter(cooldownSec)
		local cs = bait.cs
		local now = (GetTime and GetTime()) or 0
		if cs.isCounterHit and bait.itemID and cooldownSec and cooldownSec > 0 then
			cs.ignoreUntil[bait.itemID] = now + cooldownSec
		end
		cs.isCounterHit = false
		if cs.returnTrapID then
			local retID = cs.returnTrapID
			cs.returnTrapID = nil
			bait.itemID = retID
			bait.lastAlertQty = 0
			bait.dismissedItem, bait.dismissedQty = nil, 0
			bait.lastOrderSig = nil
			if ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen() then
				QueryLiveItem(retID, false)
			end
			return true
		end
		return false
	end

	local function RunCounterSweep()
		local cs = bait.cs
		local A = C_AuctionHouse
		if not (cs.enabled and ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen() and A and A.SearchForItemKeys) then
			return false
		end
		if (ns.IsAuctionScanBusy and ns.IsAuctionScanBusy()) or ns.ahScanning or bait.pendingBuy or bait.pendingPost or bait.postingItemID then
			return false
		end
		local now = (GetTime and GetTime()) or 0
		if cs.verifyID then
			if cs.verifyAt and (now - cs.verifyAt) > 4.0 then
				cs.verifyID, cs.verifyAt, cs.verifySent = nil, nil, false
			else
				if not cs.verifySent then
					cs.verifySent = QueryLiveItem(cs.verifyID, false)
				end
				return false
			end
		end
		-- Never sweep over top of an active un-dismissed snipe banner waiting to be clicked!
		if bait.snipeQty > 0 and bait.itemID and not (bait.dismissedItem == bait.itemID and bait.snipeQty <= bait.dismissedQty) then
			return false
		end
		if cs.pauseUntil and now < cs.pauseUntil then
			return false
		end
		local sb = AuctionHouseFrame and AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SearchBox
		local br = AuctionHouseFrame and AuctionHouseFrame.BrowseResultsFrame
		if sb and ((sb.HasFocus and sb:HasFocus())
			or (br and br.IsShown and br:IsShown() and sb.GetText and (sb:GetText() or "") ~= "")) then
			return false
		end
		if A.IsThrottledMessageSystemReady and not A.IsThrottledMessageSystemReady() then
			return false
		end
		local nKeys = EnsureCounterWatchlist()
		if nKeys <= 0 then
			SetStatus("Counter-Snipe waiting for AH market cache — let scan finish or run /sack scan.", 1, 0.72, 0.25)
			if RefreshBaitUI then RefreshBaitUI(false) end
			return false
		end
		cs.awaitBrowse = true
		cs.browseActive = true
		cs.queryAt = now
		local sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
		pcall(A.SearchForItemKeys, cs.keys, { { sortOrder = sortOrder, reverseSort = false } })
		return true
	end

	function ns.OnCounterSnipeBrowseResults(list)
		local cs = bait.cs
		if not (cs.browseActive and list and #cs.keys > 0) then
			return false
		end
		local now = (GetTime and GetTime()) or 0
		if #list > #cs.keys then
			cs.browseActive, cs.awaitBrowse = false, false
			cs.pauseUntil = now + 10
			return false
		end
		for i = 1, #list do
			local r = list[i]
			local id = r and r.itemKey and r.itemKey.itemID
			if id and not cs.idSet[id] then
				cs.browseActive, cs.awaitBrowse = false, false
				cs.pauseUntil = now + 10
				return false
			end
		end
		-- Always consume browse updates matching our 50-key radar buffer so unverified 1-unit sniper baits
		-- never overwrite DavesSackDB.ahPrices or spam NotifyUpdated.
		if not cs.awaitBrowse or not cs.queryAt or (now - cs.queryAt) > 4.5 then
			return true
		end
		cs.awaitBrowse = false
		cs.sweeps = cs.sweeps + 1

		local sPct = (ns.db and ns.db.snipeMaxPct) or 75
		local gold = (GetMoney and GetMoney()) or 0
		local bestID, bestScore = nil, 0

		for i = 1, #list do
			local r = list[i]
			local id = r and r.itemKey and r.itemKey.itemID
			local p = r and r.minPrice
			local q = (r and r.totalQuantity) or 0
			if id and p and p > 0 and q > 0 and not ns.IsBaitProtectedItem(id) then
				local ref = cs.refFloor[id]
				if ref and ref > 0 then
					if p > ref then
						cs.refFloor[id] = min(floor(ref * 1.5), floor(ref * 0.7 + p * 0.3 + 0.5))
					elseif not (cs.ignoreUntil[id] and now < cs.ignoreUntil[id]) and gold >= p then
						local cap = SanitizeUnitPrice(ref * sPct / 100)
						if p <= cap and (ref * AH_CUT) > p then
							local disc = (ref - p) / ref
							local score = disc * ((ref / 100) ^ 0.5)
							if score > bestScore then
								bestID, bestScore = id, score
							end
						end
					end
				end
			end
		end

		if bestID then
			cs.verifyID = bestID
			cs.verifyAt = now
			cs.verifySent = QueryLiveItem(bestID, false)
		elseif bait.panel and bait.panel:IsShown() and not bait.statusMsg and bait.snipeQty == 0 and bait.ownQty == 0 then
			bait.statusFS:SetTextColor(0.55, 0.90, 0.68)
			bait.statusFS:SetText(format("Counter-Snipe Top %d ON (Sweep #%d) — watching hottest traded mats for sniper baits & undercuts…", #cs.keys, cs.sweeps))
		end
		return true
	end

	local function VerifyCounterCandidate(itemID)
		local cs = bait.cs
		cs.verifyID, cs.verifyAt, cs.verifySent = nil, nil, false
		local A = C_AuctionHouse
		if not (A and A.GetNumCommoditySearchResults and A.GetCommoditySearchResultInfo) then return end
		local n = A.GetNumCommoditySearchResults(itemID) or 0
		if n <= 0 then return end
		local now = (GetTime and GetTime()) or 0
		local ref = cs.refFloor[itemID] or (ns.db and ns.db.ahPrices and ns.db.ahPrices[itemID]) or 0
		local sPct = (ns.db and ns.db.snipeMaxPct) or 75

		local lowUnit, cheapTiers = nil, 0
		local wallUnit, wallUnits, jumpFloor = nil, 0, nil
		for i = 1, min(n, 10) do
			local r = A.GetCommoditySearchResultInfo(itemID, i)
			if r and NotSecret(r.unitPrice) and NotSecret(r.quantity) and r.unitPrice > 0 then
				local own = NotSecret(r.numOwnerItems) and (r.numOwnerItems or 0) or 0
				local other = max(0, r.quantity - own)
				if other > 0 then
					if not lowUnit then
						lowUnit = r.unitPrice
						cheapTiers = 1
					elseif r.unitPrice < lowUnit * 1.25 then
						cheapTiers = cheapTiers + 1
					else
						if not jumpFloor and other >= 3 then
							jumpFloor = r.unitPrice
						end
						if not wallUnit and r.unitPrice >= max(lowUnit * 1.25, ref * 0.78) then
							wallUnit = r.unitPrice
						end
						if wallUnit and r.unitPrice >= wallUnit then
							wallUnits = wallUnits + other
						end
					end
				end
			end
		end

		local validCheap = cheapTiers <= 2 or (cheapTiers <= 4 and wallUnit ~= nil and wallUnit >= lowUnit * 1.35)
		if wallUnit and wallUnits >= 3 and validCheap and lowUnit and lowUnit <= SanitizeUnitPrice(wallUnit * sPct / 100) then
			cs.refFloor[itemID] = wallUnit
			if bait.itemID and bait.itemID ~= itemID and (bait.ownQty > 0 or bait.postedByUs[bait.itemID] == true) and not cs.returnTrapID then
				cs.returnTrapID = bait.itemID
			end
			bait.baseline[itemID] = wallUnit
			cs.isCounterHit = true
			bait.itemID = itemID
			bait.lastAlertQty = 0
			bait.dismissedItem, bait.dismissedQty = nil, 0
			bait.lastOrderSig = nil
			SetStatus(nil)
			if RefreshBaitUI then RefreshBaitUI(true) end
		else
			-- Organic market shift (or softened wall): recalibrate floor safely without adopting a 1-unit bait price.
			if lowUnit and lowUnit > 0 then
				cs.refFloor[itemID] = wallUnit or jumpFloor or lowUnit
			end
			cs.ignoreUntil[itemID] = now + 45
		end
	end

	local function ComputeFloorAndPrices(itemID)
		local db = ns.db or {}
		local bPct = db.baitPct or 35
		local sPct = db.snipeMaxPct or 75
		if sPct <= bPct then
			sPct = min(90, bPct + 20)
			db.snipeMaxPct = sPct
		end
		if not itemID then return nil, nil, nil, bPct, sPct end
		local floorP = bait.baseline[itemID] or (db.ahPrices and db.ahPrices[itemID]) or nil
		if not floorP or floorP <= 0 then return nil, nil, nil, bPct, sPct end
		local baitP = SanitizeUnitPrice(floorP * bPct / 100)
		local maxSnipeP = SanitizeUnitPrice(floorP * sPct / 100)
		if maxSnipeP < baitP then maxSnipeP = baitP end
		return floorP, baitP, maxSnipeP, bPct, sPct
	end

	local function ScanOrderBook()
		wipe(bait.tiers)
		bait.ownQty, bait.ownUnit = 0, nil
		bait.snipeQty, bait.snipeCost, bait.snipeAvg = 0, 0, 0
		local itemID = bait.itemID
		local A = C_AuctionHouse
		if not (itemID and ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen() and A and A.GetNumCommoditySearchResults and A.GetCommoditySearchResultInfo) then
			return
		end
		local n = A.GetNumCommoditySearchResults(itemID) or 0
		if n <= 0 then return end

		-- First pass: check if we own any units on the AH and find lowest unbaited non-owner price.
		local lowestNonOwner, secondNonOwner = nil, nil
		local sawOwn = false
		for i = 1, n do
			local r = A.GetCommoditySearchResultInfo(itemID, i)
			if r and NotSecret(r.unitPrice) and NotSecret(r.quantity) then
				local own = NotSecret(r.numOwnerItems) and (r.numOwnerItems or 0) or 0
				local other = max(0, r.quantity - own)
				if own > 0 or r.containsOwnerItem then
					sawOwn = true
					bait.ownQty = bait.ownQty + max(1, own)
					if not bait.ownUnit or r.unitPrice < bait.ownUnit then
						bait.ownUnit = r.unitPrice
					end
					if NotSecret(r.auctionID) and r.auctionID > 0 and (own >= r.quantity or bait.queriedSeparate or not bait.ownAuctionID[itemID]) then
						bait.ownAuctionID[itemID] = r.auctionID
					end
				end
				if other > 0 and r.unitPrice > 0 then
					if not lowestNonOwner then
						lowestNonOwner = r.unitPrice
					elseif not secondNonOwner and r.unitPrice > lowestNonOwner * 1.25 then
						secondNonOwner = r.unitPrice
					end
				end
			end
		end

		if not sawOwn and bait.postedByUs[itemID] and not bait.pendingPost and not bait.postingItemID then
			bait.postedByUs[itemID] = nil
			bait.ownAuctionID[itemID] = nil
			local now = (GetTime and GetTime()) or 0
			local userCanc = (bait.cancelingAt or 0) > 0 and (now - bait.cancelingAt) < 5.0
				and (not bait.cancelingItem or bait.cancelingItem == itemID)
			if not userCanc then
				SetStatus("Another buyer bought your 1 bait unit! Click Post 1 Bait (or try 50%–65%) to re-arm.", 1, 0.74, 0.28)
			end
		end

		-- Update baseline floor automatically ONLY while we have no active bait or counter-snipe lock on this item.
		if not sawOwn and not bait.postedByUs[itemID] and not (bait.cs.isCounterHit and bait.itemID == itemID)
			and lowestNonOwner and lowestNonOwner > 0 then
			bait.baseline[itemID] = lowestNonOwner
		elseif not bait.baseline[itemID] then
			local cached = ns.db and ns.db.ahPrices and ns.db.ahPrices[itemID]
			bait.baseline[itemID] = secondNonOwner or cached or lowestNonOwner
		end

		local _, _, maxSnipeP = ComputeFloorAndPrices(itemID)
		local playerGold = (GetMoney and GetMoney()) or 0
		local remainGold = playerGold

		for i = 1, min(n, 16) do
			local r = A.GetCommoditySearchResultInfo(itemID, i)
			if r and NotSecret(r.unitPrice) and NotSecret(r.quantity) and r.quantity > 0 then
				local own = NotSecret(r.numOwnerItems) and (r.numOwnerItems or 0) or 0
				local other = max(0, r.quantity - own)
				local isSnipe = maxSnipeP ~= nil and other > 0 and r.unitPrice <= maxSnipeP
				if isSnipe and remainGold >= r.unitPrice then
					local canBuy = min(other, floor(remainGold / r.unitPrice))
					if canBuy > 0 then
						bait.snipeQty = bait.snipeQty + canBuy
						bait.snipeCost = bait.snipeCost + canBuy * r.unitPrice
						remainGold = remainGold - canBuy * r.unitPrice
					end
				end
				if #bait.tiers < 6 then
					bait.tiers[#bait.tiers + 1] = {
						unitPrice = r.unitPrice,
						qty = r.quantity,
						own = own,
						other = other,
						isSnipe = isSnipe,
					}
				end
			end
		end

		if bait.snipeQty > 0 then
			bait.snipeAvg = floor(bait.snipeCost / bait.snipeQty + 0.5)
			if bait.dismissedItem ~= itemID or bait.snipeQty > bait.dismissedQty then
				bait.dismissedItem, bait.dismissedQty = nil, 0
			end
			if bait.lastAlertItem ~= itemID or bait.snipeQty > bait.lastAlertQty then
				bait.lastAlertItem = itemID
				bait.lastAlertQty = bait.snipeQty
				bait.previewUntil = nil
				PlaySnipeChime()
			end
		else
			bait.lastAlertQty = 0
			bait.dismissedItem, bait.dismissedQty = nil, 0
			if bait.cs.isCounterHit and bait.itemID == itemID and not bait.pendingBuy then
				if lowestNonOwner and lowestNonOwner > 0 then
					bait.baseline[itemID] = lowestNonOwner
					bait.cs.refFloor[itemID] = lowestNonOwner
				end
				if RestoreTrapAfterCounter(8) then
					ScanOrderBook()
				end
			end
		end
	end

	local function SelectBaitItem(itemID)
		if not itemID or itemID <= 0 then return end
		if bait.pendingBuy and C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
			pcall(C_AuctionHouse.CancelCommoditiesPurchase)
		end
		local oldID = bait.itemID
		if bait.pendingPost and oldID and bait.ownQty <= 0 and not bait.postingItemID then
			bait.postedByUs[oldID] = nil
		end
		bait.cs.isCounterHit = false
		bait.cs.returnTrapID = nil
		bait.cs.pauseUntil = nil
		bait.pendingBuy = nil
		bait.pendingPost = nil
		bait.needSeparateQuery = false
		bait.itemID = itemID
		bait.lastAlertQty = 0
		bait.dismissedItem, bait.dismissedQty = nil, 0
		bait.bagsDirty = true
		bait.lastOrderSig = nil
		SetStatus(nil)
		if ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen() then
			QueryLiveItem(itemID, false)
		end
		if RefreshBaitUI then RefreshBaitUI(true) end
	end

	local function StyleButton(btn, r, g, b, enabled)
		if not btn then return end
		btn:SetEnabled(enabled ~= false)
		if enabled == false then
			btn.bg:SetColorTexture(0.14, 0.14, 0.16, 0.75)
			btn.edge:SetColorTexture(1, 1, 1, 0.12)
			btn.fs:SetTextColor(0.50, 0.50, 0.54)
		else
			btn.bg:SetColorTexture(r, g, b, 0.30)
			btn.edge:SetColorTexture(min(1, r + 0.15), min(1, g + 0.15), min(1, b + 0.15), 0.90)
			btn.fs:SetTextColor(1, 0.96, 0.86)
		end
	end

	local function ExecuteSnipe(maxUnitOverride)
		local A = C_AuctionHouse
		local itemID = bait.itemID
		if not (itemID and ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen() and A and A.StartCommoditiesPurchase) then return end
		local floorP, _, maxSnipeP = ComputeFloorAndPrices(itemID)
		local capPrice = maxUnitOverride or maxSnipeP
		if not capPrice or capPrice <= 0 then return end

		-- Re-read live affordable quantity up to capPrice right inside this click
		local n = A.GetNumCommoditySearchResults and A.GetNumCommoditySearchResults(itemID) or 0
		local remainGold = (GetMoney and GetMoney()) or 0
		local buyQty, totalCost, highestTierUnit = 0, 0, 0
		for i = 1, n do
			local r = A.GetCommoditySearchResultInfo(itemID, i)
			if not r or not NotSecret(r.unitPrice) or r.unitPrice > capPrice then break end
			local own = NotSecret(r.numOwnerItems) and (r.numOwnerItems or 0) or 0
			local other = max(0, (r.quantity or 0) - own)
			if other > 0 and remainGold >= r.unitPrice then
				local take = min(other, floor(remainGold / r.unitPrice))
				if take > 0 then
					buyQty = buyQty + take
					totalCost = totalCost + take * r.unitPrice
					remainGold = remainGold - take * r.unitPrice
					if r.unitPrice > highestTierUnit then
						highestTierUnit = r.unitPrice
					end
				end
			end
		end
		if buyQty <= 0 then
			SetStatus("Target units were already bought — refreshing…", 1, 0.65, 0.25)
			if not RestoreTrapAfterCounter(8) then
				QueryLiveItem(itemID, false)
			end
			RefreshBaitUI(true)
			return
		end

		local pb = {
			itemID = itemID,
			qty = buyQty,
			maxUnit = capPrice,
			quoteCap = highestTierUnit > 0 and highestTierUnit or capPrice,
			previewAvg = floor(totalCost / buyQty + 0.5),
			realFloor = floorP or capPrice,
			quoteConfirmed = false,
		}
		bait.pendingBuy = pb
		SetStatus(format("Locking quote for x%d (max %s/ea)…", buyQty, CompactMoney(pb.quoteCap)), 0.35, 0.92, 0.50)
		pcall(A.StartCommoditiesPurchase, itemID, buyQty)
		C_Timer.After(6.0, function()
			if bait.pendingBuy == pb and not pb.quoteConfirmed then
				if A.CancelCommoditiesPurchase then pcall(A.CancelCommoditiesPurchase) end
				bait.pendingBuy = nil
				SetStatus("Quote timed out — watching for next seller…", 1, 0.68, 0.25)
				if not RestoreTrapAfterCounter(8) and bait.itemID then
					QueryLiveItem(bait.itemID, false)
				end
				RefreshBaitUI(true)
			end
		end)
		RefreshBaitUI()
	end

	local function OnPrimaryAction()
		local A = C_AuctionHouse
		local itemID = bait.itemID
		if not (itemID and ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen() and A) then return end

		if bait.pendingBuy then
			local pb = bait.pendingBuy
			local now = (GetTime and GetTime()) or 0
			if pb.quoteConfirmed and (not pb.confirmSent or (now - (pb.confirmAt or 0)) > 1.5) and A.ConfirmCommoditiesPurchase then
				pb.confirmSent = true
				pb.confirmAt = now
				Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
				pcall(A.ConfirmCommoditiesPurchase, pb.itemID, pb.qty)
				RefreshBaitUI()
			end
			return
		elseif bait.actMode == "snipe" then
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			ExecuteSnipe(nil)
			return
		elseif bait.actMode == "confirm_post" and bait.pendingPost and A.ConfirmPostCommodity then
			local p = bait.pendingPost
			bait.pendingPost = nil
			if not (p.loc and p.loc:IsValid()) then
				local _, newLoc = CountAndFindStack(p.itemID)
				p.loc = newLoc
			end
			if not (p.loc and p.loc:IsValid()) then
				if bait.ownQty <= 0 then bait.postedByUs[p.itemID] = nil end
				SetStatus("Could not find unlocked stack in bags.", 1, 0.35, 0.35)
				RefreshBaitUI()
				return
			end
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			bait.postedByUs[p.itemID] = true
			bait.postingItemID = p.itemID
			bait.postSeq = bait.postSeq + 1
			local pSeq = bait.postSeq
			pcall(A.ConfirmPostCommodity, p.loc, p.dur, p.qty, p.price)
			C_Timer.After(6.0, function()
				if bait.postSeq == pSeq and bait.postingItemID == p.itemID then
					bait.postingItemID = nil
					RefreshBaitUI()
				end
			end)
			SetStatus(format("Posting 1 bait @ %s… (click Cancel on WoW's AH warning if shown)", CompactMoney(p.price)), 0.95, 0.78, 0.25)
			RefreshBaitUI()
			return
		elseif bait.actMode == "post" and A.PostCommodity then
			local floorP, baitP = ComputeFloorAndPrices(itemID)
			if not (floorP and baitP and baitP < floorP) then
				SetStatus("Scan live price first (or floor is too low to undercut).", 1, 0.45, 0.35)
				QueryLiveItem(itemID, false)
				RefreshBaitUI()
				return
			end
			if A.IsThrottledMessageSystemReady and not A.IsThrottledMessageSystemReady() then
				SetStatus("Auction House throttle busy — click again in a moment.", 1, 0.72, 0.25)
				RefreshBaitUI()
				return
			end
			local _, loc = CountAndFindStack(itemID)
			if not loc then
				SetStatus("Need at least 1 unlocked stack of this material in your bags.", 1, 0.40, 0.35)
				RefreshBaitUI()
				return
			end
			local dep = (A.CalculateCommodityDeposit and A.CalculateCommodityDeposit(itemID, 1, 1)) or 0
			if ((GetMoney and GetMoney()) or 0) < dep then
				SetStatus("Not enough copper for the 1-unit deposit.", 1, 0.35, 0.35)
				RefreshBaitUI()
				return
			end
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			bait.baseline[itemID] = floorP
			bait.postedByUs[itemID] = true
			local ok, needsConfirm = pcall(A.PostCommodity, loc, 1, 1, baitP)
			if ok and needsConfirm then
				bait.postingItemID = nil
				bait.pendingPost = { loc = loc, dur = 1, qty = 1, price = baitP, itemID = itemID }
				SetStatus("Deep undercut warning: click Confirm Undercut above! (Click Cancel on WoW's popup if shown)", 1, 0.78, 0.20)
			elseif ok then
				bait.pendingPost = nil
				bait.postingItemID = itemID
				bait.postSeq = bait.postSeq + 1
				local pSeq = bait.postSeq
				C_Timer.After(6.0, function()
					if bait.postSeq == pSeq and bait.postingItemID == itemID then
						bait.postingItemID = nil
						RefreshBaitUI()
					end
				end)
				SetStatus(format("Posting 1 bait @ %s…", CompactMoney(baitP)), 0.90, 0.78, 0.30)
			else
				bait.postingItemID = nil
				if bait.ownQty <= 0 then bait.postedByUs[itemID] = nil end
				SetStatus("Could not post bait right now — try again.", 1, 0.35, 0.35)
			end
			RefreshBaitUI()
			return
		else
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			QueryLiveItem(itemID, false)
			SetStatus("Refreshing live order book…", 0.75, 0.82, 0.95)
			RefreshBaitUI()
		end
	end

	local function OnCancelBait()
		local A = C_AuctionHouse
		local itemID = bait.itemID
		if not (itemID and ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen() and A) then return end
		if bait.pendingBuy then
			if A.CancelCommoditiesPurchase then pcall(A.CancelCommoditiesPurchase) end
			bait.pendingBuy = nil
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			SetStatus("Pending snipe purchase cancelled.", 0.78, 0.78, 0.82)
			if not RestoreTrapAfterCounter(15) and bait.itemID then
				QueryLiveItem(bait.itemID, false)
			end
			RefreshBaitUI(true)
			return
		end
		if bait.pendingPost then
			bait.pendingPost = nil
			bait.postingItemID = nil
			if bait.ownQty <= 0 then bait.postedByUs[itemID] = nil end
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			SetStatus("Pending bait post cancelled.", 0.78, 0.78, 0.82)
			RefreshBaitUI()
			return
		end
		local aid = bait.ownAuctionID[itemID]
		if aid and aid > 0 and A.CancelAuction then
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			bait.cancelingAt = (GetTime and GetTime()) or 0
			bait.cancelingItem = itemID
			pcall(A.CancelAuction, aid)
			SetStatus("Cancelling bait listing (1 unit returns to your Mailbox)…", 0.95, 0.72, 0.30)
			RefreshBaitUI()
		else
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			bait.needSeparateQuery = true
			QueryLiveItem(itemID, true)
			SetStatus("Locating your bait auction ID — click Cancel Bait again in a second.", 0.95, 0.78, 0.25)
			RefreshBaitUI()
		end
	end

	local function GetBaitRow(idx)
		local r = bait.rows[idx]
		if r then return r end
		r = CreateFrame("Button", nil, bait.content)
		r:SetHeight(B_ROW_H)
		r:RegisterForClicks("LeftButtonUp")
		local bg = r:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		r.bg = bg
		local hl = r:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 0.82, 0, 0.09)
		r.hl = hl
		local iconBg = r:CreateTexture(nil, "BORDER")
		iconBg:SetSize(26, 26)
		iconBg:SetPoint("LEFT", 6, 0)
		iconBg:SetColorTexture(SLOTBG[1], SLOTBG[2], SLOTBG[3], 1)
		r.iconBg = iconBg
		local icon = r:CreateTexture(nil, "ARTWORK")
		icon:SetSize(24, 24)
		icon:SetPoint("CENTER", iconBg, "CENTER")
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.icon = icon
		local border = r:CreateTexture(nil, "OVERLAY")
		border:SetSize(26, 26)
		border:SetPoint("CENTER", iconBg, "CENTER")
		border:SetTexture(M .. "slot_border")
		r.border = border
		local leftTop = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		leftTop:SetPoint("TOPLEFT", 38, -4)
		leftTop:SetJustifyH("LEFT")
		r.leftTop = leftTop
		local leftBot = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		leftBot:SetPoint("BOTTOMLEFT", 38, 4)
		leftBot:SetJustifyH("LEFT")
		r.leftBot = leftBot
		local rightFS = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		rightFS:SetPoint("RIGHT", -8, 0)
		rightFS:SetJustifyH("RIGHT")
		r.rightFS = rightFS
		local headFS = r:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		headFS:SetPoint("LEFT", 6, 0)
		headFS:SetJustifyH("LEFT")
		r.headFS = headFS
		local headLine = r:CreateTexture(nil, "ARTWORK")
		headLine:SetHeight(1)
		headLine:SetColorTexture(0.83, 0.66, 0.31, 0.30)
		headLine:SetPoint("BOTTOMLEFT", 4, 1)
		headLine:SetPoint("BOTTOMRIGHT", -4, 1)
		r.headLine = headLine

		r:SetScript("OnClick", function(self)
			local d = self.data
			if not d then return end
			if d.kind == "mat" or d.kind == "watch" then
				if IsModifiedClick and IsModifiedClick("CHATLINK") and d.link then
					if ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(d.link)
					elseif ChatEdit_InsertLink then ChatEdit_InsertLink(d.link) end
					return
				end
				Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
				SelectBaitItem(d.id)
				if bait.scroll and bait.scroll.SetVerticalScroll then bait.scroll:SetVerticalScroll(0) end
			elseif d.kind == "tier" and d.isSnipe then
				Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
				ExecuteSnipe(d.unitPrice)
			end
		end)
		r:SetScript("OnEnter", function(self)
			local d = self.data
			if not d then return end
			if d.kind == "tier" and d.isSnipe then
				bait.hoverSnipeRow = true
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if (d.kind == "mat" or d.kind == "watch") and d.id then
				if d.link then GameTooltip:SetHyperlink(d.link) else GameTooltip:SetItemByID(d.id) end
				GameTooltip:AddLine(" ")
				if d.kind == "watch" then
					GameTooltip:AddLine("Counter-Snipe Top 50 Watchlist — click to inspect live order book.", 0.35, 0.94, 0.55)
				else
					GameTooltip:AddLine("Click to load into the Bait & Snipe deck.", 0.25, 0.92, 0.45)
				end
				GameTooltip:Show()
			elseif d.kind == "tier" then
				GameTooltip:SetText("Live Order Book Tier", 1, 0.82, 0)
				GameTooltip:AddDoubleLine("Unit Price", Money(d.unitPrice), 0.8, 0.8, 0.8, 1, 1, 1)
				GameTooltip:AddDoubleLine("Other Sellers' Units", Group(d.other), 0.8, 0.8, 0.8, 1, 1, 1)
				if d.own > 0 then
					GameTooltip:AddDoubleLine("Your Bait Units", Group(d.own), 1, 0.82, 0, 0.35, 0.95, 0.50)
				end
				if d.isSnipe then
					GameTooltip:AddLine(" ")
					GameTooltip:AddLine("Click to snipe all non-owner units up to this tier!", 0.25, 0.95, 0.45)
				end
				GameTooltip:Show()
			end
		end)
		r:SetScript("OnLeave", function()
			bait.hoverSnipeRow = false
			GameTooltip:Hide()
		end)
		r:SetScript("OnHide", function()
			bait.hoverSnipeRow = false
		end)

		bait.rows[idx] = r
		return r
	end

	local function PaintHeaderRow(idx, yOff, rowW, titleText)
		local r = GetBaitRow(idx)
		r.data = nil
		r:EnableMouse(false)
		r:SetSize(rowW, B_HEAD_H)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", bait.content, "TOPLEFT", 0, -yOff)
		r.bg:SetColorTexture(0, 0, 0, 0)
		r.hl:SetAlpha(0)
		r.iconBg:Hide(); r.icon:Hide(); r.border:Hide()
		r.leftTop:Hide(); r.leftBot:Hide(); r.rightFS:Hide()
		r.headFS:SetText("|cffd4a94e" .. titleText .. "|r")
		r.headFS:Show(); r.headLine:Show()
		r:Show()
		return B_HEAD_H
	end

	local function PlaceSnipeAlert(f)
		if not f then return end
		f:SetScale((ns.db and ns.db.scale) or 1)
		local sc = f:GetEffectiveScale()
		if not sc or sc <= 0 then sc = 1 end
		local saved = ns.db and ns.db.snipeAlertPos
		f:ClearAllPoints()
		if type(saved) == "table" and type(saved.sx) == "number" and type(saved.sy) == "number" then
			f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.sx / sc, saved.sy / sc)
		else
			f:SetPoint("TOP", UIParent, "TOP", 0, -125)
		end
	end

	function ns.SyncSnipeAlertScale()
		if bait.alert and bait.alert.frame then
			PlaceSnipeAlert(bait.alert.frame)
		end
	end

	local TriggerSnipeOrTestClick

	local function BuildSnipeAlertBanner()
		if bait.alert then return bait.alert end
		local f = CreateFrame("Frame", "DavesSackSnipeAlert", UIParent)
		f:SetSize(384, 108)
		f:SetFrameStrata("DIALOG")
		f:SetFrameLevel(50)
		f:SetClampedToScreen(true)
		f:EnableMouse(true)
		f:SetMovable(true)
		f:RegisterForDrag("LeftButton")
		if f.SetDontSavePosition then f:SetDontSavePosition(true) end
		PlaceSnipeAlert(f)

		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			local l, t = self:GetLeft(), self:GetTop()
			local sc = self:GetEffectiveScale() or 1
			if l and t and ns.db then
				ns.db.snipeAlertPos = { sx = l * sc, sy = t * sc }
			end
		end)
		f:Hide()

		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0.05, 0.09, 0.06, 0.94)

		-- Outer emerald/gold pulsing frame lines (animated on a dedicated child watcher only while shown)
		local glow = CreateFrame("Frame", nil, f)
		glow:SetAllPoints()
		local gTop = glow:CreateTexture(nil, "OVERLAY"); gTop:SetHeight(2); gTop:SetPoint("TOPLEFT"); gTop:SetPoint("TOPRIGHT"); gTop:SetColorTexture(0.28, 0.98, 0.48, 1)
		local gBot = glow:CreateTexture(nil, "OVERLAY"); gBot:SetHeight(2); gBot:SetPoint("BOTTOMLEFT"); gBot:SetPoint("BOTTOMRIGHT"); gBot:SetColorTexture(0.28, 0.98, 0.48, 1)
		local gL = glow:CreateTexture(nil, "OVERLAY"); gL:SetWidth(2); gL:SetPoint("TOPLEFT"); gL:SetPoint("BOTTOMLEFT"); gL:SetColorTexture(0.28, 0.98, 0.48, 1)
		local gR = glow:CreateTexture(nil, "OVERLAY"); gR:SetWidth(2); gR:SetPoint("TOPRIGHT"); gR:SetPoint("BOTTOMRIGHT"); gR:SetColorTexture(0.28, 0.98, 0.48, 1)
		local pulseT = 0
		glow:SetScript("OnUpdate", function(self, elapsed)
			pulseT = pulseT + (elapsed or 0) * 5.5
			local a = 0.45 + 0.50 * (0.5 + 0.5 * math.sin(pulseT))
			self:SetAlpha(a)
			if bait.previewUntil and GetTime and GetTime() >= bait.previewUntil then
				bait.previewUntil = nil
				bait.previewConfirmed = false
				if RefreshBaitUI then RefreshBaitUI(false) end
			end
		end)

		local headFS = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		headFS:SetPoint("TOPLEFT", 12, -8)
		headFS:SetText("|cff5cd65cSNIPE FOUND!|r  |cff8c8c8c(drag to move)|r")

		local dismiss = CreateFrame("Button", nil, f)
		dismiss:SetSize(20, 20)
		dismiss:SetPoint("TOPRIGHT", -6, -5)
		local dFS = dismiss:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		dFS:SetPoint("CENTER")
		dFS:SetText("|cffaaaaaa×|r")
		local dHL = dismiss:CreateTexture(nil, "HIGHLIGHT")
		dHL:SetAllPoints()
		dHL:SetColorTexture(1, 1, 1, 0.14)
		dismiss:SetScript("OnClick", function()
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			bait.previewUntil = nil
			bait.previewConfirmed = false
			if bait.itemID and bait.snipeQty > 0 then
				bait.dismissedItem = bait.itemID
				bait.dismissedQty = bait.snipeQty
				if bait.cs.isCounterHit then
					RestoreTrapAfterCounter(60)
					if RefreshBaitUI then RefreshBaitUI(true) end
				end
			end
			f:Hide()
		end)

		local iconBg = f:CreateTexture(nil, "BORDER")
		iconBg:SetSize(34, 34)
		iconBg:SetPoint("TOPLEFT", 12, -30)
		iconBg:SetColorTexture(SLOTBG[1], SLOTBG[2], SLOTBG[3], 1)
		local icon = f:CreateTexture(nil, "ARTWORK")
		icon:SetSize(30, 30)
		icon:SetPoint("CENTER", iconBg, "CENTER")
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local iconBorder = f:CreateTexture(nil, "OVERLAY")
		iconBorder:SetSize(34, 34)
		iconBorder:SetPoint("CENTER", iconBg, "CENTER")
		iconBorder:SetTexture(M .. "slot_border")

		local itemFS = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		itemFS:SetPoint("TOPLEFT", 54, -31)
		itemFS:SetPoint("TOPRIGHT", -12, -31)
		itemFS:SetJustifyH("LEFT")

		local subFS = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		subFS:SetPoint("TOPLEFT", 54, -49)
		subFS:SetPoint("TOPRIGHT", -12, -49)
		subFS:SetJustifyH("LEFT")

		local buyBtn = CreateFrame("Button", "DavesSackSnipePopupButton", f)
		buyBtn:SetHeight(28)
		buyBtn:SetPoint("BOTTOMLEFT", 10, 8)
		buyBtn:SetPoint("BOTTOMRIGHT", -10, 8)
		buyBtn:RegisterForClicks("LeftButtonUp")
		buyBtn.bg = buyBtn:CreateTexture(nil, "BACKGROUND"); buyBtn.bg:SetAllPoints()
		buyBtn.edge = buyBtn:CreateTexture(nil, "ARTWORK"); buyBtn.edge:SetHeight(1)
		buyBtn.edge:SetPoint("BOTTOMLEFT"); buyBtn.edge:SetPoint("BOTTOMRIGHT")
		buyBtn.fs = buyBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		buyBtn.fs:SetPoint("CENTER", 0, 0)
		local bHL = buyBtn:CreateTexture(nil, "HIGHLIGHT"); bHL:SetAllPoints(); bHL:SetColorTexture(1, 1, 1, 0.16)
		buyBtn:SetScript("OnClick", function()
			TriggerSnipeOrTestClick("button")
		end)

		bait.alert = {
			frame = f,
			headFS = headFS,
			icon = icon,
			border = iconBorder,
			itemFS = itemFS,
			subFS = subFS,
			buyBtn = buyBtn,
			setGlow = function(r, g, b)
				gTop:SetColorTexture(r, g, b, 1)
				gBot:SetColorTexture(r, g, b, 1)
				gL:SetColorTexture(r, g, b, 1)
				gR:SetColorTexture(r, g, b, 1)
			end,
		}
		return bait.alert
	end

	local function UpdateSnipeAlertBanner(itemID, ahOpen, floorP)
		local previewActive = bait.previewUntil and GetTime and GetTime() < bait.previewUntil
		local hasRealSnipe = ahOpen and itemID and (bait.pendingBuy ~= nil or (bait.snipeQty > 0 and not (bait.dismissedItem == itemID and bait.snipeQty <= bait.dismissedQty)))
		if not (hasRealSnipe or previewActive) then
			if bait.alert and bait.alert.frame:IsShown() then
				bait.alert.frame:Hide()
			end
			return
		end

		local a = BuildSnipeAlertBanner()
		local showID = itemID or 2589 -- Linen Cloth icon fallback for /sack bait test preview
		local m = ns.db and ns.db.ahMarket and ns.db.ahMarket[showID]
		local name, _, quality, icon = ResolveItemMeta(showID, m, nil)
		local qr, qg, qb, qhex = QualityColor(quality)
		a.icon:SetTexture(icon or 134400)
		a.border:SetVertexColor(qr, qg, qb, 1)

		if bait.pendingBuy then
			local pb = bait.pendingBuy
			a.itemFS:SetText(format("%s%s|r  |cffffffff×%s|r", qhex, name or ("Item #" .. showID), Group(pb.qty)))
			a.subFS:SetText(format("Unit price: |cff5cd65c%s|r  •  Total: %s", CompactMoney(pb.lockedUnit or pb.previewAvg), CompactMoney((pb.lockedUnit or pb.previewAvg) * pb.qty)))
			if pb.confirmSent then
				a.setGlow(0.28, 0.98, 0.48)
				a.headFS:SetText("|cff5cd65cPURCHASING SNIPE…|r")
				a.buyBtn.fs:SetText(format("Buying ×%s @ %s…", Group(pb.qty), CompactMoney(pb.lockedUnit or pb.previewAvg)))
				StyleButton(a.buyBtn, 0.16, 0.72, 0.38, true)
			elseif pb.quoteConfirmed then
				a.setGlow(1, 0.84, 0.20)
				a.headFS:SetText("|cffffd2002/2 QUOTE LOCKED — CLICK NOW TO BUY!|r")
				a.buyBtn.fs:SetText(format("2/2  CONFIRM BUY ×%s @ %s!", Group(pb.qty), CompactMoney(pb.lockedUnit or pb.previewAvg)))
				StyleButton(a.buyBtn, 0.92, 0.68, 0.12, true)
			else
				a.setGlow(0.32, 0.78, 0.98)
				a.headFS:SetText("|cff66c2ff1/2 QUOTE REQUESTED…|r")
				a.buyBtn.fs:SetText(format("Locking ×%s Quote… (Click Again When Gold!)", Group(pb.qty)))
				StyleButton(a.buyBtn, 0.20, 0.52, 0.68, true)
			end
		elseif hasRealSnipe then
			a.setGlow(0.28, 0.98, 0.48)
			local netSell = floor((floorP or bait.snipeAvg) * AH_CUT + 0.5)
			local estGain = max(0, (netSell - bait.snipeAvg) * bait.snipeQty)
			if bait.cs.isCounterHit and bait.snipeQty == 1 then
				a.headFS:SetText("|cffffd200COUNTER-SNIPE BAIT (×1)!|r  |cff8c8c8c(double-click / tap ×2)|r")
			elseif bait.cs.isCounterHit then
				a.headFS:SetText("|cff5cd65cCOUNTER-SNIPE FOUND!|r  |cff8c8c8c(double-click / tap ×2)|r")
			else
				a.headFS:SetText("|cff5cd65cSNIPE FOUND!|r  |cff8c8c8c(double-click or tap macro ×2)|r")
			end
			a.itemFS:SetText(format("%s%s|r  |cffffffff×%s|r @ |cff5cd65c%s/ea|r",
				qhex, name or ("Item #" .. showID), Group(bait.snipeQty), CompactMoney(bait.snipeAvg)))
			a.subFS:SetText(estGain > 0
				and format("Total: |cffffffff%s|r  •  Est. Net Profit: |cff5cd65c+%s|r", CompactMoney(bait.snipeCost), CompactMoney(estGain))
				or format("Total: |cffffffff%s|r  •  At or below Max Snipe cap", CompactMoney(bait.snipeCost)))
			a.buyBtn.fs:SetText(format("1/2  CLICK TO LOCK ×%s  (%s)", Group(bait.snipeQty), CompactMoney(bait.snipeCost)))
			StyleButton(a.buyBtn, 0.14, 0.78, 0.34, true)
		elseif bait.previewConfirmed then
			a.setGlow(1, 0.84, 0.20)
			a.headFS:SetText("|cffffd200MACRO / CLICK CONFIRMED!|r")
			a.itemFS:SetText("|cff5cd65cYour snipe trigger worked cleanly!|r")
			a.subFS:SetText("Tap twice on live snipes: Tap 1 locks the quote, Tap 2 confirms the buy.")
			a.buyBtn.fs:SetText("CONFIRMED — READY TO SNIPE!")
			StyleButton(a.buyBtn, 0.85, 0.68, 0.18, true)
		else
			a.setGlow(0.28, 0.98, 0.48)
			a.headFS:SetText("|cff5cd65cSNIPE ALERT PREVIEW|r  |cff8c8c8c(drag where you want it)|r")
			a.itemFS:SetText(format("%s%s|r  |cffffffff×40|r @ |cff5cd65c4s 20c/ea|r", qhex, name or "Preview Material"))
			a.subFS:SetText("Press your |cffffd200/click DavesSackBaitActionButton|r macro now to test!")
			a.buyBtn.fs:SetText("PRESS MACRO OR CLICK HERE TO TEST")
			StyleButton(a.buyBtn, 0.14, 0.78, 0.34, true)
		end

		if not a.frame:IsShown() then
			PlaceSnipeAlert(a.frame)
			a.frame:Show()
		end
	end

	TriggerSnipeOrTestClick = function(source)
		if bait.previewUntil and GetTime and GetTime() < bait.previewUntil and bait.snipeQty <= 0 and not bait.pendingBuy then
			if bait.previewConfirmed then
				Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
				bait.previewUntil = nil
				bait.previewConfirmed = false
				if bait.alert then bait.alert.frame:Hide() end
			else
				Sound("LOOT_WINDOW_COIN_SOUND")
				bait.previewConfirmed = true
				bait.previewUntil = GetTime() + 2.5
				if source == "macro" then
					print("|cffd4a94eDave's Sack:|r |cff5cd65cMacro click confirmed!|r (/click DavesSackBaitActionButton is ready.)")
				else
					print("|cffd4a94eDave's Sack:|r |cff5cd65cPopup click confirmed!|r (Snipe alert is ready.)")
				end
				UpdateSnipeAlertBanner(bait.itemID, ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen(), nil)
			end
			return
		end
		local A = C_AuctionHouse
		if bait.pendingBuy then
			local pb = bait.pendingBuy
			local now = (GetTime and GetTime()) or 0
			if pb.quoteConfirmed and (not pb.confirmSent or (now - (pb.confirmAt or 0)) > 1.5) and A and A.ConfirmCommoditiesPurchase then
				pb.confirmSent = true
				pb.confirmAt = now
				Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
				pcall(A.ConfirmCommoditiesPurchase, pb.itemID, pb.qty)
				if RefreshBaitUI then RefreshBaitUI(false) end
			end
			return
		elseif bait.snipeQty > 0 then
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			ExecuteSnipe(nil)
		elseif source ~= "macro" then
			OnPrimaryAction()
		end
	end

	-- Always-existing, plain non-protected click proxy so `/click DavesSackBaitActionButton` macros work
	-- immediately after /reload (even before opening Market, while Market is closed, and during /sack bait test).
	do
		local macroBtn = CreateFrame("Button", "DavesSackBaitActionButton", UIParent)
		macroBtn:SetSize(1, 1)
		macroBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
		macroBtn:EnableMouse(false)
		macroBtn:RegisterForClicks("AnyUp", "AnyDown")
		macroBtn:SetScript("OnClick", function()
			local now = (GetTime and GetTime()) or 0
			if now - bait.lastMacroAt < 0.08 then return end -- debounce key-down + key-up pairs
			bait.lastMacroAt = now
			TriggerSnipeOrTestClick("macro")
		end)
	end

	function ns.PreviewSnipeAlert()
		bait.previewConfirmed = false
		if GetTime then bait.previewUntil = GetTime() + 12 end
		PlaySnipeChime()
		UpdateSnipeAlertBanner(bait.itemID, ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen(), nil)
	end

	local StartBaitWatch

	function ns.ToggleCounterSnipe(forceState)
		local cs = bait.cs
		local nextOn = (forceState ~= nil) and (forceState and true or false) or (not cs.enabled)
		cs.enabled = nextOn
		cs.pauseUntil = nil
		if nextOn then
			EnsureCounterWatchlist()
			SetStatus(nil)
			if StartBaitWatch then StartBaitWatch() end
			if ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen() and not (ns.IsAuctionScanBusy and ns.IsAuctionScanBusy()) and not ns.ahScanning then
				RunCounterSweep()
			end
		else
			cs.awaitBrowse, cs.browseActive = false, false
			cs.verifyID, cs.verifyAt, cs.verifySent = nil, nil, false
			RestoreTrapAfterCounter(0)
			SetStatus("Counter-Snipe Top 50 radar paused.", 0.72, 0.72, 0.76)
		end
		bait.lastOrderSig = nil
		if RefreshBaitUI then RefreshBaitUI(true) end
	end

	RefreshBaitUI = function(forceList)
		local ahOpen = ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen()
		local cs = bait.cs
		if cs.enabled and #cs.keys == 0 then
			EnsureCounterWatchlist()
		end
		ScanOrderBook()
		local itemID = bait.itemID
		local floorP, baitP, maxSnipeP, bPct, sPct = ComputeFloorAndPrices(itemID)
		UpdateSnipeAlertBanner(itemID, ahOpen, floorP)

		if not (bait.panel and bait.panel:IsShown()) then return end
		local bagCount = itemID and select(1, CountAndFindStack(itemID)) or 0

		-- Preset Pills & Counter-Snipe Toggle highlight
		for _, p in ipairs(bait.baitPills) do
			local on = (p.pct == bPct)
			p.bg:SetColorTexture(on and 0.83 or 1, on and 0.66 or 1, on and 0.31 or 1, on and 0.32 or 0.06)
			p.fs:SetTextColor(on and 1 or 0.78, on and 0.86 or 0.78, on and 0.35 or 0.80)
		end
		for _, p in ipairs(bait.snipePills) do
			local on = (p.pct == sPct)
			p.bg:SetColorTexture(on and 0.25 or 1, on and 0.78 or 1, on and 0.42 or 1, on and 0.30 or 0.06)
			p.fs:SetTextColor(on and 0.45 or 0.78, on and 0.98 or 0.78, on and 0.58 or 0.80)
		end
		if cs.btn then
			local on = cs.enabled
			cs.btn.bg:SetColorTexture(on and 0.16 or 1, on and 0.74 or 1, on and 0.38 or 1, on and 0.34 or 0.06)
			cs.btn.edge:SetColorTexture(on and 0.35 or 1, on and 0.98 or 1, on and 0.55 or 1, on and 0.90 or 0.16)
			cs.btn.fs:SetText(on
				and format("Counter-Snipe Top %d: |cff5cd65cON|r", #cs.keys > 0 and #cs.keys or 50)
				or "Counter-Snipe Top 50: |cff9a9aa0OFF|r")
			cs.btn.fs:SetTextColor(on and 0.92 or 0.80, on and 1.0 or 0.80, on and 0.94 or 0.84)
		end

		if itemID then
			local m = ns.db and ns.db.ahMarket and ns.db.ahMarket[itemID]
			local name, link, quality, icon = ResolveItemMeta(itemID, m, nil)
			local qr, qg, qb, qhex = QualityColor(quality)
			bait.slotIcon:SetTexture(icon or 134400)
			bait.slotIcon:Show()
			bait.slotBorder:SetVertexColor(qr, qg, qb, 1)
			bait.slotCount:SetText(bagCount > 0 and ("x" .. Group(bagCount)) or "0")
			bait.slotBtn.link = link
			bait.nameFS:SetText(format("%s%s|r  |cff8c8c8c(In Bags: %s)|r", qhex, name or ("Item #" .. itemID), Group(bagCount)))
			if floorP and floorP > 0 then
				local floorTag = (bait.ownQty > 0 or bait.postedByUs[itemID]) and "Locked Floor" or "Market Floor"
				bait.priceFS:SetText(format("%s: |cffffffff%s|r  •  Bait (%d%%): |cffffd200%s|r  •  Max Snipe (%d%%): |cff5cd65c%s|r",
					floorTag, CompactMoney(floorP), bPct, CompactMoney(baitP), sPct, CompactMoney(maxSnipeP)))
			else
				bait.priceFS:SetText(ahOpen and "|cff8c8c8cQuerying live Auction House price…|r" or "|cff8c8c8cOpen the Auction House to read live market floor.|r")
			end
		else
			bait.slotIcon:Hide()
			bait.slotBorder:SetVertexColor(TRIM[1], TRIM[2], TRIM[3], 1)
			bait.slotCount:SetText("")
			bait.slotBtn.link = nil
			bait.nameFS:SetText("|cffd4a94eSelect a material below (or drag one from your bags here)|r")
			bait.priceFS:SetText("|cff8c8c8cPosts 1 unit at a deep undercut, then snipes stacks sellers auto-post onto it.|r")
		end

		-- Primary & Cancel Buttons State Machine
		if not itemID then
			bait.actMode = "none"
			bait.actBtn.fs:SetText("Select a Material Below")
			StyleButton(bait.actBtn, 0.2, 0.2, 0.2, false)
			StyleButton(bait.cancelBtn, 0.2, 0.2, 0.2, false)
			bait.cancelBtn.fs:SetText("Cancel Bait")
			StyleButton(bait.resetBtn, 0.2, 0.2, 0.2, false)
		elseif not ahOpen then
			bait.actMode = "none"
			bait.actBtn.fs:SetText("Open Auction House First")
			StyleButton(bait.actBtn, 0.2, 0.2, 0.2, false)
			StyleButton(bait.cancelBtn, 0.2, 0.2, 0.2, false)
			bait.cancelBtn.fs:SetText("Cancel Bait")
			StyleButton(bait.resetBtn, 0.2, 0.2, 0.2, false)
		elseif bait.pendingBuy then
			local pb = bait.pendingBuy
			if pb.confirmSent then
				bait.actMode = "purchasing"
				bait.actBtn.fs:SetText(format("Buying x%s @ %s…", Group(pb.qty), CompactMoney(pb.lockedUnit or pb.previewAvg)))
				StyleButton(bait.actBtn, 0.16, 0.72, 0.38, true)
			elseif pb.quoteConfirmed then
				bait.actMode = "confirm_buy"
				bait.actBtn.fs:SetText(format("2/2 Confirm Buy x%s @ %s!", Group(pb.qty), CompactMoney(pb.lockedUnit or pb.previewAvg)))
				StyleButton(bait.actBtn, 0.92, 0.68, 0.12, true)
			else
				bait.actMode = "quoting"
				bait.actBtn.fs:SetText(format("1/2 Locking x%s Quote…", Group(pb.qty)))
				StyleButton(bait.actBtn, 0.20, 0.52, 0.68, true)
			end
			bait.cancelBtn.fs:SetText("Cancel Buy")
			StyleButton(bait.cancelBtn, 0.75, 0.26, 0.22, true)
			StyleButton(bait.resetBtn, 0.2, 0.2, 0.2, false)
		elseif bait.snipeQty > 0 then
			bait.actMode = "snipe"
			local netSell = floor((floorP or bait.snipeAvg) * AH_CUT + 0.5)
			local estGain = max(0, (netSell - bait.snipeAvg) * bait.snipeQty)
			bait.actBtn.fs:SetText(estGain > 0
				and format("SNIPE x%s @ %s (+%s!)", Group(bait.snipeQty), CompactMoney(bait.snipeAvg), CompactMoney(estGain))
				or format("SNIPE x%s @ %s!", Group(bait.snipeQty), CompactMoney(bait.snipeAvg)))
			StyleButton(bait.actBtn, 0.16, 0.78, 0.34, true)
			local canCancel = bait.ownQty > 0 or bait.pendingPost ~= nil
			bait.cancelBtn.fs:SetText(bait.needSeparateQuery and not bait.ownAuctionID[itemID] and "Find Bait ID" or "Cancel Bait")
			StyleButton(bait.cancelBtn, 0.75, 0.26, 0.22, canCancel)
			StyleButton(bait.resetBtn, 0.30, 0.30, 0.36, bait.ownQty == 0)
		elseif bait.pendingPost then
			bait.actMode = "confirm_post"
			bait.actBtn.fs:SetText(format("Confirm Undercut (1 @ %s)", CompactMoney(bait.pendingPost.price)))
			StyleButton(bait.actBtn, 0.92, 0.58, 0.12, true)
			bait.cancelBtn.fs:SetText("Abort Post")
			StyleButton(bait.cancelBtn, 0.75, 0.26, 0.22, true)
			StyleButton(bait.resetBtn, 0.2, 0.2, 0.2, false)
		elseif bait.ownQty > 0 then
			bait.actMode = "watch"
			bait.actBtn.fs:SetText(format("Bait Active (1 @ %s) • Refresh", CompactMoney(bait.ownUnit or baitP or 0)))
			StyleButton(bait.actBtn, 0.24, 0.52, 0.78, true)
			bait.cancelBtn.fs:SetText((not bait.ownAuctionID[itemID]) and "Locate & Cancel" or "Cancel Bait")
			StyleButton(bait.cancelBtn, 0.78, 0.28, 0.22, true)
			StyleButton(bait.resetBtn, 0.2, 0.2, 0.2, false)
		elseif floorP and baitP and baitP < floorP then
			bait.actMode = "post"
			bait.actBtn.fs:SetText(format("Post 1 Bait @ %s", CompactMoney(baitP)))
			StyleButton(bait.actBtn, 0.80, 0.62, 0.20, bagCount > 0)
			bait.cancelBtn.fs:SetText("Cancel Bait")
			StyleButton(bait.cancelBtn, 0.2, 0.2, 0.2, false)
			StyleButton(bait.resetBtn, 0.32, 0.32, 0.38, true)
		else
			bait.actMode = "refresh"
			bait.actBtn.fs:SetText("Scan Live Price")
			StyleButton(bait.actBtn, 0.32, 0.48, 0.72, true)
			bait.cancelBtn.fs:SetText("Cancel Bait")
			StyleButton(bait.cancelBtn, 0.2, 0.2, 0.2, false)
			StyleButton(bait.resetBtn, 0.2, 0.2, 0.2, false)
		end

		-- Status Line
		if bait.statusMsg then
			local c = bait.statusColor or { 0.8, 0.8, 0.84 }
			bait.statusFS:SetTextColor(c[1], c[2], c[3])
			bait.statusFS:SetText(bait.statusMsg)
		elseif bait.snipeQty > 0 then
			bait.statusFS:SetTextColor(0.35, 0.96, 0.52)
			bait.statusFS:SetText(format(cs.isCounterHit
				and "COUNTER-SNIPE TARGET: %s non-owner units at <= %s — click SNIPE!"
				or "TARGET ON HOOK: %s non-owner units at <= %s — click SNIPE!",
				Group(bait.snipeQty), CompactMoney(maxSnipeP or 0)))
		elseif bait.ownQty > 0 and cs.enabled then
			bait.statusFS:SetTextColor(0.55, 0.90, 0.75)
			bait.statusFS:SetText(format("Bait armed + Counter-Snipe Top %d ON (Sweep #%d) — watching your bait & hunting other snipers…", #cs.keys, cs.sweeps))
		elseif bait.ownQty > 0 then
			bait.statusFS:SetTextColor(0.65, 0.82, 0.98)
			bait.statusFS:SetText("Bait is sitting at #1 lowest price — auto-refreshing every 1s for sellers matching it…")
		elseif cs.enabled and ahOpen then
			bait.statusFS:SetTextColor(0.55, 0.90, 0.68)
			bait.statusFS:SetText(format("Counter-Snipe Top %d ON (Sweep #%d) — watching hottest traded mats for sniper baits & undercuts…", #cs.keys, cs.sweeps))
		elseif cs.enabled then
			bait.statusFS:SetTextColor(0.85, 0.78, 0.42)
			bait.statusFS:SetText("Counter-Snipe Top 50 armed — open the Auction House to start sweeping live markets.")
		elseif bait.snipedUnits > 0 then
			bait.statusFS:SetTextColor(0.45, 0.90, 0.55)
			bait.statusFS:SetText(format("Session Sniped: %s units (Est. +%s net flip value)", Group(bait.snipedUnits), CompactMoney(bait.snipedProfit)))
		else
			bait.statusFS:SetTextColor(0.62, 0.62, 0.66)
			bait.statusFS:SetText(ahOpen and "Ready: post 1 bait or turn ON Counter-Snipe Top 50; click the green popup (or macro) to buy!" or "Visit an Auctioneer to post bait or sweep Top 50 traded items.")
		end

		-- Hold row layout completely still while the cursor is hovering a [SNIPE TARGET] row to click it.
		if bait.hoverSnipeRow and bait.snipeQty > 0 and not forceList then
			return
		end

		-- Only rebuild/repaint the scrollable list when the order book tiers, watchlist mode, or bag materials actually changed
		-- (eliminates row flashing while sitting on the Bait & Snipe tab).
		local sigParts = { format("%d:%s:%d:%d:%d:%s:%d", itemID or 0, tostring(ahOpen), floorP or 0, bPct, sPct, tostring(cs.enabled), #cs.ids) }
		for i = 1, #bait.tiers do
			local t = bait.tiers[i]
			sigParts[#sigParts + 1] = format("%d/%d/%d/%s", t.unitPrice, t.other, t.own, t.isSnipe and "1" or "0")
		end
		local orderSig = table.concat(sigParts, "|")
		if not (forceList or bait.bagsDirty or orderSig ~= bait.lastOrderSig) then
			return
		end
		bait.lastOrderSig = orderSig

		-- Build Scrollable Rows: Live Order Book + Bag Materials
		local rowW = bait.scroll:GetWidth() or (WIDTH - PAD * 2 - 14)
		local rIdx, yOff = 0, 0

		if itemID and ahOpen and #bait.tiers > 0 then
			rIdx = rIdx + 1
			yOff = yOff + PaintHeaderRow(rIdx, yOff, rowW, "LIVE ORDER BOOK (Steady — Updates Only On Change)") + B_GAP
			for i = 1, #bait.tiers do
				local t = bait.tiers[i]
				rIdx = rIdx + 1
				local r = GetBaitRow(rIdx)
				r.data = { kind = "tier", unitPrice = t.unitPrice, other = t.other, own = t.own, isSnipe = t.isSnipe }
				r:EnableMouse(true)
				r.hl:SetAlpha(t.isSnipe and 1 or 0.35)
				r:SetSize(rowW, B_ROW_H)
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", bait.content, "TOPLEFT", 0, -yOff)
				r.headFS:Hide(); r.headLine:Hide()
				r.iconBg:Hide(); r.icon:Hide(); r.border:Hide()
				r.leftTop:SetPoint("TOPLEFT", 10, -4)
				r.leftBot:SetPoint("BOTTOMLEFT", 10, 4)

				if t.isSnipe then
					r.bg:SetColorTexture(0.12, 0.42, 0.20, 0.36)
					local netUnit = floor((floorP or t.unitPrice) * AH_CUT + 0.5) - t.unitPrice
					r.leftTop:SetText(format("|cff5cd65c[SNIPE TARGET]|r  %s  ×  |cffffffff%s available|r", Money(t.unitPrice), Group(t.other)))
					r.leftBot:SetText(t.own > 0
						and format("Includes your %d bait (auto-skipped) • Est. +%s/ea net", t.own, CompactMoney(max(0, netUnit)))
						or format("Click row or SNIPE popup • Est. +%s/ea net", CompactMoney(max(0, netUnit))))
					r.rightFS:SetText("|cff5cd65cClick to Buy|r")
				elseif t.own > 0 and t.other == 0 then
					r.bg:SetColorTexture(0.45, 0.35, 0.12, 0.28)
					r.leftTop:SetText(format("|cffffd200[YOUR BAIT]|r  %s  ×  %d", Money(t.unitPrice), t.own))
					r.leftBot:SetText("Trap armed — waiting for sellers to auto-fill this price")
					r.rightFS:SetText("|cffffd200Active Trap|r")
				else
					r.bg:SetColorTexture(1, 1, 1, (i % 2 == 1) and 0.035 or 0.018)
					r.leftTop:SetText(format("%s  ×  |cffd0d0d5%s units|r", Money(t.unitPrice), Group(t.other)))
					r.leftBot:SetText("Above Max Snipe cap (market wall)")
					r.rightFS:SetText("|cff8c8c8cMarket Wall|r")
				end
				r.leftTop:Show(); r.leftBot:Show(); r.rightFS:Show()
				r:Show()
				yOff = yOff + B_ROW_H + B_GAP
			end
			yOff = yOff + 4
		end

		-- Bag Materials Section (re-collected only when bags or selection changed)
		if bait.bagsDirty then
			bait.bagsDirty = false
			wipe(bait.bagMats)
			if ns.CollectBagHoldings then
				ns.CollectBagHoldings(bait.bagHold)
				local prices = ns.db and ns.db.ahPrices or {}
				local market = ns.db and ns.db.ahMarket or {}
				for id, rec in pairs(bait.bagHold) do
					if IsCommodityMaterial(id, rec.classID) then
						local p = bait.baseline[id] or prices[id] or 0
						local m = market[id]
						bait.bagMats[#bait.bagMats + 1] = {
							id = id,
							count = rec.count or 0,
							price = p,
							posts = (m and m.n) or 0,
							rec = rec,
						}
					end
				end
				sort(bait.bagMats, function(a, b)
					if (a.id == itemID) ~= (b.id == itemID) then return a.id == itemID end
					if (a.posts > 0) ~= (b.posts > 0) then return a.posts > 0 end
					if a.posts ~= b.posts then return a.posts > b.posts end
					return (a.price * a.count) > (b.price * b.count)
				end)
			end
		else
			local prices = ns.db and ns.db.ahPrices or {}
			for i = 1, #bait.bagMats do
				local mEntry = bait.bagMats[i]
				mEntry.price = bait.baseline[mEntry.id] or prices[mEntry.id] or mEntry.price or 0
			end
		end

		rIdx = rIdx + 1
		yOff = yOff + PaintHeaderRow(rIdx, yOff, rowW, "YOUR BAG MATERIALS (Click to Arm Bait)") + B_GAP

		if #bait.bagMats == 0 then
			rIdx = rIdx + 1
			local r = GetBaitRow(rIdx)
			r.data = nil
			r:EnableMouse(false)
			r:SetSize(rowW, B_ROW_H)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", bait.content, "TOPLEFT", 0, -yOff)
			r.bg:SetColorTexture(1, 1, 1, 0.02)
			r.hl:SetAlpha(0)
			r.headFS:Hide(); r.headLine:Hide()
			r.iconBg:Hide(); r.icon:Hide(); r.border:Hide()
			r.leftTop:SetPoint("TOPLEFT", 10, -10)
			r.leftTop:SetText("|cff8c8c8cNo tradeable stackable materials found in your bags.|r")
			r.leftTop:Show(); r.leftBot:Hide(); r.rightFS:Hide()
			r:Show()
			yOff = yOff + B_ROW_H + B_GAP
		else
			for i = 1, min(#bait.bagMats, 45) do
				local mEntry = bait.bagMats[i]
				local id = mEntry.id
				local m = ns.db and ns.db.ahMarket and ns.db.ahMarket[id]
				local name, link, quality, icon = ResolveItemMeta(id, m, mEntry.rec)
				local qr, qg, qb, qhex = QualityColor(quality)
				rIdx = rIdx + 1
				local r = GetBaitRow(rIdx)
				r.data = { kind = "mat", id = id, link = link }
				r:EnableMouse(true)
				r.hl:SetAlpha(1)
				r:SetSize(rowW, B_ROW_H)
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", bait.content, "TOPLEFT", 0, -yOff)
				r.headFS:Hide(); r.headLine:Hide()
				r.iconBg:Show(); r.icon:Show(); r.border:Show()
				r.icon:SetTexture(icon or 134400)
				r.border:SetVertexColor(qr, qg, qb, 1)
				r.leftTop:SetPoint("TOPLEFT", 38, -4)
				r.leftBot:SetPoint("BOTTOMLEFT", 38, 4)

				local selected = (id == itemID)
				if selected then
					r.bg:SetColorTexture(0.83, 0.66, 0.31, 0.22)
				else
					r.bg:SetColorTexture(1, 1, 1, (i % 2 == 1) and 0.035 or 0.018)
				end
				r.leftTop:SetText(format("%s%s|r |cffb5b5ba×%s|r%s",
					qhex, name or ("Item #" .. id), Group(mEntry.count), selected and "  |cffffd200[Armed]|r" or ""))
				if mEntry.price > 0 then
					local sugBait = SanitizeUnitPrice(mEntry.price * bPct / 100)
					r.leftBot:SetText(format("Floor: %s  ->  Bait (%d%%): |cffffd200%s|r", CompactMoney(mEntry.price), bPct, CompactMoney(sugBait)))
					r.rightFS:SetText(CompactMoney(mEntry.price * mEntry.count))
				else
					r.leftBot:SetText("Click while at AH to query live floor")
					r.rightFS:SetText("|cff8c8c8cUncached|r")
				end
				r.leftTop:Show(); r.leftBot:Show(); r.rightFS:Show()
				r:Show()
				yOff = yOff + B_ROW_H + B_GAP
			end
		end

		if cs.enabled and #cs.ids > 0 then
			yOff = yOff + 4
			rIdx = rIdx + 1
			yOff = yOff + PaintHeaderRow(rIdx, yOff, rowW,
				format("COUNTER-SNIPE WATCHLIST (Top %d Hottest Materials — Swept Every 2s)", #cs.ids)) + B_GAP
			for i = 1, #cs.ids do
				local id = cs.ids[i]
				local m = ns.db and ns.db.ahMarket and ns.db.ahMarket[id]
				local name, link, quality, icon = ResolveItemMeta(id, m, nil)
				local qr, qg, qb, qhex = QualityColor(quality)
				local ref = cs.refFloor[id] or (ns.db and ns.db.ahPrices and ns.db.ahPrices[id]) or 0
				local trig = ref > 0 and SanitizeUnitPrice(ref * sPct / 100) or 0

				rIdx = rIdx + 1
				local r = GetBaitRow(rIdx)
				r.data = { kind = "watch", id = id, link = link }
				r:EnableMouse(true)
				r.hl:SetAlpha(1)
				r:SetSize(rowW, B_ROW_H)
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", bait.content, "TOPLEFT", 0, -yOff)
				r.headFS:Hide(); r.headLine:Hide()
				r.iconBg:Show(); r.icon:Show(); r.border:Show()
				r.icon:SetTexture(icon or 134400)
				r.border:SetVertexColor(qr, qg, qb, 1)
				r.leftTop:SetPoint("TOPLEFT", 38, -4)
				r.leftBot:SetPoint("BOTTOMLEFT", 38, 4)

				local selected = (id == itemID)
				if selected then
					r.bg:SetColorTexture(0.18, 0.62, 0.34, 0.24)
				else
					r.bg:SetColorTexture(1, 1, 1, (i % 2 == 1) and 0.035 or 0.018)
				end
				local posts = (m and m.n) or 0
				r.leftTop:SetText(format("|cff8c8c8c#%d|r %s%s|r%s",
					i, qhex, name or ("Item #" .. id), selected and "  |cff5cd65c[Inspecting]|r" or ""))
				if ref > 0 then
					r.leftBot:SetText(format("Wall Floor: %s  ->  Alert at <= |cff5cd65c%s|r (%d%%)",
						CompactMoney(ref), CompactMoney(trig), sPct))
					r.rightFS:SetText(posts > 0 and format("|cffb5b5ba%s posts|r", Group(posts)) or CompactMoney(ref))
				else
					r.leftBot:SetText("Click to inspect live order book")
					r.rightFS:SetText("|cff8c8c8cWatching|r")
				end
				r.leftTop:Show(); r.leftBot:Show(); r.rightFS:Show()
				r:Show()
				yOff = yOff + B_ROW_H + B_GAP
			end
		end

		for i = rIdx + 1, #bait.rows do
			bait.rows[i]:Hide()
			bait.rows[i].data = nil
		end
		bait.content:SetSize(rowW, max(1, yOff - B_GAP))
	end

	local function StopBaitWatch()
		if bait.ticker then
			bait.ticker:Cancel()
			bait.ticker = nil
		end
	end

	StartBaitWatch = function()
		if bait.ticker then return end
		bait.ticker = C_Timer.NewTicker(1.0, function()
			local panelShown = bait.panel and bait.panel:IsShown() and mkt and mkt:IsShown()
			local ahOpen = ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen()
			if not (panelShown or (ahOpen and HasBackgroundRadar())) then
				StopBaitWatch()
				return
			end
			if bait.pendingBuy and bait.pendingBuy.quoteConfirmed
				and C_AuctionHouse and C_AuctionHouse.GetQuoteDurationRemaining
				and C_AuctionHouse.GetQuoteDurationRemaining() == 0 then
				if C_AuctionHouse.CancelCommoditiesPurchase then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
				bait.pendingBuy = nil
				SetStatus("Locked quote expired — watching live order book…", 1, 0.68, 0.25)
				RefreshBaitUI()
			end
			if ahOpen and not (ns.IsAuctionScanBusy and ns.IsAuctionScanBusy()) and not ns.ahScanning and not bait.pendingBuy and not bait.pendingPost then
				local cs = bait.cs
				local watchSingle = bait.itemID and (panelShown or bait.ownQty > 0 or bait.postedByUs[bait.itemID] == true or cs.isCounterHit or bait.snipeQty > 0)
				cs.tickParity = (cs.tickParity + 1) % 2
				if cs.verifyID and not cs.verifySent then
					cs.verifySent = QueryLiveItem(cs.verifyID, false)
				elseif cs.enabled and cs.tickParity == 1 then
					if not RunCounterSweep() and watchSingle then
						QueryLiveItem(bait.itemID, false)
					end
				elseif watchSingle then
					QueryLiveItem(bait.itemID, false)
				end
			end
		end)
	end

	local function BuildBaitPanel(parent)
		local p = CreateFrame("Frame", nil, parent)
		bait.panel = p

		-- Top Control Deck Card
		local deck = CreateFrame("Frame", nil, p)
		deck:SetHeight(DECK_H)
		deck:SetPoint("TOPLEFT", 0, 0)
		deck:SetPoint("TOPRIGHT", 0, 0)
		local deckBg = deck:CreateTexture(nil, "BACKGROUND")
		deckBg:SetAllPoints()
		deckBg:SetColorTexture(1, 1, 1, 0.04)
		local deckTop = deck:CreateTexture(nil, "ARTWORK")
		deckTop:SetHeight(1)
		deckTop:SetPoint("TOPLEFT"); deckTop:SetPoint("TOPRIGHT")
		deckTop:SetColorTexture(0.83, 0.66, 0.31, 0.40)
		local deckBot = deck:CreateTexture(nil, "ARTWORK")
		deckBot:SetHeight(1)
		deckBot:SetPoint("BOTTOMLEFT"); deckBot:SetPoint("BOTTOMRIGHT")
		deckBot:SetColorTexture(1, 1, 1, 0.12)
		bait.deck = deck

		-- Drop/Select Material Slot
		local slot = CreateFrame("Button", nil, deck)
		slot:SetSize(36, 36)
		slot:SetPoint("TOPLEFT", 8, -8)
		slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local sBg = slot:CreateTexture(nil, "BACKGROUND")
		sBg:SetAllPoints()
		sBg:SetColorTexture(SLOTBG[1], SLOTBG[2], SLOTBG[3], 1)
		local sIcon = slot:CreateTexture(nil, "ARTWORK")
		sIcon:SetSize(32, 32)
		sIcon:SetPoint("CENTER")
		sIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		sIcon:Hide()
		bait.slotIcon = sIcon
		local sBorder = slot:CreateTexture(nil, "OVERLAY")
		sBorder:SetAllPoints()
		sBorder:SetTexture(M .. "slot_border")
		sBorder:SetVertexColor(TRIM[1], TRIM[2], TRIM[3], 1)
		bait.slotBorder = sBorder
		local sHL = slot:CreateTexture(nil, "HIGHLIGHT")
		sHL:SetAllPoints()
		sHL:SetColorTexture(1, 0.82, 0, 0.18)
		local sCount = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		sCount:SetPoint("BOTTOMRIGHT", -2, 2)
		bait.slotCount = sCount

		local function TryAcceptCursorMaterial()
			if not (CursorHasItem and CursorHasItem() and GetCursorInfo) then return false end
			local kind, id = GetCursorInfo()
			if ClearCursor then ClearCursor() end
			if kind == "item" and id and IsCommodityMaterial(id, nil) then
				Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
				SelectBaitItem(id)
			else
				SetStatus("Drop a stackable commodity material (ore, herb, cloth, leather, dust…).", 1, 0.55, 0.25)
				RefreshBaitUI()
			end
			return true
		end
		slot:SetScript("OnReceiveDrag", TryAcceptCursorMaterial)
		slot:SetScript("OnClick", function(self, btn)
			if TryAcceptCursorMaterial() then return end
			if btn == "RightButton" and bait.itemID and bait.ownQty == 0 then
				bait.itemID = nil
				SetStatus(nil)
				RefreshBaitUI()
			elseif IsModifiedClick and IsModifiedClick("CHATLINK") and self.link then
				if ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(self.link)
				elseif ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
			elseif bait.itemID then
				QueryLiveItem(bait.itemID, false)
				RefreshBaitUI()
			end
		end)
		slot:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if bait.itemID then
				if self.link then GameTooltip:SetHyperlink(self.link) else GameTooltip:SetItemByID(bait.itemID) end
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Drag another material here to switch, or right-click to clear.", 0.65, 0.65, 0.65)
			else
				GameTooltip:SetText("Bait Target Material", 1, 0.82, 0)
				GameTooltip:AddLine("Click any material in the list below or drag one from your bags onto this slot.", 0.8, 0.8, 0.8, true)
			end
			GameTooltip:Show()
		end)
		slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
		bait.slotBtn = slot

		local nameFS = deck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		nameFS:SetPoint("TOPLEFT", 52, -9)
		nameFS:SetPoint("TOPRIGHT", -8, -9)
		nameFS:SetJustifyH("LEFT")
		bait.nameFS = nameFS

		local priceFS = deck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		priceFS:SetPoint("TOPLEFT", 52, -27)
		priceFS:SetPoint("TOPRIGHT", -8, -27)
		priceFS:SetJustifyH("LEFT")
		bait.priceFS = priceFS

		-- Row 2: Bait % & Max Snipe % Preset Pills
		local bLbl = deck:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		bLbl:SetPoint("TOPLEFT", 8, -51)
		bLbl:SetText("Bait Price:")
		local px = 66
		for i, pct in ipairs(BAIT_PCTS) do
			local b = CreateFrame("Button", nil, deck)
			b:SetSize(36, 18)
			b:SetPoint("TOPLEFT", px + (i - 1) * 39, -48)
			b.pct = pct
			b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
			b.fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			b.fs:SetPoint("CENTER"); b.fs:SetText(pct .. "%")
			local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 0.82, 0, 0.14)
			b:SetScript("OnClick", function()
				Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
				if ns.db then
					ns.db.baitPct = pct
					if (ns.db.snipeMaxPct or 75) <= pct then
						ns.db.snipeMaxPct = min(90, pct + 20)
					end
				end
				if bait.pendingPost and bait.itemID and bait.ownQty <= 0 and not bait.postingItemID then
					bait.postedByUs[bait.itemID] = nil
				end
				bait.pendingPost = nil
				bait.lastOrderSig = nil
				RefreshBaitUI(true)
			end)
			bait.baitPills[i] = b
		end

		local sLbl = deck:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		sLbl:SetPoint("TOPLEFT", 230, -51)
		sLbl:SetText("Max Snipe:")
		local sx = 290
		for i, pct in ipairs(SNIPE_PCTS) do
			local b = CreateFrame("Button", nil, deck)
			b:SetSize(38, 18)
			b:SetPoint("TOPLEFT", sx + (i - 1) * 40, -48)
			b.pct = pct
			b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
			b.fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			b.fs:SetPoint("CENTER"); b.fs:SetText(pct .. "%")
			local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.3, 1, 0.5, 0.14)
			b:SetScript("OnClick", function()
				Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
				if ns.db then
					ns.db.snipeMaxPct = pct
					if (ns.db.baitPct or 35) >= pct then
						ns.db.baitPct = BAIT_PCTS[1]
					end
				end
				wipe(bait.cs.ignoreUntil)
				bait.lastOrderSig = nil
				RefreshBaitUI(true)
			end)
			bait.snipePills[i] = b
		end

		local csBtn = CreateFrame("Button", nil, deck)
		csBtn:SetSize(236, 18)
		csBtn:SetPoint("TOPRIGHT", -8, -48)
		csBtn:RegisterForClicks("LeftButtonUp")
		csBtn.bg = csBtn:CreateTexture(nil, "BACKGROUND"); csBtn.bg:SetAllPoints()
		csBtn.edge = csBtn:CreateTexture(nil, "ARTWORK"); csBtn.edge:SetHeight(1)
		csBtn.edge:SetPoint("BOTTOMLEFT"); csBtn.edge:SetPoint("BOTTOMRIGHT")
		csBtn.fs = csBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		csBtn.fs:SetPoint("CENTER", 0, 0)
		local csHL = csBtn:CreateTexture(nil, "HIGHLIGHT"); csHL:SetAllPoints(); csHL:SetColorTexture(0.3, 1, 0.5, 0.16)
		csBtn:SetScript("OnClick", function()
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			ns.ToggleCounterSnipe()
		end)
		csBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Counter-Snipe Top 50 Radar", 0.35, 0.98, 0.55)
			GameTooltip:AddLine("Sweeps the 50 hottest traded materials on the Auction House every ~2s in a single lightweight batch.", 0.85, 0.85, 0.88, true)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("• Spots other snipers' 1-unit baits so you can eat their bait and break their trap.", 0.95, 0.82, 0.30, true)
			GameTooltip:AddLine("• Catches mispriced stacks & victims posting onto sniper baits across all Top 50 items.", 0.55, 0.95, 0.65, true)
			GameTooltip:AddLine("• Verifies the live market wall before alerting so normal price drops never false-alarm.", 0.72, 0.82, 0.95, true)
			GameTooltip:Show()
		end)
		csBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		bait.cs.btn = csBtn

		-- Row 3: Hardware-Click Action Buttons
		local function MakeDeckBtn(w)
			local b = CreateFrame("Button", nil, deck)
			b:SetSize(w, 24)
			b:RegisterForClicks("LeftButtonUp")
			b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
			b.edge = b:CreateTexture(nil, "ARTWORK"); b.edge:SetHeight(1)
			b.edge:SetPoint("BOTTOMLEFT"); b.edge:SetPoint("BOTTOMRIGHT")
			b.fs = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			b.fs:SetPoint("CENTER", 0, 0)
			local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
			return b
		end

		local resetBtn = MakeDeckBtn(104)
		resetBtn:SetPoint("TOPRIGHT", -8, -72)
		resetBtn.fs:SetText("Refresh Floor")
		resetBtn:SetScript("OnClick", function()
			if not bait.itemID then return end
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
			bait.baseline[bait.itemID] = nil
			bait.postedByUs[bait.itemID] = nil
			bait.cs.isCounterHit = false
			QueryLiveItem(bait.itemID, false)
			SetStatus("Re-reading unbaited market floor…", 0.78, 0.84, 0.95)
			RefreshBaitUI()
		end)
		resetBtn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Refresh Market Floor", 1, 0.82, 0)
			GameTooltip:AddLine("Clears the remembered pre-bait floor and re-reads the current live Auction House price (disabled while your own bait is active on the AH).", 0.85, 0.85, 0.88, true)
			GameTooltip:Show()
		end)
		resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		bait.resetBtn = resetBtn

		local cancelBtn = MakeDeckBtn(132)
		cancelBtn:SetPoint("RIGHT", resetBtn, "LEFT", -6, 0)
		cancelBtn:SetScript("OnClick", OnCancelBait)
		bait.cancelBtn = cancelBtn

		local actBtn = MakeDeckBtn(330)
		actBtn:SetPoint("TOPLEFT", 8, -72)
		actBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -6, 0)
		actBtn:SetScript("OnClick", OnPrimaryAction)
		bait.actBtn = actBtn

		local statusFS = deck:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		statusFS:SetPoint("BOTTOMLEFT", 8, 5)
		statusFS:SetPoint("BOTTOMRIGHT", -8, 5)
		statusFS:SetJustifyH("LEFT")
		bait.statusFS = statusFS

		-- Scrollable Order Book + Bag Materials
		local scroll = TryTemplate("ScrollFrame", "DavesSackBaitScroll", p, "ScrollFrameTemplate")
		local nativeBar = scroll and scroll.ScrollBar
		if not nativeBar then
			scroll = scroll or CreateFrame("ScrollFrame", "DavesSackBaitScroll", p)
		end
		scroll:SetPoint("TOPLEFT", 0, -(DECK_H + 6))
		local content = CreateFrame("Frame", nil, scroll)
		content:SetSize(WIDTH - PAD * 2 - 14, 1)
		scroll:SetScrollChild(content)
		if nativeBar then
			if nativeBar.SetHideIfUnscrollable then nativeBar:SetHideIfUnscrollable(true) end
			nativeBar:ClearAllPoints()
			nativeBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
			nativeBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
			if scroll.SetPanExtent then scroll:SetPanExtent(B_ROW_H + B_GAP) end
		else
			scroll:EnableMouseWheel(true)
			scroll:SetScript("OnMouseWheel", function(self, delta)
				local cur = self:GetVerticalScroll() or 0
				local maxS = max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
				self:SetVerticalScroll(max(0, min(maxS, cur - delta * (B_ROW_H + B_GAP))))
			end)
		end
		bait.scroll, bait.content = scroll, content

		-- Dedicated AH Event Listener
		local ev = CreateFrame("Frame")
		bait.evFrame = ev
		ev:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
			if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
				if NotSecret(arg1) then
					if arg1 == bait.cs.verifyID then
						VerifyCounterCandidate(arg1)
						return
					end
					if arg1 == bait.itemID then
						if bait.needSeparateQuery and bait.ownAuctionID[arg1] then
							bait.needSeparateQuery = false
							SetStatus("Bait ID located — click Cancel Bait again to pull your 1 unit.", 0.95, 0.82, 0.25)
						end
						RefreshBaitUI()
					end
				end
			elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
				if bait.cs.verifyID and not bait.cs.verifySent then
					bait.cs.verifySent = QueryLiveItem(bait.cs.verifyID, false)
				end
			elseif event == "AUCTION_HOUSE_SHOW_NOTIFICATION" or event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" then
				local soldEnum = (Enum and Enum.AuctionHouseNotification and Enum.AuctionHouseNotification.AuctionSold) or 4
				if NotSecret(arg1) and arg1 == soldEnum then
					bait.lastSoldAt = (GetTime and GetTime()) or 0
					if NotSecret(arg3) and arg3 > 0 then
						for id, aid in pairs(bait.ownAuctionID) do
							if aid == arg3 then
								bait.ownAuctionID[id] = nil
								bait.postedByUs[id] = nil
								if id == bait.itemID or id == bait.cs.returnTrapID then
									SetStatus("Another buyer bought your 1 bait unit! Click Post 1 Bait (or try 50%–65%) to re-arm.", 1, 0.74, 0.28)
									C_Timer.After(0.30, function()
										if bait.itemID then QueryLiveItem(bait.itemID, false) end
										RefreshBaitUI()
									end)
								end
							end
						end
					end
				end
			elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
				if bait.postingItemID then
					if NotSecret(arg1) and arg1 > 0 then
						bait.ownAuctionID[bait.postingItemID] = arg1
					end
					local pid = bait.postingItemID
					bait.postingItemID = nil
					SetStatus("1 bait unit posted! Watching live order book every 1s…", 0.35, 0.92, 0.50)
					C_Timer.After(0.35, function()
						QueryLiveItem(pid, false)
						RefreshBaitUI()
					end)
				end
			elseif event == "AUCTION_HOUSE_POST_ERROR" or event == "AUCTION_HOUSE_SHOW_ERROR" then
				if bait.postingItemID then
					local pid = bait.postingItemID
					bait.postingItemID = nil
					if bait.ownQty <= 0 then bait.postedByUs[pid] = nil end
					RefreshBaitUI()
				end
			elseif event == "AUCTION_CANCELED" then
				local now = (GetTime and GetTime()) or 0
				local userCanceled = (bait.cancelingAt or 0) > 0 and (now - bait.cancelingAt) < 5.0
					and not ((bait.lastSoldAt or 0) > 0 and (now - bait.lastSoldAt) < 2.0)
				local clearedCur = false
				if NotSecret(arg1) and arg1 > 0 then
					for id, aid in pairs(bait.ownAuctionID) do
						if aid == arg1 then
							bait.ownAuctionID[id] = nil
							bait.postedByUs[id] = nil
							if id == bait.itemID then clearedCur = true end
						end
					end
				elseif userCanceled and bait.cancelingItem then
					local cid = bait.cancelingItem
					bait.ownAuctionID[cid] = nil
					bait.postedByUs[cid] = nil
					if cid == bait.itemID then clearedCur = true end
				elseif bait.itemID and bait.postedByUs[bait.itemID] then
					-- Commodity sale/change reported with auctionID == 0 while we did not click Cancel Bait:
					-- re-query the live order book so ScanOrderBook verifies whether our 1 bait unit was bought.
					C_Timer.After(0.25, function()
						if bait.itemID then QueryLiveItem(bait.itemID, false) end
						RefreshBaitUI()
					end)
				end
				if clearedCur then
					bait.cancelingAt, bait.cancelingItem = 0, nil
					bait.needSeparateQuery = false
					if userCanceled then
						SetStatus("Bait cancelled — 1 unit returned to your Mailbox.", 0.85, 0.85, 0.88)
					else
						SetStatus("Another buyer bought your 1 bait unit! Click Post 1 Bait (or try 50%–65%) to re-arm.", 1, 0.74, 0.28)
					end
					C_Timer.After(0.35, function()
						if bait.itemID then QueryLiveItem(bait.itemID, false) end
						RefreshBaitUI()
					end)
				end
			elseif event == "COMMODITY_PRICE_UPDATED" then
				local pb = bait.pendingBuy
				if pb and NotSecret(arg1) and NotSecret(arg2) then
					local unitP, totalP = arg1, arg2
					local gold = (GetMoney and GetMoney()) or 0
					local maxAllowed = pb.quoteCap or pb.maxUnit
					if unitP <= maxAllowed and totalP <= gold then
						pb.lockedUnit, pb.lockedTotal, pb.quoteConfirmed = unitP, totalP, true
						Sound("IG_ABILITY_ICON_DROP")
						SetStatus(format("2/2 QUOTE LOCKED (%s/ea) — CLICK AGAIN TO BUY!", CompactMoney(unitP)), 1, 0.86, 0.25)
						RefreshBaitUI()
					else
						if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
							pcall(C_AuctionHouse.CancelCommoditiesPurchase)
						end
						bait.pendingBuy = nil
						SetStatus(unitP > maxAllowed
							and "Protected! Cheap units were bought before lock-in (cancelled before spilling into market wall)."
							or "Not enough gold for locked quote.", 1, 0.65, 0.25)
						if not RestoreTrapAfterCounter(8) and bait.itemID then
							QueryLiveItem(bait.itemID, false)
						end
						RefreshBaitUI(true)
					end
				end
			elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
				local pb = bait.pendingBuy
				if pb then
					Sound("LOOT_WINDOW_COIN_SOUND")
					local paidUnit = pb.lockedUnit or pb.previewAvg or 0
					local netFloor = floor((pb.realFloor or paidUnit) * AH_CUT + 0.5)
					local profit = max(0, (netFloor - paidUnit) * pb.qty)
					bait.snipedUnits = bait.snipedUnits + pb.qty
					bait.snipedProfit = bait.snipedProfit + profit
					bait.pendingBuy = nil
					SetStatus(format("SNIPED x%s @ %s/ea! (Est. +%s net flip profit)",
						Group(pb.qty), CompactMoney(paidUnit), CompactMoney(profit)), 0.30, 0.98, 0.48)
					local id = pb.itemID
					local wasCounter = bait.cs.isCounterHit
					C_Timer.After(0.40, function()
						if wasCounter and RestoreTrapAfterCounter(6) then
							RefreshBaitUI(true)
						else
							bait.cs.isCounterHit = false
							QueryLiveItem(id, false)
							RefreshBaitUI()
						end
					end)
				end
			elseif event == "COMMODITY_PRICE_UNAVAILABLE" or event == "COMMODITY_PURCHASE_FAILED" then
				if bait.pendingBuy then
					if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
						pcall(C_AuctionHouse.CancelCommoditiesPurchase)
					end
					bait.pendingBuy = nil
					SetStatus("Target stack was bought just before lock-in — watching for next seller…", 1, 0.68, 0.25)
					if not RestoreTrapAfterCounter(8) and bait.itemID then
						QueryLiveItem(bait.itemID, false)
					end
					RefreshBaitUI(true)
				end
			elseif event == "AUCTION_HOUSE_SHOW" then
				if (bait.panel and bait.panel:IsShown()) or HasBackgroundRadar() then
					StartBaitWatch()
					if bait.itemID then
						C_Timer.After(0.6, function()
							if bait.itemID and not (ns.IsAuctionScanBusy and ns.IsAuctionScanBusy()) and not ns.ahScanning then QueryLiveItem(bait.itemID, false) end
							RefreshBaitUI()
						end)
					else
						RefreshBaitUI()
					end
				end
			elseif event == "AUCTION_HOUSE_CLOSED" then
				StopBaitWatch()
				bait.pendingBuy = nil
				bait.pendingPost = nil
				bait.postingItemID = nil
				bait.cancelingAt, bait.cancelingItem = 0, nil
				bait.needSeparateQuery = false
				bait.internalQueryID = nil
				bait.cs.awaitBrowse, bait.cs.browseActive = false, false
				bait.cs.verifyID, bait.cs.verifyAt, bait.cs.verifySent = nil, nil, false
				bait.cs.pauseUntil = nil
				RestoreTrapAfterCounter(0)
				bait.snipeQty = 0
				bait.lastAlertQty = 0
				bait.previewUntil = nil
				bait.previewConfirmed = false
				if bait.alert and bait.alert.frame:IsShown() then
					bait.alert.frame:Hide()
				end
				RefreshBaitUI(true)
			elseif event == "BAG_UPDATE_DELAYED" then
				bait.bagsDirty = true
				if bait.panel and bait.panel:IsShown() then
					RefreshBaitUI(true)
				end
			end
		end)
	end

	function ns.SyncBaitHeight(w, h, topShift)
		if not bait.panel then return end
		local topY = -190 + (topShift or 26)
		local availH = max(180, h - (198 - (topShift or 26)) - 30)
		bait.panel:ClearAllPoints()
		bait.panel:SetPoint("TOPLEFT", PAD, topY)
		bait.panel:SetSize(w - PAD * 2, availH)
		if bait.scroll then
			bait.scroll:SetSize(w - PAD * 2 - 14, max(60, availH - DECK_H - 6))
		end
		if bait.content then
			bait.content:SetWidth(w - PAD * 2 - 14)
		end
	end

	function ns.ShowBaitPanel(parent, w)
		if not bait.panel then BuildBaitPanel(parent) end
		local h = parent:GetHeight() or 490
		ns.SyncBaitHeight(w or WIDTH, h, 26)
		for _, e in ipairs({
			"COMMODITY_SEARCH_RESULTS_UPDATED",
			"AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
			"AUCTION_HOUSE_SHOW_NOTIFICATION",
			"AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION",
			"AUCTION_HOUSE_AUCTION_CREATED",
			"AUCTION_HOUSE_POST_ERROR",
			"AUCTION_HOUSE_SHOW_ERROR",
			"AUCTION_CANCELED",
			"COMMODITY_PRICE_UPDATED",
			"COMMODITY_PRICE_UNAVAILABLE",
			"COMMODITY_PURCHASE_SUCCEEDED",
			"COMMODITY_PURCHASE_FAILED",
			"AUCTION_HOUSE_SHOW",
			"AUCTION_HOUSE_CLOSED",
			"BAG_UPDATE_DELAYED",
		}) do
			pcall(bait.evFrame.RegisterEvent, bait.evFrame, e)
		end
		bait.bagsDirty = true
		bait.lastOrderSig = nil
		bait.panel:Show()
		StartBaitWatch()
		if bait.itemID and ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen() and not (ns.IsAuctionScanBusy and ns.IsAuctionScanBusy()) and not ns.ahScanning then
			QueryLiveItem(bait.itemID, false)
		end
		RefreshBaitUI(true)
	end

	function ns.HideBaitPanel()
		local keepRadar = HasBackgroundRadar()
		local ahOpen = ns.IsAuctionHouseOpen and ns.IsAuctionHouseOpen()
		if not (keepRadar and ahOpen) then
			StopBaitWatch()
		end
		if bait.pendingBuy and C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then
			pcall(C_AuctionHouse.CancelCommoditiesPurchase)
		end
		bait.pendingBuy = nil
		if bait.evFrame then
			bait.evFrame:UnregisterAllEvents()
			if keepRadar then
				for _, e in ipairs({
					"COMMODITY_SEARCH_RESULTS_UPDATED",
					"AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
					"AUCTION_HOUSE_SHOW_NOTIFICATION",
					"AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION",
					"AUCTION_HOUSE_AUCTION_CREATED",
					"AUCTION_HOUSE_POST_ERROR",
					"AUCTION_HOUSE_SHOW_ERROR",
					"AUCTION_CANCELED",
					"COMMODITY_PRICE_UPDATED",
					"COMMODITY_PRICE_UNAVAILABLE",
					"COMMODITY_PURCHASE_SUCCEEDED",
					"COMMODITY_PURCHASE_FAILED",
					"AUCTION_HOUSE_SHOW",
					"AUCTION_HOUSE_CLOSED",
				}) do
					pcall(bait.evFrame.RegisterEvent, bait.evFrame, e)
				end
			elseif bait.postingItemID or next(bait.postedByUs) ~= nil then
				for _, e in ipairs({ "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_CANCELED", "AUCTION_HOUSE_SHOW_NOTIFICATION", "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", "AUCTION_HOUSE_CLOSED" }) do
					pcall(bait.evFrame.RegisterEvent, bait.evFrame, e)
				end
			end
		end
		if bait.panel then
			bait.panel:Hide()
		end
	end
end
