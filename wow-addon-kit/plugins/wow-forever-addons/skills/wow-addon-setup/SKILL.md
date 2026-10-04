---
name: wow-addon-setup
description: Set up a Windows (or Mac) machine for WoW Forever addon development - find the WoW install and every client folder with its Interface number, install luacheck and the Blizzard API index from official sources, link one addon or every addon in the repo into the game's AddOns folders (junction on Windows, symlink on Mac), and recommend editor tooling. Use when the user is getting started, has just cloned or pulled the addons repo, can't find their AddOns folder, needs the current Interface number, or wants to install, link, unlink or deploy an addon.
argument-hint: "[find | tools | link-all | link <folder> | unlink <folder> | refresh-api]"
---

# WoW addon dev environment

Arguments: `$ARGUMENTS`. With none, do the full setup (1 → 3, then 5).

All scripts are Windows PowerShell 5.1 and need no admin rights. Run them as:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/<Script>.ps1" <args>
```

On a Mac only linking is supported: `Link-WowAddons.ps1` and `Find-WowInstall.ps1` run under PowerShell 7 (`pwsh -File ...`), and `link-wow-addons.sh` needs nothing but bash. The game is looked for at `/Applications/World of Warcraft`.

## 1. Find the game (`find`)

`Find-WowInstall.ps1` lists every installed client with its build and TOC Interface number. It reads Blizzard's `.build.info` and `.flavor.info`, so the numbers are the installed build's own. Example output on the Forever beta:

```
Folder         Flavor  Product          Version      Interface AddOns
_classic_beta_ forever wow_classic_beta 1.60.1.70205     16001 C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns
```

The Forever beta installs as `_classic_beta_`. The launch folder name isn't confirmed yet, so always detect it rather than hard-coding it. If the game isn't found, ask for the install path and pass `-Root`.

## 2. Install tools (`tools`)

`Install-WowDevTools.ps1`:
- **luacheck v1.2.0**, from the official lunarmodules/luacheck GitHub release. Goes to `%LOCALAPPDATA%\wow-addon-kit\bin\luacheck.exe`; the size is checked against the release asset and the SHA256 is printed. PATH is unchanged.
- **API index** for Forever (`Update-WowApiIndex.ps1 -Branch forever`), built from Blizzard's UI source (Gethe/wow-ui-source). Skipped if it is less than 7 days old.
- Prints the optional VS Code extension command: `code --install-extension ketho.wow-api`.

`refresh-api`: after a game patch, run `Update-WowApiIndex.ps1 -Branch forever` to rebuild the index. Other branches: `live` (Retail), `classic_era`, `classic`, `classic_anniversary`, `classic_titan`.

## 3. Link every addon after cloning or pulling (`link-all`)

Use this on a fresh clone of the addons repo, and after a pull that added addons. `Link-WowAddons.ps1` links every folder in the repo's `wowaddons/` that holds a `<Folder>.toc` (or `<Folder>_<Flavor>.toc`) into each installed client whose game the TOC's `## Interface` lists: a junction on Windows, a symlink on a Mac. Run `-WhatIf` first and show the user the table.

```powershell
Link-WowAddons.ps1 -WhatIf                 # what would change
Link-WowAddons.ps1                         # link everything (finds wowaddons/ by walking up from the current folder)
Link-WowAddons.ps1 -Path "<addons folder>" -Flavor forever   # another folder; only the Forever client
Link-WowAddons.ps1 -Remove                 # unlink them all
```

On a Mac, from the repo root:

```sh
pwsh wow-addon-kit/plugins/wow-forever-addons/scripts/Link-WowAddons.ps1     # with PowerShell 7
bash wow-addon-kit/plugins/wow-forever-addons/scripts/link-wow-addons.sh     # without; --dry-run, --remove, --wow-root DIR
```

The shell script doesn't read TOCs: it links every addon into every `_*_` client folder. Both scripts leave a correct link alone, re-point a link that points elsewhere, and move a real folder to `Interface/AddOns.backup/<Name>-<timestamp>` before linking. `-Flavor all` links every addon into every client. When run from `${CLAUDE_PLUGIN_ROOT}` outside the repo, pass `-Path`.

## 4. Link one addon into the game (`link` / `unlink`)

```powershell
Deploy-WowAddon.ps1 -Path "<addon folder>" -Flavor forever               # junction: edits live after /reload
Deploy-WowAddon.ps1 -Path "<addon folder>" -Flavor forever -Mode Copy    # release-like copy without dev files
Deploy-WowAddon.ps1 -Path "<addon folder>" -Flavor forever -Remove       # unlink (never deletes your source)
```

Safety rules built into both link scripts, which you should keep when doing anything by hand:
- They never delete a real folder in `AddOns`. They move it to `Interface\AddOns.backup\<Name>-<timestamp>` (Deploy only with `-Force`).
- They remove junctions with a non-recursive delete, so the linked source folder is untouched. Never run `Remove-Item -Recurse` on a junction in PowerShell 5.1.
- They write into the game folder, so **confirm with the user first** unless they asked for it.

## 5. Check it worked

Run `Test-WowAddon.ps1` on the linked addon. Then tell the user to restart the client fully once (new TOC) and enable the addon in the AddOns list.
