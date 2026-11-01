-- daves_chat / Options.lua
-- Esc > Options > AddOns > Dave's Chat.
-- API verified against Blizzard_Settings_Shared/Blizzard_Settings.lua on the forever branch.

local ADDON, ns = ...

function ns:InitOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

	local category = Settings.RegisterVerticalLayoutCategory("Dave's Chat")

	local enabled = Settings.RegisterAddOnSetting(category, ADDON .. "_enabled", "enabled", ns.db,
		Settings.VarType.Boolean, "Move the chat window", true)
	Settings.CreateCheckbox(category, enabled,
		"Place Blizzard's chat dock in Dave's Chat. Turn off to leave the chat windows with Blizzard.")

	local route = Settings.RegisterAddOnSetting(category, ADDON .. "_routeChannels", "routeChannels", ns.db,
		Settings.VarType.Boolean, "Keep public channels on General", true)
	Settings.CreateCheckbox(category, route,
		"General, Trade and the other numbered channels stay on the General tab. Party, whispers and say stay on Chat.")

	local whisper = Settings.RegisterAddOnSetting(category, ADDON .. "_whisperAlert", "whisperAlert", ns.db,
		Settings.VarType.Boolean, "Alert when someone whispers you", true)
	Settings.CreateCheckbox(category, whisper,
		"Flashes the message-bubble open icon (when closed) or the Chat tab (when viewing another tab) when a whisper arrives. The usual whisper sound still plays while the window is closed.")

	enabled:SetValueChangedCallback(function()
		if ns.ApplyEnabled then ns:ApplyEnabled() end
	end)
	route:SetValueChangedCallback(function()
		if ns.db.routeChannels and ns.RouteChannels then ns:RouteChannels() end
	end)
	whisper:SetValueChangedCallback(function()
		if ns.editDialog and ns.editDialog:IsShown() then ns.editDialog:Refresh() end
	end)

	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end

function ns:OpenOptions()
	if InCombatLockdown and InCombatLockdown() then
		ns.Print("cannot open AddOn Options during combat.")
		return
	end
	if ns.settingsCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.settingsCategory:GetID())
	else
		ns.Print("options are not available on this client.")
	end
end
