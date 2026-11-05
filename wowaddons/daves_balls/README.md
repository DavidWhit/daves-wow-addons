# Dave's Balls (`daves_balls`)

Diablo-style health and power orbs for WoW: Forever (`v0.1.5`), with swirling liquid that sloshes as you move, cursor-tracked glass glare, and optional Blizzard player-frame replacement.

Targets: WoW: Forever (`## Interface: 16001`).

## Use

- **Edit Mode (`Esc > Edit Mode`)**: drag either orb to move it (snaps to grid and nearby frames; hold `Shift` for free placement), right-click to reset, or click an orb to open its settings (scale, liquid & accent colours, number/percent toggles, accent pattern, and `"Hide Blizzard's player frame"`).
- **Clicks**: left-click targets yourself; right-click opens your player unit menu.
- **Slash Commands** (`/balls` or `/davesballs`):
  - `/balls` — open AddOn Options (`Esc > Options > AddOns`, also in the minimap AddOn Compartment)
  - `/balls unlock` / `/balls lock` — move the orbs outside Edit Mode
  - `/balls reset` — reset both orbs to their default positions
  - `/balls version` — print the loaded version

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Test-WowAddon.py -Path wowaddons/daves_balls` |
| Prepare review packet | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Prepare-WowReview.py -Path wowaddons/daves_balls` |
| Link into the game | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Link-WowAddons.py -Path wowaddons/daves_balls` |
| Rebuild orb textures | `py -3 wowaddons/daves_balls/tools/Make-OrbMedia.py -Out wowaddons/daves_balls/Media` |
| Render PNG preview | `py -3 wowaddons/daves_balls/tools/Preview-Orb.py` |
| Reload after editing Lua | `/reload` in game (new files, `.tga` textures, or TOC changes need a full restart) |

Files: `daves_balls.toc` (manifest), `Core.lua` (startup, events, slash command), `EditModeDialog.lua` (unmodified shared Edit Mode dialog from `wow-addon-kit`), `Options.lua` (Settings panel), `Orbs.lua` (orb rendering, slosh & cursor glare), `OrbSettings.lua` (per-orb Edit Mode settings), `Media/Orb*.tga` (12 uncompressed 32-bit `256×256` orb layers), `tools/Make-OrbMedia.py` & `tools/Preview-Orb.py`.
