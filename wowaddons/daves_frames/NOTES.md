# daves_frames: frame standard

One widget box for every unit. Players, ordinary NPCs, elites, rare elites (silver elites), and bosses share it. An elite uses the elite plate in that same shape, a rare or rare-elite uses the single silver-elite plate (`rareelite`), and a boss uses that same box. The mask below is the template. Paint the lip, the outer frame, and the ring.

The paint mask is [`tools/template/guides/frame-template-ai.png`](tools/template/guides/frame-template-ai.png) (`2048 × 1152`, exact `16:9`: the `2048 × 600` 2× plate canvas padded with `276 px` of `#FF00FF` magenta top and bottom), and the branched extended mask is [`tools/template/guides/frame-template-extended-ai.png`](tools/template/guides/frame-template-extended-ai.png) (`2048 × 1152`, exact `16:9`: keeps every existing section at its exact size and position, adds a top `#FF8000` Orange crest circle at `512, 20` radius `37` / diameter `74` (`4/5` of the `92 px` level ring) overlaying the portrait and portrait ring, and adds an upper background `#FF0000` Red rectangle at `x = 222..802, y = -70..81` layout px strictly above the horizontal bars and outside the portrait/crest rings behind everything where unfilled `#FF0000` Red keys out to transparent). For separate per-section previews and focused single-section redraws, [`tools/Build-FrameTemplate.py`](tools/Build-FrameTemplate.py) also generates 6 modular `2048 × 1152` (`16:9`) per-section stencils under [`tools/template/guides/layers/`](tools/template/guides/layers/) (`layer-1-backdrop-ai.png` through `layer-6-level-ai.png`) matching the 6 guide layers in exact back-to-front drawing order (`Order 1 → Order 6`). All masks are built from [`tools/template/frame-template.json`](tools/template/frame-template.json). The numbers below are that file, and they are the numbers in `Layout.lua`.

`Media/frame-plain.tga` has its gold plate in the top `2048×600` (including the level ring), while `Media/frame-elite.tga`, `Media/frame-rareelite.tga`, and `Media/frame-boss.tga` pack extended plates (`2048×600` main slot plus top/bottom overhang bands at `x = 608..1768, y = 608..748` and `y = 756..856`). [`tools/Pack-FrameTemplate.py`](tools/Pack-FrameTemplate.py) still packs a 2× `600×220` strip at `y = 608..828`. The aura boards do not draw the strip. They are a thin border.

Units: **layout pixels** (the frame before the 0.5 real-scale factor). One layout pixel is 2 pixels on the 2× mask.

---

## 1. The box

One box, 1024 × 300 layout px. The level ring sets the height. The bars sit in a plate across the middle.

| Part | Position (layout px) | Paint |
| --- | --- | --- |
| Art | 0,0 to 1024,300 | `w`, `h`. Atlas slot 2048×600 at the top of 2048×1024 (`art` bottom 0.585938) |
| Ring centre | 512, 136 | `cx`, `cy` |
| Portrait opening | radius 105 | Blue. The game draws the portrait. It is 4 px bigger so it tucks under the ring |
| Portrait ring | radius 105 to 128 | Orange. Paintable, including the lower band |
| Level ring | centre 512, 252 (`badge.dy` 116). Outer 92, band 16, hole 60 | White paint, on top of the portrait ring. Yellow hole is the placeholder |
| Health hole | 35,108 to 379,164 | Blue. 344 × 56. The game draws health here |
| Mana hole | 645,108 to 989,164 | Blue. Same size. The ring is the gap between the holes |
| 5 px lip | around each hole, and out to the ring on the inner end | Green. Paintable |
| Outer frame | 22 px around that lip. Plate 8,81 to 1016,191 | Grey. Paintable. It stops where the ring overlaps |
| Outside | the rest of the canvas | Magenta. Do not paint |
| Chains | `pivotY` 189 | The hook sits in the bottom of the outer frame. Lanes `{16,376}` and `{648,1008}` |

