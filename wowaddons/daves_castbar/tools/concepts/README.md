# Concepts

Browser-drawn concepts for the cast bar's looks, made and judged here before any game art is painted. Each
look went through variants, picks and refinements on this page, then was built into the add-on to match.

## Pages

| Page | What it is |
| --- | --- |
| `index.html` | The concept harness. By default it shows the final pick per look; `?all` shows every variant, `?only=skin,smith-a` a selection, `&hold=60` freezes the bars at 60 %, `&h=36&w=420` sets the size, `&sim=2` pre-runs two seconds (for screenshots). Some concepts take their own keys: `&tooling=0..4` (leatherworking pattern), `&weather=0..4` (lightning A3 weather) |
| `shape.html` | Corner and depth options on a sample of each look: square / soft / rounded corners, flat / bevel depth, framed or borderless, with a depth-amount slider. These are the options the add-on has |
| `shot.ps1` | Headless Chrome screenshot of `index.html` with any JS errors reported: `shot.ps1 -Only smith-a -Hold 60 -H 56 -W 560 -Out x.png -Extra "weather=2"` |

The concepts are the `.js` files next to the page, one per profession or theme, plus `ref_cloud_data.js`
(the lightning reference painting as a data URL, so the page can read its pixels from `file://`).

## Final picks

The pick per look, as built into the add-on. The letter is the variant's key on the page.

| Look | Pick | What it shows |
| --- | --- | --- |
| Skinning | C2, Pelt roll | The fur pelt (eight furs, one per cast) rolls up at the cast edge over marbled ribeye flesh; a glossy pool of blood grows behind; a steel knife stands upright beside the roll, its edge against it, sawing |
| Lightning | C2, Reference clouds, bank | The user's own indigo cloud painting, keyed off its checkerboard (matte choked a pixel, edge darkened toward the cloud's dark indigo, alpha softened), as one cloud placed in a faint far row and a low near bank of drifting mirrored copies over A3's dark blue sky, with A's forked bolts, flashes, sheet lightning and spark |
| Smelting | A3, Ladle pour, forged | A's pour at the cast edge from B3's sooty forged hand ladle, scaled to .38 bar heights, with no handle; the metal is white-hot where it lands and cools to dark crust plates with glowing seams; the pour's end is a soft rounded nose |
| Blacksmithing | A, Red-hot billet | Iron hottest at the cast edge, the hammer painted like the skinning knife, each blow a flash and sparks; it quenches to grey tempered steel with a faint sheen |
| Alchemy | B2, Alchemist's apparatus | A shuffled bench of glassware the potion works through, pouring into the bar, which fills like a liquid and brims at the end; no leading marker, the liquid is the progress |
| Tailoring | A2, Shuttle and reed, small | A's loom shrunk and painted plainer: a small worn boat shuttle, a slim steel reed, fine threads; in the add-on the loom is clipped to the bar |
| Leatherworking | B, Laced panels | Tooled leather panels, apart by their open gaps, cross-laced shut by a needle as the cast reaches each joint; the tooling cycles per cast (basket-weave, scrolling vine, diamond lattice, bordered shells, knotwork band) |
| Enchanting | C, Vortex siphon | Velvet the magic settles on; a vortex at the cast edge pulls glittering dust out of the unfilled part and spins it in |
| Disenchant | C3, Vortex siphon, disenchant | The bar starts solid with magic; the vortex comes in from the right end and moves left, drawing the magic out ahead of it and throwing it out behind as dust and small shimmers on the spent cloth (the add-on has no essence orbs) |

Corners and depth (`shape.html`): square, soft (default) and rounded corners, flat (default) and bevel depth
were picked; pill corners and the slab and tilted depths were dropped.

## Kept under `?all`

Skinning A, B, C; Lightning A, A2, A3 (Thunderhead, layered, with its five weathers), B, C, the painted
cumulus B1–B4 and the reference-cloud C1 and C3; Smelting A, A2, B, B2, B3, C, D; Blacksmithing A2, B, C;
Alchemy A, B, C; Tailoring A, A3, A4, B, C; Enchanting A, B, C2; Leatherworking A, C.

## Rules settled here

- Profession and gathering looks have no leading-edge spark; their own motion shows the progress. Spell
  looks keep the spark, coloured to the look.
- Edges are always clean: framed (a thin line in the look's colour) or borderless, never frayed or ragged.
- Nothing in the add-on turns per frame (it shimmers); anything that swings or tips is painted at fixed
  poses. The concepts may rotate freely, so a concept that spins something will be built from a pose sheet.
- Live effects draw over the frame line on every look; the loom's tools are deliberately clipped to the
  bar, and that is the one exception.
- Tools held in front of the bar (knife, hammer, ladle, needle, vortex) stand above the frame line and
  below the text.
