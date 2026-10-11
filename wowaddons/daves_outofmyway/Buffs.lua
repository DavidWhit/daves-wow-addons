-- daves_outofmyway / Buffs.lua
-- "Show all buffs (never collapse)": every buff shown, the buff frame never collapsed.
--
-- Why it collapses (Blizzard_BuffFrame/BuffFrame.lua, forever branch): two CVars decide it, and Forever's options
-- panel has a switch for neither.
--   consolidateBuffs     on: long buffs are gathered behind one consolidation icon, and the frame is ALWAYS
--                        collapsed (BuffFrameMixin:IsExpanded returns false), whatever else you set
--   collapseExpandBuffs  on: long buffs (no duration, or more than BUFF_DURATION_WARNING_TIME left) hide behind the
--                        arrow button until you click it, and every reload starts collapsed again
-- With both off, Blizzard treats it as "just a normal buff frame! Always expanded": the arrow and the consolidation
-- icon go away and every buff shows (up to BUFF_MAX_DISPLAY, 32). Edit Mode's Icon Limit only sets icons per row.
--
-- Why they're switched at logout: CVAR_UPDATE is a synchronous event, so whoever changes these CVars runs Blizzard's
-- CVarCallbackRegistry and the buff frame's update inside that change. From an addon that is tainted (a typed
-- /console is no better on Forever: its handler calls forceinsecure(), Blizzard_ChatFrameBase/Shared/
-- SlashCommands.lua), and in a running session that taint can block cancelling a buff in combat. So nothing is
-- switched while you play: PLAYER_LOGOUT (which a /reload fires too) switches them as the UI is torn down, where a
-- tainted update harms nothing, and the next UI reads them securely and nothing writes them again. A change made
-- in the options therefore shows from the next reload or login; a small window of the addon's own offers the
-- reload (Blizzard's StaticPopup isn't touched).

local _, ns = ...

local CVARS = { "consolidateBuffs", "collapseExpandBuffs" }
local prompt

local function IsOn(cvar) return C_CVar.GetCVarBool(cvar) and true or false end

function ns.BuffState()
	if IsOn("consolidateBuffs") then return "collapsed: buffs are consolidated" end
	if IsOn("collapseExpandBuffs") then return "collapsible: long buffs hide behind the arrow" end
	return "every buff shown, never collapsed"
end

---------------------------------------------------------------------------
-- The reload window
---------------------------------------------------------------------------
local function ShowReloadPrompt()
	if not prompt then
		prompt = CreateFrame("Frame", "daves_outofmywayReloadPrompt", UIParent, "BackdropTemplate")
		prompt:SetSize(360, 112)
		prompt:SetPoint("TOP", 0, -160)
		prompt:SetFrameStrata("DIALOG")
		prompt:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		prompt:SetBackdropColor(.05, .05, .07, .95)
		prompt:EnableMouse(true)
		local text = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		text:SetPoint("TOPLEFT", 14, -14)
		text:SetPoint("TOPRIGHT", -14, -14)
		text:SetJustifyH("CENTER")
		text:SetText("|cffd4a94eDave's Out Of My Way|r\nThe buff frame change takes effect\nat your next reload or login.")
		prompt:SetHeight(text:GetStringHeight() + 64)   -- the text and the buttons never touch, however it wraps
		local reload = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
		reload:SetSize(140, 24)
		reload:SetPoint("BOTTOMRIGHT", prompt, "BOTTOM", -6, 12)
		reload:SetText("Reload now")
		reload:SetScript("OnClick", function() C_UI.Reload() end)
		local later = CreateFrame("Button", nil, prompt, "UIPanelButtonTemplate")
		later:SetSize(140, 24)
		later:SetPoint("BOTTOMLEFT", prompt, "BOTTOM", 6, 12)
		later:SetText("Later")
		later:SetScript("OnClick", function() prompt:Hide() end)
	end
	prompt:Show()
end

---------------------------------------------------------------------------
-- Switching (only ever at logout)
---------------------------------------------------------------------------
-- on: both off (what you had is remembered); off: what you had put back
local function Wanted(cvar)
	if ns.db.showAllBuffs then return "0" end
	local saved = ns.db.savedCVars
	return saved and saved[cvar]
end

local function NeedsSwitch()
	for _, cvar in ipairs(CVARS) do
		local want = Wanted(cvar)
		if want and IsOn(cvar) ~= (want == "1") then return true end
	end
	return false
end

-- returns whether anything changed (SetCVar can refuse a read-only or secure CVar)
local function Switch()
	local db = ns.db
	db.savedCVars = db.savedCVars or {}
	local changed = false
	for _, cvar in ipairs(CVARS) do
		local want = Wanted(cvar)
		local done = not want or IsOn(cvar) == (want == "1")
		if not done then
			if db.showAllBuffs and db.savedCVars[cvar] == nil then db.savedCVars[cvar] = "1" end
			done = C_CVar.SetCVar(cvar, want) and IsOn(cvar) == (want == "1")
			if done then changed = true end
		end
		-- what you had is forgotten only once it's really back (a refused restore is retried next logout)
		if not db.showAllBuffs and done then db.savedCVars[cvar] = nil end
	end
	return changed
end

-- the UI is going away (logout, quit or /reload): a tainted buff frame update can't matter now
function ns:PLAYER_LOGOUT()
	if ns.db.buffsDontStick then return end
	if Switch() then ns.db.logoutSwitched = ns.db.showAllBuffs or nil end
end

-- the option changed, or at login: nothing switches now; offer the reload if one would change something
function ns.ApplyBuffs()
	if ns.db.buffsDontStick or not NeedsSwitch() then
		if prompt then prompt:Hide() end
		return
	end
	ns.Print("buff frame: changes at your next reload or login.")
	ShowReloadPrompt()
end

local function CheckBuffs()
	local db = ns.db
	-- we switched them at logout, yet they're back on: the setting doesn't stick on this client (not saved, or the
	-- server's copy came back) - say so once and stop, instead of prompting on every login
	if db.logoutSwitched and db.showAllBuffs and NeedsSwitch() then
		db.logoutSwitched = nil
		db.buffsDontStick = true
		ns.Print("buff frame: the collapse settings came back after the reload, so they don't stick on this client. Leaving them alone; tick the option again to retry.")
		return
	end
	db.logoutSwitched = nil
	ns.ApplyBuffs()
end

function ns:VARIABLES_LOADED()
	ns.events:UnregisterEvent("VARIABLES_LOADED")
	CheckBuffs()
end

function ns.InitBuffs()
	ns.events:RegisterEvent("PLAYER_LOGOUT")
	ns.db.reloadAsked = nil   -- 0.1.2's flag, from its mid-session switch: never read as a failed logout switch
	-- the CVars read at login can still be defaults until the stored ones arrive, which would look like "doesn't stick"
	if C_CVar.AreCVarsLoaded and not C_CVar.AreCVarsLoaded() then
		ns.events:RegisterEvent("VARIABLES_LOADED")
	else
		CheckBuffs()
	end
end

-- ticking the option (again, after a "doesn't stick") retries
function ns.RetryBuffs()
	ns.db.buffsDontStick = nil
	ns.ApplyBuffs()
end
