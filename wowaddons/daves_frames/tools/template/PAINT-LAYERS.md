# Painting a frame in layers

How to paint a new target frame variant so it fits the same template as the gold elite and feels like the same
frame. The measurements and behaviour are in [`NOTES.md`](../../NOTES.md). This file covers
the artwork only.

A frame is five layers, each painted on its own guide image (2400 x 920) and delivered as its own PNG. Because
every guide uses the same template, the layers stack with no offsets and every variant lines up with every other.

| Layer | What it is | Guide |
| --- | --- | --- |
| **L1 outer border** | The decorative plate: border pattern, end caps, engraving | `guides/L1-outer-border-guide.png` |
| **L2 inner border** | The container rim around the health and resource bars | `guides/L2-inner-border-guide.png` |
| **L3 portrait ring** | The ring around the portrait | `guides/L3-ring-guide.png` |
| **L4 ornament** | Dragon, wings, crest. May pass behind or in front of the plate and the ring; never over a bar | `guides/L4-ornament-back-guide.png`, `guides/L4-ornament-front-guide.png` |
| **L5 level badge** | A small round badge on the bottom of the ring; the addon writes the level in its centre | `guides/L5-level-badge-guide.png` |

`guides/L0-stack-preview.png` shows how the layers stack, each in its own colour. The gold painting (`TargetFrameGuides/render/gold-elite.jpg`, built into `Media/frame-gold.tga`) is the gold
elite as it is now: use it for style and level of detail, not for position (the guides set the position).

## Colour key (every guide)

| Colour | Meaning |
| --- | --- |
| Magenta `#FF00FF` | Background. Stays perfectly flat magenta |
| Grey `#808080` / light grey `#B0B0B0` | Paint this layer here |
| Green `#00FF00` | Ornament may be painted here (L4 only) |
| Blue `#0000FF` | A hole: the portrait opening or the bar windows. Stays perfectly flat blue |
| Yellow `#FFFF00` | Forbidden: the bars and a 6 px margin round them. Stays perfectly flat yellow |
| Orange `#FF8C00` | The ring. In L4 back anything painted here is hidden behind the ring, so it's optional |
| Cyan dashed line | Where the other layers are, for reference only. Paint over it as if it weren't there |

Key colours must stay flat and exact, with a crisp edge where the paint meets them. That's how the backgrounds
are cut out cleanly afterwards.

## Rules that make the layers feel like one frame

1. **One light:** soft, from the top, a little to the left. Every layer, every variant.
2. **One material per frame:** L1, L2 and L3 are the same metal (gold, silver, or dark gold with crimson).
   Only L4 may be a different material.
3. **Depth order:** L1 is the highest surface of the plate. L2 sits a step lower and its inner edge drops into the
   bar windows (painted as a bevel going down). L3 stands above both. Paint the shading so it agrees: L2 casts a
   thin shadow onto nothing (the window is a hole), L3 casts a soft shadow onto L1 and L2 just outside its band.
4. **Plain ends:** no spikes or wings sticking out of the plate except inside the end cap boxes. Every frame has the
   same outline; only the surface changes. The ornament is the one thing allowed to break the outline.
5. **Windows are holes:** L2's windows are flat blue (cut out later). Never paint a trough, a bar or a colour in
   them: the addon draws the trough, the bars and the inset shadow.
6. **Never over a bar:** nothing in any layer goes inside the yellow keep-out. The ornament may run behind the
   plate (L4 back) or over it (L4 front), but never across a window.
7. **Round the ring, either side:** the ornament may pass behind the ring (L4 back) or over it and the portrait
   (L4 front): claws gripping the rim, a skull on its top, horns across the portrait's edge. Only the L5 level
   badge and the portrait's text are in front of L4 front. Over the portrait, keep it to the edge: the face is
   what the frame is for.
8. **Detail size:** the frame is shown at roughly 500 to 700 px wide in game, a quarter of the painting. Keep
   engraving and highlights big enough to read at that size.
9. **No text, numbers, icons, faces or glow** on any layer, and no shadow painted onto the magenta.

## Prompts

Attach the guide first, then paste the prompt. Ask the image tool to **paint over** the guide, not to make a new
picture. One layer per new chat. After the first layer of a frame is right, attach it as a second image to every
later layer of that frame with "match the second image's material and lighting exactly".

The image tool keeps a layer on the template only when it paints *onto* the guide's shapes. Asked for "a frame",
it redraws one at its own size. The boss L1 to L3 came back 16:9, as a fat frame and with a thick ring, while
the boss L4, painted onto its guide, landed within 0.3%. So every prompt starts with the same canvas block and
gives the shape's proportions in numbers, and each layer is checked with `Preview-Layers.ps1` before the next
one is painted (see Delivering).

