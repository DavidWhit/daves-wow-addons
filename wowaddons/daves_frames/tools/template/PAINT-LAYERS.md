# Painting a frame

One single-box template for every unit (`plain`, `elite`, `rareelite`, `boss`, and the nine class frames):

- **16:9 AI-padded mask (for Gemini Nano Banana / Imagine):** [`guides/frame-template-ai.png`](guides/frame-template-ai.png) (`2048 × 1152`, exact `16:9`: the `2048 × 600` 2× canvas with `276` image px of `#FF00FF` magenta padding top and bottom so `16:9` AI image editors keep exact `1:1` proportions with zero stretching or crown clipping).
- **Branched Extended 16:9 AI mask:** [`guides/frame-template-extended-ai.png`](guides/frame-template-extended-ai.png) (`2048 × 1152`, exact `16:9`: keeps every existing section at its exact size and position, adds the top `#FF8000` Orange crest circle at `512, 20` radius `37` / diameter `74` (`4/5` of the `92 px` level ring) overlaying the portrait and portrait ring, and adds an upper background `#FF0000` Red rectangle at `x = 222..802, y = -70..81` layout px (`x = 444..1604, y = 136..438` image px, strictly above the horizontal bars and outside the portrait/crest rings) behind everything for optional intricate upper wings, chains, or filigree where unfilled `#FF0000` Red keys to transparent). Everything below the horizontal bars (`y >= 81` layout / `y >= 438` image px) is `#FF00FF` Magenta (`OFF-LIMITS`) so no bottom wings or bottom chains compete with `daves_frames`'s dynamic swinging aura boards (`pivotY = 189`); see `.claude/skills/daves-frames-paint-extended/SKILL.md`.
- **Modular Per-Section 16:9 Layer Stencils (`guides/layers/`, Order `1 → 6`):** [`../Build-FrameTemplate.py`](../Build-FrameTemplate.py) also writes six isolated `2048 × 1152` (`16:9`) section stencils preserving the exact `#0000FF` Blue + `#FFFF00` Yellow fiducial holes (`max_err = 0.00 px`) so each section can be painted, previewed separately (`--layer-dir`), redrawn in isolation without regenerating the rest of the frame, and composited back-to-front in exact guide order:
  1. [`guides/layers/layer-1-backdrop-ai.png`](guides/layers/layer-1-backdrop-ai.png) — `Order 1 [BACK]` (`backdrop`, extended): `#FF0000` Red upper intricate-art backdrop (`x = 222..802, y = -70..81` layout px, carved strictly outside the `r = 128` portrait ring and `r_top = 37` top crest circle and above the `y = 81` horizontal bar top so `#FF0000` Red never touches `#0000FF` Blue or `#FFFF00` Yellow and the painter cannot invent unaligned rings, bars, or bottom wings/chains).
  2. [`guides/layers/layer-2-frame-ai.png`](guides/layers/layer-2-frame-ai.png) — `Order 2` (`frame`): `#808080` Grey `22 px` outer bar armor frame.
  3. [`guides/layers/layer-3-lip-ai.png`](guides/layers/layer-3-lip-ai.png) — `Order 3` (`lip`): `#00FF00` Green `5 px` bevelled inner bar lip.
  4. [`guides/layers/layer-4-ring-ai.png`](guides/layers/layer-4-ring-ai.png) — `Order 4` (`ring`): `#FF8000` Orange `23 px` full 360° central portrait ring (`r = 105..128`).
  5. [`guides/layers/layer-5-crest-ai.png`](guides/layers/layer-5-crest-ai.png) — `Order 5` (`crest`, extended): `#FF8000` Orange `d = 74` top crest medallion (`512, 20`) + focused `#FF0000` Red upper horn/crown headroom (`x = 354..670, y = -70..81` layout px, strictly above the bars).
  6. [`guides/layers/layer-6-level-ai.png`](guides/layers/layer-6-level-ai.png) — `Order 6 [FRONT]` (`level`): `#FFFFFF` White `16 px` lower circular level ring (`r = 30..46`).

[`frame-template.json`](frame-template.json) holds the exact sizes and `drawableOrder` budgets. [`../Build-FrameTemplate.py`](../Build-FrameTemplate.py) generates `guides/frame-template-ai.png` and `guides/frame-template-extended-ai.png`, verifies that [`Layout.lua`](../../Layout.lua) matches, and with `--drawable` prints every drawable region in exact back-to-front drawing order (`1. Red #FF0000` → `2. Grey #808080` → `3. Green #00FF00` → `4. Orange #FF8000 ring` → `5. Orange #FF8000 top crest circle` → `6. White #FFFFFF level ring`, plus `OFF-LIMITS` `Magenta`/`Blue`/`Yellow` and Red-box headroom clearances — notably `106` image px above the top orange circle and `324 × 302` upper flanks above the bar, with `0` Red pixels below the bar):

```powershell
py -3 tools\Build-FrameTemplate.py --drawable
```

After painting, [`../Pack-FrameTemplate.py`](../Pack-FrameTemplate.py) validates that **zero out-of-bounds armor pixels** were painted into `#FF00FF` Magenta, `#0000FF` Blue, or `#FFFF00` Yellow (`--check-only` to pre-validate; in `--extended` mode, empty `#FF0000` Red ↔ `#FF00FF` Magenta transparent background-key seam jitter is accepted while every non-key painted pixel outside `x = 444..1603, y = 136..975` is strictly rejected — never hard-clip or warp/smoosh an over-extended painting to make it fit!), registers the AI output back onto the `2048 × 600` (`2048 × 840` extended) mask without radial ring smooshing, strips key fringes, builds the matching 2× `600 × 220` aura board strip, and writes `Media/frame-*.tga`. The frame does not draw that strip. Buffs and debuffs use a thin border in `Auras.lua`.

