-- daves_frames / Frame.lua
-- Builds the target frame: the layers in NOTES.md section 2, from the back:
--   boards (behind the plate) < bars (clipped to the windows) < inset shadow and portrait < frame art
--   < text and numbers.
-- Nothing here reads unit data; Unit.lua, Cast.lua and Auras.lua fill it in.

local _, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Positions are layout px from the frame's top-left, y downward.
local function Rect(region, root, l, t, r, b)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", root, "TOPLEFT", l, -t)
	region:SetPoint("BOTTOMRIGHT", root, "TOPLEFT", r, -b)
end
ns.Rect = Rect

local function Color(c, a) return CreateColor(c[1], c[2], c[3], a or c[4] or 1) end
ns.Color = Color

-- A vertical three-stop look from two gradients would need two textures; light-to-dark top-to-bottom
-- with the mid colour in between reads the same at this size.
function ns.Paint(tex, shades, alpha)
	tex:SetTexture(WHITE)
	tex:SetGradient("VERTICAL", Color(shades[3], alpha), Color(shades[1], alpha))
end

-- The empty part of a bar: its own colour, mixed dark (never a blank gap).
function ns.PaintTrough(tex, shades)
	local m, d = shades[2], shades[3]
	tex:SetColorTexture(1, 1, 1, 1)
	tex:SetGradient("VERTICAL",
		CreateColor(d[1] * 0.38 + 0.024 * 0.62, d[2] * 0.38 + 0.02 * 0.62, d[3] * 0.38 + 0.016 * 0.62, 1),
		CreateColor(m[1] * 0.30 + 0.05 * 0.7, m[2] * 0.30 + 0.04 * 0.7, m[3] * 0.30 + 0.03 * 0.7, 1))
end

local function NewBar(parent, reverse)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(WHITE)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:SetReverseFill(reverse and true or false)
	return bar
end

local function Font(parent, layer, file, size, flags)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(file, size, flags or "OUTLINE")
	fs:SetShadowColor(0, 0, 0, 0.9)
	fs:SetShadowOffset(1, -1)
	fs:SetWordWrap(false)
	return fs
end
ns.Font = Font

-- n screen pixels in this frame's layout units (PixelUtil.lua: 768 / physical height per UI unit).
function ns.Px(n)
	local factor = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor() or 1
	local eff = ns.frame and ns.frame:GetEffectiveScale() or 1
	return n * factor / eff
end

