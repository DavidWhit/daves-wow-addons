# Reference previews

Animated previews whose looks were signed off before the in-game code was written. Each is
self-contained (textures embedded), so open it in any browser to see how each look is meant to look and move.

## `approved-preview-2026-10-04-professions.html` (current)

- **Frost**: a level band of water flows ahead of the cast and freezes into a cloudy, cracked ice slab behind it; a frosty freeze front at the edge sheds flakes; a light glint sweeps across the ice now and then.
- **Fire**: the original scrolling flames, rising up the bar (the first preview scrolled them downward by mistake); embers rise from the bottom and more carry on off the top.
- **Shadow**, **Nature**, **Arcane**, **Holy**: as in the first preview below.
- **Fishing**: a pond the length of the bar; lily pads drift on the surface (some with a blossom), fish swim below and turn at random; the red-and-white bobber rides the cast edge on its line, sending out ripples.
- **Herbalism**: the nature vines, with red, blue, purple, yellow and teal flowers blooming along them; golden pollen drifts.
- **Mining**: rails along a stone wall with ore glints, dim ahead of the cast and lantern-lit behind; a gem cart with a lantern rolls along the rail to the cast edge, wheels turning; a pickaxe swings at the wall at the bar's end, throwing chips and sparks.
- **Skinning**: a dusk pasture of hopping cows and pigs; a cleaver swings like the pickaxe and chops at the cast edge, and each animal it reaches turns into a bone pile on a blood stain with a spray of blood; the filled part of the grass is stained red.

## `approved-preview-2026-10-04.html` (first)

- **Frost**: diamond-cut ice rebuilt every cast from stacked cut layers; two cuts traced to the fill edge; a light glint sweeps across now and then. (Replaced by the freezing water above.)
- **Fire**: scrolling flames with embers rising.
- **Shadow**: black smoke with purple seams; dark wisps drift up.
- **Nature**: vines grow with the cast, twisting gently, with leaves and thorns.
- **Arcane**: rune circles at random heights and sizes, each rotating its own way; glyphs flare up.
- **Holy**: soft gold with four-point stars twinkling in and out.

The URL options work in both, for example `?style=framed&h=48&hold=70&only=frost,fishing`.

To see the current art instead, run `tools/Show-Preview.ps1`. It regenerates the textures and builds
the page from `tools/preview.html`. When a new look is approved, save the built page here under a new
name rather than replacing an older one.
