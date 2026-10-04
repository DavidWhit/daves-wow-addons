-- HelloForever / Panel.lua
-- A small movable character panel: name, level, zone, gold and a health bar.
--
-- It doubles as a reference for Midnight/Forever "secret values" (Patch 12.0.0):
--   * UnitHealth is SecretReturns and UnitHealthMax is SecretWhenUnitHealthMaxRestricted in
--     Blizzard's API docs, so their results go straight into StatusBar:SetMinMaxValues /
--     SetValue and FontString:SetFormattedText, which Blizzard marks
--     SecretArguments = "AllowedWhenTainted" (addon code may pass secrets to them).
--   * We never compare, add or concatenate those values in Lua.
--   * UnitClass can be secret too; a secret can't be a table key, so it is checked with
--     issecretvalue() before indexing RAID_CLASS_COLORS.

local _, ns = ...

local CoinString = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
local issecretvalue = issecretvalue or function() return false end   -- clients without secrets

local panel

local function SavePosition()
	local point, _, relPoint, x, y = panel:GetPoint(1)
	ns.db.pos = { point, relPoint, x, y }
end

local function Build()
	panel = CreateFrame("Frame", "HelloForeverPanel", UIParent)
	panel:SetSize(220, 92)
	panel:SetFrameStrata("MEDIUM")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)

	local pos = ns.db.pos
	if pos then panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else panel:SetPoint("CENTER", 0, 200) end

	-- Plain color textures only: no dependency on Blizzard art that can move between clients.
	local bg = panel:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.65)

	panel.name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.name:SetPoint("TOPLEFT", 8, -8)
	panel.name:SetPoint("RIGHT", -8, 0)
	panel.name:SetJustifyH("LEFT")

	panel.zone = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.zone:SetPoint("TOPLEFT", panel.name, "BOTTOMLEFT", 0, -4)
	panel.zone:SetPoint("RIGHT", -8, 0)
	panel.zone:SetJustifyH("LEFT")

	panel.money = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.money:SetPoint("TOPLEFT", panel.zone, "BOTTOMLEFT", 0, -4)

	panel.health = CreateFrame("StatusBar", nil, panel)
	panel.health:SetPoint("BOTTOMLEFT", 8, 8)
	panel.health:SetPoint("BOTTOMRIGHT", -8, 8)
	panel.health:SetHeight(14)
	panel.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	panel.health:SetStatusBarColor(0.1, 0.8, 0.2)
	local hbg = panel.health:CreateTexture(nil, "BACKGROUND")
	hbg:SetAllPoints()
	hbg:SetColorTexture(0.2, 0, 0, 0.8)

	panel.healthText = panel.health:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.healthText:SetPoint("CENTER")

	panel.forever = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.forever:SetPoint("TOPRIGHT", -8, -8)
	panel.forever:SetText(ns.IS_FOREVER and "Forever" or "")
end

function ns:UpdateIdentity()
	local name = UnitName("player")
	local _, classFile = UnitClass("player")
	panel.name:SetText(name)   -- SetText accepts secrets
	if classFile and not issecretvalue(classFile) and RAID_CLASS_COLORS[classFile] then
		local c = RAID_CLASS_COLORS[classFile]
		panel.name:SetTextColor(c.r, c.g, c.b)
	end
	panel.zone:SetFormattedText("Level %d - %s", UnitLevel("player"), GetZoneText() or "")
end

function ns:UpdateMoney()
	panel.money:SetText(CoinString and CoinString(GetMoney()) or "")
end

function ns:UpdateHealth()
	-- Straight from the API into widget setters: works whether or not the values are secret.
	panel.health:SetMinMaxValues(0, UnitHealthMax("player"))
	panel.health:SetValue(UnitHealth("player"))
	panel.healthText:SetFormattedText("%d / %d", UnitHealth("player"), UnitHealthMax("player"))
end

-- Called on load and whenever a setting changes (see Options.lua).
function ns:Apply()
	if not panel then return end
	panel:SetScale(ns.db.scale or 1)
	panel:SetShown(ns.db.enabled)
end

function ns:InitPanel()
	Build()
	local ev = ns.events
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	ev:RegisterEvent("PLAYER_LEVEL_UP")
	ev:RegisterEvent("PLAYER_MONEY")
	ev:RegisterUnitEvent("UNIT_HEALTH", "player")
	ev:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
	ns:Apply()
end

function ns:PLAYER_ENTERING_WORLD()
	ns:UpdateIdentity(); ns:UpdateMoney(); ns:UpdateHealth()
end
ns.ZONE_CHANGED_NEW_AREA = ns.UpdateIdentity
ns.PLAYER_LEVEL_UP = ns.UpdateIdentity
ns.PLAYER_MONEY = ns.UpdateMoney
ns.UNIT_HEALTH = ns.UpdateHealth
ns.UNIT_MAXHEALTH = ns.UpdateHealth

function ns:TogglePanel()
	ns.db.enabled = not ns.db.enabled
	ns:Apply()
end
