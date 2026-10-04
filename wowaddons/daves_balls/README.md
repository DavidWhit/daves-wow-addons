# Dave's Balls

Diablo-style UI elements for WoW Forever

Targets: forever (`## Interface: 16001`).

## Use

- `/balls` opens the options (also in Esc > Options > AddOns, and the minimap addon menu).
- `/balls version` prints the version.

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `Test-WowAddon.ps1 -Path . -Flavor forever` |
| Link into the game | `Deploy-WowAddon.ps1 -Path . -Flavor forever` |
| Reload after editing Lua | `/reload` in game (new files or TOC changes need a full restart) |

Files: `daves_balls.toc` (manifest), `Core.lua` (startup, events, slash command), `EditModeDialog.lua` (the kit's shared Edit Mode dialog and selection art; copied from `wow-addon-kit`, don't edit it here), `Options.lua` (Settings panel), `Orbs.lua` (the orbs), `OrbSettings.lua` (each orb's Edit Mode settings).