-- All text uses Blizzard's own unit-frame text: TextStatusBarText, the font of the numbers on Blizzard's
-- target frame (Friz Quadrata, outlined, the right font for the client's language; GameFontStyles.xml).
local function BlizzardFont()
	local obj = TextStatusBarText or GameFontHighlightSmall
	local file, height, flags
	if obj then file, height, flags = obj:GetFont() end
	return file or "Fonts\\FRIZQT__.TTF", height or 10, flags or "OUTLINE"
end
ns.BlizzardFont = BlizzardFont

-- Blizzard's font, size and outline.
function ns.StyleFont(fs, _, size)
	local file, _, flags = BlizzardFont()
	-- A whole number of screen pixels tall: fractional sizes render soft.
	local px = ns.Px(1)
	size = math.max(1, math.floor(size / px + 0.5)) * px
	fs:SetFont(file, size, flags)
	fs:SetShadowColor(0, 0, 0, 0)
	fs.styled = { file = file, size = size, flags = flags }   -- ns.SetNameText picks another font at this size
	if fs.nameSet then ns.SetNameText(fs, fs.nameValue, fs.nameFmt) end   -- a name keeps its alphabet's font
end

-- Names in another alphabet: Friz Quadrata has no Chinese, Korean or Cyrillic letters, so they showed as boxes.
-- The name's letters pick Blizzard's font for that alphabet (Blizzard_Fonts_Shared/Mainline/Fonts.xml), at the
-- same size (Chinese a third larger, as Blizzard has it). UTF-8 lead bytes: Cyrillic D0-D3, kana and CJK E3-E9,
-- Hangul EA-ED. A secret name can't be read, so it keeps the frame's font.
local SCRIPTS = {
	{ "[\234-\237]", "Fonts\\2002.TTF", 1 },          -- Korean
	{ "[\227-\233]", "Fonts\\ARKai_T.ttf", 1.3 },      -- Chinese (and Japanese kana)
	{ "[\208-\211]", "Fonts\\FRIZQT___CYR.TTF", 1 },   -- Russian
}
function ns.SetNameText(fs, name, fmt)
	local s = fs.styled
	if s then
		local file, size = s.file, s.size
		if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
			for _, script in ipairs(SCRIPTS) do
				if name:find(script[1]) then file, size = script[2], s.size * script[3]; break end
			end
		end
		fs:SetFont(file, size, s.flags)
	end
	if fmt then fs:SetFormattedText(fmt, name) else fs:SetText(name) end
	fs.nameSet, fs.nameValue, fs.nameFmt = true, name, fmt
end

local NAME_FONT = "Fonts\\FRIZQT__.TTF"
local NUM_FONT = "Fonts\\ARIALN.TTF"
ns.NAME_FONT, ns.NUM_FONT = NAME_FONT, NUM_FONT

-- Inset over a window (NOTES.md section 4): a dark edge all round, a shadow under the top lip, lighter
-- shadows along the bottom and at each end.
local function Inset(frame, root, l, t, r, b, outerLeft)
	local function Edge(layer)
		local tex = frame:CreateTexture(nil, layer or "ARTWORK")
		tex:SetColorTexture(1, 1, 1, 1)
		return tex
	end
	local black, clear = CreateColor(0, 0, 0, 0.7), CreateColor(0, 0, 0, 0)
	local top = Edge(); Rect(top, root, l, t, r, t + 6); top:SetGradient("VERTICAL", clear, black)
	local bottom = Edge(); Rect(bottom, root, l, b - 4, r, b); bottom:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.45), clear)
	local endShade = Edge()
	if outerLeft then
		Rect(endShade, root, l, t, l + 6, b); endShade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.55), clear)
	else
		Rect(endShade, root, r - 6, t, r, b); endShade:SetGradient("HORIZONTAL", clear, CreateColor(0, 0, 0, 0.55))
	end
	for _, side in ipairs({ { l, t, r, t + 1.5 }, { l, b - 1.5, r, b } }) do
		local line = Edge("OVERLAY"); Rect(line, root, side[1], side[2], side[3], side[4]); line:SetColorTexture(0, 0, 0, 0.85)
	end
	local endLine = Edge("OVERLAY")
	if outerLeft then Rect(endLine, root, l, t, l + 1.5, b) else Rect(endLine, root, r - 1.5, t, r, b) end
	endLine:SetColorTexture(0, 0, 0, 0.85)
end

