# Dave's Cast Bar (daves_castbar)

An animated, elemental player cast bar for WoW Forever. Each spell gets one of ten looks (six elements
and four gathering professions), and every cast is different:

| Element | Look |
| --- | --- |
| Frost | Water flows ahead of the cast and freezes into ice behind it, with a frosty freeze front; a glint sweeps across the ice. Channels (Blizzard) freeze the other way: the ice grows in from the right as the channel drains |
| Fire | Scrolling flames rising up the bar; embers rise from the bottom and carry on off the top |
| Shadow | Black smoke with purple seams, dark wisps drifting up |
| Nature | Vines that grow with the cast, twisting around each other, with leaves and thorns |
| Arcane | Rune circles at random heights and sizes, held still (turning made them shimmer); glyphs flare up |
| Holy | Soft gold with four-point stars twinkling in and out |
| Fishing | A pond: lily pads drift on top, fish swim below, the bobber rides the cast edge with ripples |
| Herbalism | The nature vines, with flowers blooming along them |
| Mining | Rails along a rock wall: a gem cart rolls to the cast edge while a pickaxe strikes the wall at the end |
| Skinning | Cows and pigs along a pasture: a cleaver chops at the cast edge, turning each one into a bone pile on a blood stain |

Targets: forever (`## Interface: 16001`).

## Use

- Cast something. The bar replaces Blizzard's player cast bar (you can turn that off).
- **Edit Mode**: drag the bar to move it (it snaps to the grid when Snap is on; hold Shift to place
  freely), drag its corner to resize (at least 200 x 20, so the art and text have room), click it for settings and a preview of each element,
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
| Rebuild the art | `& .\tools\Make-CastbarMedia.ps1` |
| Animated preview in the browser | `& .\tools\Show-Preview.ps1` |
| Profession concepts (not in game yet) | open `tools/concepts/index.html` (see its README) |
| Reload after editing Lua | `/reload` in game (new files, textures or TOC changes need a full restart) |

The approved look is kept in `tools/reference/` for future changes.

Files:

| File | What it does |
| --- | --- |
| `Core.lua` | Startup, saved settings, slash command |
| `Elements.lua` | The ten looks and which spell gets which (Fishing, Mining, Herb Gathering and Skinning get theirs by name) |
| `Bar.lua` | The bar, casting states, fill, glow, spark, text, borderless masks, hiding Blizzard's bar |
| `Effects.lua` | Particles and each element's live effects |
| `EditModeDialog.lua` | The kit's shared Edit Mode settings dialog and selection art (copied from `wow-addon-kit`; don't edit it here) |
| `EditMode.lua` | Moving, resizing, grid snapping, what the settings dialog holds |
| `Options.lua` | Settings panel |
| `Media/` | Generated textures (`tools/Make-CastbarMedia.ps1`) |
