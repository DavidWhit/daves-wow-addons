-- daves_map / Stitch / Base.lua
-- The seamless world map: OpenMap's (MIT licence, Stitch\LICENSE-OpenMap.txt), copied into daves_map. Every zone's
-- art stitched into one canvas inside Blizzard's map, zooming from the whole world down to street level and out of
-- one zone into the next. Stitch.lua (the art), WorldMap.lua (the view and zoom), Close.lua (the closest zooms) and
-- Combat.lua (Blizzard's pins in combat) are OpenMap's files with as few changes as possible, so a new OpenMap release
-- can be taken in by comparing them; each change is marked "daves_map". This file stands in for OpenMap's Core.lua.
--
-- The art and data tables are the drop-in addon daves_map_textures (tools\Update-MapTextures.ps1; not in git). It
-- leaves its namespace behind as DAVES_MAP_TEXTURES, and OpenMap's code runs in that namespace (ns.OM), apart from
-- daves_map's own: no name of OpenMap's can clash with one of ours. Without the drop-in, ns.OM is nil, the files
-- below return at once and the map is Blizzard's, as before.
--
-- Settings: daves_mapDB.stitch.worldmap (account) and daves_mapCharDB.stitch.worldmap (character), filled from the
-- module's defaults. The map starts at login unless the real OpenMap is loaded (two copies would fight over
-- Blizzard's map) or its `enabled` is off (Options: "Seamless world map", takes a reload).

local ADDON, dm = ...
local ns = type(DAVES_MAP_TEXTURES) == "table" and DAVES_MAP_TEXTURES.texturesAddon and DAVES_MAP_TEXTURES or nil
dm.OM = ns
if not ns then return end

ns.name = ADDON
ns.Media = { path = "Interface\\AddOns\\" .. ns.texturesAddon .. "\\Media\\" }
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
-- The module ("worldmap", WorldMap.lua): settings and start
---------------------------------------------------------------------------
ns.modules = {}

function ns:NewModule(key, spec)
	local mod = spec or {}
	mod.key = key
	mod.defaults = mod.defaults or {}
	if mod.defaults.enabled == nil then mod.defaults.enabled = true end
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

-- daves_map's ADDON_LOADED (Core.lua): every file has added its defaults by then
function dm.InitStitch(db, char)
	db.stitch = type(db.stitch) == "table" and db.stitch or {}
	char.stitch = type(char.stitch) == "table" and char.stitch or {}
	for key, mod in pairs(ns.modules) do
		db.stitch[key] = db.stitch[key] or {}
		if mod.Migrate then mod.Migrate(db.stitch[key]) end
		mod.db = Fill(db.stitch[key], mod.defaults)
		char.stitch[key] = char.stitch[key] or {}
		mod.char = char.stitch[key]
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
end