function ns:BuildFrame(variant)
	local L = ns.VARIANTS[variant]
	local S = ns.STD
	ns.L = L

	local f = CreateFrame("Frame", "DavesFramesTarget", UIParent)
	f:SetSize(L.w, L.h)
	f:SetFrameStrata("MEDIUM")
	f:SetFrameLevel(10)
	f:Hide()
	ns.frame = f
	local base = f:GetFrameLevel()

	-- Boards sit behind the plate (Auras.lua builds them on this layer).
	f.boardLayer = CreateFrame("Frame", nil, f)
	f.boardLayer:SetAllPoints()
	f.boardLayer:SetFrameLevel(base + 1)

	-- Bars, clipped to each window (run a few px under the rim; the ring hides the inner end).
	local cl, cr, ct, cb = L.winL - S.sideX, L.winR + S.sideX, L.winT - S.sideY, L.winB + S.sideY
	local function Clip(l, r)
		local c = CreateFrame("Frame", nil, f)
		c:SetFrameLevel(base + 2)
		Rect(c, f, l, ct, r, cb)
		c:SetClipsChildren(true)
		c.trough = c:CreateTexture(nil, "BACKGROUND")
		c.trough:SetAllPoints()
		return c
	end
	f.clipL = Clip(cl, L.cx)
	f.clipR = Clip(L.cx, cr)

	-- Left: health and what hangs off its moving end (heal, then shield), all filling outward.
	local hl, hr = cl, L.cx - L.hidden
	f.trail = NewBar(f.clipL, true)
	f.health = NewBar(f.clipL, true)
	f.heal = NewBar(f.clipL, true)
	f.absorb = NewBar(f.clipL, true)
	f.trail:SetStatusBarColor(1, 0.95, 0.84, 0.85)
	f.heal:SetStatusBarColor(unpack(ns.COLORS.heal))
	f.absorb:SetStatusBarTexture(ns.STRIPES)
	local at = f.absorb:GetStatusBarTexture()
	at:SetHorizTile(true); at:SetVertTile(true)
	f.healthSpan = { hl, hr }

	-- Right: resource, with the cast over it.
	local pl, pr = L.cx + L.hidden, cr
	f.power = NewBar(f.clipR, false)
	f.cast = NewBar(f.clipR, false)
	f.cast:SetFrameLevel(f.power:GetFrameLevel() + 2)
	f.cast:Hide()
	f.powerSpan = { pl, pr }

	-- Inset over each window, and the portrait, both under the art.
	local overlay = CreateFrame("Frame", nil, f)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(base + 4)
	f.insetLayer = overlay
	local c = L.cut
	local dyMax = math.max(math.abs(c[3] - L.cy), math.abs(c[4] - L.cy))
	local ringEdge = math.sqrt((L.rOut - 3) ^ 2 - dyMax ^ 2) - 6
	Inset(overlay, f, c[1], c[3], L.cx - ringEdge, c[4], true)
	Inset(overlay, f, L.cx + ringEdge, c[3], c[2], c[4], false)

	local pr2 = L.rIn + S.portraitPad
	f.portraitBack = overlay:CreateTexture(nil, "BACKGROUND")
	Rect(f.portraitBack, f, L.cx - pr2, L.cy - pr2, L.cx + pr2, L.cy + pr2)
	f.portraitBack:SetColorTexture(1, 1, 1, 1)
	f.portraitBack:SetGradient("VERTICAL", CreateColor(0.03, 0.02, 0.015, 1), CreateColor(0.14, 0.11, 0.075, 1))
	f.portrait = overlay:CreateTexture(nil, "ARTWORK")
	f.portrait:SetAllPoints(f.portraitBack)
	local mask = overlay:CreateMaskTexture()
	mask:SetAllPoints(f.portraitBack)
	mask:SetAtlas("CircleMask")
	f.portraitBack:AddMaskTexture(mask)
	f.portrait:AddMaskTexture(mask)
	f.portraitMask = mask

	-- The frame art.
	local artLayer = CreateFrame("Frame", nil, f)
	artLayer:SetAllPoints()
	artLayer:SetFrameLevel(base + 6)
	f.art = artLayer:CreateTexture(nil, "ARTWORK")
	f.art:SetAllPoints()
	f.art:SetTexture(L.texture)
	f.art:SetTexCoord(unpack(L.art))

	-- Text over everything.
	local text = CreateFrame("Frame", nil, f)
	text:SetAllPoints()
	text:SetFrameLevel(base + 8)
	f.textLayer = text

	-- Portrait numbers on a soft dark band, clipped to the opening.
	f.numBand = text:CreateTexture(nil, "BACKGROUND")
	Rect(f.numBand, f, L.cx - L.rIn, L.cy - 34, L.cx + L.rIn, L.cy + 34)
	f.numBand:SetColorTexture(0, 0, 0, 0.62)
	local bandMask = text:CreateMaskTexture()
	Rect(bandMask, f, L.cx - L.rIn, L.cy - L.rIn, L.cx + L.rIn, L.cy + L.rIn)
	bandMask:SetAtlas("CircleMask")
	f.numBand:AddMaskTexture(bandMask)
	f.pnHealth = Font(text, "OVERLAY", NUM_FONT, 23)
	f.pnHealth:SetPoint("CENTER", f, "TOPLEFT", L.cx, -(L.cy - 12))
	f.pnPower = Font(text, "OVERLAY", NUM_FONT, 19)
	f.pnPower:SetPoint("CENTER", f, "TOPLEFT", L.cx, -(L.cy + 13))

	-- Name and level (left window), cast text and who they target (right window), bar numbers.
	-- Level: Blizzard's own level circle and number (Forever's TargetFrameTemplates.xml: LevelBackgroundCircle,
	-- atlas UI-HUD-UnitFrame-SmallCircle, and LevelText in WhiteLargeNumberFont, centred on it 0.5 low).
	f.levelBadge = text:CreateTexture(nil, "ARTWORK")
	f.levelBadge:SetAtlas(S.badge.atlas)
	f.level = Font(text, "OVERLAY", NUM_FONT, 16)
	f.name = Font(text, "OVERLAY", NAME_FONT, 21)
	f.name:SetJustifyH("LEFT")
	f.dead = Font(text, "OVERLAY", NAME_FONT, 21)
	f.dead:SetText(DEAD or "Dead")
	f.dead:SetTextColor(0.8, 0.8, 0.8)
	f.dead:Hide()

	f.numHealthValue = Font(text, "OVERLAY", NUM_FONT, 21)
	f.numHealthPct = Font(text, "OVERLAY", NUM_FONT, 21)
	f.numPowerPct = Font(text, "OVERLAY", NUM_FONT, 21)
	f.numPowerValue = Font(text, "OVERLAY", NUM_FONT, 21)

	f.castName = Font(text, "OVERLAY", NUM_FONT, 19)
	f.castName:SetJustifyH("LEFT")
	f.castTime = Font(text, "OVERLAY", NUM_FONT, 19)
	f.castLock = text:CreateTexture(nil, "OVERLAY")
	f.castLock:SetSize(15, 18)
	f.castLock:SetAtlas("ui-castingbar-shield")   -- Blizzard's own "can't be interrupted" shield (CastingBarFrame.xml)
	f.tot = Font(text, "OVERLAY", NUM_FONT, 15)
	f.tot:SetJustifyH("LEFT")

	ns:ApplyLayout()
	return f
