-- daves_castbar / Core.lua
-- Startup, saved settings, events and the slash command.

local ADDON, ns = ...

-- WoW: Forever identifies itself as project "Camelot" (Blizzard's Forever UI source,
-- Blizzard_ProjectConstants/Camelot/ProjectConstants.lua: WOW_PROJECT_CAMELOT = 18).
ns.IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT

-- Feature detection, never version checks: C_AddOns on modern clients, the old global elsewhere.
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = GetAddOnMetadata(ADDON, "Version") or "dev"

ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- The bar's size limits. The minimum keeps each look's art visible and the text (which scales
-- with the bar, Bar.lua LayoutText) readable; ns:Layout holds saved sizes to it too.
ns.MIN_W, ns.MAX_W, ns.MIN_H, ns.MAX_H = 200, 800, 20, 80

local DEFAULTS = {
	enabled = true,
	width = 300,
	height = 26,
	scale = 1.0,
	showName = true,
	showTime = true,
	showIcon = false,
	textScale = 1.0,        -- size of the spell name and time left
	textOutline = true,     -- dark outline so the text stands out against every element
	namePos = "left",       -- "left", "center" or "right"
	timePos = "right",
	hideBlizzard = true,    -- hide Blizzard's player cast bar while ours is enabled
	locked = true,          -- unlocked: drag the bar any time, not just in Edit Mode
	point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 190,
	style = "framed",      -- "framed" (a thin line in the look's colour) or "borderless" (none); edges are always clean
	corners = "soft",      -- "square", "soft" (slightly rounded) or "rounded"
	depth = "flat",        -- "flat" or "bevel" (light along the top, shade along the bottom, a shadow inside the frame)
	fallback = "plain",     -- the look for casts we can't place (other professions, hearthstone, ...): Blizzard's own bar art, or "class"
	spellElements = {},     -- [spellID] = element, set with /castbar set
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
	DavesCastbarDB = DavesCastbarDB or {}
	for k, v in pairs(DEFAULTS) do
		if DavesCastbarDB[k] == nil then
			DavesCastbarDB[k] = type(v) == "table" and {} or v
		end
	end
	DavesCastbarDB.borderless = nil   -- the old ragged-edge style's key (removed in 0.4.0); db.style replaces it, with clean edges
	ns.db = DavesCastbarDB

	ns:InitBar()
	ns:InitEditMode()
	ns:InitOptions()
	ns:Apply()
end

function ns:PLAYER_LOGIN()   -- also fires on /reload
	ns.Print(("v%s loaded. Type /castbar for options."):format(ns.VERSION))
end

---------------------------------------------------------------------------
-- Slash command and Addon Compartment (minimap addon menu)
---------------------------------------------------------------------------
local function ElementList()
	local names = {}
	for _, key in ipairs(ns.ELEMENT_ORDER) do names[#names + 1] = key end
	return table.concat(names, ", ")
end

SLASH_DAVESCASTBAR1, SLASH_DAVESCASTBAR2 = "/castbar", "/davescastbar"
SlashCmdList["DAVESCASTBAR"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	if cmd == "" or cmd == "options" then
		ns:OpenOptions()
	elseif cmd == "test" then
		local element = arg ~= "" and arg or nil
		if element and not ns.ELEMENTS[element] then
			ns.Print("unknown element. Use one of: " .. ElementList())
		else
			ns:TestCast(element)
		end
	elseif cmd == "set" then
		-- the element for the last spell you cast (or "auto" to go back to guessing)
		local last = ns.lastSpell
		if not last then
			ns.Print("cast the spell first, then /castbar set <element>.")
		elseif arg == "auto" then
			ns.db.spellElements[last.id] = nil
			ns.Print(("%s: back to automatic."):format(last.name))
		elseif ns.ELEMENTS[arg] then
			ns.db.spellElements[last.id] = arg
			ns.Print(("%s will use %s."):format(last.name, arg))
		else
			ns.Print("use /castbar set <element> with one of: " .. ElementList() .. ", or auto.")
		end
	elseif cmd == "unlock" or cmd == "lock" then
		ns.db.locked = (cmd == "lock")
		ns:Apply()
		ns.Print(ns.db.locked and "bar locked." or "bar unlocked: drag to move, drag the corner to resize, right-click to reset. /castbar lock when done.")
	elseif cmd == "reset" then
		ns:ResetPosition()
		ns.Print("position and size reset.")
	elseif cmd == "version" then
		ns.Print(ns.VERSION)
	else
		ns.Print("commands: /castbar [options | test <element> | set <element> | unlock | lock | reset | version]")
		ns.Print("elements: " .. ElementList() .. ". The bar can also be moved and sized in Edit Mode.")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function DavesCastbar_OnAddonCompartmentClick()
	ns:OpenOptions()
end
