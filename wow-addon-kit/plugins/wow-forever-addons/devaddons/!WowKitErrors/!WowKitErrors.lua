-- !WowKitErrors -- a development aid for the wow-forever-addons kit.
-- The client shows Lua errors in a pop-up (/console scriptErrors 1) but keeps no record of them on disk, so they can't
-- be read after the fact. This records every Lua error (message and stack), every blocked or forbidden action and every
-- Lua warning into SavedVariables (written on /reload or logout), where the kit's Get-WowScriptErrors.ps1 reads them.
--
-- How it hooks in: Blizzard_ScriptErrors installs Blizzard's handler (seterrorhandler(HandleLuaError)). This wraps
-- whatever handler is installed and always calls it afterwards, so Blizzard's pop-up and logging carry on unchanged;
-- if a handler is installed after us, it is wrapped again at ADDON_LOADED and PLAYER_LOGIN. The "!" in the folder name
-- makes it load before other addons, so their load-time errors are caught too.
-- Nothing else of Blizzard's is touched. Secret values are never stored: a secret message is recorded as "(secret)".

local ADDON = ...
local MAX_ENTRIES = 300
local pending = {}           -- recorded before our SavedVariables are loaded
local db                     -- WowKitErrorsDB once loaded
local session                -- this session's number (one per /reload or login)
local byKey = {}             -- [kind .. message] = entry, this session, to count repeats

local function Now() return date("%Y-%m-%d %H:%M:%S") end

local function Safe(v)
	if v == nil then return "" end
	if issecretvalue and issecretvalue(v) then return "(secret)" end
	if canaccessvalue and not canaccessvalue(v) then return "(secret)" end
	return tostring(v)
end

local function Store(e)
	local list = db.entries
	list[#list + 1] = e
	while #list > MAX_ENTRIES do table.remove(list, 1) end
end

local function Record(kind, message, stack)
	message, stack = Safe(message), Safe(stack)
	local key = kind .. "\0" .. message
	local e = byKey[key]
	if e then
		e.count = e.count + 1
		e.last = Now()
		return
	end
	e = { kind = kind, message = message, stack = stack, count = 1, time = Now(), last = Now(), session = session }
	byKey[key] = e
	if db then Store(e) else pending[#pending + 1] = e end
end

-- the stack at the error, as Blizzard computes it (Blizzard_ScriptErrors.lua GetErrorData)
local function ErrorStack()
	if GetCallstackHeight and GetErrorCallstackHeight then
		local current, atError = GetCallstackHeight(), GetErrorCallstackHeight()
		return debugstack(current - ((atError and atError - 1) or 0))
	end
	return debugstack(3)
end

local wrapped               -- the handler we call on to (Blizzard's, normally)
local function Handler(message, ...)
	local ok, stack = pcall(ErrorStack)
	pcall(Record, "error", message, ok and stack or "")
	if wrapped then return wrapped(message, ...) end
end

local function Hook()
	local current = geterrorhandler()
	if current ~= Handler then
		wrapped = current
		seterrorhandler(Handler)
	end
end
Hook()

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("LUA_WARNING")
events:SetScript("OnEvent", function(_, event, a, b)
	if event == "ADDON_LOADED" then
		Hook()
		if a ~= ADDON then return end
		WowKitErrorsDB = type(WowKitErrorsDB) == "table" and WowKitErrorsDB or {}
		db = WowKitErrorsDB
		db.version = 1
		db.entries = db.entries or {}
		db.session = (db.session or 0) + 1
		session = db.session
		local build, _, _, toc = GetBuildInfo()
		db.sessions = db.sessions or {}
		db.sessions[session] = { start = Now(), build = Safe(build), toc = toc }
		for k in pairs(db.sessions) do if k < session - 50 then db.sessions[k] = nil end end
		for _, e in ipairs(pending) do e.session = session; Store(e) end
		wipe(pending)
	elseif event == "PLAYER_LOGIN" then
		Hook()
		local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
		print(("|cff33ff99WowKit Error Log|r v%s: recording Lua errors, blocked actions and warnings (session %d, %d kept)."):format(
			GetMeta(ADDON, "Version") or "?", session or 0, db and #db.entries or 0))
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		-- a = the addon blamed, b = the protected function
		Record(event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden", Safe(a) .. " tried to call " .. Safe(b), debugstack(2))
	elseif event == "LUA_WARNING" then
		Record("warning", a, "")
	end
end)
