# WoW Addon Kit

A Claude Code plugin (`wow-forever-addons`) for creating, setting up, testing and releasing World of Warcraft addons for **WoW: Forever** (and Retail/Midnight and Classic).

All API knowledge comes from Blizzard's own client source and your installed client, not from memory. See `plugins/wow-forever-addons/skills/wow-forever-api/sources.md`.

## Install

```powershell
claude plugin marketplace add "C:\Users\David\Documents\wow-addon-kit"
claude plugin install wow-forever-addons@wow-addon-kit
```

After editing the plugin, bump `version` in `plugins/wow-forever-addons/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then run `claude plugin marketplace update wow-addon-kit` and `claude plugin update wow-forever-addons@wow-addon-kit`.

## Skills (slash commands)

| Command | What it does |
| --- | --- |
| `/wow-forever-addons:wow-addon-new [Name] [idea]` | Scaffold an addon (TOC, events, SavedVariables, slash command, Settings panel), validate it, link it into the game |
| `/wow-forever-addons:wow-addon-test [folder]` | Validate against the real Forever API, run the advisor code review (fixes wait for your approval), then walk through the in-game test checklist |
| `/wow-forever-addons:wow-addon-setup` | Find the game and Interface numbers, install luacheck and the API index, link/unlink addons (one, or every addon in the repo after a clone or pull) |
| `/wow-forever-addons:wow-addon-release [folder] [version]` | Version bump, clean zip, BigWigsMods/packager setup |
| `wow-forever-api` (loaded automatically) | Forever facts, secret values, restrictions, removed-API table, Settings API |
| `@agent-wow-forever-addons:wow-addon-reviewer` | Advisor-mode code review for Forever/Midnight compatibility, taint and performance: numbered findings and proposed fixes, never edits. Runs automatically from `wow-addon-test` and `wow-addon-new` |

## Scripts (usable without Claude)

Windows PowerShell 5.1, no admin needed. Run them from `plugins/wow-forever-addons/scripts`:

| Script | Purpose |
| --- | --- |
| `Find-WowInstall.ps1` | Lists installed clients with build, TOC Interface number and AddOns path (reads `.build.info`) |
| `New-WowAddon.ps1 -Name X [-Flavor forever,retail]` | Scaffold from `templates/addon` |
| `Test-WowAddon.ps1 -Path X [-Flavor ...] [-Json]` | Static validator; exit code 1 on errors |
| `Find-WowApi.ps1 <name or pattern> [-Events] [-SecretOnly]` | Look up functions/events in the Forever API index |
| `Deploy-WowAddon.ps1 -Path X [-Mode Link/Copy] [-Remove]` | Junction or copy into `Interface\AddOns`; never deletes real folders |
| `Link-WowAddons.ps1 [-Path dir] [-Flavor ...] [-Remove] [-WhatIf]` | After cloning or pulling: links every addon in `wowaddons/` into each client its TOC targets; real folders go to `AddOns.backup`. Also runs under PowerShell 7 on macOS (symlinks) |
| `link-wow-addons.sh [--dry-run] [--remove] [--wow-root DIR] [dir]` | The same for a Mac without PowerShell (bash, symlinks, every addon into every client) |
| `Install-WowDevTools.ps1` | luacheck from its official GitHub release, plus the API index |
| `Update-WowApiIndex.ps1 [-Branch forever]` | Rebuild `data/api-<branch>.json` from Blizzard's UI source (after patches) |

Self-test: `plugins/wow-forever-addons/tests/Invoke-KitSelfTest.ps1` checks that every planted bug in `tests/fixtures/BrokenAddon` is caught, that a fresh scaffold and the example come out clean, and that `Link-WowAddons.ps1` links, re-points, backs up and unlinks correctly in a fake install.

## Example addon

`examples/HelloForever`: a movable character panel (name, level, zone, gold, health bar) built with the scaffold. It shows the secret-value-safe patterns for Forever. It's linked into the Forever client's AddOns folder (`_classic_beta_`); restart the client, enable it, and type `/hf`.

## What the validator checks

TOC name, Interface currency per flavor, missing or wrong-case files, `[Family]`/`[Game]` and `AllowLoadGameType` handling, XML includes, unloaded Lua files, unknown `C_` namespaces/functions, globals removed or moved into `C_` namespaces, deprecation-shim calls, unknown events, `COMBAT_LOG_EVENT_UNFILTERED` (errors on 12.x/Forever), comparisons/math/concatenation on secret values, slash-command wiring, unused SavedVariables, addon-comms lockdown, and luacheck (syntax, accidental globals, unused locals).
