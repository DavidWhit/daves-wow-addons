---
name: daves-frames-paint-extended
description: Branched extended workflow to paint, generate, restyle, or pack an AI target unit frame theme for daves_frames using the extended 16:9 UV stencil (guides/frame-template-extended-ai.png) or modular per-section 16:9 layer stencils (guides/layers/layer-1..6-*-ai.png) with separate section previews, focused single-section redraws, and Order 1->6 layered compositing via Pack-FrameTemplate.py --extended.
---

# Paint and pack an extended `daves_frames` target frame (Branched Workflow)

This is the **branched extended workflow** for `wowaddons/daves_frames/` using [`guides/frame-template-extended-ai.png`](../../../wowaddons/daves_frames/tools/template/guides/frame-template-extended-ai.png) and its 6 modular per-section `16:9` layer stencils under [`guides/layers/`](../../../wowaddons/daves_frames/tools/template/guides/layers/) (`2048 × 1152`, exact `16:9`). (For the standard single-box workflow without crown/backdrop extensions, see `daves-frames-paint`.)

Every existing section from `frame-template-ai.png` keeps its **exact size and position** (`1024 × 300` layout px; `2048 × 600` 2× base canvas), and two new paintable regions are added:

| Stencil colour | Hex | Paint? | Region (`1024 × 300` layout px origin) |
| --- | --- | --- | --- |
| **Grey** | `#808080` | **Yes (solid)** | `22 px` outer bar armor frame (`8,81` to `1016,191`, interrupted by the central ring) |
| **Green** | `#00FF00` | **Yes (solid)** | `5 px` bevelled inner bar lip framing both bar openings out to the central ring |
| **Orange (ring)** | `#FF8000` | **Yes (solid)** | Central portrait ring (`centre 512,136`, radius `105` to `128`) |
| **Orange (top crest circle)** | `#FF8000` | **Yes** | Top circular crest medallion (`centre 512,20`, radius `37` / diameter `74` = `4/5` of the `92 px` bottom level ring; `y = -17..57` layout px) blending into the portrait ring and overlaying the top of the portrait opening (`y = 31..57`) |
| **White** | `#FFFFFF` | **Yes (solid)** | Lower circular level ring (`centre 512,252`, outer diameter `92`, `16 px` band on top of the portrait ring) |
| **Red (upper background box)** | `#FF0000` | **Optional (unfilled = transparent)** | Upper background intricate-artwork rectangle (`x = 222..802, y = -70..81` layout px; `580 × 151` layout px / `1160 × 302` image px, strictly **above** the horizontal bar `y = 81` and **outside** the `r = 128` portrait ring & `r_top = 37` crest disc) **behind everything**. Reserved for upper wings, filigree, chains, spikes, or halo. Painter does **not** need to fill the entire Red box — any unfilled `#FF0000` Red keys out to **transparent** |
| **Blue** | `#0000FF` | **No (off-limits)** | Left health opening (`35,108..379,164`), portrait opening (`r = 105` outside the top orange circle and bottom level ring), right resource opening (`645,108..989,164`) |
| **Yellow** | `#FFFF00` | **No (off-limits)** | `60 px` hole inside the lower level ring (`r = 30`) where the level text sits |
| **Magenta** | `#FF00FF` | **No (off-limits)** | Exterior background outside the frame and outside the Red box (including the entire lower half below the horizontal bars) |

## Rules for the Branched Extended Workflow

1. **Always paint onto `guides/frame-template-extended-ai.png` (`2048 × 1152`, exact `16:9`) and pass `AspectRatio="16:9"`.**
2. **Never resize or shift any existing section.** The health/resource blue bar holes, green `5 px` lip, grey `22 px` outer bar frame, central portrait ring (`r = 105..128`), and bottom white/yellow level ring (`centre 512,252`, outer `92`, hole `60`) must remain pixel-locked.
3. **Blue (`#0000FF`), Yellow (`#FFFF00`), and exterior Magenta (`#FF00FF`) are strictly off-limits.** Never let wings, claws, glow, or drop shadows cross over the blue bar windows, the blue portrait opening (below the top orange crest circle), the yellow level hole, or the magenta exterior. Extended artwork passes **behind** the solid Grey/Green bars, never in front of the `#0000FF` Blue bar openings.
4. **Top Orange Circle (`#FF8000`, `centre 512,20`, `d = 74` layout px / `148` image px):**
   - Blends seamlessly into the `#FF8000` portrait ring while overlaying both the portrait ring (`y = 8..31`) and the top of the portrait opening (`y = 31..57`) and extending above the crown (`y = -17..8`).
   - Use for a prominent connected class/boss/elite crest, dragon head, medallion, helm crown, skull, or signet — never float disconnected crowns or icons detached in the red space above the crest.
