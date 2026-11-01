-- daves_frames / Layout.lua
-- Where everything sits, and the colours. All positions are layout pixels from the frame's top-left
-- corner (y grows downward here; Frame.lua flips it for SetPoint). One geometry for every unit.
-- The box is tools/template/frame-template.json, drawn by tools/Build-FrameTemplate.py.
-- guides/frame-template-ai.png is the 16:9 paint mask (2x). Media/frame-*.tga is that plate in the
-- top of the atlas.

local _, ns = ...

local MEDIA = "Interface\\AddOns\\daves_frames\\Media\\"
ns.MEDIA = MEDIA
ns.STRIPES = MEDIA .. "stripes.tga"
ns.CIRCLE = MEDIA .. "circle.tga"   -- full-bleed disc. Portrait mask and the level circle.

-- Shared standard (NOTES.md sections 3-6): the same for every variant.
ns.STD = {
	sideX = 5,          -- bars run this far under the rim at each end...
	sideY = 2,          -- ...and this far at the top and bottom
	strip = 30,         -- the name/cast strip in the stacked layout (layout px; the bars get the rest)
	portraitPad = 4,    -- the portrait is this much bigger than the opening, so it tucks under the ring
	chain = 36,         -- pivot to the board's top
	hook = 14,          -- chain hooks on this far above the pivot (hidden by the plate)
	slot = 40, slotGap = 10, rowGap = 6, timerGap = 5, timerH = 10,
	-- Hairline around the aura icons. border is layout px: about one screen pixel at Scale 1
	-- (real scale 0.5). A 1 px border disappears at that scale.
	plainPad = { top = 4, side = 3, bottom = 4, border = 2 },
	underGap = 6,       -- "right under the bar": gap below the plate
	-- Level placeholder. The painted border is the white ring on the template,
	-- on top of the portrait ring: outer diameter 92, band 16. dy is the middle
	-- of that ring at the bottom. d is the yellow hole the number sits in.
	badge = { dy = 116, d = 60 },
}
-- Half a one-aura board, so one aura hangs centred under the outer chain.
local auraPad = ns.STD.plainPad
local auraSide = auraPad.side + auraPad.border
ns.STD.chainTail = auraPad.top + auraPad.border   -- tucks under the top edge and stops before the icons
ns.STD.chainIn = (ns.STD.slot + ns.STD.slotGap + 2 * auraSide) / 2

-- Dim metal for the aura hairline. The plate's mid tone at full strength is the frame, not the boards.
function ns.BoardEdgeColor(L)
	local m = (L or ns.L).metal[2]
	return m[1] * 0.45, m[2] * 0.45, m[3] * 0.45, 0.85
end

-- The name is 44 layout px. Scale stops at 0.65 so that stays at least 14 screen px (see ns.MinSize).
-- Art slot: the 2x mask is 2048 x 600, the top of the 2048 x 1024 atlas (600/1024 = 0.585938).
-- The 600 x 220 board strip still sits 8 px below it (y 608..828). The aura boards do not sample it.
local GEO = {
	art = { 0, 1, 0, 0.585938 },
	strip = { 0, 0.292969, 0.59375, 0.808594 },
	stripPx = { w = 600, h = 220 },
	stripSlice = { top = 56, right = 56, bottom = 56, left = 56 },
	-- Packed 9-slice corner, in layout px. Build-FrameTemplate.py checks this line. Unused at runtime.
	board = { top = 28, right = 28, bottom = 28, left = 28 },
	w = 1024, h = 300,
	cx = 512, cy = 136, rIn = 105, rOut = 128,
	winL = 35, winR = 989, winT = 108, winB = 164,
	cut = { 35, 989, 108, 164 },
	hidden = 128,
	plateL = 8, plateR = 1016, plateT = 81, plateB = 191,
	pivotY = 189,
	laneL = { 16, 376 }, laneR = { 648, 1008 },
}

local function Variant(key, label, texture, chain, metal)
	local v = { key = key, label = label, texture = MEDIA .. texture, chain = MEDIA .. chain, metal = metal }
	for k, value in pairs(GEO) do v[k] = value end
	return v
end

local GOLD = { { 1.000, 0.910, 0.690 }, { 0.729, 0.486, 0.149 }, { 0.110, 0.063, 0.024 } }
local SILVER = { { 0.925, 0.949, 0.973 }, { 0.580, 0.627, 0.690 }, { 0.078, 0.094, 0.118 } }

