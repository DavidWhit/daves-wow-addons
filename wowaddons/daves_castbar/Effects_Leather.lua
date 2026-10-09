-- daves_castbar / Effects_Leather.lua
-- Leatherworking: tooled leather panels drawn together and cross-laced shut by a needle, stitches running along
-- the edges. One of the effect files (see Effects.lua): its own 200 top-level locals, the shared helpers from
-- ns.FXi, and its hooks registered at the end.

local _, ns = ...
local I = ns.FXi
local MEDIA, rand, pick, Smooth = I.MEDIA, I.rand, I.pick, I.Smooth
local RGB, ToolTexture, PlaceIn, lerp, clamp = I.RGB, I.ToolTexture, I.PlaceIn, I.lerp, I.clamp
local tools                               -- above the bar's frame line: the needle (init)
local content, cfg, W, H = nil, nil, 300, 26   -- the core's state, copied in by sync

---------------------------------------------------------------------------
-- Leatherworking: tooled leather panels laced together (concept lw-b). The panels lie across the whole bar (the
-- content is the whole bar, wholeBar) with their lacing holes punched, apart by the gaps still open; the lacing is
-- the progress: as the cast reaches each joint its gap closes and a needle cross-laces it shut with a thong, while
-- running stitches follow along both long edges behind the work. Each panel is a small frame inside the content
-- frame (so the bar clips it): its leather, tint, tooling, burnished edges and holes move with it as the gaps close.
-- The laces are Lines on a frame over the panels; the needle stands on `tools`, in a few fixed poses.
---------------------------------------------------------------------------
local TONES = { RGB(198, 150, 98), RGB(158, 104, 62), RGB(118, 74, 42), RGB(96, 60, 36), RGB(132, 96, 60) }   -- light, medium, heavy, thick, rugged
local THREADS = { RGB(236, 224, 188), RGB(48, 38, 30), RGB(156, 46, 34), RGB(214, 168, 92), RGB(226, 226, 222) }
local THONGS = { RGB(60, 36, 20), RGB(30, 24, 20), RGB(176, 120, 70) }
local LW_JOINTS, LW_ROWS = 20, 5                 -- joints at most (a long bar is cut off at the last), lacing holes a side at most
local LW_PANELS, LW_SEGS = LW_JOINTS + 1, (LW_ROWS - 1) * 2
local TOOLINGS = 5                               -- lw_tool1..5: basket-weave, scrolling vine, diamond lattice, bordered shells, knotwork band
local toolingTurn = math.random(TOOLINGS) - 1
local LEATHER_NOM = .88                          -- the leather is painted at this brightness for the tone's colour (Make-CastbarMedia.ps1 Leather)
local LEATHER_SPAN = 8                           -- lw_leather is 512x64: eight bar heights long
-- The needle atlas (Make-CastbarMedia.ps1 Needle): 2x2 cells NEEDLE_SPAN bar heights square, the eye at (NEEDLE_OX,
-- NEEDLE_OY) from each cell's top-left, the tip NEEDLE_L away pointing down-right at NEEDLE_ANG rad; flipped for down-left.
local NEEDLE_POSES, NEEDLE_SPAN, NEEDLE_OX, NEEDLE_OY = 4, 1.0, .25, .3
local NEEDLE_ANG = { .44, .56, .70, .82 }
local leather                -- this cast's state
local stitchery              -- the needle, made once

local function MakeStitchery()
	stitchery = { needle = ToolTexture("p_needle", 5) }
end

local function HideLeather()
	if stitchery then stitchery.needle:Hide() end
	if content and content.leather then
		local l = content.leather
		for _, pn in ipairs(l.panels) do pn.frame:Hide() end
		for _, t in ipairs(l.stitch) do t:Hide() end
		l.light:Hide(); l.shade:Hide()
		for _, J in ipairs(l.laces) do for _, line in ipairs(J) do line:Hide() end end
	end
end

