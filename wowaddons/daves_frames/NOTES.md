# daves_frames: frame standard

Everything about the target frame except its artwork (the notes for this addon). It's written from the **gold elite** variant as built in the
demo (https://claude.ai/artifact/CAA5HcesyiyZtLrQUdkkV2). Every other variant (silver rare elite, normal, rare,
boss, friendly, and so on) follows this file exactly. Only the four art layers change, and they're painted to the
template in [`tools/template/PAINT-LAYERS.md`](tools/template/PAINT-LAYERS.md).

Units: **layout pixels** (the frame at 100% size). Art is delivered at **2x** (double resolution), so multiply by 2
for image pixels.

---

## 1. The template

One template for every variant, 1200 x 460 layout px (2400 x 920 image px). The ring is on the centre line.

| Part | Position (layout px) | Notes |
| --- | --- | --- |
| Canvas | 0,0 to 1200,460 | Everything the frame draws stays inside it, ornament included |
| Ring centre | 600, 230 | Centre of the portrait |
| Portrait opening | radius 105 | Transparent in the art; the portrait shows through |
| Ring (L3) | radius 105 to 131 | 26 px band |
| Level badge (L5) | centre 600,354, radius 40; number area radius 32 | On the ring's bottom (ring centre + 124), in front of the ring. The size the addon shows Blizzard's level circle at, so a painted badge replaces it exactly |
| Outer border (L1) | 8,153 to 1192,289, corner radius 14 | The plate. Plus an end cap allowance at each end: 0..64 and 1136..1200, y 138..304. Its middle is open from 38,179 to 1162,263 (radius 6): 4 px inside L2's outer edge, so L1 runs under L2 and no seam shows |
| Inner border (L2) | 34,175 to 1166,267, corner radius 10 | The container rim around both bars |
| Bar windows | 50,191 to 1150,251, corner radius 5 | Transparent. Health is the left half, resource the right; the ring covers the middle |
| Window keep-out | 44,185 to 1156,257 | The window plus 6 px. No ornament is ever painted here |
| Ornament zone above | 300,0 to 900,153 | |
| Ornament zone on the plate | 300,153 to 900,289 | Front ornament (L4 front), which may also cover the ring and the portrait; never inside the keep-out outside the ring |
| Ornament zone behind the plate | The whole plate | Back ornament (L4 back) only, hidden by the plate; never inside the keep-out |
| Ornament zone below | 430,289 to 770,460 | The ring column only, so the aura boards' lanes stay clear |

Health window, visible part: x 50 to the ring's edge. Resource window, visible part: the ring's edge to x 1150.

### Gold and silver v1 (the current paintings)

The current gold and silver art are single flattened paintings, not layered. They were measured and cut to fit
rather than painted to the template, so their numbers are a little off it. The demo uses these measured values:

| | Gold elite | Silver rare elite |
| --- | --- | --- |
| Art size (1x) | 1198 x 412 | 1201 x 427 |
| Ring centre | 595.8, 227.8 | 602.0, 209.5 |
| Ring radius in / out | 105 / 131 | 105 / 121 |
| Plate | 8..1190 x 153..286 | 11..1190 x 132..266 |
| Window cut | 49..1146 x 189..249 | 53..1146 x 169..229 |
| Board lanes (left / right) | 70..430 / 810..1130 | 75..420 / 870..1130 |

New variants are painted to the template, so they need no measuring. When gold and silver are repainted as layers,
they move onto the template too.

---

## 2. Layers and draw order

Five art layers, plus what the addon draws. From the back to the front:

