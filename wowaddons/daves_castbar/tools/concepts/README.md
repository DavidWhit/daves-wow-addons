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
