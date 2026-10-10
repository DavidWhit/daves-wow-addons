# Dave's WoW addons

WoW addons (`wowaddons/`) plus the kit that builds and checks them (`wow-addon-kit/`, plugin `wow-forever-addons`).

## Use the plugin for anything WoW

For any World of Warcraft work here, use the `wow-forever-addons` plugin's skills, agent and scripts, not recall or the web:

| Task | Use |
| --- | --- |
| Does an API/event exist, is it secret, did it move | `wow-forever-api` skill → `scripts/Find-WowApi.ps1` |
| How Blizzard's own UI does something | local source `wow-addon-kit/plugins/wow-forever-addons/data/ui-source/forever/` → look up in `INDEX.tsv` first |
| Something broke in game (error, "action blocked", "only available to the Blizzard UI", odd behaviour) | `wow-addon-test` skill, step 0, **before reading code**: `scripts/Get-WowScriptErrors.ps1 -Addon <name>` (Lua errors and stacks recorded by `devaddons/!WowKitErrors`), then `scripts/Get-WowTaintLog.ps1 -Addon <name>`, and work backwards from the failing line or the tainted read |
| After any addon change | `wow-addon-test` skill (validator + `wow-addon-reviewer` agent in advisor mode) |
| New addon / install, link, Interface number / release | `wow-addon-new` / `wow-addon-setup` / `wow-addon-release` |
| Refresh daves_map's Map Genie pins and quest links | `daves-map-refresh` skill (`.claude/skills/`) → `wowaddons/daves_map/tools/Update-MapData.ps1`; generates the companion addon `wowaddons/daves_map_data/`, never committed |

When a plugin script or the local source is missing or stale, refresh it (`Update-WowApiIndex.ps1`, `Update-WowUiSource.ps1`) rather than working around it.
