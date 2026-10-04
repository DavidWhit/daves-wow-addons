---
name: wow-addon-new
description: Create a new World of Warcraft addon for WoW Forever (and optionally Retail/Classic) from a tested template - TOC with the right Interface numbers, events, SavedVariables, slash command, Settings panel, luacheck/packager/VS Code config - then validate it and link it into the game. Use when the user wants to start, scaffold, create or set up a new WoW addon.
argument-hint: "[AddonName] [what it should do]"
---

# Create a new WoW: Forever addon

Arguments: `$ARGUMENTS` (addon name and/or what it should do; may be empty).

## 1. Settle the basics (ask only for what's missing)

Take what you can from `$ARGUMENTS` and the conversation. Ask for the rest with the **AskUserQuestion** tool, not a free-text message: up to 4 questions per call, 2-4 options each, the default first and labelled "(recommended)". The user can always pick "Other" and type their own answer. Ask in dependency order: purpose before name, and name before slash command and icon. With no arguments that is two calls: purpose, flavors, where and link first, then name, slash command and icon.

| Question | Options (first is the default) |
| --- | --- |
| **What it does** (only if unknown) | 3-4 common kinds, e.g. unit frames or health bars / bags and inventory / cast bar or action bar tweak / tracker or info panel |
| **Name** | 2-3 names in the style of the addons already in the repo's `wowaddons/` (`daves_balls`, `daves_sack`: `daves_<thing>`), based on the purpose. Skip any that already exist |
| **Flavors** | Forever only (recommended) / Forever + Retail / Forever + Retail + Classic Era |
| **Where** | The repo's `wowaddons/` folder (recommended) / Another folder |
| **Slash command** | `/<lowercased name>` (recommended) / a short custom one such as `/<abbreviation>` |
| **Icon** | 2-3 stock `Interface\Icons\...` icons that fit (orbs → `Spell_Priest_ShadowOrbs`, bags → `INV_Misc_Bag_08`, maps → `INV_Misc_Map_01`) |
| **Link it into the game afterwards?** | Yes, link it (recommended) / No |

If the user says "use defaults" (or skips), take the first option of each and don't ask again. With no purpose at all, scaffold the plain template as `daves_newaddon`. A "Yes" to linking is the go-ahead for the link step in step 4.

Rules behind the answers:
- **Name**: folder-safe (letters, digits, underscore; starts with a letter). WoW only loads a TOC whose name matches its folder.
- **Flavors**: `forever` and `retail` share one API; `classic_era` needs feature-detected fallbacks.
- **Where**: the repo's `wowaddons/` is the nearest one walking up from the current folder. Outside the repo, use a dev folder such as `%USERPROFILE%\Documents\WowAddons\`. Never scaffold straight into the game folder; step 4 links it in.
- **Icon**: always settle it before scaffolding. It's the `## IconTexture` shown in the AddOns list and the minimap addon menu. Never ship the template's `INV_Misc_QuestionMark`; the validator warns about it.

## 2. Scaffold

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/New-WowAddon.ps1" `
  -Name <Name> -OutDir "<repo>\wowaddons, or the chosen folder>" -Flavor forever[,retail,classic_era] `
  -Notes "<one line>" -Author "<author>" -Icon <IconName> [-Slash <cmd>]
```

The script reads the Interface number from the installed client (`.build.info`), so a patched client gets the right number. Then it runs the validator; expect `0 error(s), 0 warning(s)`.

You get:

| File | Purpose |
| --- | --- |
| `<Name>.toc` | Interface list, Title, Notes, Version, IconTexture, SavedVariables `<Name>DB`, Addon Compartment hook |
| `Core.lua` | `local ADDON, ns = ...` namespace, `ns:EVENT()` dispatch, defaults merged into SavedVariables on `ADDON_LOADED`, version printed on `PLAYER_LOGIN`, slash command, `ns.IS_FOREVER` |
| `Options.lua` | Blizzard Settings panel (checkbox and slider), `ns:OpenOptions()` |
| `.luacheckrc`, `.pkgmeta`, `.vscode/settings.json`, `.gitignore`, `README.md` | Lint, packaging and editor config |

## 3. Build the feature

- Load the **wow-forever-api** skill before writing feature code, and check every API you use with `Find-WowApi.ps1`. Don't trust memory: many classic globals are gone on Forever.
- Keep the version announcement: `ns.VERSION` comes from `## Version`, and `ns:PLAYER_LOGIN()` prints `v<version> loaded`. `PLAYER_LOGIN` also fires on `/reload`, so every reload shows which build is running. Bump `## Version` with every change the user will test, so a stale build is obvious. The validator warns (`load-version`) if the addon never reads its version.
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
- **PowerShell finds .NET members without regard to case.** In an `Add-Type` C# class, a method `Glyphs()` next to a field `glyphs` or a constant `GLYPHS` fails with "does not contain a method named 'Glyphs'". Give members names that differ by more than case. Also, a type added by `Add-Type` stays loaded for the whole session, so after changing the C#, run the script in a fresh `powershell -File` process.
- **No Python by default.** Use `System.Drawing` (`Add-Type -AssemblyName System.Drawing`) for image previews. It can't read `.tga`, so decode the 18-byte header and BGRA pixels yourself.
- **Check art before asking for a restart:** render a quick PNG composite of the layers and look at it. New or changed textures need a full client restart, so each art round-trip costs the user a restart.

## 4. Validate and review, then put it in the game

Once the feature code is written, run the **wow-addon-test** skill on the addon, not just the validator script. It runs the validator and then the **wow-addon-reviewer** agent in advisor mode. Show the user the reviewer's numbered findings and **wait for them to choose** which to apply before changing anything. Deploy only after that round is settled.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Link-WowAddons.ps1" -Path "<addon folder>"
```

This links the addon into every installed client its TOC targets (so a Forever + Retail addon lands in both): a junction in each client's `Interface\AddOns`, so later edits are live after `/reload`. A real folder of the same name is moved to `AddOns.backup` first. For one client only, use `Deploy-WowAddon.ps1 -Path "<addon folder>" -Flavor forever` instead (it refuses to replace a real folder without `-Force`). On a Mac, run the same script with `pwsh`, or `bash .../scripts/link-wow-addons.sh "<addon folder>"`. If the user answered "No" to linking, skip this and tell them the command. If linking was never asked, **ask first**, since it writes into the game folder.

## 5. Tell the user

- Where the addon lives, and that it's linked into the game (or how to link it).
- How to try it: fully restart the client the first time (new TOC), enable it in the AddOns list, then use `/<slash>`.
- What the review found, and which findings they approved, skipped or still need to decide.
- Next step: describe the feature. After each change, **wow-addon-test** runs again (validator plus advisor review).
