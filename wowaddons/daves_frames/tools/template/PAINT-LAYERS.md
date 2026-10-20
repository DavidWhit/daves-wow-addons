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
| **L4 ornament** | Dragon, wings, crest. Always behind the ring; may pass behind or in front of the plate; never over a bar | `guides/L4-ornament-back-guide.png`, `guides/L4-ornament-front-guide.png` |
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
| Orange `#FF8C00` | The ring. In L4 anything painted here is hidden behind the ring, so it's optional |
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
7. **The ring wins:** L3 is always in front of the ornament. A dragon wraps round the ring by passing behind it
   (L4 back) or lying on the plate beside it (L4 front), never across the ring band.
   The one thing in front of the ring is the L5 level badge on its bottom.
8. **Detail size:** the frame is shown at roughly 500 to 700 px wide in game, a quarter of the painting. Keep
   engraving and highlights big enough to read at that size.
9. **No text, numbers, icons, faces or glow** on any layer, and no shadow painted onto the magenta.

## Prompts

Attach the guide first, then paste the prompt. Ask the image tool to **paint over** the guide, not to make a new
picture. One layer per new chat. After the first layer of a frame is right, attach it as a second image to every
later layer of that frame with "match the second image's material and lighting exactly".

### L1 outer border

> Paint over the attached guide image exactly, keeping every shape where it is and the same size.
>
> The GREY shape is the outer border of a long horizontal unit frame for a fantasy game interface: a decorative
> metal plate, [MATERIAL]. Paint an ornate border pattern along it, with fine engraving and a raised outer edge.
> The two GREY boxes at the very ends are the end caps: shape them into a simple, solid end piece inside the box.
> No spikes or points outside the grey.
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

> Paint over the attached guide image exactly, keeping every shape where it is and the same size.
>
> The GREY shape is the inner rim of a fantasy game unit frame, the container around two long bar windows,
> [MATERIAL], matching the second attached image exactly. Paint it a step lower than the outer border, with a
> clean bevel that drops down into the windows on every side and slightly rounded inner corners. Even width all
> the way round. No ornaments.
>
> The BLUE window stays perfectly flat pure blue #0000FF with a crisp edge: it's cut out later. Don't paint a
> trough, a shadow or anything inside it. The dashed cyan line is only a guide; ignore it. The MAGENTA stays
> perfectly flat magenta.
>
> Style: as the second image. Front-on, lit softly from the top left, perfectly symmetrical.
>
> Never add: text, numbers, logos, bars, colour in the window, glow, anything outside the grey.

### L3 portrait ring

> Paint over the attached guide image exactly, keeping every shape where it is and the same size.
>
> The LIGHT GREY ring is the frame around a round portrait, [MATERIAL], matching the second attached image
> exactly. A thick ring with a raised rolled outer rim, a fine engraved band and a thin dark inner lip. It stands
> above the plate: give it a soft shadow on its lower outside edge, inside the grey only.
>
> The BLUE circle stays perfectly flat pure blue #0000FF with a crisp edge. The dashed cyan lines are only a
> guide; ignore them. The MAGENTA stays perfectly flat magenta.
>
> Style: as the second image. Front-on, lit softly from the top left.
>
> Never add: text, gems, a face or portrait, ornaments outside the ring, glow.

### L4 ornament (back and front)

Paint the whole ornament once on `L4-ornament-back-guide.png`, then split it: the parts that pass **in front of**
the plate go in L4 front (repaint them on `L4-ornament-front-guide.png`, or cut them out of the first image), the
rest stays in L4 back.

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
>
> Style: hand-painted World of Warcraft art, [MATERIAL] scales with darker shading, soft top-left light, readable
> at small size, front-on. Not symmetrical.
>
> Never add: text, logos, watermarks, fire, smoke, glow, sparkles, shadows on the background, a frame or bar.

### L5 level badge

> Paint over the attached guide image exactly, keeping every shape where it is and the same size.
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

Name the files `<variant>-L1.png`, `<variant>-L2.png`, `<variant>-L3.png`, `<variant>-L4-back.png`,
`<variant>-L4-front.png`, `<variant>-L5.png` (for example `gold-elite-L4-front.png`) and drop them in a folder. Each is cut out with
clean edges (no fringe, nothing frayed), checked against the rules in NOTES.md section 8, and dropped
into the demo to compare with the gold elite before it goes into the addon.

To redraw the guides (for example after a template change), run `Make-LayerGuides.ps1 -Out guides`.
