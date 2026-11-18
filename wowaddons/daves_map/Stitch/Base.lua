-- daves_map / Stitch / Base.lua
-- The seamless world map & dungeon maps: OpenMap's (MIT licence, Stitch\LICENSE-OpenMap.txt), bundled in daves_map.
-- Every zone's art stitched into one canvas inside Blizzard's map, zooming from the whole world down to street level
-- and out of one zone into the next, plus multi-floor dungeon & raid maps. Stitch.lua (the art), WorldMap.lua (the
-- view and zoom), Close.lua (the closest zooms), Dungeons.lua (dungeon & raid maps) and Combat.lua (Blizzard's pins in
-- combat) are OpenMap's files with as few changes as possible, so a new OpenMap release can be taken in by comparing
-- them; each change is marked "daves_map". This file stands in for OpenMap's Core.lua.
--
-- The art and data tables live in the companion addon daves_map_textures (built by tools\Update-MapTextures.py).
-- OpenMap's code and tables run in their own sub-namespace (dm.OM), apart from daves_map's own: no name of OpenMap's
-- can clash with one of ours. Without daves_map_textures installed, dm.OM is nil and Blizzard's map runs as usual.
--
-- Settings: daves_mapDB.stitch.worldmap (account) and daves_mapCharDB.stitch.worldmap (character), filled from the
-- module's defaults. The map starts at login unless the real OpenMap is loaded (two copies would fight over
-- Blizzard's map) or its `enabled` is off (Options: "Seamless world map", takes a reload).

local ADDON, dm = ...
local ns = type(DAVES_MAP_TEXTURES) == "table" and DAVES_MAP_TEXTURES.texturesAddon and DAVES_MAP_TEXTURES or nil
dm.OM = ns
if not ns then return end

ns.name = ADDON
ns.loadMs = { start = debugprofilestop and debugprofilestop(), parts = {} }
-- translations: OpenMap's English text as it is
ns.L = setmetatable({}, { __index = function(_, k) return k end })

function ns:Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or tostring(fmt)
	dm.Print(msg)
end

