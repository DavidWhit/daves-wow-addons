# Concepts

Browser-drawn concepts for a new cast bar look, made and judged here before any game art is painted. Only the
look being designed lives here. Once a look is built into the add-on its concept is removed, and the add-on's
code is the reference for it: compare a new look with the other bars' code (`Elements.lua`, `Bar.lua`,
`Effects_*.lua`) and the add-on's README, never with old concepts, so the concepts and their iterations stay clean.

## Pages

| Page | What it is |
| --- | --- |
| `index.html` | The concept harness. It shows every concept here; `?only=fa-b,fa-c` a selection, `&hold=60` freezes the bars at 60 %, `&h=36&w=420` sets the size, `&sim=2` pre-runs two seconds (for screenshots). `&style=borderless` (or the Style switch) shows the bars without their frame |
| `shot.ps1` | Headless Chrome screenshot of `index.html` with any JS errors reported: `shot.ps1 -Only fa -Hold 60 -H 56 -W 560 -Out x.png -Extra "wrap=spica"` |

## In progress

| Look | Variants | What it shows |
| --- | --- | --- |
| First Aid (`firstaid.js`): built into the add-on (0.5.0) as C for casts and D for channels, with a random wrap each cast, one bandage (linen) and the band a seventh of the bar's length wide; this concept goes once the add-on's look is approved in game | A wrapped turns, B bandage roll, C soaked through, D applying a bandage (channel) | An open crimson wound bleeding ahead of the cast (running blood, a heartbeat pulse, beads dripping off the bottom); broad bandage turns, about one and a half bar heights wide, wrap round it at the cast edge and blood seeps through each after it is laid. Each cast changes the wrap (spiral, figure-eight, reverse spiral, spica, circular), its lean, which way the turns come round, and the cloth (linen, wool, silk, mageweave, runecloth). The roll is clipped to the bar. Page keys `&wrap=spica`, `&cloth=0..4`. All four variants are kept for now |

## Rules for a concept

The add-on's full list is in its README, "Rules for every look". Here:

- One concept page per look: no second, simplified copy of it anywhere else.
- Give the concept its frame colour as `frame` (the add-on's `border`); the page then draws the add-on's frame (a
  dark line .1 bar heights thick, 2/3 outside, and a lit line in that colour half as thick inside). Check it
  framed and borderless before a pick.
- Never paint a frame, outline, corners or bevel of your own; fill the bar's rectangle (clipped to the soft
  corner here) and let the options do the rest. Keep the look's own shading light at the edges (about .2 alpha)
  so the bevel isn't doubled.
- A calm finishing flash is `flashAlpha` (the add-on's), for art where the full flash glares.
- Profession and gathering looks have no leading-edge spark; spell looks keep one, coloured to the look.
- The concepts may rotate freely, but nothing in the add-on turns per frame (it shimmers): anything that swings,
  tips or leans is built from fixed poses, so design with that in mind.
- Nothing of a look's material shows past the bar's lines; live effects (particles, sparks, steam, dust, drops of
  blood) may spill over the frame line. Tools that work inside the bar are clipped to it; tools held in front of
  it stand over the frame line, below the text.
- Check every concept at the smallest bar too (`&h=20&w=200`).
- When the look is built into the add-on, delete its `.js` and its `<script>` line in `index.html`.
