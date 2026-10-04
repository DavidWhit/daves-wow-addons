# {{TITLEPLAIN}}

{{NOTES}}

Targets: {{FLAVORS}} (`## Interface: {{INTERFACES}}`).

## Use

- `/{{SLASH}}` opens the options (also in Esc > Options > AddOns, and the minimap addon menu).
- `/{{SLASH}} version` prints the version.

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `Test-WowAddon.ps1 -Path . -Flavor {{FLAVORLIST}}` |
| Link into the game | `Deploy-WowAddon.ps1 -Path . -Flavor forever` |
| Reload after editing Lua | `/reload` in game (new files or TOC changes need a full restart) |

Files: `{{NAME}}.toc` (manifest), `Core.lua` (startup, events, slash command), `Options.lua` (Settings panel).
