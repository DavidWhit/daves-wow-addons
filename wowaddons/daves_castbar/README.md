# Dave's Cast Bar (daves_castbar)

An animated, elemental player cast bar for WoW Forever. Each spell gets one of six looks, and every
cast is different:

| Element | Look |
| --- | --- |
| Frost | Diamond-cut ice, re-cut at random every cast; two cuts traced to the fill edge; a glint sweeps across |
| Fire | Scrolling flames, embers rising |
| Shadow | Black smoke with purple seams, dark wisps drifting up |
| Nature | Vines that grow with the cast, twisting around each other, with leaves and thorns |
| Arcane | Rune circles at random heights and sizes, each turning its own way; glyphs flare up |
| Holy | Soft gold with four-point stars twinkling in and out |

Targets: forever (`## Interface: 16001`).

## Use

- Cast something. The bar replaces Blizzard's player cast bar (you can turn that off).
- **Edit Mode**: drag the bar to move it (it snaps to the grid when Snap is on; hold Shift to place
  freely), drag its corner to resize, click it for settings and a preview of each element,
  right-click to reset.
- `/castbar` opens the options (also Esc > Options > AddOns, and the minimap addon menu).
- `/castbar test [element]` plays a pretend cast.
- `/castbar set <element>` right after casting a spell picks that spell's look; `/castbar set auto` undoes it.
- `/castbar unlock` / `lock` lets you move the bar outside Edit Mode. `/castbar reset` puts it back.

WoW gives addons no way to read a spell's school, so the element comes from your choice for that
spell, then the spell's name ("Frostbolt", anything with "Flame", ...), then your class and
specialization, then the "Other casts" setting.

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `Test-WowAddon.ps1 -Path . -Flavor forever` |
| Link into the game | `Deploy-WowAddon.ps1 -Path . -Flavor forever` |
| Rebuild the art (and `FrostCuts.lua`) | `& .\tools\Make-CastbarMedia.ps1` |
| Animated preview in the browser | `& .\tools\Show-Preview.ps1` |
| Reload after editing Lua | `/reload` in game (new files, textures or TOC changes need a full restart) |

The approved look is kept in `tools/reference/` for future changes.

Files:

| File | What it does |
| --- | --- |
| `Core.lua` | Startup, saved settings, slash command |
| `Elements.lua` | The six looks and which spell gets which |
| `FrostCuts.lua` | Generated: the frost cut lines, so the bar can trace them |
| `Bar.lua` | The bar, casting states, fill, glow, spark, text, borderless masks, hiding Blizzard's bar |
| `Effects.lua` | Particles and each element's live effects |
| `EditModeDialog.lua` | The kit's shared Edit Mode settings dialog and selection art (copied from `wow-addon-kit`; don't edit it here) |
| `EditMode.lua` | Moving, resizing, grid snapping, what the settings dialog holds |
| `Options.lua` | Settings panel |
| `Media/` | Generated textures (`tools/Make-CastbarMedia.ps1`) |
