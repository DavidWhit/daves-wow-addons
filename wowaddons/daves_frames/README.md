# Dave's Frames (daves_frames)

Target frame: a portrait in a ring, health on the left and the resource on the right, both
emptying toward the portrait, with your debuffs and their buffs on boards hanging below.

Targets: forever (`## Interface: 16001`). Blizzard's own target frame stays as it is.

Players and ordinary NPCs use the plain frame. A rare is the same frame in silver. An elite and a
world boss use that same box. The paint mask is
[tools/template/guides/frame-template.png](tools/template/guides/frame-template.png). The standard
is in [NOTES.md](NOTES.md). How that plate was painted is in
[tools/template/PAINT-LAYERS.md](tools/template/PAINT-LAYERS.md). The level is Blizzard's circle,
centred on the lower ring, drawn above the plate. `Media/frame-*.tga` has that plate in
the top of the atlas. The board strip under it is still the previous one.

## Use

- Open **Edit Mode** and click the frame for its settings: scale, name and cast (Overlay or Stacked),
  numbers (on the portrait, in the bars, off) and Numbers / % / Both, portrait opacity, aura boards
  (on chains or right under the bar), max aura rows (1-4), swing, pin to top edge.
  In Edit Mode the frame previews on yourself when you have no target.
- `/davesframes test` previews on yourself outside Edit Mode. `/davesframes` opens the Settings page
  (enable, scale). `/davesframes version` prints the version.
- `/davesframes art plain|rare|elite|rareelite|auto` forces a frame. A preview on yourself is a
  player, so it would otherwise always show plain. `auto` follows the unit again.

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `Test-WowAddon.py -Path . -Flavor forever` |
| Link into the game | `Link-WowAddons.py -Path .` |
| Reload after editing Lua | `/reload` in game (new files, TOC or texture changes need a full restart) |
| Redraw the paint mask | `py -3 tools\Build-FrameTemplate.py` |
| Check a texture without the game | `tools\Preview-Tga.ps1 -Tga Media\frame-plain.tga -Png preview.png` |

| File | What it does |
| --- | --- |
| `Core.lua` | Settings, events, the per-frame ticker, preview, slash command |
| `Layout.lua` | One geometry for every unit, the four art variants, and the colours |
| `Frame.lua` | Builds the layers: boards, bars (clipped to the windows), inset, portrait, art, text |
| `Unit.lua` | Health, resource, heals and shields, name, level, colour, portrait, dead (secret-safe) |
| `Cast.lua` | The cast over the resource, or in its strip when Stacked |
| `Auras.lua` | The boards: lanes, wrapping, max rows with an ellipsis, chains, swing |
| `EditMode.lua` | The Edit Mode dialog (the kit's `EditModeDialog.lua`) |
| `tools\` | `Build-FrameTemplate.py` draws the paint mask. `template\guides\frame-template.png` is that mask |
