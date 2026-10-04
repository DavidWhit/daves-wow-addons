---
name: wow-addon-release
description: Prepare a WoW Forever addon release - bump the version, make sure the TOC Interface numbers match the live clients, validate, build a clean zip, and set up BigWigsMods/packager (.pkgmeta, GitHub Actions) for CurseForge/Wago/WoWInterface. Use when the user wants to publish, package, zip, release or update the version of a WoW addon.
argument-hint: "[addon folder] [new version]"
disable-model-invocation: true
---

# Release a WoW addon

Arguments: `$ARGUMENTS`.

## 1. Gate on a clean check

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Find-WowInstall.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Test-WowAddon.ps1" -Path "<addon>" -Flavor forever[,retail,classic_era]
```

Don't release with errors. Warnings need either a fix or a stated reason.

## 2. Version and Interface

- Bump `## Version:` in the TOC (semver, e.g. `1.4.0`). Add a changelog entry if the project keeps one.
- `## Interface:` must include the current number for every supported flavor: 16001 for Forever, plus whatever `Find-WowInstall.ps1` reports for others. Keep older numbers only if those clients still exist.

## 3. Build a zip locally (no packager needed)

The zip must contain the addon **folder** at its root (`MyAddon/MyAddon.toc`), not loose files. Exclude dev files:

```powershell
$src = "<addon folder>"; $name = Split-Path $src -Leaf
$ver = (Select-String -Path "$src\$name.toc" -Pattern '^## Version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$stage = Join-Path $env:TEMP "wowrel\$name"; Remove-Item (Split-Path $stage) -Recurse -Force -ErrorAction SilentlyContinue
robocopy $src $stage /E /XD .git .vscode tests .release /XF .luacheckrc .pkgmeta .gitignore *.zip | Out-Null
Compress-Archive -Path $stage -DestinationPath (Join-Path (Split-Path $src) "$name-$ver.zip") -Force
```

Then test the zip itself: extract it over the deployed copy (`Deploy-WowAddon.ps1 -Mode Copy` gives the same layout) and do the in-game checks from **wow-addon-test**.

## 4. Automated releases with BigWigsMods/packager (optional)

The packager (https://github.com/BigWigsMods/packager) builds zips from git tags and uploads them to CurseForge, Wago and WoWInterface. The template's `.pkgmeta` already sets `package-as` and `ignore`.

- **Workflow:** copy `${CLAUDE_PLUGIN_ROOT}/templates/github/release.yml` to `<repo>/.github/workflows/release.yml`. It follows the packager wiki's example (packager v2, `actions/checkout@v7`, `fetch-depth: 0`).
- **Secrets** (repo Settings → Secrets): `CF_API_KEY`, `WAGO_API_TOKEN`, `WOWI_API_TOKEN`; `GITHUB_TOKEN` is automatic. `release.sh` also accepts the newer names `CF_API_TOKEN` and `GITHUB_API_TOKEN`.
- **Project IDs** go in the TOC (`## X-Curse-Project-ID:`, `## X-Wago-ID:`, `## X-WoWI-ID:`) or as arguments (`-p`, `-a`, `-w`).
- **Keywords:** `@project-version@` in `## Version:`; `--@version-forever@` … `--@end-version-forever@` blocks keep code only in the Forever build.

**Forever support** (checked in the packager's `release.sh`, 2026-10-03): game type `forever` (alias `camelot`), auto-detected from `## Interface: 16xxx`. `-S` generates a `<Name>_Camelot.toc`, and `-g forever` forces the flavor. A single TOC listing `16001, 120100, ...` works for multi-flavor releases.

## 5. Report

Give the zip path, version, Interface numbers shipped, and the validation result. Publishing to CurseForge/Wago is outward-facing, so let the user do it, or get explicit confirmation before pushing a tag that triggers an upload.
