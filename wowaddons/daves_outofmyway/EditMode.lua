-- daves_outofmyway / EditMode.lua
-- Moving and setting up the loot roll anchor in Blizzard's Edit Mode, the same way as every addon from the kit:
-- ns.EditMode (EditModeDialog.lua) draws the outline, snaps like Blizzard's frames, opens the settings dialog on click
-- and resets on right-click. Never build your own window, sliders or checkboxes for this.
--
-- The flight-path dismount button (MainMenuBarVehicleLeaveButton, "Request early landing" on a taxi) is NOT moved
-- here: it is one of Blizzard's own Edit Mode systems on Forever. Every time it shows, Edit Mode places it again
-- with the action bars (EditModeVehicleLeaveButtonSystem_OnShow -> UpdateActionBarLayout), so an addon's position
-- would be undone on each flight, and moving it from addon code would taint the action bar layout (actions blocked
-- in combat). Blizzard's Edit Mode moves it properly once "Vehicle Leave Button" is ticked in its settings (Misc);
-- this addon only points that out (ns.CheckLeaveButton), reading the setting, never writing it.

local _, ns = ...

-- Blizzard's Edit Mode setting "Vehicle Leave Button" (Enum.EditModeAccountSetting.ShowVehicleLeaveButton): read only
local function LeaveButtonShownInEditMode()
	local mgr = EditModeManagerFrame
	local setting = Enum.EditModeAccountSetting and Enum.EditModeAccountSetting.ShowVehicleLeaveButton
	if not (mgr and setting and mgr.GetAccountSettingValueBool and mgr.HasAccountSettings and mgr:HasAccountSettings()) then return nil end
	return mgr:GetAccountSettingValueBool(setting)
end

local LEAVE_HINT = "To move the flight-path dismount button, tick |cffffd200Vehicle Leave Button|r in Edit Mode's settings (click Expand options, then Misc); then drag it like any other Edit Mode frame."

function ns.CheckLeaveButton()
	if LeaveButtonShownInEditMode() == false and not ns.leaveHintShown then
		ns.leaveHintShown = true
		ns.Print(LEAVE_HINT)
	end
end

function ns:InitEditMode(frame)
	local dialog = ns.EditMode.CreateDialog("daves_outofmywayEditDialog", "Loot rolls")
	dialog:AddSlider({ label = "Scale", min = .5, max = 2, step = .05, format = "%.2f",
		get = function() return ns.db.scale end,
		set = function(v) ns.db.scale = v; ns.ApplyAnchor() end })
	dialog:AddButtonGrid({ label = "More rolls", columns = 2,
		buttons = { { key = "up", text = "Stack above" }, { key = "down", text = "Stack below" } },
		onClick = function(key) ns.db.grow = key; ns.PlaceRolls(); ns.UpdatePreview(true); dialog:Refresh() end,
		isActive = function(key) return (ns.db.grow or "up") == key end })
	dialog:AddNote({ text = function()
		if not ns.db.enabled then return "Moving is off in the addon's options (Esc > Options > AddOns)." end
		if not ns.db.pos then return "Not moved yet: rolls appear above the action bars (Blizzard's spot). Drag this to move them." end
		return ""
	end })
	dialog:AddNote({ text = function()
		if LeaveButtonShownInEditMode() == false then return LEAVE_HINT end
		return ""
	end })
	dialog:AddButton({ text = "Back to Blizzard's spot", onClick = function()
		ns.db.pos = nil
		ns.ApplyAnchor()
		dialog:Refresh()
	end })

	ns.editMode = ns.EditMode.Attach(frame, {
		label = "Loot rolls",
		dialog = dialog,
		onMoved = function(f)
			ns.SaveAnchor()   -- in UIParent units, so Scale never moves it
			ns.PlaceRolls()
			dialog:Refresh()
		end,
		onReset = function()
			ns.db.pos = nil
			ns.ApplyAnchor()
		end,
	})

	-- the placeholder shows only in Edit Mode; opening Edit Mode also mentions the dismount button once
	if EventRegistry then
		EventRegistry:RegisterCallback("EditMode.Enter", function()
			if not ns.db.pos then ns.ApplyAnchor() end   -- follow Blizzard's container until moved
			ns.UpdatePreview(true)
			ns.CheckLeaveButton()
		end, ns)
		EventRegistry:RegisterCallback("EditMode.Exit", function() ns.UpdatePreview(false) end, ns)
	end
end