The bar widget runs 5 px under the lip and stops at the ring's outer edge (`hidden` 128, x 384 on the left). The blue hole is the part that stays unpainted, so the bar shows there. The name ends 14 px before that ring edge.

The name is 44 layout px in a 56 px window, so scale 0.65 still leaves it about 14 screen px. The frame is about 333 × 88 at that floor.

---

## 2. Layers and draw order

Paint the green lip, the grey outer frame, the orange portrait ring, and the white level ring. Leave blue, magenta, and the yellow level hole alone. The level ring sits on top of the portrait ring, centred on the middle of that ring at the bottom.

| Region | Colour on the mask | What |
| --- | --- | --- |
| Health and mana holes | Blue `#0000FF` | The addon draws the bars |
| Portrait opening | Blue `#0000FF` | The target portrait fits inside the ring |
| 5 px lip | Green `#00FF00` | The border around each bar |
| Outer frame | Grey `#808080` | The thicker frame around that lip. 22 layout px |
| Portrait ring | Orange `#FF8000` | The band the portrait sits inside, including the lower band |
| Level ring | White `#FFFFFF` | Painted 16 px border (outer 92) stamped on top of the portrait ring at `512, 252` |
| Level hole | Yellow `#FFFF00` | 60 px hole inside the level ring where the level number sits. Do not paint |
| Outside | Magenta `#FF00FF` | Exterior. Do not paint |

What the addon draws, from the back to the front: aura boards and chains, then the bar troughs and the bars, then the inset, portrait, and dark level disc, then the art, then the text and level number.

**Stitching.** Where the bar meets the lip, the bar runs on under the paint:

| Joint | Overlap |
| --- | --- |
| Bars / lip | Bars run 5 px under the lip at each end, 2 px at the top and bottom (`ns.STD.sideX`, `sideY`) |
| Portrait / ring | The portrait is 4 px bigger than the opening |

How plates are painted on `guides/frame-template-ai.png` is in [`tools/template/PAINT-LAYERS.md`](tools/template/PAINT-LAYERS.md).

---

## 3. Bars

- Health on the left, resource on the right. Both **empty toward the portrait**: the full end is the outer end.
- The bar widget runs from 5 px outside the hole to the ring's outer edge (`hidden` 128). The blue hole is the part the mask leaves open.
- **Damage trail:** a pale bar behind the health that holds for 0.55 s after a hit, then eases to the current health (`Enum.StatusBarInterpolation.ExponentialEaseOut`).
- **Incoming heal:** pale green, from the end of the health outward.
- **Shield:** white diagonal stripes beyond the heal (the shield-overflow white tick is listed under Section 10 "Not in yet").
- **Empty part:** never blank. It's the bar's own colour mixed dark (30% of the mid colour, 38% of the dark colour).
- **Outer end:** the bar tucks 5 px under the green lip.
- Inner end: the bar stops at the ring's outer edge. The green lip covers the last 5 px. The ring starts there.

### Colours (light, mid, dark)

| Bar | Colours |
| --- | --- |
| Health (connected) | Blizzard's target-frame green (`ns.ShadesOf(0, 1, 0)`); grey (`ns.COLORS.tapped`) while disconnected |
| Mana | `#a9c8ff` `#2e6fe0` `#0b2766` |
| Cast, can be interrupted | `#ffe39a` `#f0a12a` `#a85a06` |
| Cast, can't be interrupted | `#e2e6ea` `#9aa3ad` `#5b636c`, with a small shield before the spell name |
| Cast finished / interrupted | Flash `#fff6d0` to `#ffd56a` / `#ff8c7a` to `#c0261a` and the word "Interrupted" |

Rage, energy and focus use their usual power colours in the same three-stop form.

## 4. Inset over each window

The bars must read as sunk into the plate. One even inset over each window, the same on every variant:

