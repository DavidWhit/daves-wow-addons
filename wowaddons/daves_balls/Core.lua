-- daves_balls / Core.lua
-- Startup, saved settings, events and the slash command.

local ADDON, ns = ...

ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

local DEFAULTS = {
	enabled = true,
	scale = 1.0,
	textMode = "numbers",   -- "numbers", "percent", "both" or "none"
	holder = "none",        -- "none", "chalice", "arcane" or "sanctum"
	bobEnabled = false,
	bobIntensity = 35,
	castShadow = false,
	dustEnabled = false,
	dustPattern = "auto",   -- "auto", "ring", "helix", "figure8", "vortex", "atom", "chaos"
	dustCount = 20,
	dustSpeed = 1.0,
	dustRotation = 0,
	dustSpread = 25,
	dustTails = true,
	dustTrails = true,
	dustTailLength = 60,
	animate = true,
	glare = true,
	locked = true,          -- unlocked: drag the orbs any time, not just in Edit Mode
	hidePlayerFrame = false,
}

function ns.Print(...)
	print("|cff33ff99" .. ADDON .. "|r:", ...)
end

---------------------------------------------------------------------------
-- Events: ns:EVENT_NAME(...) is called for every registered event.
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
	local handler = ns[event]
	if handler then handler(ns, ...) end
end)
ns.events = events

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")

function ns:ADDON_LOADED(name)
	if name ~= ADDON then return end
	events:UnregisterEvent("ADDON_LOADED")

	-- SavedVariables are loaded by the time our own ADDON_LOADED fires.
	DavesBallsDB = DavesBallsDB or {}
	if DavesBallsDB.showText == false and DavesBallsDB.textMode == nil then
		DavesBallsDB.textMode = "none"   -- carry over the old on/off numbers setting
	end
	DavesBallsDB.showText = nil
	if DavesBallsDB.holder == "claws" then
		DavesBallsDB.holder = "sanctum"
	end
	for k, v in pairs(DEFAULTS) do
		if DavesBallsDB[k] == nil then DavesBallsDB[k] = v end
	end
	ns.db = DavesBallsDB

	ns:InitOptions()
	ns:InitOrbs()
	ns:Apply()
end

function ns:PLAYER_LOGIN()
	ns.Print(("v%s loaded. Type /balls for options."):format(ns.VERSION))
end

---------------------------------------------------------------------------
-- Slash command and Addon Compartment (minimap addon menu)
---------------------------------------------------------------------------
SLASH_DAVESBALLS1, SLASH_DAVESBALLS2 = "/balls", "/davesballs"
SlashCmdList["DAVESBALLS"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "options" then
		ns:OpenOptions()
	elseif msg == "unlock" or msg == "lock" then
		ns.db.locked = (msg == "lock")
		ns:Apply()
		ns.Print(ns.db.locked and "orbs locked." or "orbs unlocked: drag to move, left- or right-click for settings. /balls lock when done.")
	elseif msg == "reset" then
		for _, orb in pairs(ns.orbs) do ns:ResetOrbPosition(orb) end
		ns.Print("orb positions reset.")
	elseif msg == "holder" or msg:match("^holder%s+") then
		local arg = msg:match("^holder%s+(%S+)$")
		local norm = arg and ns.NormalizeHolderStyle and (arg == "none" or ns.NormalizeHolderStyle(arg) ~= "none") and ns.NormalizeHolderStyle(arg) or nil
		if norm and ns.HOLDER_STYLES and ns.HOLDER_STYLES[norm] then
			ns:SetAllOrbHolders(norm)
			ns.Print("orb holder set to " .. ns.HOLDER_STYLES[norm].label .. ".")
		else
			local hCur = ns.orbs and ns.orbs.health and ns:GetOrbHolder(ns.orbs.health) or ns.db.holder or "none"
			local pCur = ns.orbs and ns.orbs.power and ns:GetOrbHolder(ns.orbs.power) or hCur
			local cur = (hCur == pCur) and hCur or ("health: " .. hCur .. ", power: " .. pCur)
			ns.Print("holder variants: none, chalice, arcane, sanctum (current: " .. cur .. "). Usage: /balls holder <variant>")
		end
	elseif msg == "version" then
		ns.Print(ns.VERSION)
	else
		ns.Print("commands: /balls [options | holder <none|chalice|arcane|sanctum> | unlock | lock | reset | version]. The orbs can also be moved in Edit Mode.")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function DavesBalls_OnAddonCompartmentClick()
	ns:OpenOptions()
end
