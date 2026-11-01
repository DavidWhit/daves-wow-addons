---
name: daves-frames-paint
description: Paint, generate, restyle, or pack an AI target unit frame theme (plain, rare, elite/boss, rareelite, or class frame) for daves_frames using the zero-drift 16:9 UV stencil (guides/frame-template-ai.png), Gemini Nano Banana (image-generator), and Pack-FrameTemplate.py. Use whenever the user asks to paint, print, generate, restyle, or pack a new target frame look or texture atlas for daves_frames.
---

# Paint and pack a `daves_frames` target frame

Every unit variant in `wowaddons/daves_frames/` (`plain`, `rare`, `elite`, `rareelite`, `boss`, and the nine class frames) shares **one exact single-box geometry** (`1024 × 300` layout px; `2048 × 600` 2× canvas) packed into a `2048 × 1024` 32-bit `.tga` atlas (`Media/frame-*.tga`) with its matching 2× `600 × 220` 9-slice aura board strip at `y = 608`.

Full pixel coordinates live in `wowaddons/daves_frames/tools/template/PAINT-LAYERS.md` and `wowaddons/daves_frames/NOTES.md`.

| Stencil colour | Hex | Paint? | Region (`1024 × 300` layout px) |
| --- | --- | --- | --- |
| **Grey** | `#808080` | **Yes** | `22 px` outer bar armor frame (`8,81` to `1016,191`, interrupted by the central ring) |
| **Green** | `#00FF00` | **Yes** | `5 px` bevelled inner bar lip framing both bar openings out to the central ring |
| **Orange** | `#FF8000` | **Yes** | Central portrait ring (`centre 512,136`, radius `105` to `128`) |
| **White** | `#FFFFFF` | **Yes** | Lower circular level ring (`centre 512,252`, outer diameter `92`, `16 px` band on top of the portrait ring) |
| **Blue** | `#0000FF` | **No** | Left health opening (`35,108..379,164`), portrait opening (`r = 105`), right resource opening (`645,108..989,164`) |
| **Yellow** | `#FFFF00` | **No** | `60 px` hole inside the lower level ring (`r = 30`) where the level text sits |
| **Magenta** | `#FF00FF` | **No** | Exterior background outside the frame |

## Zero-drift rules (always)

1. **Always paint onto `guides/frame-template-ai.png` (`2048 × 1152`, exact `16:9`) and pass `AspectRatio="16:9"`.**
   Gemini Nano Banana (`image-generator` / `generate_image`) outputs wide renders natively at `16:9` (`1376 × 768`), never `21:9`. Passing a non-`16:9` stencil forces vertical resampling drift or clips the upper portrait crown. `frame-template-ai.png` pads the `2048 × 600` plate with `276` image px of `#FF00FF` magenta top and bottom so `16:9` renders stay `1:1` (`< 1 px` hole error, `~0.1–0.5%` aspect drift).
2. **Immutable single-box silhouette — zero external ornaments.**
   Never add external ornament boxes or let wings, horns, spikes, flames, smoke, or drop shadows protrude into `#FF00FF` Magenta, `#0000FF` Blue, or `#FFFF00` Yellow. External protrusions tempt the model to shrink the portrait ring and shift the bar holes. Express 100% of the theme **inside** the Grey, Green, Orange, and White armor bands.
3. **Save a lossless `.png` of every accepted painting** under `wowaddons/daves_frames/tools/template/paintings/<theme>.png` so plates can be re-packed or silver-graded later without re-generating.
4. **Never alter `Layout.lua` box dimensions** unless explicitly asked. Both `Build-FrameTemplate.py` and `Pack-FrameTemplate.py` assert that `Layout.lua` matches the `1024 × 300` standard.

## 1. Verify or rebuild the stencil guides

Run `Build-FrameTemplate.py` if `guides/frame-template-ai.png` is missing or if `Layout.lua` was touched (use `python` inside the Windows sandbox if `py -3` is unavailable):

```powershell
py -3 "wowaddons/daves_frames/tools/Build-FrameTemplate.py"
```

This writes `guides/frame-template-ai.png` (`2048 × 1152`, `16:9`) and `frame-template.json`, and checks `Layout.lua`.

## 2. Plan each section's pixel budget, then paint on `frame-template-ai.png`

Before writing the image prompt, **budget the actual drawable thickness of each stencil band** so motifs, crests, and gems are proportioned to fit comfortably *inside* their band without touching or clipping against inner/outer rims:

