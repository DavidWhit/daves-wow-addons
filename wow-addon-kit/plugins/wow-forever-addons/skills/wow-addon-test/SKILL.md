---
name: wow-addon-test
description: Test a World of Warcraft addon for WoW Forever - static validation against Blizzard's real Forever API (TOC, missing files, removed/moved APIs, unknown events, combat-log use, secret-value misuse, slash commands, luacheck), an advisor-mode code review whose fixes wait for the user's approval, plus an in-game test checklist (reload, script errors, taint log). Use after any addon change, when an addon is out of date or broken, when the game reports an error, "action blocked" or "only available to the Blizzard UI" (it reads the client's taint.log first), or when asked to check, lint, verify or debug a WoW addon.
argument-hint: "[addon folder] [flavors]"
---

# Test a WoW addon

Arguments: `$ARGUMENTS` (addon folder and optional flavors, e.g. `C:\dev\CampTracker forever,retail`). Without a folder, use the addon you're working on, or ask.

## 0. Bug reports: start from the game's own evidence

When the user reports something going wrong in game ("action blocked", "only available to the Blizzard UI", an error, odd behaviour), read what the client recorded **before** reading addon code or forming a theory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:/Users/David/Documents/daves-wow-addons/wow-addon-kit/plugins/wow-forever-addons/scripts/Get-WowTaintLog.ps1" -Addon <addon folder name>
```

Then work from the root cause outward:
1. Take the `Execution tainted by <addon> while reading <X>` line. That's where taint entered Blizzard code, not the blocked call after it.
2. Open each stack `Interface/...:line` in the local UI source (`data/ui-source/forever/`; look names up in its `INDEX.tsv`). Follow the branch the code actually took. In this session's daves_sack case, the stack showed the vendor branch, so a vendor window was open.
3. Find who wrote `<X>`. If Blizzard wrote it moments earlier in the same call, the taint came in before that: list the state that call path reads, then find which of it the addon touches (calling Blizzard functions from addon code, hooks, `SetScript`/`HookScript` on Blizzard frames, fields written on template frames).
4. Only then search the addon for the write, and fix it there.

No log, or nothing for this addon: ask the user to run `/console taintLog 1`, reproduce, `/reload`, then re-run the script. Note the log's timestamp, so you don't chase old events.

## 1. Static validation (always)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Test-WowAddon.ps1" -Path "<addon folder>" -Flavor forever[,retail,classic_era]
```

Add `-Json` for machine-readable output. The exit code is 1 when there are errors.

What each rule means and how to fix it:

| Rule | Severity | Fix |
| --- | --- | --- |
| `toc-name` | error | Rename the TOC to `<Folder>.toc` (or `<Folder>_Camelot.toc`) |
| `toc-interface` / `toc-flavor` | error/warn | Put the number `Find-WowInstall.ps1` reports (Forever: 16001) in `## Interface:` |
| `toc-missing-file` / `xml-missing-file` | error | Fix the path or add the file. `[Family]` is Mainline and `[Game]` is Camelot on Forever |
| `file-case` | warn | Match case exactly (macOS clients are case-sensitive) |
| `unloaded-file` | warn | Add the file to the TOC, or delete it |
| `cleu-removed` | error | Combat log isn't available on 12.x/Forever. Redesign around unit events and widget setters |
| `unknown-event` | error | The event doesn't exist on this client. Look it up: `Find-WowApi.ps1 <part> -Events` |
| `unknown-namespace` / `unknown-function` | error/warn | Look it up with `Find-WowApi.ps1`. Feature-detect (`C_X and C_X.Fn`) if it's flavor-specific |
| `moved-api` | warn | Use the `C_*` replacement it names, with a fallback if you also target Classic |
| `unknown-global` | warn | The global doesn't exist on Forever (e.g. `UnitAura`). Use the suggested replacement |
| `deprecated-api` | warn | Only Blizzard's deprecation shim provides it, and it will be removed. Migrate now |
| `secret-value` | warn | Don't compare, do math on or concatenate the value. Pass it to `SetValue`/`SetText`/`SetFormattedText`, or check `issecretvalue()` |
| `slash-handler` | error | Assign `SlashCmdList["NAME"]` for every `SLASH_NAME1` |
| `savedvariables-unused` | warn | Use it, or drop it from the TOC |
| `editmode-dialog` | error/warn | Error: the addon joins Edit Mode but has no `EditModeDialog.lua`. Copy the kit's `templates/editmode/EditModeDialog.lua` in, list it after `Core.lua`. Warn: the copy was edited. Restore the kit's version and make the change in the kit instead |
| `editmode-snap` | error/warn | Error: hand-rolled grid snapping (`gridSpacing`, `IsSnapEnabled`, `EditModeMagnetismManager`). Warn: a frame dragged without the kit's snapping. Use `ns.EditMode.Attach`, or `ns.EditMode.SnapRect` / `SnapEdge` in the drag's OnUpdate, so it snaps like Blizzard's frames |
| `editmode-ui` | error | A hand-built panel, slider or checkbox in an Edit Mode addon. Rebuild it with `ns.EditMode.CreateDialog` (see the **wow-forever-api** skill). For a window that isn't Edit Mode settings (a bag window, say), end the line with `-- editmode-ui: ok` |
| `luacheck-E*` | error | Lua syntax error. The game would refuse to load the whole file |
| `luacheck-W111/112` | warn | Accidental global: add `local`, or declare it in `.luacheckrc` `globals` if intentional |
| `luacheck-W211/212/431...` | warn | Unused or shadowed locals. Tidy up |

Fix errors first, re-run until clean, then fix warnings. Info notes are context; for example, "feature-detected, OK" means the code already guards the call.

If it says the API index or luacheck is missing, run `scripts/Install-WowDevTools.ps1` (see the **wow-addon-setup** skill).

## 2. Code review (always, advisor mode)

The validator only catches what static rules can see. After it runs, launch the reviewer agent with the Agent tool, `subagent_type: "wow-forever-addons:wow-addon-reviewer"`. Give it the addon folder, the flavors, and what changed this session.

The reviewer is read-only and returns numbered findings with proposed fixes. Then:

1. Show the user the findings: the numbered list, the recommendation and any questions. Keep them verbatim or tightly condensed, and never drop a finding.
2. **Stop and wait for the user's answer.** Don't apply any reviewer finding until the user says which ones to apply ("apply 1, 3", "all", "none").
3. Apply exactly what they approved, re-run step 1, and say what changed.

Fixing the validator's own errors in step 1 doesn't need to wait. Design changes, behaviour trade-offs and anything marked suspect always do.

## 3. In-game test (tell the user these steps; you can't run the client)

1. **First load / TOC or new-file changes:** fully restart the client. Otherwise `/reload`.
2. At character select, open **AddOns**: the addon should be listed and not marked "out of date".
3. In game, turn on errors: `/console scriptErrors 1`. Optionally install BugSack + BugGrabber to collect them.
4. Exercise every feature, then repeat **in combat and in an instance**. For an Edit Mode addon, open Edit Mode and click each of its frames, plus one of Blizzard's: only one settings dialog should be open at a time, none should cover its frame or Edit Mode's window, every number should sit inside the dialog at its widest value, and Escape should close it. With Snap ticked, drag each frame slowly past grid lines, the screen centre and a Blizzard frame. It should move freely and pull on only within a few pixels, the same as Blizzard's own frames. For a cast bar, check a channel (e.g. Blizzard) ending normally in combat: it must not show as interrupted. Secret values and addon-comms lockdown only show up there.
5. Taint: `/console taintLog 1`, reproduce, `/reload`, then read `Logs\taint.log` in the client folder (e.g. `_classic_beta_\Logs`). Lines naming the addon mean it touched secure code.
6. Useful commands: `/dump <expr>` prints a value, `/fstack` identifies the frame under the mouse, `/etrace` shows live events, `/run <lua>` runs a line.

When the user pastes an error, find the file:line, explain the cause in one sentence, fix it, and re-run step 1.

## 4. Report

Say what was checked (flavors, API commit shown in the first line of output), the error/warning counts before and after, which reviewer findings were applied, skipped or are still waiting on the user, and which in-game steps still need the user.