-- Hairline colour from a class colour (light, mid, dark). Same shape as GOLD / SILVER.
local function Metal(r, g, b)
	return {
		{ r + (1 - r) * 0.45, g + (1 - g) * 0.45, b + (1 - b) * 0.45 },
		{ r, g, b },
		{ r * 0.35, g * 0.35, b * 0.35 },
	}
end

-- plain: ordinary NPCs. rare: silver, same shape. elite / rareelite / boss: the same shape.
-- Class keys are UnitClass's English file token, lowercased. Forever's nine classes each have a plate.
ns.VARIANT_ORDER = {
	"plain", "rare", "elite", "rareelite", "boss",
	"warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid",
}
ns.VARIANTS = {
	plain = Variant("plain", "Plain", "frame-plain.tga", "chain-gold.tga", GOLD),
	rare = Variant("rare", "Rare", "frame-rare.tga", "chain-silver.tga", SILVER),
	elite = Variant("elite", "Elite", "frame-elite.tga", "chain-gold.tga", GOLD),
	rareelite = Variant("rareelite", "Rare Elite", "frame-rareelite.tga", "chain-silver.tga", SILVER),
	boss = Variant("boss", "Boss", "frame-boss.tga", "chain-gold.tga", GOLD),
	warrior = Variant("warrior", "Warrior", "frame-warrior.tga", "chain-gold.tga", Metal(0.780, 0.612, 0.431)),
	paladin = Variant("paladin", "Paladin", "frame-paladin.tga", "chain-gold.tga", Metal(0.961, 0.549, 0.729)),
	hunter = Variant("hunter", "Hunter", "frame-hunter.tga", "chain-gold.tga", Metal(0.671, 0.831, 0.451)),
	rogue = Variant("rogue", "Rogue", "frame-rogue.tga", "chain-silver.tga", Metal(1.000, 0.961, 0.412)),
	priest = Variant("priest", "Priest", "frame-priest.tga", "chain-silver.tga", Metal(0.860, 0.840, 0.780)),
	shaman = Variant("shaman", "Shaman", "frame-shaman.tga", "chain-gold.tga", Metal(0.000, 0.439, 0.871)),
	mage = Variant("mage", "Mage", "frame-mage.tga", "chain-silver.tga", Metal(0.412, 0.800, 0.941)),
	warlock = Variant("warlock", "Warlock", "frame-warlock.tga", "chain-silver.tga", Metal(0.580, 0.510, 0.788)),
	druid = Variant("druid", "Druid", "frame-druid.tga", "chain-gold.tga", Metal(1.000, 0.490, 0.039)),
}

-- Colours: light, mid, dark (NOTES.md section 3).
ns.COLORS = {
	hostile = { { 1.00, 0.54, 0.46 }, { 0.82, 0.19, 0.12 }, { 0.37, 0.05, 0.02 } },
	neutral = { { 1.00, 0.94, 0.60 }, { 0.88, 0.71, 0.13 }, { 0.42, 0.31, 0.02 } },
	friendly = { { 0.55, 0.95, 0.55 }, { 0.20, 0.72, 0.25 }, { 0.05, 0.30, 0.08 } },
	tapped = { { 0.75, 0.75, 0.75 }, { 0.50, 0.50, 0.50 }, { 0.22, 0.22, 0.22 } },
	mana = { { 0.66, 0.78, 1.00 }, { 0.18, 0.44, 0.88 }, { 0.04, 0.15, 0.40 } },
	cast = { { 1.00, 0.89, 0.60 }, { 0.94, 0.63, 0.16 }, { 0.66, 0.35, 0.02 } },
	castLocked = { { 0.89, 0.90, 0.92 }, { 0.60, 0.64, 0.68 }, { 0.36, 0.39, 0.42 } },
	castDone = { 1.00, 0.84, 0.42 },
	castCut = { 0.75, 0.15, 0.10 },
	heal = { 0.45, 0.95, 0.50, 0.65 },
	-- Aura borders by type; physical (no type) uses "none".
	auraBorder = { Magic = { 0.24, 0.55, 1 }, Curse = { 0.61, 0.19, 1 }, Poison = { 0.2, 0.75, 0.2 },
		Disease = { 0.6, 0.4, 0 }, none = { 0.75, 0.15, 0.10 }, buff = { 0.55, 0.45, 0.25 } },
}

-- Three-stop bar colours from a class colour (light, mid, dark).
function ns.ShadesOf(r, g, b)
	return { { r + (1 - r) * 0.45, g + (1 - g) * 0.45, b + (1 - b) * 0.45 }, { r, g, b }, { r * 0.3, g * 0.3, b * 0.3 } }
end
