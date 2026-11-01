# Painting a frame

One single-box template for every unit (`plain`, `rare`, `elite` / `worldboss`, `rareelite`, and the nine class frames):

- **Exact 2× canvas mask:** [`guides/frame-template.png`](guides/frame-template.png) (`2048 × 600`, two image pixels per layout pixel).
- **16:9 AI-padded mask (for Gemini Nano Banana / Imagine):** [`guides/frame-template-ai.png`](guides/frame-template-ai.png) (`2048 × 1152`, exact `16:9` with `276` image px of `#FF00FF` magenta padding top and bottom so `16:9` AI image editors keep exact `1:1` proportions with zero stretching or crown clipping).

[`frame-template.json`](frame-template.json) holds the exact sizes. [`../Build-FrameTemplate.py`](../Build-FrameTemplate.py) generates the guides and verifies that [`Layout.lua`](../../Layout.lua) matches:

```powershell
py -3 tools\Build-FrameTemplate.py
```

After painting, [`../Pack-FrameTemplate.py`](../Pack-FrameTemplate.py) registers the AI output back onto the `2048 × 600` mask, strips key fringes, builds the matching 2× `600 × 220` aura board strip, and writes `Media/frame-*.tga`. The frame does not draw that strip. Buffs and debuffs use a thin border in `Auras.lua`.

## Colours

| Colour | Hex | Paint? | What it is |
| --- | --- | --- | --- |
| Blue | `#0000FF` | No | Health (left), mana (right), and the portrait opening |
| Green | `#00FF00` | Yes | The 5 layout px lip around each bar |
| Grey | `#808080` | Yes | The outer frame, 22 layout px around that lip |
| Orange | `#FF8000` | Yes | The portrait ring, radius 105 to 128, including the lower band |
| White | `#FFFFFF` | Yes | The level ring. Its own border, 16 px thick, outer diameter 92 |
| Magenta | `#FF00FF` | No | Outside the frame. Do not add wings, horns, spikes, or glow here |
| Yellow | `#FFFF00` | No | The 60 px hole inside the level ring. The number sits here |

The level ring is a paint layer of its own, drawn on top of the portrait ring. White is that border. Yellow is the placeholder inside it, not paint. The centre is `512, 252`, the middle of the portrait ring at the bottom. The frame is `300` layout px tall so the ring fits, with `2 px` of margin under the rim.

Every variant (`plain`, `rare`, `elite`, `boss`, `class`) keeps this **exact single-box silhouette** — express theme differences (forged gold, silver, obsidian & molten fissures, runes, rivets, surface reliefs) **inside** the Grey, Green, Orange, and White regions rather than protruding into Magenta, Blue, or Yellow.

## The box

Layout pixels, y downward. The 2× PNG is twice this (`2048 × 600`), and `frame-template-ai.png` adds `276` image px of magenta top and bottom (`2048 × 1152`, exact `16:9`).

| Part | Where |
| --- | --- |
| Canvas | `1024 × 300`. Image `2048 × 600` (`2048 × 1152` on `frame-template-ai.png`) |
| Ring centre | `512, 136` |
| Portrait opening | radius `105`. The portrait is `4 px` bigger, so it tucks under the ring |
| Ring | radius `105` to `128`. This is the drawable band. The target portrait fits inside it |
| Health | `35,108` to `379,164` (`344 × 56`) |
| Mana | `645,108` to `989,164`. Same size. Both holes end `5 px` before the ring's outer edge |
| Lip | `5 px` around each hole. On the inner end it runs out to the ring, so the gap meets the circle |
| Outer frame | Plate `8,81` to `1016,191`. It stops where the ring overlaps the middle |
| Level ring | White band on top of the portrait ring, centre `512, 252`. Outer diameter `92`, band `16`. Yellow hole inside, `60 px` across |
| Board strip | `600 × 220` at `y = 608` in the `2048 × 1024` atlas (left `150` + right `150` layout px of the plate at 2× over a dark recessed backing; 9-slice corners `56` atlas px / `28` layout px). Packed, not drawn. The live boards are a 2 px border |

The two bars are gapped by the ring. Each ends on the ring the same way: a `5 px` lip, then the orange band. The grey frame is the border around that lip, on the outside of the plate.

The name is `44` layout px inside the `56 px` window. Scale `0.65` keeps that name at about `14` screen px. Do not grow the box to fit a second line of portrait text.

## Workflow: painting and packing a frame

