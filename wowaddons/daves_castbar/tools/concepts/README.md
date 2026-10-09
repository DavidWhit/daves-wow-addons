# Profession concepts

Browser-drawn concepts for new cast bar looks, made before any game art. Open `index.html` in a browser
(it loads the five `.js` files next to it).

Picked to build on (2026-10-08), shown by default:

| Look | Pick | What it shows |
| --- | --- | --- |
| Skinning | C, Pelt roll | The pelt peels back into a growing roll behind the knife; raw hide with blood spots behind it; bones tumble out the bottom |
| Lightning | A, Thunderhead | A churning storm cloud fills the bar; forked bolts strike inside it and light it up |
| Smelting | B, Running channel | A ladle pours at the left end; molten metal runs along the bar with a glowing front, crust drifting on it |
| Blacksmithing | A, Red-hot billet, with C's ending | The iron glows hottest at the cast edge; a forge hammer strikes there in rhythm with sparks and steam; on completion it quenches to tempered steel in a cloud of steam |
| Alchemy | B, Coiled condenser | A glass coil runs the bar; the potion snakes through it from a heated flask to a receiving one |

`index.html?all` shows every variant (three per profession); `?only=skin,smith-a` a selection;
`&hold=60` freezes the bars at 60%. `shot.ps1 -Only smith-a -Hold 60` takes a headless Chrome
screenshot and reports any script errors.

Second round (2026-10-08), each shown next to the pick it came from:

| New | Changes asked for |
| --- | --- |
| Skinning C2, Pelt roll, raw | Real insides behind the roll: fat layers, muscle fibres, branching vessels, wet sheen, pooling and dripping blood; the knife stands in front of the bar's top line |
| Lightning A2, Thunderhead, dark | Darker, billowing storm clouds in three depths; strikes light the clouds from inside |
| Smelting B2, Foundry ladle | A massive riveted foundry ladle on a crane yoke tips on its pivots and pours a thick stream |
| Blacksmithing A2, Red-hot billet, forged | Deeper heat colours that each blow pushes hotter; a Warcraft-style forge hammer; same quench ending |
| Alchemy B2, Alchemist's apparatus | A whole bench of glassware (burners, retort, condenser, coil, funnel, vial rack) joined by glass, hoses and valves; Alchemy C is shown too for its burners |

Final drafts (2026-10-08), shown by default:

| Look | Final | Last changes |
| --- | --- | --- |
| Skinning | C2, Pelt roll, raw | Blood streaks run along the top and bottom of the raw side and drip, instead of tumbling bones |
| Lightning | A2, Thunderhead, dark | Thinner clouds: separate masses with dark sky between them |
| Smelting | B2, Foundry ladle | Bucket the size of B's hand ladle; realistic cast iron (no outlines or gear wheel); thinner stream |
| Blacksmithing | A, Red-hot billet | A2's Warcraft-style hammer at 78% size, in front of the bar; A's colours and the quench ending |
| Alchemy | B2, Alchemist's apparatus | The potion in the bar rises to the top by the end of the cast |

Final-draft tweaks (2026-10-09):

| Look | Change |
| --- | --- |
| Skinning C2 | Natural flesh side under the roll: creamy, lumpy fat thinning to red meat, a thin membrane, moist sheen (no veins) |
| Lightning A2 | Grey cauliflower storm cloud after a reference photo; no bolt lines, lightning only flashes inside the cloud |
| Blacksmithing A | The hammer painted as forged steel lit by the forge (no outline, no gem) |
| Alchemy B2 | The potion pours in, spreads with a rounded front, sloshes and rises with ripples and bubbles until it brims |
| Skinning C2 (again) | Marbled ribeye flesh (wine-red muscle laced with cream fat, fat cap at the edges); the blood animation is replaced by splatter flung off the cut that lands across the bar's top and bottom edge lines |
| Lightning | Back to the original pick, A (Thunderhead); A2 stays in the file (`?all`) |
| Smelting B2 | Thick, slow molten steel: heaps where the stream lands, slumps and creeps with a fat glowing front, the skin wrinkles and crusts as it cools, rising until it fills the bar |
| Lightning | Now A3, Thunderhead, cumulus: A's bolts, flashes and blues with heaped cumulus clouds (A and A2 kept, `?all`) |
| Lightning A3 | Clouds stretched wider: each puff drawn 1.7x wider than tall, towers and gaps widened to match |
| Skinning C2 | Painted fur pelt and fur roll with a spiral end, a steel skinning knife with a wood or antler handle (no outlines) |
| Lightning A3 | Now "Thunderhead, layered": four depths of wide cloud banks with broad swelling tops and flat dark undersides |
| Smelting B3 | New: back to the hand-ladle pour, painted as sooty, heat-tinted iron, pouring B2's thick, slow metal |
| Smelting D | New: Foundry line, a shuffled smelting works (furnace, bellows, hopper, crucible, sluice, moulds, quench trough, ladle) the metal runs through into the bar |
| Skinning C2 | Knife moved to the roll's left, slicing under it; the edge splatter is replaced by a glossy pool of blood that grows behind the knife |
| Skinning C2 | Knife flipped (tip on the meat pointing back, handle up over the roll); "C2 alt" has it upside down instead, to pick from; the pelt cycles through eight furs, one per cast (bear, wolf, tawny cat, red fox, arctic white, black bear, nightsaber, boar) |

