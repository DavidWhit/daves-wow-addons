-- daves_frames / Layout.lua
-- Where everything sits, per art variant, and the colours. All positions are layout pixels from the
-- frame's top-left corner (y grows downward here; Frame.lua flips it for SetPoint). See NOTES.md.

local _, ns = ...

local MEDIA = "Interface\\AddOns\\daves_frames\\Media\\"
ns.MEDIA = MEDIA
ns.STRIPES = MEDIA .. "stripes.tga"

-- Shared standard (NOTES.md sections 3-6): the same for every variant.
ns.STD = {
	sideX = 5,          -- bars run this far under the rim at each end...
	sideY = 2,          -- ...and this far at the top and bottom
	strip = 30,         -- the name/cast strip in the stacked layout (layout px; the bars get the rest)
	portraitPad = 4,    -- the portrait is this much bigger than the opening, so it tucks under the ring
	chain = 36,         -- pivot to the board's top
	hook = 14,          -- chain hooks on this far above the pivot (hidden by the plate)
	chainTail = 36,     -- chain carries on behind the board
	slot = 40, slotGap = 10, rowGap = 6, timerGap = 5, timerH = 10,
	boardPad = { top = 9, bottom = 6, side = 2 },
	board = { top = 30, right = 35, bottom = 31, left = 35 },   -- 9-slice border widths on screen
	plainPad = { top = 6, side = 6, bottom = 6, border = 2 },
	underGap = 6,       -- "right under the bar": gap below the plate
	-- Level circle (L5): Blizzard's atlas, centred this far below the ring centre, this many layout px across.
	-- Same numbers as the L5 paint guide (whose number area, radius 32, the code doesn't need).
	badge = { dy = 124, d = 80, atlas = "UI-HUD-UnitFrame-SmallCircle" },
}
ns.STD.chainIn = (ns.STD.slot + ns.STD.slotGap + ns.STD.board.left + ns.STD.board.right + 2 * ns.STD.boardPad.side) / 2

-- Gold elite v1: measured from the painting (gold-elite.jpg), built by tools\Make-FrameMedia.ps1.
-- Every target uses this one for now.
ns.VARIANTS = {
	gold = {
		texture = MEDIA .. "frame-gold.tga",
		chain = MEDIA .. "chain-gold.tga",
		art = { 0, 1, 0, 0.6875 },                        -- texcoords of the frame art in the atlas
		strip = { 0, 0.5, 712 / 1024, 985 / 1024 },        -- the board strip (1024 x 273 px)
		stripPx = { w = 1024, h = 273 },
		stripSlice = { top = 85, right = 99, bottom = 89, left = 99 },   -- 9-slice insets, atlas px
		w = 1198.5, h = 412,
		cx = 595.8, cy = 227.8, rIn = 105, rOut = 131,
		winL = 52, winR = 1142, winT = 190, winB = 248,
		cut = { 49, 1146, 189, 249 },                      -- the window as cut from the art (left, right, top, bottom)
		hidden = 122,                                      -- part of each bar under the ring
		plateL = 8, plateR = 1190, plateT = 151, plateB = 286,
		pivotY = 268,
		laneL = { 70, 430 }, laneR = { 810, 1130 },
		metal = { { 0.965, 0.863, 0.580 }, { 0.659, 0.478, 0.173 }, { 0.290, 0.196, 0.047 } },
	},
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
