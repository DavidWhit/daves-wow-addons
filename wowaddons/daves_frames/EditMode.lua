-- daves_frames / EditMode.lua
-- Moving and setting up the target frame in Blizzard's Edit Mode, the same way as every addon from
-- the kit: ns.EditMode (EditModeDialog.lua) draws the outline, snaps like Blizzard's frames, opens the
-- settings dialog on click and resets on right-click. While Edit Mode is open the frame previews on
-- yourself if you have no target (Core.lua), so it can be placed and set up any time.

local _, ns = ...

-- Pinned to the top edge by default: the top of the whole frame (the dragon's top) on the screen's edge.
local DEFAULT_POS = { point = "TOP", relPoint = "TOP", x = 0, y = 0 }

local function ApplyPosition(frame)
	local pos = ns.db.pos or DEFAULT_POS
	frame:ClearAllPoints()
	frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
end


function ns:InitEditMode(frame)
	ApplyPosition(frame)

	local d = ns.EditMode.CreateDialog("daves_framesEditDialog", "Dave's Frames")
	d:AddSlider({ label = "Scale", min = 0.5, max = 1, step = 0.05, format = "%.2f",
		get = function() return ns.db.size end,
		set = function(v)
			local wasAllowed = ns.StackedAllowed()
			ns.db.size = v; frame:SetScale(ns.FrameScale())
			if ns.StackedAllowed() ~= wasAllowed then
				ns:Apply()   -- crossed 0.85: below it Stacked switches to Overlay (Apply refreshes the dialog)
			else
				ns:ApplyLayout(); ns:ApplyBoardStyle()   -- pixel-snapped sizes follow the scale
			end
		end })

	d:AddButtonGrid({ label = "Name and cast", columns = 2,
		buttons = { { key = "overlay", text = "Overlay" }, { key = "stacked", text = "Stacked" } },
		onClick = function(key) ns.db.layout = key; ns:Apply() end,
		-- Below Scale 0.85 the setting is switched to Overlay and Stacked is hidden.
		isActive = function(key) return ns.db.layout == key end,
		isShown = function(key) return key ~= "stacked" or ns.StackedAllowed() end })
	d:AddNote({ text = function()
		if not ns.StackedAllowed() then
			return ("Stacked needs Scale %.2f or more; at this Scale the name and cast overlay the bars."):format(ns.STACKED_MIN)
		end
		return ""
	end })

	d:AddButtonGrid({ label = "Health and resource numbers", columns = 3,
		buttons = { { key = "portrait", text = "On the portrait" }, { key = "bars", text = "In the bars" }, { key = "off", text = "Off" } },
		onClick = function(key)
			if key == "bars" and not ns.Stacked() then return end   -- only with Stacked
			ns.db.numbers = key; ns:Apply()
		end,
		isActive = function(key) return (ns.numbersWhere or ns.db.numbers) == key end,   -- lit for where they show
		isShown = function(key) return key ~= "bars" or ns.Stacked() end })   -- Overlay keeps the bars clear
	d:AddNote({ text = function()
		if ns.Stacked() and ns.numbersForced then return "Too small to read in the bars at this scale, so they show on the portrait. Raise Scale to bring them back." end
		return ""
	end })

	d:AddButtonGrid({ label = "Show", columns = 3,
		buttons = { { key = "num", text = "Numbers" }, { key = "pct", text = "%" }, { key = "both", text = "Both" } },
		onClick = function(key) ns.db.format = key; ns:Apply() end,
		isActive = function(key) return ns.db.format == key end })

	d:AddSlider({ label = "Portrait opacity", min = 0, max = 100, step = 5, format = "%d%%",
		get = function() return ns.db.portraitAlpha * 100 end,
		set = function(v) ns.db.portraitAlpha = v / 100; ns:ApplyNumbers() end })

	d:AddButtonGrid({ label = "Aura boards", columns = 2,
		buttons = { { key = "chains", text = "On chains" }, { key = "under", text = "Under the bar" } },
		onClick = function(key) ns.db.boards = key; ns:ApplyBoardStyle() end,
		isActive = function(key) return ns.db.boards == key end })
	d:AddSlider({ label = "Max aura rows", min = 1, max = 4, step = 1, format = "%d",
		get = function() return ns.db.maxRows end,
		set = function(v) ns.db.maxRows = v end })
	d:AddCheckbox({ label = "Swing a little when you move",
		tooltip = "The boards on chains sway when you start, stop, walk and turn. In instances, where facing isn't available, they sway on movement only.",
		get = function() return ns.db.swing end,
		set = function(v) ns.db.swing = v end })

	-- The default place, so this is also the reset (right-clicking the frame does the same).
	d:AddButton({ text = "Pin to top edge", onClick = function()
		ns.db.pos = nil
		ApplyPosition(frame)
	end })

	ns.editDialog = d
	ns.editMode = ns.EditMode.Attach(frame, {
		label = "Dave's Frames",   -- on the Edit Mode outline
		dialog = d,
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