end

-- Text scales with the frame, like the art: TEXT layout units for a full-size role (what Blizzard's target
-- frame numbers at 200% measured at Scale 0.9), times the role's share, capped (layout units) so it stays
-- inside where it sits. Fixed sizes, so text never changes the bars (the stacked strip stays put).
local TEXT = 44
local function Size(mult, cap)
	return math.max(4, math.min(cap, TEXT * mult))
end
ns.TextSize = Size

-- Places the bars and the window text for the current layout setting (overlay or stacked).
function ns:ApplyLayout()
	local f, L, S, db = ns.frame, ns.L, ns.STD, ns.db
	if not f then return end
	local stacked = ns.Stacked()
	local winH = L.winB - L.winT
	-- Text is centred on its digits and capitals, not its line box (which has room for descenders below),
	-- so it sits a little lower than the box centre; snapped to whole screen pixels.
	local px = ns.Px(1)
	-- Rounded to whole pixels. In Stacked it may round to zero (forcing one pushed its small text half a
	-- pixel low); Overlay keeps at least one, which is how it looked right.
	local function Snap(v) return math.floor(v / px + 0.5) * px end
	local function Y(mid, size)
		local nudge = Snap(size * 0.06)
		if not stacked and nudge < px then nudge = px end
		return -(mid + nudge)
	end
	-- Stacked: the name/cast strip on top, the bars below. The line between them is on a whole screen
	-- pixel, and each row's middle is taken from the edges you can see (the art's cut, L.cut) and snapped
	-- too, so a 12 px row centres its text exactly instead of half a pixel off.
	local strip = S.strip
	local split = Snap(L.winT + strip)
	local stripMid = Snap((L.cut[3] + split) / 2)
	local stackBarMid = Snap((split + L.cut[4]) / 2)
	local barH = stacked and (L.winB - split) or winH
	local top = L.winT - S.sideY
	local barTop = stacked and split or top
	local bottom = L.winB + S.sideY
	local hl, hr = f.healthSpan[1], f.healthSpan[2]
	local pl, pr = f.powerSpan[1], f.powerSpan[2]

	for _, bar in ipairs({ f.trail, f.health }) do Rect(bar, f, hl, barTop, hr, bottom) end
	-- Heal and shield start at the health's moving end and are as long as the health bar, so the
	-- same min/max gives the right size without any maths on the (secret) values.
	local width = hr - hl
	for i, bar in ipairs({ f.heal, f.absorb }) do
		local anchor = (i == 1) and f.health:GetStatusBarTexture() or f.heal:GetStatusBarTexture()
		bar:ClearAllPoints()
		bar:SetPoint("TOPRIGHT", anchor, "TOPLEFT")
		bar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT")
		bar:SetWidth(width)
	end
	Rect(f.power, f, pl, barTop, pr, bottom)
	if stacked then Rect(f.cast, f, pl, top, pr, split) else Rect(f.cast, f, pl, top, pr, bottom) end

	-- Level: Blizzard's level circle on the bottom middle of the portrait ring, until a variant paints its own
	-- (NOTES.md: L5 level badge), at the L5 guide's size so a painted badge replaces it exactly. It scales with
	-- the frame like the art; the number keeps Blizzard's proportion to the circle, so two digits always fit.
	local B = S.badge
	local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(B.atlas)
	local atlasW = (info and info.width and info.width > 0) and info.width or 30
	local d = B.d
	local u = d / atlasW                                              -- layout px per unit of Blizzard's circle
	local bx, by = Snap(L.cx), Snap(L.cy + B.dy)
	local bHalf = Snap(d / 2)
	Rect(f.levelBadge, f, bx - bHalf, by - bHalf, bx + bHalf, by + bHalf)
	local fontObj = WhiteLargeNumberFont or TextStatusBarText
	local file, height, flags = fontObj:GetFont()
	local levelSize = math.max(1, math.floor((height or 14) * u / px + 0.5)) * px
	f.level:ClearAllPoints(); f.level:SetPoint("CENTER", f, "TOPLEFT", bx, -Snap(by + 0.5 * u))   -- on a whole pixel: sharp digits
	f.level:SetJustifyH("CENTER"); f.level:SetJustifyV("MIDDLE")
	f.level:SetFont(file or (BlizzardFont()), levelSize, flags or "")
	f.level:SetShadowColor(0, 0, 0, 0)

	-- Name, from the outer end of the health window.
	local nameMid = stacked and stripMid or (L.winT + L.winB) / 2
	local nameSize = stacked and Size(1, strip - 6) or Size(1, 34)
	f.name:ClearAllPoints()
	f.name:SetPoint("LEFT", f, "TOPLEFT", L.winL + 16, Y(nameMid, nameSize))
	f.name:SetPoint("RIGHT", f, "TOPLEFT", L.cx - L.hidden - 60, Y(nameMid, nameSize))
	ns.StyleFont(f.name, ns.NAME_FONT, nameSize)

	local barMid = stacked and stackBarMid or (L.winT + L.winB) / 2
	-- Dead: in the right bar at its outer end, the mirror of the name in the left one (over the power numbers,
	-- which hide while it shows: ns:SetDead).
	ns.StyleFont(f.dead, ns.NAME_FONT, nameSize)
	f.dead:ClearAllPoints(); f.dead:SetPoint("RIGHT", f, "TOPLEFT", L.winR - 16, Y(barMid, nameSize))
	local numSize = Size(1, barH - 6)
	ns.barTextPx = numSize / px   -- ApplyNumbers moves the numbers to the portrait when this is too small
	local barY = Y(barMid, numSize)
	for _, fs in ipairs({ f.numHealthValue, f.numHealthPct, f.numPowerPct, f.numPowerValue }) do
		ns.StyleFont(fs, ns.NUM_FONT, numSize)
	end
	f.numHealthValue:ClearAllPoints(); f.numHealthValue:SetPoint("LEFT", f, "TOPLEFT", L.winL + 16, barY)
	f.numHealthPct:ClearAllPoints(); f.numHealthPct:SetPoint("RIGHT", f, "TOPLEFT", L.cx - L.hidden - 10, barY)
	f.numPowerPct:ClearAllPoints(); f.numPowerPct:SetPoint("LEFT", f, "TOPLEFT", L.cx + L.hidden + 10, barY)
	f.numPowerValue:ClearAllPoints(); f.numPowerValue:SetPoint("RIGHT", f, "TOPLEFT", L.winR - 16, barY)

	local castMid = stacked and stripMid or (L.winT + L.winB) / 2
	local size = stacked and Size(1, strip - 6) or Size(1, 34)
	f.castLock:SetSize(math.floor(size * 0.8 + 0.5), size)
	f.castLock:ClearAllPoints(); f.castLock:SetPoint("LEFT", f, "TOPLEFT", L.cx + L.hidden + 10, -castMid)
	f.castName:ClearAllPoints(); f.castName:SetPoint("LEFT", f, "TOPLEFT", L.cx + L.hidden + 14 + math.floor(size * 0.8 + 0.5), Y(castMid, size))
	f.castName:SetPoint("RIGHT", f, "TOPLEFT", L.winR - 16 - size * 3, Y(castMid, size))
	ns.StyleFont(f.castName, ns.NUM_FONT, size)
	f.castTime:ClearAllPoints(); f.castTime:SetPoint("RIGHT", f, "TOPLEFT", L.winR - 16, Y(castMid, size))
	ns.StyleFont(f.castTime, ns.NUM_FONT, size)
	local totSize = Size(1, strip - 6)
	ns.StyleFont(f.tot, ns.NUM_FONT, totSize)
	f.tot:ClearAllPoints(); f.tot:SetPoint("LEFT", f, "TOPLEFT", L.cx + L.hidden + 10, Y(stripMid, totSize))
	f.tot:SetPoint("RIGHT", f, "TOPLEFT", L.winR - 16, Y(stripMid, totSize))   -- long names end in "..."
	f.tot:SetShown(stacked and not f.cast:IsShown())   -- the cast takes the strip while it shows (Cast.lua)

	-- Numbers on the portrait: health over resource, centred, on a dark band that grows with them.
	-- "Both" ("12.3K  ·  100%", about 7.5 em in Friz Quadrata) is capped to the opening's width where
	-- the text sits.
	local cap = db.format == "both" and math.floor(2 * math.sqrt(L.rIn * L.rIn - 1225) / 7.5) or 42
	-- Health and resource are one size: the same as the numbers in the bars.
	local hs = Size(1, math.min(34, cap))
	local ps = hs
	-- The band covers at most about 40% of the opening.
	local half = math.min(math.floor(L.rIn * 0.4 + 0.5), math.max(34, math.floor((hs + ps) * 0.75 + 0.5)))
	Rect(f.numBand, f, L.cx - L.rIn, L.cy - half, L.cx + L.rIn, L.cy + half)
	ns.StyleFont(f.pnHealth, ns.NUM_FONT, hs)
	f.pnHealth:SetPoint("CENTER", f, "TOPLEFT", L.cx, -(L.cy - hs * 0.5))
	ns.StyleFont(f.pnPower, ns.NUM_FONT, ps)
	f.pnPower:SetPoint("CENTER", f, "TOPLEFT", L.cx, -(L.cy + ps * 0.5))

	ns:ApplyNumbers()
