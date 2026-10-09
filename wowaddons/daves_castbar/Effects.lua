-- daves_castbar / Effects.lua
-- Everything that moves on its own: the particles, the shared helpers, and the hooks Bar.lua calls. The looks
-- themselves live in the Effects_*.lua files (listed after this one in the TOC), one group each:
--   Effects_Spells     frost (the freeze front, the glint), nature and herbalism (vines), arcane (rune circles,
--                      glyphs), holy (twinkling stars)
--   Effects_Gathering  fishing (the pond, the bobber), mining (the cart, the pickaxe), skinning (the pelt roll)
--   Effects_Forge      blacksmithing (the hammer, the heat, the quench) and smelting (the ladle, the pour)
--   Effects_Storm      lightning (the painted clouds, the bolts)
--   Effects_Alchemy    the glassware bench and the trough that fills like a liquid
--   Effects_Tailor     the loom: shuttle, reed, the woven cloth
--   Effects_Leather    tooled leather panels laced shut by a needle
--   Effects_Ench       enchanting and disenchant: the velvet, the vortex, the dust
--   (plain, Blizzard's own cast bar art, is small and lives here)
-- Why several files: Lua 5.1 allows 200 local variables per function, and a file's top level is one function. One
-- file for every look passed that (the game refuses the whole file: "too many local variables"), so each group has
-- its own file and its own 200. They share what they need through ns.FXi (the table I below): the helpers, the
-- pools, and the state the core keeps (content, cfg, W, H, clock), which every file copies into its own locals
-- through its `sync` (so the hot paths still read upvalues, not table fields). Each file registers its hooks with
-- I.Register at its end; the hooks below call them in TOC order.
-- Positions are in bar pixels from the bottom-left corner, y up. Effects drawn on the fx frame
-- can spill past the bar; those on an element's content frame are clipped by the fill and
-- inside the frame line.

local _, ns = ...

local MEDIA = ns.MEDIA
local rand = ns.rand
local PI = math.pi
local FX = {}
ns.FX = FX

local fx                     -- the unclipped frame over the bar
local W, H = 300, 26
local content, cfg           -- the element being shown
local clock = 0

local function easeOutBack(t) local c = 1.7; t = t - 1; return 1 + t * t * ((c + 1) * t + c) end
local function pick(list) return list[math.random(#list)] end
local tools                  -- above the bar's frame line (bar level + 8): tools held in front of the bar
local linePool, spritePool   -- lines and sprites on fx, for every look

-- Sprites that turn, grow or drift every frame must not snap to the pixel grid: each corner would
-- jump to a different pixel every frame and the sprite would shake. Blizzard turns snapping off the
-- same way on its animated textures (snapToPixelGrid="false" texelSnappingBias="0.0", e.g.
-- Blizzard_ActionBar/Shared/ActionButtonComponentTemplate.xml, forever branch).
local function Smooth(tex)
	tex:SetSnapToPixelGrid(false)
	tex:SetTexelSnappingBias(0)
	return tex
end
ns.SmoothTexture = Smooth

-- Texture and line pools, so nothing is created during play after the first few casts.
local function Pool(make)
	local pool = { free = {}, used = {} }
	function pool:Get()
		local obj = table.remove(self.free) or make()
		self.used[obj] = true
		obj:Show()
		return obj
	end
	function pool:Release(obj)
		if not self.used[obj] then return end
		self.used[obj] = nil
		obj:Hide()
		self.free[#self.free + 1] = obj
	end
	function pool:ReleaseAll()
		for obj in pairs(self.used) do self:Release(obj) end
	end
	return pool
end

---------------------------------------------------------------------------
-- Particles
---------------------------------------------------------------------------
local particles = {}
local particlePool
local emitAcc = {}

local function Spawn(e, x, y)
	local tex = particlePool:Get()
	tex:SetTexture(MEDIA .. e.tex)
	tex:SetBlendMode(e.add and "ADD" or "BLEND")
	local c = pick(e.colors)
	tex:SetVertexColor(c[1], c[2], c[3])
	local k = H / 28
	local p = {
		tex = tex, e = e, x = x, y = y, age = 0, life = rand(e.life[1], e.life[2]),
		vx = rand(e.vx and e.vx[1] or -5, e.vx and e.vx[2] or 5) * k, vy = rand(e.vy and e.vy[1] or -5, e.vy and e.vy[2] or 5) * k,
		size = rand(e.size[1], e.size[2]) * H, rot = rand(0, 6.283), spin = e.spin and rand(e.spin[1], e.spin[2]) or 0,
		tw = e.twinkle and rand(8, 16) or 0, sw = rand(0, 6.283), grow = e.grow and rand(e.grow[1], e.grow[2]) * H or nil,
	}
	tex:SetSize(p.size, p.size)
	-- hidden and in place until UpdateParticles draws it, so a recycled texture never flashes
	-- for a frame where its previous particle was
	tex:SetAlpha(0)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", fx, "BOTTOMLEFT", x, y)
	particles[#particles + 1] = p
	return p
end

local function UpdateParticles(dt)
	for i = #particles, 1, -1 do
		local p = particles[i]
		p.age = p.age + dt
		if p.age >= p.life then
			particlePool:Release(p.tex)
			table.remove(particles, i)
		else
			if p.e.swirl then p.vx = p.vx + math.sin(p.age * 6 + p.sw) * p.e.swirl * dt end
			if p.e.gravity then p.vy = p.vy - p.e.gravity * (H / 28) * dt end   -- rock chips and sparks fall back down
			if p.grow then p.size = p.size + p.grow * dt; p.tex:SetSize(p.size, p.size) end   -- steam spreads as it rises
			p.x, p.y, p.rot = p.x + p.vx * dt, p.y + p.vy * dt, p.rot + p.spin * dt
			local t = p.age / p.life
			local a = math.min(1, t / .15) * math.min(1, (1 - t) / .4) * (p.e.alpha or 1)
			if p.tw > 0 then a = a * (.5 + .5 * math.sin(p.age * p.tw)) end
			p.tex:SetAlpha(math.max(0, a))
			p.tex:SetRotation(p.rot)
			p.tex:ClearAllPoints()
			p.tex:SetPoint("CENTER", fx, "BOTTOMLEFT", p.x, p.y)
		end
	end
end

local function Emit(dt, fillW)
	if fillW <= 2 then return end
	for i, e in ipairs(cfg.emit) do
		emitAcc[i] = (emitAcc[i] or 0) + e.rate * dt
		while emitAcc[i] >= 1 do
			emitAcc[i] = emitAcc[i] - 1
			local x, y
			if e.from == "edge" then x, y = fillW + rand(-4, 1), rand(0, H)
			elseif e.from == "bottom" then x, y = rand(0, fillW), H * rand(0, .65)
			elseif e.from == "top" then x, y = rand(0, fillW), H * rand(.7, 1)   -- embers carrying on off the top
			else x, y = rand(0, fillW), rand(0, H) end
			Spawn(e, x, y)
		end
	end
end

---------------------------------------------------------------------------
-- Shared helpers (ns.FXi, for the effect files)
---------------------------------------------------------------------------
local function Sprite(name, sub, blend)
	local tex = spritePool:Get()
	tex:SetTexture(MEDIA .. name)
	tex:SetDrawLayer("ARTWORK", sub)
	tex:SetBlendMode(blend or "BLEND")
	tex:SetTexCoord(0, 1, 0, 1)
	tex:SetRotation(0)
	tex:SetAlpha(1)
	tex:SetVertexColor(1, 1, 1, 1)   -- a recycled sprite may still carry another look's tint
	return tex
end

local function PlaceSprite(tex, cx, cy, size, rot)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", fx, "BOTTOMLEFT", cx, cy)
	tex:SetSize(math.max(.1, size), math.max(.1, size))
	tex:SetRotation(rot)
end

local function RGB(r, g, b) return { r / 255, g / 255, b / 255 } end

local function ToolTexture(name, sub, blend)
	local tex = Smooth(tools:CreateTexture(nil, "ARTWORK", nil, sub))
	tex:SetTexture(MEDIA .. name)
	tex:SetBlendMode(blend or "BLEND")
	tex:Hide()
	return tex
end

local function PlaceIn(tex, frame, x, y, w, h)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", frame, "BOTTOMLEFT", x, y)
	tex:SetSize(math.max(.1, w), math.max(.1, h))
end

-- a band of a content texture between left and right (x in bar pixels), clipped to the bar
local function Band(tex, left, right)
	left, right = math.max(0, left), math.min(W, right)
	tex:SetShown(right - left > .5)
	if right - left > .5 then
		tex:ClearAllPoints()
		tex:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", left, 0)
		tex:SetSize(right - left, H)
	end
end

local function Light(c, k) return c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k end
local function smooth(t) t = math.max(0, math.min(1, t)); return t * t * (3 - 2 * t) end
local function lerp(a, b, t) return a + (b - a) * t end
local function clamp(v) return v < 0 and 0 or v > 1 and 1 or v end
-- a texture inside an element's content frame (hidden until its look shows it)
local function ContentTex(c, name, sub, blend, wrapH)
	local tex = Smooth(c:CreateTexture(nil, "ARTWORK", nil, sub))
	if wrapH then tex:SetTexture(MEDIA .. name, wrapH, "CLAMP") else tex:SetTexture(MEDIA .. name) end
	tex:SetBlendMode(blend or "BLEND")
	tex:Hide()
	return tex
end

-- Everything the effect files share. fx, tools and the pools are filled in by FX:Init; the files read them in
-- their `init`. The core's state (content, cfg, W, H, clock) reaches them through their `sync`, never from here.
local I = {
	MEDIA = MEDIA, rand = rand, PI = PI, pick = pick, easeOutBack = easeOutBack, Smooth = Smooth, Pool = Pool,
	Spawn = Spawn, Sprite = Sprite, PlaceSprite = PlaceSprite, RGB = RGB, ToolTexture = ToolTexture, PlaceIn = PlaceIn,
	Band = Band, Light = Light, lerp = lerp, clamp = clamp, smooth = smooth, ContentTex = ContentTex,
}
ns.FXi = I

-- The effect files register here, in TOC order. A section is a table of hooks, all optional but sync:
--   init()                       once, after FX:Init made fx, tools and the pools (I.fx, I.tools, I.linePool, I.spritePool)
--   sync(content, cfg, W, H, t)  copy the core's state into the file's locals (FX:Begin, Layout, LayoutContent)
--   create(c)                    pieces inside an element's content frame c (FX:CreateContent)
--   begin()                      a cast starts on the synced content (FX:Begin, after clear and sync)
--   update(dt, fillW, casting, state, t)   every frame (t is the clock)
--   interrupted(k)               the interrupted tint fading in, k 0..1
--   clear(keep)                  the cast is over or another starts; keep: the next follows straight on (carry)
local sections = {}
function I.Register(sec) sections[#sections + 1] = sec end
local function Sync() for _, s in ipairs(sections) do s.sync(content, cfg, W, H, clock) end end

---------------------------------------------------------------------------
-- Plain: Blizzard's own cast bar art (CastingBarFrameBaseTemplate, Blizzard_UIPanels_Game/Mainline/CastingBarFrame.xml;
-- the atlases per kind are CastingBarTypeInfo in Shared/CastingBarFrame.lua): the standard or channel filling, the
-- full bar when the cast finishes, the interrupted bar when it doesn't. No effects.
---------------------------------------------------------------------------
local plain                  -- this cast's plain state

local function MakePlain()
	plain = { done = false, broken = false }
	content.plainFill:SetAtlas(cfg.plain.fill)
	content.plainFill:Show()
end

local function UpdatePlain(state)
	if state == "done" and not plain.done then
		plain.done = true
		content.plainFill:SetAtlas(cfg.plain.full)
	end
end

---------------------------------------------------------------------------
-- Hooks called by Bar.lua
---------------------------------------------------------------------------
function FX:Init(frame)
	fx = frame
	particlePool = Pool(function() return Smooth(fx:CreateTexture(nil, "ARTWORK", nil, 7)) end)
	linePool = Pool(function() return fx:CreateLine(nil, "ARTWORK") end)
	spritePool = Pool(function() return Smooth(fx:CreateTexture(nil, "ARTWORK")) end)
	fx.frontRev = Smooth(fx:CreateTexture(nil, "ARTWORK", nil, -1))
	fx.frontRev:SetTexture(MEDIA .. "frost_front")
	fx.frontRev:SetTexCoord(1, 0, 0, 1)   -- strongest at the edge, feathering to the right
	fx.frontRev:SetBlendMode("ADD")
	fx.frontRev:Hide()
	-- above the frame line (border, bar level + 7) and below the text (+ 9): tools held in front of the bar
	local bar = fx:GetParent()
	tools = CreateFrame("Frame", nil, bar)
	tools:SetAllPoints(bar)
	tools:SetFrameLevel(bar:GetFrameLevel() + 8)
	I.fx, I.tools, I.linePool, I.spritePool = fx, tools, linePool, spritePool
	for _, s in ipairs(sections) do if s.init then s.init() end end
end

-- Pieces that live inside an element's content frame (clipped by the fill).
function FX:CreateContent(c)
	for _, s in ipairs(sections) do if s.create then s.create(c) end end
	if c.cfg.plain then   -- Blizzard's filling (CastingBarTypeInfo), revealed by the fill like their status bar
		c.plainFill = c:CreateTexture(nil, "ARTWORK", nil, 1)
		c.plainFill:SetAllPoints(c)
	end
end

function FX:LayoutContent(c, w, h)
	W, H = w, h
	Sync()
	if c.sweepTex then c.sweepTex:SetSize(H * 1.0, H * 1.8) end
end

function FX:Layout(w, h) W, H = w, h; Sync() end

local function ClearAll(keepParticles)
	if not keepParticles then
		wipe(particles)
		particlePool:ReleaseAll()
	end
	linePool:ReleaseAll()
	spritePool:ReleaseAll()
	wipe(emitAcc)
	for _, s in ipairs(sections) do if s.clear then s.clear(keepParticles) end end
	plain = nil
end

-- Back-to-back casts of the same look (a "Create All" batch) run on from each other: the steam and sparks
-- already in the air stay, and blacksmithing's iron keeps its heat instead of snapping back to cold.
local CARRY_GAP = .6         -- seconds between one cast stopping and the next starting
local stoppedAt              -- when the shown cast stopped (FX:Update)

function FX:Begin(c, w, h)
	W, H = w, h
	local carry = c == content and stoppedAt and clock - stoppedAt < CARRY_GAP
	stoppedAt = nil
	ClearAll(carry)
	content, cfg = c, c.cfg
	Sync()
	for _, s in ipairs(sections) do if s.begin then s.begin() end end
	if cfg.plain then MakePlain() end
end

function FX:Update(dt, t, fillW, casting, state)   -- state: "cast", "done" or "interrupted"
	clock = t
	if not content then return end
	if not casting and not stoppedAt then stoppedAt = clock end
	if casting then Emit(dt, fillW) end
	UpdateParticles(dt)
	for _, s in ipairs(sections) do if s.update then s.update(dt, fillW, casting, state, t) end end
	if plain then UpdatePlain(state) end
end

-- The interrupted tint fading in (k 0 to 1): greys the pieces that aren't layers, which the bar greys itself.
-- Painted pieces lose their colour; additive glows fade out by (1 - grey) in their Update functions.
function FX:Interrupted(k)
	for _, s in ipairs(sections) do if s.interrupted then s.interrupted(k) end end
	if plain and content and content.plainFill and not plain.broken then   -- Blizzard's interrupted bar
		plain.broken = true
		content.plainFill:SetAtlas("ui-castingbar-interrupted")
	end
end

function FX:End()
	ClearAll()
end