```
inset 0 0 0 1.5px  rgba(0,0,0,.85)     dark edge all round
inset 0 5px 6px -2px rgba(0,0,0,.7)    shadow under the top lip
inset 0 -3px 4px -2px rgba(0,0,0,.45)  lighter shadow along the bottom
inset 5px 0 6px -3px rgba(0,0,0,.55)   and at each end
inset -5px 0 6px -3px rgba(0,0,0,.55)
inset 0 -1px 0 1px rgba(255,235,200,.06)  faint light on the bottom lip
```

Radius 5 at the outer end, square at the inner end (under the ring).

---

## 5. Name, cast and numbers

### Name and cast layout (a setting)

| Setting | Left window | Right window |
| --- | --- | --- |
| **Overlay** | The name over the health | The cast fills over the resource, which dims to 38% brightness. Spell name by the ring, time left at the outer end |
| **Stacked** | A 30 px strip on top: the name in Blizzard's target-frame green (grey while disconnected). Health below | A 30 px strip on top: the cast, or "on Dave" (who they target) when not casting. Resource below |

Stacked needs room: scaling below 0.85 switches the setting to Overlay (and numbers in the bars to the portrait),
and Edit Mode hides Stacked there with a note.

### Numbers (a setting)

| Setting | Where |
| --- | --- |
| **On the portrait** (default) | Two centred lines on the portrait: health over resource, one size, on a soft dark band |
| **In the bars** | Value at the outer end, % by the ring. **Only offered with Stacked**; Overlay keeps the bars clear. If they would be under 8 screen px they show on the portrait instead (the setting stays) |
| **Off** | |

**Format** (a setting): Numbers, %, or Both ("18.6K · 74%"). The same choice applies in both places.

