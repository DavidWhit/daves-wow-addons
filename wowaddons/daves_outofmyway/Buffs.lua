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
-- Switching them, and why a reload follows: CVAR_UPDATE is a synchronous event, so whoever changes these CVars runs
-- Blizzard's CVarCallbackRegistry and the buff frame's update inside that change. From an addon that is tainted; a
-- typed /console is no better on Forever (its handler calls forceinsecure(), Blizzard_ChatFrameBase/Shared/
-- SlashCommands.lua). The taint lasts until the UI reloads, and until then cancelling a buff in combat can be
-- blocked. After a reload both CVars are already off, Blizzard reads them securely and nothing writes them again,
-- so the buff frame is clean for good. So: the option switches them (out of combat, remembering what you had) and
-- offers a reload straight away, in a small window of the addon's own (Blizzard's StaticPopup isn't touched).

local _, ns = ...

local CVARS = { "consolidateBuffs", "collapseExpandBuffs" }
local pending = false
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
		text:SetText("|cffd4a94eDave's Out Of My Way|r\nBuff frame changed. Reload to finish:\nuntil then, cancelling a buff in combat may be blocked.")
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
-- Switching
---------------------------------------------------------------------------
-- on: both off (what you had is remembered); off: what you had put back. Returns whether anything changed.
-- a change counts only when the game took it (SetCVar can refuse a read-only or secure CVar)
local function Set(cvar, value)
	local ok = C_CVar.SetCVar(cvar, value)
	if ok and IsOn(cvar) == (value == "1") then return true end
	ns.Print(("buff frame: the game won't let addons change %s. Type /console %s %s once instead."):format(cvar, cvar, value))
	return false
end

local function Switch()
	local db = ns.db
	db.savedCVars = db.savedCVars or {}
	local changed = false
	if db.showAllBuffs then
		for _, cvar in ipairs(CVARS) do
			if IsOn(cvar) then
				if db.savedCVars[cvar] == nil then db.savedCVars[cvar] = "1" end
				if Set(cvar, "0") then changed = true end
			end
		end
	else
		for _, cvar in ipairs(CVARS) do
			if db.savedCVars[cvar] == "1" and not IsOn(cvar) then
				if Set(cvar, "1") then changed = true end
			end
			db.savedCVars[cvar] = nil
		end
	end
	return changed
end

function ns.ApplyBuffs()
	if InCombatLockdown() then
		if not pending then ns.Print("buff frame: changes after combat.") end
		pending = true
		ns.events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	pending = false
	if Switch() then
		ns.db.reloadAsked = ns.db.showAllBuffs or nil
		ns.Print("buff frame: " .. ns.BuffState() .. ". Reload to finish.")
		ShowReloadPrompt()
	end
end

function ns:PLAYER_REGEN_ENABLED()
	ns.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
	if pending then ns.ApplyBuffs() end
end

-- something turned one back on (a settings sync, another addon, a typed /console): off again, while the option is
-- on - once per session; if it keeps coming back, something else keeps setting it, and fighting it would only taint
-- the buff frame and prompt again every time
local reapplied, stopped = false, false
function ns:CVAR_UPDATE(cvar)
	if stopped or not ns.db.showAllBuffs or type(cvar) ~= "string" or issecretvalue(cvar) then return end
	for _, name in ipairs(CVARS) do
		if cvar == name then
			C_Timer.After(0, function()
				if stopped or not (ns.db.showAllBuffs and IsOn(name)) then return end
				if reapplied then
					stopped = true
					ns.Print(("buff frame: something else keeps turning %s back on (another addon or a settings sync); leaving it alone this session."):format(name))
					return
				end
				reapplied = true
				ns.ApplyBuffs()
			end)
			return
		end
	end
end

function ns.InitBuffs()
	ns.events:RegisterEvent("CVAR_UPDATE")
	local db = ns.db
	local anyOn = IsOn("consolidateBuffs") or IsOn("collapseExpandBuffs")
	-- we switched them and asked for a reload, yet they're back on after it: the setting doesn't stick on this client
	-- (not saved, or the server's copy came back) - say so once instead of switching and prompting on every login
	if db.reloadAsked and db.showAllBuffs and anyOn then
		db.reloadAsked = nil
		stopped = true
		ns.Print("buff frame: the collapse settings came back after the reload, so they don't stick on this client. Leaving them alone; tick the option again to retry.")
		return
	end
	if not anyOn then db.reloadAsked = nil end   -- the reload finished the job
	ns.ApplyBuffs()   -- nothing to do (and no reload asked) once both are off
end

-- ticking the option again after a "doesn't stick" retries
function ns.RetryBuffs()
	stopped, reapplied = false, false
	ns.ApplyBuffs()
end
