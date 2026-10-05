-- daves_castbar / Elements.lua
-- The looks (six elements and four gathering professions), and which one a spell gets.
--
-- WoW has no API that returns a spell's school (C_Spell.GetSpellInfo has none, and the combat
-- log is closed to addons on Forever), so the element comes from, in order:
--   1. your own choice for that spell (/castbar set <element>)
--   2. the gathering spells by name: Fishing, Mining, Herb Gathering, Skinning
--   3. the spell's name: known names first, then words in it ("Frost", "Flame", "Shadow", ...)
--   4. your class and specialization
--   5. the fallback setting (professions, hearthstone, mounts)

local _, ns = ...

-- Colours are 0-1. Layers scroll in texture widths (su) and heights (sv) per second; "a" is an
-- alpha range the layer breathes through. Particle sizes are fractions of the bar height,
-- speeds are pixels per second on a 28-pixel bar (scaled with the height), y up.
local function C(r, g, b) return { r / 255, g / 255, b / 255 } end

ns.ELEMENT_ORDER = { "frost", "fire", "shadow", "nature", "arcane", "holy", "fishing", "herbalism", "mining", "skinning" }

ns.ELEMENTS = {
	frost = {
		-- a band of water flows ahead of the cast (the track) and freezes into ice behind the fill edge
		label = "Frost", border = C(190, 225, 255), glow = C(110, 180, 255), spark = C(225, 245, 255), veil = C(140, 200, 255),
		layers = { { tex = "frost_ice" } },
		track = { tex = "frost_water", su = .05, a = .95, hi = "frost_water_hi", su2 = .09 },
		freeze = true, sweep = true,        -- the freeze front at the fill edge; a glint sweeps across the ice
		channelLook = "frost_channel",      -- channels drain, so they use the reversed look below
		emit = {
			{ tex = "p_flake", rate = 5, colors = { C(220, 240, 255) }, size = { .25, .45 }, life = { .8, 1.6 }, vx = { -24, -6 }, vy = { -8, 8 }, spin = { -1.5, 1.5 }, from = "edge", add = true },
			{ tex = "p_star", rate = 7, colors = { C(225, 245, 255) }, size = { .15, .3 }, life = { .3, .7 }, twinkle = true, add = true },
		},
	},
	-- Frost while channelling (Blizzard, ...): the bar drains from the right, so the roles swap. What is
	-- left of the channel is flowing water, the drained part behind the edge is ice, and the freeze front
	-- faces right, so the water still freezes as the channel runs instead of seeming to thaw.
	-- Not in ELEMENT_ORDER: StartCast picks it for frost channels.
	frost_channel = {
		label = "Frost", border = C(190, 225, 255), glow = C(110, 180, 255), spark = C(225, 245, 255), veil = C(140, 200, 255),
		layers = { { tex = "frost_water", su = .05, a = { .95, .95 } }, { tex = "frost_water_hi", su = .09, a = { .8, .8 }, add = true } },
		track = { tex = "frost_ice", a = .95 },
		freezeReverse = true,
		emit = {
			{ tex = "p_flake", rate = 5, colors = { C(220, 240, 255) }, size = { .25, .45 }, life = { .8, 1.6 }, vx = { 6, 24 }, vy = { -8, 8 }, spin = { -1.5, 1.5 }, from = "edge", add = true },
			{ tex = "p_star", rate = 7, colors = { C(225, 245, 255) }, size = { .15, .3 }, life = { .3, .7 }, twinkle = true, add = true },
		},
	},
	fire = {
		label = "Fire", border = C(220, 100, 30), glow = C(255, 110, 20), spark = C(255, 210, 140), veil = C(255, 120, 30),
		-- the flame tongues scroll upward (sv > 0); embers rise from the bottom and carry on off the top
		layers = { { tex = "fire_base", su = .02 }, { tex = "fire_flow", su = .025, sv = .55, a = { .5, .95 }, add = true, flicker = true } },
		emit = {
			{ tex = "p_ember", rate = 24, colors = { C(255, 170, 60), C(255, 120, 30), C(255, 220, 120) }, size = { .12, .26 }, life = { .5, 1.2 }, vx = { -8, 8 }, vy = { 15, 45 }, from = "bottom", swirl = 20, add = true },
			{ tex = "p_ember", rate = 16, colors = { C(255, 190, 80), C(255, 140, 40) }, size = { .08, .18 }, life = { .8, 1.6 }, vx = { -10, 10 }, vy = { 25, 55 }, from = "top", swirl = 25, add = true },
		},
	},
	shadow = {
		label = "Shadow", border = C(60, 30, 95), glow = C(130, 40, 220), spark = C(200, 130, 255), veil = C(90, 30, 160),
		layers = { { tex = "shadow_base", su = .01, sv = -.02 }, { tex = "shadow_flow", su = -.03, sv = -.06, a = { .5, 1 }, add = true } },
		emit = {
			{ tex = "p_soft", rate = 9, colors = { C(6, 4, 10) }, size = { .8, 1.4 }, life = { 1.6, 2.8 }, vx = { -10, -2 }, vy = { 3, 12 }, alpha = .7 },
			{ tex = "p_soft", rate = 8, colors = { C(180, 90, 255) }, size = { .1, .2 }, life = { .8, 1.6 }, vx = { -14, -4 }, vy = { -4, 10 }, from = "edge", add = true },
		},
	},
	nature = {
		label = "Nature", border = C(80, 150, 50), glow = C(110, 200, 60), spark = C(210, 255, 160), veil = C(120, 200, 80),
		layers = { { tex = "nature_base", su = .004 }, { tex = "nature_flow", su = .02, a = { .35, .8 }, add = true } },
		vines = true,
		emit = {
			{ tex = "p_soft", rate = 6, colors = { C(220, 255, 140) }, size = { .08, .16 }, life = { 1, 2 }, vx = { -6, 6 }, vy = { 2, 10 }, add = true },
		},
	},
	arcane = {
		label = "Arcane", border = C(90, 110, 255), glow = C(120, 110, 255), spark = C(230, 190, 255), veil = C(120, 90, 255),
		layers = { { tex = "arcane_base", su = .012 }, { tex = "arcane_flow", su = .028, a = { .55, 1 }, add = true } },
		glyphs = true,    -- rotating rune circles and glyphs that flare up
		emit = {
			{ tex = "p_star", rate = 10, colors = { C(255, 160, 235), C(150, 210, 255) }, size = { .15, .3 }, life = { .4, .9 }, vx = { -22, -5 }, vy = { -8, 8 }, from = "edge", twinkle = true, add = true },
		},
	},
	holy = {
		label = "Holy", border = C(240, 205, 120), glow = C(255, 210, 110), spark = C(255, 250, 220), veil = C(255, 220, 140),
		layers = { { tex = "holy_base", su = .008 }, { tex = "holy_flow", su = .02, a = { .4, .9 }, add = true } },
		twinkles = true,
		emit = {
			{ tex = "p_soft", rate = 12, colors = { C(255, 225, 150), C(255, 245, 210) }, size = { .08, .18 }, life = { 1, 2 }, vx = { -5, 5 }, vy = { 6, 18 }, add = true },
		},
	},

	-- Gathering professions
	fishing = {
		-- a pond the length of the bar: lily pads on top, fish below, the bobber riding the cast edge
		label = "Fishing", border = C(70, 170, 190), glow = C(80, 190, 220), spark = C(210, 245, 255), veil = C(90, 190, 210),
		channel = true,     -- Fishing is a channel: test casts and Edit Mode previews drain like the real one
		layers = { { tex = "fish_water", su = .004 }, { tex = "fish_caustic", su = .012, a = { .3, .6 }, add = true } },
		track = { tex = "fish_water", su = .004, a = .6 },
		pond = true,
		emit = {
			{ tex = "p_soft", rate = 3, colors = { C(220, 245, 255) }, size = { .06, .12 }, life = { 1, 1.8 }, vx = { -2, 2 }, vy = { 5, 12 }, from = "bottom", alpha = .7, add = true },
		},
	},
	herbalism = {
		-- the nature vines, with herbs and flowers blooming along them
		label = "Herbalism", border = C(110, 170, 60), glow = C(130, 210, 80), spark = C(230, 255, 180), veil = C(140, 210, 90),
		layers = { { tex = "nature_base", su = .004 }, { tex = "nature_flow", su = .02, a = { .35, .8 }, add = true } },
		vines = true, flowers = true,
		emit = {
			{ tex = "p_soft", rate = 8, colors = { C(255, 230, 120), C(230, 255, 160) }, size = { .06, .13 }, life = { 1.2, 2.2 }, vx = { -5, 5 }, vy = { 3, 10 }, add = true },
		},
	},
	mining = {
		-- rails along a rock wall: the gem cart rolls to the cast edge while a pickaxe strikes the wall at the end
		label = "Mining", border = C(190, 140, 80), glow = C(255, 170, 80), spark = C(255, 220, 150), veil = C(200, 140, 70),
		layers = { { tex = "mine_rails" }, { tex = "mine_flow", su = .01, a = { .4, .9 }, add = true, flicker = true } },
		track = { tex = "mine_rails", a = .35 },
		mine = true,
		emit = {
			{ tex = "p_soft", rate = 4, colors = { C(150, 130, 110) }, size = { .25, .5 }, life = { 1.2, 2 }, vx = { -4, 4 }, vy = { 1, 6 }, alpha = .35 },
		},
	},
	skinning = {
		-- a pasture of cows and pigs: the cleaver chops at the cast edge, and each animal it reaches
		-- becomes a bone pile on a blood stain
		label = "Skinning", border = C(150, 40, 40), glow = C(200, 50, 40), spark = C(255, 190, 170), veil = C(150, 60, 50),
		layers = { { tex = "skin_base" }, { tex = "skin_blood" } },
		track = { tex = "skin_base", a = .55 },
		skin = true,
		emit = {},
	},
}

