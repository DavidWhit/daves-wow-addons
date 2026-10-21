-- daves_frames / Auras.lua
-- The aura boards (NOTES.md section 6): your debuffs on the target on the left, their buffs on the right.
-- Each board grows from its outer end toward the ring and wraps to a new row before it gets there
-- (and before the ornament below the plate), up to the Max rows setting; past that the last cell shows
-- an ellipsis. Boards hang on two chains and swing a little when you move, or sit right under the bar.

local _, ns = ...


local MAX_AURAS = 40
local FILTERS = { L = "HARMFUL|PLAYER", R = "HELPFUL" }

local function Secret(v) return issecretvalue and issecretvalue(v) end

---------------------------------------------------------------------------
-- Board art: a 9-slice from the strip in the frame atlas, or a plain bordered board.
---------------------------------------------------------------------------
local function NineSlice(parent, L)
	local S = ns.STD.board
	local u0, u1, v0, v1 = unpack(L.strip)
	local du = (u1 - u0) / L.stripPx.w
	local dv = (v1 - v0) / L.stripPx.h
	local s = L.stripSlice
	local us = { u0, u0 + s.left * du, u1 - s.right * du, u1 }
	local vs = { v0, v0 + s.top * dv, v1 - s.bottom * dv, v1 }
	-- Cut lines across and down the board: corners keep their size, edges and middle stretch.
	local xs = { { "LEFT", 0 }, { "LEFT", S.left }, { "RIGHT", -S.right }, { "RIGHT", 0 } }
	local ys = { { "TOP", 0 }, { "TOP", -S.top }, { "BOTTOM", S.bottom }, { "BOTTOM", 0 } }
	local parts = {}
	for row = 1, 3 do
		for col = 1, 3 do
			local t = parent:CreateTexture(nil, "BACKGROUND")
			t:SetTexture(L.texture)
			t:SetTexCoord(us[col], us[col + 1], vs[row], vs[row + 1])
			t:SetPoint("TOPLEFT", parent, ys[row][1] .. xs[col][1], xs[col][2], ys[row][2])
			t:SetPoint("BOTTOMRIGHT", parent, ys[row + 1][1] .. xs[col + 1][1], xs[col + 1][2], ys[row + 1][2])
			parts[#parts + 1] = t
		end
	end
	return parts
end

local function PlainBoard(parent, L)
	local P = ns.STD.plainPad
	local edge = parent:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(L.metal[2][1], L.metal[2][2], L.metal[2][3], 1)
	local fill = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
	fill:SetPoint("TOPLEFT", P.border, -P.border)
	fill:SetPoint("BOTTOMRIGHT", -P.border, P.border)
	fill:SetColorTexture(1, 1, 1, 1)
	fill:SetGradient("VERTICAL", CreateColor(0.05, 0.04, 0.03, 1), CreateColor(0.13, 0.10, 0.07, 1))
	return { edge, fill }
end

---------------------------------------------------------------------------
-- Slots
---------------------------------------------------------------------------
local pool = {}

-- Time left as Blizzard's own aura buttons show it (Blizzard_AuraContainerShared.lua, forever branch):
-- "45s", "12m", "2h", seconds up to 90 s. A binding without a formatter shows no time at all.
local formatter
local function Formatter()
	if formatter == nil then
		formatter = false
		local ok, fmt = pcall(function()
			local curve = C_CurveUtil.CreateCurve()
			curve:SetType(Enum.LuaCurveType.Step)
			curve:AddPoint(0, Enum.SecondsFormatterInterval.Seconds)
			curve:AddPoint(1 + 1.5 * 60, Enum.SecondsFormatterInterval.Minutes)
			curve:AddPoint(1 + 1.5 * 3600, Enum.SecondsFormatterInterval.Hours)
			curve:AddPoint(1 + 1.5 * 86400, Enum.SecondsFormatterInterval.Days)
			local f = C_StringUtil.CreateSecondsFormatter()
			f:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.OneLetter)
			f:SetRounding(Enum.SecondsFormatterRounding.Truncate)
			f:SetCanRoundUpLastUnit(true)
			f:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
			f:SetMaxIntervalCurve(curve)
			f:SetDesiredUnitCount(1)
			if Enum.SecondsFormatterIntervalWhitespace and f.SetStripIntervalWhitespace then
				f:SetStripIntervalWhitespace(Enum.SecondsFormatterIntervalWhitespace.Strip)   -- "12m", not "12 m"
			end
			return f
		end)
		if ok and fmt then formatter = fmt end
	end
	return formatter
end

