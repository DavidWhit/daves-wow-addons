# Painting a frame

The template is [`guides/frame-template.png`](guides/frame-template.png) (2048 × 544, two layout pixels per image pixel). [`frame-template.json`](frame-template.json) is the same sizes. [`../Build-FrameTemplate.py`](../Build-FrameTemplate.py) draws both and checks that [`Layout.lua`](../../Layout.lua) still matches.

```powershell
py -3 tools\Build-FrameTemplate.py
```

This mask is the template. Paint with Imagine onto this picture, then key the result back onto the mask in code. The mask is exact regions, so the script draws it. The metal comes from Imagine.

## Colours

| Colour | Hex | Paint? | What it is |
| --- | --- | --- | --- |
| Blue | `#0000FF` | No | Health (left), mana (right), and the portrait opening |
| Green | `#00FF00` | Yes | The 5 layout px lip around each bar |
| Grey | `#808080` | Yes | The outer frame, 22 layout px around that lip |
| Orange | `#FF8000` | Yes | The portrait ring, radius 105 to 128, including the lower band |
| Magenta | `#FF00FF` | No | Outside the frame |

The level is not a hole. Blizzard's circle (`UI-HUD-UnitFrame-SmallCircle`) is drawn by the addon, centred on the lower ring (layout 512, 252), above the plate.

## The box

Layout pixels, y downward. The PNG is twice this.

| Part | Where |
| --- | --- |
| Canvas | 1024 × 272. Image 2048 × 544 |
| Ring centre | 512, 136 |
| Portrait opening | radius 105. The portrait is 4 px bigger, so it tucks under the ring |
| Ring | radius 105 to 128. This is the drawable band. The target portrait fits inside it |
| Health | 35,108 to 379,164 (344 × 56) |
| Mana | 645,108 to 989,164. Same size. Both holes end 5 px before the ring's outer edge |
| Lip | 5 px around each hole. On the inner end it runs out to the ring, so the gap meets the circle |
| Outer frame | Plate 8,81 to 1016,191. It stops where the ring overlaps the middle |
| Level | centre 512, 252. Drawn on top. The ring under it stays orange |

The two bars are gapped by the ring. Each ends on the ring the same way: a 5 px lip, then the orange band. The grey frame is the border around that lip, on the outside of the plate.

The name is 44 layout px inside the 56 px window. Scale 0.65 keeps that name at about 14 screen px. Do not grow the box to fit a second line of portrait text.

## How the plain plate was painted

1. Edit `guides/frame-template.png` with Imagine. The grey frame, the green lip, and the orange ring become one aged-gold plate: a thick bevel, a dark groove inside the lip, a bright top edge. The blue holes and the magenta outside stay flat pure colours.
2. The picture comes back a different size. Find the portrait hole and the two bar holes in that picture. Scale X from the distance between the bar centres (1220 image pixels on the mask). Scale Y from the portrait hole (420 image pixels across on the mask). Sample the picture only where the mask is green, grey, or orange. Leave blue and magenta clear.
3. A pixel that lands on a flat key colour takes the nearest gold instead.

`Media/frame-plain.tga` and `frame-elite.tga` have this plate in the top 2048×544. Rare and rare-elite are the same plate in silver. The board strip under that slot is still the previous one. `Build-FrameTemplate.py` does not write `Media/`.
