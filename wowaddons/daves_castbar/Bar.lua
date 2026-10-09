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
-- Borderless style: three mask textures per frame (ragged top/bottom edge, soft left and right
-- ends) fade the bar out instead of ending in a box. A mask must live in the frame it masks.
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

local bar, track, clip, fx, textFrame, glowFrame, border
local contents = {}                -- [element] = content frame
local W, H = 300, 26

-- The track's layers at their scroll offsets, keeping the texture's proportions on any bar size.
local function TrackCoords()
	local span = W / (TEX_W * H / 64)
	track.tex:SetTexCoord(track.u, track.u + span, 0, 1)
	track.hi:SetTexCoord(track.u2, track.u2 + span, 0, 1)
end

---------------------------------------------------------------------------
-- Masks (borderless style)
---------------------------------------------------------------------------
local function CreateMasks(frame)
	local v = frame:CreateMaskTexture()
	v:SetAllPoints(bar)
	v:SetTexture(MEDIA .. "edge_v", "REPEAT", "CLAMPTOWHITE")
	local l = frame:CreateMaskTexture()
	l:SetPoint("LEFT", bar, "LEFT")
	l:SetTexture(MEDIA .. "edge_h", "CLAMPTOWHITE", "CLAMPTOWHITE")
	local r = frame:CreateMaskTexture()
	r:SetPoint("RIGHT", bar, "RIGHT")
	r:SetTexture(MEDIA .. "edge_h", "CLAMPTOWHITE", "CLAMPTOWHITE")
	r:SetTexCoord(1, 0, 0, 1)
	frame.masks = { v, l, r }
	frame.maskable = {}
	frame.masked = ns.db.borderless      -- textures added later follow this
end

local function LayoutMasks(frame)
	local v, l, r = frame.masks[1], frame.masks[2], frame.masks[3]
	v:SetTexCoord(0, W / (256 * H / 64), 0, 1)       -- keep the ragged edge's proportions on any width
	local cap = math.min(W / 3, H * 1.4)
	l:SetSize(cap, H); r:SetSize(cap, H)
end

local function SetMasked(frame, tex, on)
	for _, m in ipairs(frame.masks) do
		if on then tex:AddMaskTexture(m) else tex:RemoveMaskTexture(m) end
	end
end

-- Remember a texture as one the borderless masks apply to.
function ns.Maskable(frame, tex)
	frame.maskable[#frame.maskable + 1] = tex
	if frame.masked then SetMasked(frame, tex, true) end
	return tex
end

local function ApplyMasks(frame, on)
	if frame.masked == on then return end
	frame.masked = on
	for _, tex in ipairs(frame.maskable) do SetMasked(frame, tex, on) end
end

---------------------------------------------------------------------------
-- Element content: the layers that make an element's look
---------------------------------------------------------------------------
local function LayerTexture(content, name, blend, sublevel)
	local tex = content:CreateTexture(nil, "ARTWORK", nil, sublevel)
	tex:SetAllPoints(content)
	tex:SetTexture(MEDIA .. name, "REPEAT", "REPEAT")
	tex:SetBlendMode(blend)
	return ns.Maskable(content, tex)
end

local function GetContent(key)
	if contents[key] then return contents[key] end
	local cfg = ns.ELEMENTS[key]
	local content = CreateFrame("Frame", nil, clip)
	content:SetPoint("TOPLEFT", bar, "TOPLEFT")
	content:SetSize(W, H)
	content.key, content.cfg = key, cfg
	CreateMasks(content)

	local black = ns.Maskable(content, content:CreateTexture(nil, "BACKGROUND"))
	black:SetAllPoints(content)
	black:SetColorTexture(0, 0, 0, 1)

	content.layers = {}
	for i, L in ipairs(cfg.layers) do
		content.layers[i] = { cfg = L, tex = LayerTexture(content, L.tex, L.add and "ADD" or "BLEND", i - 1), u = 0, v = 0,
			wob = ns.Wobble(), speedWob = ns.Wobble(.7) }
	end
	content.veil = LayerTexture(content, "veil", "ADD", 6)
	content.veil:SetVertexColor(cfg.veil[1], cfg.veil[2], cfg.veil[3])

	local flash = ns.Maskable(content, content:CreateTexture(nil, "OVERLAY", nil, 7))
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
	LayoutMasks(content)
	ns.FX:LayoutContent(content, W, H)
end

---------------------------------------------------------------------------
-- Building the bar
---------------------------------------------------------------------------
local function EdgeTexture(parent, layer, sub)
	local t = parent:CreateTexture(nil, layer, nil, sub)
	t:SetColorTexture(1, 1, 1, 1)
	return t
end

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
	CreateMasks(track)
	track.bg = ns.Maskable(track, track:CreateTexture(nil, "BACKGROUND"))
	track.bg:SetAllPoints()
	track.bg:SetColorTexture(.024, .024, .04, 1)
	track.tex = ns.Maskable(track, track:CreateTexture(nil, "ARTWORK"))
	track.tex:SetAllPoints()
	track.tex:SetAlpha(.16)
	track.hi = ns.Maskable(track, track:CreateTexture(nil, "ARTWORK", nil, 1))   -- an element's own track can add a bright layer
	track.hi:SetAllPoints()
	track.hi:SetBlendMode("ADD")
	track.hi:Hide()

	clip = CreateFrame("Frame", nil, bar)
	clip:SetPoint("TOPLEFT"); clip:SetPoint("BOTTOMLEFT")
	clip:SetWidth(1)
	clip:SetClipsChildren(true)
	clip:SetFrameLevel(bar:GetFrameLevel() + 2)

	fx = CreateFrame("Frame", nil, bar)
	fx:SetAllPoints()
	fx:SetFrameLevel(bar:GetFrameLevel() + 6)
	ns.fxFrame = fx
	local spark = fx:CreateTexture(nil, "OVERLAY", nil, 6)
	spark:SetTexture(MEDIA .. "spark"); spark:SetBlendMode("ADD")
	fx.spark, fx.sparkWob = spark, ns.Wobble(6)

	-- framed style: a dark outline and a thin line in the element's colour
	border = CreateFrame("Frame", nil, bar)
	border:SetAllPoints()
	border:SetFrameLevel(bar:GetFrameLevel() + 7)
	border.dark, border.lit = {}, {}
	for i = 1, 4 do border.dark[i] = EdgeTexture(border, "BORDER", 0); border.lit[i] = EdgeTexture(border, "BORDER", 1) end
	for _, t in ipairs(border.dark) do t:SetVertexColor(0, 0, 0, .8) end
	local function Frame4(t, inset, size)
		t[1]:SetPoint("TOPLEFT", -inset, inset); t[1]:SetPoint("TOPRIGHT", inset, inset); t[1]:SetHeight(size)
		t[2]:SetPoint("BOTTOMLEFT", -inset, -inset); t[2]:SetPoint("BOTTOMRIGHT", inset, -inset); t[2]:SetHeight(size)
		t[3]:SetPoint("TOPLEFT", -inset, inset); t[3]:SetPoint("BOTTOMLEFT", -inset, -inset); t[3]:SetWidth(size)
		t[4]:SetPoint("TOPRIGHT", inset, inset); t[4]:SetPoint("BOTTOMRIGHT", inset, -inset); t[4]:SetWidth(size)
	end
	Frame4(border.dark, 2, 3)
	Frame4(border.lit, 1.5, 1.5)

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
	LayoutMasks(track)
	ApplyMasks(track, db.borderless)
	for _, content in pairs(contents) do
		LayoutContent(content)
		ApplyMasks(content, db.borderless)
	end
	track.bg:SetAlpha(db.borderless and .45 or .85)
	if track.u then TrackCoords() end
	border:SetShown(not db.borderless)

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
	ns.FX:Layout(W, H)
end

function ns:BarSize() return W, H end

-- An element's live effects can tint the track for one cast (skinning: the fur ahead is a different
-- pelt every time). tex tints the track's texture, hi its bright layer.
function ns.TintTrack(tex, hi)
	track.tex:SetVertexColor(tex[1], tex[2], tex[3])
	if hi then track.hi:SetVertexColor(hi[1], hi[2], hi[3]) end
