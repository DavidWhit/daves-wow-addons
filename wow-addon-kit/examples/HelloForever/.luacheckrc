-- luacheck config for WoW addons (https://luacheck.readthedocs.io/en/stable/config.html)
-- WoW runs Lua 5.1 with thousands of API globals, so reading unknown globals (113)
-- is allowed; *setting* one (111/112) is still reported, which catches accidental
-- globals - the most common addon bug and a source of taint.
std = "lua51"
max_line_length = false
codes = true

exclude_files = { "Libs/", "libs/", "Libraries/", ".release/" }

ignore = {
	"113",          -- accessing an undefined global (the WoW API)
	"143",          -- undefined field of a std table (WoW adds string.split, table.wipe, ...)
	"212",          -- unused argument (event handlers receive more than they use)
	"542",          -- empty if branch
	"111/SLASH_.*", -- slash command registration is meant to be global
	"111/BINDING_.*",
}

-- Globals this addon intentionally writes: SavedVariables, public API tables.
globals = {
	"SlashCmdList",
	"StaticPopupDialogs",
	"HelloForeverDB",
	"HelloForever_OnAddonCompartmentClick",
}