end

-- Which numbers show where (NOTES.md section 5). Numbers in the bars only exist in the stacked layout.
function ns:ApplyNumbers()
	local f, db = ns.frame, ns.db
	if not f then return end
	-- Numbers in the bars only come with Stacked. Not Stacked (by choice or because the Scale is too small),
	-- or too small to read in the bars (under 8 screen pixels): they show on the portrait instead, without
	-- changing the setting, and go back once they can.
	local numbers = db.numbers
	if numbers == "bars" and not ns.Stacked() then numbers = "portrait" end
	local forced = numbers == "bars" and (ns.barTextPx or 99) < 8   -- Stacked starts at Scale 0.85, where they are about 9 px at 1080p
	if forced then numbers = "portrait" end
	-- Record the state first, then refresh an open dialog when it changed: its note and the lit button.
	local changed = forced ~= ns.numbersForced or numbers ~= ns.numbersWhere
	ns.numbersForced, ns.numbersWhere = forced, numbers
	if changed and ns.editDialog and ns.editDialog:IsShown() then ns.editDialog:Refresh() end
	local onPortrait, inBars = numbers == "portrait", numbers == "bars"
	f.pnHealth:SetShown(onPortrait); f.pnPower:SetShown(onPortrait); f.numBand:SetShown(onPortrait)
	local showValue, showPct = db.format ~= "pct", db.format ~= "num"
	f.numHealthValue:SetShown(inBars and showValue); f.numPowerValue:SetShown(inBars and showValue)
	f.numHealthPct:SetShown(inBars and showPct); f.numPowerPct:SetShown(inBars and showPct)
	f.portrait:SetAlpha(db.portraitAlpha)