-- Aura text sizes scale with the frame (ns.TextSize, capped to fit a 40 px icon).
local function SlotFonts(slot)
	ns.StyleFont(slot.stack, ns.NUM_FONT, ns.auraStackSize or 15)
	ns.StyleFont(slot.time, ns.NUM_FONT, ns.auraTimeSize or 13)
end

local function NewSlot(board)
	local slot = table.remove(pool)
	if not slot then
		slot = CreateFrame("Frame", nil, board.frame)
		slot.border = slot:CreateTexture(nil, "ARTWORK")
		slot.icon = slot:CreateTexture(nil, "ARTWORK", nil, 1)
		slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		slot.stack = ns.Font(slot, "OVERLAY", ns.NUM_FONT, 15)
		slot.time = ns.Font(slot, "OVERLAY", ns.NUM_FONT, 13)
		slot.time:SetTextColor(0.95, 0.9, 0.8)
		if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
			slot.binding = C_DurationUtil.CreateDurationTextBinding()
			slot.binding:SetFontString(slot.time)
			local fmt = Formatter()
			if fmt then slot.binding:SetFormatter(fmt) end
		end
		-- Fixed to the slot, so set once; LayoutBoard only moves and sizes the slot.
		slot.border:SetPoint("TOPLEFT", -2, 2); slot.border:SetPoint("BOTTOMRIGHT", 2, -2)
		slot.icon:SetAllPoints()
		slot.stack:SetPoint("BOTTOMRIGHT", 4, -3)
		slot.time:SetPoint("TOP", slot, "BOTTOM", 0, -ns.STD.timerGap)
	end
	SlotFonts(slot)
	slot:SetParent(board.frame)
	slot:SetFrameLevel(board.frame:GetFrameLevel() + 2)
	slot.p, slot.target = 0, 1
	slot.ax, slot.ay, slot.sz, slot.a = nil, nil, nil, nil   -- last placement (LayoutBoard skips repeats)
	slot:SetAlpha(0)
	slot:Show()
	return slot
end

local function FreeSlot(slot)
	slot:Hide()
	if slot.binding then slot.binding:SetEnabled(false) end
	slot.id = nil
	pool[#pool + 1] = slot
end

-- Nothing left over from the aura a pooled slot showed before.
local function ClearSlot(slot)
	slot.timed = false
	slot.icon:SetTexture(nil)
	slot.stack:SetText("")
	slot.time:SetText("")
	if slot.binding then slot.binding:SetEnabled(false) end
end

local function FillSlot(board, slot, unit, id)
	local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
	if not ok or not data then ClearSlot(slot) return end
	slot.icon:SetTexture(data.icon)
	local c = ns.COLORS.auraBorder.none
	if board.side == "R" then
		c = ns.COLORS.auraBorder.buff
	else
		local dispel = data.dispelName
		if not Secret(dispel) and dispel ~= nil and ns.COLORS.auraBorder[dispel] then c = ns.COLORS.auraBorder[dispel] end
	end
	slot.border:SetColorTexture(c[1], c[2], c[3], 1)
	local okCount, count = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2, 99)
	if okCount then slot.stack:SetText(count) else slot.stack:SetText("") end
	if slot.binding then
		local okDur, dur = pcall(C_UnitAuras.GetAuraDuration, unit, id)
		-- IsZero may be secret for a restricted aura: then show the binding and keep the row.
		local zero
		if okDur and dur then zero = dur:IsZero() end
		if okDur and dur and (Secret(zero) or not zero) then
			slot.binding:SetDuration(dur)
			slot.binding:SetEnabled(true)
			slot.timed = true
		else
			slot.binding:SetEnabled(false); slot.time:SetText("")
			slot.timed = false
		end
	end
end

---------------------------------------------------------------------------
-- Boards
---------------------------------------------------------------------------
local boards = {}
ns.boards = boards

local function NewBoard(side, length)
	local f, L = ns.frame, ns.L
	local b = { side = side, slots = {}, byId = {}, th = 0, w = 0, L = length, sign = side == "L" and 1 or -1, alpha = 0 }
	b.frame = CreateFrame("Frame", nil, f.boardLayer)
	b.frame:SetFrameLevel(f.boardLayer:GetFrameLevel() + 2)
	b.frame:SetSize(104, 120)
	b.ornate = NineSlice(b.frame, L)
	b.plain = PlainBoard(b.frame, L)
	b.chains = {}
	for i = 1, 2 do
		local t = f.boardLayer:CreateTexture(nil, "ARTWORK")
		t:SetTexture(L.chain, "CLAMP", "REPEAT")
		t:SetWidth(14)
		b.chains[i] = t
	end
	b.more = ns.Font(b.frame, "OVERLAY", ns.NAME_FONT, 22)
	b.more:SetText("\226\128\166")   -- ellipsis
	b.more:SetTextColor(0.95, 0.85, 0.6)
	b.more:Hide()
	return b
