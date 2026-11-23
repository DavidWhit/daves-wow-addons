# Dave's Balls (`daves_balls`)

Diablo-style health and power orbs for WoW: Forever (`v0.2.7`), with swirling liquid that sloshes as you move, cursor-tracked glass glare, optional animated bottom holders, subtle orb bobbing, light-driven cast shadows, 3D swirling dust motes with selectable orbit patterns, rotation, spread, true sphere-rim occlusion, curved comet tails and independent shimmering dust trails, and optional Blizzard player-frame replacement.

Targets: WoW: Forever (`## Interface: 16001`).

## Use

- **Edit Mode (`Esc > Edit Mode`)**: drag either orb to move it (snaps to grid and nearby frames; hold `Shift` for free placement), or left- or right-click an orb to open its per-orb settings dialog (use the dialog's **Reset position** button or `/balls reset` to reset):
  - Liquid & accent colours, compact **Orb text** (`Off`, `Numbers`, `Percent`, `Both`), random accent pattern, and `"Hide Blizzard player frame"`.
  - **Bottom holder** (`None`, `Chalice`, `Arcane`, `Sanctum`), selectable per orb so you can compare looks side by side.
  - **Bob intensity** slider (`Off` / `5%`–`100%`) to gently float the orb up and down inside its stationary container.
  - **Cast shadow** toggle — casts a soft elliptical shadow beneath the orb whose angle, spread, and depth follow the cursor glare light already hitting the glass and the orb's live bob height.
  - **Swirling dust** — **Orbit pattern** (`Auto`, `Halo Ring`, `Twin Helix`, `Figure-8`, `Vortex`, `Atom Shells`, `Chaos`), **Particle count** (`Off` / `2`–`40`, default `20`), **Dust speed** (`0.2x`–`2.5x`), **Pattern rotation** (`-180` to `+180 deg`), **Particle spread** (`0%`–`100%`, from a tight orbital track to a wide ribbon band), **Trail style** (`Off`, `Tails`, `Dust`, `Both`), and **Tail length** (`20%`–`100%`) driving 3D orbiting motes with true sphere-rim occlusion (disappearing cleanly behind the glass sphere and emerging around its rim) plus independent curved comet tails and shimmering **Dust trails** (global **Orb bobbing**, **Cast shadow**, **Swirling dust**, **Orbit pattern**, **Particle tails**, and **Shimmering dust trails** controls are also in `Esc > Options > AddOns`).
- **Optional Bottom Holders** (`None` by default; selectable globally in `Esc > Options > AddOns`, per-orb in Edit Mode, or via `/balls holder`):
  - **Gilded Chalice** (`chalice`): wrought dark-iron and antique brass cup with a liquid-tinted keystone gem and gilded filigree.
  - **Arcane Cradle** (`arcane`): floating Titan/Dalaran levitation ring and plasma conduit prongs with flowing veins and crackling arcs.
  - **Sanctum Lotus** (`sanctum`): carved dark-basalt altar basin and antique-gold blooming lotus petals with a visible 3/4 concave stone dish floor designed to catch the bobbing orb's light-driven cast shadow.
  - All three cradle only the bottom of the orb so the upper glass, liquid surface, and glare stay unobstructed, reacting live to each orb's liquid/accent colours, core breath, vein flicker, bobbing proximity, movement slosh, and cursor glare.
- **Clicks**: left-click targets yourself; right-click opens your player unit menu.
- **Slash Commands** (`/balls` or `/davesballs`):
  - `/balls` — open AddOn Options (`Esc > Options > AddOns`, also in the minimap AddOn Compartment)
  - `/balls holder <none|chalice|arcane|sanctum>` — switch both orbs' bottom holder variant
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
| Rebuild holder, shadow & dust textures | `py -3 wowaddons/daves_balls/tools/Make-HolderMedia.py -Out wowaddons/daves_balls/Media` |
| Render PNG preview | `py -3 wowaddons/daves_balls/tools/Preview-Orb.py -Media wowaddons/daves_balls/Media -Sheet preview.png` |
| Reload after editing Lua | `/reload` in game (new files, `.tga` textures, or TOC changes need a full restart) |

Files: `daves_balls.toc` (manifest), `Core.lua` (startup, events, slash command), `EditModeDialog.lua` (unmodified shared Edit Mode dialog from `wow-addon-kit`), `Options.lua` (Settings panel), `Holders.lua` (optional animated bottom holders, orb bobbing & light-driven cast shadows), `Particles.lua` (3D swirling dust motes with selectable orbit patterns, sphere-rim occlusion, curved comet tails & independent shimmering dust trails), `Orbs.lua` (orb rendering, slosh & cursor glare), `OrbSettings.lua` (per-orb Edit Mode settings), `Media/Orb*.tga` (12 orb layers + `OrbCastShadow.tga`, `OrbMote.tga`, `OrbWisp.tga`, `OrbTail.tga`), `Media/Holder*.tga` (15 uncompressed 32-bit `512×256` holder layers), `tools/Make-OrbMedia.py`, `tools/Make-HolderMedia.py` & `tools/Preview-Orb.py`.
