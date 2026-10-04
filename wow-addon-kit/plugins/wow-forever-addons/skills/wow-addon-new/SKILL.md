---
name: wow-addon-new
description: Create a new World of Warcraft addon for WoW Forever (and optionally Retail/Classic) from a tested template - TOC with the right Interface numbers, events, SavedVariables, slash command, Settings panel, luacheck/packager/VS Code config - then validate it and link it into the game. Use when the user wants to start, scaffold, create or set up a new WoW addon.
argument-hint: "[AddonName] [what it should do]"
---

# Create a new WoW: Forever addon

Arguments: `$ARGUMENTS` (addon name and/or what it should do; may be empty).

## 1. Settle the basics (ask only for what's missing)

- **Name**: a folder-safe identifier (`CampTracker`, letters/digits/underscore, starts with a letter). WoW only loads a TOC whose name matches its folder.
- **Flavors**: default `forever`. Add `retail` (Midnight) and `classic_era` only if the user wants them. `forever` and `retail` share one API; `classic_era` needs feature-detected fallbacks.
- **Where**: default to a dev folder such as `%USERPROFILE%\Documents\WowAddons\`, not straight into the game folder. The deploy step links it in.
- **Slash command**: default is the lowercased name.

## 2. Scaffold

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/New-WowAddon.ps1" `
  -Name <Name> -OutDir "<dev folder>" -Flavor forever[,retail,classic_era] `
  -Notes "<one line>" -Author "<author>" [-Slash <cmd>]
```

The script reads the Interface number from the installed client (`.build.info`), so a patched client gets the right number. Then it runs the validator; expect `0 error(s), 0 warning(s)`.

You get:

| File | Purpose |
| --- | --- |
| `<Name>.toc` | Interface list, Title, Notes, Version, SavedVariables `<Name>DB`, Addon Compartment hook |
| `Core.lua` | `local ADDON, ns = ...` namespace, `ns:EVENT()` dispatch, defaults merged into SavedVariables on `ADDON_LOADED`, slash command, `ns.IS_FOREVER` |
| `Options.lua` | Blizzard Settings panel (checkbox and slider), `ns:OpenOptions()` |
| `.luacheckrc`, `.pkgmeta`, `.vscode/settings.json`, `.gitignore`, `README.md` | Lint, packaging and editor config |

## 3. Build the feature

- Load the **wow-forever-api** skill before writing feature code, and check every API you use with `Find-WowApi.ps1`. Don't trust memory: many classic globals are gone on Forever.
- New Lua files go in the TOC, in load order. Keep everything `local` and hang shared things off `ns`.
- Add new events with `ns.events:RegisterEvent("EVENT")` and handle them with `function ns:EVENT(...)`.
- Feed values that may be secret (health, power, auras, unit identity) straight into widget setters. Don't compare them or do math on them.
- `examples/HelloForever` in the kit repo is a complete worked example (panel, events, secret-safe health bar).

### On Windows: PowerShell traps

The kit runs on Windows PowerShell 5.1. Watch for these when writing helper scripts, such as ones that generate `.tga` art:

- **Variable names ignore case, and script blocks see the caller's variables.** `$R` (a radius) and `$r` (a red channel set inside the function that runs the block) are the same variable. This silently broke a texture generator. Give constants distinctive names (`$ORB_R`).
- **`[math]::Max(0, $x)` / `[math]::Min(1, $x)` with whole-number literals pick the integer overload** and truncate doubles to 0 or 1. Write `0.0` and `1.0`.
- **Casts bind tighter than arithmetic:** `[int]($a)*255` is `([int]$a)*255`. Write `[int]($a*255)`.
- **Arrays don't pass through `powershell -File`:** `-Color 0.7,0.1,0.1` arrives as one string. Call the script with `& script.ps1 -Color @(0.7,0.1,0.1)` instead.
- **`Get-ChildItem -LiteralPath <dir> -Recurse -Include *.lua` silently ignores `-Include`** and returns every file. A bulk find-and-replace built on it once rewrote every `.tga` as text and corrupted all of an addon's art. Filter with `Where-Object { $_.Extension -in '.lua','.toc' }`, never run text edits on binary files, and back up first.
- **Deletes:** use `Remove-Item -LiteralPath "<full path>"`. A path built from variables inside a long command can be refused by the sandbox as a system path.
- **Encoding:** `Set-Content`/`Add-Content` default to ANSI. Write addon files (`.lua`, `.toc`, `.xml`) with the Write/Edit tools, or pass `-Encoding utf8`.
- **No Python by default.** Use `System.Drawing` (`Add-Type -AssemblyName System.Drawing`) for image previews. It can't read `.tga`, so decode the 18-byte header and BGRA pixels yourself.
- **Check art before asking for a restart:** render a quick PNG composite of the layers and look at it. New or changed textures need a full client restart, so each art round-trip costs the user a restart.

## 4. Validate, then put it in the game

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Test-WowAddon.ps1" -Path "<addon folder>" -Flavor forever
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Deploy-WowAddon.ps1" -Path "<addon folder>" -Flavor forever
```

Deploy creates a junction in the client's `Interface\AddOns`, so later edits are live after `/reload`. It refuses to replace a real folder unless given `-Force`, and then it moves that folder to `AddOns.backup` first. **Ask before deploying** if the user didn't request it, since it writes into the game folder.

## 5. Tell the user

- Where the addon lives, and that it's linked into the game (or how to link it).
- How to try it: fully restart the client the first time (new TOC), enable it in the AddOns list, then use `/<slash>`.
- Next step: describe the feature, then run `/wow-forever-addons:wow-addon-test` after changes.