| Section | Total band | Recommended rim margin | Net interior channel | Motif sizing rule |
| --- | --- | --- | --- | --- |
| **Grey (`#808080`) outer bar frame** | `22` layout px | `~2.5–3 px` outer rail | **`~16–17` layout px** tall × `~350 px` long | Long horizontal running motifs (vines, filigree, chains, chevrons); corner gems `<= 10–12 px` set flush inside the `22×22` corners (zero corner flange/step-out) |
| **Green (`#00FF00`) inner bar lip** | `5` layout px | — | **`5` layout px** bevel | Clean gleaming metallic bevel only — too thin for busy ornament |
| **Orange (`#FF8000`) portrait ring** | `23` layout px | `~3 px` outer + `~3 px` inner unbroken concentric rims | **`~17` layout px** circular channel | **12, 3, and 9 o'clock crests/moons/gems MUST be `<= 12–14` layout px (`~55%` of total ring width)** so dark backing + unbroken inner/outer rims stay clearly visible above and below |
| **White (`#FFFFFF`) level ring** | `16` layout px | `~2.5 px` outer + `~2.5 px` inner rims | **`~11` layout px** circular channel | Simple slender single-strand motif, ticks, or clean engraving |

Invoke the `image-generator` subagent (or an external Nano Banana / Imagine `16:9` image-edit pass) with:
- **Reference image (`ImagePaths`):** absolute path to `wowaddons/daves_frames/tools/template/guides/frame-template-ai.png`
- **Aspect ratio:** `AspectRatio="16:9"`
- **Prompt template:**

```text
Edit guides/frame-template-ai.png (2048x1152, AspectRatio="16:9") as an immutable pixel-locked UV stencil for a World of Warcraft <theme> target unit frame:
1. Do NOT move, resize, shrink, thicken, or shift the circular rings or rectangular bars by even 1 pixel.
2. Do NOT add wings, horns, spikes, flames, smoke, or drop shadows outside the frame — keep 100% of the #FF00FF Magenta exterior, all three #0000FF Blue openings (left bar, center portrait circle, right bar), and the #FFFF00 Yellow level circle completely flat, solid, and unshaded with razor-sharp boundaries.
3. Paint 100% of the <theme> character strictly INSIDE the 4 paintable armor regions:
   - Grey (#808080) 22px outer bar frame: <heavy armor material, surface reliefs, runes/cracks/rivets>, keeping the outer rectangular border razor-straight.
   - Green (#00FF00) 5px inner bar lip: <gleaming bevelled inner metallic rim> framing both blue bar windows and meeting the central ring cleanly.
   - Orange (#FF8000) central portrait ring: <forged collar bezel, inlays/runes, top-down Warcraft UI lighting> strictly inside the orange circular band.
   - White (#FFFFFF) lower circular level ring: <matching signet bezel> sitting cleanly on top of the lower portrait ring around the flat #FFFF00 yellow hole.
```