1. **Paint onto `guides/frame-template-ai.png` (`2048 × 1152`, exact `16:9`):**
   - **Why `16:9` + single-box only (zero-drift rule):** Gemini Nano Banana (`image-generator` / `generate_image`) outputs wide renders at native `16:9` (`1376 × 768`), not `21:9`. Passing a non-`16:9` guide forces vertical resampling, and adding external ornament boxes (wings/spikes outside the plate) tempts the model to shrink the portrait ring. Passing `guides/frame-template-ai.png` (`2048 × 1152`) with `AspectRatio="16:9"` and keeping the exterior solid `#FF00FF` Magenta locks registration to `< 0.65 px` error and `~0.12%` aspect drift.
   - **Proven zero-drift prompt template (used for `paintings/boss.png`):**
     > Edit `guides/frame-template-ai.png` (`2048x1152`, pass `AspectRatio="16:9"`) as an immutable pixel-locked UV stencil for a World of Warcraft `<theme>` target unit frame:
     > 1. Do NOT move, resize, shrink, thicken, or shift the circular rings or rectangular bars by even 1 pixel.
     > 2. Do NOT add wings, horns, spikes, flames, smoke, or drop shadows outside the frame — keep 100% of the `#FF00FF` Magenta exterior, all three `#0000FF` Blue openings (left bar, center portrait circle, right bar), and the `#FFFF00` Yellow level circle completely flat, solid, and unshaded with razor-sharp boundaries.
     > 3. Paint 100% of the `<theme>` character strictly INSIDE the 4 paintable armor regions:
     >    - **Grey (`#808080`) 22px outer bar frame:** `<outer armor material, surface reliefs, cracks/runes/rivets>` keeping the outer rectangular edge razor-straight.
     >    - **Green (`#00FF00`) 5px inner bar lip:** `<gleaming bevelled inner metallic rim>` framing both blue bar windows and meeting the central ring cleanly.
     >    - **Orange (`#FF8000`) central portrait ring:** `<forged collar bezel, rune/material inlays, top-down Warcraft UI specular highlights>` strictly within the orange circular band.
     >    - **White (`#FFFFFF`) lower circular level ring:** `<matching signet bezel>` sitting cleanly on top of the lower portrait ring around the flat `#FFFF00` yellow hole.
2. **Pack into `Media/` with `Pack-FrameTemplate.py`:**
   ```powershell
   # Standard gold plate + automatic silver rare grading:
   py -3 tools\Pack-FrameTemplate.py --source painted.png --plate-out tools\template\preview\mask-plain.png --preview tools\template\preview\mask-plain-preview.png --out Media\frame-plain.tga --silver-out Media\frame-rare.tga

   # Dedicated boss / elite plate + silver rareelite grading:
   py -3 tools\Pack-FrameTemplate.py --source tools\template\paintings\boss.png --plate-out tools\template\preview\boss-plate.png --preview tools\template\preview\boss-preview.png --out Media\frame-elite.tga --silver-out Media\frame-rareelite.tga
   ```
   - **Rounded or sculpted outer corners (optional):**
     - `--outer-radius <layout_px>` (e.g. `--outer-radius 8` or `12`, up to `28`): punches a mathematically identical signed-distance corner radius on all four outer corners of both the plate and the 9-slice aura board strip.
     - `--organic-edge`: lets AI-painted rounded, bevelled, or chipped outer corners stay transparent via chroma-keying while enforcing an airtight `7` layout px solid seal around the bar holes and rings so `StatusBar` widgets (`sideX = 5, sideY = 2`) and the board's recessed backing never poke out.
3. **What `Pack-FrameTemplate.py` does automatically:**
   - Accepts `.png`, `.jpg`/`.jpeg`, or `.tga`, detects the 3 blue holes and yellow level hole, fits global bar/centre scale (`sx`, `sy`) onto `2048 × 600` (warning if aspect drift exceeds `4%`), and radially preserves inner ring bevels (`map_mask_to_source`) so slightly thicker painted portrait/level collar rims stay 100% concentric instead of getting shaved off.
   - Strips 2-pixel AI fringes plus 5-pixel JPEG `4:2:0` magenta/blue chroma-subsampling halos next to flat key colours, smoothly inpaints any key-covered plate pixels, despills residual boundary chroma within `12 px` of any edge (`despill_boundary_rgb`), and applies 1-pixel signed-distance anti-aliasing to every circular and rectangular boundary.
   - Slices the left and right `150` layout px (`300` image px) ends of the plate over a dark recessed billboard backing into the `600 × 220` board strip at `y = 608`, and optionally grades a cool forged-silver variant (`--silver-out`).
