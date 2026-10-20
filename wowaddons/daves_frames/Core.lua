-- daves_frames / Core.lua
-- Startup, saved settings, events and the slash command.

local ADDON, ns = ...

-- WoW: Forever identifies itself as project "Camelot" (Blizzard's Forever UI source,
-- Blizzard_ProjectConstants/Camelot/ProjectConstants.lua: WOW_PROJECT_CAMELOT = 18).
ns.IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
ns.IS_RETAIL = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

-- Feature detection, never version checks: C_AddOns on modern clients, the old global elsewhere.
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = GetAddOnMetadata(ADDON, "Version") or "dev"

local DEFAULTS = {
	enabled = true,
	size = 0.8,               -- Scale as the player sees it: 0.5 to 1, where 1 is half the art's size (ns.FrameScale)
	layout = "overlay",       -- "overlay" or "stacked" (name and cast)
	numbers = "portrait",     -- "portrait", "bars" (stacked only) or "off"
	format = "both",          -- "num", "pct" or "both"
	portraitAlpha = 1,
	boards = "chains",        -- "chains" or "under"
	swing = true,
	maxRows = 2,              -- aura rows per board before the ellipsis (1-4)
	variant = "gold",         -- every target uses the gold elite art for now; every setting here applies to every variant
}

-- The frame's real scale: Scale 1 is half the art's size (0.5), Scale 0.5 a quarter (0.25).
function ns.FrameScale() return ns.db.size * 0.5 end

-- Stacked needs room: below Scale 0.85 the setting switches to Overlay (and numbers in the bars, which only
-- come with Stacked, to the portrait). Called whenever the Scale changes and at load.
ns.STACKED_MIN = 0.85
function ns.StackedAllowed() return ns.db.size >= ns.STACKED_MIN - 1e-6 end
function ns.Stacked() return ns.db.layout == "stacked" and ns.StackedAllowed() end
function ns:CheckLayout()
	if ns.StackedAllowed() then return end
	if ns.db.layout == "stacked" then ns.db.layout = "overlay" end
	if ns.db.numbers == "bars" then ns.db.numbers = "portrait" end
end

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