end

function ns:BuildBoards()
	boards.L = NewBoard("L", 118)
	boards.R = NewBoard("R", 134)
	ns:ApplyBoardStyle()
end

function ns:ApplyBoardStyle()
	local under = ns.db.boards == "under"
	for _, b in pairs(boards) do
		for _, t in ipairs(b.ornate) do t:SetShown(not under) end
		for _, t in ipairs(b.plain) do t:SetShown(under) end
		for _, t in ipairs(b.chains) do t:SetShown(not under) end
		b.tops, b.fx, b.fy, b.fw, b.fh = nil, nil, nil, nil, nil
		for _, t in ipairs(b.chains) do t.at = nil end
		-- Right under the bar, the boards lie over the art; on chains they hang behind the plate.
		b.frame:SetFrameLevel(under and (ns.frame:GetFrameLevel() + 7) or (ns.frame.boardLayer:GetFrameLevel() + 2))
		ns.StyleFont(b.more, ns.NAME_FONT, ns.TextSize(1.6, 30))
	end
	-- Aura text scales with the frame; the timer row under the icons fits its font.
	ns.auraStackSize, ns.auraTimeSize = ns.TextSize(1, 22), ns.TextSize(0.9, 20)
	ns.timerH = ns.auraTimeSize - 3
	for _, b in pairs(boards) do for _, slot in ipairs(b.slots) do SlotFonts(slot) end end
	for _, slot in ipairs(pool) do SlotFonts(slot) end
end

