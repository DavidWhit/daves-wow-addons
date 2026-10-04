-- {{NAME}} / EditMode.lua
-- Moving and setting up the addon's frame in Blizzard's Edit Mode, the same way as every addon
-- from the kit: ns.EditMode (EditModeDialog.lua) draws the outline, snaps like Blizzard's frames,
-- opens the settings dialog on click and resets on right-click. Add settings to the dialog with
-- its Add* calls; never build your own window, sliders or checkboxes for this.
--
-- Call ns:InitEditMode(frame) once the frame exists (after SavedVariables are loaded).

local _, ns = ...

local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }

local function ApplyPosition(frame)
	local pos = ns.db.pos or DEFAULT_POS
	frame:ClearAllPoints()
	frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end

function ns:InitEditMode(frame)
	ApplyPosition(frame)

	local dialog = ns.EditMode.CreateDialog("{{NAME}}EditDialog", "{{TITLE}}")
	dialog:AddSlider({ label = "Scale", min = .5, max = 2, step = .05, format = "%.2f",
		get = function() return ns.db.scale end,
		set = function(v) ns.db.scale = v; frame:SetScale(v) end })
	dialog:AddButton({ text = "Reset position", onClick = function()
		ns.db.pos = nil
		ApplyPosition(frame)
	end })

	ns.editMode = ns.EditMode.Attach(frame, {
		label = "{{TITLE}}",
		dialog = dialog,
		onMoved = function(f)
			local point, _, relPoint, x, y = f:GetPoint(1)
			ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
		end,
		onReset = function(f)
			ns.db.pos = nil
			ApplyPosition(f)
		end,
	})
end