-- Gathering spells (lowercase names), checked before anything else that guesses.
local GATHERING = {
	["fishing"] = "fishing", ["mining"] = "mining", ["herb gathering"] = "herbalism", ["herbalism"] = "herbalism",
	["skinning"] = "skinning",
}

---------------------------------------------------------------------------
-- Which element a spell gets
---------------------------------------------------------------------------
-- Exact names (lowercase) that the word rules below would get wrong.
local NAMES = {
	["holy fire"] = "holy", ["frostfire bolt"] = "frost", ["soul fire"] = "fire", ["searing pain"] = "fire",
	["shadowflame"] = "shadow", ["drain life"] = "shadow", ["drain soul"] = "shadow", ["drain mana"] = "shadow",
	["health funnel"] = "shadow", ["ritual of summoning"] = "shadow", ["create healthstone"] = "shadow",
	["create soulstone"] = "shadow", ["starfire"] = "arcane", ["moonfire"] = "arcane", ["starsurge"] = "arcane",
	["wrath"] = "nature", ["hurricane"] = "nature", ["tranquility"] = "nature", ["cyclone"] = "nature",
	["hibernate"] = "nature", ["entangling roots"] = "nature", ["rebirth"] = "nature", ["mind blast"] = "shadow",
	["mind flay"] = "shadow", ["mind control"] = "shadow", ["mind vision"] = "shadow", ["mind sear"] = "shadow",
	["smite"] = "holy", ["penance"] = "holy", ["prayer of healing"] = "holy", ["polymorph"] = "arcane",
	["evocation"] = "arcane", ["hearthstone"] = "arcane", ["lava burst"] = "fire", ["chain heal"] = "nature",
	["revive pet"] = "nature", ["aimed shot"] = "nature", ["frostbolt"] = "frost", ["fireball"] = "fire",
	-- shaman and druid heals are nature, not holy
	["healing wave"] = "nature", ["lesser healing wave"] = "nature", ["healing touch"] = "nature",
	["healing rain"] = "nature", ["healing stream totem"] = "nature", ["ancestral spirit"] = "nature",
}