end

-- A texture on the track (below the fill, ahead of the cast) that follows the borderless masks.
function ns.TrackTexture(sub) return ns.Maskable(track, track:CreateTexture(nil, "ARTWORK", nil, sub)) end

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
	ApplyMasks(content, ns.db.borderless)
	content:Show()
	local cfg = content.cfg

	-- every cast starts the layers somewhere new
	for _, layer in ipairs(content.layers) do
		layer.u, layer.v = rand(0, 1), layer.cfg.sv and rand(0, 1) or 0
		layer.tex:SetDesaturated(false)
		layer.tex:SetVertexColor(1, 1, 1)
	end
	content.veilU = rand(0, 1)
	content.flash:SetAlpha(0)

	-- the track: a dim copy of the element, or the element's own (water flowing ahead of frost, the pond, rails)
	local T = cfg.track
	track.cfg = T
	track.tex:SetTexture(MEDIA .. (T and T.tex or cfg.layers[1].tex), "REPEAT", "REPEAT")
	track.tex:SetAlpha(T and T.a or .16)
	track.hi:SetShown(T and T.hi ~= nil or false)
	if T and T.hi then track.hi:SetTexture(MEDIA .. T.hi, "REPEAT", "REPEAT") end
	track.u, track.u2 = rand(0, 1), rand(0, 1)
	TrackCoords()
	track.tex:SetVertexColor(1, 1, 1); track.hi:SetVertexColor(1, 1, 1)   -- FX:Begin may tint it (ns.TintTrack)
	track.tex:SetDesaturation(0); track.hi:SetDesaturation(0)             -- an interrupt greys it (TintInterrupted)
	for _, t in ipairs({ glowFrame.l, glowFrame.m, glowFrame.r }) do SetColor(t, cfg.glow) end
	SetColor(fx.spark, cfg.spark)
	for _, t in ipairs(border.lit) do SetColor(t, cfg.border) end

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

-- k = 0..1: from the element's own colours to grey-red.
local function TintInterrupted(k)
	for _, layer in ipairs(active.layers) do
		layer.tex:SetDesaturation(k)
		layer.tex:SetVertexColor(1, 1 - .55 * k, 1 - .55 * k)
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
	clip:SetWidth(math.max(.01, fillW))

	-- fades
	if cast.state == "done" then
		active.flash:SetAlpha(math.max(0, 1 - cast.t / .35) * .8)
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