Canvas block (first lines of every prompt):

> Paint ONLY onto the GREY shape of the attached guide image. Do not repaint, move, resize or reshape the guide's
> shapes, and do not crop, zoom or re-frame the picture: the result must be the same 2400 x 920 canvas, with every
> shape exactly where the guide has it.

### L1 outer border

> [Canvas block]
>
> The GREY shape is the outer border of a long horizontal unit frame for a fantasy game interface: a decorative
> metal plate, [MATERIAL]. It is very long and thin, about nine times as wide as it is tall, and stays that shape.
> Paint an ornate border pattern along it, with fine engraving and a raised outer edge. The two GREY boxes at the
> very ends are the end caps, each a narrow upright box: shape them into a simple, solid end piece inside the box,
> no wider than the box. No spikes or points outside the grey.
>
> The MAGENTA area inside the plate stays perfectly flat magenta: another layer sits there. The MAGENTA background
> stays perfectly flat magenta.
>
> Style: hand-painted World of Warcraft user interface art, like Blizzard's own unit frames. Chunky, readable
> metalwork, soft painted highlights, slight wear. Perfectly front-on, no perspective. Lit softly from the top
> left. Perfectly left-right symmetrical.
>
> Never add: text, letters, numbers, logos, watermarks, icons, gems, a face, glow, shadows on the background,
> anything outside the grey.

### L2 inner border

> [Canvas block]
>
> The GREY shape is the inner rim of a fantasy game unit frame, the container around two long bar windows,
> [MATERIAL], matching the second attached image exactly. It is a thin rim, about twelve times as wide as it is
> tall, and the metal is only as thick as the grey band in the guide: don't widen it or shrink the window.
> Paint it a step lower than the outer border, with a clean bevel that drops down into the windows on every side
> and slightly rounded inner corners. Even width all the way round. No ornaments.
>
> The BLUE window stays perfectly flat pure blue #0000FF with a crisp edge: it's cut out later. Don't paint a
> trough, a shadow or anything inside it. The dashed cyan line is only a guide; ignore it. The MAGENTA stays
> perfectly flat magenta.
>
> Style: as the second image. Front-on, lit softly from the top left, perfectly symmetrical.
>
> Never add: text, numbers, logos, bars, colour in the window, glow, anything outside the grey.

### L3 portrait ring

> [Canvas block]
>
> The LIGHT GREY ring is the frame around a round portrait, [MATERIAL], matching the second attached image
> exactly. The band is narrow: the blue opening is four fifths of the ring's width, and the ring's outer edge is
> exactly the guide's grey edge, no bigger. Within that band: a raised rolled outer rim, a fine engraved band and
> a thin dark inner lip. It stands above the plate: give it a soft shadow on its lower outside edge, inside the
> grey only.
>
> The BLUE circle stays perfectly flat pure blue #0000FF with a crisp edge. The dashed cyan lines are only a
> guide; ignore them. The MAGENTA stays perfectly flat magenta.
>
> Style: as the second image. Front-on, lit softly from the top left.
>
> Never add: text, gems, a face or portrait, ornaments outside the ring, glow.

### L4 ornament (back and front)

Paint the whole ornament once on `L4-ornament-back-guide.png`, then split it with a mask, not a second painting:
make `<variant>-L4-front-mask.png` on the same canvas as the painting, white over the parts that pass **in front
of** the plate or the ring and black everywhere else (any paint program: a layer over the painting, filled in,
saved alone). `Preview-Layers.ps1` cuts L4 front out of the painting with it, so front and back are the very
same pixels where they meet and stitch without a seam. L4 back keeps the whole ornament; don't erase the front
parts from it.

Draw the mask's edges along a natural break in the ornament (where a claw meets the rim, a strap's edge), not
across open paint. Inside the ring, the front parts may cover the guide's blue opening.

The L4 front prompt below is only for when an ornament part must look different in front (say, a claw that
grips the rim instead of passing behind it). A repainted front never matches the back pixel for pixel, so put
its joins where the plate or the ring hides them.

L4 back:

> Paint ONLY [ORNAMENT, e.g. "a sleek gold dragon"] onto the attached guide image. Do not repaint the guide's
> coloured shapes.
>
> The ORANGE ring marks where a round metal ring already sits in the finished interface. The ornament wraps
> around it: its body passes behind the ring, its wings rise into the GREEN area above, its tail may hang into the
> GREEN area below the ring.
>
> Hard limits, the most important part:
> - NOTHING on the YELLOW area. Not a claw, wing tip, tail, spine, shadow or glow. The game needs it clear.
> - NOTHING on the BLUE circle.
> - Only on GREEN (and ORANGE, which will be hidden). MAGENTA, YELLOW and BLUE stay perfectly flat and exact,
>   with crisp edges.

