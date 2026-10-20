# Dave's Frames (daves_frames)

Dragon target frame: a portrait in a ring, health on the left and the resource on the right, both
emptying toward the portrait, with your debuffs and their buffs on boards hanging below.

Targets: forever (`## Interface: 16001`). Blizzard's own target frame stays as it is.

For now every target uses the **gold elite** art, so the frame can be tried and adjusted before more
variants are painted. The standard every variant follows is in [NOTES.md](NOTES.md).

## Use

- Open **Edit Mode** and click the frame for its settings: scale, name and cast (Overlay or Stacked),
  numbers (on the portrait, in the bars, off) and Numbers / % / Both, portrait opacity, aura boards
  (on chains or right under the bar), max aura rows (1-4), swing, pin to top edge.
  In Edit Mode the frame previews on yourself when you have no target.
- `/davesframes test` previews on yourself outside Edit Mode. `/davesframes` opens the Settings page
  (enable, scale). `/davesframes version` prints the version.

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `Test-WowAddon.ps1 -Path . -Flavor forever` |
| Link into the game | `Link-WowAddons.ps1 -Path .` |
| Reload after editing Lua | `/reload` in game (new files, TOC or texture changes need a full restart) |
| Rebuild the textures from a painting | `tools\Make-FrameMedia.ps1 -Source <painting.jpg> -Variant gold` |
| Check a texture without the game | `tools\Preview-Tga.ps1 -Tga Media\frame-gold.tga -Png preview.png` |
| Redraw the layer paint guides | `tools\template\Make-LayerGuides.ps1 -Out tools\template\guides` |

| File | What it does |
| --- | --- |
| `Core.lua` | Settings, events, the per-frame ticker, preview, slash command |
| `Layout.lua` | Positions per art variant (gold elite v1, measured) and the colours |
| `Frame.lua` | Builds the layers: boards, bars (clipped to the windows), inset, portrait, art, text |
| `Unit.lua` | Health, resource, heals and shields, name, level, colour, portrait, dead (secret-safe) |
| `Cast.lua` | The cast over the resource, or in its strip when Stacked |
| `Auras.lua` | The boards: lanes, wrapping, max rows with an ellipsis, chains, swing |
| `EditMode.lua` | The Edit Mode dialog (the kit's `EditModeDialog.lua`) |
| `tools\` | Keying and cutting the painting into `Media\frame-<variant>.tga`, chain and stripe textures, and `template\` with the layer paint guide for new variants |
