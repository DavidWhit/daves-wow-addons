# Dave's WoW Addons

World of Warcraft addons for **WoW: Forever** (Interface 16001), plus the Claude Code tooling used to build them.

## Contents

| Folder | What it is |
| --- | --- |
| [`wowaddons/daves_balls`](wowaddons/daves_balls) | **Dave's Balls**: Diablo-style health and power orbs (v0.1.0) |
| [`wowaddons/daves_sack`](wowaddons/daves_sack) | **Dave's Sack**: an all-in-one bag with categories, search and quality borders (v1.7.5) |
| [`wow-addon-kit`](wow-addon-kit) | Claude Code plugin (`wow-forever-addons`) for scaffolding, testing, reviewing and releasing addons, plus a `HelloForever` example |

## Installing an addon

Copy (or junction-link) an addon folder from `wowaddons/` into your game's AddOns folder, e.g.:

```
<WoW install>\_forever_\Interface\AddOns\daves_sack
```

The `wow-addon-setup` skill / scripts in `wow-addon-kit` can find the folder and create the link for you.

## Using the addon kit

```powershell
claude plugin marketplace add ".\wow-addon-kit"
claude plugin install wow-forever-addons@wow-addon-kit
```

See [`wow-addon-kit/README.md`](wow-addon-kit/README.md) for the full list of skills and scripts.
