-- {{NAME}} / Core.lua
-- Startup, saved settings, events and the slash command.

local ADDON, ns = ...

ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"

local DEFAULTS = {
	enabled = true,
	scale = 1.0,
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
	{{DB}} = {{DB}} or {}
	for k, v in pairs(DEFAULTS) do
		if {{DB}}[k] == nil then {{DB}}[k] = v end
	end
	ns.db = {{DB}}

	ns:InitOptions()
end

function ns:PLAYER_LOGIN()
	ns.Print(("v%s loaded. Type /{{SLASH}} for options."):format(ns.VERSION))
end

---------------------------------------------------------------------------
-- Slash command and Addon Compartment (minimap addon menu)
---------------------------------------------------------------------------
SLASH_{{SLASHUPPER}}1 = "/{{SLASH}}"
SlashCmdList["{{SLASHUPPER}}"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "options" then
		ns:OpenOptions()
	elseif msg == "version" then
		ns.Print(ns.VERSION)
	else
		ns.Print("commands: /{{SLASH}} [options | version]")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function {{NAME}}_OnAddonCompartmentClick()
	ns:OpenOptions()
end
