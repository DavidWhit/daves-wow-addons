# Dave's Frames (daves_frames)

Target frame: a portrait in a ring, health on the left and the resource on the right, both
emptying toward the portrait, with your debuffs and their buffs on boards hanging below.

Targets: forever (`## Interface: 16001`). Blizzard's own target frame stays as it is.

Players and ordinary NPCs use the plain frame. A rare is the same frame in silver. An elite and a
world boss use that same box. The exact paint mask is
[tools/template/guides/frame-template.png](tools/template/guides/frame-template.png) (`2048 × 600`), with
an exact `16:9` AI-padded guide at
[tools/template/guides/frame-template-ai.png](tools/template/guides/frame-template-ai.png) (`2048 × 1152`).
The standard is in [NOTES.md](NOTES.md). How a plate is painted and packed is in
[tools/template/PAINT-LAYERS.md](tools/template/PAINT-LAYERS.md) (automated via the `daves-frames-paint` skill in [`../../.claude/skills/daves-frames-paint/SKILL.md`](../../.claude/skills/daves-frames-paint/SKILL.md)). The level ring is the white band on the template, drawn above the plate. The number sits in the yellow hole. `Media/frame-*.tga` has that plate in
the top `2048 × 600` of the atlas and its matching 2× `600 × 220` aura board strip directly below it.

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
| Redraw the paint masks | `py -3 tools\Build-FrameTemplate.py` |
| Pack an AI-painted plate into `Media/` | `py -3 tools\Pack-FrameTemplate.py --source painted.png --out Media\frame-plain.tga --silver-out Media\frame-rare.tga` |
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
| `tools\` | `Build-FrameTemplate.py` draws the paint masks (`guides\frame-template*.png`). `Pack-FrameTemplate.py` registers, keys, and packs AI paintings into `Media\frame-*.tga` |
