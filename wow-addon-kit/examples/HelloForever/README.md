# Hello Forever

Kit test addon: a small character panel with a secret-safe health bar.

Targets: forever, retail, classic_era (`## Interface: 16001, 120100, 11509`).

## Use

- `/hf` opens the options (also in Esc > Options > AddOns, and the minimap addon menu).
- `/hf version` prints the version.

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `Test-WowAddon.ps1 -Path . -Flavor forever,retail,classic_era` |
| Link into the game | `Deploy-WowAddon.ps1 -Path . -Flavor forever` |
| Reload after editing Lua | `/reload` in game (new files or TOC changes need a full restart) |

Files: `HelloForever.toc` (manifest), `Core.lua` (startup, events, slash command), `Options.lua` (Settings panel).
