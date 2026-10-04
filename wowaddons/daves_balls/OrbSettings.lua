-- daves_balls / OrbSettings.lua
-- Small per-orb settings dialog, opened by clicking an orb while it is movable (Blizzard's
-- Edit Mode, or unlocked): colours, number/percent text, and position reset.
-- Liquid and accent colours use Blizzard's colour picker:
-- ColorPickerFrame:SetupColorPickerAndShow(info) and ColorPickerFrame:GetColorRGB()
-- (Blizzard_ColorPickerFrame/Shared/ColorPickerFrame.lua, forever branch).

local _, ns = ...

local dialog

-- Note: SetupColorPickerAndShow fires swatchFunc once while opening (SetColorRGB triggers
-- OnColorSelect), so an unchanged colour must not be saved, and cancel restores the
-- previous saved value, which may be nil ("use the default").
local function PickColor(current, onPick, onCancel)
	local r, g, b = current[1], current[2], current[3]
	ColorPickerFrame:SetupColorPickerAndShow({
		r = r, g = g, b = b,
		swatchFunc = function()
			local nr, ng, nb = ColorPickerFrame:GetColorRGB()
			if nr == r and ng == g and nb == b then return end
			onPick({ nr, ng, nb })
		end,
		cancelFunc = onCancel,
	})
end

local function CreateSwatchRow(parent, labelText, y, field)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 20, y)
	label:SetText(labelText)

	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(22, 22)
	swatch:SetPoint("TOPRIGHT", -22, y + 4)
	local border = swatch:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0.8, 0.8, 0.8)
	local color = swatch:CreateTexture(nil, "ARTWORK")
	color:SetPoint("TOPLEFT", 2, -2)
	color:SetPoint("BOTTOMRIGHT", -2, 2)
	swatch.color = color

	swatch:SetScript("OnClick", function()
		local orb = dialog.orb
		local liquid, accent = ns:GetOrbColors(orb)
		local saved = ns.db.colors[orb.key]
		local prev = saved[field]
		local function Set(c)
			saved[field] = c
			ns:RefreshOrbColors(orb)
			dialog:Refresh()
		end
		PickColor(field == "liquid" and liquid or accent, Set, function() Set(prev) end)
	end)
	return swatch
end

local function CreateDialog()
	dialog = CreateFrame("Frame", "DavesBallsOrbSettings", UIParent, "DefaultPanelTemplate")
	dialog:SetSize(250, 312)
	dialog:SetFrameStrata("DIALOG")
	dialog:SetMovable(true)
	dialog:EnableMouse(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	dialog:SetClampedToScreen(true)
	table.insert(UISpecialFrames, dialog:GetName())   -- Escape closes it

	local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 0)

	dialog.liquid = CreateSwatchRow(dialog, "Liquid colour", -40, "liquid")
	dialog.accent = CreateSwatchRow(dialog, "Accent colour (core and gold veins)", -72, "accent")

	-- Text: number and percent can each be on or off, independently, per orb.
	local function TextCheck(labelText, y, field)
		local check = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
		check:SetSize(26, 26)
		check:SetPoint("TOPLEFT", 14, y)
		local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", check, "RIGHT", 2, 0)
		label:SetText(labelText)
		check:SetScript("OnClick", function(self)
			ns.db.orbText[dialog.orb.key][field] = self:GetChecked()
			ns:Apply()
		end)
		return check
	end
	dialog.showNumber = TextCheck("Show number", -98, "number")
	dialog.showPercent = TextCheck("Show percent", -124, "percent")

	-- Accent pattern: steady flowing veins, or random re-forming arcs (per orb).
	local randomAccent = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
	randomAccent:SetSize(26, 26)
	randomAccent:SetPoint("TOPLEFT", 14, -150)
	local raLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	raLabel:SetPoint("LEFT", randomAccent, "RIGHT", 2, 0)
	raLabel:SetText("Random accent pattern")
	randomAccent:SetScript("OnClick", function(self)
		ns.db.accentRandom[dialog.orb.key] = self:GetChecked() and true or nil
	end)
	randomAccent:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Random accent pattern")
		GameTooltip:AddLine("On: the gold veins jump to a new random pattern every few seconds and the core flashes. Off: one pattern flows steadily.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	randomAccent:SetScript("OnLeave", function() GameTooltip:Hide() end)
	dialog.randomAccent = randomAccent

	-- Global: hide Blizzard's player frame. Goes through the Settings object when there is one,
	-- so the options panel stays in step (its callback runs ns:Apply).
	local hidePlayer = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
	hidePlayer:SetSize(26, 26)
	hidePlayer:SetPoint("TOPLEFT", 14, -182)
	local hpLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hpLabel:SetPoint("LEFT", hidePlayer, "RIGHT", 2, 0)
	hpLabel:SetText("Hide Blizzard player frame")
	hidePlayer:SetScript("OnClick", function(self)
		local value = self:GetChecked() and true or false
		if ns.hidePlayerSetting then
			ns.hidePlayerSetting:SetValue(value)
		else
			ns.db.hidePlayerFrame = value
			ns:Apply()
		end
	end)
	dialog.hidePlayer = hidePlayer

	local note = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 20, -214)
	note:SetPoint("RIGHT", -20, 0)
	note:SetJustifyH("LEFT")
	dialog.note = note

	local defaults = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	defaults:SetSize(210, 22)
	defaults:SetPoint("BOTTOM", 0, 44)
	defaults:SetText("Default colours")
	defaults:SetScript("OnClick", function()
		ns.db.colors[dialog.orb.key] = {}
		ns:RefreshOrbColors(dialog.orb)
		dialog:Refresh()
	end)

	local resetPos = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
	resetPos:SetSize(210, 22)
	resetPos:SetPoint("BOTTOM", 0, 16)
	resetPos:SetText("Reset position")
	resetPos:SetScript("OnClick", function() ns:ResetOrbPosition(dialog.orb) end)

	function dialog:Refresh()
		local liquid, accent = ns:GetOrbColors(self.orb)
		self.liquid.color:SetColorTexture(liquid[1], liquid[2], liquid[3])
		self.accent.color:SetColorTexture(accent[1], accent[2], accent[3])
		local flags = ns.db.orbText[self.orb.key]
		self.showNumber:SetChecked(flags.number)
		self.showPercent:SetChecked(flags.percent)
		self.hidePlayer:SetChecked(ns.db.hidePlayerFrame)
		self.randomAccent:SetChecked(ns.db.accentRandom[self.orb.key] or false)
		if self.orb.key == "power" and not ns.db.colors.power.liquid then
			self.note:SetText("Liquid follows your power type until you pick a colour.")
		else
			self.note:SetText("")
		end
	end
end

function ns:OpenOrbSettings(orb)
	if not dialog then CreateDialog() end
	dialog.orb = orb
	if dialog.TitleContainer and dialog.TitleContainer.TitleText then
		dialog.TitleContainer.TitleText:SetText(orb.label .. " Orb")
	end
	dialog:ClearAllPoints()
	-- Open beside the orb, on whichever side has more room.
	local x = orb:GetCenter()
	if not issecretvalue(x) and x and x * orb:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2 then
		dialog:SetPoint("RIGHT", orb, "LEFT", -10, 0)
	else
		dialog:SetPoint("LEFT", orb, "RIGHT", 10, 0)
	end
	dialog:Refresh()
	dialog:Show()
end

-- Let ApplyOrb close it when the orbs lock again.
ns.orbSettingsDialog = function() return dialog end