L4 front (attach the L4 back result as the second image):

> Paint ONLY the parts of the second image's ornament that lie IN FRONT of the plate and the ring onto the
> attached guide image, in exactly the same place and size: [PARTS, e.g. "the skull on top of the ring and the
> claws gripping its sides"]. Do not repaint the guide's coloured shapes.
>
> The dashed cyan circles are a round metal ring and the portrait inside it. These parts lie over them, the
> way a claw grips a rim. Over the inner circle (the portrait), keep to its edge.
>
> Hard limits, the most important part:
> - NOTHING on the YELLOW area. Not a claw, wing tip, tail, spine, shadow or glow. The game needs it clear.
> - Only on GREEN. MAGENTA and YELLOW stay perfectly flat and exact, with crisp edges.
>
> Style: hand-painted World of Warcraft art, [MATERIAL] scales with darker shading, soft top-left light, readable
> at small size, front-on. Not symmetrical.
>
> Never add: text, logos, watermarks, fire, smoke, glow, sparkles, shadows on the background, a frame or bar.

### L5 level badge

> [Canvas block]
>
> The small LIGHT GREY circle is a round badge that sits on the bottom of a portrait ring, [MATERIAL], matching
> the second attached image exactly. A raised rim with a rolled edge, like a coin set into the ring, the size of Blizzard's own level circle:
> keep the rim inside the grey band; the number area in the middle is large. It stands in
> front of the ring: a soft shadow on its lower edge, inside the grey only.
>
> The BLUE circle in its centre stays perfectly flat pure blue #0000FF with a crisp edge: a number is written there
> later. The dashed cyan lines are only a guide; ignore them. The MAGENTA stays perfectly flat magenta.
>
> Style: as the second image. Front-on, lit softly from the top left.
>
> Never add: text, numbers, gems, a skull, glow, anything outside the grey.

Fix line if it breaks a rule: *"Remove everything that touches the yellow (or blue) area and repaint it flat.
Change nothing else."*

### Materials

| Variant | [MATERIAL] |
| --- | --- |
| Gold (normal, elite) | "aged dark bronze with a burnished gold edge" |
| Silver (rare, rare elite) | "cold dark steel with a polished silver edge and a faint blue-white sheen" |
| Boss | "blackened bronze with a dark gold edge and a thin line of deep crimson enamel" |

## Delivering

Name the files `<variant>-L1`, `<variant>-L2`, `<variant>-L3`, `<variant>-L4-back` (or just `-L4`),
`<variant>-L4-front-mask` (or a painted `<variant>-L4-front`) and `<variant>-L5` (for example `boss-L4-front.png`), as png or jpg straight from the image tool
with the guide colours still in, and drop them in one folder. Then preview them as the addon stacks them:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Preview-Layers.ps1 -Folder "$HOME\Downloads" -Variant boss
```

It keys out every guide colour with clean edges, fits each layer onto the template (L1 3-slice by its end caps, L2
9-slice by its rim, L3 by its opening, L4 by the guide's orange ring), clears what NOTES.md section 8 forbids, and
writes `preview-ring-scale.png`, `preview-ring-remap.png` (the two ways to fit a ring that is the wrong
thickness), `fit-sheet.png` (each layer with the template drawn over it) and `fitted-*.png` (the 2400 x 920 layer
files with alpha). L5 isn't stacked yet.

Run it after **each** layer, not at the end, and repaint a layer until its report passes:

| Report line | Passes when |
| --- | --- |
| Size | The canvas is 2400 x 920 or the same 2.609 aspect |
| `FIX` | None. Each one is paint where the rules forbid it (the preview clears it, the next painting shouldn't need that). `cut` lines are the fitter's and are fine |
| L1 fit | Caps squeezed no further than x0.85, middle stretched no more than x1.2 |
| L2 fit | Rim scale between x0.8 and x1.25, painted aspect close to the template's 12.3:1 |
| L3 | Opening/outer between 0.77 and 0.83 (template 0.80), so both ring fits look the same |
| L4 | Ring centre within 0.01 of 0.5, 0.5 |
| Seams | `ok, the stacked frame is solid` for the ring fit you use. Otherwise `seams-ring-*.png` shows each gap in red |

A layer that passes sits on the template as painted, with nothing stretched. Then compare the preview with the
gold elite in the demo before it goes into the addon.

To redraw the guides (for example after a template change), run `Make-LayerGuides.ps1 -Out guides`.
