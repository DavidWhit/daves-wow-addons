# Dave's Cast Bar (daves_castbar)

An animated, elemental player cast bar for WoW Forever. Each spell gets one of twenty looks (seven elements,
four gathering and six crafting professions, Disenchant, First Aid, and a plain bar), and every cast is different:

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
| First Aid | An open crimson wound bleeding ahead of the cast: the blood runs down and pulses with a heartbeat, beads swell on its lower edge and drip off. Broad bandage turns (a seventh of the bar's length wide, 1.4 to 5 bar heights, so a long bar takes about as many turns as a short one) wrap round it at the cast edge, a roll riding the end of the band (it passes behind the limb at the bar's edges, clipped to the bar), and blood soaks through each turn a moment after it is laid, creeping and drying darker, the soaked turns dripping; the heartbeat slows and the bleeding eases as it binds. Every cast takes a random wrap (spiral, figure-eight, reverse spiral with a fold in each turn, spica, circular), never the last one, and a random lean and way round; the bandage itself is always the same. Using a bandage (the First Aid channel) wraps in from the right as the channel drains. Bandage recipes, and the First Aid channel by name |
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
spell, then the gathering and smelting spells, Disenchant and First Aid (using a bandage) by name, then for crafting casts the recipe's
profession (Blacksmithing, Alchemy, Tailoring, Leatherworking, Enchanting, First Aid; Mining recipes are smelts), then the spell's name ("Frostbolt", anything
with "Flame", ...), then the "Other casts" setting: a look (Plain, Blizzard's own bar, unless you pick another) or "Your class", which picks your class's and specialization's element. Hearthstone, mounts and anything else without a match get that setting.

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `Test-WowAddon.ps1 -Path . -Flavor forever` |
| Link into the game | `Deploy-WowAddon.ps1 -Path . -Flavor forever` |
| Rebuild the art | `& .\tools\Make-CastbarMedia.ps1` |
| Animated preview in the browser | `& .\tools\Show-Preview.ps1` |
| Concept of the look being designed (only that one; finished looks live in the code) | open `tools/concepts/index.html` (see its README) |
| Reload after editing Lua | `/reload` in game (new files, textures or TOC changes need a full restart) |

The approved look is kept in `tools/reference/` for future changes.

Files:

| File | What it does |
| --- | --- |
| `Core.lua` | Startup, saved settings, slash command |
| `Elements.lua` | The twenty looks and which spell gets which (Fishing, Mining, Herb Gathering, Skinning, Smelt ..., Disenchant and First Aid get theirs by name; Blacksmithing, Alchemy, Tailoring, Leatherworking, Enchanting, First Aid and Mining crafts by their recipe's profession) |
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
| `Effects_FirstAid.lua` | First Aid: the wound, the bandage turns, the blood, the roll |
| `EditModeDialog.lua` | The kit's shared Edit Mode settings dialog and selection art (copied from `wow-addon-kit`; don't edit it here) |
| `EditMode.lua` | Moving, resizing, grid snapping, what the settings dialog holds |
| `Options.lua` | Settings panel |
| `Media/` | Generated textures (`tools/Make-CastbarMedia.ps1`) |

## Rules for every look

Every look follows these, so all bars match on frames, corners and depth. Check a new look against them, in the
concept (`tools/concepts`) and again in the add-on. To compare a new look with the others, read their code (`Elements.lua`,
`Bar.lua`, `Effects_*.lua`), not old concepts: a look's concept is deleted once it is built.

| Rule | What it means |
| --- | --- |
| Its own colours | Each look sets `border` (the frame's lit line, in the look's colour), `glow`, `spark` (also the finishing flash) and `veil` in `Elements.lua`; `flashAlpha` lowers the .8 finishing flash where it would glare on pale or dark art (enchanting .18) |
| The bar draws the frame | Framed is `Bar.lua`'s two lines: a dark line .1 bar heights thick, 2/3 of it outside the bar, and the lit line in the look's colour, half as thick, inside. Borderless draws none. A look never paints its own frame, outline or edge, and its edges are never frayed or ragged |
| The masks make the corners | Art is painted as a full rectangle out to the bar's edges, never with corners or rounded ends of its own; every texture that reaches an edge gets the corner masks (`ns.MaskCorners`, `ns.MaskAllTextures`), so square, soft and rounded all work. A mask always covers everything it masks: never rely on CLAMP to stretch a mask past its own rect, which the game does unreliably (the corner masks are long strips, one per end, for that reason) |
| The overlay makes the depth | The bevel is laid over every look. A look doesn't paint its own bevel, inner shadow or heavy dark top and bottom edges; its own shading stays light at the edges (about .2 alpha at most) so Flat looks flat and Bevel isn't doubled |
| Inside the bar | The look's material (cloth, leather, metal, bandage, liquid) never shows past the bar's lines. Only live effects (particles, sparks, steam, dust, drops of blood) spill over the frame line |
| Tools | Tools that work inside the bar (the loom's shuttle and reed, the enchanting vortex, the bandage roll) are clipped to the bar. Tools held in front of it (knife, hammer, ladle, needle) stand over the frame line, below the text |
| Track and fill | The unfilled part is the track: dark, or the look's own art (`track`). Art that crosses the fill edge (a liquid's level, leaning bands, a vortex) uses `wholeBar` and shows the progress itself, still clipped to the bar |
| Channels | A channel drains from the right, so its art runs the other way (frost's channels freeze in from the right) |
| Interrupts | The bar greys its layers; every other piece greys in the look's `interrupted(k)` as the tint fades in over .25 s, and the next cast resets it |
| Markers | Spell looks have the spark at the cast edge; professions and gathering set `noSpark` and their own motion shows the progress |
| Different every cast | Each cast takes the next variation (cloth, pelt, tooling, palette ...) in turn, or a random one that is never the last (first aid's wrap), so two casts in a row differ |
| Sizes | The art reads at the smallest bar (200 x 20) and scales with the bar's height; the spell name and time stay readable over it |
| Nothing turns | Nothing rotates per frame (it shimmers); anything that swings or tips is painted as fixed poses. A piece that only leans may be rotated once when it is laid out and held there (first aid's bandage turns, each set at its own lean when the cast starts) |
| One file per look group | Each look group has its own `Effects_*.lua` registering through `ns.FXi` (Lua allows 200 locals a file) |
