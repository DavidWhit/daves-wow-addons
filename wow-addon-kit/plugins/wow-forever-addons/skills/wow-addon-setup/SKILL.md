---
name: wow-addon-setup
description: Set up a Windows machine for WoW Forever addon development - find the WoW install and every client folder with its Interface number, install luacheck and the Blizzard API index from official sources, link an addon into the game's AddOns folder (junction), and recommend editor tooling. Use when the user is getting started, can't find their AddOns folder, needs the current Interface number, or wants to install, link, unlink or deploy an addon.
argument-hint: "[find | tools | link <folder> | unlink <folder> | refresh-api]"
---

# WoW addon dev environment

Arguments: `$ARGUMENTS`. With none, do the full setup (1 → 3).

All scripts are Windows PowerShell 5.1 and need no admin rights. Run them as:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/<Script>.ps1" <args>
```

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

## 3. Link an addon into the game (`link` / `unlink`)

```powershell
Deploy-WowAddon.ps1 -Path "<addon folder>" -Flavor forever               # junction: edits live after /reload
Deploy-WowAddon.ps1 -Path "<addon folder>" -Flavor forever -Mode Copy    # release-like copy without dev files
Deploy-WowAddon.ps1 -Path "<addon folder>" -Flavor forever -Remove       # unlink (never deletes your source)
```

Safety rules built into the script, which you should keep when doing anything by hand:
- It never deletes a real folder in `AddOns`. With `-Force` it moves the folder to `Interface\AddOns.backup\<Name>-<timestamp>`.
- It removes junctions with a non-recursive delete, so the linked source folder is untouched. Never run `Remove-Item -Recurse` on a junction in PowerShell 5.1.
- It writes into the game folder, so **confirm with the user first** unless they asked for it.

## 4. Check it worked

Run `Test-WowAddon.ps1` on the linked addon. Then tell the user to restart the client fully once (new TOC) and enable the addon in the AddOns list.
