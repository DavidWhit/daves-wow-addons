# Dave's Frames (daves_frames)

Target frame: a portrait in a ring, health on the left and the resource on the right, both
emptying toward the portrait, with your debuffs and their buffs on boards hanging below.

Targets: forever (`## Interface: 16001`). Blizzard's own target frame stays as it is.

Ordinary NPCs use the plain frame. Elites, rare elites / silver elites (covering both `"rare"` and `"rareelite"` classifications), and bosses
use that same box. A player uses their class plate (warrior, paladin, hunter, rogue, priest, shaman,
mage, warlock, druid) when the class token can be read. The exact `16:9` AI paint masks are
[tools/template/guides/frame-template-ai.png](tools/template/guides/frame-template-ai.png) (`2048 × 1152` single-box),
[tools/template/guides/frame-template-extended-ai.png](tools/template/guides/frame-template-extended-ai.png) (`2048 × 1152` branched extended workflow with top `#FF8000` orange crest circle and background `#FF0000` red intricate-artwork rectangle), and the six modular per-section `2048 × 1152` (`16:9`) stencils in
[tools/template/guides/layers/](tools/template/guides/layers/) (`layer-1-backdrop-ai.png` .. `layer-6-level-ai.png`, allowing separate section previews, focused single-section redraws, and `Order 1 → 6` layered compositing).
The standard is in [NOTES.md](NOTES.md). How a plate is painted and packed is in
[tools/template/PAINT-LAYERS.md](tools/template/PAINT-LAYERS.md) (automated via the `daves-frames-paint` and `daves-frames-paint-extended` skills in [`../../.claude/skills/`](../../.claude/skills/)). The level ring is the white band on the template, drawn above the plate. The number sits in the yellow hole. `Media/frame-*.tga` has that plate in
the top `2048 × 600` of the atlas (plus optional extended overhang bands at `x = 608..1768, y = 608..748` and `y = 756..856`). Buffs and debuffs sit on a thin border drawn in Lua. The `600 × 220` strip under the plate is packed and not shown.

## Use

- Open **Edit Mode** and click the frame for its settings: scale, name and cast (Overlay or Stacked),
  numbers (on the portrait, in the bars, off) and Numbers / % / Both, portrait opacity, aura boards
  (on chains or right under the bar), max aura rows (1-4), swing, plate preview (`Auto` to show the
  unit's own plate, or pick any plate to inspect it), pin to top edge.
  In Edit Mode the frame previews on yourself when you have no target.
- `/davesframes test` previews on yourself outside Edit Mode. `/davesframes` opens the Settings page
  (enable, scale). `/davesframes version` prints the version.
- `/davesframes art <key>|auto` forces a frame. Keys are `plain`, `elite`, `rareelite` (`rare` / `silver`
  aliases), `boss`, and the nine classes. A preview on yourself is a player, so it shows your class unless
  you force one. `auto` follows the unit again.

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `Test-WowAddon.py -Path .` |
| Link into the game | `Link-WowAddons.py -Path .` |
| Reload after editing Lua | `/reload` in game (new files, TOC or texture changes need a full restart) |
| Redraw the paint masks & check drawable pixels in layer order | `py -3 tools\Build-FrameTemplate.py --drawable` |
| Validate a painted stencil has zero out-of-bounds pixels | `py -3 tools\Pack-FrameTemplate.py [--extended] --source painted.png --check-only` |
| Pack a standard AI-painted plate into `Media/` | `py -3 tools\Pack-FrameTemplate.py --source painted.png --out Media\frame-elite.tga --silver-out Media\frame-rareelite.tga` |
| Pack an extended AI-painted plate into `Media/` | `py -3 tools\Pack-FrameTemplate.py --extended --source painted-ext.png --layer-dir tools\template\preview\boss-layers --out Media\frame-boss.tga` |
| Composite separate painted sections (`Order 1 → 6`) & emit per-section previews | `py -3 tools\Pack-FrameTemplate.py --extended --layer-backdrop ... --layer-frame ... --layer-lip ... --layer-ring ... --layer-crest ... --layer-level ... --layer-dir tools\template\preview\boss-layers --preview tools\template\preview\boss-preview.png` |
| Check a texture without the game | `tools\Preview-Tga.ps1 -Tga Media\frame-plain.tga -Png preview.png` |

| File | What it does |
| --- | --- |
| `Core.lua` | Settings, events, the per-frame ticker, preview, slash command |
| `Layout.lua` | One geometry for every unit, the class plates and the four NPC variants (`plain`, `elite`, `rareelite`, `boss`), and the colours |
| `Frame.lua` | Builds the layers: boards, bars (clipped to the windows), inset, portrait, art (including extended top/bottom bands), text |
| `Unit.lua` | Health, resource, heals and shields, name, level, colour, portrait, dead (secret-safe) |
| `Cast.lua` | The cast over the resource, or in its strip when Stacked |
| `Auras.lua` | The boards: thin border, lanes, wrapping, max rows with an ellipsis, chains, swing |
| `EditMode.lua` | The Edit Mode dialog (the kit's `EditModeDialog.lua`) |
| `tools\` | `Build-FrameTemplate.py` draws the paint masks (`guides\frame-template-ai.png`, `guides\frame-template-extended-ai.png`, and `guides\layers\layer-1..6-*-ai.png`). `Pack-FrameTemplate.py` registers, keys, emits separate section previews (`--layer-dir`), composites per-section layers (`Order 1 → 6`), and packs standard or `--extended` AI paintings into `Media\frame-*.tga` |
