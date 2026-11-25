-- Where each boss and rare spawn is on its dungeon's map: its floor (the index of the instance's
-- floors in Data/DungeonMaps.lua, else Data/DungeonDrawn.lua) and its place on that floor's picture,
-- 0..1 across and down (Stitch/Dungeons.lua's boss & rare pins).
--   [instance mapID] = { [name] = { floor, x, y [, rare = true] [, spots = { { floor, x, y }, ... }] [, note = "..."] }, ... }
--   ["minimap:<mapID>"] = the same, on its map built from the minimap pictures (Data/DungeonMinimap.lua)
-- Built from Blizzard JournalEncounter (5.5.4 / 12.1.5), pre-Cataclysm Classic spawn/waypoint tables,
-- and verified positions on WoW: Forever's drawn dungeon maps.

local _, ns = ...

ns.MapDungeonBosses = {
	[33] = { -- Shadowfang Keep
		["Rethilgore"] = { 1, 0.6614, 0.7115, note = "Courtyard prison cell" }, -- WotLK 3.3.5
		["Razorclaw the Butcher"] = { 2, 0.4803, 0.2895, note = "Dining Hall" }, -- WotLK 3.3.5
		["Baron Silverlaine"] = { 2, 0.3044, 0.7740 }, -- MoP Classic journal
		["Commander Springvale"] = { 1, 0.2804, 0.5973 }, -- MoP Classic journal
		["Odo the Blindwatcher"] = { 7, 0.5510, 0.7715, note = "The Wall Walk" }, -- WotLK 3.3.5
		["Fenrus the Devourer"] = { 4, 0.5743, 0.4331, note = "Lower Observatory" }, -- WotLK 3.3.5
		["Wolf Master Nandos"] = { 5, 0.6178, 0.2867, note = "Upper Observatory" }, -- WotLK 3.3.5
		["Archmage Arugal"] = { 6, 0.6390, 0.2003, note = "Upper tower chamber" }, -- WotLK 3.3.5
		["Deathsworn Captain"] = { 7, 0.6296, 0.5250, rare = true, spots = { { 7, 0.6296, 0.5250 }, { 7, 0.6914, 0.7887 }, { 7, 0.7294, 0.6365 } }, note = "Patrols The Wall Walk battlements" }, -- WotLK 3.3.5 waypoints
	},
	[34] = { -- Stormwind Stockade
		["Targorr the Dread"] = { 1, 0.4987, 0.2422 }, -- WotLK 3.3.5
		["Kam Deepfury"] = { 1, 0.6920, 0.3094 }, -- WotLK 3.3.5
		["Hamhock"] = { 1, 0.7817, 0.4566 }, -- WotLK 3.3.5
		["Dextren Ward"] = { 1, 0.1455, 0.2136 }, -- WotLK 3.3.5
		["Bazil Thredd"] = { 1, 0.8641, 0.5200 }, -- WotLK 3.3.5
		["Bruegal Ironknuckle"] = { 1, 0.3811, 0.2403, rare = true, note = "North-west cell block" }, -- WotLK 3.3.5
	},
	[36] = { -- Deadmines
		["Rhahk'Zor"] = { 1, 0.3653, 0.6123 }, -- retail journal
		["Sneed"] = { 1, 0.5020, 0.8683 }, -- retail journal
		["Miner Johnson"] = { 1, 0.5169, 0.5039, rare = true, note = "Side alcove off the Mast Room" }, -- WotLK 3.3.5
		["Gilnid"] = { 2, 0.1248, 0.7590 }, -- retail journal
		["Mr. Smite"] = { 2, 0.5518, 0.2536 }, -- retail journal
		["Captain Greenskin"] = { 2, 0.6076, 0.3748 }, -- retail journal
		["Cookie"] = { 2, 0.6763, 0.4017 }, -- retail journal
		["Edwin VanCleef"] = { 2, 0.6076, 0.4489 }, -- retail journal
	},
	[43] = { -- Wailing Caverns
		["Lady Anacondra"] = { 1, 0.3060, 0.4303 }, -- MoP Classic journal
		["Lord Cobrahn"] = { 1, 0.1667, 0.5676 }, -- MoP Classic journal
		["Kresh"] = { 1, 0.3852, 0.3607 }, -- MoP Classic journal
		["Lord Pythas"] = { 1, 0.1913, 0.3955 }, -- MoP Classic journal
		["Skum"] = { 1, 0.6230, 0.7439 }, -- MoP Classic journal
		["Lord Serpentis"] = { 1, 0.6161, 0.5389 }, -- MoP Classic journal
		["Verdan the Everliving"] = { 1, 0.5546, 0.4652 }, -- MoP Classic journal
		["Mutanus the Devourer"] = { 1, 0.3456, 0.1373, note = "Summoned by Naralex escort" }, -- MoP Classic journal
		["Deviate Faerie Dragon"] = { 1, 0.6583, 0.3430, rare = true, note = "Central cavern ledge" }, -- WotLK 3.3.5
	},
	[47] = { -- Razorfen Kraul
		["Roogug"] = { 1, 0.4271, 0.5630 }, -- placed (OpenMap v0.8.13)
		["Aggem Thorncurse"] = { 1, 0.8019, 0.5164 }, -- MoP Classic journal
		["Death Speaker Jargba"] = { 1, 0.8730, 0.4221 }, -- MoP Classic journal
		["Overlord Ramtusk"] = { 1, 0.5710, 0.3053 }, -- MoP Classic journal
		["Agathelos the Raging"] = { 1, 0.0806, 0.6885 }, -- MoP Classic journal
		["Charlga Razorflank"] = { 1, 0.2172, 0.3135 }, -- MoP Classic journal
		["Blind Hunter"] = { 1, 0.1096, 0.3032, rare = true, note = "Bat cave north of Charlga" }, -- WotLK 3.3.5
		["Earthcaller Halmgar"] = { 1, 0.4937, 0.4706, rare = true, note = "South side tunnel off central ring" }, -- WotLK 3.3.5
		["Razorfen Spearhide"] = { 1, 0.5624, 0.2926, rare = true, note = "Near Overlord Ramtusk" }, -- WotLK 3.3.5
	},
	[48] = { -- Blackfathom Deeps
		["Ghamoo-ra"] = { 1, 0.3333, 0.6069 }, -- MoP Classic journal
		["Lady Sarevess"] = { 1, 0.1119, 0.3896 }, -- MoP Classic journal
		["Gelihast"] = { 1, 0.5433, 0.5642 }, -- MoP Classic journal
		["Lorgus Jett"] = { 2, 0.3543, 0.4829, rare = true, note = "Moonshrine Sanctum alcove" }, -- WotLK 3.3.5
		["Baron Aquanis"] = { 3, 0.2340, 0.4980, note = "Summoned at the Fathom Stone" }, -- WotLK 3.3.5 GO
		["Old Serra'kis"] = { 3, 0.5866, 0.3090 }, -- MoP Classic journal
		["Twilight Lord Kelris"] = { 2, 0.5239, 0.8082 }, -- MoP Classic journal
		["Aku'mai"] = { 2, 0.8552, 0.8642 }, -- MoP Classic journal
	},
	[70] = { -- Uldaman
		["Revelosh"] = { 1, 0.5342, 0.7254 }, -- MoP Classic journal
		["The Lost Dwarves"] = { 1, 0.5847, 0.9201 }, -- MoP Classic journal
		["Ironaya"] = { 1, 0.3730, 0.7398 }, -- MoP Classic journal
		["Obsidian Sentinel"] = { 1, 0.2894, 0.5974 }, -- MoP Classic journal
		["Ancient Stone Keeper"] = { 1, 0.4754, 0.4406 }, -- MoP Classic journal
		["Galgann Firehammer"] = { 1, 0.2678, 0.3279 }, -- MoP Classic journal
		["Grimlok"] = { 1, 0.2199, 0.2561 }, -- MoP Classic journal
		["Archaedas"] = { 2, 0.5533, 0.5041 }, -- MoP Classic journal
	},
	[90] = { -- Gnomeregan
		["Grubbis"] = { 1, 0.7787, 0.6701 }, -- MoP Classic journal
		["Viscous Fallout"] = { 2, 0.7596, 0.4652 }, -- MoP Classic journal
		["Electrocutioner 6000"] = { 2, 0.2432, 0.6844 }, -- MoP Classic journal
		["Crowd Pummeler 9-60"] = { 3, 0.4317, 0.8832 }, -- MoP Classic journal
		["Mekgineer Thermaplugg"] = { 4, 0.3115, 0.3033 }, -- MoP Classic journal
		["Dark Iron Ambassador"] = { 4, 0.4340, 0.6219, rare = true, spots = { { 4, 0.4340, 0.6219 }, { 3, 0.2031, 0.5701 } }, note = "Entrance hall to Tinkers' Court" }, -- WotLK 3.3.5
	},
	[109] = { -- Sunken Temple
		["Atal'alarion"] = { 1, 0.4981, 0.4861, note = "Lower Pit of Refuse (statue puzzle)" }, -- WotLK 3.3.5
		["Atal'ai Defenders"] = { 1, 0.4498, 0.5902, spots = { { 1, 0.4498, 0.5902 }, { 1, 0.5515, 0.5888 }, { 1, 0.6019, 0.4564 }, { 1, 0.5501, 0.3245 }, { 1, 0.4485, 0.3259 }, { 1, 0.3982, 0.4580 } }, note = "6 troll mini-bosses on upper ring balconies" }, -- WotLK 3.3.5
		["Avatar of Hakkar"] = { 1, 0.2432, 0.4590, note = "Summoned at the Altar of Hakkar" }, -- MoP Classic journal
		["Jammal'an the Prophet"] = { 1, 0.7609, 0.4590, note = "With Ogom the Wretched" }, -- MoP Classic journal
		["Dreamscythe"] = { 1, 0.4397, 0.4279, note = "Dragon balcony above the Pit" }, -- WotLK 3.3.5
		["Weaver"] = { 1, 0.4533, 0.4396, note = "Dragon balcony above the Pit" }, -- WotLK 3.3.5
		["Morphaz"] = { 1, 0.4887, 0.8901, note = "South dragon hall before Eranikus" }, -- WotLK 3.3.5
		["Hazzas"] = { 1, 0.5208, 0.8896, note = "South dragon hall before Eranikus" }, -- WotLK 3.3.5
		["Shade of Eranikus"] = { 1, 0.6708, 0.8770 }, -- MoP Classic journal
		["Spawn of Hakkar"] = { 1, 0.5948, 0.6075, rare = true, spots = { { 1, 0.5948, 0.6075 }, { 1, 0.5139, 0.2474 }, { 1, 0.4186, 0.2908 } }, note = "Patrols the lower sunken ring" }, -- WotLK 3.3.5 pool/wp
	},
	[129] = { -- Razorfen Downs
		["Tuten'kash"] = { 1, 0.5943, 0.3402 }, -- MoP Classic journal
		["Plaguemaw the Rotting"] = { 1, 0.4772, 0.2117, note = "Summoned by Belnistrasz's Idol event" }, -- WotLK 3.3.5 GO
		["Mordresh Fire Eye"] = { 1, 0.8607, 0.4672 }, -- MoP Classic journal
		["Ragglesnout"] = { 1, 0.5295, 0.6723, rare = true, note = "Quilboar huts along the central spiral" }, -- WotLK 3.3.5
		["Glutton"] = { 1, 0.3429, 0.6680 }, -- MoP Classic journal
		["Amnennar the Coldbringer"] = { 1, 0.4454, 0.6045 }, -- MoP Classic journal
	},
	[189] = { -- Scarlet Monastery
		["Interrogator Vishas"] = { 1, 0.7154, 0.5894, note = "Graveyard wing" }, -- WotLK 3.3.5
		["Bloodmage Thalnos"] = { 1, 0.2440, 0.5077, note = "Graveyard crypt" }, -- WotLK 3.3.5
		["Fallen Champion"] = { 1, 0.3589, 0.6629, rare = true, note = "Graveyard rare (shares spawn with Ironspine/Azshir)" }, -- WotLK 3.3.5
		["Ironspine"] = { 1, 0.5171, 0.6788, rare = true, note = "Graveyard rare (shares spawn with Fallen Champion/Azshir)" }, -- WotLK 3.3.5
		["Azshir the Sleepless"] = { 1, 0.2825, 0.4336, rare = true, note = "Graveyard crypt rare (shares spawn with Ironspine/Fallen Champion)" }, -- WotLK 3.3.5
		["Houndmaster Loksey"] = { 2, 0.3079, 0.8780, note = "Library kennels" }, -- WotLK 3.3.5
		["Arcanist Doan"] = { 2, 0.8321, 0.7451, note = "Library sanctum" }, -- WotLK 3.3.5
		["Herod"] = { 3, 0.7865, 0.1077, note = "Armory circular hall" }, -- WotLK 3.3.5
		["High Inquisitor Fairbanks"] = { 4, 0.5541, 0.2611, note = "Cathedral secret room behind alcove" }, -- WotLK 3.3.5
		["High Inquisitor Whitemane"] = { 4, 0.4904, 0.1688, note = "Cathedral chapel with Mograine" }, -- WotLK 3.3.5
	},
	[209] = { -- Zul'Farrak
		["Hydromancer Velratha"] = { 1, 0.3362, 0.4484 }, -- MoP Classic journal
		["Gahz'rilla"] = { 1, 0.2809, 0.3828, note = "Summoned with Mallet of Zul'Farrak" }, -- MoP Classic journal
		["Antu'sul"] = { 1, 0.6462, 0.2766 }, -- MoP Classic journal
		["Theka the Martyr"] = { 1, 0.5314, 0.2623 }, -- MoP Classic journal
		["Witch Doctor Zum'rah"] = { 1, 0.4426, 0.1762 }, -- MoP Classic journal
		["Nekrum Gutchewer"] = { 1, 0.3074, 0.1853, note = "Pyramid stairs event" }, -- WotLK 3.3.5 script
		["Shadowpriest Sezz'ziz"] = { 1, 0.3075, 0.1796, note = "Pyramid stairs event" }, -- WotLK 3.3.5 script
		["Chief Ukorz Sandscalp"] = { 1, 0.4221, 0.3299 }, -- MoP Classic journal
		["Sandarr Dunereaver"] = { 1, 0.4406, 0.5482, rare = true, note = "South plaza near entrance" }, -- WotLK 3.3.5
		["Dustwraith"] = { 1, 0.3422, 0.2039, rare = true, note = "Beside the pyramid gate" }, -- WotLK 3.3.5
		["Zerillis"] = { 1, 0.5206, 0.4094, rare = true, note = "Central courtyard" }, -- WotLK 3.3.5
	},
	[229] = { -- Blackrock Spire
		["Highlord Omokk"] = { 3, 0.3866, 0.5902 }, -- MoP Classic journal
		["Shadow Hunter Vosh'gajin"] = { 2, 0.5533, 0.6926 }, -- MoP Classic journal
		["War Master Voone"] = { 1, 0.5246, 0.5451 }, -- MoP Classic journal
		["Mother Smolderweb"] = { 2, 0.6207, 0.7414 }, -- MoP Classic journal
		["Urok Doomhowl"] = { 4, 0.4549, 0.5574, note = "Summoned at Omokk's pike" }, -- MoP Classic journal
		["Quartermaster Zigris"] = { 5, 0.5396, 0.8443 }, -- MoP Classic journal
		["Halycon"] = { 5, 0.3798, 0.8402 }, -- MoP Classic journal
		["Gizrul the Slavener"] = { 5, 0.3948, 0.7930 }, -- MoP Classic journal
		["Overlord Wyrmthalak"] = { 6, 0.5751, 0.6004 }, -- MoP Classic journal
		["Pyroguard Emberseer"] = { 6, 0.3033, 0.2664, note = "Upper Blackrock Spire entry chamber" }, -- MoP Classic journal
		["Warchief Rend Blackhand"] = { 7, 0.5122, 0.2455, note = "Blackrock Stadium arena" }, -- WotLK 3.3.5
		["The Beast"] = { 7, 0.6477, 0.3048, note = "Hall of Binding" }, -- WotLK 3.3.5
		["General Drakkisath"] = { 7, 0.3344, 0.4532, note = "Hall of Ascension" }, -- WotLK 3.3.5
		["Lord Valthalak"] = { 7, 0.6147, 0.4301, note = "Tier 0.5 quest summon in The Beast's room" }, -- WotLK 3.3.5
		["Bannok Grimaxe"] = { 1, 0.4952, 0.5600, rare = true, note = "Tazz'Alor near War Master Voone" }, -- WotLK 3.3.5
		["Crystal Fang"] = { 2, 0.4654, 0.6935, rare = true, note = "Skitterweb Tunnels" }, -- WotLK 3.3.5
		["Spirestone Lord Magus"] = { 3, 0.4185, 0.5668, rare = true, note = "Hordemar City ogre mound" }, -- WotLK 3.3.5
		["Spirestone Battle Lord"] = { 3, 0.4822, 0.5739, rare = true, note = "Hordemar City ogre hall" }, -- WotLK 3.3.5
		["Spirestone Butcher"] = { 3, 0.5102, 0.5767, rare = true, spots = { { 3, 0.5102, 0.5767 }, { 3, 0.5560, 0.5781 }, { 3, 0.4766, 0.5775 } }, note = "Patrols Hordemar City ogre bridge" }, -- WotLK 3.3.5 waypoints
		["Burning Felguard"] = { 4, 0.3777, 0.7051, rare = true, note = "Hall of Blackhand ledge" }, -- WotLK 3.3.5
		["Ghok Bashguud"] = { 4, 0.3404, 0.6671, rare = true, note = "Hall of Blackhand" }, -- WotLK 3.3.5
		["Goraluk Anvilcrack"] = { 7, 0.2856, 0.2693, rare = true, note = "Upper Spire forge near Emberseer" }, -- WotLK 3.3.5
		["Jed Runewatcher"] = { 7, 0.3863, 0.2729, rare = true, spots = { { 7, 0.3863, 0.2729 }, { 7, 0.4439, 0.2350 }, { 7, 0.3638, 0.2730 } }, note = "Patrols Upper Spire balcony above Rookery" }, -- WotLK 3.3.5 waypoints
	},
	[230] = { -- Blackrock Depths
		["High Interrogator Gerstahn"] = { 1, 0.4740, 0.9221 }, -- MoP Classic journal
		["Lord Roccor"] = { 1, 0.5560, 0.6701, note = "Patrols outer Ring of Law" }, -- MoP Classic journal
		["Houndmaster Grebmar"] = { 1, 0.5350, 0.5735 }, -- MoP Classic journal
		["Ring of Law"] = { 1, 0.4978, 0.6458 }, -- MoP Classic journal
		["Pyromancer Loregrain"] = { 2, 0.5492, 0.9488, note = "Shrine of Thaurissan" }, -- MoP Classic journal
		["Lord Incendius"] = { 1, 0.5642, 0.3115 }, -- MoP Classic journal
		["Warder Stilgiss"] = { 2, 0.6025, 0.6598, note = "Guards The Vault with Verek" }, -- MoP Classic journal
		["Fineous Darkvire"] = { 1, 0.6352, 0.2111 }, -- MoP Classic journal
		["Bael'Gar"] = { 1, 0.2514, 0.5348 }, -- MoP Classic journal
		["General Angerforge"] = { 2, 0.3634, 0.8238 }, -- MoP Classic journal
		["Golem Lord Argelmach"] = { 2, 0.3648, 0.6516 }, -- MoP Classic journal
		["Hurley Blackbreath"] = { 2, 0.5057, 0.7048, note = "Grim Guzzler" }, -- MoP Classic journal
		["Phalanx"] = { 2, 0.4582, 0.5647, note = "Grim Guzzler" }, -- MoP Classic journal
		["Ribbly Screwspigot"] = { 2, 0.5255, 0.6254, note = "Grim Guzzler" }, -- MoP Classic journal
		["Plugger Spazzring"] = { 2, 0.4772, 0.6571, note = "Grim Guzzler" }, -- MoP Classic journal
		["The Vault"] = { 2, 0.6161, 0.6925, note = "Dark Coffer & Watchman Doomgrip" }, -- WotLK 3.3.5 GO
		["Ambassador Flamelash"] = { 2, 0.5383, 0.4857 }, -- MoP Classic journal
		["The Seven"] = { 2, 0.5383, 0.2480, note = "Summoner's Tomb" }, -- MoP Classic journal
		["Magmus"] = { 2, 0.7964, 0.1189 }, -- MoP Classic journal
		["Princess Moira Bronzebeard"] = { 2, 0.9315, 0.1148, note = "Imperial Seat with Emperor Thaurissan" }, -- WotLK 3.3.5
		["Emperor Dagran Thaurissan"] = { 2, 0.9098, 0.1189 }, -- MoP Classic journal
		["Panzor the Invincible"] = { 2, 0.4879, 0.3628, rare = true, spots = { { 2, 0.4879, 0.3628 }, { 2, 0.5061, 0.3283 }, { 2, 0.4679, 0.3443 } }, note = "Mold Foundry (patrols golem floor)" }, -- WotLK 3.3.5
	},
	[249] = { -- Onyxia's Lair
		["Onyxia"] = { 1, 0.6724, 0.3099 }, -- retail journal
	},
	[289] = { -- Scholomance
		["Kirtonos"] = { 2, 0.4949, 0.0429, note = "Summoned at Brazier of the Herald" }, -- WotLK 3.3.5 GO
		["Jandice Barov"] = { 2, 0.5403, 0.2368, note = "Vault of the Ravenian" }, -- WotLK 3.3.5
		["Rattlegore"] = { 2, 0.3175, 0.6836, note = "Lower bone pit" }, -- WotLK 3.3.5
		["Marduk Blackpool"] = { 2, 0.4436, 0.6386, note = "Viewing Room" }, -- WotLK 3.3.5
		["Vectus"] = { 2, 0.4825, 0.6620, note = "Viewing Room" }, -- WotLK 3.3.5
		["Kormok"] = { 4, 0.4280, 0.8830, note = "Tier 0.5 quest summon in Ras's room" }, -- WotLK 3.3.5
		["Ras Frostwhisperer"] = { 4, 0.4061, 0.8836, note = "Great Ossuary" }, -- WotLK 3.3.5
		["Instructor Malicia"] = { 3, 0.7277, 0.8085, note = "Upper Study south room" }, -- WotLK 3.3.5
		["Doctor Theolen Krastinov"] = { 3, 0.9556, 0.4589, note = "Butcher's room" }, -- WotLK 3.3.5
		["Lorekeeper Polkelt"] = { 3, 0.7196, 0.1201, note = "Upper Study north room" }, -- WotLK 3.3.5
		["The Ravenian"] = { 4, 0.6753, 0.5209, note = "Headmaster's Study south room" }, -- WotLK 3.3.5
		["Lord Alexei Barov"] = { 4, 0.8435, 0.3078, note = "Headmaster's Study east room" }, -- WotLK 3.3.5
		["Lady Illucia Barov"] = { 4, 0.6704, 0.0614, note = "Headmaster's Study north room" }, -- WotLK 3.3.5
		["Darkmaster Gandling"] = { 4, 0.6823, 0.3021, note = "Spawns after clearing the 6 study bosses" }, -- WotLK 3.3.5
	},
	[309] = { -- Zul'Gurub
		["High Priestess Jeklik"] = { 1, 0.3619, 0.7542, note = "Bat altar" }, -- WotLK 3.3.5
		["High Priest Venoxis"] = { 1, 0.5100, 0.5374, note = "Snake altar" }, -- MoP Classic journal
		["High Priestess Mar'li"] = { 1, 0.4548, 0.7787, note = "Spider altar" }, -- WotLK 3.3.5
		["Bloodlord Mandokir"] = { 1, 0.6199, 0.6665, note = "Raptor stairs" }, -- WotLK 3.3.5
		["Edge of Madness"] = { 1, 0.6023, 0.4681, note = "Brazier of Madness" }, -- WotLK 3.3.5 GO
		["High Priest Thekal"] = { 1, 0.6537, 0.3364, note = "Tiger temple" }, -- WotLK 3.3.5
		["Gahz'ranka"] = { 1, 0.4215, 0.4355, note = "Fished from Muddy Churning Waters" }, -- WotLK 3.3.5 GO
		["High Priestess Arlokk"] = { 1, 0.4789, 0.1995, note = "Summoned at Gong of Bethekk" }, -- WotLK 3.3.5 script
		["Jin'do the Hexxer"] = { 1, 0.3126, 0.2056, note = "North-west hex pit" }, -- WotLK 3.3.5
		["Hakkar"] = { 1, 0.4889, 0.3976, note = "Altar of the Blood God" }, -- WotLK 3.3.5
	},
	[329] = { -- Stratholme
		["Hearthsinger Forresten"] = { 1, 0.6052, 0.3135, rare = true, spots = { { 1, 0.6052, 0.3135 }, { 1, 0.8473, 0.4542 } }, note = "Live side (Festival Lane or Elders' Square)" }, -- MoP Classic + WotLK 3.3.5
		["Timmy the Cruel"] = { 1, 0.5000, 0.1783, note = "Spawns after clearing Scarlet Bastion square" }, -- MoP Classic journal
		["Malor the Zealous"] = { 1, 0.3045, 0.4004, note = "Scarlet Bastion hall" }, -- WotLK 3.3.5
		["Cannon Master Willey"] = { 1, 0.0359, 0.5014, note = "Scarlet Bastion cannon room" }, -- WotLK 3.3.5
		["Archivist Galford"] = { 1, 0.2713, 0.7513, note = "Scarlet Bastion library" }, -- WotLK 3.3.5
		["Balnazzar"] = { 1, 0.2049, 0.8217, note = "Grand Crusader Dathrohan" }, -- MoP Classic journal
		["The Unforgiven"] = { 1, 0.7350, 0.2049, note = "Ambush near Festival Lane" }, -- MoP Classic journal
		["Baroness Anastari"] = { 2, 0.7459, 0.4693 }, -- MoP Classic journal
		["Nerub'enkan"] = { 2, 0.5724, 0.4611 }, -- MoP Classic journal
		["Maleki the Pallid"] = { 2, 0.6749, 0.2275 }, -- MoP Classic journal
		["Magistrate Barthilas"] = { 2, 0.5669, 0.1619, spots = { { 2, 0.5669, 0.1619 }, { 2, 0.6534, 0.7550 } }, note = "Slaughter Square (Service Gate entry) or Service Gate (Main Gate entry)" }, -- MoP Classic + WotLK 3.3.5
		["Ramstein the Gorger"] = { 2, 0.4563, 0.1988, note = "Slaughter Square" }, -- MoP Classic journal
		["Baron Rivendare"] = { 2, 0.3722, 0.1993, note = "Slaughter House" }, -- WotLK 3.3.5
		["Black Guard Swordsmith"] = { 2, 0.7272, 0.5236, note = "Summoned at Blacksmithing Plans" }, -- WotLK 3.3.5 GO
		["Crimson Hammersmith"] = { 1, 0.1250, 0.4760, note = "Summoned at Blacksmithing Plans" }, -- WotLK 3.3.5 GO
		["Ezra Grimm"] = { 1, 0.5416, 0.7138, note = "Fras Siabi's tobacco shop" }, -- WotLK 3.3.5
		["Postmaster Malown"] = { 1, 0.5581, 0.6841, note = "Spawns after opening 3 postboxes" }, -- retail journal
		["Skul"] = { 1, 0.5754, 0.6967, rare = true, spots = { { 1, 0.5754, 0.6967 }, { 2, 0.6534, 0.7550 } }, note = "Can spawn near Main Gate (F1) or Service Gate (F2)" }, -- WotLK 3.3.5
		["Stonespine"] = { 2, 0.6197, 0.2509, rare = true, spots = { { 2, 0.6197, 0.2509 }, { 2, 0.6693, 0.5185 }, { 2, 0.5963, 0.4600 } }, note = "Patrols Undead side among Rockwing Gargoyles" }, -- WotLK 3.3.5
	},
	[349] = { -- Maraudon
		["Noxxion"] = { 1, 0.3620, 0.0984 }, -- MoP Classic journal
		["Razorlash"] = { 1, 0.1667, 0.3443 }, -- MoP Classic journal
		["Tinkerer Gizlock"] = { 1, 0.5096, 0.5307 }, -- MoP Classic journal
		["Lord Vyletongue"] = { 1, 0.3784, 0.7049 }, -- MoP Classic journal
		["Celebras the Cursed"] = { 2, 0.2459, 0.1434 }, -- MoP Classic journal
		["Landslide"] = { 2, 0.4085, 0.4877 }, -- MoP Classic journal
		["Rotgrip"] = { 2, 0.4139, 0.8176 }, -- MoP Classic journal
		["Princess Theradras"] = { 2, 0.2582, 0.7889 }, -- MoP Classic journal
		["Meshlok the Harvester"] = { 1, 0.2275, 0.6621, rare = true, spots = { { 1, 0.2275, 0.6621 }, { 1, 0.2372, 0.7459 }, { 1, 0.2461, 0.8737 } }, note = "Patrols the Orange/Purple connecting cavern" }, -- WotLK 3.3.5 waypoints
	},
	[389] = { -- Ragefire Chasm
		["Oggleflint"] = { 1, 0.5605, 0.3800 }, -- WotLK 3.3.5
		["Taragaman the Hungerer"] = { 1, 0.4098, 0.5773 }, -- WotLK 3.3.5
		["Jergosh the Invoker"] = { 1, 0.3298, 0.8454 }, -- WotLK 3.3.5
		["Bazzalan"] = { 1, 0.4153, 0.8618 }, -- WotLK 3.3.5
	},
	[409] = { -- Molten Core
		["Lucifron"] = { 1, 0.6586, 0.3750 }, -- retail journal
		["Magmadar"] = { 1, 0.6943, 0.2368 }, -- retail journal
		["Gehennas"] = { 1, 0.3309, 0.4853 }, -- retail journal
		["Garr"] = { 1, 0.3151, 0.6896 }, -- retail journal
		["Shazzrah"] = { 1, 0.5584, 0.8526 }, -- retail journal
		["Baron Geddon"] = { 1, 0.5239, 0.7763 }, -- retail journal
		["Sulfuron Harbinger"] = { 1, 0.8283, 0.8255 }, -- retail journal
		["Golemagg the Incinerator"] = { 1, 0.6887, 0.5764 }, -- retail journal
		["Majordomo Executus"] = { 1, 0.8415, 0.6528 }, -- retail journal
		["Ragnaros"] = { 1, 0.5623, 0.5340 }, -- retail journal
	},
	[429] = { -- Dire Maul
		["Zevrim Thornhoof"] = { 6, 0.5751, 0.7439 }, -- MoP Classic journal
		["Hydrospawn"] = { 6, 0.5369, 0.7152 }, -- MoP Classic journal
		["Lethtendris"] = { 5, 0.4385, 0.4816 }, -- MoP Classic journal
		["Pusillin"] = { 5, 0.1224, 0.3103, spots = { { 5, 0.1224, 0.3103 }, { 6, 0.3183, 0.5597 } }, note = "Starts at East entrance (F5); chase down to F6" }, -- WotLK 3.3.5
		["Alzzin the Wildshaper"] = { 6, 0.5669, 0.2889 }, -- MoP Classic journal
		["Tendris Warpwood"] = { 2, 0.3361, 0.5369 }, -- MoP Classic journal
		["Illyanna Ravenoak"] = { 2, 0.2036, 0.7766 }, -- MoP Classic journal
		["Magister Kalendris"] = { 3, 0.3388, 0.4508 }, -- MoP Classic journal
		["Immol'thar"] = { 4, 0.3497, 0.5758 }, -- MoP Classic journal
		["Prince Tortheldrin"] = { 4, 0.6230, 0.2316 }, -- MoP Classic journal
		["Guard Mol'dar"] = { 1, 0.6954, 0.7602 }, -- MoP Classic journal
		["Stomper Kreeg"] = { 1, 0.6120, 0.6926 }, -- MoP Classic journal
		["Guard Fengus"] = { 1, 0.4945, 0.7807 }, -- MoP Classic journal
		["Guard Slip'kik"] = { 1, 0.2664, 0.5717 }, -- MoP Classic journal
		["Captain Kromcrush"] = { 1, 0.3183, 0.5061 }, -- MoP Classic journal
		["Cho'Rush the Observer"] = { 1, 0.3195, 0.3037 }, -- MoP Classic journal
		["King Gordok"] = { 1, 0.3195, 0.2295 }, -- MoP Classic journal
		["Lord Hel'nurath"] = { 4, 0.3690, 0.5620, note = "Warlock Dreadsteed quest summon in Immol'thar's arena" }, -- Classic
		["Tsu'zee"] = { 3, 0.3220, 0.1426, rare = true, note = "Court of the Highborne (Dire Maul West)" }, -- WotLK 3.3.5
	},
	[469] = { -- Blackwing Lair
		["Razorgore the Untamed"] = { 1, 0.4193, 0.6024 }, -- retail journal
		["Vaelastrasz the Corrupt"] = { 1, 0.3328, 0.2754 }, -- retail journal
		["Broodlord Lashlayer"] = { 3, 0.5058, 0.6175 }, -- retail journal
		["Firemaw"] = { 3, 0.4644, 0.4295 }, -- retail journal
		["Ebonroc"] = { 3, 0.3491, 0.2096 }, -- retail journal
		["Flamegor"] = { 4, 0.3554, 0.3712 }, -- retail journal
		["Chromaggus"] = { 4, 0.3942, 0.7265 }, -- retail journal
		["Nefarian"] = { 4, 0.7037, 0.7246 }, -- retail journal
	},
	[509] = { -- Ruins of Ahn'Qiraj
		["Kurinnaxx"] = { 1, 0.5635, 0.3574 }, -- retail journal
		["General Rajaxx"] = { 1, 0.5840, 0.4913 }, -- retail journal
		["Moam"] = { 1, 0.3286, 0.3605 }, -- retail journal
		["Buru the Gorger"] = { 1, 0.6979, 0.6205 }, -- retail journal
		["Ayamiss the Hunter"] = { 1, 0.6168, 0.9051 }, -- retail journal
		["Ossirian the Unscarred"] = { 1, 0.4291, 0.6959 }, -- retail journal
	},
	[531] = { -- Ahn'Qiraj Temple
		["The Prophet Skeram"] = { 2, 0.4579, 0.5220 }, -- retail journal
		["Silithid Royalty"] = { 1, 0.2845, 0.4974 }, -- retail journal
		["Battleguard Sartura"] = { 1, 0.4456, 0.3359 }, -- retail journal
		["Fankriss the Unyielding"] = { 1, 0.6230, 0.2190 }, -- retail journal
		["Viscidus"] = { 1, 0.7215, 0.1790 }, -- retail journal
		["Princess Huhuran"] = { 1, 0.4353, 0.5036 }, -- retail journal
		["Twin Emperors"] = { 1, 0.6209, 0.6949, note = "Vek'nilash & Vek'lor" }, -- WotLK 3.3.5
		["Ouro"] = { 1, 0.3020, 0.8190 }, -- retail journal
		["C'thun"] = { 3, 0.5707, 0.6251 }, -- retail journal
	},
	[2959] = { -- City of Dalaran
		["Fel Ancient"] = { 1, 0.5200, 0.5450, note = "Runeweaver Square" }, -- Forever drawn map
		["Shade of the Archmage"] = { 1, 0.5200, 0.2350, note = "The Violet Citadel" }, -- Forever drawn map
		["Atrexis the Grave Knight"] = { 2, 0.5450, 0.5100, note = "The Underbelly arena" }, -- Forever drawn map
		["Lyn the Ignored"] = { 2, 0.4150, 0.6600, rare = true, note = "Cantrips & Crows (The Underbelly)" }, -- Forever drawn map
	},
	[2970] = { -- The Drowned City
		["Zul'Alai"] = { 1, 0.6350, 0.5150, note = "Eastern ruin courtyard" }, -- Forever drawn map
		["Var'Taka"] = { 1, 0.2950, 0.5450, note = "Eternal Amphitheater" }, -- Forever drawn map
		["Captain Dreadrise"] = { 1, 0.4450, 0.3650, note = "Northern docks" }, -- Forever drawn map
		["Primeval Elemental"] = { 1, 0.1950, 0.5450, note = "Abyssal Dais" }, -- Forever drawn map
		["Min'loth the Serpent"] = { 1, 0.5550, 0.2700, note = "Altar of the Serpent" }, -- Forever drawn map
	},
	[2974] = { -- Blackmaw Hold
		["Bonesnout the Unbroken"] = { 1, 0.7600, 0.5450, note = "Bonesnout's Thicket" }, -- Forever drawn map
		["Withermaw"] = { 2, 0.6200, 0.2550, note = "Festering Grotto" }, -- Forever drawn map
		["Elder Shaman Bloodmane"] = { 4, 0.4550, 0.3750, note = "Depths of the Elders" }, -- Forever drawn map
		["Blackmaw Behemoth"] = { 5, 0.6250, 0.3350, note = "Depths of the Burrow" }, -- Forever drawn map
		["Varrox Bleakhoof"] = { 6, 0.6300, 0.6150, note = "Depths of Forbidden Magic" }, -- Forever drawn map
	},
	[2998] = { -- Excavation Site: Wetlands
		["Saltspine"] = { 1, 0.5550, 0.3650, note = "Lost Marsh" }, -- Forever drawn map
		["Shadetooth"] = { 1, 0.3400, 0.4550, note = "Stalker's Thicket" }, -- Forever drawn map
		["Highland Horror"] = { 1, 0.0950, 0.4850, note = "Lost Dig Site" }, -- Forever drawn map
		["Relic Guardian"] = { 1, 0.3450, 0.6800, note = "Site of the Guardian" }, -- Forever drawn map
	},
	[2999] = { -- Ruins of Lordaeron
		["Witherfang"] = { 1, 0.6750, 0.4250, note = "King's Alley" }, -- Forever drawn map
		["The Abandoned"] = { 1, 0.3650, 0.4400, note = "Market Street" }, -- Forever drawn map
		["Bjork"] = { 1, 0.5150, 0.4950, note = "Central Courtyard" }, -- Forever drawn map
		["Rath'mael"] = { 1, 0.4250, 0.7750, note = "Lordaeron Graveyard" }, -- Forever drawn map
		["Viktor the Vile"] = { 1, 0.5450, 0.6550, note = "Lordamere Overlook" }, -- Forever drawn map
		["Lordaeron Captain"] = { 1, 0.5150, 0.5850, rare = true, spots = { { 1, 0.3650, 0.5400 }, { 1, 0.5150, 0.5850 }, { 1, 0.6600, 0.5400 } }, note = "Patrols inner city streets" }, -- Forever drawn map
	},
	[3001] = { -- Shaper's Terrace
		["Nanaya"] = { 1, 0.7350, 0.6000, note = "Pillar of Assimilation" }, -- Forever drawn map
		["King Op"] = { 2, 0.3900, 0.2400, rare = true, note = "Prismatic Talus cave" }, -- Forever drawn map
	},
	[3065] = { -- The Hall of Thanes
		["Faldrim Anvilmar"] = { 1, 0.5100, 0.6650, note = "Anvilmar's Rest" }, -- Forever drawn map
		["Infurnus"] = { 1, 0.7350, 0.4800, note = "Dark Iron Ingress" }, -- Forever drawn map
		["Plunder"] = { 1, 0.5100, 0.5150, note = "Main Hall" }, -- Forever drawn map
		["Durgen Dirgehammer"] = { 1, 0.5080, 0.1720, note = "Reliquary of Kings" }, -- Forever drawn map
	},
}
