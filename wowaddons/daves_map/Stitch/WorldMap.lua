--------------------------------------------------------------------------------
-- OpenMap: Blizzard's world map (quest log, controls, Questie) with every
-- zone stitched into one canvas (ns.MapStitch). More map helpers are in
-- Extras.lua, Flights.lua, Townsfolk.lua, Panel.lua, Paint.lua and Gamepad.lua.
--
-- On the world, continent and zone maps:
--   * the stitched art is a layer just above Blizzard's map art, under its pins
--   * zoom runs from the whole world down to street level, anchored at the cursor
--   * panning runs past the map's edge into its neighbours
--   * once the view settles, the map underneath quietly becomes the zone (or
--     continent) you're looking at, so quest areas, coordinates and the zone
--     name always match what's on screen
--   * left-click zooms into the place under the cursor, right-click out a level
-- Other maps (dungeons, battlegrounds) behave as Blizzard made them.
--------------------------------------------------------------------------------

-- (daves_map: OpenMap's isolated sub-namespace created in Base.lua)
local ns = select(2, ...).OM
if not ns then return end
local S = ns.MapStitch
local WORLD = S.WORLD

local mod = ns:NewModule("worldmap", {
	defaults = {
		enabled = true,
		autoSwitch = true,      -- the map underneath follows what you're looking at
		hoverHighlight = false, -- Blizzard's glow on the zone under the cursor (on the stitched map)
		icons = true,            -- dungeon and raid entrances (Dungeons.lua)
		dungeonIconsOn = true,   -- (daves_map: marks fresh saves as already migrated to icons = true)
		boats = false,           -- boat docks and routes
		zeppelins = false,       -- zeppelin towers (Horde's) and routes
		flight = false,
		hideWorldPinsInInstances = false,
		playerArrow = true,     -- your own arrow on the world map (off: find your way old-school; the party still shows)
		iconsFrom = 0,          -- the places' icons from this zoom (ICONS_FROM; 1: the whole world); 0: each from its own (Auto)
		iconScale = 1,          -- OpenMap's icons at this times their own size (ICON_SCALE)
		brightness = 1,         -- brightness of the whole stitched map; icons keep their own colour
		darkening = 1,          -- how dark darkened unexplored areas are (0..1 of the full shade)
		darkenColor = false,    -- their shade's colour, { r, g, b } (false: the game-like dark one)
		routes = false,         -- boat and zeppelin routes
		foundOnly = false,      -- dungeons, docks and towers only once explored there; flight masters once learned
		colorMatch = 1,         -- how far zone borders move to the shared palette
		desaturate = 0.1,
		unexplored = "show",    -- areas not explored yet: "show", "dim" or "hide"
		gapFills = false,        -- the gaps between zones painted by hand (art/drawn/gaps)
		maxZoom = 48 * (ns.ClientMaps and ns.ClientMaps.zoom or 1),   -- x the whole-world view (MAX_ZOOM: what it can
		                        --  be set to; a world of smaller zones goes as much further: Data\<client>\Client.lua)
		chart = false,          -- Santiago Reyes's sea chart round the world (Chart.lua)
		padMap = false,         -- OpenMap's map with the Gamepad UI on too (Gamepad.lua binds B and full screen; a test)
		padView = false,        -- with the Gamepad UI on, OpenMap's map over Blizzard's on a frame of its own (PadView.lua; a test)
	},
})

-- (dungeons, boats and zeppelins were one switch, `icons`: an old save's choice carried to each)
function mod.Migrate(db)
	if db.boats == nil and db.icons ~= nil then db.boats, db.zeppelins = db.icons, db.icons end
	-- (friends and guild were one switch too, `friends`, and its menu row's id: the friends row keeps
	-- that id, and a save's single choice carries to the guild's switch too)
	if db.guild == nil then db.guild = db.friends end
	-- ("Fade icons while zooming" off from v0.8.6, once for every save: the defaults were written into each
	-- save, so one never touched has it on all the same; turned on again after this, it stays on)
	if not db.zoomHidePinsOff then db.zoomHidePins, db.zoomHidePinsOff = false, true end
	-- (Soften and paper grain off from v0.8.10, once for every save: its blur rests while the map moves, so the
	-- map went soft each time it stopped, which players took for the map going blurry; turned on again, it stays)
	if not db.softenOff then db.soften, db.softenOff = false, true end
	-- (the dungeon's map's tab beside the quest log isn't kept from v0.8.10: always your quests first)
	db.dungeonDockTab = nil
	-- (daves_map: dungeon maps & entrance portals enabled once on existing saves from before 0.5.8)
	if not db.dungeonIconsOn then db.icons, db.dungeonIconsOn = true, true end
	-- (daves_map: default the floating Bosses overlay off once on existing saves now that boss/rare markers render directly on the map)
	if not db.bossListDefaultOff then db.dungeonBossList, db.bossListDefaultOff = false, true end
end

local ICONS_FROM = { 0, 20, 0.5 }   -- iconsFrom's least (0: Auto), most, step (zoom: times the whole-world view)
mod.ICONS_FROM = ICONS_FROM
local ICON_SCALE = { 0.6, 2, 0.05 } -- iconScale's least, most, step
mod.ICON_SCALE = ICON_SCALE

local ZOOM_STEP = 1.25          -- each wheel notch
local MAX_ZOOM = { 16, 192, 8 } -- the deepest zoom's setting: least, most, step (the minimap's own detail runs out
                                --  near 48; past it the painted map and the minimap are only enlarged)
mod.MAX_ZOOM = MAX_ZOOM
local ENTER, LEAVE = 0.9, 0.7   -- switch into a map at this share of its fit zoom; leave it below that
local ART_RANGE = 80            -- frame levels the stitched art needs
local PLAYER_ABOVE = 8500       -- the player's arrow: this many levels over the view, over every icon (Questie's,
                                --  lifted over the art, and other addons' at fixed levels), under a dungeon's map (+8800)

local map, sc
local active = false            -- the current map is stitched
local switching = false         -- we're changing the map ourselves
local userMoved = false         -- the view moved since Blizzard last showed a map (only then do we follow it)
local wheelMode, scalingMode    -- Blizzard's, to put back on other maps
local levelCount                -- how many zoom levels are ours (other addons add steps past them: trimmed)

--------------------------------------------------------------------------------
-- Geometry: "zoom" 1 = the whole world fits the view
--------------------------------------------------------------------------------

local function Stitchable(mapID)
	if not mapID then return false end
	if mapID == WORLD then return true end
	local info = C_Map.GetMapInfo(mapID)
	if not info then return false end
	if info.mapType ~= Enum.UIMapType.Continent and info.mapType ~= Enum.UIMapType.Zone then return false end
	return S.Rect(mapID) ~= nil and S.ArtSize(mapID) ~= nil and S.Stitched(mapID, true)   -- (a client's own list: Stitch.lua)
end

-- view px per world unit when the whole world fits
local function FitPx()
	local W, H = S.Size()
	return math.min(sc:GetWidth() / W, sc:GetHeight() / H)
end

-- the least zoom: the whole world fits the view (1), or with the sea chart, the chart does (further out)
local function LeastZoom()
	return S.Chart and S.Chart.on and S.Chart.LeastZoom(sc:GetWidth(), sc:GetHeight(), FitPx()) or 1
end

-- host canvas units per world unit
local function K(mapID)
	local W = S.Size()
	local l, r = S.Rect(mapID)
	return S.ArtSize(mapID) / ((r - l) * W)
end

local function ZoomFor(mapID, scale) return scale * K(mapID) / FitPx() end

-- the zoom the layers fade by (Stitch.lua's S.SetZoom, Close.lua's S.SetView): by how much of the
-- world is in view, its area, not how far it is from fitting it. A view the world map's shape (3:2)
-- is the same; a tall one (or a very wide one) fits the world across its narrow side and shows much
-- more of it the other way, so at the same zoom the zones would come in while it still shows a
-- continent's worth of map. On a world of smaller zones (retail's twelve continents) by as much less
-- (ns.ClientMaps.zoom), so each layer comes in on a zone the size it does on WoW Forever's
local function DetailK()
	local W, H = S.Size()
	local w, h = sc:GetWidth(), sc:GetHeight()
	local k = ns.ClientMaps and ns.ClientMaps.zoom or 1
	if not W or w <= 0 or h <= 0 then return 1 / k end
	return math.min(w / W, h / H) / math.sqrt(w * h / (W * H)) / k
end
local function ScaleFor(mapID, zoom) return zoom * FitPx() / K(mapID) end

-- the zoom at which `mapID` just fits the view
local function FitZoom(mapID)
	local W, H = S.Size()
	local l, r, t, b = S.Rect(mapID)
	local z = math.min(sc:GetWidth() / ((r - l) * W), sc:GetHeight() / ((b - t) * H)) / FitPx()
	return ns.Safe.Finite(z) and z > 0 and z or 1                 -- (the map 0 px across yet: 0 / 0)
end

-- world point (normalized) <-> the current map's normalized point
local function ToWorld(mapID, x, y)
	local l, r, t, b = S.Rect(mapID)
	return l + x * (r - l), t + y * (b - t)
end
local function FromWorld(mapID, u, v)
	local l, r, t, b = S.Rect(mapID)
	return (u - l) / (r - l), (v - t) / (b - t)
end

-- the view: world centre (normalized) and zoom
local function View()
	local mapID = map:GetMapID()
	local x, y = sc:GetCurrentScrollX() or 0.5, sc:GetCurrentScrollY() or 0.5
	if not ns.Safe.Finite(x, y) then x, y = 0.5, 0.5 end          -- (a scroll left NaN: the map's middle, #261)
	local u, v = ToWorld(mapID, x, y)
	local zoom = ZoomFor(mapID, sc:GetCanvasScale())
	if not ns.Safe.Finite(zoom) or zoom <= 0 then zoom = 1 end    -- (the map 0 px across yet)
	return u, v, zoom
end

-- puts the view at once (Blizzard's InstantPanAndZoom drifts the pan toward the old one)
local openStart, Part             -- (timing an opening: below)

-- the Lua garbage each part makes (KB, added up), for the debug overlay (Debug.lua): counted
-- only while it's on. (A collection during a part makes it read low, never high)
local garbage = {}
mod.garbage = garbage
local function Before() return mod.db.debugOverlay and collectgarbage("count") or nil end
local function After(name, before)
	if not before then return end
	local d = collectgarbage("count") - before
	if d > 0 then garbage[name] = (garbage[name] or 0) + d end
end
local BLOB_PINS = { "QuestBlobPinTemplate", "ScenarioBlobPinTemplate", "BonusObjectiveBlobPinTemplate" }
-- /openmap bench (Bench.lua): each part's time, added up while it runs (S.bench, ms)
local function Clock() return S.bench and debugprofilestop and debugprofilestop() end
local function Clocked(name, t0)
	if t0 and S.bench then S.bench[name] = (S.bench[name] or 0) + debugprofilestop() - t0 end
end

-- In combat the canvas holds a protected pin (the group members'), so a scale or scroll set on it from
-- OpenMap's code can be refused. The view is then laid out at what the canvas kept: the art, every
-- addon's icons and the zoom levels picked from it all agree (with the scale it was told and not the
-- one it has, the art was laid out for one and drawn at the other: stretched, half missing). The view
-- asked for waits, and is put up as combat ends (mod.FlushWaitingView)
local waitingView                 -- { mapID, scale, x, y }: a view the canvas refused in combat
local viewOwner = {}              -- (its event handler's key)
local function Kept(want, have) return have and math.abs(have - want) > math.max(1e-3, math.abs(want) * 1e-3) end
local function SetView(scale, x, y)
	-- (never a view that isn't one: NaN or a zero scale, from a size of 0 while the map is laid out, stuck
	-- the map on a blank view, every later view worked out from it NaN too: #260 #261 #263)
	if not ns.Safe.Finite(scale, x, y) or scale <= 0 then return end
	local wantScale, wantX, wantY = scale, x, y
	sc.currentScale, sc.targetScale, sc.zoomTarget = scale, scale, scale
	sc.Child:SetScale(scale)
	local fight, refused = InCombatLockdown(), false
	if fight and Kept(scale, sc.Child:GetScale()) then
		scale = sc.Child:GetScale()
		sc.currentScale, sc.targetScale, sc.zoomTarget = scale, scale, scale
		refused = true
	end
	sc:CalculateScrollExtents()
	x = Clamp(x, sc.scrollXExtentsMin, sc.scrollXExtentsMax)
	y = Clamp(y, sc.scrollYExtentsMin, sc.scrollYExtentsMax)
	sc.targetScrollX, sc.targetScrollY, sc.currentScrollX, sc.currentScrollY = x, y, x, y
	sc:SetNormalizedHorizontalScroll(x)
	sc:SetNormalizedVerticalScroll(y)
	if fight then
		-- (the scroll refused too: the view follows where the canvas is)
		local hx, hy = sc:GetNormalizedHorizontalScroll(), sc:GetNormalizedVerticalScroll()
		if Kept(x, hx) or Kept(y, hy) then
			x, y = hx, hy
			sc.targetScrollX, sc.targetScrollY, sc.currentScrollX, sc.currentScrollY = x, y, x, y
			refused = true
		end
	end
	waitingView = refused and { mapID = map:GetMapID(), scale = wantScale, x = wantX, y = wantY } or nil
	local start = openStart and debugprofilestop and debugprofilestop()
	local g, t0 = Before(), Clock()
	map:OnCanvasScaleChanged()
	After("pins (all addons)", g)
	Clocked("every addon's pins rescaled", t0)
	if start then Part("icons rescaled (all addons)", debugprofilestop() - start) end
	-- Blizzard's quest areas (blobs) redraw for a new scale in their own next OnUpdate, which can
	-- come before this in the next frame: a frame behind all through a zoom. Redrawn now, each one's
	-- place on screen worked out first (GetRect: the game otherwise works it out only when it next lays
	-- the frames out, and an area drawn from the last step's place trailed the zoom and sprang back)
	g, t0 = Before(), Clock()
	sc.Child:GetRect()
	for _, template in ipairs(BLOB_PINS) do
		for pin in map:EnumeratePinsByTemplate(template) do
			if pin:IsShown() and pin.Refresh then
				pin:GetRect()
				pin:Refresh()
			end
		end
	end
	After("quest areas", g)
	Clocked("quest areas", t0)
	sc:MarkAreaTriggersDirty()
	sc:MarkViewRectDirty()
end

-- the view centred on a world point (normalized) at `zoom`, at once
local function ShowWorld(u, v, zoom)
	local mapID = map:GetMapID()
	local x, y = FromWorld(mapID, u, v)
	SetView(ScaleFor(mapID, zoom), x, y)
end

--------------------------------------------------------------------------------
-- Zoom animation. Ours, not Blizzard's: Blizzard eases zoom and pan separately
-- (the point under the cursor zigzags) and won't pan while zooming out. Each
-- frame we work out the view exactly, so the point under the cursor stays put,
-- and a drag mid-zoom just carries that point with the cursor.
--   anchor: wheel zoom about a world point held at a view offset
--   glide:  click zoom from one view to another, as one zoom about a fixed point
--------------------------------------------------------------------------------

local ZOOM_RATE = 14            -- the wheel zoom's approach, per second (in log zoom)
local GLIDE_TIME = 0.4
local anim                      -- the running animation, or nil

-- the gamepad's cursor on the map (Blizzard's SoftCursor, in gamepad mode), in screen px as
-- GetCursorPosition: while it's what's in use. That's from when it shows or moves until the
-- mouse moves over the map (as Blizzard's own map labels judge it); nil otherwise
local padX, padY                -- the mouse when the pad's cursor showed or last moved
local padTilt = 0               -- the zoom stick's tilt as last read (PadStickTilt), -1 to 1
local function PadFocus()
	local soft = _G.SoftCursor
	if not (soft and soft:IsShown() and InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()) then
		return false
	end
	-- (Blizzard keeps its cursor up while the pad is on the quest log, to come back to: it's the map's
	-- only while the map has the pad, as Blizzard's own IsCanvasGamepadFocus judges it)
	return not (map and map.IsCanvasGamepadFocus) or map:IsCanvasGamepadFocus() and true or false
end
local function PadCursor()
	if not PadFocus() then padX = nil return end
	local soft = _G.SoftCursor
	local mx, my = GetCursorPosition()
	if not padX or soft:IsMoving() or (sc.gamepadZoom or 0) ~= 0 or padTilt ~= 0 then
		padX, padY = mx, my
	elseif (mx ~= padX or my ~= padY) and sc:IsMouseOver() then
		return
	end
	local l, b, w, h = soft:GetRect()
	if not l then return end
	local es = soft:GetEffectiveScale()
	return (l + w / 2) * es, (b + h / 2) * es
end

-- Blizzard puts the gamepad's cursor back in the middle of the map whenever the canvas changes
-- (its scroll container's OnCanvasSizeChanged: RefreshBounds, ResetPosition). OpenMap changes the
-- map underneath as you look round (and lays the canvas out again), so the cursor is put back where
-- it was, as the cursor places itself (SoftCursorMixin:OnUpdate), within its new bounds
local function KeepPadCursor(fn, ...)
	local soft = _G.SoftCursor
	local x, y
	if soft and soft:IsShown() then x, y = soft:GetCenter() end
	local a, b = fn(...)
	if x and soft:IsShown() then
		if soft.bounds and soft.bounds.ClampPointInBounds then x, y = soft.bounds:ClampPointInBounds(x, y) end
		soft:ClearAllPoints()
		soft:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	end
	return a, b
end
mod.KeepPadCursor = KeepPadCursor

-- in combat in the gamepad's UI: a map change of OpenMap's then would have Blizzard set the map's
-- gamepad bindings again (its footer, OnMapChanged) from OpenMap's code, which the game blocks in
-- combat, leaving the pad's buttons wrong. Such changes wait (Dungeons.lua)
function mod.PadCombat()
	return InCombatLockdown() and InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end

-- the game's Gamepad UI is on (its controller mode)
local function PadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() and true or false
end
mod.PadUI = PadUI

-- the cursor in view px from the view's centre (y down)
local function CursorOffset()
	local x, y = PadCursor()
	if not x then x, y = GetCursorPosition() end
	local es = sc:GetEffectiveScale()
	return x / es - (sc:GetLeft() + sc:GetWidth() / 2), (sc:GetTop() - sc:GetHeight() / 2) - y / es
end

-- world units (normalized) per view px at `zoom`
local function PerPx(zoom)
	local W, H = S.Size()
	local px = FitPx() * zoom
	return 1 / (W * px), 1 / (H * px)
end

-- the deepest zoom at (u, v): further in a city, whose map is small (its own map, and outdoors
-- the minimap, carry the detail there)
local CITY_ZOOM = 1.5
-- and over a cave or a dungeon's entrance area (Close.lua), on in till its map fills this much of the
-- view: past the deepest zoom, which leaves most caves a speck (their map is drawn finer than the
-- land's), though in step with it (a low setting stays lower) and no deeper than a city's goes at the
-- deepest setting
local CAVE_FILL = 0.9
local CAVE_DEEPER = 6
local CAVE_ZOOM_MOST = MAX_ZOOM[2] * CITY_ZOOM
local function MaxZoomAt(u, v)
	local most = mod.db.maxZoom * ((u and S.InCity and S.InCity(u, v)) and CITY_ZOOM or 1)
	if u and S.CaveRectAt then
		local u0, v0, u1, v1 = S.CaveRectAt(u, v)
		if u0 then
			local W, H = S.Size()
			local fit = math.min(sc:GetWidth() / ((u1 - u0) * W), sc:GetHeight() / ((v1 - v0) * H)) / FitPx()
			most = math.max(most, math.min(CAVE_ZOOM_MOST, mod.db.maxZoom * CAVE_DEEPER, fit * CAVE_FILL))
		end
	end
	return most
end

-- wheel: zoom about the point under the cursor (zooming in never takes it out: deep over a cave,
-- with the cursor moved off it)
local function ZoomAtCursor(factor)
	local u, v, zoom = View()
	local sx, sy = CursorOffset()
	local pu, pv = PerPx(zoom)
	local from = anim and anim.mode == "anchor" and anim.target or zoom
	local most = MaxZoomAt(u + sx * pu, v + sy * pv)
	if factor > 1 then most = math.max(most, from) end
	local target = Clamp(from * factor, LeastZoom(), most)
	anim = { mode = "anchor", u = u + sx * pu, v = v + sy * pv, sx = sx, sy = sy, target = target }
	userMoved = true
end

-- glides the view to a world point (normalized) at `zoom`
local function GlideTo(u, v, zoom)
	local u0, v0, z0 = View()
	anim = { mode = "glide", u0 = u0, v0 = v0, z0 = z0, u1 = u, v1 = v,
		z1 = Clamp(zoom, LeastZoom(), MaxZoomAt(u, v)), t = 0 }
	userMoved = true
end

-- (daves_map) flies the view to a world point at `zoom`: out while it moves, then in on the target, on van Wijk
-- and Nuij's smooth zoom-and-pan path (d3's interpolateZoom), the one that keeps the apparent speed steady. Worked
-- in world px (u * W, v * H) with the view's width as the zoom, as the path needs one scale both ways. How far out
-- it goes (rho) is chosen from the distance first: d3's sqrt 2 when there's room, less on a long hop, so the widest
-- view on the way stays inside the whole-world view (at that floor the zoom would stall while the centre moved on)
local FLY_RHO = { 0.25, 1.42 }  -- how far out it goes on the way: least, most (sqrt 2: d3's)
local FLY_ROOM = 0.9            -- the widest view on the way, of the whole-world view's width
local FLY_TIME = { 0.6, 1.6 }   -- seconds, shortest and longest
local FLY_PACE = 0.42           -- seconds per unit of path (the path's length in its own measure, S * rho)
local Finite = ns.Safe.Finite
local function Asinh(x) if x < 0 then return -math.log(-x + math.sqrt(x * x + 1)) end return math.log(x + math.sqrt(x * x + 1)) end
local function Cosh(x) local e = math.exp(x) return (e + 1 / e) / 2 end
local function Sinh(x) local e = math.exp(x) return (e - 1 / e) / 2 end
local function Tanh(x) if x > 20 then return 1 elseif x < -20 then return -1 end local e = math.exp(2 * x) return (e - 1) / (e + 1) end

-- the path for one rho: r0 and its length S (in the rho measure), and the widest view on it
local function FlyPath(w0, w1, d1, rho)
	local r2 = rho * rho
	local b0 = (w1 * w1 - w0 * w0 + r2 * r2 * d1 * d1) / (2 * w0 * r2 * d1)
	local b1 = (w1 * w1 - w0 * w0 - r2 * r2 * d1 * d1) / (2 * w1 * r2 * d1)
	local r0, r1 = -Asinh(b0), -Asinh(b1)           -- (asinh, not log(sqrt(b*b+1) - b): no cancellation to 0 at large b)
	local widest = (r0 < 0 and r1 > 0) and w0 * Cosh(r0) or math.max(w0, w1)
	return r0, (r1 - r0) / rho, widest
end

local function FlyTo(u, v, zoom)
	local u0, v0, z0 = View()
	local z1 = Clamp(zoom, LeastZoom(), MaxZoomAt(u, v))
	local W, H = S.Size()
	local span = sc:GetWidth() / FitPx()             -- (the view's width in world px is span / zoom)
	if not (Finite(u0, v0, z0, span) and z0 > 0 and span > 0) then
		return GlideTo(u, v, zoom)                    -- (no view to start from yet: the map still being laid out)
	end
	local x0, y0, w0 = u0 * W, v0 * H, span / z0
	local dx, dy, w1 = u * W - x0, v * H - y0, span / z1
	local d1 = math.sqrt(dx * dx + dy * dy)
	local a = { mode = "fly", x0 = x0, y0 = y0, w0 = w0, dx = dx, dy = dy, W = W, H = H, span = span, t = 0,
		u1 = u, v1 = v, z1 = z1 }
	if d1 < 1e-3 * math.min(w0, w1) then             -- (a move under 0.1% of the view: a plain zoom)
		if math.abs(math.log(w1 / w0)) < 1e-3 then anim = nil ShowWorld(u, v, z1) userMoved = true return end   -- (nothing to fly)
		a.flat, a.rho = true, FLY_RHO[2]
		a.S = math.log(w1 / w0) / a.rho
	else
		-- the distance first: the most rho whose widest view fits (it widens with rho), halving in between
		local room = math.max(FLY_ROOM * span / LeastZoom(), w0, w1)
		local lo, hi = FLY_RHO[1], FLY_RHO[2]
		local r0, len, widest = FlyPath(w0, w1, d1, hi)
		if widest > room then
			for _ = 1, 12 do
				local mid = (lo + hi) / 2
				local m0, mlen, mw = FlyPath(w0, w1, d1, mid)
				if mw > room then hi = mid else lo, r0, len = mid, m0, mlen end
			end
			if lo == FLY_RHO[1] then r0, len = FlyPath(w0, w1, d1, lo) end
			hi = lo
		end
		a.rho, a.r0, a.S, a.d1 = hi, r0, len, d1
		a.c0, a.s0 = Cosh(r0), Sinh(r0)   -- (the same every frame of it)
	end
	if not (Finite(a.S) and (a.flat or Finite(a.r0))) then anim = nil ShowWorld(u, v, z1) userMoved = true return end
	a.time = Clamp(math.abs(a.S) * a.rho * FLY_PACE, FLY_TIME[1], FLY_TIME[2])
	anim = a
	userMoved = true
	mod.userDraggedAt = nil
end

-- one frame of a flight, t 0..1 (eased): the view's centre (world, normalized) and zoom
local function FlyAt(a, t)
	local s, rho = t * a.S, a.rho
	local x, y, w
	if a.flat then
		x, y, w = a.x0 + t * a.dx, a.y0 + t * a.dy, a.w0 * math.exp(rho * s)
	else
		local c0 = a.c0
		local k = a.w0 / (rho * rho * a.d1) * (c0 * Tanh(rho * s + a.r0) - a.s0)
		x, y, w = a.x0 + k * a.dx, a.y0 + k * a.dy, a.w0 * c0 / Cosh(rho * s + a.r0)
	end
	return x / a.W, y / a.H, math.max(a.span / w, LeastZoom())
end

-- the gamepad's zoom stick: a steady rate in log zoom, about its cursor (Blizzard's adds a fixed
-- scale a second, which at the stitched map's depths is too slow zoomed in, too fast out)
local PAD_ZOOM_RATE = 1.8       -- per second at full tilt (in log zoom: 6x a second)
local PAD_DEAD = 0.05           -- the zoom stick's tilt below which it's at rest

-- With the Gamepad UI (Options' padMap) the zoom stick is read from the controller itself. Blizzard
-- binds it to the map's zoom (GamepadZoom: sc.gamepadZoom) through its binding stack, but on OpenMap's
-- map those bindings are made again from OpenMap's map changes (the footer's Refresh in OnMapChanged),
-- so the stick can end up on the quest log's scrolling (SmartNavigation's), which refuses to run then
-- ("Interface action failed because of an AddOn") and the map never zooms. Reading the stick takes no
-- binding at all. nil: not to be read (no Gamepad UI, or the game doesn't give it): sc.gamepadZoom then
local function PadStickTilt()
	if not (PadUI() and C_GamePad and C_GamePad.GetDeviceMappedState and C_GamePad.StickIndexToConfigName) then
		return nil
	end
	local ok, state = pcall(C_GamePad.GetDeviceMappedState)
	if not ok or type(state) ~= "table" then return nil end
	local count, sticks = ns.Safe.Value(state.stickCount), ns.Safe.Value(state.sticks)
	if type(count) ~= "number" or type(sticks) ~= "table" then return nil end
	for i = 1, count do
		if C_GamePad.StickIndexToConfigName(i - 1) == "Camera" then   -- (0 based; Blizzard's right stick)
			local stick = sticks[i]
			local y = type(stick) == "table" and ns.Safe.Value(stick.y)
			if type(y) ~= "number" then return nil end
			if math.abs(y) < PAD_DEAD then return 0 end
			local tilt = math.min(math.abs(y), 1) ^ 1.8               -- (Blizzard's curve, GetZoomVelocityFromMagnitude)
			return y >= 0 and tilt or -tilt
		end
	end
	return nil
end
mod.PadStickTilt = PadStickTilt   -- (PadView.lua's zoom too)

-- tilt: the zoom stick, -1 (out) to 1 (in)
local function PadZoom(elapsed, tilt)
	local u, v, zoom = View()
	local sx, sy = CursorOffset()
	local pu, pv = PerPx(zoom)
	local cu, cv = u + sx * pu, v + sy * pv
	anim = nil
	userMoved = true
	local most = MaxZoomAt(cu, cv)
	if tilt > 0 then most = math.max(most, zoom) end
	local to = Clamp(zoom * math.exp(tilt * PAD_ZOOM_RATE * elapsed), LeastZoom(), most)
	if math.abs(to - zoom) < 1e-6 then return end
	pu, pv = PerPx(to)
	mod.padZoomAt = GetTime()
	ShowWorld(cu - sx * pu, cv - sy * pv, to)
end

-- after Blizzard's own OnUpdate, so its panning never adds to ours
local function Animate(_, elapsed)
	local tilt = active and mod.db.padMap and PadFocus() and PadStickTilt() or nil
	if tilt == nil and active and (sc.gamepadZoom or 0) ~= 0 then
		local speed = sc.gamepadZoomSpeed
		tilt = Clamp(sc.gamepadZoom / ((speed and speed > 0) and speed or 1), -1, 1)   -- (Blizzard's curve applied)
	end
	padTilt = tilt or 0
	if padTilt ~= 0 then return PadZoom(elapsed, padTilt) end
	-- the gamepad's cursor at the view's edge pans it (Blizzard's): a move of the user's
	if active and sc.HasGamepadScrollSpeed and sc:HasGamepadScrollSpeed() then userMoved = true end
	if not anim then return end
	if not active then anim = nil return end
	local a = anim
	if a.mode == "anchor" then
		local _, _, z = View()
		local zoom = math.exp(math.log(z) + (math.log(a.target) - math.log(z)) * (1 - math.exp(-elapsed * ZOOM_RATE)))
		local done = math.abs(math.log(a.target / zoom)) < 0.003
		if done then zoom = a.target end
		local down = sc.mouseButtonInfo.LeftButton.down
		if down and not a.down then
			-- grabbed mid-zoom: what's under the cursor now is what the cursor carries
			local u, v = View()
			local sx, sy = CursorOffset()
			local pu, pv = PerPx(z)
			a.u, a.v, a.sx, a.sy = u + sx * pu, v + sy * pv, sx, sy
		elseif down then
			a.sx, a.sy = CursorOffset()
		end
		a.down = down
		local pu, pv = PerPx(zoom)
		ShowWorld(a.u - a.sx * pu, a.v - a.sy * pv, zoom)
		if done then
			anim = nil
		elseif waitingView then
			-- (refused in combat: the zoom would never arrive, every addon's icons rescaled each frame
			-- till it's over. It ends here, and where it was going is what waits)
			anim = nil
			local mapID = map:GetMapID()
			pu, pv = PerPx(a.target)
			local x, y = FromWorld(mapID, a.u - a.sx * pu, a.v - a.sy * pv)
			waitingView = { mapID = mapID, scale = ScaleFor(mapID, a.target), x = x, y = y }
		end
	elseif a.mode == "fly" then   -- (daves_map)
		a.t = math.min(1, a.t + elapsed / a.time)
		if a.t >= 1 then
			ShowWorld(a.u1, a.v1, a.z1)               -- (the last frame exactly on the target)
			anim = nil
		else
			local u, v, zoom = FlyAt(a, a.t * a.t * (3 - 2 * a.t))
			if Finite(u, v, zoom) then ShowWorld(u, v, zoom) else ShowWorld(a.u1, a.v1, a.z1) anim = nil end
			if waitingView then                       -- (refused in combat: wait on the flight's destination)
				anim = nil
				local mapID = map:GetMapID()
				local x, y = FromWorld(mapID, a.u1, a.v1)
				waitingView = { mapID = mapID, scale = ScaleFor(mapID, a.z1), x = x, y = y }
			end
		end
	else
		a.t = math.min(1, a.t + elapsed / GLIDE_TIME)
		local e = a.t * a.t * (3 - 2 * a.t)
		local zoom = math.exp(math.log(a.z0) + (math.log(a.z1) - math.log(a.z0)) * e)
		-- the centre moves with 1/zoom, which is what zooming about one fixed point looks like
		local w = math.abs(a.z1 - a.z0) < 1e-6 and e or (1 / a.z0 - 1 / zoom) / (1 / a.z0 - 1 / a.z1)
		ShowWorld(a.u0 + (a.u1 - a.u0) * w, a.v0 + (a.v1 - a.v0) * w, zoom)
		if a.t >= 1 then anim = nil end
	end
end

--------------------------------------------------------------------------------
-- Following the view: which map should be underneath
--------------------------------------------------------------------------------

local function PickMap(u, v, zoom, current)
	local chain = S.ChainAt(u, v)
	local pick = WORLD
	for _, mapID in ipairs(chain) do
		local need = (mapID == current) and LEAVE or ENTER
		if mapID ~= WORLD and Stitchable(mapID) and zoom >= FitZoom(mapID) * need then pick = mapID end
	end
	return pick
end

local switchView                  -- the view a switch is for, while the new map's icons are placed (mod.PinView)
local function Switch(target)
	local u, v, zoom = View()
	switching = true
	mod.lastSwitchAt = GetTime()
	switchView = { u, v, zoom }
	local g = Before()
	local ok, err = KeepPadCursor(pcall, map.SetMapID, map, target)
	After("map switch (all addons)", g)
	switching = false
	switchView = nil
	if not ok then geterrorhandler()(err) return end
	if active then
		local x, y = FromWorld(target, u, v)
		SetView(ScaleFor(target, zoom), x, y)
	end
end

-- (a current value of nil is Blizzard's "lay it out again" (MarkCanvasDirty, on every pin another addon
-- adds), not a move: it's the target then. Taken as a move, the map underneath never followed the view
-- with such an addon on, Questie's or GatherLite's icons never coming in for the zone you'd panned to)
local function Settled()
	return not anim and not sc.mouseButtonInfo.LeftButton.down
		and (sc.currentScale or sc.targetScale) == sc.targetScale
		and (sc.currentScrollX or sc.targetScrollX) == sc.targetScrollX
		and (sc.currentScrollY or sc.targetScrollY) == sc.targetScrollY
end

-- the player's arrow on top of every other icon (#31): Blizzard's (its group members pin, the party's
-- with it) and ours. Blizzard sets its level again as it reuses the pin, so it's checked each tick.
-- Its blips are sized away where OpenMap's switch for them is off: your own while Your arrow is off
-- (and the yellow ring it pings on opening, #78), the party's and raid's while Party and raid members
-- is off (#77). Blizzard sizes them again on every zoom step (SynchronizePinSizes): hooked, so they
-- go at once, and each tick as well where there's no such step to hook
local BLIP_GONE = 0.01            -- (a size too small to draw: 0 is taken as the texture's own size, a huge arrow)
local BLIP_UNITS = { player = "playerArrow", party = "group", raid = "group" }
local blipHidden = setmetatable({}, { __mode = "k" })    -- pin -> { unit = true } sized away
local blipHooked = setmetatable({}, { __mode = "k" })
local groupBlipSizes = setmetatable({}, { __mode = "k" })
local loweredGroupBlips = setmetatable({}, { __mode = "k" })
local function BlipOff(unit)
	if mod.instanceWorldHidden or mod.db[BLIP_UNITS[unit]] == false then return true end
	-- OpenMap's own arrow up (the map underneath couldn't place you): Blizzard's goes, one arrow not two (#229).
	-- Not on retail (ns.MapWorld): its zones' rectangles come from the game's chain of maps, which is off
	-- by tens of yards, so ours could be the one out of place, and only it was left (#254)
	if ns.MapWorld then return false end
	return unit == "player" and active and S.PlayerShown and S.PlayerShown() or false
end
local function Locked(pin) return pin:IsProtected() and InCombatLockdown() end
-- Blizzard's arrow and group dots default to sublevel 7 within the same frame.
local function LayerGroupBlips(pin)
	local lowered = active or nil
	local set = pin.SetPinSubLevel
	if loweredGroupBlips[pin] == lowered or not set or Locked(pin) then return end
	local sublevel = lowered and 6 or 7
	if not pcall(set, pin, "party", sublevel) then return end
	if not pcall(set, pin, "raid", sublevel) then
		pcall(set, pin, "party", lowered and 7 or 6)
		return
	end
	loweredGroupBlips[pin] = lowered
end

local function ScaleGroupBlips(pin)
	if not pin.SetPinSize or Locked(pin) then return end
	if active and BlipOff("party") then
		groupBlipSizes[pin] = nil
		return
	end
	local applied = groupBlipSizes[pin]
	local factor = active and tonumber(mod.db.iconScale) or 1
	if factor <= 0 then factor = 1 end
	if factor == 1 and not applied then return end
	local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
	if scale <= 0 or (applied and applied.factor == factor and applied.scale == scale) then return end
	local provider = pin.dataProvider
	local sizes = provider and provider.GetUnitPinSizesTable and provider:GetUnitPinSizesTable()
	if not sizes or not sizes.party or not sizes.raid then return end
	if not pcall(pin.SetPinSize, pin, "party", sizes.party * factor / scale) then return end
	if not pcall(pin.SetPinSize, pin, "raid", sizes.raid * factor / scale) then
		local previous = applied and applied.factor / applied.scale or 1 / scale
		pcall(pin.SetPinSize, pin, "party", sizes.party * previous)
		return
	end
	groupBlipSizes[pin] = factor ~= 1 and { factor = factor, scale = scale } or nil
end

-- The rim uses the size that could be applied to the stock dot.
function mod.NativeGroupIconScale(pin)
	local applied = groupBlipSizes[pin]
	return applied and applied.factor or 1
end

local function Blips(pin)
	local ping = type(pin.StartPlayerPing) == "function" and type(pin.StopPlayerPing) == "function"
	if not blipHooked[pin] then
		blipHooked[pin] = true
		if pin.SetPinSize and type(pin.SynchronizePinSizes) == "function" then
			hooksecurefunc(pin, "SynchronizePinSizes", function(self)
				groupBlipSizes[self] = nil -- Blizzard just restored the provider's default sizes
				if Locked(self) then return end
				for unit in pairs(BLIP_UNITS) do
					if BlipOff(unit) then pcall(self.SetPinSize, self, unit, BLIP_GONE) end
				end
				ScaleGroupBlips(self)
			end)
		end
		if ping then
			hooksecurefunc(pin, "StartPlayerPing", function(self)
				if BlipOff("player") and not Locked(self) then pcall(self.StopPlayerPing, self) end
			end)
		end
	end
	if ping and BlipOff("player") then pcall(pin.StopPlayerPing, pin) end
	if not pin.SetPinSize then return end
	local hidden = blipHidden[pin] or {}
	blipHidden[pin] = hidden
	for unit in pairs(BLIP_UNITS) do
		if BlipOff(unit) then
			pcall(pin.SetPinSize, pin, unit, BLIP_GONE)
			hidden[unit] = true
		elseif hidden[unit] then
			-- (back at Blizzard's size for this zoom: its size over the canvas's scale, as it sets it)
			local dp = pin.dataProvider
			local sizes = dp and dp.GetUnitPinSizesTable and dp:GetUnitPinSizesTable()
			local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
			if sizes and sizes[unit] and scale and scale > 0 then pcall(pin.SetPinSize, pin, unit, sizes[unit] / scale) end
			hidden[unit] = nil
		end
	end
	ScaleGroupBlips(pin)
end

local function RaisePlayer()
	local level = math.min(sc:GetFrameLevel() + PLAYER_ABOVE, 9500)
	for pin in map:EnumeratePinsByTemplate("GroupMembersPinTemplate") do
		if not Locked(pin) then
			if pin:GetFrameLevel() ~= level then pin:SetFrameLevel(level) end
			Blips(pin)
			LayerGroupBlips(pin)
		end
	end
	S.RaiseArrow(level + 1)
	if mod.RefreshNativeRingLayout then mod.RefreshNativeRingLayout() end
end

local ticker = CreateFrame("Frame")
ticker:Hide()
local elapsedSum = 0
-- a switch has Blizzard refresh every map data provider (every Questie pin with them): a
-- hitch, so it waits until the view has been still this long, not the moment it stops
local SWITCH_AFTER = 0.6
local stillFor = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	elapsedSum = elapsedSum + elapsed
	if elapsedSum < 0.1 then return end
	elapsedSum = 0
	if not active then
		if mod.instanceWorldHidden then RaisePlayer() end
		return
	end
	-- another addon's zoom steps past ours (BetterMaps', High Fidelity World Map's): the deepest
	-- zoom is OpenMap's, and Blizzard's icons size themselves from the last step
	local zl = sc.zoomLevels
	if levelCount and zl and #zl > levelCount then
		for i = #zl, levelCount + 1, -1 do zl[i] = nil end
	end
	local mapID = map:GetMapID()

	-- the player, when the map underneath can't show them
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if pos then
		S.SetPlayer(nil)
	else
		local best = C_Map.GetBestMapForUnit("player")
		local p = best and S.Rect(best) and C_Map.GetPlayerMapPosition(best, "player")
		local x, y
		if p then x, y = ns.Safe.XY(p) end
		if not ns.Safe.IsSecret(x) and not ns.Safe.IsSecret(y) and x and y then
			local u, v = ToWorld(best, x, y)
			S.SetPlayer(u, v, ns.Safe.Call(GetPlayerFacing))
		else
			S.SetPlayer(nil)
		end
	end

	RaisePlayer()

	stillFor = Settled() and stillFor + 0.1 or 0
	-- (daves_map: don't switch the host map while QuestMapFrame.DetailsFrame is open or while referencing a pinned Zone/Dungeon sidebar link)
	local detailsOpen = QuestMapFrame and QuestMapFrame.DetailsFrame and QuestMapFrame.DetailsFrame:IsShown()
	if mod.suspendAutoSwitch then
		stillFor = 0
	elseif mod.db.autoSwitch and userMoved and stillFor >= SWITCH_AFTER and not detailsOpen and not InCombatLockdown() and not mod.benching then
		local u, v, zoom = View()
		local target = PickMap(u, v, zoom, mapID)
		if target ~= mapID then Switch(target) end
	end
end)

--------------------------------------------------------------------------------
-- Hooks into Blizzard's map
--------------------------------------------------------------------------------

-- how long opening the map takes, to the next frame drawn (/openmap status): the game's
-- work, Questie's and ours (the first opening also builds the map); and OpenMap's own part,
-- its handlers' time from the open until the second frame after it
local openTimes, openOurs, openFrames = {}, 0, 0
local openParts, openLast = {}, {}
local openTimer = CreateFrame("Frame")
openTimer:Hide()
openTimer:SetScript("OnUpdate", function(self)
	openFrames = openFrames + 1
	if openFrames == 1 and openStart then
		table.insert(openTimes, 1, { debugprofilestop() - openStart, 0 })
		openTimes[4] = nil
	elseif openFrames >= 2 then
		if openTimes[1] then openTimes[1][2] = openOurs end
		openLast, openParts = openParts, {}
		openStart = nil
		self:Hide()
	end
end)
-- `fn`, with its time counted as OpenMap's part of an opening (while one is being timed),
-- by part. "icons rescaled" (Blizzard telling every addon's map icons the new scale, from
-- SetView) is timed apart: it runs inside our handlers but is mostly other addons' work.
Part = function(name, ms)
	openParts[name] = (openParts[name] or 0) + ms
end
local function Ours(name, fn)
	return function(...)
		if not openStart or not debugprofilestop then return fn(...) end
		local start = debugprofilestop()
		fn(...)
		local ms = debugprofilestop() - start
		openOurs = openOurs + ms
		Part(name, ms)
	end
end

-- After an opening (AFTER_OPEN seconds) and as the map closes: OpenMap's later work (timers, the
-- warm art's let-go, the friends scan, Questie's icons and paths), the worst of each, and the longest
-- frame then, ours or not (/openmap status). A stall after the opening frame shows here, not above
local AFTER_OPEN = 3
local after = { parts = {}, close = {}, gap = 0, gapAt = 0 }
local afterFrame = CreateFrame("Frame")
afterFrame:Hide()
afterFrame:SetScript("OnUpdate", function(self)
	local now = debugprofilestop()
	if after.last and now - after.last > after.gap then after.gap, after.gapAt = now - after.last, after.last - after.start end
	after.last = now
	if now - after.start > AFTER_OPEN * 1000 then self:Hide() end
end)
local function AfterOpening()
	if not debugprofilestop then return end
	after.start, after.last, after.gap, after.gapAt = debugprofilestop(), nil, 0, 0
	wipe(after.parts)
	afterFrame:Show()
end
local function Note(list, name, ms) if ms > (list[name] or 0) then list[name] = ms end end
-- fn(...) timed as `name` while an opening's later work is being watched (its results passed on)
function mod.TimeAfter(name, fn, ...)
	if not debugprofilestop or not afterFrame:IsShown() then return fn(...) end
	local start = debugprofilestop()
	local a, b, c = fn(...)
	Note(after.parts, name, debugprofilestop() - start)
	return a, b, c
end
-- fn(...) timed as `name`, as the map closes
function mod.TimeClose(name, fn, ...)
	if not debugprofilestop then return fn(...) end
	local start = debugprofilestop()
	local a, b, c = fn(...)
	after.close[name] = debugprofilestop() - start
	return a, b, c
end
local function Worst(list)
	local parts = {}
	for name, ms in pairs(list) do parts[#parts + 1] = { name, ms } end
	table.sort(parts, function(x, y) return x[2] > y[2] end)
	for i, p in ipairs(parts) do parts[i] = ("%s %.0f"):format(p[1], p[2]) end
	return #parts > 0 and table.concat(parts, ", ") or "nothing timed"
end

-- the view for Close.lua (minimap, grain, caves): centre, half extents (normalized), zoom
-- (Blizzard reports a pan several times a frame: the work is done once, on the next frame)
local live                      -- { u, v, zoom, width, height }: the view on screen, and the view's size then
local viewFrame = CreateFrame("Frame")
viewFrame:Hide()
viewFrame:SetScript("OnUpdate", Ours("view update", function(self)
	self:Hide()
	-- (only on the map open: Blizzard resets the view once more as it closes, and a view taken then was
	-- read on the next opening as one put up while it's open, the zone's whole map, before the zoom kept
	-- was put back a frame later: "Center on player, keep zoom" opened closer, then jumped. The opening
	-- runs it again: ApplyZoom)
	if not active or not S.SetView or not map:IsShown() then return end
	local u, v, zoom = View()
	live = live or {}                             -- (kept: the view updates every frame of a pan)
	live[1], live[2], live[3], live[4], live[5] = u, v, zoom, sc:GetWidth(), sc:GetHeight()
	local pu, pv = PerPx(zoom)
	local g, t0 = Before(), Clock()
	S.SetView(u, v, sc:GetWidth() / 2 * pu, sc:GetHeight() / 2 * pv, zoom * DetailK(), zoom / (ns.ClientMaps and ns.ClientMaps.zoom or 1))
	After("close-up", g)
	Clocked("OpenMap's view update", t0)
	if mod.OnViewMoved then mod.OnViewMoved() end   -- (API.lua: other addons told, a few times a second at most)
end))
local function ApplyView()
	if active then viewFrame:Show() end
end

local function ApplyZoom()
	if not active then return end
	local g, t0 = Before(), Clock()
	S.SetZoom(ZoomFor(map:GetMapID(), sc:GetCanvasScale()) * DetailK(), sc:GetCanvasScale())
	After("zoom", g)
	Clocked("OpenMap's zoom update", t0)
	ApplyView()
end

-- a map is about to show: decide whether it's stitched, then lay the art out for it
-- Blizzard's own art for the host map (its tiles, and the explored-area pin, which also
-- runs every frame): all under ours, so off while the stitched map shows
local function BlizzardArt()
	local show = not active
	if map.detailLayerPool then
		for layer in map.detailLayerPool:EnumerateActive() do layer:SetShown(show) end
	end
	for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do pin:SetShown(show) end
end

-- A viewport-sized shade above all stitched art (including close-up terrain and caves),
-- below Blizzard's and OpenMap's pins. It stays still while the canvas pans or zooms.
function mod:UpdateBrightness()
	if not sc or not S.IsBuilt() then return end
	local brightness = math.max(0.25, math.min(1, tonumber(self.db.brightness) or self.defaults.brightness))
	local shade = self.brightnessShade
	if not shade and brightness == 1 then return end
	if not shade then
		shade = CreateFrame("Frame", nil, sc)
		shade:SetAllPoints(sc)
		shade:EnableMouse(false)
		shade.texture = shade:CreateTexture(nil, "OVERLAY")
		shade.texture:SetAllPoints(shade)
		shade.texture:SetColorTexture(0, 0, 0, 1)
		self.brightnessShade = shade
	end
	shade:SetFrameLevel(S.artTop)
	shade.texture:SetAlpha(1 - brightness)
	shade:SetShown(active and self.enabled and brightness < 1)
end

local function Attach(mapID, refreshed)
	if not refreshed then mod:RefreshInstancePins(true) end
	local wasHidden = mod.instanceWorldHidden
	mod.instanceWorldHidden = mod.InstanceWorldHidden(mapID)
	active = mod.enabled and not mod.instanceWorldHidden and Stitchable(mapID) and S.IsBuilt() and S.Layout(mapID) or false
	S.SetShown(active)
	mod:UpdateBrightness()
	BlizzardArt()
	if active then
		sc:SetMouseWheelZoomMode(MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE)
		sc:SetScalingMode("SCALING_MODE_LINEAR")
		if map:IsShown() then ticker:Show() end
	else
		for pin in pairs(groupBlipSizes) do ScaleGroupBlips(pin) end
		for pin in pairs(loweredGroupBlips) do LayerGroupBlips(pin) end
		sc:SetMouseWheelZoomMode(wheelMode)
		sc:SetScalingMode(scalingMode)
		S.SetPlayer(nil)
		ticker:Hide()
		if mod.RefreshNativeRingLayout then mod.RefreshNativeRingLayout() end
		anim = nil
		if mod.IsPainting and mod:IsPainting() then mod:TogglePaint(false) end
		if mod.IsSketching and mod:IsSketching() then mod:ToggleSketch(false) end
	end
	if map:IsShown() and (wasHidden or mod.instanceWorldHidden) then
		RaisePlayer()
		if mod.instanceWorldHidden then ticker:Show() end
	end
	if mod.OnStitchedChanged then mod.OnStitchedChanged(active) end
end

-- zoom levels from the whole world to street level, in this map's scale
-- what's built on the stitched art once it is, one a step (a frame each, built ahead: Prebuild), then a refresh
local EXTRAS = { "BuildFlights", "BuildPaint", "BuildSketch", "BuildNav", "BuildMapPins" }
local extrasDone = 0
local function ExtrasBuilt() return extrasDone > #EXTRAS end
local function BuildExtra()             -- (the next; true once they're all done)
	if ExtrasBuilt() then return true end
	extrasDone = extrasDone + 1
	local name = EXTRAS[extrasDone]
	if name then
		if mod[name] then mod[name](mod) end
		return false
	end
	mod:Refresh()
	return true
end
local function BuildArgs()
	local fl = map:GetPinFrameLevelsManager()
	return map:GetCanvas(), fl:GetValidFrameLevel("PIN_FRAME_LEVEL_DAVES_MAP_STITCH"), ART_RANGE,
		fl:GetValidFrameLevel("PIN_FRAME_LEVEL_DAVES_MAP_STITCH_ICONS")
end

-- The map built ahead, a few ms a frame, a moment after the loading screen (out of combat, the map
-- closed): neither the loading screen nor the map's first opening carries it all (thousands of regions,
-- hundreds of files). The map opened before it's done: the rest at once (OnCreateZoomLevels)
local prebuildOwner = {}
local function Prebuild()
	if S.IsBuilt() and ExtrasBuilt() then return end
	if InCombatLockdown() or map:IsShown() then C_Timer.After(2, Prebuild) return end   -- (open: its own build)
	if not S.IsBuilt() then
		if not S.pace then
			local parent, artLevel, range, iconLevel = BuildArgs()   -- (all four: a call not last gives one)
			S.BuildSoon(parent, artLevel, range, iconLevel, function()
				ns.loadMs.build, ns.loadMs.builtShown = S.paceMs, false
				C_Timer.After(0, Prebuild)
			end)
		end
		return
	end
	if not BuildExtra() then C_Timer.After(0, Prebuild) end
end
local function PrebuildSoon()
	ns.UnregisterEvent(prebuildOwner, "LOADING_SCREEN_DISABLED")
	ns.UnregisterEvent(prebuildOwner, "PLAYER_ENTERING_WORLD")
	C_Timer.After(3, Prebuild)
end

local zoomAttached = false        -- (daves_map: whether OnCreateZoomLevels has attached on a shown, sized map)
local function OnCreateZoomLevels(self)
	if not (S.IsBuilt() and ExtrasBuilt()) then
		-- (not while the map is closed: the game sizes the full-screen map as the screen and the UI scale are
		-- set, at login, FillScreen lays it out again, and other addons lay the closed window out too; the
		-- whole map was built then, in the loading screen. It's built ahead (Prebuild), or as it first
		-- opens: `shown`, below)
		if not map:IsShown() then zoomAttached = false return end
		local t0 = debugprofilestop and debugprofilestop()
		local ahead = S.IsBuilt()
		S.Build(BuildArgs())
		repeat until BuildExtra()
		if t0 and not ahead then ns.loadMs.build, ns.loadMs.builtShown = debugprofilestop() - t0, map:IsShown() end
	end
	if not map:IsShown() or self:GetWidth() <= 0 or self:GetHeight() <= 0 then zoomAttached = false return end   -- (daves_map)
	zoomAttached = true
	Attach(self.mapID)
	if not active then return end
	if S.Chart then S.Chart.Layout(self:GetWidth(), self:GetHeight()) end   -- (the sea chart for the view's shape)
	local levels = {}
	local zoom = LeastZoom()
	local deepest = mod.db.maxZoom * CITY_ZOOM               -- (the deepest anywhere: a city's)
	while zoom < deepest * ZOOM_STEP do
		levels[#levels + 1] = { scale = ScaleFor(self.mapID, math.min(zoom, deepest)), layerIndex = 1 }
		zoom = zoom * ZOOM_STEP
	end
	self.zoomLevels = levels
	self.baseScale = levels[1].scale    -- panning allowed above the whole-world view
	levelCount = #levels
end

-- combat over: the view the canvas refused in it (SetView), if that map is still the one up
function mod.FlushWaitingView()
	local w = waitingView
	waitingView = nil
	if not w or InCombatLockdown() or not active or anim or not map:IsShown() or map:GetMapID() ~= w.mapID then return end
	SetView(w.scale, w.x, w.y)
end

-- Blizzard showed a map (opening, the quest log, the dropdown): show it as it would
-- Blizzard's zoom reset (each time the map opens, after re-adding every addon's icons), done
-- our way while the map is stitched: straight to where you left off, in one step (not the
-- whole world and then there: every addon's icons rescaled twice); and if the map is still
-- there (closed and reopened without moving), nothing at all. The window resized while open
-- (full screen and back): where you were looking, at the same framing; its corner dragged: the
-- map as it is on screen (the drag shows more or less of it, at the same scale). Another
-- map put up while it's open (the quest log's, the dropdown's) shows whole, as Blizzard's does
local beforeReset                 -- the view on screen when Blizzard last put up a map: { u, v, zoom, at = GetTime() }
local resize                      -- the window's corner being dragged: { left, scroll } (FollowResize)
local function ResetView(self)
	userMoved = false
	anim = nil
	if live and map:IsShown() then beforeReset = { live[1], live[2], live[3], at = GetTime() } end
	local u, v, zoom
	local sizeChanged = live and map:IsShown() and (math.abs(sc:GetWidth() - live[4]) > 0.5 or math.abs(sc:GetHeight() - live[5]) > 0.5)   -- (daves_map)
	if resize and live and map:IsShown() then
		u, v, zoom = View()
	elseif sizeChanged then
		u, v, zoom = live[1], live[2], live[3]
	elseif not live and mod.SavedView then          -- (no view drawn yet: the map is opening)
		u, v, zoom = mod.SavedView(self.mapID)
	end
	if not u and mod.ReturnView then u, v, zoom = mod.ReturnView(self.mapID) end   -- (out of a dungeon's map: Dungeons.lua)
	if u then
		zoom = Clamp(zoom, LeastZoom(), MaxZoomAt(u, v))
		local nu, nv, nz = View()
		if resize or sizeChanged or not (nu and math.abs(nu - u) < 1e-4 and math.abs(nv - v) < 1e-4 and math.abs(nz - zoom) < 1e-3) then   -- (daves_map)
			ShowWorld(u, v, zoom)
		end
		userMoved = true
		return
	end
	local aw, ah = S.ArtSize(self.mapID)
	SetView(math.min(self:GetWidth() / aw, self:GetHeight() / ah), 0.5, 0.5)
end

-- the window's corner dragged (Window.lua): Blizzard isn't told the view's size changed until the
-- drop (laying the map out again takes every addon's icons with it), so each frame of the drag the
-- map is kept where it is on screen, under the window's edge that stays put, and the view's centre
-- and extents follow what's now in the window (the close-up art filling in as it grows); the drop
-- lays it out at that same scale (ResetView), so nothing jumps
function mod.BeginResize()
	resize = nil
	if not active or not map:IsShown() or not sc:GetLeft() then return end
	resize = { left = sc:GetLeft(), scroll = sc:GetHorizontalScroll() }
end
function mod.FollowResize()
	if not resize or not active or not map:IsShown() then return end
	local left = sc:GetLeft()
	if not left then return end
	sc:SetHorizontalScroll(resize.scroll + (left - resize.left) / sc:GetCanvasScale())
	sc:CalculateScrollExtents()
	local x, y = sc:GetNormalizedHorizontalScroll(), sc:GetNormalizedVerticalScroll()
	sc.currentScrollX, sc.targetScrollX, sc.currentScrollY, sc.targetScrollY = x, x, y, y
	sc:MarkAreaTriggersDirty()
	sc:MarkViewRectDirty()
	ApplyView()
end
function mod.EndResize() resize = nil end

-- pan anywhere on the world, not just this map. Zoomed right out the world is centred;
-- zooming in, the view gains room to go past its edges (EDGE_SLACK, in by CENTRE_UNTIL), so
-- the wheel zooms about the point under the cursor from the first step
local EDGE_SLACK = 0.2          -- world widths / heights
local CENTRE_UNTIL = 1.6        -- zoom by which the view has all that room
local function Range(a0, a1, half, slack, t)
	local lo, hi = a0 + half, a1 - half
	local c = (a0 + a1) / 2
	local plainLo, plainHi = lo, hi         -- on the world, or (the view wider than it) centred
	if lo > hi then plainLo, plainHi = c, c end
	-- with room: the whole world kept in view (if wider), and EDGE_SLACK past it
	local fullLo, fullHi = math.min(lo, hi) - slack, math.max(lo, hi) + slack
	return plainLo + (fullLo - plainLo) * t, plainHi + (fullHi - plainHi) * t
end
local function Extents(origExtents)
	return function(self, scale)
		if not active then return origExtents(self, scale) end
		local mapID = map:GetMapID()
		local hw = self:NormalizeHorizontalSize(self:GetWidth() * 0.5 / scale)
		local hh = self:NormalizeVerticalSize(self:GetHeight() * 0.5 / scale)
		-- with the sea chart: anywhere on it, to its edges and no further, at every zoom
		local cl, ct, cr, cb
		if S.Chart and S.Chart.on then cl, ct, cr, cb = S.Chart.Rect(self:GetWidth(), self:GetHeight()) end
		if cl then
			local x0, y0 = FromWorld(mapID, cl, ct)
			local x1, y1 = FromWorld(mapID, cr, cb)
			local minX, maxX = Range(x0, x1, hw, 0, 0)
			local minY, maxY = Range(y0, y1, hh, 0, 0)
			return minX, maxX, minY, maxY
		end
		local x0, y0 = FromWorld(mapID, 0, 0)
		local x1, y1 = FromWorld(mapID, 1, 1)
		local t = Clamp((ZoomFor(mapID, scale) - 1) / (CENTRE_UNTIL - 1), 0, 1)
		local minX, maxX = Range(x0, x1, hw, (x1 - x0) * EDGE_SLACK, t)
		local minY, maxY = Range(y0, y1, hh, (y1 - y0) * EDGE_SLACK, t)
		return minX, maxX, minY, maxY
	end
end

-- the hover highlight. Blizzard's shows the host map's children: on the world, whole
-- continents. Once the continents' art (and its zone outlines) is in, it's the zone under
-- the cursor instead: the continent's own highlight for it, placed on the world
local ZONE_HIGHLIGHT = 1.5      -- zoom from which the world highlights zones (Stitch.lua's continents half in)
local lastHU, lastHV, lastHK      -- (the highlight's cursor: it's redone only when that moves a pixel)
local function HighlightZone(pin)
	local tex = pin.HighlightTexture
	local u, v, pu = mod.CursorWorld()
	local key = sc:GetCanvasScale()
	if u and lastHU and lastHK == key and math.abs(u - lastHU) < pu and math.abs(v - lastHV) < pu then return end
	lastHU, lastHV, lastHK = u, v, key
	local cont
	for _, id in ipairs(u and S.ChainAt(u, v) or {}) do
		local info = C_Map.GetMapInfo(id)
		if info and info.mapType == Enum.UIMapType.Continent then cont = id end
	end
	local l, r, t, b = S.Rect(cont or WORLD)
	if not cont or not l then tex:Hide() return end
	local x, y = FromWorld(cont, u, v)
	local fid, atlas, tx, ty, w, h, left, top = C_Map.GetMapHighlightInfoAtPosition(cont, x, y)
	if not ((fid and fid > 0) or atlas) or not w or w <= 0 or h <= 0 then tex:Hide() return end
	if atlas then
		tex:SetAtlas(atlas, false, "TRILINEAR")
	else
		tex:SetTexture(fid, nil, nil, "TRILINEAR")
		tex:SetTexCoord(0, tx, 0, ty)
	end
	-- from the continent's normalized space to the world's (this map's)
	local pw, ph = pin:GetWidth(), pin:GetHeight()
	tex:ClearAllPoints()
	tex:SetSize(w * (r - l) * pw, h * (b - t) * ph)
	tex:SetPoint("TOPLEFT", (l + left * (r - l)) * pw, -(t + top * (b - t)) * ph)
	tex:Show()
end
local function HookHighlight()
	for pin in map:EnumeratePinsByTemplate("MapHighlightPinTemplate") do
		if not pin.omRefresh and pin.Refresh and pin.HighlightTexture then
			pin.omRefresh = pin.Refresh
			pin.Refresh = function(self)
				if mod.instanceWorldHidden then return self.HighlightTexture:Hide() end
				if active and not mod.db.hoverHighlight then return self.HighlightTexture:Hide() end
				if active and map:GetMapID() == WORLD and select(3, View()) >= ZONE_HIGHLIGHT then
					return HighlightZone(self)
				end
				return self:omRefresh()
			end
		end
	end
end

-- wheel: a step, about the point under the cursor
local function OnMouseWheel(_, delta)
	if not active then return end
	ZoomAtCursor(delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP)
end

-- a left click drops a pin under the cursor when the menu's pin button is on, or with Ctrl (unless
-- that's turned off: ctrlClickPin)
local function Dropping(button)
	return active and button == "LeftButton" and mod.DropWaypoint
		and ((IsControlKeyDown() and mod.db.ctrlClickPin ~= false) or (mod.PinMode and mod.PinMode()))
end

local function DropAtCursor()
	local fromButton = mod.PinMode and mod.PinMode()
	if mod.SetPinMode then mod.SetPinMode(false) end
	local u, v = mod.CursorWorld()
	mod.DropWaypoint(u, v, fromButton)     -- (not the click position Blizzard passes: that's clamped to this map's rectangle)
end

-- clicks: in = the next map down under the cursor, out = the map above
-- Shift-click with Shortest Path Forever: its own click plans a journey to the point on the map
-- underneath (its GetNormalizedCursorPosition), which past that map's edge is off it (another
-- continent, or the whole world's view, where the game places nothing). There, the journey goes
-- through its API instead, to the point on the zone under the cursor
local function PathTo()
	local api = _G.ShortestPathForever and _G.ShortestPathForever.API
	if type(api) ~= "table" or type(api.Navigate) ~= "function" then return false end
	local chat = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or _G.ChatEdit_GetActiveWindow
	if chat and chat() then return false end   -- (a chat box open: Shift-click puts a link in it)
	local u, v = mod.CursorWorld()
	if not u then return false end
	local host = map:GetMapID()
	local hx, hy = FromWorld(host, u, v)
	if host ~= WORLD and hx >= 0 and hx <= 1 and hy >= 0 and hy <= 1 then return false end
	local chain = S.ChainAt(u, v)
	local zone = chain[#chain]
	if not zone or zone == WORLD then return false end
	local x, y = FromWorld(zone, u, v)
	if x < 0 or x > 1 or y < 0 or y > 1 then return false end
	local ok, started = pcall(api.Navigate, "OpenMap", zone, x, y)
	return ok and started and true or false
end

-- a left press that wandered off and came back isn't a click: Blizzard's test only compares where it
-- went down with where it came up (about 4 pixels), so a drag back and forth over the map, or a slow
-- one that ends near its start, zoomed into the zone or city under the cursor (#37, #64)
local press = { moved = false }
local PRESS_SLOP_SQ = 20          -- (Blizzard's own click distance, squared: MAX_DIST_FOR_CLICK_SQ)
local function PressDown(_, button)
	if button ~= "LeftButton" then return end
	press.x, press.y = sc:GetCursorPosition()
	press.moved = false
end
local function PressTrack()
	if not press.x or not sc.mouseButtonInfo.LeftButton.down then return end
	if press.moved then
		mod.userDraggedAt = GetTime()
		return
	end
	local x, y = sc:GetCursorPosition()
	local dx, dy = x - press.x, y - press.y
	if dx * dx + dy * dy > PRESS_SLOP_SQ then
		press.moved = true
		mod.userDraggedAt = GetTime()
	end
end
local function WasDrag() return press.moved end

local function OnCanvasClick(from, button)
	-- NeedRoll draws over a world-map host: a click must not select a zone underneath it.
	if mod.instanceWorldHidden then return true end
	if not active then return false end
	if Dropping(button) then
		DropAtCursor()
		return true
	end
	-- (Shift-click is other addons' first, Shortest Path Forever's journeys: handled by none of them,
	-- it comes back here through NavigateToCursor, `from` nil, and zooms in as a click)
	if from and button == "LeftButton" and IsShiftKeyDown() then return PathTo() end
	-- (Ctrl-click with "Ctrl-click drops a pin" off is other addons', Map Pin Enhanced's, and Blizzard's
	-- own waypoint: passed on, not a zoom that ends the click here (#19))
	if from and button == "LeftButton" and IsControlKeyDown() and mod.db.ctrlClickPin == false then return false end
	if from and button == "LeftButton" and WasDrag() then return true end
	local u, v = mod.CursorWorld()
	local vu, vv, zoom = View()
	local chain = S.ChainAt(u, v)
	if button == "LeftButton" then
		local zoomed = false
		for _, id in ipairs(chain) do
			if id ~= WORLD and Stitchable(id) and FitZoom(id) > zoom * 1.05 then
				local l, r, t, b = S.Rect(id)
				GlideTo((l + r) / 2, (t + b) / 2, FitZoom(id))
				if mod.onUserMapNav then mod.onUserMapNav(id) end
				zoomed = true
				break
			end
		end
		if not zoomed and u and v then
			local maxZ = MaxZoomAt(u, v)
			if maxZ and zoom < maxZ * 0.98 then
				GlideTo(u, v, math.min(maxZ, zoom * 1.85))
			end
		end
	elseif button == "RightButton" then
		-- (daves_map: right-clicking the waypoint pin removes it instead of zooming out)
		if from and mod.IsWaypointHovered and mod.IsWaypointHovered() and mod.ClearPin then
			mod.ClearPin()
			return true
		end
		if mod.ClearFlightRoute then mod:ClearFlightRoute() end
		-- (a city's map is its continent's child in the game's tables: out of it, its own zone comes
		-- first, as out of any other part of that zone; ns.MapCityZones, banners.py)
		-- (S.ChainAt puts it there itself now: kept for safety, not twice)
		local zone = ns.MapCityZones and ns.MapCityZones[chain[#chain]]
		if zone and chain[#chain - 1] ~= zone then tinsert(chain, #chain, zone) end
		local target = WORLD
		local deepestFit = FitZoom(WORLD)
		for _, id in ipairs(chain) do
			if id ~= WORLD and Stitchable(id) then
				local fz = FitZoom(id)
				if fz > deepestFit then deepestFit = fz end
				if fz < zoom * 0.95 then target = id end
			end
		end
		if zoom > deepestFit * 1.95 then
			GlideTo(vu or u, vv or v, math.max(deepestFit, zoom / 1.85))
		else
			local l, r, t, b = S.Rect(target)
			GlideTo((l + r) / 2, (t + b) / 2, FitZoom(target))
			if mod.onUserMapNav then mod.onUserMapNav(target) end
		end
	end
	return true
end

-- our icons: a press still drags the map, a click is the icon's
-- the map was grabbed (on it or on one of our icons)
local function OnGrab()
	userMoved = true
	waitingView = nil                 -- (the view is the user's again: not put back where it was as combat ends)
	if anim and (anim.mode == "glide" or anim.mode == "fly") then anim = nil end   -- a grab stops a glide where it is (daves_map: a flight too)
end

local function OnPinMouseDown(_, button)
	sc:OnMouseDown(button)
	PressDown(nil, button)
	OnGrab()
end

local function OnPinMouseUp(pin, button)
	local x, y = sc:GetCursorPosition()
	-- (daves_map: right-clicking a pin with OnRightClick - e.g. user waypoint - handles it without zooming out)
	if button == "RightButton" and pin.OnRightClick then
		if sc:WouldCursorPositionBeClick(button, x, y) or pin:IsMouseOver() then
			if sc.mouseButtonInfo and sc.mouseButtonInfo.RightButton then
				sc.mouseButtonInfo.RightButton.down = false
			end
			pin:OnRightClick()
			return
		end
	end
	if button ~= "LeftButton" or not sc:WouldCursorPositionBeClick(button, x, y) or WasDrag() then
		sc:OnMouseUp(button)
		return
	end
	sc.mouseButtonInfo.LeftButton.down = false
	if Dropping(button) and (not pin.isWaypoint or (mod.PinMode and mod.PinMode())) then DropAtCursor() return end
	if pin.OnClick then pin:OnClick() end
end

-- a click on one of Blizzard's map icons goes to its pin handlers, not the canvas's: dropping a
-- pin works there too (Blizzard's own only took Ctrl-clicks, never the menu's pin button)
local function OnBlizzardPinAction(_, action, button)
	if not Dropping(button) then return false end
	if action == MapCanvasMixin.MouseAction.Click then DropAtCursor() end
	return action ~= MapCanvasMixin.MouseAction.Up
end

-- one part of the setup, its time kept (ns.loadMs.parts: /openmap status)
local function Timed(name, fn, ...)
	if not fn then return end
	local t0 = debugprofilestop and debugprofilestop()
	fn(...)
	if t0 then ns.loadMs.parts[name] = debugprofilestop() - t0 end
end

local function Setup()
	local setupStart = debugprofilestop and debugprofilestop()
	map = _G.WorldMapFrame
	sc = map and map.ScrollContainer
	if not sc or not sc.CreateZoomLevels or not map.GetPinFrameLevelsManager or not map:GetPinFrameLevelsManager() then
		ns:Print(ns.L["World map: Blizzard's map isn't the expected kind; the seamless map is off."])
		return
	end
	wheelMode = sc.mouseWheelZoomMode or MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL
	scalingMode = sc.scalingMode or "SCALING_MODE_TRANSLATE_FASTER_THAN_SCALE"

	-- our art sits just above Blizzard's exploration overlays, our icons above the highlight
	local fl = map:GetPinFrameLevelsManager()
	local okArt = fl:InsertFrameLevelAbove("PIN_FRAME_LEVEL_DAVES_MAP_STITCH", "PIN_FRAME_LEVEL_MAP_EXPLORATION", ART_RANGE)
	local okIcons = fl:InsertFrameLevelAbove("PIN_FRAME_LEVEL_DAVES_MAP_STITCH_ICONS", "PIN_FRAME_LEVEL_MAP_HIGHLIGHT", 6)
	-- (and where they came out: the art over the exploration overlays, the icons over all of the art.
	-- Said, not acted on, till the real levels are known in game: /openmap status prints them. PR #22)
	local art = okArt and fl:GetValidFrameLevel("PIN_FRAME_LEVEL_DAVES_MAP_STITCH")
	local icons = okIcons and fl:GetValidFrameLevel("PIN_FRAME_LEVEL_DAVES_MAP_STITCH_ICONS")
	local explore = fl:GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION")
	if not (art and icons and explore and art > explore and icons > art + ART_RANGE) then
		ns:Print(ns.L["World map: Blizzard's map layers aren't the expected ones; the stitched art may cover some map icons."])
	end

	S.OnPinMouseDown, S.OnPinMouseUp = OnPinMouseDown, OnPinMouseUp
	S.GlideToWorld = function(u, v, zoom) GlideTo(u, v, math.max(zoom or 1, select(3, View()))) end
	-- glides until a world rectangle (normalized) just fills the view
	S.GlideToRect = function(u0, v0, u1, v1, fill)
		local W, H = S.Size()
		local z = math.min(sc:GetWidth() / ((u1 - u0) * W), sc:GetHeight() / ((v1 - v0) * H)) / FitPx()
		GlideTo((u0 + u1) / 2, (v0 + v1) / 2, z * (fill or 1))
	end
	S.OpenMap = function(mapID) KeepPadCursor(map.SetMapID, map, mapID) end
	S.Switching = function() return switching end   -- (the map underneath following the view, not another map put up)
	hooksecurefunc(sc, "CreateZoomLevels", Ours("zoom levels", OnCreateZoomLevels))
	local blizzardReset, ourReset = sc.ResetZoom, Ours("reset zoom", ResetView)
	sc.ResetZoom = function(self, ...)
		if active and not switching then return ourReset(self) end
		return blizzardReset(self, ...)
	end
	if map.RefreshDetailLayers then hooksecurefunc(map, "RefreshDetailLayers", BlizzardArt) end
	sc.CalculateScrollExtentsAtScale = Extents(sc.CalculateScrollExtentsAtScale)
	sc:HookScript("OnMouseWheel", OnMouseWheel)
	sc:HookScript("OnMouseDown", OnGrab)
	sc:HookScript("OnMouseDown", PressDown)
	-- Listen directly: Blizzard's canvas click dispatcher only tracks left/right buttons.
	sc:HookScript("OnMouseUp", function(_, button)
		if active and button == "MiddleButton" and mod.FindMe then mod:FindMe(true) end
	end)
	sc:HookScript("OnUpdate", Animate)
	sc:HookScript("OnUpdate", PressTrack)
	-- the gamepad (Forever's gamepad mode): its zoom stick is ours on the stitched map (PadZoom);
	-- its A (Blizzard's icons under the cursor, then this) presses OpenMap's control or icon under
	-- the cursor (Gamepad.lua), or else zooms in as a click does; its X, with no icon under the
	-- cursor, zooms out a map as a right-click does (Blizzard's would change the map underneath)
	if sc.IsGamepadZooming then
		local zooming = sc.IsGamepadZooming
		sc.IsGamepadZooming = function(self, ...)
			if active then return false end
			return zooming(self, ...)
		end
	end
	-- other addons' view changes (zoom remembered per map, keep centred, a jump into a cave) don't
	-- apply on the stitched map: its view is OpenMap's. Blizzard's own calls go through
	if sc.InstantPanAndZoom and debugstack then
		local pan = sc.InstantPanAndZoom
		sc.InstantPanAndZoom = function(self, ...)
			if active then
				local caller = (debugstack(2, 1, 0) or ""):match("AddOns[\\/]([^\\/]+)[\\/]")
				if caller and caller ~= "daves_map" and not caller:find("^Blizzard_") then return end
			end
			return pan(self, ...)
		end
	end
	if map.NavigateToGamepadCursor then
		local navigate = map.NavigateToGamepadCursor
		map.NavigateToGamepadCursor = function(self, ...)
			local x, y = PadCursor()
			-- (A has just clicked Blizzard's own icons under the cursor, GamepadMapClick's ClickHoveredPins:
			-- then OpenMap's icon there isn't pressed as well, only its windows over the map)
			local clicked = self.GetHoveredPin and self:GetHoveredPin() ~= nil
			if x and mod.PadPress and mod.PadPress(x, y, clicked) then return true end
			if not active then return navigate(self, ...) end
			if clicked then return true end
			return OnCanvasClick(nil, "LeftButton")
		end
	end
	-- the pad's waypoint (its left stick pressed: GamepadTryPlaceWaypoint) is set where the cursor is on
	-- the map underneath, clamped to its edge: on the stitched map, where the cursor is, on the zone there
	if map.GamepadTryPlaceWaypoint then
		hooksecurefunc(map, "GamepadTryPlaceWaypoint", function()
			if not active or not PadCursor() or not (C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return end
			local u, v = mod.CursorWorld()
			if u and mod.DropWaypoint then mod.DropWaypoint(u, v) end
		end)
	end
	if map.NavigateToParentMap then
		local up = map.NavigateToParentMap
		map.NavigateToParentMap = function(self, ...)
			if active and PadFocus() then return OnCanvasClick(nil, "RightButton") end
			return up(self, ...)
		end
	end
	map:AddCanvasClickHandler(OnCanvasClick, 1000)
	if map.AddGlobalPinMouseActionHandler and MapCanvasMixin and MapCanvasMixin.MouseAction then
		map:AddGlobalPinMouseActionHandler(OnBlizzardPinAction, 1000)
	end
	-- Blizzard's pin cursor while the menu's pin button is on
	if map.AddCursorHandler then
		map:AddCursorHandler(function() if active and mod.PinMode and mod.PinMode() then return "MAP_PIN_CURSOR" end end, 1000)
	end
	HookHighlight()
	-- a quest's details, Back: the map stays where you're looking (most likely at the quest's place,
	-- to pick another nearby). Blizzard puts back the map it was on when they opened, and a map Blizzard
	-- puts up shows whole: the view from just before that comes back
	if QuestMapFrame_ReturnFromQuestDetails then
		hooksecurefunc("QuestMapFrame_ReturnFromQuestDetails", function()
			local b = beforeReset
			if b and b.at == GetTime() and active and map:IsShown() then mod.ShowNow(b[1], b[2], b[3]) end
		end)
	end
	-- (daves_map: Layer.lua and Open.lua fly to opened quest details rather than snapping to the whole zone)

	local dp = CreateFromMixins(MapCanvasDataProviderMixin)
	dp.OnCanvasScaleChanged = Ours("scale changed", ApplyZoom)
	dp.OnCanvasPanChanged = ApplyView
	dp.OnMapChanged = function()
		HookHighlight()                             -- (a highlight pin made since: the toggle reaches it too, #262)
		ApplyZoom()
		if mod.OnHostMapChanged then mod.OnHostMapChanged() end
		if mod.RefreshPortrait then pcall(mod.RefreshPortrait) end   -- (OpenMap's icon only while stitching)
	end
	dp.OnHide = function()
		mod.instanceWorldBrowsing = nil
		mod.instanceMapGeneration = (mod.instanceMapGeneration or 0) + 1
		live = nil
		if mod.OnMapHidden then mod:OnMapHidden() end
		ticker:Hide()
	end
	local shown = Ours("map shown", function()
		HookHighlight()
		mod.instanceWorldBrowsing = nil
		mod.instanceMapGeneration = (mod.instanceMapGeneration or 0) + 1
		if (not (S.IsBuilt() and ExtrasBuilt()) or not zoomAttached) and map:GetMapID() then sc:OnCanvasSizeChanged() end   -- built on first showing
		mod:RefreshInstancePins()
		if mod.instanceWorldHidden then ticker:Show() RaisePlayer() end
		if active then
			ticker:Show()
			S.Recull()
			ApplyZoom()
			RaisePlayer()
		end
		if mod.OnMapShown then mod:OnMapShown() end
	end)
	dp.OnShow = function()
		if debugprofilestop then openStart, openOurs, openFrames, openParts = debugprofilestop(), 0, 0, {} openTimer:Show() end
		AfterOpening()
		shown()
	end
	map:AddDataProvider(dp)

	Timed("Extras", mod.SetupExtras, mod, map)
	Timed("Flights", mod.SetupFlights, mod)
	-- map closed: the world-wide re-grade waits for the next opening
	local exploredDirty, citiesDirty = false, false
	ns.RegisterEvent(mod, "MAP_EXPLORATION_UPDATED", function()
		if not S.IsBuilt() then return end
		if map:IsShown() then S.RefreshExplored() else exploredDirty = true end
	end)
	-- (into a city: found, though nothing was explored there just now)
	ns.RegisterEvent(mod, "ZONE_CHANGED_NEW_AREA", function()
		if not S.IsBuilt() then return end
		if map:IsShown() then S.RefreshCities() else citiesDirty = true end
	end)
	map:HookScript("OnShow", function()
		if not (exploredDirty or citiesDirty) then return end
		C_Timer.After(0, function()
			if not S.IsBuilt() then return end
			if exploredDirty then exploredDirty = false citiesDirty = false S.RefreshExplored()
			elseif citiesDirty then citiesDirty = false S.RefreshCities() end
		end)
	end)
	Timed("Nav", mod.SetupNav, mod, map)          -- (before the menu: it holds Nav's search box)
	Timed("Pins", mod.SetupPins, mod, map)
	Timed("Friends", mod.SetupFriends, mod, map)
	Timed("Quests", mod.SetupQuests, mod, map)
	Timed("Dungeons", mod.SetupDungeons, mod, map)
	Timed("Combat", mod.SetupCombat, mod, map)
	ns.RegisterEvent(viewOwner, "PLAYER_REGEN_ENABLED", mod.FlushWaitingView)
	-- (the map built ahead once the loading screen is gone: Prebuild)
	if not ns.RegisterEvent(prebuildOwner, "LOADING_SCREEN_DISABLED", PrebuildSoon) then
		ns.RegisterEvent(prebuildOwner, "PLAYER_ENTERING_WORLD", PrebuildSoon)
	end
	Timed("News", mod.SetupNews, mod)
	Timed("Panel", mod.SetupPanel, mod, map)
	Timed("Paint", mod.SetupPaint, mod, map)
	Timed("Sketch", mod.SetupSketch, mod, map)
	Timed("Debug", mod.SetupDebug, mod, map)
	Timed("Bench", mod.SetupBench, mod, map)
	Timed("Gamepad", mod.SetupGamepad, mod, map)
	Timed("Report", mod.SetupReport, mod, map)
	Timed("Window", mod.SetupWindow, mod, map)
	Timed("Compat", mod.SetupCompat, mod, map)

	if setupStart then ns.loadMs.setup = debugprofilestop() - setupStart end

	-- the map may already be showing something
	if map:IsShown() and map:GetMapID() then sc:OnCanvasSizeChanged() end
end

-- for Extras / Flights / Townsfolk / Panel / Paint
function mod.IsStitched() return active end
-- Unexplored areas: every character's (the account's setting), or this character's own once it has one
-- (Unexplored areas for this character, the menu's: mod.char.unexploredOwn)
function mod.Unexplored()
	local c = mod.char
	if c and c.unexploredOwn and c.unexplored then return c.unexplored end
	return mod.db.unexplored
end
function mod.SetUnexplored(v)
	local c = mod.char
	if c and c.unexploredOwn then c.unexplored = v else mod.db.unexplored = v end
	mod:Refresh()
end
function mod.SetUnexploredOwn(on)
	local c = mod.char
	if not c then return end
	if on and not c.unexploredOwn then c.unexplored = mod.db.unexplored end   -- (starts as it is now)
	c.unexploredOwn = on and true or nil
	mod:Refresh()
end
-- a zoom of the user's under way (the wheel's, a click's glide, the gamepad's stick): for Extras.lua's
-- icons resting while the map zooms (not a view put back, a map switch or the window laid out again)
function mod.Zooming() return anim ~= nil or GetTime() - (mod.padZoomAt or -10) < 0.2 end
function mod.WheelZoom(delta) if active then ZoomAtCursor(delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP) end end
-- the world point (normalized) under the cursor, and world units per view px
function mod.CursorWorld()
	if not active then return end
	local u, v, zoom = View()
	local sx, sy = CursorOffset()
	local pu, pv = PerPx(zoom)
	return u + sx * pu, v + sy * pv, pu, pv
end
-- the gamepad's cursor (screen px) while it's the one in use on the map, else nil
function mod.PadCursor() if sc then return PadCursor() end end
mod.ToWorld = function(mapID, x, y) return ToWorld(mapID, x, y) end
function mod.ViewHalfExtents(zoom)
	local pu, pv = PerPx(zoom)
	return sc:GetWidth() / 2 * pu, sc:GetHeight() / 2 * pv
end
-- for Nav.lua: glide / jump to a world point (normalized) at a zoom; the zoom where a map fits
function mod.Glide(u, v, zoom) if active then GlideTo(u, v, zoom) end end
function mod.Fly(u, v, zoom) if active then FlyTo(u, v, zoom) end end   -- (daves_map)
function mod.Flying() return anim ~= nil and anim.mode == "fly" end      -- (daves_map)
-- (daves_map) the view from just before Blizzard put up another map, in this same frame (a quest opened from the
-- tracker with the map open: it's shown whole at once; Layer.lua flies there from this instead)
function mod.ViewBeforeReset()
	local b = beforeReset
	if b and b.at == GetTime() then return b[1], b[2], b[3] end
end
function mod.ShowNow(u, v, zoom) if active then anim = nil ShowWorld(u, v, Clamp(zoom, LeastZoom(), MaxZoomAt(u, v))) userMoved = true end end
-- for Bench.lua: the view heads for a world point (normalized) the way a drag moves it, Blizzard's
-- scroll easing there over the next frames; and whether a zoom or glide of ours is running
function mod.PanTo(u, v)
	if not active then return end
	local x, y = FromWorld(map:GetMapID(), u, v)
	sc.targetScrollX = Clamp(x, sc.scrollXExtentsMin, sc.scrollXExtentsMax)
	sc.targetScrollY = Clamp(y, sc.scrollYExtentsMin, sc.scrollYExtentsMax)
end
function mod.Animating() return anim ~= nil end
function mod.FitZoom(mapID) return FitZoom(mapID) end
-- the deepest zoom (the menu's slider and the options): the zoom levels are rebuilt for it
function mod.SetMaxZoom(v)
	mod.db.maxZoom = math.max(MAX_ZOOM[1], math.min(MAX_ZOOM[2], v))
	if map and active then KeepPadCursor(sc.OnCanvasSizeChanged, sc) end
end
function mod.HostMap() return active and map:GetMapID() or nil end
-- the close-up layers again, for the view as it is (a setting changed)
function mod.RefreshView() ApplyView() end
mod.FromWorld = function(mapID, u, v) return FromWorld(mapID, u, v) end
-- the view now: centre (normalized), zoom; nil when the map isn't stitched
function mod.ViewNow() if active then return View() end end
-- for Extras.lua, placing other addons' icons: the view's centre and half extents (world, normalized),
-- the one a map switch is for while it puts the new map up (the view is set after it)
function mod.PinView()
	if not active then return end
	local u, v, zoom
	if switchView then u, v, zoom = switchView[1], switchView[2], switchView[3] else u, v, zoom = View() end
	local hu, hv = mod.ViewHalfExtents(zoom)
	return u, v, hu, hv
end

-- The Gamepad UI and OpenMap's map don't mix. The UI sets the controller's buttons on the map again on
-- every map change, and on OpenMap's map those changes (and the view they read) are OpenMap's code,
-- not Blizzard's: the buttons then run as OpenMap's, and closing the map with B does what only
-- Blizzard's code may ("OpenMap has been blocked from an action only available to the Blizzard UI").
-- With the Gamepad UI on at login OpenMap leaves the map alone, touching nothing of it, until the UI
-- is off; turned on later, the map is OpenMap's already and only a reload gives it back. Options'
-- padMap keeps OpenMap's map with the Gamepad UI too: Gamepad.lua binds B and the full-screen buttons
-- to secure clicks of the map's own buttons, which the game doesn't block (mod.PadKeys)
local started = false
local function Start()
	started = true
	if _G.WorldMapFrame then
		Setup()
	elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
		EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Setup)
	end
end

-- (said once at login, and whenever /openmap or the options are opened while it waits)
function mod.PadOffText()
	return ns.L["The Gamepad UI is on, so OpenMap leaves the world map to Blizzard: with OpenMap's map the game blocks the controller's buttons (B to close the map). Turn the Gamepad UI off for OpenMap's map."]
end

local styleOwner = {}
local function StyleChanged()
	if PadUI() then
		if started and not mod.db.padMap then ns:Print(ns.L["The Gamepad UI is on: /reload so OpenMap leaves the world map to Blizzard (until then the game may block closing the map with the controller)."]) end
	elseif mod.padWaits then
		if InCombatLockdown() then      -- (set up out of combat, as at login)
			ns.RegisterEvent(styleOwner, "PLAYER_REGEN_ENABLED", function()
				ns.UnregisterEvent(styleOwner, "PLAYER_REGEN_ENABLED")
				StyleChanged()
			end)
			return
		end
		-- (the controller view built: the art is on its frame, not Blizzard's map: a reload gives it back)
		if mod.PadViewBuilt and mod.PadViewBuilt() then return end
		mod.padWaits = nil
		mod.enabled = true
		Start()
		ns:Print(ns.L["The Gamepad UI is off: OpenMap's map is back."])
	end
end

-- Options' padMap turned on or off: on, while OpenMap waits for the Gamepad UI to go, its map at once
-- (in combat, once it's over: set up out of combat, as at login); off with the Gamepad UI on and the
-- map OpenMap's, only a reload gives it back
local padMapOwner = {}
function mod.SetPadMap(on)
	if on and mod.padWaits and not InCombatLockdown() then
		mod.padWaits = nil
		mod.enabled = true
		Start()
	elseif on and mod.padWaits then
		ns.RegisterEvent(padMapOwner, "PLAYER_REGEN_ENABLED", function()
			ns.UnregisterEvent(padMapOwner, "PLAYER_REGEN_ENABLED")
			if mod.db.padMap then mod.SetPadMap(true) end   -- (not turned off again meanwhile)
		end)
	elseif not on and started and PadUI() then
		ns:Print(ns.L["The Gamepad UI is on: /reload so OpenMap leaves the world map to Blizzard (until then the game may block closing the map with the controller)."])
	end
	if mod.PadKeys then mod.PadKeys() end
end

-- Options' padView turned on or off: on, while OpenMap waits for the Gamepad UI to go, its map over
-- Blizzard's at once (PadView.lua); off once it's up, a reload (it's set up on Blizzard's map)
function mod.SetPadView(on)
	if on and mod.padWaits and mod.StartPadView then
		mod.StartPadView()
	elseif not on and mod.PadViewBuilt and mod.PadViewBuilt() then
		ns:Print(ns.L["Takes effect after a /reload."])
	end
end

function mod:OnEnable()
	if self.db.hideWorldPinsInInstances then   -- (daves_map: avoid registering GLOBAL_MOUSE_UP when disabled)
		self.instancePinsEvents = self.instancePinsEvents or {}
		for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
			ns.RegisterEvent(self.instancePinsEvents, event, function() mod:RefreshInstancePins() end)
		end
		ns.RegisterEvent(self.instancePinsEvents, "GLOBAL_MOUSE_UP", function(_, _, button)
			if button ~= "RightButton" or not mod.instancePinsHidden or mod.db.dungeonMaps ~= false
				or mod.instanceWorldBrowsing or not map or not map:IsShown() or not sc:IsMouseOver()
				or (mod.MenuShown and mod.MenuShown()) then return end
			local generation = mod.instanceMapGeneration
			-- NeedRoll also watches this event. Let its handler dismiss the overlay first.
			C_Timer.After(0, function()
				if generation == mod.instanceMapGeneration then mod:BrowseInstanceWorld() end
			end)
		end)
	end
	mod:RefreshInstancePins()
	ns.RegisterEvent(styleOwner, "INPUT_DEVICE_INTERFACE_TRANSITION", StyleChanged)
	if PadUI() and not self.db.padMap then
		self.enabled, self.padWaits = false, true
		-- (padView: OpenMap's map on a frame of its own over Blizzard's, which it leaves alone)
		if self.db.padView and mod.StartPadView then
			mod.StartPadView()
			return
		end
		if not self.db.padNoted then
			self.db.padNoted = true
			ns:Print(mod.PadOffText())
		end
		return
	end
	Start()
end

-- which pin sets each option shows
local SET_OPTION = { dungeons = "icons", boats = "boats", zeppelins = "zeppelins", flight = "flight", routes = "routes" }

-- the sea chart as Options has it, the view kept where it was (the least zoom and the reach change with it)
local function ApplyChart()
	if not S.Chart or not sc or (S.Chart.on == (mod.db.chart and true or false)) then return end
	local u, v, zoom
	if active and map:IsShown() then u, v, zoom = View() end
	S.Chart.SetShown(mod.db.chart)
	if active then
		sc:CreateZoomLevels()                       -- (ours: OnCreateZoomLevels, from the new least zoom)
		if u then ShowWorld(u, v, Clamp(zoom, LeastZoom(), MaxZoomAt(u, v))) end
	end
end

function mod.InstanceWorldHidden(mapID)
	-- A real dungeon map keeps its native player/group positions. Only suspend a world host.
	return mod.instancePinsHidden and not mod.instanceWorldBrowsing and mod.db.dungeonMaps == false
		and Stitchable(mapID or (map and map:GetMapID())) or false
end

function mod:RefreshInstancePins(onlyPins)
	-- Use the player's instance, not the displayed map: NeedRoll can keep a world map as host.
	local inside, kind = IsInInstance()
	inside, kind = ns.Safe.Value(inside), ns.Safe.Value(kind)
	self.instancePinsHidden = self.db.hideWorldPinsInInstances and inside
		and (kind == "party" or kind == "raid" or kind == "pvp" or kind == "arena") or false
	if not self.instancePinsHidden then self.instanceWorldBrowsing = nil end
	if not inside and self.RememberOutsideInstance then self.RememberOutsideInstance() end
	S.SetWorldPinsHidden(self.instancePinsHidden and not self.instanceWorldBrowsing)
	if not onlyPins and map and sc and S.IsBuilt()
		-- (nil before the first Attach counts as false: nil ~= false attached the map during its first build, while
		-- the canvas was still 0 x 0, and every view after that was NaN: #261, found by OlehPetrykUA)
		and (self.instanceWorldHidden or false) ~= self.InstanceWorldHidden(map:GetMapID()) then
		Attach(map:GetMapID(), true)
	end
end

function mod:BrowseInstanceWorld()
	if not self.instancePinsHidden or self.db.dungeonMaps ~= false or self.instanceWorldBrowsing
		or not map or not map:IsShown() or not Stitchable(map:GetMapID()) then return end
	self.instanceWorldBrowsing = true
	self:RefreshInstancePins()
	sc:CreateZoomLevels()
	local u, v, zoom
	if self.InstanceEntranceView then u, v, zoom = self.InstanceEntranceView() end
	if not u and self.outsideInstanceView then
		local last = self.outsideInstanceView
		u, v = last[1], last[2]
		zoom = math.min(self.FitZoom(last[3]), self.db.maxZoom or math.huge)
	end
	if u then self.ShowNow(u, v, zoom) end
	self:Refresh()
end

function mod:Refresh()
	self:RefreshInstancePins()
	ApplyChart()
	self:UpdateBrightness()
	for key, opt in pairs(SET_OPTION) do
		local set = S.GetPinSet(key)
		if set then S.SetPinSetOn(set, self.db[opt]) end
	end
	if S.RefreshRoutes then S.RefreshRoutes() end
	S.SetPlayerHidden(self.db.playerArrow == false)
	if active and map:IsShown() then RaisePlayer() end
	S.SetPlacesFrom(self.db.iconsFrom)
	S.SetFoundOnly(self.db.foundOnly)
	if self.RefreshFlightsFound then self.RefreshFlightsFound() end
	S.SetIconScale(self.db.iconScale or 1)
	S.SetGapFillsShown(self.db.gapFills ~= false)       -- (before the grade: it decides on the baked tiles)
	if S.SetDarkening then S.SetDarkening(self.db.darkening or 1, self.db.darkenColor or nil) end
	S.ApplyGrade(self.db.colorMatch, self.db.desaturate, mod.Unexplored())
	ApplyZoom()
	if self.RefreshExtras then self.RefreshExtras() end
	if self.RefreshTownsfolk then self:RefreshTownsfolk() end
	if self.RefreshQuests then self:RefreshQuests() end
	if self.RefreshDungeonCard then self.RefreshDungeonCard() end
	if self.RefreshSketch then self.RefreshSketch() end
	if self.RefreshFriends then self.RefreshFriends() end
	if self.RefreshPanel then self:RefreshPanel() end
end

-- /openmap status: what the map is doing
function mod:Diag()
	-- what loading cost: its files, the login, the map's setup (its dearest parts)
	local lm = ns.loadMs
	local parts = {}
	for name, ms in pairs(lm.parts) do parts[#parts + 1] = { name, ms } end
	table.sort(parts, function(x, y) return x[2] > y[2] end)
	local top = {}
	for i = 1, math.min(5, #parts) do top[i] = ("%s %.0f"):format(parts[i][1], parts[i][2]) end
	ns:Print("Loading: files %.0f ms, login %.0f ms (the map's setup %.0f: %s); building the map %.0f ms (%s).", lm.files or 0,
		lm.login or 0, lm.setup or 0, table.concat(top, ", "), lm.build or 0,
		lm.build == nil and "not yet" or lm.builtShown and "as it opened" or "before it was opened")
	if not map or not sc or not S.IsBuilt() then
		ns:Print("World map: not built yet (it's built the first time the map opens).")
		return
	end
	local fl = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
	if fl then
		local _, explore = pcall(fl.GetValidFrameLevel, fl, "PIN_FRAME_LEVEL_MAP_EXPLORATION")
		local _, art = pcall(fl.GetValidFrameLevel, fl, "PIN_FRAME_LEVEL_DAVES_MAP_STITCH")
		local _, icons = pcall(fl.GetValidFrameLevel, fl, "PIN_FRAME_LEVEL_DAVES_MAP_STITCH_ICONS")
		ns:Print("Frame levels: exploration %s, art %s (+%d), icons %s.", tostring(explore), tostring(art), ART_RANGE, tostring(icons))
	end
	local mapID = map:GetMapID()
	local info = C_Map.GetMapInfo(mapID)
	ns:Print("World map: %s (%d), %s, zoom %.2f, scale %.3f, %d zones / %d base tiles / %d overlay tiles / %d icons.",
		info and info.name or "?", mapID or 0, active and "stitched" or "Blizzard's",
		active and select(3, View()) or 0, sc:GetCanvasScale(),
		S.stats.zones, S.stats.tiles, S.stats.overlays, S.stats.pins)
	local fixed, live = S.RegionCount()
	local kb
	if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
		kb = GetAddOnMemoryUsage(ns.name)
	end
	ns:Print("World map: %d art regions, %d live ones; addon memory %s.", fixed, live, kb and ("%.1f MB"):format(kb / 1024) or "?")
	if map:IsVisible() then
		ns:Print("Drawing %d of the art's textures now; %.0f frames a second.", S.DrawnCount(), GetFramerate())
	else
		ns:Print("The map is closed: open it and run this again for what it's drawing.")
	end
	if #openTimes > 0 then
		local list = {}
		for i, t in ipairs(openTimes) do list[i] = ("%.0f (OpenMap %.0f)"):format(t[1], t[2]) end
		ns:Print("Opening the map took %s ms, latest first; the rest is the game and other addons.", table.concat(list, ", "))
		local parts = {}
		for name, ms in pairs(openLast) do parts[#parts + 1] = { name, ms } end
		table.sort(parts, function(a, b) return a[2] > b[2] end)
		for i, p in ipairs(parts) do parts[i] = ("%s %.0f"):format(p[1], p[2]) end
		if #parts > 0 then ns:Print("  the latest, by part (ms; parts can run inside each other): %s.", table.concat(parts, ", ")) end
	end
	if after.start then
		ns:Print("In the %d s after the latest opening: the longest frame %.0f ms, %.1f s in; OpenMap's later work, slowest (ms): %s.",
			AFTER_OPEN, after.gap, after.gapAt / 1000, Worst(after.parts))
	end
	if next(after.close) then ns:Print("As the map last closed (ms): %s.", Worst(after.close)) end
	if mod.dungeonOpenMs then ns:Print("Opening the latest dungeon's map took %.0f ms (OpenMap's part).", mod.dungeonOpenMs) end
	if mod.FlightStatus then ns:Print("%s", mod.FlightStatus()) end
	if mod.QuestsStatus then ns:Print("%s", mod.QuestsStatus()) end
	local registered, shown, placed, ours, moved
	if mod.QuestieStatus then registered, shown, placed, ours, moved = mod.QuestieStatus() end
	if registered then
		ns:Print("Questie: %d map icons, %d on this map (%d placed by Questie, %d of those moved to Forever's positions, %d placed by OpenMap), map %d.",
			registered, shown, placed, moved, ours, map:GetMapID() or 0)
	end
	local kinds = mod.QuestieKinds and mod.QuestieKinds()
	if kinds then ns:Print("Questie's icons by kind (all / on this map): %s.", kinds) end
	local lost = mod.QuestieLost and mod.QuestieLost()
	if lost then
		ns:Print("Questie's pins: %d; pin hidden %d, no icon %d, icon off its pin %d, icon hidden %d, see-through %d, under the art %d.",
			lost.pins, lost.pinHidden, lost.noIcon, lost.offPin, lost.hidden, lost.faint, lost.under)
		local k = math.max(lost.pins - lost.noIcon, 1)
		ns:Print("Questie's icons: %d visible; on screen %.1f px across on average (scale %.2f, pins' own %.2f); top level %d, art's top %d.",
			lost.visible, lost.size / k, lost.scale / k, lost.pinScale / k, lost.level, S.artTop or 0)
	end
	local cv = S.closeView or {}
	ns:Print("Up close: zoom %.1f, softening %.0f%%, minimap %.0f%% (%d tiles, %d in the gaps); %d view updates, the last %.1fs ago; %.2f ms each (worst %.1f).",
		cv.zoom or 0, (cv.soft or 0) * 100, (cv.mix or 0) * 100, cv.tiles or 0, cv.gapTiles or 0,
		cv.updates or 0, cv.time and (GetTime() - cv.time) or -1, cv.ms or 0, cv.worst or 0)
	cv.worst = 0
	-- its slowest steps (by their worst), so a slow update says where the time went
	local steps = {}
	for name, s in pairs(S.closeSteps or {}) do steps[#steps + 1] = { name, s } end
	table.sort(steps, function(a, b) return a[2].worst > b[2].worst end)
	local list = {}
	for i = 1, math.min(3, #steps) do
		list[i] = ("%s %.1f (worst %.1f)"):format(steps[i][1], steps[i][2].ms, steps[i][2].worst)
		steps[i][2].worst = 0
	end
	if #list > 0 then ns:Print("Slowest steps, ms: %s.", table.concat(list, "; ")) end
	-- and the zoom update's (S.SetZoom, "scale changed" when the map opens)
	steps = {}
	for name, st in pairs(S.zoomSteps or {}) do steps[#steps + 1] = { name, st } end
	table.sort(steps, function(a, b) return a[2].worst > b[2].worst end)
	list = {}
	for i = 1, math.min(4, #steps) do
		list[i] = ("%s %.1f (worst %.1f)"):format(steps[i][1], steps[i][2].ms, steps[i][2].worst)
		steps[i][2].worst = 0
	end
	if #list > 0 then ns:Print("Zoom update, slowest parts, ms: %s.", table.concat(list, "; ")) end
	for name, err in pairs(S.closeFailed or {}) do ns:Print("|cffff6060%s failed:|r %s", name, err) end
end

--------------------------------------------------------------------------------
-- Waypoints (daves_map: adapted from OpenMap/Map/Nav.lua so Ctrl-click and the
-- World Map's top-right Map Pin button place & display user waypoints across
-- the entire stitched map, even when the host map is WORLD or another zone)
--------------------------------------------------------------------------------
do
	local Safe = ns.Safe
	local wpSet, RefreshWaypoint
	local pinArmed = false
	local WAYPOINT_TRACKED = { atlas = "Waypoint-MapPin-Tracked", texture = "Interface\\Minimap\\Ping\\ping5", size = 30 }
	local WAYPOINT_UNTRACKED = { atlas = "Waypoint-MapPin-Untracked", texture = "Interface\\Minimap\\Ping\\ping5", size = 30 }

	local function BlizzardPin()
		if not (C_Map.HasUserWaypoint and C_Map.GetUserWaypoint) then return end
		local ok, has = pcall(C_Map.HasUserWaypoint)
		if not ok or not has then return end
		local point = C_Map.GetUserWaypoint()
		if point and point.position then
			local x, y = Safe.XY(point.position)
			return point.uiMapID, x, y
		end
	end

	local function HideBlizzardPin()
		if not active or not map or not map.EnumeratePinsByTemplate then return end
		for pin in map:EnumeratePinsByTemplate("WaypointLocationPinTemplate") do pin:Hide() end
	end

	local function ClearPin()
		if C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
		end
		if mod.char then mod.char.pin = nil end
		local tipOwner = GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
		if tipOwner and tipOwner.isWaypoint then GameTooltip:Hide() end
		if SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_REMOVE then PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_REMOVE) end
		RefreshWaypoint()
	end

	local function PinClick()
		if IsModifiedClick and IsModifiedClick("CHATLINK") then
			local ok, link = pcall(C_Map.GetUserWaypointHyperlink or nop)
			if ok and link then
				local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
				if insert then insert(link) end
			end
			return
		end
		if IsControlKeyDown() and C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.SetSuperTrackedUserWaypoint then
			local track = not C_SuperTrack.IsSuperTrackingUserWaypoint()
			pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, track)
			if SOUNDKIT then
				PlaySound(track and SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON or SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_OFF)
			end
			RefreshWaypoint()
			return
		end
		ClearPin()
	end

	function mod.WaypointPoint()
		local mapID, x, y = BlizzardPin()
		if mapID then
			if mod.char then mod.char.pin = nil end
			return mapID, x, y, false
		end
		local own = mod.char and mod.char.pin
		if own then return own[1], own[2], own[3], true end
	end

	function RefreshWaypoint()
		if not wpSet then return end
		S.ClearPinSet(wpSet)
		local mapID, x, y, own = mod.WaypointPoint()
		HideBlizzardPin()
		if not mapID or not S.Rect(mapID) then return end
		local tracked = own or not (C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint) or C_SuperTrack.IsSuperTrackingUserWaypoint()
		local u, v = ToWorld(mapID, x, y)
		local pin = S.AddPin(wpSet, u, v, tracked and WAYPOINT_TRACKED or WAYPOINT_UNTRACKED)
		pin.owningMap = map
		pin.isWaypoint = true
		pin:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local info = C_Map.GetMapInfo(mapID)
			GameTooltip:AddLine(ns.L["Waypoint"], 1, 0.82, 0)
			GameTooltip:AddLine(("%s  %.1f, %.1f"):format(info and info.name or "", x * 100, y * 100), 1, 1, 1)
			GameTooltip:AddLine(ns.L["Left/Right-click to clear waypoint"], 0.6, 0.6, 0.6)
			if not own then
				GameTooltip:AddLine(ns.L["Ctrl-click to toggle super tracking"], 0.6, 0.6, 0.6)
				GameTooltip:AddLine(ns.L["Shift-click to share in chat"], 0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
		end)
		pin:SetScript("OnLeave", GameTooltip_Hide)
		pin.OnClick = PinClick
		pin.OnRightClick = ClearPin
	end

	function mod.TrackPoint(mapID, x, y, _, fromButton)
		local blizzard = false
		if C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
			and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(mapID)) then
			blizzard = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(mapID, x, y)) and BlizzardPin() ~= nil
			if blizzard and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
			end
		end
		if mod.char then mod.char.pin = not blizzard and { mapID, x, y } or nil end
		if SOUNDKIT then
			PlaySound(fromButton and SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE or SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK)
		end
		RefreshWaypoint()
	end

	function mod.DropWaypoint(u, v, fromButton)
		if not u or not Safe.Finite(u, v) then return end
		local chain = S.ChainAt(u, v)
		local mapID
		for i = #chain, 1, -1 do
			local id = chain[i]
			if id ~= WORLD then
				local x, y = FromWorld(id, u, v)
				if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
					if not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(id) then
						mapID = id
						break
					elseif not mapID then
						mapID = id
					end
				end
			end
		end
		if not mapID then return end
		local x, y = FromWorld(mapID, u, v)
		mod.TrackPoint(mapID, x, y, nil, fromButton)
	end

	function mod.PinMode() return pinArmed end

	function mod.SetPinMode(on)
		pinArmed = on and true or false
		local btn = map and map.WorldMapTrackingPinButton
		if btn and btn.SetActive and (btn.isActive and true or false) ~= pinArmed then
			btn:SetActive(pinArmed)
		end
		if mod.OnPinMode then mod.OnPinMode(pinArmed) end
	end

	function mod.ClearPin() ClearPin() end

	function mod.IsWaypointHovered()
		if not (wpSet and wpSet.pins) then return false end
		for _, pin in ipairs(wpSet.pins) do
			if pin:IsVisible() and pin:IsMouseOver() then return true end
		end
		return false
	end

	function mod:FindMe(keepZoom)
		if not mod.IsStitched() then return false end
		local best = Safe.Call(C_Map.GetBestMapForUnit, "player")
		local u, v
		if best and S.Rect(best) then
			local pos = Safe.Call(C_Map.GetPlayerMapPosition, best, "player")
			local x, y = Safe.XY(pos)
			if not Safe.IsSecret(x) and not Safe.IsSecret(y) and x and y and (x ~= 0 or y ~= 0) then
				u, v = ToWorld(best, x, y)
			end
		end
		if not u then
			local host = mod.HostMap and mod.HostMap()
			local pos = host and Safe.Call(C_Map.GetPlayerMapPosition, host, "player")
			local x, y = Safe.XY(pos)
			if not Safe.IsSecret(x) and not Safe.IsSecret(y) and x and y and (x ~= 0 or y ~= 0) then
				u, v = ToWorld(host, x, y)
				best = host
			end
		end
		if not u then return false end
		local _, _, zoom = mod.ViewNow()
		mod.Glide(u, v, keepZoom and zoom or math.max(zoom or 1, mod.FitZoom(best)))
		if mod.onUserMapNav then mod.onUserMapNav(best) end
		return true
	end

	function mod:BuildNav()
		local wpOffset = 20
		local fl = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
		if fl and fl.GetValidFrameLevel and S.iconLevel then
			local ok, lvl = pcall(fl.GetValidFrameLevel, fl, "PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
			if ok and type(lvl) == "number" and lvl > S.iconLevel then
				wpOffset = math.max(20, lvl - S.iconLevel)
			end
		end
		wpSet = S.PinSet("waypoint", 0, wpOffset)
		RefreshWaypoint()
	end

	function mod:SetupNav(worldMap)
		if type(worldMap.OnMapChanged) == "function" then
			hooksecurefunc(worldMap, "OnMapChanged", function() -- taint-hook: ok
				local ok, err = pcall(mod.RefreshNav, mod)
				if not ok then geterrorhandler()(err) end
			end)
		end
		ns.RegisterEvent(mod, "USER_WAYPOINT_UPDATED", RefreshWaypoint)
		ns.RegisterEvent(mod, "SUPER_TRACKING_CHANGED", RefreshWaypoint)
		for provider in pairs(worldMap.dataProviders or {}) do
			if type(provider) == "table" and provider.OnWayPointLocationToggleUpdate and provider.RefreshAllData then
				hooksecurefunc(provider, "RefreshAllData", HideBlizzardPin) -- taint-hook: ok
			end
		end
		if worldMap.RegisterCallback then
			worldMap:RegisterCallback("WaypointLocationToggleUpdate", function(_, isActive)
				pinArmed = isActive and true or false
			end, mod)
		end
		local btn = worldMap.WorldMapTrackingPinButton
		if btn then
			if btn.Refresh then
				hooksecurefunc(btn, "Refresh", function(self) -- taint-hook: ok
					if active then
						self:Enable()
						if self.DesaturateHierarchy then self:DesaturateHierarchy(0) end
					end
				end)
			end
			btn:HookScript("OnEnter", function(self)
				if active and C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(worldMap:GetMapID()) then
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip_SetTitle(GameTooltip, MAP_PIN)
					GameTooltip_AddNormalLine(GameTooltip, MAP_PIN_TOOLTIP)
					GameTooltip_AddBlankLineToTooltip(GameTooltip)
					GameTooltip_AddInstructionLine(GameTooltip, MAP_PIN_TOOLTIP_INSTRUCTIONS)
					GameTooltip:Show()
				end
			end)
		end
	end

	function mod:RefreshNav()
		RefreshWaypoint()
		local btn = map and map.WorldMapTrackingPinButton
		if active and btn and btn.Refresh then btn:Refresh() end
	end
end