| # | What | Drawn by | Rule |
| --- | --- | --- | --- |
| 1 | **L4 back**: ornament behind the plate (wings, a tail tucked behind) | art | Behind everything |
| 2 | Bar trough: the empty part of each bar | addon | A dark, worn version of the bar's own colour |
| 3 | Health and resource bars, heal, shield, cast | addon | Inside the windows only |
| 4 | Aura boards and chains (on chains) | addon | Chains hook in behind the plate |
| 5 | **L1 outer border**: the decorative plate | art | Its middle is empty (L2 sits there) |
| 6 | **L2 inner border**: the rim around the bars | art | Overlaps the bar ends: bars run 5 px under it at each end and 2 px at the top and bottom |
| 7 | Inset shadow over each window | addon | See section 4 |
| 8 | Portrait | addon | Circle-masked, 4 px bigger than the opening so its edge tucks under the ring |
| 9 | **L3 ring** | art | Over L4 back, the plate, the portrait and the inner ends of the bars |
| 10 | **L4 front**: ornament over the plate, the ring and the portrait (claws gripping the ring, a head, horns, the tail) | art | Never in the window keep-out, except inside the ring, where no bar shows |
| 10b | **L5 level badge** | art (until a variant has one, the addon shows Blizzard's own level circle, `UI-HUD-UnitFrame-SmallCircle`, at the same size and place) | In front of the ring and L4 front; the level is written in its centre |
| 11 | Numbers and text on the portrait | addon | Over everything, the ornament included |
| 12 | Aura boards (right under the bar) | addon | Over the art |

L4 is one ornament split into two files, so it can pass behind the plate and the ring in some places and in
front of them in others. Only the level badge and the text are in front of L4 front. Nothing ever covers a bar.

**Stitching.** Where two layers meet, the lower one runs on under the upper one, so their soft edges never sit
side by side (two half-transparent edges let the background through as a hairline):

| Joint | Overlap |
| --- | --- |
| L1 / L2 | L1's open middle is 4 px inside L2's outer edge (section 1) |
| Bars / L2 | Bars run 5 px under the rim at each end, 2 px at the top and bottom (`ns.STD.sideX`, `sideY`) |
| Portrait / L3 | The portrait is 4 px bigger than the opening |
| L1, L2 / L3 | L1 and L2 carry on under the ring to radius 104 |
| L4 back / L4 front | L4 front is cut out of the L4 back painting with a mask, never repainted, and L4 back keeps the whole ornament, so the two are the same pixels where they meet |

`tools\Preview-Layers.ps1` checks it: stacked with no background, the plate and the ring must be solid, and every
see-through pixel there is reported and drawn red. The bare template passes (shapes from
`Make-LayerGuides.ps1 -Plain`), so a seam is always in the painting.

A variant may leave out L4 entirely (normal and rare frames have no ornament), and L5 (the addon then shows
Blizzard's level circle). L1, L2 and L3 are always present.

---

## 3. Bars

- Health on the left, resource on the right. Both **empty toward the portrait**: the full end is the outer end.
- Fill width = (the part hidden under the ring) + percent x (visible length). Hidden part: gold 122, silver 111.
- Animation: 0.45 s, `cubic-bezier(.3, .7, .2, 1)`.
- **Damage trail:** a pale bar behind the health that catches up 0.55 s after a hit, over 0.9 s.
- **Incoming heal:** pale green, from the end of the health outward.
- **Shield:** white diagonal stripes beyond the heal. If health + heal + shield is more than full, a glowing white
  tick shows at the outer end.
- **Empty part:** never blank. It's the bar's own colour mixed dark (30% of the mid colour, 38% of the dark colour).
- **Outer end:** rounded with a 5 px radius. The art window, the bar clip and the inset all use the same radius.
- Inner end: always hidden under the ring on every row. The ring is narrowest at the window's top and bottom
  edges, which sets how far under it the bar and the inset must start.

### Colours (light, mid, dark)

| Bar | Colours |
| --- | --- |
| Hostile | `#ff8a76` `#d1301f` `#5e0c06` |
| Neutral | `#fff09a` `#e0b522` `#6a4e04` |
| Friendly player | Class colour (for example mage `#a9ecff` `#3fc7eb` `#0d4d63`) |
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
| **Stacked** | A 30 px strip on top: the name in the reaction colour. Health below | A 30 px strip on top: the cast, or "on Dave" (who they target) when not casting. Resource below |

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
- Dead: the portrait goes grey, the health reads "Dead", and the boards fade out.

### Fonts

All text uses Blizzard's own unit-frame text (`TextStatusBarText`: Friz Quadrata, outlined, the right font for the
client's language). It scales with the frame like the art (no setting): 44 layout px for a full-size role, capped
so it fits where it sits, so text never changes the bars. The level sits on the L5 badge, sized from its centre.

---

## 6. Aura boards

Your debuffs on the target on the **left** board, their buffs on the **right**. Each board is its own billboard
in the frame's metal.

### Board art

Made from L1 + L2, never painted separately: the plate's left 300 px and right 300 px side by side make a strip,
which is drawn as a 9-slice. The slice insets are 100 / 116 / 104 / 116 image px (top / right / bottom / left at
2x). On screen they're 30 / 35 / 31 / 35 px.

### Contents

- One slot per aura: a 40 px icon, then its time left 5 px below it. Slots are 10 px apart, with 6 px between rows.
- Padding is 9 px at the top and 6 px at the bottom. The icon's 3 px border sits in the top padding, so the space
  above the icons matches the space below the timers.
- Icon border by type: magic `#3c8cff`, curse `#9b30ff`, enrage `#ff7a1a`, physical `#c0261a`.
- Time left turns red under 5 s.
- **Stacks:** one icon per aura, never repeats. From 2 stacks a count badge shows in the bottom-right corner, and
  it pops when the count changes.
- An aura arriving or leaving eases in or out over 0.4 s (width, fade, scale from 0.55). The board's width follows.

### Lanes, growth and chains

- **Lanes:** the left board fills from x 70 toward the centre, the right board from x 1130 toward the centre. Each
  wraps to a new row before reaching the ornament below the plate (lane ends at 430 and 770 on the template).
  They can never overlap each other or the ornament.
- The **outer edge never moves**: the left board's left edge and the right board's right edge stay fixed.
- **Two vertical chains**, 62 px in from each end. That's half a one-aura board, so a single aura hangs centred
  under the outer chain alone.
- **Chain sizes:** each chain hooks on 14 px above its pivot, and the pivot is 18 px above the plate's bottom edge.
  The board's top hangs 36 px below the pivot, so about 18 px of chain shows between the plate and the board.
  Each chain carries on 36 px behind the board so it never looks unhooked.
- **Growing and shrinking:** the outer chain never moves. The inner chain's top slides along its track first and
  the board's edge follows, so the chain leans briefly (/ when growing to the right, \ when shrinking) and then
  hangs straight. On the right board it's the mirror image.
- Chains are drawn as real links in the frame's metal: face-on rings alternating with edge-on links.

### Placement (a setting)

| Setting | |
| --- | --- |
| **On chains** | Hanging below the plate as above |
| **Right under the bar** | No chains, no swing. A plain board: 2 px metal border, 5 px radius, dark fill, padding 8 / 6 / 5. It sits 6 px below the plate and may lie over the ornament, so its lane runs up to the ring |

### Swing (a setting: Off or Subtle)

- Each board is a pendulum and stays level. Gravity 2000, length 118 (left) and 134 (right), so the two never move
  in step. Damping 2.3, gain 0.55, and a hard limit of 8 degrees.
- **What moves them:** starting and stopping, a gentle sway while walking (1.7 steps a second), a lean while
  turning, and dragging the frame.
- **In game:** `IsPlayerMoving()` and the change in `GetPlayerFacing()` per frame. Facing returns nil in
  instances, so there it sways on movement only.

---

## 7. Placement, Edit Mode and size

- **Pinned:** the top of the whole frame (the ornament's top) sits on the screen's top edge. Nothing is clipped
  or hidden.
- **Floating:** anywhere on screen.
- **Edit Mode:** uses the kit's `templates/editmode/EditModeDialog.lua`, as every addon frame must. Blizzard's
  outline covers the whole frame, ornament included: blue, yellow while dragging. It snaps within 8 screen px to
  the 50 px grid, the screen centre, the screen edges and Blizzard's frames, and Shift places it freely. Dropping
  it on the top edge pins it.
- **Scale:** 0.5 to 1 (default 0.8). 1 is half the art's size (the frame's real scale 0.5), 0.5 a quarter (0.25). It scales around the centre and keeps a pinned frame on the top edge. Every setting applies to every variant.
  The art ships at 2x, so it stays sharp up to about 200% on a normal screen.

---

## 8. Art files and the checks they must pass

| File (per variant) | Size | Content |
| --- | --- | --- |
| `<variant>-L1.png` | 2400 x 920 | Outer border only |
| `<variant>-L2.png` | 2400 x 920 | Inner border only; windows fully transparent |
| `<variant>-L3.png` | 2400 x 920 | Ring only; opening fully transparent |
| `<variant>-L4-back.png` | 2400 x 920 | Optional |
| `<variant>-L4-front.png` | 2400 x 920 | Optional |
| `<variant>-L5.png` | 2400 x 920 | Optional: the level badge; number area fully transparent |

All are PNG with straight alpha, on the template, at the same position, so they stack with no offsets.

Every file must pass:

1. **Clean edges:** no magenta or blue fringe, no ragged or frayed edges, no stray half-transparent pixels.
2. **Keep-out:** zero alpha inside the window keep-out in L4 back and L3, in L4 front outside the ring
   (radius 131), and zero alpha in the windows in L1 and L2. A script can count the pixels.
3. **Opening:** zero alpha inside radius 104 in every layer except L4 front, which may cover the portrait.
4. **Ring:** L3's band fills radius 105 to 131 with no gaps.
5. **Zones:** L4 only inside its zones; nothing outside the canvas.
6. **Same metal:** L1, L2 and L3 share one material. The ornament may differ (a gold dragon on a gold frame, a
   silver dragon on a silver frame).

In game the layers become textures. 2400 is wider than 2048, so either pad them to 4096 x 1024 and crop with
`SetTexCoord`, or split each layer into two 2048 halves. Settle this when the addon is built, against the kit's
texture checks.

## 9. Variants

| Variant | Material | L4 ornament |
| --- | --- | --- |
| Normal | Gold | None |
| Elite | Gold | Gold dragon |
| Rare | Silver | None |
| Rare elite | Silver | Silver dragon |
| Boss | Dark gold with crimson | Wings and crest |
| Friendly / self | As the reaction (to decide) | None |
| Dead | The same art, desaturated by the addon (grey, 72% brightness) | Not painted |

Nothing in sections 1 to 8 changes between variants.

---

## 10. In this addon (0.1.0, for testing)

- **Every target uses the gold elite art** (`Layout.lua` → `ns.VARIANTS.gold`, measured from the painting).
  Classification-based variants come once more art is painted.
- **Textures:** `tools\Make-FrameMedia.ps1` keys the painting, cuts the windows (smooth edges, 5 px rounded
  ends, whole ring kept) and packs `Media\frame-gold.tga` (2048 x 1024): the frame art across the top at
  2048 wide (1.71x the layout size), and the board strip in the rows below. It also writes the chain and
  shield-stripe textures. It prints the atlas numbers `Layout.lua` needs. A layered painting (L1 to L4)
  needs the script to stack the layers first; that comes with the first layered variant.
- **Secret values:** health, absorbs and heals go straight into the bars and text; cast times into
  `SetMinMaxValues`/`SetValue`; "can't be interrupted" through `SetVertexColorFromBoolean`. Aura times use
  `C_UnitAuras.GetAuraDuration` with a duration text binding, and stacks use
  `C_UnitAuras.GetAuraApplicationDisplayCount`. The kit's wow-forever-api skill has the full list
  ("Unit frame toolbox").
- **Not in 0.1.0 yet:**
  - the shield-overflow tick
  - the "+2.4K" shield number
  - aura borders by dispel type when the type is secret (they fall back to the plain colour)
  - the time left on a cast whose times are secret
  - the stack badge's pop
  - hiding Blizzard's target frame
  - clicking the frame to target or open the menu (it's a display frame; that needs a secure button)