---------------------------------------------------------------------------
-- Secret-safe reads (as OpenMap's Core.lua)
---------------------------------------------------------------------------
local Safe = {}
ns.Safe = Safe

function Safe.IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

function Safe.Value(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

-- a position's x, y: Blizzard's vectors have GetXY, some APIs hand back a plain { x, y }
function Safe.XY(vec)
	if type(vec) ~= "table" then return end
	if vec.GetXY then return vec:GetXY() end
	return vec.x, vec.y
end

-- a plain number that's neither NaN nor infinite (a view worked out while the map is 0 px across
-- divides by zero: one such view put into the map left it blank until a reload, #260 #261)
function Safe.Finite(...)
	for i = 1, select("#", ...) do
		local n = select(i, ...)
		if type(n) ~= "number" or Safe.IsSecret(n) or n ~= n or n == math.huge or n == -math.huge then return false end
	end
	return true
end

-- fn(...)'s first result when it is plain, else nil
function Safe.Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok then return nil end
	return Safe.Value(v)
end

---------------------------------------------------------------------------
-- Events: any number of handlers per event, keyed by owner
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
eventFrame:SetScript("OnEvent", function(_, event, ...)
	for owner, fn in pairs(handlers[event] or {}) do
		local ok, err = pcall(fn, owner, event, ...)
		if not ok then geterrorhandler()(err) end
	end
end)

function ns.RegisterEvent(owner, event, fn)
	if not handlers[event] then
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
		handlers[event] = {}
	end
	handlers[event][owner] = fn or owner[event]
	return true
end

function ns.UnregisterEvent(owner, event)
	local list = handlers[event]
	if not list then return end
	list[owner] = nil
	if next(list) == nil then
		handlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

---------------------------------------------------------------------------
-- Look: fonts and dark panels (used by Dungeons.lua, from OpenMap's Core.lua)
---------------------------------------------------------------------------
local Look = {}
ns.Look = Look

function Look:Font(fs, size, flags)
	if not fs:SetFont(STANDARD_TEXT_FONT, size or 12, flags or "") then
		fs:SetFontObject(GameFontHighlight)
	end
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	return fs
end

function Look:Panel(frame, opts)
	opts = opts or {}
	local bd = frame.omBackdrop
	if not bd then
		bd = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		bd:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
		frame.omBackdrop = bd
	end
	local inset = opts.inset or 0
	bd:ClearAllPoints()
	bd:SetPoint("TOPLEFT", -inset, inset)
	bd:SetPoint("BOTTOMRIGHT", inset, -inset)
	bd:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	bd:SetBackdropColor(0.06, 0.06, 0.07, opts.alpha or 0.9)
	bd:SetBackdropBorderColor(0, 0, 0, 1)
	return bd
end

function Look:Dropdown(frame)
	if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("common-dropdown-bg") then
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAtlas("common-dropdown-bg")
		bg:SetPoint("TOPLEFT", -10, 3)
		bg:SetPoint("BOTTOMRIGHT", 10, -3)
		bg:SetAlpha(0.925)
		return 8, 8, 8, 15
	end
	local bd = Look:Panel(frame, { alpha = 0.97 })
	bd:SetBackdropBorderColor(0.66, 0.49, 0.28, 1)
	return 6, 6, 6, 6
end

---------------------------------------------------------------------------
-- The module ("worldmap", WorldMap.lua): settings and start
---------------------------------------------------------------------------
ns.modules = {}

function ns:NewModule(key, spec)
	local mod = spec or {}
	mod.key = key
	mod.defaults = mod.defaults or {}
	if mod.defaults.enabled == nil then mod.defaults.enabled = true end
	mod.padRoots = mod.padRoots or {}
	ns.modules[key] = mod
	return mod
end

function ns:GetModule(key)
	return ns.modules[key]
end

local function Fill(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then
			t[k] = type(v) == "table" and Fill({}, v) or v
		elseif type(v) == "table" and type(t[k]) == "table" then
			Fill(t[k], v)
		end
	end
	return t
end

-- every number in a saved table (and the tables in it) that isn't finite, removed (#306)
function ns.ScrubSaved(t, seen)
	if type(t) ~= "table" then return end
	seen = seen or {}
	if seen[t] then return end
	seen[t] = true
	for k, v in pairs(t) do
		if type(v) == "number" and not Safe.Finite(v) then t[k] = nil
		elseif type(v) == "table" then ns.ScrubSaved(v, seen) end
	end
end

-- daves_map's ADDON_LOADED (Core.lua): every file has added its defaults by then
function dm.InitStitch(db, char)
	db.stitch = type(db.stitch) == "table" and db.stitch or {}
	char.stitch = type(char.stitch) == "table" and char.stitch or {}
	for key, mod in pairs(ns.modules) do
		mod.fresh = db.stitch[key] == nil
		db.stitch[key] = db.stitch[key] or {}
		if not mod.fresh and mod.Migrate then mod.Migrate(db.stitch[key]) end
		mod.db = Fill(db.stitch[key], mod.defaults)
		char.stitch[key] = char.stitch[key] or {}
		mod.char = char.stitch[key]
	end
	if not ns.scrubOwner then
		ns.scrubOwner = {}
		ns.RegisterEvent(ns.scrubOwner, "PLAYER_LOGOUT", function()
			ns.ScrubSaved(db.stitch)
			ns.ScrubSaved(char.stitch)
		end)
	end
end

-- OpenMap itself is installed and on for this character (it may not have loaded yet: daves_map doesn't depend on it,
-- so it can load after us). daves_map never needs it; it only stands aside, as two copies would fight over the map
function dm.OpenMapOn()
	if not (C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("OpenMap")) then return false end
	if C_AddOns.IsAddOnLoaded("OpenMap") then return true end
	local ok, state = pcall(C_AddOns.GetAddOnEnableState, "OpenMap", UnitName("player"))
	return ok and type(state) == "number" and state > 0 or false
end

-- daves_map's PLAYER_LOGIN: every addon has loaded by then
function dm.StartStitch()
	if dm.OpenMapOn() then
		dm.Print("OpenMap is on, so daves_map's copy of its seamless map stays off (turn OpenMap off for daves_map's).")
		return
	end
	local t0 = debugprofilestop and debugprofilestop()
	for _, mod in pairs(ns.modules) do
		if mod.db.enabled and not mod.enabled then
			mod.enabled = true
			if mod.OnEnable then
				local ok, err = pcall(mod.OnEnable, mod)
				if not ok then
					mod.enabled = false
					dm.Print("|cffff6060the seamless map failed to start|r: " .. tostring(err):sub(1, 300))
					geterrorhandler()(err)
				end
			end
		end
	end
	if t0 then ns.loadMs.login = debugprofilestop() - t0 end
end
