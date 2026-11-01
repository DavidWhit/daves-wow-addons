# Dave's Frames (daves_frames)

Target frame: a portrait in a ring, health on the left and the resource on the right, both
emptying toward the portrait, with your debuffs and their buffs on boards hanging below.

Targets: forever (`## Interface: 16001`). Blizzard's own target frame stays as it is.

Ordinary NPCs use the plain frame. A rare is the same frame in silver. An elite and a world boss
use that same box. A player uses their class plate (warrior, paladin, hunter, rogue, priest, shaman,
mage, warlock, druid) when the class token can be read. The exact `16:9` AI paint mask is
[tools/template/guides/frame-template-ai.png](tools/template/guides/frame-template-ai.png) (`2048 × 1152`).
The standard is in [NOTES.md](NOTES.md). How a plate is painted and packed is in
[tools/template/PAINT-LAYERS.md](tools/template/PAINT-LAYERS.md) (automated via the `daves-frames-paint` skill in [`../../.claude/skills/daves-frames-paint/SKILL.md`](../../.claude/skills/daves-frames-paint/SKILL.md)). The level ring is the white band on the template, drawn above the plate. The number sits in the yellow hole. `Media/frame-*.tga` has that plate in
the top `2048 × 600` of the atlas. Buffs and debuffs sit on a thin border drawn in Lua. The `600 × 220` strip under the plate is packed and not shown.

## Use

- Open **Edit Mode** and click the frame for its settings: scale, name and cast (Overlay or Stacked),
  numbers (on the portrait, in the bars, off) and Numbers / % / Both, portrait opacity, aura boards
  (on chains or right under the bar), max aura rows (1-4), swing, plate preview (`All` to cycle every
  plate in turn, or pick one to hold), pin to top edge.
  In Edit Mode the frame previews on yourself when you have no target and cycles through the plates.
- `/davesframes test` previews on yourself outside Edit Mode. `/davesframes` opens the Settings page
  (enable, scale). `/davesframes version` prints the version.
- `/davesframes art <key>|auto` forces a frame. Keys are `plain`, `rare`, `elite`, `rareelite`, `boss`, and
  the nine classes. A preview on yourself is a player, so it shows your class unless you force one.
  `auto` follows the unit again.

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
| `Layout.lua` | One geometry for every unit, the class plates and the five NPC variants (`plain`, `rare`, `elite`, `rareelite`, `boss`), and the colours |
| `Frame.lua` | Builds the layers: boards, bars (clipped to the windows), inset, portrait, art, text |
| `Unit.lua` | Health, resource, heals and shields, name, level, colour, portrait, dead (secret-safe) |
| `Cast.lua` | The cast over the resource, or in its strip when Stacked |
| `Auras.lua` | The boards: thin border, lanes, wrapping, max rows with an ellipsis, chains, swing |
| `EditMode.lua` | The Edit Mode dialog (the kit's `EditModeDialog.lua`) |
| `tools\` | `Build-FrameTemplate.py` draws the paint mask (`guides\frame-template-ai.png`). `Pack-FrameTemplate.py` registers, keys, and packs AI paintings into `Media\frame-*.tga` |
