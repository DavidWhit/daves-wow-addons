-- !WowKitErrors -- a development aid for the wow-forever-addons kit.
-- The client shows Lua errors in a pop-up (/console scriptErrors 1) but keeps no record of them on disk, so they can't
-- be read after the fact. This records every Lua error (message and stack), every blocked or forbidden action (with a
-- taint probe, below) and every Lua warning into SavedVariables (written on /reload or logout), where the kit's
-- Get-WowScriptErrors.ps1 reads them.
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
	return e
end

-- Taint probe. A blocked or forbidden action means the protected call ran tainted: something it read had been written
-- by addon code. issecurevariable(table, key) says whether a stored value is secure and, if not, which addon tainted it.
-- So the probe looks where that read most likely was and lists what an addon wrote there:
--   1. every field of the frames under the mouse and of their parents (the clicked button and what holds it),
--   2. Blizzard's own globals an addon replaced (their names are taken at load, before any other addon: "!" loads first),
--   3. fields an addon wrote on Blizzard's global tables and frames (MerchantFrame.selectedTab, say).
-- Read only: it keeps names, types and the addon blamed, never values. It runs once per distinct entry per session, on a
-- time budget, since it walks _G. It only sees taint still stored when the action fails; the client's taint log
-- (/console taintLog 2) stays the full record of how execution became tainted. /wkprobe runs it by hand.
local isv = issecurevariable
local blizzGlobals = {}
if isv then for k in next, _G do if type(k) == "string" then blizzGlobals[k] = true end end end
local PROBE_BUDGET_MS, PROBE_MAX = 250, 60
-- Blizzard registries addons are meant to add to: their addon-written keys are expected, not a finding.
local REGISTRIES = { SlashCmdList = true, hash_SlashCmdList = true, StaticPopupDialogs = true, UIPanelWindows = true,
	UISpecialFrames = true, _G = true }

local function Probe()
	if not (isv and debugprofilestop) then return "(this client has no issecurevariable: no probe)" end
	local found, seen, start, stopped = {}, {}, debugprofilestop(), false
	local function Over()
		stopped = stopped or #found >= PROBE_MAX or debugprofilestop() - start > PROBE_BUDGET_MS
		return stopped
	end
	local function Fields(t, where)
		if seen[t] then return end
		seen[t] = true
		pcall(function()   -- forbidden tables and frames refuse access
			for k, v in next, t do
				if type(k) == "string" then
					local secure, by = isv(t, k)
					if not secure then found[#found + 1] = ("%s.%s (%s) by %s"):format(where, Safe(k), type(v), Safe(by)) end
				end
				if Over() then return end
			end
		end)
	end

	local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
	for _, f in ipairs(foci or {}) do
		for _ = 1, 8 do
			if not f or Over() then break end
			local ok, name = pcall(f.GetDebugName, f)
			Fields(f, "mouse " .. (ok and Safe(name) or "?"))
			ok, f = pcall(f.GetParent, f)
			if not ok then break end
		end
	end
	for k, v in next, _G do
		if Over() then break end
		if type(k) == "string" and not REGISTRIES[k] then
			local secure, by = isv(k)
			if not secure then
				if blizzGlobals[k] then found[#found + 1] = ("global %s (%s) replaced by %s"):format(k, type(v), Safe(by)) end
			elseif type(v) == "table" then
				Fields(v, k)
			end
		end
	end

	if stopped then found[#found + 1] = "(probe stopped early: time or size limit)" end
	if #found == 0 then return "(no tainted values found where the probe looks)" end
	return table.concat(found, "\n")
end

SLASH_WOWKITPROBE1 = "/wkprobe"
SlashCmdList.WOWKITPROBE = function()
	local e = Record("probe", "manual probe at " .. Now(), "")
	if e then e.taint = Probe(); print("|cff33ff99WowKit Error Log|r: probe recorded; /reload to write it.") end
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
		local e = Record(event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden", Safe(a) .. " tried to call " .. Safe(b), debugstack(2))
		if e then
			local ok, found = pcall(Probe)
			e.taint = ok and found or ("(probe failed: " .. Safe(found) .. ")")
		end
	elseif event == "LUA_WARNING" then
		Record("warning", a, "")
	end
end)
