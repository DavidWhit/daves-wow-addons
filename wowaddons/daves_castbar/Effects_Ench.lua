-- daves_castbar / Effects_Ench.lua
-- Enchanting (a vortex at the cast edge spinning glittering dust into magic that settles and flows on dark
-- velvet) and disenchant (the vortex coming in from the right, drawing the magic out of the solid bar and
-- throwing it out as dust). One of the effect files (see Effects.lua): its own 200 top-level locals, the shared
-- helpers from ns.FXi, and its hooks registered at the end.

local _, ns = ...
local I = ns.FXi
local MEDIA, rand, pick, Smooth, Pool = I.MEDIA, I.rand, I.pick, I.Smooth, I.Pool
local RGB, PlaceIn, Light, lerp, clamp, ContentTex = I.RGB, I.PlaceIn, I.Light, I.lerp, I.clamp, I.ContentTex
local fx, tools                           -- the core's fx frame, and this file's clip frame over the bar for the vortex (init)
local content, cfg, W, H, clock = nil, nil, 300, 26, 0   -- the core's state, copied in by sync

---------------------------------------------------------------------------
-- Enchanting (concept ench-c) and Disenchant (ench-c3): magic and a vortex. The velvet (the layers, tinted to this
-- cast's palette) is where the magic settles: two bands of light flow along it and glitter twinkles on it.
-- Enchanting: the vortex rides the cast edge, pulling glittering dust out of the unfilled part and spinning it into
-- the filled part. Disenchant: the whole bar starts solid with magic (wholeBar); the vortex comes in at the right end
-- and moves left, the magic ahead of it fading as it is drawn off, motes spiralling into it and flung out behind as
-- dust and essence motes that settle on the cloth it leaves spent. The vortex's rings are an atlas of spin phases
-- (Make-CastbarMedia.ps1 Vortex) on `tools`; the dust lives on a frame clipped to the bar; nothing turns.
---------------------------------------------------------------------------
local ENCH_PALETTES = {      -- as the concept: main, deep (the velvet), accent, hi (the pale glints)
	{ main = RGB(158, 96, 255), deep = RGB(34, 12, 62), acc = RGB(86, 228, 222), hi = RGB(232, 208, 255) },
	{ main = RGB(96, 205, 235), deep = RGB(10, 34, 56), acc = RGB(190, 120, 255), hi = RGB(214, 252, 255) },
	{ main = RGB(206, 112, 255), deep = RGB(46, 14, 58), acc = RGB(255, 196, 104), hi = RGB(255, 226, 255) },
	{ main = RGB(124, 132, 255), deep = RGB(18, 18, 64), acc = RGB(120, 255, 200), hi = RGB(222, 228, 255) },
}
local ASH = RGB(190, 190, 200)
local VELVET_NOM = .78       -- the velvet is painted at this brightness for its tint (Make-CastbarMedia.ps1 EnchVelvet)
local VELVET_SPAN = 8        -- ench_velvet is 512x64: eight bar heights long
local ENCH_FLOW = { { w = 11.4, su = .223 }, { w = 12.6, su = .302 } }   -- ench_flow1/2: width in bar heights, speed in widths a second (the concept's wavelengths and rates)
local VORTEX_COLS, VORTEX_ROWS, VORTEX_CELL = 16, 6, 1.4   -- the atlas (Vortex): spin phases across, rings down, a cell 1.4 bar heights square; 1024x512 holds 8 rows
local ENCH_DRAIN = 2.6       -- bar heights ahead of the vortex over which the magic is drawn off (disenchant)
local DUST_MAX, GLITTER_MAX, ASH_MAX = 48, 40, 24
local PULL_MAX, THROWN_MAX = 36, 110
local ench                   -- this cast's state
local vortex                 -- the vortex's textures on tools, made once
local enchFrame, enchPool    -- a frame clipped to the bar, on fx: the dust in the unfilled part, the motes drawn out and thrown

local function EnchSprite(name, sub)
	local tex = enchPool:Get()
	tex:SetTexture(MEDIA .. name)
	tex:SetDrawLayer("ARTWORK", sub)
	tex:SetBlendMode("ADD")
	tex:SetTexCoord(0, 1, 0, 1)
	tex:SetAlpha(0)
	return tex
end

-- The vortex's textures live on `tools`, this file's clip frame over the bar (init): it runs a little ahead of
-- the cast edge and off the bar's end by the time the cast completes, so the clip cuts it away cleanly and no
-- ring or tail is left showing at the finish.
local function MakeVortex()
	local function Tex(name, sub)
		local tex = Smooth(tools:CreateTexture(nil, "ARTWORK", nil, sub))
		tex:SetTexture(MEDIA .. name)
		tex:SetBlendMode("ADD")
		tex:Hide()
		return tex
	end
	vortex = { rings = {} }
	vortex.glow = Tex("p_soft", 1)
	for i = 1, VORTEX_ROWS do vortex.rings[i] = Tex("p_vortex", 2) end
	vortex.core = Tex("p_soft", 3)
	vortex.core:SetVertexColor(1, 1, 1)
end

local function HideEnch()
	if vortex then
		vortex.glow:Hide(); vortex.core:Hide()
		for _, r in ipairs(vortex.rings) do r:Hide() end
	end
	if enchPool then enchPool:ReleaseAll() end
	if content and content.ench then
		local e = content.ench
		for _, t in ipairs(e.flow) do t:Hide() end
		for _, t in ipairs(e.glitter) do t:Hide() end
		for _, t in ipairs(e.ash) do t:Hide() end
		if e.spent then e.spent:Hide() end
	end
end

-- a grain of dust: a soft glow with a bright point in it (the sprites come from the pool and are kept while it lives)
local function ResetDust(d, x)
	d.x, d.y, d.ang, d.r, d.f, d.ph = x, H * rand(.1, .9), rand(0, 6.283), rand(.025, .05), rand(2, 6), rand(0, 6.283)
end
local function NewDust(x, pal)
	local d = { glow = EnchSprite("p_soft", 1), dot = EnchSprite("p_dot", 2) }
	d.dot:SetVertexColor(pal.hi[1], pal.hi[2], pal.hi[3])   -- the dot's colour never changes; the glow's does near the vortex (DrawMote)
	ResetDust(d, x)
	return d
end
local function DrawMote(d, x, y, near, a, pal, lit)
	local acc = near > .3
	if d.acc ~= acc then   -- the glow turns to the accent colour as the grain nears the vortex: set only when that changes
		d.acc = acc
		local c = acc and pal.acc or pal.main
		d.glow:SetVertexColor(c[1], c[2], c[3])
	end
	PlaceIn(d.glow, enchFrame, x, y, H * d.r * 5.6, H * d.r * 5.6)
	d.glow:SetAlpha(a * .6 * lit)
	PlaceIn(d.dot, enchFrame, x, y, H * d.r * 1.2, H * d.r * 1.2)
	d.dot:SetAlpha(a * lit)
end

local function MakeEnch()
	if not vortex then MakeVortex() end
	local pal = pick(ENCH_PALETTES)
	local dis = cfg.ench.disenchant
	local e = content.ench
	-- the velvet: its deep colour, the top toward the main one; the mottles and specks added in main and accent
	local top = {}
	for i = 1, 3 do top[i] = (pal.deep[i] + (pal.main[i] - pal.deep[i]) * .18) / VELVET_NOM end
	ns.TintLayer(content, 1, top[1], top[2], top[3])
	ns.TintLayer(content, 2, (pal.main[1] + pal.acc[1]) / 2, (pal.main[2] + pal.acc[2]) / 2, (pal.main[3] + pal.acc[3]) / 2)
	e.flow[1]:SetVertexColor(pal.main[1], pal.main[2], pal.main[3])
	e.flow[2]:SetVertexColor(pal.acc[1], pal.acc[2], pal.acc[3])
	for _, t in ipairs(e.flow) do t:Show() end
	ench = { pal = pal, dis = dis, flowU = { math.random(), math.random() }, glitter = {}, dust = {}, pull = {}, thrown = {}, ash = {}, pullAcc = 0, grey = 0,
		gOn = {}, aOn = {}, vOn = false }   -- what is shown, so UpdateEnch only calls SetShown when that changes
	-- glitter on the velvet, anchored once
	local n = math.min(GLITTER_MAX, math.floor(W / H * 10))
	for i = 1, GLITTER_MAX do
		local t = e.glitter[i]
		if i <= n then
			local q = { x = rand(0, W), y = H * rand(.1, .9), f = rand(2, 6), ph = rand(0, 6.283), r = rand(.02, .045) }
			ench.glitter[i] = q
			PlaceIn(t, content, q.x, q.y, H * q.r * 6.6, H * q.r * 6.6)
			t:SetVertexColor(pal.hi[1], pal.hi[2], pal.hi[3])
			t:SetAlpha(0); t:Show()
			ench.gOn[i] = true
		else
			t:Hide()
		end
	end
	if dis then
		-- the spent cloth behind the vortex: the velvet again, drained of colour and darkened, through a mask that
		-- fades it in over the drain stretch (edge_h, CLAMP: hidden left of the mask, whole right of it)
		local u = content.layers[1].u
		e.spent:SetTexCoord(u, u + W / (VELVET_SPAN * H), 0, 1)   -- as the layer
		e.spent:SetVertexColor(top[1] * .55, top[2] * .55, top[3] * .55)
		e.spent:SetDesaturation(.85)
		e.spent:Show()
		n = math.min(ASH_MAX, math.floor(W / H * 8))
		for i = 1, ASH_MAX do
			local t = e.ash[i]
			if i <= n then
				local q = { x = rand(0, W), y = H * rand(.1, .9), f = rand(1, 3), ph = rand(0, 6.283), r = rand(.015, .03) }
				ench.ash[i] = q
				PlaceIn(t, content, q.x, q.y, H * q.r * 6.6, H * q.r * 6.6)
				t:SetAlpha(0); t:Show()
				ench.aOn[i] = true
			else
				t:Hide()
			end
		end
	else
		n = math.min(DUST_MAX, math.floor(W / H * 8))
		for i = 1, n do ench.dust[i] = NewDust(rand(0, W), pal) end
	end
	-- the vortex: rings alternately the accent and the pale colour (brighter toward the throat, UpdateEnch); its glow in the main colour
	for i, r in ipairs(vortex.rings) do
		local c = i % 2 == 0 and pal.acc or pal.hi
		r:SetVertexColor(c[1], c[2], c[3])
	end
	vortex.glow:SetVertexColor(pal.main[1], pal.main[2], pal.main[3])
end

-- Enchanting: the dust in the unfilled part is drawn toward the vortex and spun into it; each grain that goes in
-- comes back somewhere ahead.
local function UpdateEnchantDust(dt, vx, vy, casting)
	local s, pal, lit = ench, ench.pal, 1 - ench.grey
	for _, d in ipairs(s.dust) do
		local dx = d.x - vx
		local dist = math.max(H * .2, math.abs(dx))
		local pull = casting and H * 2.8 / (dist / H + .4) or 0
		if dx > 0 then d.x = d.x - pull * dt end
		d.ang = d.ang + dt * (2 + 9 / (dist / H + .3))
		local near = clamp(1 - dist / (H * 1.6))
		local y = lerp(d.y, vy + math.sin(d.ang) * H * .38 * (1 - near * .4), near)
		local a = .25 + .55 * near * (.5 + .5 * math.sin(clock * d.f + d.ph))
		DrawMote(d, d.x, y, near, a, pal, lit)
		if d.x < vx - H * .05 then ResetDust(d, rand(math.max(vx + H * .5, 0), W + H * .3)) end
	end
end

-- Disenchant: a mote out of the vortex's throat is flung behind it (right) as a grain of dust; a third of them are
-- shimmers, small four-point glints that twinkle briefly as they settle (no essence orbs)
local function Throw(d, vx, vy)
	local s, pal = ench, ench.pal
	local q = { x = vx + H * .1, y = vy + rand(-.15, .15) * H, vx = H * rand(1.4, 3.6), vy = H * rand(-1.2, 1.2), rest = H * rand(.15, .85),
		r = rand(.02, .045), f = rand(2, 6), ph = rand(0, 6.283), shine = math.random() < .35, glow = d.glow, dot = d.dot }
	q.glow:SetVertexColor(pal.main[1], pal.main[2], pal.main[3])
	if q.shine then
		q.dot:SetTexture(MEDIA .. "p_star")
		q.dot:SetVertexColor(Light(pal.hi, .3))
		q.f = rand(1.2, 3)
	else
		local c = math.random() < .5 and pal.hi or pal.acc
		q.dot:SetVertexColor(c[1], c[2], c[3])
	end
	if #s.thrown >= THROWN_MAX then   -- the oldest makes way
		local old = table.remove(s.thrown, 1)
		enchPool:Release(old.glow); enchPool:Release(old.dot)
	end
	s.thrown[#s.thrown + 1] = q
end

local function UpdateDisenchant(dt, vx, vy, casting)
	local e, s, pal, lit = content.ench, ench, ench.pal, 1 - ench.grey
	local drain = ENCH_DRAIN * H
	-- the spent cloth fading in over the drain stretch, the flow fading out over it
	for _, m in ipairs({ e.spentMask, e.flowMask }) do
		m:ClearAllPoints()
		m:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", vx - drain, 0)
		m:SetSize(drain, H)
	end
	-- a last few dull glints in the spent part
	for i, q in ipairs(s.ash) do
		local on = q.x > vx + drain * .5
		if on ~= s.aOn[i] then e.ash[i]:SetShown(on); s.aOn[i] = on end
		if on then e.ash[i]:SetAlpha(math.max(0, math.sin(clock * q.f + q.ph)) ^ 4 * .25 * lit) end
	end
	-- motes drawn out of the drain stretch ahead, spiralling right into the vortex
	if casting and vx > H * .3 then
		s.pullAcc = s.pullAcc + dt * 34
		while s.pullAcc >= 1 do
			s.pullAcc = s.pullAcc - 1
			if #s.pull < PULL_MAX then
				local d = { x = rand(math.max(0, vx - drain), vx - H * .15), y = H * rand(.12, .88), ang = rand(0, 6.283), r = rand(.025, .05),
					f = rand(2, 6), ph = rand(0, 6.283), glow = EnchSprite("p_soft", 1), dot = EnchSprite("p_dot", 2) }
				d.dot:SetVertexColor(pal.hi[1], pal.hi[2], pal.hi[3])
				s.pull[#s.pull + 1] = d
			end
		end
	else
		s.pullAcc = 0
	end
	for i = #s.pull, 1, -1 do
		local d = s.pull[i]
		local dist = math.max(H * .15, math.abs(vx - d.x))
		d.x = d.x + H * 2.6 / (dist / H + .35) * dt
		d.ang = d.ang - dt * (2 + 9 / (dist / H + .3))
		local near = clamp(1 - dist / (H * 1.6))
		local y = lerp(d.y, vy + math.sin(d.ang) * H * .38 * (1 - near * .4), near)
		DrawMote(d, d.x, y, near, .35 + .55 * near, pal, lit)
		if d.x >= vx - H * .05 or not casting then
			table.remove(s.pull, i)
			if casting then
				Throw(d, vx, vy)   -- out of the throat: its sprites carry on as thrown dust
			else
				enchPool:Release(d.glow); enchPool:Release(d.dot)
			end
		end
	end
	-- the thrown dust drifts behind, slows and settles on the spent cloth, where it collects and glitters
	for _, q in ipairs(s.thrown) do
		if not q.settled then
			local drag = math.exp(-dt * 2.4)
			q.vx = q.vx * drag
			q.vy = q.vy * drag + (q.rest - q.y) * dt * 3
			q.x, q.y = q.x + q.vx * dt, q.y + q.vy * dt
			if casting then q.x = math.max(q.x, vx + H * (.3 + .2 * math.sin(q.ph))) end   -- never left on the solid part
			if math.abs(q.vx) < H * .01 and math.abs(q.vy) < H * .01 and math.abs(q.rest - q.y) < H * .01 then q.settled = true end   -- at rest: only its glitter changes from here
			local gs = H * q.r * 5.2
			PlaceIn(q.glow, enchFrame, q.x, q.y, gs, gs)
			local ds = q.shine and H * .14 or H * q.r * 1.1
			PlaceIn(q.dot, enchFrame, q.x, q.y, ds, ds)
		end
		local tw = .45 + .55 * math.max(0, math.sin(clock * q.f + q.ph))
		if q.shine then   -- a shimmer: mostly faint, flaring into a small star now and then
			local flare = math.max(0, math.sin(clock * q.f + q.ph)) ^ 8
			q.glow:SetAlpha((.12 + .3 * flare) * lit)
			q.dot:SetAlpha((.15 + .85 * flare) * lit)
		else
			q.glow:SetAlpha(.35 * tw * lit)
			q.dot:SetAlpha(.85 * tw * lit)
		end
	end
end

local function UpdateEnch(dt, fillW, casting)
	local e, s = content.ench, ench
	local lit = 1 - s.grey
	-- the vortex leads the cast edge a little, and over the last .6 bar heights of travel pulls a whole bar height
	-- ahead, so by completion its widest glow has passed the bar's end and the clip frame has cut it all away
	local lead = H * (.15 + .85 * clamp((fillW - (W - H * .6)) / (H * .6)))
	local vx, vy = s.dis and (W - fillW - lead) or (fillW + lead), H * .5
	-- the settled power's flow: two bands of light sliding along the velvet
	for i, f in ipairs(e.flow) do
		local F = ENCH_FLOW[i]
		s.flowU[i] = (s.flowU[i] - F.su * dt) % 1
		f:SetTexCoord(s.flowU[i], s.flowU[i] + W / (F.w * H), 0, 1)
		f:SetAlpha(.2 * lit)
	end
	-- glitter twinkling on it: behind the edge (enchanting), well ahead of the vortex (disenchant)
	local upTo = s.dis and vx - ENCH_DRAIN * H * .3 or fillW
	for i, q in ipairs(s.glitter) do
		local on = q.x < upTo
		if on ~= s.gOn[i] then e.glitter[i]:SetShown(on); s.gOn[i] = on end
		if on then e.glitter[i]:SetAlpha(math.max(0, math.sin(clock * q.f + q.ph)) ^ 3 * .8 * lit) end
	end
	if s.dis then UpdateDisenchant(dt, vx, vy, casting) else UpdateEnchantDust(dt, vx, vy, casting) end
	-- the vortex at the cast edge, only while casting: the glow, the rings at this moment's spin, the white throat
	local on = casting and fillW >= 2
	if on ~= s.vOn then
		s.vOn = on
		vortex.glow:SetShown(on); vortex.core:SetShown(on)
		for _, r in ipairs(vortex.rings) do r:SetShown(on) end
	end
	if not on then return end
	PlaceIn(vortex.glow, tools, vx, vy, H * 2, H * 2); vortex.glow:SetAlpha(.35 * lit)
	PlaceIn(vortex.core, tools, vx, vy, H * .4, H * .4); vortex.core:SetAlpha(.85 * lit)
	for i, r in ipairs(vortex.rings) do
		local k = (i - 1) / 5
		local col = math.floor((clock * (3 + (i - 1) * 1.6) / 6.283 % 1) * VORTEX_COLS)
		local l, rr = col / VORTEX_COLS, (col + 1) / VORTEX_COLS
		if s.dis then l, rr = rr, l end   -- mirrored: leaning and spinning the other way
		r:SetTexCoord(l, rr, (i - 1) / 8, i / 8)
		PlaceIn(r, tools, vx, vy, VORTEX_CELL * H, VORTEX_CELL * H)
		r:SetAlpha((.2 + .5 * k) * lit)
	end
end

---------------------------------------------------------------------------
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "ench",
	init = function()
		fx = I.fx
		-- the vortex's own frame: over the frame line like the shared tools frame, but clipped to the bar
		tools = CreateFrame("Frame", nil, I.tools)
		tools:SetAllPoints(I.tools)
		tools:SetClipsChildren(true)
		tools:SetFrameLevel(I.tools:GetFrameLevel())
		-- clipped to the bar, at fx's level: enchanting's dust in the unfilled part, disenchant's motes and thrown dust
		enchFrame = CreateFrame("Frame", nil, fx)
		enchFrame:SetAllPoints(fx)
		enchFrame:SetClipsChildren(true)
		enchFrame:SetFrameLevel(fx:GetFrameLevel())
		enchPool = Pool(function() return Smooth(enchFrame:CreateTexture(nil, "ARTWORK")) end)
	end,
	sync = function(c, cf, w, h, t) content, cfg, W, H, clock = c, cf, w, h, t end,
	create = function(c)
		local ccfg = c.cfg
		if ccfg.ench then   -- over the velvet: the flow's two bands and the glitter; disenchant: the spent cloth behind the vortex, its masks, the ash
			local e = { flow = {}, glitter = {}, ash = {} }
			for i = 1, 2 do
				e.flow[i] = ContentTex(c, "ench_flow" .. i, 2, "ADD", "REPEAT")
				e.flow[i]:SetAllPoints(c)
			end
			for i = 1, GLITTER_MAX do e.glitter[i] = ContentTex(c, "p_soft", 5, "ADD") end
			if ccfg.ench.disenchant then
				e.spent = ContentTex(c, "ench_velvet", 4, "BLEND", "REPEAT")
				e.spent:SetAllPoints(c)
				-- the masks are never hidden (a hidden mask stops masking); UpdateDisenchant moves them over the drain stretch
				e.spentMask = Smooth(c:CreateMaskTexture())
				e.spentMask:SetTexture(MEDIA .. "edge_h", "CLAMP", "CLAMP")   -- hidden left of the mask, fading in across it, whole right of it
				e.spentMask:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", -10, 0); e.spentMask:SetSize(10, 10)
				e.spent:AddMaskTexture(e.spentMask)
				e.flowMask = Smooth(c:CreateMaskTexture())
				e.flowMask:SetTexture(MEDIA .. "edge_h", "CLAMP", "CLAMP")
				e.flowMask:SetTexCoord(1, 0, 0, 1)                             -- the other way: the flow fades out toward the vortex
				e.flowMask:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", -10, 0); e.flowMask:SetSize(10, 10)
				for i = 1, 2 do e.flow[i]:AddMaskTexture(e.flowMask) end
				for i = 1, ASH_MAX do
					e.ash[i] = ContentTex(c, "p_soft", 5, "ADD")
					e.ash[i]:SetVertexColor(ASH[1], ASH[2], ASH[3])
				end
			end
			c.ench = e
		end
	end,
	begin = function() if cfg.ench then MakeEnch() end end,
	update = function(dt, fillW, casting, _, t)
		clock = t
		if ench then UpdateEnch(dt, fillW, casting) end
	end,
	interrupted = function(k)
		if ench and content and content.ench then   -- the velvet greys with the bar; the glows and the dust fade by (1 - grey) in UpdateEnch
			ench.grey = k
			if content.ench.spent then content.ench.spent:SetDesaturation(math.max(.85, k)) end
		end
	end,
	clear = function()
		HideEnch()
		ench = nil
	end,
})
