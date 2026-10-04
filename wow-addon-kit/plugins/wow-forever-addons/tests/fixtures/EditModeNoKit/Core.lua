-- Fixture: joins Edit Mode but builds its own settings window and snapping (rules editmode-dialog, editmode-ui, editmode-snap).
local ADDON, ns = ...
ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version")

local dialog = CreateFrame("Frame", "EditModeNoKitDialog", UIParent, "DefaultPanelTemplate")
local slider = CreateFrame("Frame", nil, dialog, "MinimalSliderWithSteppersTemplate")
local check = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
local other = CreateFrame("Frame", nil, UIParent, "DefaultPanelTemplate") -- editmode-ui: ok
ns.dialog, ns.slider, ns.check, ns.other = dialog, slider, check, other

EventRegistry:RegisterCallback("EditMode.Enter", function() dialog:Show() end, ns)
local trailing = CreateFrame("Frame", nil, UIParent) -- not a "DefaultPanelTemplate"
ns.trailing = trailing
local spacing = EditModeManagerFrame.Grid.gridSpacing
ns.dialog:SetScript("OnDragStart", function() end)
ns.spacing = spacing
