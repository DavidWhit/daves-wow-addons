-- daves_balls / OrbSettings.lua
-- Per-orb settings dialog, opened by clicking an orb while it is movable (Blizzard's Edit Mode,
-- or unlocked): colours, number/percent text, accent pattern and position reset. Built with the
-- kit's shared Edit Mode dialog (EditModeDialog.lua), so it looks and behaves like every other
-- addon's Edit Mode settings. Colours use Blizzard's colour picker through it.

local _, ns = ...

local dialog

local function CreateDialog()
	dialog = ns.EditMode.CreateDialog("DavesBallsOrbSettings")
	local function Orb() return dialog.orb end
	-- Colours get the orb the colour picker was opened for, so a change can't land on the other orb.
	local function SavedColor(field)
		return function(orb) return ns.db.colors[(orb or Orb()).key][field] end
	end
	local function SetColor(field)
		return function(c, orb)
			orb = orb or Orb()
			ns.db.colors[orb.key][field] = c
			ns:RefreshOrbColors(orb)
		end
	end

	dialog:AddColor({ label = "Liquid colour", saved = SavedColor("liquid"), set = SetColor("liquid"),
		get = function(orb) return (ns:GetOrbColors(orb or Orb())) end })
	dialog:AddColor({ label = "Accent colour (core and gold veins)", saved = SavedColor("accent"), set = SetColor("accent"),
		get = function(orb) local _, accent = ns:GetOrbColors(orb or Orb()); return accent end })

	-- Text: number and percent can each be on or off, independently, per orb.
	local function TextFlag(field)
		return {
			get = function() return ns.db.orbText[Orb().key][field] end,
			set = function(v) ns.db.orbText[Orb().key][field] = v; ns:Apply() end,
		}
	end
	local number, percent = TextFlag("number"), TextFlag("percent")
	dialog:AddCheckbox({ label = "Show number", get = number.get, set = number.set })
	dialog:AddCheckbox({ label = "Show percent", get = percent.get, set = percent.set })

	-- Accent pattern: steady flowing veins, or random re-forming arcs (per orb).
	dialog:AddCheckbox({ label = "Random accent pattern",
		tooltip = "On: the gold veins jump to a new random pattern every few seconds and the core flashes. Off: one pattern flows steadily.",
		get = function() return ns.db.accentRandom[Orb().key] end,
		set = function(v) ns.db.accentRandom[Orb().key] = v or nil end })

	-- Global: hide Blizzard's player frame. Goes through the Settings object when there is one,
	-- so the options panel stays in step (its callback runs ns:Apply).
	dialog:AddCheckbox({ label = "Hide Blizzard player frame",
		get = function() return ns.db.hidePlayerFrame end,
		set = function(v)
			if ns.hidePlayerSetting then
				ns.hidePlayerSetting:SetValue(v)
			else
				ns.db.hidePlayerFrame = v
				ns:Apply()
			end
		end })

	dialog:AddNote({ text = function()
		if Orb().key == "power" and not ns.db.colors.power.liquid then
			return "Liquid follows your power type until you pick a colour."
		end
		return ""
	end })

	dialog:AddButton({ text = "Default colours", onClick = function()
		ns.db.colors[Orb().key] = {}
		ns:RefreshOrbColors(Orb())
	end })
	dialog:AddButton({ text = "Reset position", onClick = function() ns:ResetOrbPosition(Orb()) end })
end

function ns:OpenOrbSettings(orb)
	if not dialog then CreateDialog() end
	dialog.orb = orb
	dialog:OpenFor(orb, orb.label .. " Orb")
end

-- Let ApplyOrb close it when the orbs lock again.
ns.orbSettingsDialog = function() return dialog end
