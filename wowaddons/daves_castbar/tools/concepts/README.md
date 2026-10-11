# Concepts

Browser-drawn concepts for a new cast bar look, made and judged here before any game art is painted. Only the
look being designed lives here. Once a look is built into the add-on its concept is removed, and the add-on's
code is the reference for it: compare a new look with the other bars' code (`Elements.lua`, `Bar.lua`,
`Effects_*.lua`) and the add-on's README, never with old concepts, so the concepts and their iterations stay clean.

## Pages

| Page | What it is |
| --- | --- |
| `index.html` | The concept harness. It shows every concept here; `?only=key-b,key-c` a selection, `&hold=60` freezes the bars at 60 %, `&h=36&w=420` sets the size, `&sim=2` pre-runs two seconds (for screenshots). `&style=borderless` (or the Style switch) shows the bars without their frame |
| `shot.ps1` | Headless Chrome screenshot of `index.html` with any JS errors reported: `shot.ps1 -Only key -Hold 60 -H 56 -W 560 -Out x.png -Extra "style=borderless"` |

## In progress

None. First Aid, the last look designed here, was built into the add-on in 0.5.0 and its concept removed (it is in
git history).

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
