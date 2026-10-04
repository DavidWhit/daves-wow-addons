# Dave's WoW Addons

World of Warcraft addons for **WoW: Forever** (Interface 16001), plus the Claude Code tooling used to build them.

## Contents

| Folder | What it is |
| --- | --- |
| [`wowaddons/daves_balls`](wowaddons/daves_balls) | **Dave's Balls**: Diablo-style health and power orbs (v0.1.3) |
| [`wowaddons/daves_sack`](wowaddons/daves_sack) | **Dave's Sack**: an all-in-one bag with categories, search and quality borders (v1.7.6) |
| [`wowaddons/daves_castbar`](wowaddons/daves_castbar) | **Dave's Cast Bar**: an animated elemental cast bar (frost, fire, shadow, nature, arcane, holy), different every cast (v0.1.4) |
| [`wow-addon-kit`](wow-addon-kit) | Claude Code plugin (`wow-forever-addons`) for scaffolding, testing, reviewing and releasing addons, plus a `HelloForever` example |

## After cloning (or pulling)

Link every addon in `wowaddons/` into the game, so it loads straight from the repo. Run from the repo root; re-run after a pull that adds an addon (existing links are left alone).

Windows (PowerShell, no admin needed; makes junctions):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\wow-addon-kit\plugins\wow-forever-addons\scripts\Link-WowAddons.ps1
```

Mac (makes symlinks; looks for the game in `/Applications/World of Warcraft`, override with `--wow-root` or `WOW_ROOT`):

```sh
bash wow-addon-kit/plugins/wow-forever-addons/scripts/link-wow-addons.sh
```

Add `-WhatIf` (Windows) or `--dry-run` (Mac) to preview, and `-Remove` / `--remove` to unlink. An existing real folder with the same name is moved to `Interface/AddOns.backup/` first. Then fully restart the game once and enable the addons.

## Installing an addon without the repo

Copy an addon folder from `wowaddons/` into your game's AddOns folder, e.g.:

```
<WoW install>\_forever_\Interface\AddOns\daves_sack
```

## Using the addon kit

```powershell
claude plugin marketplace add ".\wow-addon-kit"
claude plugin install wow-forever-addons@wow-addon-kit
```

See [`wow-addon-kit/README.md`](wow-addon-kit/README.md) for the full list of skills and scripts.
