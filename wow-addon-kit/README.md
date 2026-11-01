# WoW Addon Kit

A Claude Code plugin (`wow-forever-addons`) for creating, setting up, testing and releasing World of Warcraft addons for **WoW: Forever** (and Retail/Midnight and Classic).

All API knowledge comes from Blizzard's own client source and your installed client, not from memory. See `plugins/wow-forever-addons/skills/wow-forever-api/sources.md`.

## Install

```powershell
# Run from the daves-wow-addons repo root:
claude plugin marketplace add ".\wow-addon-kit"
claude plugin install wow-forever-addons@wow-addon-kit
```

After editing the plugin, bump `version` in `plugins/wow-forever-addons/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then run `claude plugin marketplace update wow-addon-kit` and `claude plugin update wow-forever-addons@wow-addon-kit`.

## Skills (slash commands)

| Command | What it does |
| --- | --- |
| `/wow-forever-addons:wow-addon-new [Name] [idea]` | Scaffold an addon (TOC, events, SavedVariables, slash command, Settings panel), validate it, link it into the game |
| `/wow-forever-addons:wow-addon-test [folder]` | Build the `Prepare-WowReview.py` review packet (validator + diff + API/`NOTES.md` context), run the advisor code review (inline for small clean diffs or diff-scoped subagent; fixes wait for your approval), then walk through the in-game test checklist |
| `/wow-forever-addons:wow-addon-setup` | Find the game and Interface numbers, install luacheck and the API index, link/unlink addons (one, or every addon in the repo after a clone or pull) |
| `/wow-forever-addons:wow-addon-release [folder] [version]` | Version bump, clean zip, BigWigsMods/packager setup |
| `wow-forever-api` (loaded automatically) | Forever facts, secret values, restrictions, removed-API table, Settings API |
| `@agent-wow-forever-addons:wow-addon-reviewer` | Packet-driven (`Prepare-WowReview.py`), diff-scoped `sonnet` advisor review for Forever/Midnight compatibility, taint and performance: numbered findings and proposed fixes, never edits. Runs automatically from `wow-addon-test` and `wow-addon-new` |

## Scripts (usable without Claude)

On Windows, run them with `py -3` from `plugins/wow-forever-addons/scripts`. The PowerShell originals are still there. On macOS, link with `pwsh` on `Link-WowAddons.ps1`, or with `link-wow-addons.sh`:

| Script | Purpose |
| --- | --- |
| `Find-WowInstall.py` | Lists installed clients with build, TOC Interface number and AddOns path (reads `.build.info`) |
| `New-WowAddon.py -Name X [-Flavor forever,retail] [-EditMode]` | Scaffold from `templates/addon`; `-EditMode` adds the shared Edit Mode behaviour and an `EditMode.lua` wired up with it |
| `Test-WowAddon.py -Path X [-Flavor ...] [-NoInfo] [-Json]` | Static validator; exit code 1 on errors |
| `Prepare-WowReview.py -Path X [-Flavor ...] [-Full]` | One-shot pre-review packet: runs validator (`-NoInfo`), scopes `git diff` (skipping unmodified `EditModeDialog.lua`), extracts `NOTES.md` rules/skipped items, pre-annotates APIs/methods/events, and picks `inline` vs `subagent-diff` vs `subagent-full` |
| `Find-WowApi.py <pattern...> [-Events] [-Methods] [-SecretOnly] [-UiSource]` | Batch look up functions, `:WidgetMethods`, events, or branch-filtered `INDEX.tsv` definitions (`-UiSource`) |
| `Get-WowScriptErrors.py [-Addon X] [-Session n]` | Lua errors (with stacks), blocked/forbidden actions (each with a taint probe: what an addon wrote where the action read, via `issecurevariable`; `/wkprobe` runs it by hand) and Lua warnings recorded in game by the dev addon `devaddons/!WowKitErrors` (installed by every kit link: `Link-WowAddons.py`, `Deploy-WowAddon.py`, and by this script when it's missing). Read first when something breaks in game (the order: wow-addon-test step 0) |
| `Get-WowTaintLog.py [-Addon X]` | The client's `Logs\taint.log`: which addon tainted what, and the blocked call. Read when nothing was recorded, or when the taint probe names nothing. Reads the live log while the game runs (a `/reload` starts a new one) |
| `Deploy-WowAddon.py -Path X [-Mode Link/Copy] [-Remove]` | Junction or copy into `Interface\AddOns`; never deletes real folders |
| `Link-WowAddons.py [-Path dir] [-Flavor ...] [-Remove] [-NoDevAddons] [-WhatIf]` | After cloning or pulling: links every addon in `wowaddons/` into each client its TOC targets, plus the kit's error recorder; real folders go to `AddOns.backup`. On macOS use `pwsh` with `Link-WowAddons.ps1`, or the bash script below |
| `link-wow-addons.sh [--dry-run] [--remove] [--no-dev-addons] [--wow-root DIR] [dir]` | The same for a Mac without PowerShell (bash, symlinks, every addon into every client, error recorder included) |
| `Install-WowDevTools.py` | luacheck from its official GitHub release, plus the API index |
| `Update-WowApiIndex.py [-Branch forever] [-FromLocal]` | Rebuild `data/api-<branch>.json` from Blizzard's UI source (GitHub zip, or local `data/ui-source/<branch>` with `-FromLocal`) |

Self-test: `py -3 plugins/wow-forever-addons/tests/Invoke-KitSelfTest.py` checks that every planted bug in `tests/fixtures/BrokenAddon` is caught, that a fresh scaffold and the example come out clean, and that `Link-WowAddons.py` links, re-points, backs up and unlinks correctly in a fake install, error recorder included.

## Example addon

`examples/HelloForever`: a movable character panel (name, level, zone, gold, health bar) built with the scaffold. It shows the secret-value-safe patterns for Forever. It's linked into the Forever client's AddOns folder (`_classic_beta_`); restart the client, enable it, and type `/hf`.

## What the validator checks

TOC name, Interface currency per flavor, missing or wrong-case files, `[Family]`/`[Game]` and `AllowLoadGameType` handling, XML includes, unloaded Lua files, unknown `C_` namespaces/functions, globals removed or moved into `C_` namespaces, deprecation-shim calls, unknown events, `COMBAT_LOG_EVENT_UNFILTERED` (errors on 12.x/Forever), same-line and 1-hop local comparisons/math/concatenation/indexing on secret values (`secret-value`), secret values passed to `AllowedWhenUntainted`/`NotAllowed` APIs or widget methods (`secret-args`), direct state-tainting Blizzard UI calls (`taint-call`), raw global hook overwrites (`taint-hook`), unregistering events on Blizzard frames (`taint-unregister`), Lua's 200-local budget (`local-limit`), slash-command wiring, version announcement (`load-version`), unused SavedVariables, addon-comms lockdown, and luacheck (syntax, accidental globals, unused locals).

The Edit Mode rule: an addon that joins Edit Mode must ship `templates/editmode/EditModeDialog.lua` unchanged and build no settings windows, sliders, checkboxes or grid snapping of its own, must not put `SetScript("OnUpdate")` on an `EditMode.Attach`ed frame, and must open dialogs via `:OpenFor(frame)` rather than `:SetPoint` (rules `editmode-dialog`, `editmode-ui`, `editmode-snap`, `editmode-onupdate`, `editmode-openfor`).

## Edit Mode settings (shared by every addon)

`templates/editmode/EditModeDialog.lua` is the one Edit Mode behaviour for every addon frame placed in Edit Mode, modelled on Blizzard's own Edit Mode:
- **Outline:** Blizzard's blue/yellow outline.
- **Snapping:** magnetic, like Blizzard's frames. Within 8 px it pulls onto the grid, the screen edges and centre, and nearby Edit Mode frames.
- **Settings dialog:** labels and slider numbers are measured, so they always fit. Only one dialog is open at a time, across Blizzard's and every addon's. It opens beside its frame, clear of that frame and of Edit Mode's window, and steps aside if a setting moves the frame under it.

`ns.EditMode.Attach(frame, ...)` wires all of it up in one call. `New-WowAddon.py -EditMode` adds the file plus an `EditMode.lua` that uses `Attach`. The `wow-forever-api` skill documents the API. To change it, edit the kit's file, then copy it into every addon that has one (`wowaddons/daves_balls`, `wowaddons/daves_castbar`, `wowaddons/daves_chat`, `wowaddons/daves_frames`, `wowaddons/daves_outofmyway`). The validator warns about any copy that differs.
