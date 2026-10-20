-- daves_frames / Cast.lua
-- The unit's cast, over the resource bar (Overlay) or in the strip above it (Stacked).
-- Cast times can be secret on Forever: start and end go straight into SetMinMaxValues and the bar
-- moves with SetValue(GetTime() * 1000), so no maths is done on them. The time left only shows when
-- the times are readable. "Can't be interrupted" is set with SetVertexColorFromBoolean /
-- SetAlphaFromBoolean, which accept a secret boolean.

local _, ns = ...

local function Secret(v) return issecretvalue and issecretvalue(v) end
-- A value is there: secret or not nil. Never test a possibly secret value with if / not / and / or.
local function Has(v) return Secret(v) or v ~= nil end

local function StillCasting(unit)
	return Has((UnitCastingInfo(unit))) or Has((UnitChannelInfo(unit)))
end

-- Cast GUIDs can be secret; when either one can't be read, assume it's the same cast.
local function SameCast(a, b)
	if Secret(a) or Secret(b) or a == nil or b == nil then return true end
	return a == b
end

local castColor, lockedColor
local function Colors()
	if not castColor then
		castColor = ns.Color(ns.COLORS.cast[2])
		lockedColor = ns.Color(ns.COLORS.castLocked[2])
	end
	return castColor, lockedColor
end

local function SetInterruptible(notInterruptible)
	local f = ns.frame
	local tex = f.cast:GetStatusBarTexture()
	local cast, locked = Colors()
	if Secret(notInterruptible) then
		tex:SetVertexColorFromBoolean(notInterruptible, locked, cast)
		f.castLock:SetAlphaFromBoolean(notInterruptible, 1, 0)
	else
		local c = notInterruptible and locked or cast
		tex:SetVertexColor(c.r, c.g, c.b)
		f.castLock:SetAlpha(notInterruptible and 1 or 0)
	end
end

local function ShowCastPieces(on)
	local f = ns.frame
	f.cast:SetShown(on)
	f.castName:SetShown(on); f.castTime:SetShown(on); f.castLock:SetShown(on)
	-- Overlay: the resource dims under the cast. Stacked: who they target shows when not casting.
	f.power:SetAlpha((on and not ns.Stacked()) and 0.38 or 1)
	f.tot:SetShown(not on and ns.Stacked())
end

function ns:RefreshCast()
	local f, unit = ns.frame, ns.unit
	if not unit then return end
	local name, _, _, startMs, endMs, _, castID, notInterruptible = UnitCastingInfo(unit)
	local channel = false
	if not Has(name) then
		name, _, _, startMs, endMs, _, notInterruptible = UnitChannelInfo(unit)
		channel, castID = true, nil
	end
	if not Has(name) then
		ns.cast = nil
		if not ns.castFinishing then ShowCastPieces(false) end
		return
	end
	ns.castFinishing = nil
	local finish
	if not Secret(endMs) then finish = endMs / 1000 end
	ns.cast = { channel = channel, castID = castID, finish = finish }
	f.cast:SetMinMaxValues(startMs, endMs)
	f.cast:SetValue(GetTime() * 1000)
	f.cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	SetInterruptible(notInterruptible)
	f.castName:SetText(name)
	f.castTime:SetText("")
	ShowCastPieces(true)
end

-- How a cast ended: "done" flashes gold, "cut" (interrupted or failed) flashes red with the word.
function ns:FinishCast(how)
	local f = ns.frame
	if not ns.cast then return end
	ns.cast = nil
	local mark = {}   -- this flash; a newer one (or a target change) replaces it
	ns.castFinishing = mark
	f.cast:SetMinMaxValues(0, 1); f.cast:SetValue(1)
	local tex = f.cast:GetStatusBarTexture()
	local c = how == "cut" and ns.COLORS.castCut or ns.COLORS.castDone
	tex:SetVertexColor(c[1], c[2], c[3])
	f.castLock:SetAlpha(0)
	if how == "cut" then f.castName:SetText(INTERRUPTED or "Interrupted") end
	f.castTime:SetText("")
	C_Timer.After(0.45, function()
		if ns.castFinishing == mark then
			ns.castFinishing = nil
			if not ns.cast then ShowCastPieces(false) end
		end
	end)
end

-- STOP / FAILED / INTERRUPTED of a cast (how: "done" or "cut"). Another spell's event (a second press
-- that fails while casting) is ignored: its GUID differs, or the unit is still casting.
function ns:CastEnded(how, castGUID)
	local cast = ns.cast
	if not cast or cast.channel or not SameCast(cast.castID, castGUID) then return end
	if StillCasting(ns.unit) then ns:RefreshCast() return end
	ns:FinishCast(how)
end

-- CHANNEL_STOP: interruptedBy is secret in combat, so then it's judged by timing: stopping well before
-- the scheduled end is a cut. With the times secret too it counts as done (never a false "Interrupted").
function ns:ChannelEnded(interruptedBy)
	local cast = ns.cast
	if not cast or not cast.channel then return end
	if StillCasting(ns.unit) then ns:RefreshCast() return end
	local cut
	if Secret(interruptedBy) then
		cut = cast.finish ~= nil and GetTime() < cast.finish - 0.25
	else
		cut = interruptedBy ~= nil and interruptedBy ~= ""
	end
	ns:FinishCast(cut and "cut" or "done")
end

-- A quiet stop: the cast went away without its end event (the unit ran out of range, say).
local function DropCast()
	ns.cast = nil
	if not ns.castFinishing then ShowCastPieces(false) end
end

function ns:TickCast()
	local cast = ns.cast
	if not cast then return end
	if not ns.unit then DropCast() return end
	local f = ns.frame
	local now = GetTime()
	f.cast:SetValue(now * 1000)
	if cast.finish then f.castTime:SetFormattedText("%.1f", math.max(0, cast.finish - now)) end
	-- Safety stop if the end event never comes; works with secret times too.
	if now >= (cast.nextCheck or 0) then
		cast.nextCheck = now + 0.2
		if not StillCasting(ns.unit) then
			if cast.finish and now > cast.finish then ns:FinishCast("done") else DropCast() end
		end
	end
end

function ns:SetCastInterruptible(notInterruptible)
	if ns.cast then SetInterruptible(notInterruptible) end
end
