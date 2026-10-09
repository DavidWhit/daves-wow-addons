# Dave's Cast Bar (daves_castbar)

An animated, elemental player cast bar for WoW Forever. Each spell gets one of nineteen looks (seven elements,
four gathering and six crafting professions, Disenchant, and a plain bar), and every cast is different:

| Element | Look |
| --- | --- |
| Frost | Water flows ahead of the cast and freezes into ice behind it, with a frosty freeze front; a glint sweeps across the ice. Channels (Blizzard) freeze the other way: the ice grows in from the right as the channel drains |
| Fire | Scrolling flames rising up the bar; embers rise from the bottom and carry on off the top |
| Shadow | Black smoke with purple seams, dark wisps drifting up |
| Nature | Vines that grow with the cast, twisting around each other, with leaves and thorns |
| Lightning | A dark storm: a painted indigo cloud (the one in `tools/ref_cloud.jpg`), laid out afresh every cast as a far row of small copies and a near bank of big ones, some mirrored, drifting at their own pace; forked bolts strike inside the bar and light the clouds near them from within; now and then a dim sheet of lightning. Lightning, Thunder and Storm spells (and Elemental shamans) |
| Arcane | Rune circles at random heights and sizes, held still (turning made them shimmer); glyphs flare up |
| Holy | Soft gold with four-point stars twinkling in and out |
| Fishing | A pond: lily pads drift on top, fish swim below, the bobber rides the cast edge with ripples |
| Herbalism | The nature vines, with flowers blooming along them |
| Mining | Rails along a rock wall: a gem cart rolls to the cast edge while a pickaxe strikes the wall at the end |
| Skinning | The pelt rolls back over marbled meat: fur ahead of the cast (a different pelt every cast: bear, wolf, tawny cat, red fox, arctic white, black bear, nightsaber, boar), the hide rolling up at the cast edge, a pool of blood spreading behind the knife, which stands against the roll with its edge on it, sawing up and down |
| Smelting | A forged-iron ladle rides the cast edge, pouring a glowing stream; the molten steel is pale yellow where it lands and cools through orange to dark crust behind it, its seams still glowing; sparks fly where the stream lands. At the end the ladle tips back and lifts away |
| Blacksmithing | Red-hot iron, hottest at the cast edge, cold iron ahead; a forge hammer (wood and brass, or antler and steel) strikes the edge in rhythm, each blow a flash, sparks, a puff of steam and a flare that cools; steam rises more as it heats. Finishing quenches it: a cloud of steam and grey tempered steel with a faint straw-to-blue sheen |
| Alchemy | A bench of glassware stands on the bar, shuffled every cast: a flask boiling over a burner, a retort, measuring cylinders, a condenser, a glass coil, a vial rack, a funnel dripping into a beaker, joined by glass, bent glass and hoses with brass valves. The potion works its way through, lighting burners and filling each in turn, and pours into the bar, which fills like a liquid (it spreads, sloshes and bubbles) and brims at the end |
| Tailoring | A small loom: taut warp ahead of the cast, woven cloth behind it (linen, wool, silk, mageweave, runecloth or mooncloth, one per cast in turn, with a slow sheen); at the cast edge a small worn boat shuttle crosses the shed with the weft and a slim steel reed beats each pick in, fluff flying; the loom is clipped to the bar, so nothing of it shows past the bar's lines |
| Leatherworking | Tooled leather panels (five tones; the tooling changes each cast: basket-weave, scrolling vine, diamond lattice, bordered shells, knotwork band) lie across the bar with their lacing holes punched, apart by the gaps still open. As the cast reaches each joint the gap closes and a steel needle cross-laces it shut with a thong; running stitches follow along both edges |
| Enchanting | Dark velvet the magic settles on (a palette per cast: violet, sea-blue, orchid or indigo): behind the cast edge it shimmers with flowing bands of light and glitter; at the edge a vortex of spinning rings pulls glittering dust out of the unfilled part and spins it in |
| Disenchant | The bar starts solid with magic; the vortex comes in at the right end and moves left, drawing the magic out of the solid part ahead of it (it fades as it is drawn off) and throwing it out behind as glittering dust and small shimmers that settle on the cloth it leaves spent; the vortex leads the edge and is clipped away by the time the cast completes. For the spell Disenchant |
| Plain | Blizzard's own cast bar art (its filling, green for channels, full when done, red when interrupted), no effects. The default for casts the addon can't place (the "Other casts" setting) |

Spell looks mark the cast edge with a spark, like Blizzard's bar for damage and healing casts; casts that are not spells (the gathering and crafting professions) get no marker, and their own art shows the progress.

Framed or borderless; edges are always clean, never frayed. Framed draws a thin line in the look's colour (Blizzard's frame for Plain); borderless draws none. Corners can be square, soft (slightly rounded, the default) or rounded, and the depth flat or a bevel (light along the top, shade along the bottom, a shadow inside the frame); every look follows both.

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
spell, then the gathering and smelting spells and Disenchant by name, then for crafting casts the recipe's
profession (Blacksmithing, Alchemy, Tailoring, Leatherworking, Enchanting; Mining recipes are smelts), then the spell's name ("Frostbolt", anything
with "Flame", ...), then the "Other casts" setting: a look (Plain, Blizzard's own bar, unless you pick another) or "Your class", which picks your class's and specialization's element. Hearthstone, mounts and anything else without a match get that setting.

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `Test-WowAddon.ps1 -Path . -Flavor forever` |
| Link into the game | `Deploy-WowAddon.ps1 -Path . -Flavor forever` |
| Rebuild the art | `& .\tools\Make-CastbarMedia.ps1` |
| Animated preview in the browser | `& .\tools\Show-Preview.ps1` |
| Concepts the looks were designed from | open `tools/concepts/index.html` (see its README) |
| Reload after editing Lua | `/reload` in game (new files, textures or TOC changes need a full restart) |

The approved look is kept in `tools/reference/` for future changes.

Files:

| File | What it does |
| --- | --- |
| `Core.lua` | Startup, saved settings, slash command |
| `Elements.lua` | The nineteen looks and which spell gets which (Fishing, Mining, Herb Gathering, Skinning, Smelt ... and Disenchant get theirs by name; Blacksmithing, Alchemy, Tailoring, Leatherworking, Enchanting and Mining crafts by their recipe's profession) |
| `Bar.lua` | The bar, casting states, fill, glow, spark, frame, text, hiding Blizzard's bar |
| `Effects.lua` | Particles, the shared helpers (`ns.FXi`) and the hooks the bar calls; the looks register with it from the files below (Lua allows 200 locals a file, so each group has its own) |
| `Effects_Spells.lua` | Frost, nature and herbalism vines, arcane, holy |
| `Effects_Gathering.lua` | Fishing, mining, skinning |
| `Effects_Forge.lua` | Blacksmithing and smelting |
| `Effects_Storm.lua` | Lightning: the painted clouds and the bolts |
| `Effects_Alchemy.lua` | The alchemy bench and trough |
| `Effects_Tailor.lua` | The tailoring loom |
| `Effects_Leather.lua` | The leatherworking panels and laces |
| `Effects_Ench.lua` | Enchanting and disenchant |
| `EditModeDialog.lua` | The kit's shared Edit Mode settings dialog and selection art (copied from `wow-addon-kit`; don't edit it here) |
| `EditMode.lua` | Moving, resizing, grid snapping, what the settings dialog holds |
| `Options.lua` | Settings panel |
| `Media/` | Generated textures (`tools/Make-CastbarMedia.ps1`) |