5. **Upper Background Red Box (`#FF0000`, `x = 222..802, y = -70..81` layout px / `x = 444..1604, y = 136..438` image px):**
   - Sits behind all other sections, strictly **above** the horizontal bars (`y_img < 438`) and **outside** the `Order 4` portrait ring (`r > 256` img px) and `Order 5` top crest circle (`r_top > 74` img px).
   - **Why `Order 2, 4, 5, 6` and the lower half are `#FF00FF` Magenta on `layer-1-backdrop-ai.png`:** Previously, when `layer-1-backdrop-ai.png` filled the portrait ring (`r = 210..256`), horizontal bars (`y = 438..657`), and lower half (`y = 658..976`) with `#FF0000` Red right up against the naked `#0000FF` Blue holes, the diffusion painter had no visual landmark for the portrait collar or bar top and went rogue inventing its own unaligned rings, bar rails, and bottom wings/chains. Carving `#FF00FF` Magenta around the exact outer silhouette of the portrait ring (`r = 256`), top crest (`r_top = 74`), and horizontal bar top (`y = 438`) ensures `#FF0000` Red **never touches `#0000FF` Blue or `#FFFF00` Yellow**, gives the painter the exact curved ring arch and flat bar top where the upper wings/chains attach, and blocks any bottom wings/chains below the bars (leaving clean space for `daves_frames`'s dynamic swinging aura boards at `pivotY = 189`).
   - **Stay `15–20 px` inside the outer top/left/right edges of the `#FF0000` Red box:** Anything crossing outside `x = 444..1603, y = 136..437` into `#FF00FF` Magenta is rejected by `validate_painting_bounds`.
   - **Leave any unused portion of the Red box flat, solid `#FF0000` Red** with crisp metallic silhouettes and zero smoke, vignette, or drop shadows — `Pack-FrameTemplate.py --extended` automatically keys unfilled `#FF0000` Red to **transparent** (`alpha = 0`) and tucks `Order 1` `4 px` underneath `Order 2`, `Order 4`, and `Order 5` so every attachment seam is `100%` opaque (`alpha = 255`).

## 1. Check Drawable Pixels in Layer Order BEFORE Painting (Mandatory)

Always run `Build-FrameTemplate.py --drawable` **before** designing motifs or writing the painter prompt:

```powershell
py -3 "wowaddons/daves_frames/tools/Build-FrameTemplate.py" --drawable
```

This rebuilds/verifies `guides/frame-template-extended-ai.png` and all 6 modular per-section `2048 × 1152` (`16:9`) stencils under `guides/layers/`, and prints every region **in exact back-to-front drawing order** with pixel counts and safe clearance budgets:

| Layer Order (Back → Front) | Per-Section 16:9 Stencil (`guides/layers/`) | Stencil Colour | Drawable Pixels (`2048 × 1152` img px) | Safe Motif Budget & Hard Boundary Rule |
| --- | --- | --- | --- | --- |
| **Order 1 [BACK]** (`backdrop`) | `layer-1-backdrop-ai.png` | **Red (`#FF0000`)** | `296,344 px` (`x = 444..1603, y = 136..437`; `1160 × 302` img px / `580 × 151` layout px outside `r = 256` & `r_top = 74`) | Drawn **behind everything**; unfilled `#FF0000` keys to transparent (`4 px` automatic under-tuck beneath `Order 2/4/5`). Keep outer Red borders (`x = 444..1603, y = 136`) untouched against `#FF00FF` Magenta (`>= 20` img px / `10` layout px inward margin):<br>• **Top-center above Top Orange Circle (`y = 136..241`):** only `106` img px (`53` layout px) total → **`<= 86` img px (`<= 43` layout px) safe height** (leave clear `#FF0000` Red here when painting `Order 5 crest` separately!).<br>• **Upper flanks L/R of ring above bar (`x = 444..767` & `1280..1603, y = 136..437`):** `324 × 302` img px → **`<= 304 × 282` img px (`152 × 141` layout px) per side**.<br>• **Lower half below bar (`y >= 438`):** `0 px` (`#FF00FF` Magenta OFF-LIMITS — no bottom wings or bottom chains). |
| **Order 2** (`frame`) | `layer-2-frame-ai.png` | **Grey (`#808080`)** | `146,784 px` (`x = 16..2031, y = 438..657`; `44` img px / `22` layout px band) | Solid outer bar armor **in front of Red**. Outer corner caps at bar ends MUST stay flush inside `y = 438..657` (`0` vertical flange/step-out into `#FF00FF` Magenta). |
| **Order 3** (`lip`) | `layer-3-lip-ai.png` | **Green (`#00FF00`)** | `33,536 px` (`x = 60..1987, y = 482..613`; `10` img px / `5` layout px bevel) | Solid bevelled inner bar lip **in front of Grey**, framing the off-limits `#0000FF` Blue bar windows. |
| **Order 4** (`ring`) | `layer-4-ring-ai.png` | **Orange (`#FF8000` ring)** | `centre 1024,548`, `r = 210..256` img px (`46` img px / `23` layout px band) | Solid central portrait collar **in front of bars & Red** (full 360° circular band around the portrait). Never thicken inward or let claws cross inside `r = 210` (`#0000FF` Blue portrait circle). |
| **Order 5** (`crest`) | `layer-5-crest-ai.png` | **Orange (`#FF8000` top disc) + focused Red (`#FF0000`)** | Disc `centre 1024,316`, `r = 74` img px (`x = 950..1098, y = 242..390`) + focused Red horn/crown headroom (`x = 708..1340, y = 136..438`) | Connected top crest medallion + horns/crown blending over Order 4 and overlaying the top `52` img px (`y = 338..390`) of the portrait circle. Any chin/fang/star point inside the portrait circle MUST end at `y <= 390` (`r <= 74`) — never hang down into `#0000FF` Blue! |
| **Order 6 [FRONT]** (`level`) | `layer-6-level-ai.png` | **White (`#FFFFFF`)** | `15,360 px` (`centre 1024,780`, `r = 60..92` img px; `32` img px / `16` layout px band) | Frontmost lower level-badge bezel stamped **on top of** Order 4 around the off-limits `#FFFF00` Yellow hole (`r <= 60`). |
| **OFF-LIMITS** | *(preserved on every stencil)* | **Magenta / Blue / Yellow** | `#FF00FF`, `#0000FF`, `#FFFF00` | **`0` painted pixels allowed.** Preserved on every per-section guide so `fit_source_transform` registers every isolated section render to `< 1 px` identically. |

### Zero-Smoosh & Zero-Clip Rule (Never Warp or Amputate Over-Extended Art!)

- **Never warp, compress, tuck, radially remap, or hard-clip an over-extended painting to cram it inside `#FF0000` Red or outside `#0000FF` Blue / `#FFFF00` Yellow!** Post-hoc compression smooshes proportions, and post-hoc mask stamping slices flat amputated horn/blade tips.
- `Pack-FrameTemplate.py` enforces strict drawable-pixel boundary validation (`validate_painting_bounds`) across every off-limits zone (`Magenta TOP`, `Magenta BOTTOM`, `Magenta LEFT/RIGHT flanks & bar corners`, `Blue bar windows`, `Blue portrait circle`, `Yellow level hole`) and **fails fast** if any non-key armor/metal/shadow pixel steps outside the drawable stencil pixels.
  - In `--extended` mode, empty `#FF0000` Red (`alpha = 0`) ↔ `#FF00FF` Magenta (`alpha = 0`) background-key border jitter (`8×8` VAE / JPEG `4:2:0` seam shift with zero armor pixels) is recognized as transparent background so painters are not penalized for empty chroma-key drift, while **every painted non-key pixel** outside `x = 444..1603, y = 136..975` is strictly rejected.
- If a candidate fails `--check-only`, **reject it and repaint** with tighter motif sizing for the specific overflowing zone — only save a `1:1` unwarped PNG (`--save-png`).

## 2. Preview-First Modular Per-Section Workflow (Separate Section Previews & Focused Redraws)

**Whenever the skill is asked to preview items first (or iterate on sections without regenerating the entire frame), keep each painted section separate and composite them as layers in guide order (`Order 1 → Order 6`):**

1. **Paint or extract each section on its own `16:9` stencil (`wowaddons/daves_frames/tools/template/guides/layers/`):**
   - `Order 1 [BACK]` (`backdrop`): `guides/layers/layer-1-backdrop-ai.png` — `#FF0000` Red intricate-art backdrop (`x = 444..1603, y = 136..975` img px; leave the upper-center crest zone clear `#FF0000` Red so `Order 5` owns the top crest & horns).
   - `Order 2` (`frame`): `guides/layers/layer-2-frame-ai.png` — `#808080` Grey `22 px` (`44` img px) outer bar armor frame.
   - `Order 3` (`lip`): `guides/layers/layer-3-lip-ai.png` — `#00FF00` Green `5 px` (`10` img px) bevelled inner bar lip.
   - `Order 4` (`ring`): `guides/layers/layer-4-ring-ai.png` — `#FF8000` Orange `23 px` (`46` img px) full 360° central portrait ring.
   - `Order 5` (`crest`): `guides/layers/layer-5-crest-ai.png` — `#FF8000` Orange `d = 74` (`148` img px) top crest medallion + focused `#FF0000` Red upper horn/crown headroom (`x = 708..1340, y = 136..438` img px, strictly above the bars).
   - `Order 6 [FRONT]` (`level`): `guides/layers/layer-6-level-ai.png` — `#FFFFFF` White `16 px` (`32` img px) lower circular level ring.
   - *Reusing unchanged sections from an existing plate/TGA:* Pass `--base-layers "wowaddons/daves_frames/Media/frame-<variant>.tga"` (or a prior painting/plate) to supply unchanged sections (`frame`, `lip`, `ring`, `level`) automatically while painting only the new or modified `--layer-*` sections!
2. **Validate each painted section independently (`--layer <section> --check-only`):**
   ```powershell
   py -3 "wowaddons/daves_frames/tools/Pack-FrameTemplate.py" `
     --layer crest `
     --source "<crest-candidate.jpg>" `
     --check-only
   ```
3. **Emit separate per-section previews (`--layer-dir`) AND apply them as layers (`Order 1 → 6`):**
   ```powershell
   py -3 "wowaddons/daves_frames/tools/Pack-FrameTemplate.py" `
     --extended `
     --layer-backdrop "<backdrop.png>" `
     --layer-frame "<frame.png>" `
     --layer-lip "<lip.png>" `
     --layer-ring "<ring.png>" `
     --layer-crest "<crest.png>" `
     --layer-level "<level.png>" `
     --layer-dir "wowaddons/daves_frames/tools/template/preview/<theme>-layers" `
     --plate-out "wowaddons/daves_frames/tools/template/preview/<theme>-extended-plate.png" `
     --preview "wowaddons/daves_frames/tools/template/preview/<theme>-extended-preview.png"
   ```
   - `--layer-dir` writes `layer-1-backdrop-preview.png` .. `layer-6-level-preview.png` (and matching `-plate.png` RGBA layers + `1:1` `-painting.png` sources) so the user can inspect each painted section separately alongside the layered composite `--preview` (and do **not** pass `--out Media/frame-*.tga` during preview-first runs until the user approves!).
   - You can also split an existing monolithic painting into all 6 separate section plates & previews via `--extended --source "<painting.png>" --layer-dir "wowaddons/daves_frames/tools/template/preview/<theme>-layers"`.
4. **Focused Single-Section Redraws (never regenerate untouched sections!):**
   - When the user asks to tweak or redraw one section (e.g., *"redraw just the boss crest"*, *"drop the bottom claws in the backdrop"*, *"change the outer bar frame"*), repaint **only** that single `guides/layers/layer-<N>-<section>-ai.png` stencil (or edit that section's `-painting.png`), validate with `--layer <section> --check-only`, and re-run `Pack-FrameTemplate.py --extended` passing the new file to `--layer-<section>` alongside the existing saved `layer-*-plate.png` files for the other 5 sections!
   - `Pack-FrameTemplate.py` composites all sections in strict back-to-front guide order (`Order 1 backdrop → 2 frame → 3 lip → 4 ring → 5 crest → 6 level`) with automatic `2 px` solid under-tuck beneath higher-order solid/opaque layers so every shared seam stays `100%` opaque (`alpha = 255`).

## 3. Stencil-Painter Diffusion Rules & Monolithic Option

### Stencil-Painter Diffusion Rules & Continuous Feedback Loop

1. **Always pass the stencil PNG (`guides/layers/layer-<N>-<section>-ai.png` or `guides/frame-template-extended-ai.png`) in `ImagePaths` with `AspectRatio="16:9"` on every call** (including retries). Generating without `ImagePaths` causes `3%–13%` aspect drift (`max_err > 10 px`).
2. **Use Visual Landmarks & Negative-Space Ratios Instead of Raw Pixel Offsets:**
   - Diffusion spatial attention ignores raw pixel numbers like *"stay 25 px from `y = 136`"*. Anchor boundaries to visible stencil landmarks:
     - **Horizontal span:** State that the `#FF0000` Red box covers **only the inner 1/3 of each horizontal bar** (the **outer 2/3 of both bars protrude completely bare into `#FF00FF` Magenta**). Use **one compact C-coil, wing-arch, crescent blade, or single short chain swag per quadrant hugging the central portrait ring** (zero secondary outer chain swags along the bare Magenta bar ends) rather than wide multi-loop serpent coils spanning the bars.
     - **Top & bottom negative-space ribbons:** Require a **wide, continuous, uninterrupted pure `#FF0000` Red ribbon** visible across the entire top edge and entire bottom edge of the Red box.
     - **Complete stencil coverage:** Explicitly require **zero leftover neon `#00FF00` Green, `#FF8000` Orange, or `#FFFFFF` White stencil pixels** on the painted metal.
3. **Use Outward-Horizontal / Recessed Crest Anatomy in the Tight `106 px` Top Ceiling (Especially on `layer-5-crest-ai.png`):**
   - Prompts mentioning *"tall dragon horns"*, *"upward wyrm horns"*, or *"star crown"* trigger upward vertical priors that breach `y = 136`, while oversized full-loop ram horns can curl down across the portrait collar into the `#0000FF` Blue portrait circle. Prompt explicitly for **compact outward-swept horizontal `S`-horns staying above the portrait collar**, **cheek-swept fins**, or **recessed brow gems/stars embedded inside the forehead** (*"highest point strictly at or below the flanking upper coils/blades, and horn tips staying outside/above the portrait collar"*), and keep total head/skull vertical height `<= 220` guide px (`y = 165..385`) so jaws/teeth terminate strictly inside `y <= 390` (note: inside `top_pa` where `r_ring < 210` at `y = 338..390`, `#0000FF` Blue on the left/right of a narrow snout or jaw natively keys to transparent).
   - When painting `guides/layers/layer-5-crest-ai.png` in isolation (where the `Order 4` portrait collar is omitted), explicitly state that the `#FF8000` Orange disc **only indents the top ~12% of the `#0000FF` Blue circle** so the entire face/jaw sits like a compact hood ornament **inside the Orange disc (`0` exposed neon orange at top, bottom ~88% of the Blue circle left 100% flat `#0000FF` Blue)**; if `Order 4` is already painted, compositing its upper collar arch (`r = 210..256` inside `CREST_RED`) onto a scratch `layer-5-crest` guide gives the painter an exact collar-crown landmark (`extract_single_layer("crest", ...)` isolates the connected crest + exterior horns and smoothly feathers collar shoulders beyond `TOP_BR + 10..22`).
   - When painting core horizontal bar armor (`Orders 2, 3, 4, 6`) onto `guides/frame-template-ai.png` to pair with `--layer-backdrop` and `--layer-crest`, pass `[guides/frame-template-ai.png, preview/plain-painting.png]` so the painter locks onto the exact `44 px` slender `#808080` Grey bar height without adding duplicate outer gold rails into `#FF00FF` Magenta.
   - When re-texturing an existing `Order 1` backdrop silhouette in-place (e.g., upgrading wing membranes to chiseled dragon scales & baroque filigree), never pass a second full `16:9` stencil image that contains wider wings (cross-attention will copy the wider wing span); instead pass a **tightly cropped square/rectangular texture swatch** as Image 2 (or embed the target texture in the top half of a single image).
4. **Refining Overflowing Extremities Without Flat Guillotine Cuts or Outward Extrapolation:**
   - **Never leave a flat horizontal Python cut across a motif inside `#FF0000` Red** — the diffusion model will faithfully preserve any flat-sliced clasp, blade, or horn edge left sitting in the Red field, and slicing within `5–25 px` of `y = 136` or `y = 975` causes diffusion priors to extrapolate `+20–40 px` *outward* across the border.
   - Instead, pass `[<layer-or-extended-guide.png>, <candidate>]` to a **fresh clean-context subagent** and instruct it to **arc/curl the complete, uncut 3D points tighter inward/upward** inside Image 1's exact `#FF0000` Red box (leaving a wide uninterrupted `#FF0000` Red ribbon beyond the uncut tips). If pre-clearing an overflowing horn/limb on a guide PNG, erase cleanly all the way back to its natural anatomical joint/brow (removing any detached floating curl fragments and normalizing all background red pixels to uniform pure `#FF0000` `(255, 0, 0)`) — never slice halfway through an intact clasp, shield, or level ring!
5. **Standing Stencil-Painter Feedback Loop:**
   - Ask `image-generator` stencil painters to include 1–2 sentences of candid feedback whenever recurring stencil or diffusion friction slows them down or causes retries. Fold warranted, rule-compliant improvements into this skill and tooling (while always rejecting any suggestion to hard-clip or post-hoc warp artwork).

For a single-pass monolithic paint onto `guides/frame-template-extended-ai.png` (`ImagePaths`, `AspectRatio="16:9"`):

```text
Edit guides/frame-template-extended-ai.png (2048x1152, pass in ImagePaths with AspectRatio="16:9") as an immutable pixel-locked UV stencil for a World of Warcraft <theme> target unit frame. Respect every pixel boundary and paint strictly inside the drawable colours in back-to-front layer order:

1. STRICT OFF-LIMITS REGIONS (0 painted armor pixels allowed — do NOT move, shrink, or paint over):
   - #FF00FF Magenta exterior: keep 100% of the outer Magenta margin untouched on all 4 sides (do NOT widen or tallen the #FF0000 Red box; the Red box covers ONLY the inner 1/3 of each horizontal bar while the outer 2/3 of both bars protrude completely bare into #FF00FF Magenta).
   - #0000FF Blue openings: keep both horizontal bar windows and the central Blue portrait circle (r <= 210 image px below the top orange disc) 100% flat, solid #0000FF Blue — zero claws, ring thickening, or jaws crossing inside the Blue circle!
   - #FFFF00 Yellow level hole: keep the 120px central Yellow disc inside the bottom White ring 100% flat #FFFF00 Yellow.

2. PAINTABLE LAYERS IN BACK-TO-FRONT ORDER (leave zero neon #00FF00 Green, #FF8000 Orange, or #FFFFFF White stencil pixels unpainted):
   - Order 1 [BACK] Red (#FF0000) background art box (1160x840 px behind everything; unfilled #FF0000 stays flat uniform #FF0000 so it keys to transparent):
     * Paint compact upper-flank ornament (324x302 px left and right above the horizontal bars) hugging the central portrait ring inside the inner 1/3 bar span, passing BEHIND the solid bars (never over Blue windows), and leave the lower #FF0000 Red region below the bars flat #FF0000 Red (transparent, no bottom wings or chains) unless explicitly requested.
     * TOP NEGATIVE-SPACE RIBBON: Direct top-center above the top orange disc has ONLY 106 px of Red height — sculpt compact outward-swept horizontal horns, cheek-swept fins, or a recessed brow emblem whose highest point stays level with or below the flanking upper arches, leaving a wide uninterrupted #FF0000 Red ribbon across the entire top edge!
   - Order 2 Grey (#808080) 44px outer bar frame (in front of Red): full-width <heavy armor material, reliefs, rivets>, keeping the top, bottom, and outer bar-end corners razor-straight and flush inside the Grey band (zero corner flange/step-out above or below the bar into Magenta!).
   - Order 3 Green (#00FF00) 10px inner bar lip (in front of Grey): <gleaming bevelled inner metallic rim> completely covering every #00FF00 Green pixel around both Blue bar windows.
   - Order 4 Orange (#FF8000) 46px central portrait ring (in front of bars & Red): <forged collar bezel> strictly within the Orange circular band (do NOT encroach inward into the Blue portrait circle).
   - Order 5 Orange (#FF8000) 148px top circular crest disc: <connected 3D <theme> crest/bust> sculpted directly over the top Orange disc and blending seamlessly into the portrait ring; its bottom edge (chin/fangs/bevel) MUST terminate inside the top Orange disc (never hang down into the Blue portrait circle), with no disconnected floating icons above it.
   - Order 6 [FRONT] White (#FFFFFF) 32px lower circular level ring: <matching signet bezel> completely covering the White band around the untouched #FFFF00 Yellow hole.

3. Return the saved image path, and note in 1-2 sentences if any stencil/diffusion boundary friction arose so we can keep improving the skill within our zero-clip/zero-smoosh rules.
```

Validate every generated candidate immediately before saving or packing (`--layer <section>` for per-section renders, or `--extended` for monolithic):

```powershell
py -3 "wowaddons/daves_frames/tools/Pack-FrameTemplate.py" `
  --extended `
  --source "<candidate.jpg>" `
  --check-only
```

Inspect with `read_file` as well. If `--check-only` reports out-of-bounds pixels in any zone, **do not warp or smoosh the image** — message the painter with the exact overflowing zone so it tucks that motif natively inside the stencil.

## 4. Pack Approved Layers or Plate into `Media/*.tga`

Once the user approves the previewed sections, pack from the separate `layer-*-plate.png` layers (or monolithic `--source`):

```powershell
# Pack from approved separate section layers (Order 1 -> 6):
py -3 "wowaddons/daves_frames/tools/Pack-FrameTemplate.py" `
  --extended `
  --layer-backdrop "wowaddons/daves_frames/tools/template/preview/<theme>-layers/layer-1-backdrop-plate.png" `
  --layer-frame "wowaddons/daves_frames/tools/template/preview/<theme>-layers/layer-2-frame-plate.png" `
  --layer-lip "wowaddons/daves_frames/tools/template/preview/<theme>-layers/layer-3-lip-plate.png" `
  --layer-ring "wowaddons/daves_frames/tools/template/preview/<theme>-layers/layer-4-ring-plate.png" `
  --layer-crest "wowaddons/daves_frames/tools/template/preview/<theme>-layers/layer-5-crest-plate.png" `
  --layer-level "wowaddons/daves_frames/tools/template/preview/<theme>-layers/layer-6-level-plate.png" `
  --plate-out "wowaddons/daves_frames/tools/template/preview/<theme>-extended-plate.png" `
  --preview "wowaddons/daves_frames/tools/template/preview/<theme>-extended-preview.png" `
  --out "wowaddons/daves_frames/Media/frame-<variant>.tga"
```

What `--extended` does:
- Composites (or extracts) the full `2048 × 840` extended plate (`y_layout = -70..350`) in back-to-front guide order (`Order 1 → 6`), keeping the solid armor bands + top orange crest circle + painted intricate artwork inside the Red rectangle while keying unfilled `#FF0000` Red, `#FF00FF` Magenta, `#0000FF` Blue, and `#FFFF00` Yellow to transparent.
- Writes `2048 × 840` `--plate-out`, `--preview`, and optional `--layer-dir` per-section PNGs so you can inspect every section separately as well as the full top (`y = -70..0`) and bottom (`y = 300..350`) overhangs in one continuous image.
- Packs the middle `y = 0..300` (`2048 × 600`) into the top of the `2048 × 1024` `.tga` atlas, the `600 × 220` board strip at `x = 0..600, y = 608..828`, the top overhang (`1160 × 140`, `x_layout = 222..802, y_layout = -70..0`) at `x = 608..1768, y = 608..748`, and the bottom overhang (`1160 × 100`, `x_layout = 222..802, y_layout = 300..350`) at `x = 608..1768, y = 756..856` (with 1px bilinear guard rows).
- `Frame.lua` (`f.art`, `f.artTop`, `f.artBottom`) renders all three slices seamlessly in game.