## Colours

| Colour | Hex | Paint? | What it is |
| --- | --- | --- | --- |
| Blue | `#0000FF` | No | Health (left), mana (right), and the portrait opening |
| Green | `#00FF00` | Yes | The 5 layout px lip around each bar |
| Grey | `#808080` | Yes | The outer frame, 22 layout px around that lip |
| Orange | `#FF8000` | Yes | The portrait ring, radius 105 to 128, including the lower band |
| White | `#FFFFFF` | Yes | The level ring. Its own border, 16 px thick, outer diameter 92 |
| Red *(extended)* | `#FF0000` | Optional | Background intricate-art rectangle (`222,-70` to `802,350` layout px) behind all sections on `frame-template-extended-ai.png`. Unfilled `#FF0000` Red keys out to transparent |
| Magenta | `#FF00FF` | No | Outside the frame. Do not add wings, horns, spikes, or glow here |
| Yellow | `#FFFF00` | No | The 60 px hole inside the level ring. The number sits here |

The level ring is a paint layer of its own, drawn on top of the portrait ring. White is that border. Yellow is the placeholder inside it, not paint. The centre is `512, 252`, the middle of the portrait ring at the bottom. The frame is `300` layout px tall so the ring fits, with `2 px` of margin under the rim.

Every variant (`plain`, `elite`, `rareelite`, `boss`, `class`) keeps this **exact single-box silhouette** — express theme differences (forged gold, silver, obsidian & molten fissures, runes, rivets, surface reliefs) **inside** the Grey, Green, Orange, and White regions rather than protruding into Magenta, Blue, or Yellow.

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
   # Standard gold elite plate + automatic silver rare-elite (silver elite) grading (QA --plate-out and --preview renders go in gitignored tools/template/preview/):
   py -3 tools\Pack-FrameTemplate.py --source tools\template\paintings\elite.png --plate-out tools\template\preview\elite-plate.png --preview tools\template\preview\elite-preview.png --out Media\frame-elite.tga --silver-out Media\frame-rareelite.tga

   # Dedicated boss plate:
   py -3 tools\Pack-FrameTemplate.py --source tools\template\paintings\boss.png --preview tools\template\preview\boss-preview.png --out Media\frame-boss.tga

   # Branched extended template plate (top orange crest circle + background #FF0000 Red intricate-art box):
   py -3 tools\Pack-FrameTemplate.py --extended --source tools\template\paintings\boss-extended.png --layer-dir tools\template\preview\boss-layers --plate-out tools\template\preview\boss-extended-plate.png --preview tools\template\preview\boss-extended-preview.png --out Media\frame-boss.tga

   # Preview-first modular per-section compositing (Order 1 -> 6) & focused single-section redraws:
   py -3 tools\Pack-FrameTemplate.py --extended --layer crest --source new-crest.jpg --check-only
   py -3 tools\Pack-FrameTemplate.py --extended --layer-backdrop tools\template\preview\boss-layers\layer-1-backdrop-plate.png --layer-frame tools\template\preview\boss-layers\layer-2-frame-plate.png --layer-lip tools\template\preview\boss-layers\layer-3-lip-plate.png --layer-ring tools\template\preview\boss-layers\layer-4-ring-plate.png --layer-crest new-crest.jpg --layer-level tools\template\preview\boss-layers\layer-6-level-plate.png --layer-dir tools\template\preview\boss-layers --preview tools\template\preview\boss-extended-preview.png
   ```
   - **Rounded or sculpted outer corners (optional):**
     - `--outer-radius <layout_px>` (e.g. `--outer-radius 8` or `12`, up to `28`): punches a mathematically identical signed-distance corner radius on all four outer corners of both the plate and the 9-slice aura board strip.
     - `--organic-edge`: lets AI-painted rounded, bevelled, or chipped outer silhouettes stay transparent via exterior-connected magenta chroma-keying while enforcing an airtight `7` layout px solid seal around the bar holes and rings (and preserving enclosed purple/violet gems inside the armor) so `StatusBar` widgets (`sideX = 5, sideY = 2`) and the board's recessed backing never poke out.
3. **What `Pack-FrameTemplate.py` does automatically:**
   - Accepts `.png`, `.jpg`/`.jpeg`, or `.tga`, detects the 3 blue holes and yellow level hole, fits global bar/centre scale (`sx`, `sy`) onto `2048 × 600` (warning if aspect drift exceeds `4%`), and radially preserves inner ring bevels (`map_mask_to_source`) so slightly thicker painted portrait/level collar rims stay 100% concentric instead of getting shaved off.
   - Identifies only true connected stencil-hole and border-connected exterior `#FF00FF` components (so enclosed purple, blue, or gold gem highlights inside the armor are never false-keyed), strips 2-pixel AI fringes plus 5-pixel JPEG `4:2:0` magenta/blue chroma-subsampling halos next to stencil keys, smoothly inpaints any key-covered plate pixels, despills residual boundary chroma within `4 px` of any edge (`despill_boundary_rgb`), and applies 1-pixel signed-distance anti-aliasing to every circular and rectangular boundary.
   - Slices the left and right `150` layout px (`300` image px) ends of the plate over a dark recessed billboard backing into the `600 × 220` board strip at `y = 608`, and optionally grades a cool forged-silver variant (`--silver-out`).