Values are abbreviated from 1,000 to three figures: `1.23k`, `12.3k`, `123k`, `1.23m` (Korean and Chinese clients keep Blizzard's own). On Forever health is a secret value: it goes straight into the bars and
into Blizzard's number abbreviation, never into addon maths.

### Portrait

- **Opacity** (a setting, 0 to 100%): the portrait fades over a dark disc so the numbers stand out. 0% leaves
  just the disc.
- Dead: the portrait and plate desaturate, health and power numbers hide, `"Dead"` shows at the outer right end of the right (resource) bar, and the boards fade out.

### Fonts

All text uses Blizzard's own unit-frame text (`TextStatusBarText`: Friz Quadrata, outlined, the right font for the
client's language). The name is 44 layout px. The frame's smallest scale is 0.65, which is a real scale of 0.325, so that name is still about 14 screen px. The window is tall enough for those 44 px (the overlay cap is the window height minus 8, which is 48). The portrait's "Both" line ("12.3k · 74%") is smaller than that on purpose: growing the portrait to fit it would grow the whole frame. The level ring is white on the template, 92 px across with a 16 px band, centred at 512, 252, on top of the portrait ring. The number sits in the 60 px yellow hole, 0.5 px low, above the plate.

---

## 6. Aura boards

Your debuffs on the target on the **left** board, their buffs on the **right**. Each board is a thin border
around the icons, the same on chains and right under the bar.

### Board art

A 2 layout px hairline (`ns.STD.plainPad.border`) in a dimmed version of the plate's mid metal (`ns.BoardEdgeColor`, 45% of the mid tone at 85% alpha), with a faint dark fill (alpha 0.35) inside it. At Scale 1 that line is about one screen pixel. Padding is 4 px top and bottom and 3 px on the sides, outside that line. The icon's 2 px border sits inside the top padding. The atlas still holds the old `600 × 220` 9-slice strip at `y = 608..828` (`ns.L.board` is the 28 px corner the packer uses). The boards do not sample it.

### Contents

- One slot per aura: a 40 px icon, then its time left 5 px below it. Slots are 10 px apart, with 6 px between rows.
- Icon border by dispel type (`Layout.lua` `ns.DISPEL`): Magic `#3c8cff`, Curse `#9b30ff`, Poison `#32b432`, Disease `#b87822`, none/physical `#c0261a`, buff `#6c6050`.
- Time left uses `C_DurationUtil.CreateDurationTextBinding()` in warm pale text (`0.95, 0.9, 0.8`).
- **Stacks:** one icon per aura, never repeats. From 2 stacks a count badge shows in the bottom-right corner.
- An aura arriving or leaving eases in or out over 0.4 s (width, fade, scale from 0.55). The board's width follows.

### Lanes, growth and chains

- **Lanes:** the left board fills from x 16 to 376, the right board from x 1008 back to 648 (`laneL`, `laneR`). They stop before the ring.
- The **outer edge never moves**: the left board's left edge and the right board's right edge stay fixed.
- **Two vertical chains**, `ns.STD.chainIn` in from each end (half a one-aura board: slot, gap, the board's side insets and padding). A single aura hangs centred under the outer chain alone.
- **Chain sizes:** each chain hooks on 14 px above its pivot. The pivot is `pivotY` 189. The plate bottom is `plateB` 191.
  The board's top hangs 36 px below the pivot. The painted lip ends above `plateB`, so the chain shows below the plate.
  Each chain tucks under the top edge by the border plus the top padding (`chainTail`, 6 px) and stops before the icons.
- **Growing and shrinking:** the outer chain never moves. The inner chain's top slides along its track first and
  the board's edge follows, so the chain leans briefly (/ when growing to the right, \ when shrinking) and then
  hangs straight. On the right board it's the mirror image.
- Chains are drawn as real links in the frame's metal: face-on rings alternating with edge-on links.

### Placement (a setting)

| Setting | |
| --- | --- |
| **On chains** | The same thin border, hanging below the plate as above |
| **Right under the bar** | No chains, no swing. The same thin border. It sits 6 px below the plate, so its lane runs up to the ring |

### Swing (a setting: Off or Subtle)

- Each board is a pendulum and stays level. Gravity 2000, length 118 (left) and 134 (right), so the two never move
  in step. Damping 2.3, gain 0.55, and a hard limit of 8 degrees.
- **What moves them:** starting and stopping, a gentle sway while walking (1.7 steps a second), and a lean while turning (`IsPlayerMoving()` and the change in `GetPlayerFacing()` per frame; `GetPlayerFacing()` returns nil in instances, so there it sways on movement only).

---

## 7. Placement, Edit Mode and size

- **Pinned:** the top of the extended elite/boss frame (`L.extTopT = -70` layout px above the `1024 × 300` frame canvas, scaled by `ns.FrameScale()`) sits on the screen's top edge, and every variant shares this same anchor (`SetClampRectInsets(0, 0, 70, -50)`) so nothing is clipped and the target frame never shifts up and down when changing targets.
- **Floating:** anywhere on screen, stored in `UIParent` units and re-clamped for the user's current `Scale` (dragging unpins; `"Pin to top edge"` in Edit Mode or right-click reset pins it back).
- **Edit Mode:** uses the kit's `templates/editmode/EditModeDialog.lua`, as every addon frame must. Blizzard's
  outline covers the whole frame (with the selection border and `"Dave's Frames"` label synced to `UIParent` scale so they never shrink with `SetScale`): blue, yellow while dragging. It snaps within 8 screen px to
  the 50 px grid, the screen centre, the screen edges and Blizzard's frames, and Shift places it freely.
- **Scale:** 0.65 to 1 (default 0.8), step 0.05. 1 sets a real scale of 0.5. 0.65 is the floor where the 44 px name is still about 14 screen px, and the frame is about 333 x 88. A saved size below that is raised on load. The art stays sharp up to scale 1.

---

## 8. Art files and the checks they must pass

The frame art in `Media/frame-*.tga` is the plate painted on this mask. `Pack-FrameTemplate.py` still slices a matching 2× `600 × 220` strip from the plate's ends into the atlas. The aura boards do not draw that strip.

| File | Size | Content |
| --- | --- | --- |
| `Media/frame-plain.tga` | 2048 x 1024 | Classic dark-iron/bronze molding & stepped antique-gold plate (`tools/template/paintings/plain.png`) in the top `2048×600` and its matching `600×220` gold board strip at `y = 608` |
| `Media/frame-elite.tga` | 2048 x 1024 | Extended Royal Golden Elite Dragon plate (composited `Order 1 → 6` from `tools/template/preview/elite-layers/` with top golden dragon crest, upper golden wings/chains packed in `extTop`, and matching `600×220` board strip at `y = 608`) |
| `Media/frame-rareelite.tga` | 2048 x 1024 | Extended silver-dragon rare-elite plate (used for both `"rare"` and `"rareelite"` classifications, composited `Order 1 → 6` from `tools/template/preview/rareelite-layers/` with top silver dragon crest, upper silver wings/chains, and lower chain swags packed in `extTop` / `extBot`) |
| `Media/frame-boss.tga` | 2048 x 1024 | Extended Blackrock obsidian & molten-gold rune Boss plate (composited `Order 1 → 6` from `tools/template/preview/boss-layers/` with molten-horned skull crest, balanced upper/lower obsidian-and-magma blades & chains packed in `extTop` / `extBot`, and matching `600×220` board strip at `y = 608`) |
| `Media/frame-warrior.tga` | 2048 x 1024 | Forged dark-iron riveted armor & burnished-bronze warrior plate with martial weapon/shield reliefs (`tools/template/paintings/warrior.png`) and its board strip |
| `Media/frame-paladin.tga` | 2048 x 1024 | Judgement royal-crimson enamel & radiant-gold crusader filigree paladin plate with golden wing-feather halo & Silver Hand warhammer crest (`tools/template/paintings/paladin.png`) |
| `Media/frame-hunter.tga` | 2048 x 1024 | Tooled ranger saddle-leather, emerald dragonscale & golden-brass feathered-arrow hunter plate with horn bow grips & crossed-arrows crest (`tools/template/paintings/hunter.png`) |
| `Media/frame-rogue.tga` | 2048 x 1024 | Shadow-black & midnight-purple stitched assassin leather rogue plate with saddle-stitched leather collar ring, diagonal leather bindings, honed gunmetal blade bevels, and riveted blackened-iron corners (`tools/template/preview/rogue-painting.png`, `tools/template/preview/rogue-layers/`) |
| `Media/frame-priest.tga` | 2048 x 1024 | Discipline Priest twilight-violet & obsidian-pewter enamel plate inlaid with interwoven champagne-gold Sacred Light cathedral filigree, moonstone-silver Shadow crescents, and faceted amethyst corner gems (`tools/template/preview/priest-painting.png`, `tools/template/preview/priest-layers/`) |
| `Media/frame-shaman.tga` | 2048 x 1024 | Chiseled volcanic basalt runestone & bronze-gold shaman plate engraved with glowing Fire, Earth, Lightning & Water runes (`tools/template/paintings/shaman.png`) |
| `Media/frame-mage.tga` | 2048 x 1024 | Dalaran Archmage mithril spellplate with golden Kirin Tor scrollwork, ice-cyan highborne runes, cyan mana-sapphire gems & Eye of the Kirin Tor crest (`tools/template/paintings/mage.png`, `--organic-edge`) |
| `Media/frame-warlock.tga` | 2048 x 1024 | Blackened fel-iron warlock plate with recessed dark-iron chains, glowing fel-green Legion runes & faceted purple Soul Shard gems (`tools/template/paintings/warlock.png`, `--organic-edge`) |
| `Media/frame-druid.tga` | 2048 x 1024 | Bark-and-bronze druid plate, leaf inlay, amber beads, crescent on the ring |
| `Media/chain-gold.tga`, `chain-silver.tga` | 32 x 64 | One chain repeat, tiling vertically. The link has a hole |
| `Media/stripes.tga` | 32 x 32 | Shield stripes |
| `Media/circle.tga` | 256 x 256 | Full-bleed anti-aliased disc for the portrait mask and level hole |

The art slot is the top `2048 × 600` of that atlas (`art` in `Layout.lua`). The `600 × 220` board strip sits `8 px` below it (`strip`, `y = 608..828`) and is not shown. Every atlas is packed the same way, so a classification change is `SetTexture` plus the chain and the hairline colour. It is not a frame rebuild.

A later repaint starts from `guides/frame-template-ai.png` (`2048 × 1152`, exact `16:9`), the way [`PAINT-LAYERS.md`](tools/template/PAINT-LAYERS.md) describes.

Plain, elite, and boss share the gold metal. Rare elite (silver elite, covering both `"rare"` and `"rareelite"`) uses the silver. Dead is not a painting: the addon desaturates the art.

## 9. Variants

| Key | Who | Metal | Crest |
| --- | --- | --- | --- |
| `plain` | Ordinary NPCs, and a secret classification or a secret class token | Gold | No |
| `elite` | `UnitClassification` `"elite"` | Gold | Extended |
| `rareelite` | `UnitClassification` `"rareelite"` or `"rare"` (silver elite) | Silver | Extended |
| `boss` | `UnitIsBossMob(unit)` or `UnitClassification` `"worldboss"` | Gold | Extended |
| `warrior` `paladin` `hunter` `rogue` `priest` `shaman` `mage` `warlock` `druid` | A player, when `UnitClass` returns that token | Class colour, dimmed for the aura hairline | No |

An ordinary unit, an elite, a rare elite (silver elite), and a boss are the same box. The nine class plates are the same box again. "Plain" is the name of the key.

A player uses the class plate (`Unit.lua` `ns.ArtFor`). `UnitClass` is secret when unit identity is restricted, and a secret token stays plain. NPCs follow boss / classification (`UnitIsBossMob` or `"worldboss"` -> `boss`, `"rareelite"` or `"rare"` -> `rareelite` matching Forever's `Camelot/TargetFrameUtils.lua` `ShouldUseSilverUnitFrame`, `"elite"` -> `elite`). Dead uses the same art, desaturated by the addon. There is no class animation yet. While Edit Mode is open, the frame shows the unit's own plate by default (`Preview: Auto`, which is your class when previewing on yourself with no target) and does not auto-cycle; pick any variant button in the Edit Mode `Preview` grid to inspect it. `/davesframes art <key>|auto` forces a look outside Edit Mode (`rare`, `silver`, and `silverelite` alias to `rareelite`). `auto` follows the unit. A `/davesframes test` preview on yourself is a player, so it shows your class.

Nothing in sections 1 to 7 changes between variants.

---

## 10. In this addon (0.2.10)

- **Aura boards** are a 2 px dim metal hairline and a faint dark fill (`Auras.lua` `ThinBoard`). They do not sample the atlas strip. Chains still hang the boards.
- **Art follows the unit** (`Unit.lua` `ns.ArtFor`, applied by `ns:ApplyArt`). A readable player class uses `frame-<class>.tga`. Saved `db.variant` is cleared on load.
- **Class & plain plates:** `tools/template/preview/plain-painting.png`, `warrior-painting.png`, `paladin-painting.png`, `hunter-painting.png`, `rogue-painting.png`, `priest-painting.png`, `shaman-painting.png`, `mage-painting.png`, and `warlock-painting.png` (`1376×768`) were painted via Gemini Nano Banana (`daves-frames-paint` skill) on `guides/frame-template-ai.png` and register directly via `Pack-FrameTemplate.py`'s blob fitter. (`tools/template/preview/` is gitignored for QA `--preview`, `--plate-out`, and `--layer-dir` renders.) The remaining `druid` class `Media/frame-druid.tga` file from the initial Imagine pass can be repainted onto `guides/frame-template-ai.png` via `daves-frames-paint` (or onto `guides/frame-template-extended-ai.png` via `daves-frames-paint-extended`) as needed.
- **Textures (standard, branched extended, & modular per-section workflows):** `py -3 tools\Build-FrameTemplate.py` (pass `--drawable` before painting to print exact drawable stencil pixel counts, back-to-front layer order `1..6`, and `#FF0000` Red headroom clearances) redraws `guides/frame-template-ai.png`, `guides/frame-template-extended-ai.png`, and the 6 modular `Order 1..6` section stencils in `guides/layers/layer-1..6-*-ai.png` (`2048 × 1152`, exact `16:9`) and checks that `Layout.lua` matches. Gemini Nano Banana / Imagine paints onto `frame-template-ai.png` (standard), `frame-template-extended-ai.png` (extended, with the top `#FF8000` orange crest circle at `512, 20` `r = 37` and upper background `#FF0000` Red intricate-art box `222,-70..802,81` strictly above the horizontal bars and carved outside the `r = 128` portrait ring & `r_top = 37` crest circle so `#FF0000` Red never touches `#0000FF` Blue or `#FFFF00` Yellow and the painter cannot invent unaligned rings, bars, or bottom wings/chains; see `.claude/skills/daves-frames-paint-extended/SKILL.md`), or any individual `guides/layers/layer-<N>-<section>-ai.png` stencil for focused single-section redraws. `py -3 tools\Pack-FrameTemplate.py` (with `--extended`, `--check-only`, `--save-png`, `--layer <key>`, `--layer-dir <dir>` for separate `layer-1..6-*-preview.png` & `-plate.png` section previews, and `--base-layers` + `--layer-backdrop/--layer-frame/--layer-lip/--layer-ring/--layer-crest/--layer-level` for `Order 1 → 6` back-to-front layered compositing with `4 px` backdrop & `2 px` solid under-tuck) validates zero out-of-bounds armor paint across all `#FF00FF` Magenta, `#0000FF` Blue, and `#FFFF00` Yellow off-limits zones (tolerating empty `#FF0000` Red ↔ `#FF00FF` Magenta `alpha = 0` chroma-key border jitter and off-limits fiducial seams without hard-clipping or radially smooshing over-extended art), registers the holes, extracts or composites the `2048 × 600` standard or `2048 × 840` extended plate, packs the top/bottom overhang bands at `x = 608..1768, y = 608..748` (`extTop`) and `y = 756..856` (`extBot`) alongside the `600 × 220` board strip, and writes `Media/frame-*.tga`. `Frame.lua` renders `f.art`, `f.artTop`, and `f.artBottom` seamlessly (standard atlases leave the overhang slots transparent). See `tools/template/PAINT-LAYERS.md`.
- **Level:** the template's white ring is the painted border (outer 92, band 16, centre 512, 252, on top of the portrait ring). The number sits in the 60 px hole on `Media/circle.tga`, 0.5 px low. The font string is that hole, so the digits center in it.
- **Portrait masking:** `SetPortraitTexture(f.portrait, unit)` must keep `disableMasking` omitted/`false` — the C++ engine caches one shared dynamic portrait texture per unit, so passing `true` unmasks Blizzard's stock unit frames into an opaque `#000E21` square. Instead, `f.portrait` is sized to `L.rOut` (`128`) so the engine's baked circular margin sits outside `L.rIn + portraitPad` (`109`), and `f.portraitMask` (`Media/circle.tga`) crops it cleanly under the ring.
- **Portrait button:** `Frame.lua` `ns:BuildPortraitButton` places a `SecureUnitButtonTemplate` on `UIParent` over the portrait (`RegisterUnitWatch` out of Edit Mode, synced out of combat) so left-click targets and right-click opens the unit menu.
- **Secret values:** health, absorbs and heals go straight into the bars and text; cast times into
  `SetMinMaxValues`/`SetValue`; "can't be interrupted" through `SetVertexColorFromBoolean`. Aura times use
  `C_UnitAuras.GetAuraDuration` with a duration text binding, and stacks use
  `C_UnitAuras.GetAuraApplicationDisplayCount`. Classification and the class token are read only after `issecretvalue`; a secret stays plain. The kit's wow-forever-api skill has the full list
  ("Unit frame toolbox").
- **Not in yet:**
  - the shield-overflow tick
  - the "+2.4K" shield number
  - aura borders by dispel type when the type is secret (they fall back to the plain colour)
  - the time left on a cast whose times are secret
  - the stack badge's pop
  - hiding Blizzard's target frame
  - a short animation on the class plates. The plates themselves are in