Inspect the generated candidate(s) with `read_file` before packing. Confirm all three `#0000FF` blue holes, the `#FFFF00` yellow level hole, and the `#FF00FF` magenta exterior are completely clean and unoccluded, then save the chosen painting as a lossless PNG at `wowaddons/daves_frames/tools/template/paintings/<theme>.png` (`Pack-FrameTemplate.py`'s `read_image` + `write_png` can convert `.jpg` to `.png` directly).

## 3. Register, key, and pack into `Media/*.tga`

Run `Pack-FrameTemplate.py`:

```powershell
# Example: boss / elite plate + matching forged-silver rareelite atlas
# (QA --preview and --plate-out renders go to gitignored tools/template/preview/)
py -3 "wowaddons/daves_frames/tools/Pack-FrameTemplate.py" `
  --source "wowaddons/daves_frames/tools/template/paintings/<theme>.png" `
  --plate-out "wowaddons/daves_frames/tools/template/preview/<theme>-plate.png" `
  --preview "wowaddons/daves_frames/tools/template/preview/<theme>-preview.png" `
  --out "wowaddons/daves_frames/Media/frame-elite.tga" `
  --silver-out "wowaddons/daves_frames/Media/frame-rareelite.tga"
```

| Flag | Purpose |
| --- | --- |
| `--source <path>` | Input AI painting (`.png`, `.jpg`/`.jpeg`, or `.tga`) or pre-aligned `2048 × 600` RGBA plate |
| `--out <path.tga>` | Primary `2048 × 1024` 32-bit uncompressed top-down `.tga` (`frame-plain.tga`, `frame-elite.tga`, etc.) |
| `--also <path.tga>` | Copy primary `.tga` to additional variant path(s) (repeatable) |
| `--silver-out <path.tga>` | Grade a matching cool forged-silver `2048 × 1024` `.tga` (`frame-rare.tga` or `frame-rareelite.tga`) |
| `--silver-also <path.tga>` | Copy silver `.tga` to additional path(s) (repeatable) |
| `--plate-out <path.png>` | Save the keyed, despilled `2048 × 600` transparent RGBA plate PNG |
| `--preview <path.png>` | Save a `2048 × 600` composite preview PNG over stand-in health/mana bars, portrait, and level circle |
| `--outer-radius <0..28>` | Optional exact signed-distance outer corner radius in layout px (applied identically to plate and 9-slice aura board) |
| `--organic-edge` | Optional chroma-keyed outer contour mode for chipped/bevelled outer corners while keeping the inner `7 px` bar/ring seal airtight |

Built-in `Layout.lua` variants:
- `Media/frame-plain.tga` (`plain`: ordinary NPCs, and players whose class token is secret)
- `Media/frame-rare.tga` (`rare`: normal rares, typically `--silver-out` of `plain`)
- `Media/frame-elite.tga` (`elite`: gold elites)
- `Media/frame-rareelite.tga` (`rareelite`: silver rare-elites, typically `--silver-out` of `elite`)
- `Media/frame-boss.tga` (`boss`: bosses and world bosses via `UnitIsBossMob` or `"worldboss"`)
- `Media/frame-<class>.tga` (`warrior`, `paladin`, `hunter`, `rogue`, `priest`, `shaman`, `mage`, `warlock`, `druid`: players when `UnitClass` returns a non-secret token)

If adding a brand-new art key beyond the built-in variants above, wire it into `Layout.lua` (`VARIANTS`), `Core.lua` (`/davesframes art`), and `daves_frames/README.md` + `NOTES.md`.

## 4. Check the result

- **Registration fit:** Check the `registered ... -> 2048x600:` line printed by `Pack-FrameTemplate.py`:
  - Good `16:9` single-box renders hit `max_err <= 2.0 px` (typically `< 1.5 px`) and `aspect_drift < 2.0%` (typically `0.1%–0.5%`).
  - If `Pack-FrameTemplate.py` prints `WARNING: high geometry drift detected` (`max_err > 6 px` or `aspect_drift > 4%`), do **not** ship the texture — re-run Step 2 with stricter stencil adherence on `guides/frame-template-ai.png`.
- **Visual inspection:** View the `--preview` PNG with `read_file` (and optionally convert the `.tga` atlas via `wowaddons/daves_frames/tools/Preview-Tga.ps1` to inspect the `600 × 220` 9-slice aura board strip packed at `y = 608`; note that live aura boards use `Auras.lua` `ThinBoard` rather than drawing the strip). Verify:
  - Crisp outer edges with zero `#FF00FF` magenta or `#0000FF` blue halo;
  - Complete, symmetrical `5 px` inner bar lips on both left and right bar openings;
  - Concentric portrait ring (including the upper crown) and lower circular level ring;
  - Clean `600 × 220` aura board strip with seamless center seam and dark recessed interior.
- **Validation:**
  - Texture-only updates: run `py -3 "wow-addon-kit/plugins/wow-forever-addons/scripts/Test-WowAddon.py" -Path "wowaddons/daves_frames" -NoInfo`.
  - Any `.lua`, `.toc`, or `tools/*.py` change: run the full **`wow-addon-test`** skill (`Prepare-WowReview.py -Path "wowaddons/daves_frames"` + advisor review) and update `NOTES.md` / `README.md`.

## 5. Tell the user

- Report the saved source painting (`tools/template/paintings/<theme>.png`), the packed `Media/frame-*.tga` files, and the registration metrics (`max_err` and `aspect_drift`).
- Remind the user that **new or updated `.tga` files require a full WoW client restart** (not `/reload`).
- In game, preview any variant immediately on yourself without hunting for a mob or rerolling a class:
  ```text
  /davesframes test
  /davesframes art warrior
  /davesframes art elite
  /davesframes art auto
  ```
