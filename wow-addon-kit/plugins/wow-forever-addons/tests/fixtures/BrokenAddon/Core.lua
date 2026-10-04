-- Test fixture: every block below should be reported by Test-WowAddon.ps1.
-- The expected rule is named in each comment; Invoke-KitSelfTest.ps1 asserts them.
local ADDON, ns = ...

local f = CreateFrame("Frame")                        -- fine: engine global still exists
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")        -- cleu-removed
f:RegisterEvent("NOT_A_REAL_EVENT")                   -- unknown-event
f:RegisterEvent("PLAYER_LOGIN")                       -- fine

local name = GetSpellInfo(133)                        -- moved-api (C_Spell.GetSpellInfo)
local aura = UnitAura("player", 1)                    -- unknown-global (Forever has no UnitAura; only Classic shims it)
local ench = GetWeaponEnchantInfo()                   -- deprecated-api (Blizzard shim, Deprecated_12_1_0.lua)
local x = C_NotARealNamespace.DoThing()               -- unknown-namespace
local y = C_Spell.NoSuchFunction(1)                   -- unknown-function

f:SetScript("OnEvent", function()
	if UnitHealth("player") < 100 then                -- secret-value
		print("low health " .. UnitHealth("player"))  -- secret-value
	end
	BrokenAddonDB = BrokenAddonDB or {}
	counter = 0                                       -- luacheck-W111 (accidental global)
end)

SLASH_BROKEN1 = "/broken"                             -- slash-handler (no SlashCmdList.BROKEN)
print(ADDON, ns, name, aura, ench, x, y)