local function MakeLeather()
	if not stitchery then MakeStitchery() end
	local l = content.leather
	local tone, thread, thong = pick(TONES), pick(THREADS), pick(THONGS)
	toolingTurn = toolingTurn % TOOLINGS + 1
	local rows = H >= 34 and 5 or 4
	local joints = {}
	local x = H * rand(1.3, 2)
	while x < W - H * .9 and #joints < LW_JOINTS do
		joints[#joints + 1] = x
		x = x + H * rand(1.8, 3)
	end
	leather = { joints = joints, rows = rows, n = #joints + 1, ys = {}, offs = {}, lp = {}, laced = {}, grey = 0 }
	for r = 1, rows do leather.ys[r] = H * (1 - (.18 + .64 * (r - 1) / (rows - 1))) end   -- the lacing rows, y up
	local tk = 1 / LEATHER_NOM
	for p = 1, LW_PANELS do
		local pn = l.panels[p]
		pn.off = nil
		if p > leather.n then pn.frame:Hide() else
			local a = p > 1 and joints[p - 1] or 0
			local b = p <= #joints and joints[p] or W
			pn.a, pn.b = a, b
			pn.frame:SetSize(math.max(.1, b - a), H)
			pn.frame:Show()
			pn.hide:SetVertexColor(tone[1] * tk, tone[2] * tk, tone[3] * tk)
			pn.hide:SetTexCoord(a / (LEATHER_SPAN * H), b / (LEATHER_SPAN * H), 0, 1)   -- its stretch of the hide
			pn.hide:SetDesaturation(0)
			local v = rand(-.14, .12)   -- each panel a little lighter or darker
			if v > 0 then pn.tint:SetColorTexture(1, .93, .84, v) else pn.tint:SetColorTexture(.12, .055, .016, -v) end
			-- the tooling, in the panel's middle band, clear of the holes at its ends and the edge stitching
			local ix0, ix1 = p > 1 and H * .24 or H * .18, (b - a) - (p <= #joints and H * .24 or H * .18)
			pn.tool:SetTexture(MEDIA .. "lw_tool" .. toolingTurn, "REPEAT", "CLAMP")
			pn.tool:SetShown(ix1 - ix0 > H * .4)
			if ix1 - ix0 > H * .4 then
				pn.tool:ClearAllPoints()
				pn.tool:SetPoint("TOPLEFT", pn.frame, "TOPLEFT", ix0, -H * .15)
				pn.tool:SetSize(ix1 - ix0, H * .7)
				pn.tool:SetTexCoord(0, (ix1 - ix0) / (2 * H), .15, .85)
				pn.tool:SetDesaturation(0)
			end
			pn.edge[1]:SetShown(p > 1); pn.edge[2]:SetShown(p <= #joints)   -- burnished only where panels meet
			pn.edge[1]:SetWidth(H * .08); pn.edge[2]:SetWidth(H * .08)
			for r = 1, LW_ROWS do
				local hl, hr = pn.holes[r], pn.holes[LW_ROWS + r]
				hl:SetShown(r <= rows and p > 1); hr:SetShown(r <= rows and p <= #joints)
				if r <= rows then
					PlaceIn(hl, pn.frame, H * .1, leather.ys[r], H * .1, H * .1)
					PlaceIn(hr, pn.frame, (b - a) - H * .1, leather.ys[r], H * .1, H * .1)
				end
			end
		end
	end
	for j = 1, LW_JOINTS do
		for q = 1, LW_SEGS do
			local line = l.laces[j][q]
			line:Hide()
			line:SetVertexColor(thong[1], thong[2], thong[3])
			line:SetDesaturation(0)
			line:SetThickness(math.max(1.4, H * .06))
		end
	end
	for i, t in ipairs(l.stitch) do
		t:SetVertexColor(thread[1], thread[2], thread[3])
		t:SetDesaturation(0)
		t:ClearAllPoints()
		t:SetPoint("LEFT", content, "BOTTOMLEFT", 0, i == 1 and H * .93 or H * .07)
		t:SetHeight(H * .1)
		t:Hide()
	end
	l.light:ClearAllPoints(); l.light:SetPoint("TOPLEFT", content, "TOPLEFT"); l.light:SetSize(W, H * .3); l.light:Show()
	l.shade:ClearAllPoints(); l.shade:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT"); l.shade:SetSize(W, H * .7); l.shade:Show()
	stitchery.needle:SetDesaturation(0)
end

local function UpdateLeather(dt, fillW, casting)
	local l, J, ys = content.leather, leather.joints, leather.ys
	-- how far each joint is laced, and the panels shifted right by the gaps still open before them
	local off = 0
	for j = 1, #J do
		local lp = clamp((fillW - J[j]) / (H * .9))
		leather.lp[j], leather.offs[j] = lp, off
		off = off + H * .14 * (1 - (1 - (1 - lp) * (1 - lp)))
	end
	leather.offs[#J + 1] = off
	for p = 1, leather.n do
		local pn, o = l.panels[p], leather.offs[p]
		if pn.off ~= o then   -- only panels still moving
			pn.off = o
			pn.frame:ClearAllPoints()
			pn.frame:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", pn.a + o, 0)
		end
	end
	-- running stitches along both long edges, behind the work
	local done = fillW - H * .2
	for j = 1, #J do if leather.lp[j] < 1 then done = math.min(done, J[j] + leather.offs[j]); break end end
	for _, t in ipairs(l.stitch) do
		t:SetShown(done > 1)
		if done > 1 then t:SetWidth(done); t:SetTexCoord(0, done / (H * .2), 0, 1) end
	end
	-- the joints: the holes are already punched; the needle cross-laces each shut as the cast reaches it. A joint's
	-- lines move only while it is being laced (the gaps before it have closed by then)
	local segs, tool = (leather.rows - 1) * 2, nil
	for j = 1, #J do
		local lp = leather.lp[j]
		if leather.laced[j] ~= lp then
			leather.laced[j] = lp
			local L = J[j] + leather.offs[j]
			local R = L + H * .14 * (1 - (1 - (1 - lp) * (1 - lp)))
			local xl, xr = L - H * .1, R + H * .1
			local n = lp * segs
			for q = 1, segs do
				local line = l.laces[j][q]
				if lp > 0 and q <= math.ceil(n) then
					local r = math.floor((q - 1) / 2) + 1
					local x1, y1, x2, y2
					if q % 2 == 1 then x1, y1, x2, y2 = xl, ys[r], xr, ys[r + 1] else x1, y1, x2, y2 = xr, ys[r], xl, ys[r + 1] end
					local f = math.min(1, n - (q - 1))
					line:SetStartPoint("BOTTOMLEFT", content, x1, y1)
					line:SetEndPoint("BOTTOMLEFT", content, lerp(x1, x2, f), lerp(y1, y2, f))
					line:Show()
					if f < 1 then tool = { x = lerp(x1, x2, f), y = lerp(y1, y2, f), dx = x2 - x1, dy = y2 - y1 } end
				else
					line:Hide()
				end
			end
		elseif lp > 0 and lp < 1 then   -- holding mid-lace (a channel, a test cast held): the needle stays
			local n = lp * segs
			local q = math.ceil(n)
			local L = J[j] + leather.offs[j]
			local xl, xr = L - H * .1, L + H * .14 * (1 - (1 - (1 - lp) * (1 - lp))) + H * .1
			local r = math.floor((q - 1) / 2) + 1
			local x1, y1, x2, y2
			if q % 2 == 1 then x1, y1, x2, y2 = xl, ys[r], xr, ys[r + 1] else x1, y1, x2, y2 = xr, ys[r], xl, ys[r + 1] end
			local f = n - (q - 1)
			tool = { x = lerp(x1, x2, f), y = lerp(y1, y2, f), dx = x2 - x1, dy = y2 - y1 }
		end
	end
	-- the needle at the lace's end, pointing along it (down-right or down-left, in the nearest painted pose)
	local needle = stitchery.needle
	needle:SetShown(tool ~= nil and casting)
	if not tool or not casting then return end
	local d = math.sqrt(tool.dx * tool.dx + tool.dy * tool.dy)
	if d < .01 then needle:Hide(); return end
	local ux, uy = tool.dx / d, tool.dy / d
	local ex, ey = tool.x - ux * H * .08, tool.y - uy * H * .08
	local ang = math.atan(math.abs(uy) / math.max(.01, math.abs(ux)))
	local pose = math.max(0, math.min(NEEDLE_POSES - 1, math.floor((ang - NEEDLE_ANG[1]) / (NEEDLE_ANG[NEEDLE_POSES] - NEEDLE_ANG[1]) * (NEEDLE_POSES - 1) + .5)))
	local col, row, e = pose % 2, math.floor(pose / 2), .5 / 256
	local u0, u1, v0, v1 = col / 2 + e, (col + 1) / 2 - e, row / 2 + e, (row + 1) / 2 - e
	local flip = ux < 0
	if flip then needle:SetTexCoord(u1, u0, v0, v1) else needle:SetTexCoord(u0, u1, v0, v1) end
	local left = flip and ex - (NEEDLE_SPAN - NEEDLE_OX) * H or ex - NEEDLE_OX * H
	needle:ClearAllPoints()
	needle:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", left, ey + NEEDLE_OY * H)
	needle:SetSize(NEEDLE_SPAN * H, NEEDLE_SPAN * H)
end

---------------------------------------------------------------------------
-- Hooks (Effects.lua calls them)
---------------------------------------------------------------------------
I.Register({
	key = "leather",
	init = function() tools = I.tools end,
	sync = function(c, cf, w, h) content, cfg, W, H = c, cf, w, h end,
	create = function(c)
		local ccfg = c.cfg
		if ccfg.leather then   -- the panels (frames the bar clips), and over them the hide's light and shade, the edge stitches, the laces
			local l = { panels = {}, laces = {}, stitch = {} }
			for p = 1, LW_PANELS do
				local f = CreateFrame("Frame", nil, c)
				ns.MaskAllTextures(f)   -- the end panels reach the bar's corners
				f:SetSize(10, 10)
				f:Hide()
				local pn = { frame = f, edge = {}, holes = {} }
				pn.hide = Smooth(f:CreateTexture(nil, "ARTWORK", nil, 0)); pn.hide:SetTexture(MEDIA .. "lw_leather", "REPEAT", "CLAMP"); pn.hide:SetAllPoints(f)
				pn.tint = f:CreateTexture(nil, "ARTWORK", nil, 1); pn.tint:SetAllPoints(f)
				pn.tool = Smooth(f:CreateTexture(nil, "ARTWORK", nil, 2)); pn.tool:SetTexture(MEDIA .. "lw_tool1", "REPEAT", "CLAMP")
				for i = 1, 2 do   -- burnished cut edges, darkest at the panel's end
					local e = Smooth(f:CreateTexture(nil, "ARTWORK", nil, 3))
					e:SetTexture(MEDIA .. "edge_h")
					e:SetVertexColor(36 / 255, 18 / 255, 6 / 255, .7)
					if i == 1 then e:SetTexCoord(1, 0, 0, 1); e:SetPoint("TOPLEFT", f, "TOPLEFT"); e:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
					else e:SetPoint("TOPRIGHT", f, "TOPRIGHT"); e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT") end
					e:SetWidth(2)   -- H * .08 at MakeLeather
					pn.edge[i] = e
				end
				for i = 1, LW_ROWS * 2 do
					local h = Smooth(f:CreateTexture(nil, "ARTWORK", nil, 4))
					h:SetTexture(MEDIA .. "p_hole")
					h:Hide()
					pn.holes[i] = h
				end
				l.panels[p] = pn
			end
			l.over = CreateFrame("Frame", nil, c)
			ns.MaskAllTextures(l.over)
			l.over:SetAllPoints(c)
			l.over:SetFrameLevel(c:GetFrameLevel() + 2)
			l.light = l.over:CreateTexture(nil, "ARTWORK", nil, 0)   -- edge_h turned on its side: strongest at the top
			l.light:SetTexture(MEDIA .. "edge_h"); l.light:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1); l.light:SetVertexColor(1, .94, .86, .1); l.light:Hide()
			l.shade = l.over:CreateTexture(nil, "ARTWORK", nil, 0)   -- strongest at the bottom
			l.shade:SetTexture(MEDIA .. "edge_h"); l.shade:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1); l.shade:SetVertexColor(0, 0, 0, .18); l.shade:Hide()
			for i = 1, 2 do
				local t = Smooth(l.over:CreateTexture(nil, "ARTWORK", nil, 1))
				t:SetTexture(MEDIA .. "lw_stitch", "REPEAT", "CLAMP")
				t:Hide()
				l.stitch[i] = t
			end
			for j = 1, LW_JOINTS do
				l.laces[j] = {}
				for q = 1, LW_SEGS do
					local line = l.over:CreateLine(nil, "ARTWORK", nil, 2)
					line:SetTexture(MEDIA .. "lw_lace")
					line:Hide()
					l.laces[j][q] = line
				end
			end
			c.leather = l
		end
	end,
	begin = function() if cfg.leather then MakeLeather() end end,
	update = function(dt, fillW, casting)
		if leather then UpdateLeather(dt, fillW, casting) end
	end,
	interrupted = function(k)
		if leather and stitchery and content and content.leather then
			leather.grey = k
			local l = content.leather
			for p = 1, leather.n do
				local pn = l.panels[p]
				pn.hide:SetDesaturation(k); pn.tool:SetDesaturation(k)
			end
			for _, t in ipairs(l.stitch) do t:SetDesaturation(k) end
			for j = 1, #leather.joints do for _, line in ipairs(l.laces[j]) do line:SetDesaturation(k) end end
			stitchery.needle:SetDesaturation(k)
		end
	end,
	clear = function()
		HideLeather()
		leather = nil
	end,
})