-- Reads the unit's auras into each board; new ones ease in, gone ones ease out.
function ns:RefreshAuras(reset)
	local unit = ns.unit
	for side, b in pairs(boards) do
		if reset then
			for _, slot in ipairs(b.slots) do FreeSlot(slot) end
			wipe(b.slots); wipe(b.byId)
		end
		local seen = {}
		if unit and C_UnitAuras and C_UnitAuras.GetUnitAuraInstanceIDs then
			local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, FILTERS[side], MAX_AURAS)
			if ok and ids then
				for _, id in ipairs(ids) do
					seen[id] = true
					local slot = b.byId[id]
					if not slot then
						slot = NewSlot(b)
						slot.id = id
						b.byId[id] = slot
						b.slots[#b.slots + 1] = slot
						if reset then slot.p = 1 end
					end
					slot.target = 1
					FillSlot(b, slot, unit, id)
				end
			end
		end
		for id, slot in pairs(b.byId) do
			if not seen[id] then slot.target = 0; b.byId[id] = nil end
		end
	end
end

---------------------------------------------------------------------------
-- Layout, chains and swing (every frame while the frame shows)
---------------------------------------------------------------------------
local GRAVITY, DAMP, GAIN, LIMIT = 2000, 2.3, 0.55, math.rad(8)
local lastFacing, gaitPhase, turnLean, wasMoving = nil, 0, 0, false

local function Swing(dt)
	local on = ns.db.swing and ns.db.boards ~= "under"
	if not on then
		for _, b in pairs(boards) do b.th, b.w = 0, 0 end
		return
	end
	local moving = IsPlayerMoving and IsPlayerMoving() or false
	if moving ~= wasMoving then
		for _, b in pairs(boards) do b.w = b.w + b.sign * (moving and 0.5 or -0.35) * GAIN end
		wasMoving = moving
	end
	gaitPhase = gaitPhase + dt * (moving and 2 * math.pi * 1.7 or 0)
	local facing = GetPlayerFacing and GetPlayerFacing()   -- nil in instances: sway on movement only
	local turn = 0
	if facing and lastFacing then
		local d = facing - lastFacing
		if d > math.pi then d = d - 2 * math.pi elseif d < -math.pi then d = d + 2 * math.pi end
		turn = math.max(-1, math.min(1, d / math.max(dt, 0.001) / 3))
	end
	lastFacing = facing
	turnLean = turnLean + (turn - turnLean) * math.min(1, dt * 6)
	if turn == 0 and math.abs(turnLean) < 1e-3 then turnLean = 0 end
	for _, b in pairs(boards) do
		local ax = turnLean * -380
		if moving then ax = ax + math.sin(gaitPhase + (b.sign > 0 and 0 or 1.3)) * 900 end
		ax = ax * GAIN
		local acc = -(GRAVITY / b.L) * math.sin(b.th) - DAMP * b.w - (ax / b.L) * math.cos(b.th)
		b.w = b.w + acc * dt
		b.th = b.th + b.w * dt
		if math.abs(b.th) > LIMIT then b.th = (b.th > 0 and LIMIT or -LIMIT); b.w = b.w * -0.3 end
		-- Settle exactly at rest, so the layout stops changing (and stops re-anchoring).
		if not moving and math.abs(b.th) < 1e-4 and math.abs(b.w) < 1e-3 and math.abs(turnLean) < 1e-3 then b.th, b.w = 0, 0 end
	end
end

-- Eases a toward b and lands on it exactly once close.
local function Ease(a, b, k, eps)
	a = a + (b - a) * k
	if math.abs(b - a) < eps then return b end
	return a
end

local ROT_PIVOT = CreateVector2D(0.5, 0)   -- chains turn about their top
local PAD = {}                              -- board padding per style, built once
local function Pad(under)
	local key = under and "under" or "chains"
	if not PAD[key] then
		local S = ns.STD
		PAD[key] = under and { top = S.plainPad.top + S.plainPad.border, bottom = S.plainPad.bottom + S.plainPad.border, side = S.plainPad.side + S.plainPad.border }
			or { top = S.board.top + S.boardPad.top, bottom = S.board.bottom + S.boardPad.bottom, side = S.board.left + S.boardPad.side }
	end
	return PAD[key]
end

-- Placement helpers that skip the widget call when nothing moved.
local function PlaceSlot(slot, frame, x, y, size, alpha)
	if x ~= slot.ax or y ~= slot.ay then slot:SetPoint("CENTER", frame, "TOPLEFT", x, -y); slot.ax, slot.ay = x, y end
	if size ~= slot.sz then slot:SetSize(size, size); slot.sz = size end
	if alpha ~= slot.a then slot:SetAlpha(alpha); slot.a = alpha end
end

local function LayoutBoard(b, dt)
	local f, L, S, db = ns.frame, ns.L, ns.STD, ns.db
	local under = db.boards == "under"

	-- Ease slots in and out; drop the ones that have faded away.
	local k = math.min(1, dt * 9)
	local live = 0
	for i = #b.slots, 1, -1 do
		local slot = b.slots[i]
		slot.p = Ease(slot.p, slot.target, k, 0.002)
		if slot.target == 0 and slot.p < 0.02 then
			table.remove(b.slots, i)
			FreeSlot(slot)
		elseif slot.target == 1 then
			live = live + 1
		end
	end

	-- Fade the whole board out when it's empty or the unit is dead; nothing more to do once it's gone.
	local want = (live > 0 and not ns.isDead) and 1 or 0
	b.alpha = Ease(b.alpha, want, math.min(1, dt * 6), 0.003)
	if b.alpha ~= b.shownAlpha then
		b.frame:SetAlpha(b.alpha)
		for _, t in ipairs(b.chains) do t:SetAlpha(b.alpha) end
		b.shownAlpha = b.alpha
	end
	if b.alpha == 0 and want == 0 then
		b.tops = nil   -- chains start from where they belong when the board comes back
		return
	end

	-- Lane: on chains it stops before the ornament below the plate; under the bar it may run to the ring.
	local lane = L[b.side == "L" and "laneL" or "laneR"]
	local laneA, laneB = lane[1], lane[2]
	if under then
		if b.side == "L" then laneB = L.cx - L.rOut - 8 else laneA = L.cx + L.rOut + 8 end
	end
	local B = Pad(under)
	local pad = 2 * B.side
	local cell = S.slot + S.slotGap
	local perRow = math.max(1, math.floor((laneB - laneA - pad) / cell))
	local capacity = perRow * db.maxRows

	-- Which slots show: the first (capacity - 1) plus an ellipsis when there are more than fit.
	local overflow = live > capacity
	local shown, n = overflow and (capacity - 1) or capacity, 0

	local rows, rowW, maxRowW, count, timed = 1, 0, 0, 0, false
	for _, slot in ipairs(b.slots) do
		local visible = true
		if slot.target == 1 then n = n + 1; visible = n <= shown end
		slot.visible = visible
		if visible and slot.timed then timed = true end
		if visible then
			if count == perRow then rows = rows + 1; rowW = 0; count = 0 end
			slot.row, slot.x = rows, rowW
			rowW = rowW + cell * slot.p
			if slot.target == 1 then count = count + 1 end
			maxRowW = math.max(maxRowW, rowW)
		end
	end
	local moreRow, moreX
	if overflow then
		if count == perRow then rows = rows + 1; rowW = 0 end
		moreRow, moreX = rows, rowW
		rowW = rowW + cell
		maxRowW = math.max(maxRowW, rowW)
	end

	-- Room for the time left under the icons only when something shown has one: no empty gap below.
	-- It eases in and out like the rest of the board.
	b.timerRow = Ease(b.timerRow or (timed and 1 or 0), timed and 1 or 0, math.min(1, dt * 9), 0.002)
	local rowH = S.slot + b.timerRow * (S.timerGap + (ns.timerH or S.timerH))
	local w = math.max(under and 60 or 104, maxRowW + pad)
	local h = B.top + B.bottom + rows * rowH + (rows - 1) * S.rowGap
	if w ~= b.fw or h ~= b.fh then b.frame:SetSize(w, h); b.fw, b.fh = w, h end

	-- Outer edge fixed at the lane end; swing moves the board level along its arc.
	local x0 = (b.side == "L") and laneA or (laneB - w)
	local hang = under and 0 or (S.chain + S.hook)
	local top = under and (L.plateB + S.underGap) or (L.pivotY - S.hook)
	local dx, dy = hang * math.sin(b.th), hang * math.cos(b.th)
	local fx, fy = x0 + dx, -(top + dy)
	if fx ~= b.fx or fy ~= b.fy then
		b.frame:SetPoint("TOPLEFT", f, "TOPLEFT", fx, fy)
		b.fx, b.fy = fx, fy
	end

	-- Slots, from the outer end inward (the right board fills right to left).
	for _, slot in ipairs(b.slots) do
		if slot.visible then
			local size = S.slot * (0.55 + 0.45 * slot.p)
			local cx = slot.x + cell * slot.p / 2
			local x = (b.side == "L") and (B.side + cx) or (w - B.side - cx)
			local y = B.top + (slot.row - 1) * (rowH + S.rowGap) + S.slot / 2
			PlaceSlot(slot, b.frame, x, y, size, slot.p)
		elseif slot.a ~= 0 then
			slot:SetAlpha(0); slot.a = 0
		end
	end
	if moreRow then
		local cx = moreX + cell / 2
		local x = (b.side == "L") and (B.side + cx) or (w - B.side - cx)
		b.more:SetPoint("CENTER", b.frame, "TOPLEFT", x, -(B.top + (moreRow - 1) * (rowH + S.rowGap) + S.slot / 2))
		b.more:Show()
	else
		b.more:Hide()
	end

	if under then return end
	-- Chains: the outer one never moves; with one aura the inner one joins it, so a single aura hangs
	-- centred under one chain. Their tops slide along the plate first and the board's edge follows,
	-- so a moving chain leans briefly and then hangs straight.
	local ci = S.chainIn
	local one = live <= 1
	local outer = (b.side == "L") and (laneA + ci) or (laneB - ci)
	local targetW = math.max(104, math.min(live, perRow) * cell + pad)
	local tx0 = (b.side == "L") and laneA or (laneB - targetW)
	local innerTop = one and outer or ((b.side == "L") and (tx0 + targetW - ci) or (tx0 + ci))
	local innerEnd = one and outer or ((b.side == "L") and (x0 + w - ci) or (x0 + ci))
	-- Chain 1 is the left one on both boards.
	local goal1, goal2, end1, end2
	if b.side == "L" then goal1, goal2, end1, end2 = outer, innerTop, outer, innerEnd
	else goal1, goal2, end1, end2 = innerTop, outer, innerEnd, outer end
	if not b.tops then b.tops, b.ends = { goal1, goal2 }, { end1, end2 } end
	local kt, ke = math.min(1, dt * 14), math.min(1, dt * 7)
	b.tops[1] = Ease(b.tops[1], goal1, kt, 0.05); b.tops[2] = Ease(b.tops[2], goal2, kt, 0.05)
	b.ends[1] = Ease(b.ends[1], end1, ke, 0.05); b.ends[2] = Ease(b.ends[2], end2, ke, 0.05)
	for i = 1, 2 do
		local t = b.chains[i]
		local tx, ex, ey = b.tops[i], (b.ends[i] + dx) - b.tops[i], dy
		if tx ~= t.at or ex ~= t.ex or ey ~= t.ey then
			local len = math.sqrt(ex * ex + ey * ey) + S.chainTail
			t:SetPoint("TOP", f, "TOPLEFT", tx, -top)
			t:SetHeight(len)
			t:SetTexCoord(0, 1, 0, len / 28)
			t:SetRotation(math.atan2(ex, ey), ROT_PIVOT)
			t.at, t.ex, t.ey = tx, ex, ey
		end
	end
end

function ns:TickBoards(dt)
	if not boards.L then return end
	Swing(dt)
	LayoutBoard(boards.L, dt)
	LayoutBoard(boards.R, dt)
end
