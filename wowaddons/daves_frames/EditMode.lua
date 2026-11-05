-- daves_frames / EditMode.lua
-- Moving and setting up the target frame in Blizzard's Edit Mode, the same way as every addon from
-- the kit: ns.EditMode (EditModeDialog.lua) draws the outline, snaps like Blizzard's frames, opens the
-- settings dialog on click and resets on right-click. While Edit Mode is open the frame previews on
-- yourself if you have no target (Core.lua), so it can be placed and set up any time.

local _, ns = ...

-- Pinned to the top edge by default: the top of the extended elite/boss frame (L.extTopT = -70
-- layout px above the 1024x300 box) sits on the screen's top edge at the user's current scale,
-- and every target shares this anchor so the target frame never shifts up and down when changing targets.
function ns:ApplyPosition()
	local frame = ns.frame
	if not frame then return end
	local L = ns.L
	local s = ns.FrameScale()
	local pos = ns.db.pos
	if pos and pos.point == "TOP" and pos.relPoint == "TOP" and pos.x == 0 and (pos.y == 0 or pos.y == L.extTopT) then
		pos = nil
		ns.db.pos = nil
	end
	if not pos then
		frame:ClearAllPoints()
		frame:SetPoint("TOP", UIParent, "TOP", 0, L.extTopT)
		return
	end
	if not pos.ui then
		pos.x = pos.x * s
		pos.y = pos.y * s
		pos.ui = true
	end
	local x, y = pos.x, pos.y
	local W, H = UIParent:GetWidth(), UIParent:GetHeight()
	if W and H and W > 0 and H > 0 and pos.point == "CENTER" and pos.relPoint == "BOTTOMLEFT" then
		local halfW = L.w * 0.5 * s
		local minY = (L.h * 0.5 + (L.extBotB - L.h)) * s
		local maxY = H - (L.h * 0.5 - L.extTopT) * s
		if W > 2 * halfW then x = math.max(halfW, math.min(W - halfW, x)) end
		if maxY > minY then y = math.max(minY, math.min(maxY, y)) end
	end
	frame:ClearAllPoints()
	frame:SetPoint(pos.point, UIParent, pos.relPoint, x / s, y / s)
end

local function SavePosition(frame)
	local cx, cy = frame:GetCenter()
	if not cx then return end
	local s = frame:GetScale()
	ns.db.pos = { point = "CENTER", relPoint = "BOTTOMLEFT", x = cx * s, y = cy * s, ui = true }
	ns:ApplyPosition()
end


function ns:InitEditMode(frame)
	ns:ApplyPosition()

	local d = ns.EditMode.CreateDialog("daves_framesEditDialog", "Dave's Frames")
	d:AddSlider({ label = "Scale", min = ns.MinSize(), max = 1, step = 0.05, format = "%.2f",
		get = function() return ns.db.size end,
		set = function(v)
			local wasAllowed = ns.StackedAllowed()
			ns.db.size = v; frame:SetScale(ns.FrameScale()); ns:ApplyPosition()
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

	-- Preview: show the unit's own plate ("Auto"), or pick any plate in the dialog to inspect it.
	local previews = { { key = "auto", text = "Auto" } }
	for _, k in ipairs(ns.VARIANT_ORDER) do
		previews[#previews + 1] = { key = k, text = ns.VARIANTS[k].label }
	end
	d:AddButtonGrid({ label = "Preview", columns = 3,
		buttons = previews,
		onClick = function(key)
			ns.editPreview = key ~= "auto" and key or nil
			if ns.editing then ns:ApplyArt(ns.ArtFor(ns.unit)) end
		end,
		isActive = function(key) return (key == "auto" and not ns.editPreview) or key == ns.editPreview end })

	-- The default place, so this is also the reset (right-clicking the frame does the same).
	d:AddButton({ text = "Pin to top edge", onClick = function()
		ns.db.pos = nil
		ns:ApplyPosition()
	end })

	ns.editDialog = d
	ns.editMode = ns.EditMode.Attach(frame, {
		label = "Dave's Frames",   -- on the Edit Mode outline
		dialog = d,
		onMoved = SavePosition,
		onReset = function()
			ns.db.pos = nil
			ns:ApplyPosition()
		end,
	})
end