-- Words in a name, checked in this order (so "Flash of Light" is holy, not fire's "flash").
local WORDS = {
	{ "frost", "frost" }, { "ice ", "frost" }, { "icy", "frost" }, { "blizzard", "frost" }, { "cone of cold", "frost" },
	{ "glacial", "frost" }, { "freez", "frost" }, { "chill", "frost" }, { "snow", "frost" },
	{ "shadow", "shadow" }, { "void", "shadow" }, { "corruption", "shadow" }, { "curse", "shadow" }, { "fear", "shadow" },
	{ "death", "shadow" }, { "dark", "shadow" }, { "soul", "shadow" }, { "haunt", "shadow" }, { "affliction", "shadow" },
	{ "siphon", "shadow" }, { "banish", "shadow" }, { "summon", "shadow" }, { "seed of", "shadow" }, { "mind ", "shadow" },
	{ "holy", "holy" }, { "light", "holy" }, { "heal", "holy" }, { "prayer", "holy" }, { "resurrect", "holy" },
	{ "redemption", "holy" }, { "divine", "holy" }, { "exorcism", "holy" }, { "renew", "holy" }, { "smite", "holy" },
	{ "arcane", "arcane" }, { "teleport", "arcane" }, { "portal", "arcane" }, { "conjure", "arcane" }, { "star", "arcane" },
	{ "moon", "arcane" }, { "mana", "arcane" }, { "slow", "arcane" },
	{ "fire", "fire" }, { "flame", "fire" }, { "pyro", "fire" }, { "scorch", "fire" }, { "burn", "fire" }, { "incinerat", "fire" },
	{ "immolat", "fire" }, { "conflagrat", "fire" }, { "searing", "fire" }, { "lava", "fire" }, { "ignite", "fire" },
	{ "meteor", "fire" }, { "combust", "fire" }, { "magma", "fire" },
	{ "lightning", "nature" }, { "thunder", "nature" }, { "earth", "nature" }, { "nature", "nature" }, { "wave", "nature" },
	{ "regrowth", "nature" }, { "rejuvenation", "nature" }, { "nourish", "nature" }, { "root", "nature" }, { "thorn", "nature" },
	{ "totem", "nature" }, { "poison", "nature" }, { "sting", "nature" }, { "wind", "nature" }, { "storm", "nature" },
}

-- Class (and specialization name) fallbacks.
local CLASSES = {
	MAGE = "arcane", WARLOCK = "shadow", PRIEST = "holy", DRUID = "nature", SHAMAN = "nature", PALADIN = "holy",
	HUNTER = "nature", DEATHKNIGHT = "frost", EVOKER = "fire", MONK = "nature", DEMONHUNTER = "shadow",
}
local SPEC_WORDS = { { "frost", "frost" }, { "fire", "fire" }, { "arcane", "arcane" }, { "shadow", "shadow" },
	{ "holy", "holy" }, { "unholy", "shadow" }, { "balance", "arcane" }, { "elemental", "nature" } }

local function SpecElement()
	local spec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
	if not spec or spec == 0 then return end
	local _, specName = C_SpecializationInfo.GetSpecializationInfo(spec)
	if type(specName) ~= "string" or issecretvalue(specName) then return end
	specName = specName:lower()
	for _, w in ipairs(SPEC_WORDS) do
		if specName:find(w[1], 1, true) then return w[2] end
	end
end

local function ClassElement()
	local _, class = UnitClass("player")
	if not class or issecretvalue(class) then return end
	return SpecElement() or CLASSES[class]
end

function ns:ResolveElement(spellID, name, isTradeskill)
	local own = spellID and not issecretvalue(spellID) and ns.db.spellElements[spellID]
	if own and ns.ELEMENTS[own] then return own end
	if type(name) == "string" and not issecretvalue(name) and GATHERING[name:lower()] then return GATHERING[name:lower()] end
	if isTradeskill then return ns.db.fallback end
	if type(name) == "string" and not issecretvalue(name) then
		local lower = name:lower()
		if NAMES[lower] then return NAMES[lower] end
		lower = lower .. " "
		for _, w in ipairs(WORDS) do
			if lower:find(w[1], 1, true) then return w[2] end
		end
	end
	return ClassElement() or ns.db.fallback
end