Settled (2026-10-09): **Skinning C2** (knife pointing back over the cut, handle over the roll; the upside-down alternative dropped), **Alchemy B2**, **Blacksmithing A** (hammer painted in the skinning knife's style) and **Smelting A3** (A's pour from B3's forged hand ladle).
| Smelting | Now A2, Ladle pour, foundry: A's pour at the cast edge and cooling metal, from B2's cast-iron foundry ladle on a crane that rides the cast edge (B3 and D kept, `?all`) |
| Smelting | Now A3, Ladle pour, forged: A's pour at the cast edge and cooling metal, from B3's sooty forged hand ladle (A2's foundry version kept, `?all`) |
| Skinning C2 | Knife upright beside the roll, parallel to its edge with the blade's edge against it, sawing up and down |
| Smelting A3 | Ladle scaled down to about two-thirds (radius .38 bar heights, was .56), stream thinner to match |
| Lightning A3 | Curvier, slightly narrower clouds: 2–6.5 bar heights long, scalloped rounded billows, gently bulging undersides, rounded ends |

Rule (2026-10-09): profession and gathering looks (fishing, herbalism, mining, skinning, smelting, blacksmithing, alchemy) get no leading-edge spark; the look's own motion shows progress. Spell looks (damage, healing, utility) keep the spark, coloured to match the look.

New concepts (2026-10-09), three variants each, waiting for picks: **Tailoring** (A shuttle and reed, B cloth beam, C embroidery hoop), **Enchanting** (A disenchant siphon, B enchanting rod, C vortex siphon), **Leatherworking** (A saddle-stitched seam, B laced panels, C tooled strap). Open `index.html?only=tail,ench,lw`.

Picked (2026-10-09): **Tailoring C** (smaller hoop, five patterns cycling), **Enchanting C** with its flipped **C2 for Disenchant**, **Leatherworking B** (no awl dropping in; holes already punched). Edges: the add-on's ragged "borderless" style was removed; every bar is framed with clean edges.

Later (2026-10-09): **Leatherworking B** panels are tooled, a pattern per cast in turn (basket-weave, scrolling vine, diamond lattice, bordered shells, knotwork band; `&tooling=0..4` starts from one). **Tailoring A** got three smaller, plainer variants, waiting for a pick: A2 (small worn boat shuttle and a slim reed), A3 (flat stick shuttle and a hardwood batten), A4 (no shuttle; the weft laid down the shed, the reed packs it). `index.html?only=lw-b,tail-a,tail-a2,tail-a3,tail-a4`.

Smelting A3 (2026-10-09): the ladle lost its handle; only the forged bowl rides the cast edge, pouring.

Enchanting (2026-10-09): **C** is the Enchant look; **C3** is the Disenchant look (C2 retired to `?all`): the bar starts solid with magic, the vortex comes in from the right end and moves left, drawing the magic out of the solid part ahead of it and throwing it out behind as C2's dust and essence motes, which settle on C2's spent cloth.

Lightning A3 (2026-10-09): the weather changes every cast, in turn (`&weather=0..4` starts from one): layered, towering (stacked billows, thicker), scattered (fewer banks, more sky between short clouds), overcast (long flat banks, little sky), ragged squall (torn edges, wisps, fast drift). Each weather sets which banks there are, cloud lengths and gaps, thickness, a slight tint, drift speed and direction (some banks drift backwards), how the billows stack into towers, and faint stray rows between the banks.

`shape.html` (2026-10-09): a preview of corner and depth options for the bar, on a sample of each look: corners square / soft (now) / rounded / pill, depth flat (now) / bevel / slab / tilted, framed or borderless, with a depth-amount slider. Picked (2026-10-09): corners square / soft / rounded and depth flat / bevel go into the add-on as options; pill, slab and tilted were dropped (the page now shows only the picks).

`clouds.html` (2026-10-09): a contact sheet of the lightning cloud variants, to pick from by key. Keys → textures: **Layered 1–4** = `storm_bank1..4` (the approved layered set, far to near), **Tower 1–4** = `storm_tower1..4`, **Ragged 1–4** = `storm_ragged1..4`, **Overcast 1–4** = `storm_over1..4` (each over the sky at its own height, bar heights 36 and 56; PNG copies in `clouds/`). **Weather 0–4** = the game's weathers as composed (preview page iframes, hold 70): 0 layered (Layered 1–4), 1 towering (Tower 1–4), 2 scattered (Ragged 2–4), 3 overcast (Overcast 1–4), 4 ragged squall (Ragged 1, 3, 4); the concept's five weathers are shown under them for reference. `?preview=<path>` points it at another built preview page.

Confirmed for the add-on (2026-10-09): **Tailoring A2** (replaces C as the tailoring pick; C stays in `?all`), **Leatherworking B** with its tooling, **Enchanting C** for enchanting casts, **Enchanting C3** for Disenchant, and **Lightning A3** Thunderhead, layered, with the per-cast weathers ("PERFECT").
