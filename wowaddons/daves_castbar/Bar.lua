-- daves_castbar / Bar.lua
-- The bar: textures, the fill, the casting states, and hiding Blizzard's cast bar.
--
-- Layout, back to front:
--   glow      soft light behind the filled part
--   track     the empty bar: dark, with a dim copy of the element's texture
--   clip      a frame as wide as the fill that clips its children; inside it, one "content" frame
--             per element, always the full bar size, holding that element's layers. So the art
--             is revealed by the fill instead of being stretched by it.
--   fx        spark, particles and live effects; not clipped, so they can spill past the edges
--   tools     (Effects.lua) things held in front of the bar, over its frame line: the skinning roll and knife
--   text      spell name, time, icon
-- Edges: framed or borderless (db.style); either way they are always clean - never frayed, ragged or torn (a
-- ragged-edge style was removed in 0.4.0); new looks keep their art inside the bar with clean edges.
-- Corners (db.corners): square, soft or rounded, by masks on every texture that reaches the edges (ns.MaskCorners).
-- Depth (db.depth): flat, or a bevel laid over the fill (light along the top, shade along the bottom, an inner shadow).
--
-- Cast times come from UnitCastingInfo/UnitChannelInfo("player"). They are only secret for
-- restricted units (SecretWhenUnitSpellCastRestricted, UnitDocumentation.lua), not for the player,
-- and Blizzard's own player cast bar does arithmetic on them; still, a secret value is never
-- compared or computed with here - the bar just stays hidden.

local _, ns = ...

local MEDIA = ns.MEDIA
local TEX_W = 512                  -- element layers are 512x64
local rand = function(a, b) return a + math.random() * (b - a) end

-- A smooth random signal (-1..1) from three sines with unrelated periods, so it never visibly loops.
function ns.Wobble(scale)
	scale = scale or 1
	local f1, f2, f3 = rand(.07, .12) * scale, rand(.17, .26) * scale, rand(.37, .53) * scale
	local p1, p2, p3 = rand(0, 6.283), rand(0, 6.283), rand(0, 6.283)
	return function(t)
		return math.sin(t * f1 * 6.283 + p1) * .5 + math.sin(t * f2 * 6.283 + p2) * .3 + math.sin(t * f3 * 6.283 + p3) * .2
	end
end
ns.rand = rand

local bar, track, clip, fx, textFrame, glowFrame, border, depth
local contents = {}                -- [element] = content frame
local W, H = 300, 26