end

-- The portrait clicks like Blizzard's target frame: right-click opens the unit's menu, left-click targets it.
-- It's a secure button (SecureUnitButtonTemplate, "togglemenu": Blizzard_FrameXML/SecureTemplates.lua), so it
-- can't be a child of the frame, which shows and hides in combat: it sits on UIParent, the game shows it while
-- you have a target (RegisterUnitWatch), and it follows the portrait out of combat (ns:SyncPortraitButton).
function ns:BuildPortraitButton()
	local f = ns.frame
	local b = CreateFrame("Button", "DavesFramesTargetPortrait", UIParent, "SecureUnitButtonTemplate")
	b:SetFrameStrata(f:GetFrameStrata())
	b:SetFrameLevel(f:GetFrameLevel() + 20)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("unit", "target")
	b:SetAttribute("*type1", "target")
	b:SetAttribute("*type2", "togglemenu")
	b:Hide()
	f.portraitButton = b
	ns:SyncPortraitButton()
	ns:UpdatePortraitButton()
end

-- Sits the button on the portrait. Called every frame (the frame can be dragged, scaled or laid out);
-- only moves it when the portrait moved.
local lastX, lastY, lastSize
function ns:SyncPortraitButton()
	local f = ns.frame
	local b = f and f.portraitButton
	if not b or InCombatLockdown() then return end
	local x, y = f.portraitBack:GetCenter()
	if not x then return end
	local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	x, y = x * k, y * k
	local size = f.portraitBack:GetWidth() * k
	if x == lastX and y == lastY and size == lastSize then return end
	lastX, lastY, lastSize = x, y, size
	b:ClearAllPoints()
	b:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	b:SetSize(size, size)
end

-- On while the frame is on (the game shows it with the target); off in Edit Mode, so clicks there reach the
-- frame. Out of combat only: a change made in combat waits for PLAYER_REGEN_ENABLED.
local watching
function ns:UpdatePortraitButton()
	local b = ns.frame and ns.frame.portraitButton
	if not b then return end
	local want = ns.db.enabled and not ns.editing
	if want == watching then return end
	if InCombatLockdown() then
		ns.events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	watching = want
	if want then
		RegisterUnitWatch(b)
	else
		UnregisterUnitWatch(b)
		b:Hide()
	end
end

function ns:PLAYER_REGEN_ENABLED()
	ns.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	ns:UpdatePortraitButton()
end
