-- daves_outofmyway / LootRolls.lua
-- Blizzard's need/greed roll frames (GroupLootFrame1-4, plus the bonus roll frames) moved to where you put them.
--
-- How Blizzard places them (Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua, forever branch): every roll that
-- opens, closes or is replaced goes through GroupLootContainer_Update, which anchors each roll frame to
-- GroupLootContainer at CENTER/BOTTOM, reservedSize (100) apart. The container itself is a bottom-managed frame
-- (BottomManagedFrameTemplate): UIParent's managed layout positions it together with protected frames such as the
-- extra action button, so it is never touched here - moving or sizing it from addon code would taint that layout.
--
-- Instead a post-hook (hooksecurefunc, which leaves Blizzard's own call untainted) re-anchors just the roll frames
-- to our own anchor, the same distance apart, after Blizzard has placed them. The roll frames are plain (not
-- protected) frames; nothing of Blizzard's is read back from their positions, and the container keeps its size.
-- Until you move the anchor in Edit Mode the hook does nothing at all: the rolls stay exactly where Blizzard puts them.

local _, ns = ...

local anchor, preview
local SLOT = 100             -- Blizzard's spacing (GroupLootContainer.reservedSize)
local ROLL_W, ROLL_H = 277, 67   -- GroupLootFrameBaseTemplate's size

-- the roll frames Blizzard is showing, in its order (rollFrames is sparse: index = slot)
local function EachRoll(fn)
	local c = GroupLootContainer
	if not (c and c.rollFrames) then return end
	for i, frame in pairs(c.rollFrames) do
		if type(i) == "number" and frame then fn(i, frame) end
	end
end

local function Moved() return ns.db.enabled and ns.db.pos ~= nil end

-- put the roll frames at our anchor (or back on Blizzard's container when the anchor was reset)
function ns.PlaceRolls()
	local c = GroupLootContainer
	if not (c and anchor) then return end
	local slot = c.reservedSize or SLOT
	local up = ns.db.grow ~= "down"
	local scale = ns.db.scale or 1
	EachRoll(function(i, frame)
		frame:ClearAllPoints()
		if Moved() then
			frame:SetScale(scale)
			if up then
				frame:SetPoint("CENTER", anchor, "BOTTOM", 0, slot * (i - 1 + 0.5))
			else
				frame:SetPoint("CENTER", anchor, "TOP", 0, -slot * (i - 1 + 0.5))
			end
		else
			-- exactly Blizzard's placement (GroupLootContainer_Update)
			frame:SetScale(1)
			frame:SetPoint("CENTER", c, "BOTTOM", 0, slot * (i - 1 + 0.5))
		end
	end)
end

-- the anchor's default spot: where Blizzard's container is now (it moves with the bottom bars), else above centre
local function DefaultPosition()
	local c = GroupLootContainer
	local x, bottom
	if c then x, bottom = c:GetCenter(), c:GetBottom() end
	if x and bottom then
		local ux, uy = UIParent:GetCenter()
		return { point = "CENTER", relPoint = "CENTER", x = x - ux, y = bottom - uy + SLOT / 2 }
	end
	return { point = "CENTER", relPoint = "CENTER", x = 0, y = -120 }
end

-- Positions are kept in UIParent units (unscaled) and divided by the anchor's scale when applied: SetPoint offsets
-- are in the anchor's own scaled units, so changing Scale would otherwise move it across the screen.
function ns.ApplyAnchor()
	local pos = ns.db.pos or DefaultPosition()
	local scale = ns.db.scale or 1
	anchor:SetScale(scale)
	anchor:ClearAllPoints()
	anchor:SetPoint(pos.point, UIParent, pos.relPoint, pos.x / scale, pos.y / scale)
	ns.PlaceRolls()
end

-- the anchor's position as saved: its centre, in UIParent units from the bottom left
function ns.SaveAnchor()
	local x, y = anchor:GetCenter()
	if not x then return end
	local s = anchor:GetScale()
	ns.db.pos = { point = "CENTER", relPoint = "BOTTOMLEFT", x = x * s, y = y * s }
end

-- what Edit Mode shows: a roll frame's outline in Blizzard's own loot toast art, so you can see where they'll land
local function MakePreview()
	preview = CreateFrame("Frame", nil, anchor)
	preview:SetAllPoints()
	preview:Hide()
	local bg = preview:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(ROLL_W, ROLL_H)
	bg:SetPoint("CENTER")
	bg:SetTexture("Interface\\LootFrame\\LootToast")
	bg:SetTexCoord(0.28222656, 0.55273438, 0.30859375, 0.57031250)   -- the roll frame's background (GroupLootFrame.xml)
	local label = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("CENTER")
	label:SetText("Loot rolls")
	preview.hint = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	preview.hint:SetPoint("TOP", label, "BOTTOM", 0, -4)
end

function ns.UpdatePreview(inEditMode)
	if not preview then return end
	preview:SetShown(inEditMode and true or false)
	preview.hint:SetText(ns.db.grow == "down" and "more rolls stack below" or "more rolls stack above")
end

function ns.InitLootRolls()
	anchor = CreateFrame("Frame", "daves_outofmywayLootAnchor", UIParent)
	anchor:SetSize(ROLL_W, SLOT)
	anchor:SetFrameStrata("DIALOG")
	MakePreview()
	ns.ApplyAnchor()
	-- after Blizzard places the rolls: put them at our anchor (only once you've moved it)
	hooksecurefunc("GroupLootContainer_Update", function()
		if Moved() then ns.PlaceRolls() end
	end)
	return anchor
end