---------------------------------------------------------------------------
-- Corners (db.corners): "square", "soft" (rounded by .18 bar heights, the look so far) or "rounded" (.36).
-- A mask on every texture that reaches the bar's edges rounds them: each frame holding such textures gets
-- two masks, the bar's left end square and its right one (mirrored), wrapped CLAMP so they change nothing
-- beyond their square. A hidden mask stops masking, so they are never hidden: square is an all-white mask.
-- A texture takes three masks at most (Blizzard's EncounterTimelineTrackView checks that); the looks' own
-- masks (the storm's glow, the spent velvet) make one each, so there is room for these two.
---------------------------------------------------------------------------
local CORNERS = { square = { r = 0, mask = "corner_square" }, soft = { r = .18, mask = "corner_soft" }, rounded = { r = .36, mask = "corner_rounded" } }
local cornerMasks = {}             -- every mask made, for Layout to size and retexture
local function CornerStyle() return CORNERS[ns.db and ns.db.corners] or CORNERS.soft end

local function CornerMasksFor(frame)
	if frame.cornerMasks then return frame.cornerMasks end
	local file = MEDIA .. CornerStyle().mask
	local m = {}
	for i = 1, 2 do
		local mask = frame:CreateMaskTexture()
		mask:SetTexture(file, "CLAMP", "CLAMP")
		mask.file = file
		mask:SetSnapToPixelGrid(false); mask:SetTexelSnappingBias(0)
		if i == 1 then mask:SetPoint("TOPLEFT", bar, "TOPLEFT")
		else mask:SetPoint("TOPRIGHT", bar, "TOPRIGHT"); mask:SetTexCoord(1, 0, 0, 1) end
		mask:SetSize(H, H)
		m[i] = mask
		cornerMasks[#cornerMasks + 1] = mask
	end
	frame.cornerMasks = m
	return m
end

-- Round a texture's corners where it meets the bar's edges (with the masks of the frame it belongs to).
function ns.MaskCorners(tex)
	local m = CornerMasksFor(tex:GetParent())
	tex:AddMaskTexture(m[1]); tex:AddMaskTexture(m[2])
	return tex
end

-- Every texture made on this frame from now on gets the corner masks (the track, each element's content).
function ns.MaskAllTextures(frame)
	local CreateTexture = frame.CreateTexture
	frame.CreateTexture = function(self, ...) return ns.MaskCorners(CreateTexture(self, ...)) end
end

-- The track's layers at their scroll offsets, keeping the texture's proportions on any bar size.
local function TrackCoords()
	if track.atlas then return end      -- an atlas (the plain look's Blizzard background) keeps its own coordinates
	local span = W / (TEX_W * H / 64)
	track.tex:SetTexCoord(track.u, track.u + span, 0, 1)
	track.hi:SetTexCoord(track.u2, track.u2 + span, 0, 1)
end

---------------------------------------------------------------------------
-- Element content: the layers that make an element's look
---------------------------------------------------------------------------
-- A fill layer scrolls by a fraction of a texel a frame (OnBarUpdate), so it must not snap its texels to the pixel
-- grid: snapped, it jumps a whole texel at a time (three screen pixels on a wide bar), a back-and-forth jitter that
-- the still sprites over it (arcane's rune circles) seemed to share. Smooth = Effects.lua's unsnapped texture.
local function LayerTexture(content, name, blend, sublevel)
	local tex = ns.SmoothTexture(content:CreateTexture(nil, "ARTWORK", nil, sublevel))
	tex:SetAllPoints(content)
	tex:SetTexture(MEDIA .. name, "REPEAT", "REPEAT")
	tex:SetBlendMode(blend)
	return tex
end

local function GetContent(key)
	if contents[key] then return contents[key] end
	local cfg = ns.ELEMENTS[key]
	local content = CreateFrame("Frame", nil, clip)
	content:SetPoint("TOPLEFT", bar, "TOPLEFT")
	content:SetSize(W, H)
	content.key, content.cfg = key, cfg
	ns.MaskAllTextures(content)   -- its art follows the corners

	local black = content:CreateTexture(nil, "BACKGROUND")
	black:SetAllPoints(content)
	black:SetColorTexture(0, 0, 0, 1)

	content.layers = {}
	for i, L in ipairs(cfg.layers) do
		content.layers[i] = { cfg = L, tex = LayerTexture(content, L.tex, L.add and "ADD" or "BLEND", i - 1), u = 0, v = 0,
			wob = ns.Wobble(), speedWob = ns.Wobble(.7) }
	end
	content.veil = LayerTexture(content, "veil", "ADD", 6)
	content.veil:SetVertexColor(cfg.veil[1], cfg.veil[2], cfg.veil[3])

	local flash = content:CreateTexture(nil, "OVERLAY", nil, 7)
	flash:SetAllPoints(content)
	flash:SetColorTexture(1, 1, 1, 1)
	flash:SetBlendMode("ADD")
	flash:SetVertexColor(cfg.spark[1], cfg.spark[2], cfg.spark[3])
	flash:SetAlpha(0)
	content.flash = flash

	ns.FX:CreateContent(content)          -- element-specific pieces (frost cuts, rune circles, ...)
	contents[key] = content
	content:Hide()
	return content
end

local function LayoutContent(content)
	content:SetSize(W, H)
	ns.FX:LayoutContent(content, W, H)
end

---------------------------------------------------------------------------
-- Building the bar
---------------------------------------------------------------------------
function ns:InitBar()
	bar = CreateFrame("Frame", "DavesCastbarFrame", UIParent)
	bar:SetFrameStrata("MEDIUM")
	bar:SetMovable(true)
	bar:SetResizable(true)
	bar:SetClampedToScreen(true)
	bar:Hide()
	ns.bar = bar

	glowFrame = CreateFrame("Frame", nil, bar)
	glowFrame:SetFrameLevel(bar:GetFrameLevel())
	glowFrame.l = glowFrame:CreateTexture(nil, "BACKGROUND")
	glowFrame.m = glowFrame:CreateTexture(nil, "BACKGROUND")
	glowFrame.r = glowFrame:CreateTexture(nil, "BACKGROUND")
	for _, t in ipairs({ glowFrame.l, glowFrame.m, glowFrame.r }) do
		t:SetTexture(MEDIA .. "glow"); t:SetBlendMode("ADD")
	end
	glowFrame.l:SetTexCoord(0, .5, 0, 1); glowFrame.m:SetTexCoord(.5, .5, 0, 1); glowFrame.r:SetTexCoord(.5, 1, 0, 1)
	glowFrame.l:SetPoint("TOPLEFT"); glowFrame.l:SetPoint("BOTTOMLEFT")
	glowFrame.r:SetPoint("TOPRIGHT"); glowFrame.r:SetPoint("BOTTOMRIGHT")
	glowFrame.m:SetPoint("TOPLEFT", glowFrame.l, "TOPRIGHT"); glowFrame.m:SetPoint("BOTTOMRIGHT", glowFrame.r, "BOTTOMLEFT")
	glowFrame.wob = ns.Wobble(1.5)

	track = CreateFrame("Frame", nil, bar)
	track:SetAllPoints()
	track:SetFrameLevel(bar:GetFrameLevel() + 1)
	ns.MaskAllTextures(track)
	track.bg = track:CreateTexture(nil, "BACKGROUND")
	track.bg:SetAllPoints()
	track.bg:SetColorTexture(.024, .024, .04, 1)
	track.bg:SetAlpha(.85)
	track.tex = ns.SmoothTexture(track:CreateTexture(nil, "ARTWORK"))   -- unsnapped: it scrolls (see LayerTexture)
	track.tex:SetAllPoints()
	track.tex:SetAlpha(.16)
	track.hi = ns.SmoothTexture(track:CreateTexture(nil, "ARTWORK", nil, 1))   -- an element's own track can add a bright layer
	track.hi:SetAllPoints()
	track.hi:SetBlendMode("ADD")
	track.hi:Hide()

	clip = CreateFrame("Frame", nil, bar)
	clip:SetPoint("TOPLEFT"); clip:SetPoint("BOTTOMLEFT")
	clip:SetWidth(1)
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(bar:GetFrameLevel() + 2)

	-- live effects (particles, sprites, the spark, vines, the pond, the mine cart): above the frame line (border, + 7),
	-- so embers, flakes, wisps, twinkles, the bobber and the cart overlap the frame when the bar is framed, on
	-- every look alike. Only the loom's tools are clipped to the bar (Effects_Tailor.lua), on purpose.
	fx = CreateFrame("Frame", nil, bar)
	fx:SetAllPoints()
	fx:SetFrameLevel(bar:GetFrameLevel() + 8)
	ns.fxFrame = fx
	local spark = fx:CreateTexture(nil, "OVERLAY", nil, 6)
	spark:SetTexture(MEDIA .. "spark"); spark:SetBlendMode("ADD")
	fx.spark, fx.sparkWob = spark, ns.Wobble(6)

	-- the frame: a dark outline and a thin line in the element's colour. Edges are clean - never frayed,
	-- ragged or torn (a ragged-edge style was removed in 0.4.0; don't bring one back for new looks)
	border = CreateFrame("Frame", nil, bar)
	border:SetAllPoints()
	border:SetFrameLevel(bar:GetFrameLevel() + 7)
	-- Three painted pieces per line (Make-CastbarMedia.ps1 CapRing / StripRing): a left cap, a strip stretched between
	-- the caps, the cap mirrored at the right; the strip is cut from the cap's straight part, so every pixel of the
	-- line has the same thickness and anti-aliasing round the whole bar, at every height and corner style (drawn
	-- straight lines met the painted caps with different pixels). All snap to the pixel grid: they don't move.
	border.capDark, border.capLit = {}, {}
	for i = 1, 2 do
		border.capDark[i] = border:CreateTexture(nil, "BORDER", nil, 0)
		border.capDark[i]:SetVertexColor(0, 0, 0, .8)
		border.capLit[i] = border:CreateTexture(nil, "BORDER", nil, 1)
		if i == 2 then border.capDark[i]:SetTexCoord(1, 0, 0, 1); border.capLit[i]:SetTexCoord(1, 0, 0, 1) end
	end
	border.stripDark = border:CreateTexture(nil, "BORDER", nil, 0)
	border.stripDark:SetVertexColor(0, 0, 0, .8)
	border.stripLit = border:CreateTexture(nil, "BORDER", nil, 1)
	border.pieces = { border.capDark[1], border.capDark[2], border.stripDark, border.capLit[1], border.capLit[2], border.stripLit }
	for _, t in ipairs(border.pieces) do t:SetSnapToPixelGrid(true) end
	-- the plain look's frame: Blizzard's own (CastingBarFrameBaseTemplate's Border, Mainline/CastingBarFrame.xml)
	border.blizz = border:CreateTexture(nil, "BORDER", nil, 2)
	border.blizz:SetAtlas("ui-castingbar-frame")
	border.blizz:SetPoint("TOPLEFT", -2, 2); border.blizz:SetPoint("BOTTOMRIGHT", 2, -2)
	border.blizz:Hide()

	-- depth: the bevel, laid over the fill and under the effects: light along the top, shade along the bottom
	-- and a shadow just inside the frame, all following the corners (LayoutShape sizes it, db.depth shows it)
	depth = CreateFrame("Frame", nil, bar)
	depth:SetAllPoints()
	depth:SetFrameLevel(bar:GetFrameLevel() + 5)
	ns.MaskAllTextures(depth)
	local function Bevel(sub, r, g, b, a, ...)
		local t = depth:CreateTexture(nil, "ARTWORK", nil, sub)
		t:SetTexture(MEDIA .. "bevel_v")   -- alpha 1 along its top fading to 0 at its bottom
		if select("#", ...) > 0 then t:SetTexCoord(...) end
		t:SetVertexColor(r, g, b, a)
		return t
	end
	depth.top = Bevel(1, 1, 1, 1, .28)
	depth.bottom = Bevel(1, 0, 0, 0, .5, 0, 1, 1, 0)
	depth.shadow = {
		Bevel(2, 0, 0, 0, .35),                               -- strongest at the top
		Bevel(2, 0, 0, 0, .35, 0, 1, 1, 0),                   -- at the bottom
		Bevel(2, 0, 0, 0, .35, 0, 0, 1, 0, 0, 1, 1, 1),       -- turned: strongest at the left
		Bevel(2, 0, 0, 0, .35, 0, 1, 1, 1, 0, 0, 1, 0),       -- at the right
	}
	depth:Hide()

	textFrame = CreateFrame("Frame", nil, bar)
	textFrame:SetAllPoints()
	textFrame:SetFrameLevel(bar:GetFrameLevel() + 9)   -- above the tools held in front of the bar (Effects.lua, + 8)
	local name = textFrame:CreateFontString(nil, "OVERLAY")
	name:SetJustifyH("LEFT"); name:SetWordWrap(false)
	name:SetShadowOffset(1, -1); name:SetShadowColor(0, 0, 0, 1)
	local time = textFrame:CreateFontString(nil, "OVERLAY")
	time:SetJustifyH("RIGHT"); time:SetWordWrap(false)
	time:SetShadowOffset(1, -1); time:SetShadowColor(0, 0, 0, 1)
	local icon = textFrame:CreateTexture(nil, "OVERLAY")
	icon:SetTexCoord(.08, .92, .08, .92)
	textFrame.name, textFrame.time, textFrame.icon = name, time, icon

	ns.FX:Init(fx)

	local events = CreateFrame("Frame")
	for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
		"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
		"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP" }) do
		events:RegisterUnitEvent(e, "player")
	end
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function(_, event, ...) ns:OnCastEvent(event, ...) end)

	bar:SetScript("OnUpdate", function(_, elapsed) ns:OnBarUpdate(elapsed) end)
end

---------------------------------------------------------------------------
-- Layout: size, style, text
---------------------------------------------------------------------------
local JUSTIFY = { left = "LEFT", center = "CENTER", right = "RIGHT" }

-- Spell name and time left: size (textScale), contrast outline (textOutline) and placement
-- (namePos, timePos: "left", "center" or "right").
-- Size: Text size is relative to a baseline bar (the default BASE_W x BASE_H, where 100% is
-- BASE_TEXT). On any other bar the text scales by whichever of width and height shrank more, so
-- it keeps its proportions to the bar and never grows past it (TEXT_MAX_H of its height at most).
-- Sections: the time and the name each get their own section of the bar and never share one.
-- The time's is as wide as its widest reading; the name's is the rest, and a name too long for
-- it ends in "...". A centred name keeps a time-sized gap on both sides, so it stays centred on
-- the bar; with the time centred as well, the time moves to the right end to make room.
local BASE_W, BASE_H, BASE_TEXT, TEXT_MAX_H = 300, 26, 12, .78

local function SetTextFont(size)
	local db = ns.db
	local flags = db.textOutline and "OUTLINE" or ""
	for _, fs in ipairs({ textFrame.name, textFrame.time }) do
		fs:SetFont("Fonts\\FRIZQT__.TTF", size, flags)
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, db.textOutline and .9 or 1)
	end
end

-- the widest the time reads (no cast lasts 100 seconds)
local function TimeWidth(time)
	local shown = time:GetText()
	time:SetText("88.8")
	local w = time:GetStringWidth()
	time:SetText(shown or "")
	return math.ceil(w) + 2
end

local function LayoutText()
	local db = ns.db
	local name, time = textFrame.name, textFrame.time
	local pad = math.min(H * .4, W * .06)
	local fit = math.min(H / BASE_H, W / BASE_W)
	local maxSize = math.floor(H * TEXT_MAX_H) - (db.textOutline and 2 or 0)   -- room for the outline and shadow
	local size = math.max(6, math.min(math.floor(BASE_TEXT * db.textScale * fit + .5), maxSize))
	SetTextFont(size)
	local namePos = JUSTIFY[db.namePos] and db.namePos or "left"
	local timePos = JUSTIFY[db.timePos] and db.timePos or "right"
	local showTime, showName = db.showTime, db.showName
	if showTime and showName and timePos == "center" and namePos == "center" then timePos = "right" end

	local tw = showTime and TimeWidth(time) or 0
	time:ClearAllPoints()
	time:SetWidth(tw)
	time:SetJustifyH(JUSTIFY[timePos])
	if timePos == "left" then time:SetPoint("LEFT", pad, 0)
	elseif timePos == "center" then time:SetPoint("CENTER")
	else time:SetPoint("RIGHT", -pad, 0) end

	-- the name's section, in offsets from the bar's left edge
	local l, r = pad, W - pad
	if showTime then
		local gap = tw + math.max(3, size * .5)
		if namePos == "center" and timePos ~= "center" then l, r = pad + gap, W - pad - gap
		elseif timePos == "left" then l = pad + gap
		elseif timePos == "right" then r = W - pad - gap
		elseif namePos == "right" then l = W / 2 + gap - tw / 2
		else r = W / 2 - gap + tw / 2 end
	end
	name:ClearAllPoints()
	name:SetPoint("LEFT", bar, "LEFT", l, 0)
	name:SetPoint("RIGHT", bar, "LEFT", math.max(r, l + 1), 0)
	name:SetJustifyH(JUSTIFY[namePos])
	name:SetShown(showName and r - l >= size)   -- no room for even a letter and "...": leave the time alone
	time:SetShown(showTime)
end

-- The frame line (db.style): "framed" draws our two-line frame (for the plain look Blizzard's own cast bar
-- frame); "borderless" draws none, leaving the bar's own clean shape. Never a frayed edge. With rounded corners
-- the end caps stand in for the left and right lines.
local function ShowBorder(cfg)
	local framed = ns.db.style ~= "borderless"
	local blizz = cfg and cfg.plain and true or false
	local ours = framed and not blizz
	border.blizz:SetShown(framed and blizz)
	for _, t in ipairs(border.pieces) do t:SetShown(ours) end
end

-- The bar's shape: the corner masks sized to the bar and switched to the corners setting; the frame lines, whose
-- thickness scales with the bar (the dark line .1 of its height with 2/3 of that outside the bar, the lit line
-- half as thick, inside it and ending at the edge), with the painted caps at both ends when the corners are
-- rounded; and the bevel.
local function LayoutShape()
	local db = ns.db
	local style = CornerStyle()
	local file = MEDIA .. style.mask
	for _, mask in ipairs(cornerMasks) do
		mask:SetSize(H, H)
		if mask.file ~= file then mask.file = file; mask:SetTexture(file, "CLAMP", "CLAMP") end
	end
	-- the frame: the dark line .1 H thick with 2/3 of it outside the bar, so its pieces are squares of H + 2e at both
	-- ends and a strip of that height between them (the painted pieces hold both lines' thickness and corners)
	local e = H * .1 * 2 / 3
	local capS = H + 2 * e
	local key = style.r > .2 and "rounded" or style.r > 0 and "soft" or "square"
	for i = 1, 2 do
		local cd, cl = border.capDark[i], border.capLit[i]
		cd:SetTexture(MEDIA .. "cap_dark_" .. key); cl:SetTexture(MEDIA .. "cap_lit_" .. key)
		cd:ClearAllPoints(); cl:ClearAllPoints()
		if i == 1 then cd:SetPoint("TOPLEFT", -e, e); cl:SetPoint("TOPLEFT", -e, e)
		else cd:SetPoint("TOPRIGHT", e, e); cl:SetPoint("TOPRIGHT", e, e) end
		cd:SetSize(capS, capS); cl:SetSize(capS, capS)
	end
	for _, sd in ipairs({ { border.stripDark, "strip_dark_" }, { border.stripLit, "strip_lit_" } }) do
		local t = sd[1]
		t:SetTexture(MEDIA .. sd[2] .. key)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", -e + capS, e); t:SetPoint("BOTTOMRIGHT", e - capS, -e)
	end
	local bevel = db.depth == "bevel"
	depth:SetShown(bevel)
	if bevel then
		local function Strip(t, top, size)
			t:ClearAllPoints()
			if top == "left" then t:SetPoint("TOPLEFT"); t:SetPoint("BOTTOMLEFT"); t:SetWidth(size)
			elseif top == "right" then t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(size)
			elseif top then t:SetPoint("TOPLEFT"); t:SetPoint("TOPRIGHT"); t:SetHeight(size)
			else t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(size) end
		end
		Strip(depth.top, true, H * .35)
		Strip(depth.bottom, false, H * .4)
		local s = H * .12
		Strip(depth.shadow[1], true, s); Strip(depth.shadow[2], false, s)
		Strip(depth.shadow[3], "left", s); Strip(depth.shadow[4], "right", s)
	end
end

function ns:Layout()
	local db = ns.db
	db.width = math.max(ns.MIN_W, math.min(ns.MAX_W, math.floor(db.width + .5)))      -- older saves may be smaller
	db.height = math.max(ns.MIN_H, math.min(ns.MAX_H, math.floor(db.height + .5)))
	W, H = db.width, db.height
	bar:SetSize(W, H)
	if bar:GetScale() ~= db.scale then
		-- keep the bar's centre where it is on screen: offsets are in the bar's own scale
		local x, y = bar:GetCenter()
		local old = bar:GetEffectiveScale()
		bar:SetScale(db.scale)
		if x then
			local new = bar:GetEffectiveScale()
			bar:ClearAllPoints()
			bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * old / new, y * old / new)
			ns:SavePosition()
		end
	end
	for _, content in pairs(contents) do LayoutContent(content) end
	if track.u then TrackCoords() end

	local glowH = H * 2.2
	glowFrame:SetHeight(glowH)
	glowFrame:ClearAllPoints()
	glowFrame:SetPoint("LEFT", bar, "LEFT", -H * .55, 0)
	glowFrame.l:SetWidth(glowH / 2); glowFrame.r:SetWidth(glowH / 2)
	fx.spark:SetSize(H * .9, H * 1.7)

	LayoutText()
	textFrame.icon:SetSize(H, H)
	textFrame.icon:ClearAllPoints(); textFrame.icon:SetPoint("RIGHT", bar, "LEFT", -4, 0)
	textFrame.icon:SetShown(db.showIcon)
	LayoutShape()
	ShowBorder(ns.activeCfg)
	ns.FX:Layout(W, H)
end

function ns:BarSize() return W, H end

-- An element's live effects can tint the track for one cast (skinning: the fur ahead is a different
-- pelt every time). tex tints the track's texture, hi its bright layer.
function ns.TintTrack(tex, hi)
	track.tex:SetVertexColor(tex[1], tex[2], tex[3])
	if hi then track.hi:SetVertexColor(hi[1], hi[2], hi[3]) end
end

-- A texture on the track (below the fill, ahead of the cast).
function ns.TrackTexture(sub) return track:CreateTexture(nil, "ARTWORK", nil, sub) end

---------------------------------------------------------------------------
-- Showing an element
---------------------------------------------------------------------------
local active             -- the content frame being shown
local cast = {}          -- the cast being shown: element, start, finish, channel, ...

local function SetColor(t, c, a) t:SetVertexColor(c[1], c[2], c[3], a or 1) end

local function ActivateElement(key)
	local content = GetContent(key)
	if active and active ~= content then active:Hide() end
	active = content
	LayoutContent(content)
	content:Show()
	local cfg = content.cfg

	-- every cast starts the layers somewhere new
	for _, layer in ipairs(content.layers) do
		layer.u, layer.v = rand(0, 1), layer.cfg.sv and rand(0, 1) or 0
		layer.tex:SetDesaturated(false)
		layer.tex:SetVertexColor(1, 1, 1)
		layer.tint = nil   -- the look may tint it for this cast (ns.TintLayer); an interrupt greys from that
	end
	content.veilU = rand(0, 1)
	content.flash:SetAlpha(0)

	-- the track: a dim copy of the element, or the element's own (water flowing ahead of frost, the pond, rails)
	local T = cfg.track
	track.cfg = T
	track.atlas = T and T.atlas
	if track.atlas then
		track.tex:SetAtlas(T.atlas)
		track.tex:SetAlpha(1)
	else
		track.tex:SetTexture(MEDIA .. (T and T.tex or cfg.layers[1].tex), "REPEAT", "REPEAT")
		track.tex:SetAlpha(T and T.a or .16)
	end
	track.hi:SetShown(T and T.hi ~= nil or false)
	if T and T.hi then track.hi:SetTexture(MEDIA .. T.hi, "REPEAT", "REPEAT") end
	track.u, track.u2 = rand(0, 1), rand(0, 1)
	TrackCoords()
	track.tex:SetVertexColor(1, 1, 1); track.hi:SetVertexColor(1, 1, 1)   -- FX:Begin may tint it (ns.TintTrack)
	track.tex:SetDesaturation(0); track.hi:SetDesaturation(0)             -- an interrupt greys it (TintInterrupted)
	for _, t in ipairs({ glowFrame.l, glowFrame.m, glowFrame.r }) do SetColor(t, cfg.glow) end
	-- the leading-edge flare, in the look's colour; the plain look has it too (gold, green for channels) rather than
	-- Blizzard's thin pip, which read as a bare vertical bar next to the other looks
	fx.spark:SetTexture(MEDIA .. "spark")
	fx.spark:SetBlendMode("ADD")
	fx.spark:SetSize(H * .9, H * 1.7)
	SetColor(fx.spark, cfg.spark)
	for _, t in ipairs(border.capLit) do SetColor(t, cfg.border) end
	SetColor(border.stripLit, cfg.border)
	ns.activeCfg = cfg
	ShowBorder(cfg)

	ns.FX:Begin(content, W, H)
	return content
end

---------------------------------------------------------------------------
-- Casting
---------------------------------------------------------------------------
local function Now() return GetTime() end

-- kind: "cast" fills, "channel" drains, "empower" fills (and holds at the last stage).
local function ReadCast(kind)
	local name, text, texture, startMs, endMs, isTradeskill, castID, spellID, stages
	if kind == "cast" then
		name, text, texture, startMs, endMs, isTradeskill, castID, _, spellID = UnitCastingInfo("player")
	else
		name, text, texture, startMs, endMs, isTradeskill, _, spellID, _, stages = UnitChannelInfo("player")
	end
	if not name then return end
	if issecretvalue(startMs) or issecretvalue(endMs) then return end   -- never do maths on secrets
	if castID and issecretvalue(castID) then castID = nil end             -- can't be matched; the safety stop ends it
	local finish = endMs / 1000
	if kind == "empower" and stages and stages > 0 then
		-- Blizzard adds the hold-at-max time the same way (CastingBarFrame.lua, forever branch)
		local hold = GetUnitEmpowerHoldAtMaxTime and GetUnitEmpowerHoldAtMaxTime("player")
		if hold and not issecretvalue(hold) then finish = finish + hold / 1000 end
	end
	return name, text, texture, startMs / 1000, finish, isTradeskill, castID, spellID
end

local function ShowText(label, icon)
	cast.label = label   -- may be secret: only ever handed to SetText/SetFormattedText
	textFrame.name:SetText(label or "")
	if icon then textFrame.icon:SetTexture(icon) end
end

function ns:StartCast(kind)
	if not ns.db.enabled then return end
	local name, text, texture, start, finish, isTradeskill, castID, spellID = ReadCast(kind)
	if not name then return end
	local key = ns:ResolveElement(spellID, name, isTradeskill)
	if kind == "channel" and ns.ELEMENTS[key].channelLook then key = ns.ELEMENTS[key].channelLook end   -- e.g. frost freezes the other way
	cast.kind, cast.channel = kind, kind == "channel"
	cast.start, cast.finish, cast.castID, cast.test, cast.loop = start, finish, castID, nil, nil
	cast.state, cast.t, cast.shown, cast.easeT = "cast", 0, nil, nil
	if spellID and not issecretvalue(spellID) then ns.lastSpell = { id = spellID, name = name } end
	ActivateElement(key)
	ShowText((text and not issecretvalue(text) and text ~= "" and text) or name, texture)
	bar:SetAlpha(1)
	bar:Show()
end

-- Pushback and channel updates move the fill. It glides from where it was shown to the new
-- spot over EASE seconds instead of jumping (OnBarUpdate).
local EASE = .25
local INTERRUPT_FADE = .25   -- the interrupted tint fades in over this long

local function Refresh(kind)
	if cast.state ~= "cast" or cast.test then return end
	local name, _, _, start, finish = ReadCast(kind)
	if name then
		cast.start, cast.finish = start, finish
		if cast.shown then cast.easeFrom, cast.easeT = cast.shown, 0 end
	end
end

local function Progress()
	return math.min(1, math.max(0, (Now() - cast.start) / math.max(.001, cast.finish - cast.start)))
end

local function Finish(how)   -- "done" (flash and fade) or "interrupted"
	if cast.state ~= "cast" then return end
	cast.finishedAt = cast.channel and Progress() or 1   -- a channel ends where it stopped draining
	if how == "interrupted" then cast.finishedAt = Progress() end
	cast.state, cast.t = how, 0
	if how == "interrupted" then ShowText(INTERRUPTED or "Interrupted") end   -- the tint fades in (OnBarUpdate)
end

-- A look tints one of its layers for this cast (the cloth, the velvet, the storm's sky): remembered, so the
-- interrupted tint greys that colour instead of replacing it.
local WHITE = { 1, 1, 1 }
function ns.TintLayer(content, i, r, g, b)
	local L = content.layers[i]
	L.tint = { r, g, b }
	L.tex:SetVertexColor(r, g, b)
end

-- k = 0..1: from the element's own colours (or the cast's tint) to grey-red.
local function TintInterrupted(k)
	for _, layer in ipairs(active.layers) do
		local t = layer.tint or WHITE
		layer.tex:SetDesaturation(k)
		layer.tex:SetVertexColor(t[1], t[2] * (1 - .55 * k), t[3] * (1 - .55 * k))
	end
	-- looks that fill the bar with more than their layers (skinning's fur ahead, roll and pool) grey too
	track.tex:SetDesaturation(k); track.hi:SetDesaturation(k)
	ns.FX:Interrupted(k)
end

-- Cast GUIDs can be secret for spells flagged that way, so they are only compared when neither is.
local function SameCast(castID)
	if castID == nil or cast.castID == nil or cast.kind ~= "cast" then return false end
	if issecretvalue(castID) or issecretvalue(cast.castID) then return false end
	return castID == cast.castID
end

-- Stopped well before its scheduled end.
local function EndedEarly() return Now() < cast.finish - .25 end

-- interruptedBy from a STOP event. Blizzard's bar treats nil as "finished" (CastingBarFrame.lua).
-- In combat and other restricted moments the payload is secret (SecretWhenUnitSpellCastRestricted)
-- and can't be read. A channel that finished normally then looked interrupted. A secret is judged
-- by timing instead: stopping near the scheduled end means it finished.
local function Interrupted(by)
	if issecretvalue(by) then return EndedEarly() end
	return by ~= nil and by ~= ""
end

-- Payloads (CastingBarFrame.lua, forever branch): most UNIT_SPELLCAST_* are (unit, castGUID, spellID, ...);
-- CHANNEL_STOP is (unit, castGUID, spellID, interruptedBy, castBarID);
-- EMPOWER_STOP is (unit, castGUID, spellID, complete, interruptedBy, castBarID).
function ns:OnCastEvent(event, _, castID, _, arg4, arg5)
	if event == "UNIT_SPELLCAST_START" then ns:StartCast("cast")
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then ns:StartCast("channel")
	elseif event == "UNIT_SPELLCAST_EMPOWER_START" then ns:StartCast("empower")
	elseif event == "UNIT_SPELLCAST_DELAYED" then Refresh("cast")
	elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then Refresh("channel")
	elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then Refresh("empower")
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_STOP" then
		if SameCast(castID) then Finish("done") end
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		if SameCast(castID) then Finish("interrupted") end
	elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if cast.kind == "channel" then Finish(Interrupted(arg4) and "interrupted" or "done") end
	elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
		if cast.kind == "empower" then
			local complete
			if issecretvalue(arg4) then complete = not EndedEarly() else complete = arg4 end
			Finish((complete and not Interrupted(arg5)) and "done" or "interrupted")
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if UnitCastingInfo("player") then ns:StartCast("cast")
		elseif UnitChannelInfo("player") then ns:StartCast("channel")
		elseif cast.state == "cast" and not cast.test then Finish("done") end   -- a stop we missed during loading
	end
end

-- A pretend cast, for /castbar test and while Edit Mode is open.
function ns:TestCast(key, loop)
	if not key then
		ns.testIndex = (ns.testIndex or 0) % #ns.ELEMENT_ORDER + 1
		key = ns.ELEMENT_ORDER[ns.testIndex]
	end
	local cfg = ns.ELEMENTS[key]
	local now = Now()
	-- a look whose real spell is a channel (Fishing) previews as one, draining instead of filling
	cast.kind, cast.channel = cfg.channel and "channel" or "cast", cfg.channel or false
	cast.start, cast.finish, cast.castID = now, now + 2.6, nil
	cast.state, cast.t, cast.test, cast.loop, cast.shown, cast.easeT = "cast", 0, true, loop, nil, nil
	ActivateElement(key)
	ShowText(cfg.label .. " test", "Interface\\Icons\\INV_Misc_QuestionMark")
	bar:SetAlpha(1)
	bar:Show()
end

function ns:StopTest()
	if cast.test then
		cast.state, cast.test = "idle", nil
		ns.FX:End()
	end
	ns:UpdateVisibility()
end
---------------------------------------------------------------------------
-- Every frame while the bar is shown
---------------------------------------------------------------------------
local clock = 0

function ns:OnBarUpdate(dt)
	clock = clock + dt
	local p
	if cast.state == "cast" then
		local now = Now()
		if cast.test and now >= cast.finish then Finish("done") end
		-- safety stop: a real cast well past its end that the game no longer reports
		if not cast.test and now > cast.finish + .5 and not UnitCastingInfo("player") and not UnitChannelInfo("player") then Finish("done") end
		p = Progress()
	elseif cast.state == "done" or cast.state == "interrupted" then
		p = cast.finishedAt
		cast.t = cast.t + dt
	else
		return
	end
	local f = cast.channel and (1 - p) or p
	if cast.easeT then   -- gliding after a pushback or channel update, toward the moving target
		cast.easeT = cast.easeT + dt
		local k = math.min(1, cast.easeT / EASE)
		k = k * k * (3 - 2 * k)
		f = cast.easeFrom + (f - cast.easeFrom) * k
		if k >= 1 then cast.easeT = nil end
	end
	cast.shown = f
	local fillW = W * f
	clip:SetWidth(active.cfg.wholeBar and W or math.max(.01, fillW))   -- alchemy: the liquid's level is the progress

	-- fades
	if cast.state == "done" then
		active.flash:SetAlpha(math.max(0, 1 - cast.t / .35) * (active.cfg.flashAlpha or .8))   -- the finishing flash; some looks keep it calm
		local a = cast.t < .4 and 1 or math.max(0, 1 - (cast.t - .4) / .5)
		bar:SetAlpha(a)
		if a <= 0 then return ns:EndCast() end
	elseif cast.state == "interrupted" then
		if cast.t - dt < INTERRUPT_FADE then TintInterrupted(math.min(1, cast.t / INTERRUPT_FADE)) end
		local a = cast.t < .7 and 1 or math.max(0, 1 - (cast.t - .7) / .5)
		bar:SetAlpha(a)
		if a <= 0 then return ns:EndCast() end
	end

	-- layers scroll at speeds that drift, so they never settle into a loop
	local k = H / 64
	local spanU = W / (TEX_W * k)
	for _, layer in ipairs(active.layers) do
		local L = layer.cfg
		local sm = 1 + .45 * layer.speedWob(clock)
		layer.u = (layer.u + (L.su or 0) * sm * dt) % 1
		layer.v = (layer.v + (L.sv or 0) * dt * (1 + .3 * layer.speedWob(clock + 9))) % 1
		layer.tex:SetTexCoord(layer.u, layer.u + spanU, layer.v, layer.v + 1)
		if L.a then
			local w = layer.wob(clock * (L.flicker and 6 or 1))
			layer.tex:SetAlpha(L.a[1] + (L.a[2] - L.a[1]) * (.5 + .5 * w))
		end
	end
	if track.cfg and (track.cfg.su or track.cfg.su2) then   -- water flowing ahead of the cast
		track.u = (track.u + (track.cfg.su or 0) * dt) % 1
		track.u2 = (track.u2 + (track.cfg.su2 or 0) * dt) % 1
		TrackCoords()
	end
	active.veilU = (active.veilU + .015 * dt) % 1
	active.veil:SetTexCoord(active.veilU, active.veilU + W / (512 * k), 0, 1)
	active.veil:SetAlpha(.35 + .2 * glowFrame.wob(clock + 3))

	-- glow behind the fill (anchored in Layout), and the spark on its leading edge
	glowFrame:SetWidth(math.max(H * 2.2, fillW + H * 1.1))
	glowFrame:SetAlpha(fillW > 1 and (.30 + .12 * glowFrame.wob(clock)) * 1.2 or 0)
	local sparkOn = cast.state == "cast" and p > 0 and p < 1 and not active.cfg.noSpark
	fx.spark:SetShown(sparkOn)
	if sparkOn then
		fx.spark:ClearAllPoints()
		fx.spark:SetPoint("CENTER", bar, "LEFT", fillW, 0)
		fx.spark:SetAlpha(.75 + .25 * fx.sparkWob(clock))
	end

	ns.FX:Update(dt, clock, fillW, cast.state == "cast", cast.state)

	if cast.state == "cast" and ns.db.showTime then
		local left = math.max(0, cast.finish - Now())
		textFrame.time:SetFormattedText("%.1f", left)
	elseif cast.state ~= "cast" then
		textFrame.time:SetText("")
	end
end

function ns:EndCast()
	cast.state, cast.test, cast.loop = "idle", nil, nil
	ns.FX:End()
	if ns.inEditMode then   -- keep previewing while Edit Mode is open, also after a real cast
		C_Timer.After(.4, function() if ns.inEditMode and cast.state == "idle" then ns:TestCast(ns.editPreview, true) end end)
	end
	ns:UpdateVisibility()
end

---------------------------------------------------------------------------
-- Visibility, position, Blizzard's cast bar
---------------------------------------------------------------------------
function ns:UpdateVisibility()
	local busy = cast.state == "cast" or cast.state == "done" or cast.state == "interrupted"
	bar:SetShown((ns.db.enabled and busy) or ns.inEditMode or not ns.db.locked)
	if not busy then
		bar:SetAlpha(1)
		clip:SetWidth(.01)
		fx.spark:Hide()
		glowFrame:SetAlpha(0)
		textFrame.name:SetText(ns.inEditMode and "Cast Bar" or "")
		textFrame.time:SetText("")
	end
end

-- Blizzard's player cast bar: muted by unregistering its events, never hidden from here. It is a
-- managed frame (BottomManagedFrameTemplate): a Hide() from addon code would run the bottom
-- layout container tainted, which also positions secure frames such as the extra action button.
-- Edit Mode still shows and positions it, since that is driven by isInEditMode, not events.
-- Turning the option off registers exactly what CastingBarMixin:SetUnit registers (forever branch).
local BLIZZ_EVENTS = { "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE",
	"UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED" }

function ns:ApplyBlizzardBar()
	local blizz = PlayerCastingBarFrame
	if not blizz then return end
	local mute = ns.db.enabled and ns.db.hideBlizzard
	if mute == (ns.blizzMuted or false) then return end
	if InCombatLockdown() then   -- change it once combat ends
		ns.events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if mute then
		blizz:UnregisterAllEvents()
	else
		for _, e in ipairs(BLIZZ_EVENTS) do blizz:RegisterUnitEvent(e, "player") end
		blizz:RegisterEvent("PLAYER_ENTERING_WORLD")
	end
	ns.blizzMuted = mute
end

function ns:PLAYER_REGEN_ENABLED()
	ns.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	ns:ApplyBlizzardBar()
end

function ns:Apply()
	ns:Layout()
	local db = ns.db
	bar:ClearAllPoints()
	bar:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x, db.y)
	ns:ApplyBlizzardBar()
	ns:ApplyEditState()
	ns:UpdateVisibility()
end
function ns:SavePosition()
	local point, _, relPoint, x, y = bar:GetPoint(1)
	ns.db.point, ns.db.relPoint, ns.db.x, ns.db.y = point, relPoint, x, y
end

function ns:ResetPosition()
	local db = ns.db
	db.point, db.relPoint, db.x, db.y = "BOTTOM", "BOTTOM", 0, 190
	db.width, db.height, db.scale = 300, 26, 1
	ns:Apply()
end

function ns:IsCasting() return cast.state == "cast" and not cast.test end
