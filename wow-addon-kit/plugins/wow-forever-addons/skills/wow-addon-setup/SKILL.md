---
name: wow-addon-setup
description: Set up a Windows (or Mac) machine for WoW Forever addon development - find the WoW: Forever install (_forever_) and its Interface number, install luacheck and the Blizzard API index from official sources, link one addon or every addon in the repo into the game's AddOns folder (junction on Windows, symlink on Mac), and recommend editor tooling. Use when the user is getting started, has just cloned or pulled the addons repo, can't find their AddOns folder, needs the current Interface number, or wants to install, link, unlink or deploy an addon.
argument-hint: "[find | tools | link-all | link <folder> | unlink <folder> | refresh-api]"
---

# WoW addon dev environment

Arguments: `$ARGUMENTS`. With none, do the full setup (1 → 3, then 5).

Run the Python 3 kit scripts (`py -3` on Windows, `python3` on macOS; no admin rights needed):

```powershell
py -3 "${CLAUDE_PLUGIN_ROOT}/scripts/<Script>.py" <args>
```

On macOS, the Python scripts (`Find-WowInstall.py`, `Link-WowAddons.py`, `Test-WowAddon.py`, `Find-WowApi.py`, `Prepare-WowReview.py`) look for `/Applications/World of Warcraft` and create symlinks natively, and `link-wow-addons.sh` provides a pure-bash linking fallback (`Install-WowDevTools.py` downloads a Windows `luacheck.exe`; on macOS install `luacheck` via Homebrew/LuaRocks).

## 1. Find the game (`find`)

`Find-WowInstall.py` finds the installed WoW: Forever client (`_forever_`) with its build and TOC Interface number. It reads Blizzard's `.build.info` and `.flavor.info`, so the numbers are the installed build's own. Example output on WoW: Forever:

```
Folder     Flavor  Product  Version      Interface AddOns
_forever_  forever wowf     1.60.1.70790     16001 C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns
```

WoW: Forever installs under `_forever_` (product `wowf`). Always detect the client path with `Find-WowInstall.py` rather than hard-coding it. If the game isn't found, ask for the install path and pass `-Root`.

## 2. Install tools (`tools`)

`Install-WowDevTools.py`:
- **luacheck v1.2.0**, from the official lunarmodules/luacheck GitHub release. Goes to `%LOCALAPPDATA%\wow-addon-kit\bin\luacheck.exe`; the size is checked against the release asset and the SHA256 is printed. PATH is unchanged.
- **API index** for Forever (`Update-WowApiIndex.py -Branch forever`), built from Blizzard's UI source (Gethe/wow-ui-source). Skipped if it is less than 7 days old.
- Prints the optional VS Code extension command: `code --install-extension ketho.wow-api`.

`refresh-api`: after a game patch, run `Update-WowUiSource.py` to refresh the local Blizzard UI source and its `INDEX.tsv`, then `Update-WowApiIndex.py -Branch forever -FromLocal` (or omit `-FromLocal` to fetch directly from GitHub).

## 3. Link every addon after cloning or pulling (`link-all`)

Use this on a fresh clone of the addons repo, and after a pull that added addons. `Link-WowAddons.py` links every folder in the repo's `wowaddons/` that holds a `<Folder>.toc` (or `<Folder>_Camelot.toc`) targeting Forever (`## Interface: 16001`) into `_forever_/Interface/AddOns`: a junction on Windows, a symlink on a Mac. Run `-WhatIf` first and show the user the table. Every run also links the kit's error recorder `devaddons/!WowKitErrors` into the same client (shown as "kit error recorder"), so in-game Lua errors and blocked actions are always on file for `Get-WowScriptErrors.py`. `-NoDevAddons` leaves it out.

```powershell
py -3 Link-WowAddons.py -WhatIf                 # what would change
py -3 Link-WowAddons.py                         # link everything (finds wowaddons/ by walking up from the current folder)
py -3 Link-WowAddons.py -Path "<addons folder>" -Flavor forever   # another folder
py -3 Link-WowAddons.py -Remove                 # unlink them all
```

On a Mac, from the repo root:

```sh
python3 wow-addon-kit/plugins/wow-forever-addons/scripts/Link-WowAddons.py    # TOC-aware symlinks
bash wow-addon-kit/plugins/wow-forever-addons/scripts/link-wow-addons.sh      # pure-bash fallback; --dry-run, --remove, --no-dev-addons, --wow-root DIR
```

The bash script doesn't read TOCs: it links every addon into `_forever_/Interface/AddOns`. Both scripts leave a correct link alone, re-point a link that points elsewhere, and move a real folder to `Interface/AddOns.backup/<Name>-<timestamp>` before linking. When run from `${CLAUDE_PLUGIN_ROOT}` outside the repo, pass `-Path`.

## 4. Link one addon into the game (`link` / `unlink`)

```powershell
py -3 Deploy-WowAddon.py -Path "<addon folder>" -Flavor forever               # junction: edits live after /reload
py -3 Deploy-WowAddon.py -Path "<addon folder>" -Flavor forever -Mode Copy    # release-like copy without dev files
py -3 Deploy-WowAddon.py -Path "<addon folder>" -Flavor forever -Remove       # unlink (never deletes your source)
```

Linking or copying also links the kit's error recorder (`!WowKitErrors`) into that client.

Safety rules built into both link scripts, which you should keep when doing anything by hand:
- They never delete a real folder in `AddOns`. They move it to `Interface\AddOns.backup\<Name>-<timestamp>` (Deploy only with `-Force`).
- They remove junctions with a non-recursive delete, so the linked source folder is untouched. Never run `Remove-Item -Recurse` on a junction in PowerShell 5.1.
- They write into the game folder, so **confirm with the user first** unless they asked for it.

## 5. Check it worked

Run `Test-WowAddon.py` on the linked addon. Then tell the user to restart the client fully once (new TOC) and enable the addon in the AddOns list.