-- Unit events for the target, and for yourself while previewing.
local UNIT_EVENTS = {
	"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
	"UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_PREDICTION", "UNIT_AURA", "UNIT_NAME_UPDATE", "UNIT_LEVEL",
	"UNIT_FACTION", "UNIT_FLAGS", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_TARGET",
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

function ns:ADDON_LOADED(name)
	if name ~= ADDON then return end
	events:UnregisterEvent("ADDON_LOADED")

	-- SavedVariables are loaded by the time our own ADDON_LOADED fires.
	daves_framesDB = daves_framesDB or {}
	for k, v in pairs(DEFAULTS) do
		if daves_framesDB[k] == nil then daves_framesDB[k] = v end
	end
	ns.db = daves_framesDB
	if not ns.VARIANTS[ns.db.variant] then ns.db.variant = "gold" end
	ns.db.textSize, ns.db.textVersion = nil, nil   -- 0.1.13: text scales with the frame, no setting
	ns.db.textStyle = nil
	if ns.db.scale then   -- 0.1.11: Scale became 0.5 to 1 (1 = the old 0.5)
		ns.db.size = math.max(0.5, math.min(1, ns.db.scale / 0.5)); ns.db.scale = nil
	end

	ns:CheckLayout()
	local f = ns:BuildFrame(ns.db.variant)
	f:SetScale(ns.FrameScale())
	ns:BuildBoards()

	-- Per-frame work runs on its own child frame: Edit Mode's drag owns the frame's OnUpdate.
	local ticker = CreateFrame("Frame", nil, f)
	ticker:SetScript("OnUpdate", function(_, dt)
		if ns.aurasDirty then ns.aurasDirty = nil; ns:RefreshAuras() end
		ns:TickCast()
		ns:TickBoards(dt)
	end)

	ns:InitEditMode(f)
	ns:InitOptions()

	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterEvent("UI_SCALE_CHANGED")
	events:RegisterEvent("DISPLAY_SIZE_CHANGED")
	for _, e in ipairs(UNIT_EVENTS) do events:RegisterUnitEvent(e, "target", "player") end
	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Enter", function() ns:SetPreview("editmode", true) end, ns)
		EventRegistry:RegisterCallback("EditMode.Exit", function() ns:SetPreview("editmode", false) end, ns)
	end
end

function ns:PLAYER_LOGIN()
	ns.Print(("v%s loaded%s. Type /davesframes for options, /davesframes test to preview on yourself."):format(ns.VERSION, ns.IS_FOREVER and " (WoW: Forever)" or ""))
	ns:UI_SCALE_CHANGED()   -- UIParent has its final scale by now
	ns:Refresh()
end

-- Preview shows the frame on yourself when there's no target: in Edit Mode, or with /davesframes test.
local previewReasons = {}
function ns:SetPreview(reason, on)
	previewReasons[reason] = on or nil
	ns.preview = next(previewReasons) ~= nil
	ns.editing = previewReasons.editmode ~= nil   -- Edit Mode shows the frame even when it's disabled
	ns:Refresh()
end

function ns:Apply()
	if not ns.frame then return end
	ns:CheckLayout()
	ns.frame:SetScale(ns.FrameScale())
	ns:ApplyLayout()
	ns:ApplyBoardStyle()
	ns:Refresh()
	-- An open Edit Mode dialog shows the change, from whichever path made it (the Options page too).
	if ns.editDialog and ns.editDialog:IsShown() then ns.editDialog:Refresh() end
end

function ns:PLAYER_TARGET_CHANGED() ns:Refresh() end

-- Screen-pixel sizes (text shadow, level ring) follow the UI scale and resolution.
function ns:UI_SCALE_CHANGED()
	if not ns.frame then return end
	ns:ApplyLayout(); ns:ApplyBoardStyle()
end
ns.DISPLAY_SIZE_CHANGED = ns.UI_SCALE_CHANGED

-- Unit events only matter for the unit on show.
local function Mine(unit) return unit == ns.unit end

function ns:UNIT_HEALTH(unit) if Mine(unit) then ns:UpdateHealth() end end
ns.UNIT_MAXHEALTH = ns.UNIT_HEALTH
function ns:UNIT_POWER_UPDATE(unit) if Mine(unit) then ns:UpdatePower() end end
ns.UNIT_MAXPOWER = ns.UNIT_POWER_UPDATE
ns.UNIT_DISPLAYPOWER = ns.UNIT_POWER_UPDATE
function ns:UNIT_HEAL_PREDICTION(unit) if Mine(unit) then ns:UpdatePrediction() end end
ns.UNIT_ABSORB_AMOUNT_CHANGED = ns.UNIT_HEAL_PREDICTION
function ns:UNIT_AURA(unit) if Mine(unit) then ns.aurasDirty = true end end
function ns:UNIT_NAME_UPDATE(unit) if Mine(unit) then ns:UpdateIdentity() end end
ns.UNIT_LEVEL = ns.UNIT_NAME_UPDATE
ns.UNIT_FACTION = ns.UNIT_NAME_UPDATE
ns.UNIT_FLAGS = ns.UNIT_NAME_UPDATE
function ns:UNIT_PORTRAIT_UPDATE(unit) if Mine(unit) then ns:UpdatePortrait() end end
ns.UNIT_MODEL_CHANGED = ns.UNIT_PORTRAIT_UPDATE
function ns:UNIT_TARGET(unit) if Mine(unit) then ns:UpdateTargetOfTarget() end end

function ns:UNIT_SPELLCAST_START(unit) if Mine(unit) then ns:RefreshCast() end end
ns.UNIT_SPELLCAST_DELAYED = ns.UNIT_SPELLCAST_START
ns.UNIT_SPELLCAST_CHANNEL_START = ns.UNIT_SPELLCAST_START
ns.UNIT_SPELLCAST_CHANNEL_UPDATE = ns.UNIT_SPELLCAST_START
-- Payloads (CastingBarFrame.lua, forever branch): (unit, castGUID, spellID, ...);
-- CHANNEL_STOP is (unit, castGUID, spellID, interruptedBy, castBarID).
function ns:UNIT_SPELLCAST_STOP(unit, castGUID) if Mine(unit) then ns:CastEnded("done", castGUID) end end
function ns:UNIT_SPELLCAST_INTERRUPTED(unit, castGUID) if Mine(unit) then ns:CastEnded("cut", castGUID) end end
ns.UNIT_SPELLCAST_FAILED = ns.UNIT_SPELLCAST_INTERRUPTED
function ns:UNIT_SPELLCAST_CHANNEL_STOP(unit, _, _, interruptedBy) if Mine(unit) then ns:ChannelEnded(interruptedBy) end end
function ns:UNIT_SPELLCAST_INTERRUPTIBLE(unit) if Mine(unit) then ns:SetCastInterruptible(false) end end
function ns:UNIT_SPELLCAST_NOT_INTERRUPTIBLE(unit) if Mine(unit) then ns:SetCastInterruptible(true) end end

---------------------------------------------------------------------------
-- Slash command and Addon Compartment (minimap addon menu)
---------------------------------------------------------------------------
SLASH_DAVES_FRAMES1 = "/davesframes"
SlashCmdList["DAVES_FRAMES"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "" or msg == "options" then
		ns:OpenOptions()
	elseif msg == "test" then
		ns:SetPreview("test", not ns.previewTest)
		ns.previewTest = not ns.previewTest
		ns.Print(ns.previewTest and "previewing on yourself while you have no target." or "preview off.")
	elseif msg == "version" then
		ns.Print(ns.VERSION)
	else
		ns.Print("commands: /davesframes [options | test | version]")
	end
end

-- Named in the TOC (## AddonCompartmentFunc), so it must be global.
function daves_frames_OnAddonCompartmentClick()
	ns:OpenOptions()
end
