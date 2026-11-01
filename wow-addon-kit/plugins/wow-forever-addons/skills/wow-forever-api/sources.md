# Validated sources

Use these, in this order, when a question about the WoW API comes up. Don't rely on recall or on forum posts.

| Source | What it's authoritative for | How the kit uses it |
| --- | --- | --- |
| **Blizzard's UI source**: https://github.com/Gethe/wow-ui-source, branch `forever` (also `live`, `classic`, `classic_era`, ...) | What actually ships in the client: FrameXML, templates, the Settings API, deprecation shims, project constants, Blizzard's own TOCs | `Update-WowApiIndex.py` downloads the branch zip (or indexes `data/ui-source/<branch>/` offline via `-FromLocal`). Its global-usage scan is the evidence that engine/FrameXML globals exist. `Update-WowUiSource.py` keeps a readable copy in `data/ui-source/<branch>/` (git-ignored) with `INDEX.tsv` mapping every function, mixin method, XML template and named frame to `path:line` (queried via `Find-WowApi.py -UiSource`) |
| **Blizzard_APIDocumentationGenerated** (inside the branch above) | Every C API function, `ScriptObject` widget method, and event, with `SecretReturns`, `SecretReturnsForAspect`, `SecretWhen*`, `SecretIn*`, `SecretArguments`, `SecretPayloads`, `IsProtectedFunction`, `HasRestrictions`, `SecureHooksAllowed`, and `Requires*` | Parsed into `data/api-forever.json` (`functions`, `methods`, `events`); queried by `Find-WowApi.py`, `Test-WowAddon.py`, and `Prepare-WowReview.py` |
| **Installed client**: `.build.info` (install root) and `.flavor.info` (each `_xxx_` folder) | The exact build installed, which gives the TOC Interface number (major·10000 + minor·100 + patch) | `Find-WowInstall.py`, `New-WowAddon.py`, `Test-WowAddon.py` |
| **Warcraft Wiki**: https://warcraft.wiki.gg | TOC format and directives (`TOC_format`), current builds (`Public_client_builds`), patch API change lists (`Patch_12.0.0/API_changes`, `Patch_11.0.0/API_changes`), per-function pages | Cited in skills and validator messages |
| **luacheck**: https://github.com/lunarmodules/luacheck (v1.2.0 official release) | Lua syntax errors, accidental globals, unused/shadowed locals | `Install-WowDevTools.py` downloads `luacheck.exe` from the GitHub release and checks its size against the release asset |
| **VS Code WoW API extension**: `ketho.wow-api` (https://github.com/Ketho/vscode-wow-api), built on LuaLS | Editor IntelliSense for the WoW API | Recommended; not installed automatically |
| **BigWigsMods/packager**: https://github.com/BigWigsMods/packager (`BigWigsMods/packager@v2`, v2.6.1) | Release zips, `.pkgmeta`, CurseForge/Wago/WoWInterface upload. Its `release.sh` is the source of truth; the README lagged behind (it didn't list Forever, but the code supports game type `forever`/`camelot`) | `.pkgmeta` template, `templates/github/release.yml`, `wow-addon-release` skill |

## Facts checked and where (2026-10-03)

- Forever = 1.60.1, Interface 16001: Warcraft Wiki Public_client_builds, and the installed `_classic_beta_` build 1.60.1.70205.
- `WOW_PROJECT_CAMELOT = 18`: `Blizzard_ProjectConstants/Camelot/ProjectConstants.lua`.
- `mainline` includes `camelot`; `[Family]`=Mainline and `[Game]`=Camelot: `Blizzard_UnitFrame.toc` on the forever branch.
- CLEU registration errors on 12.x: Warcraft Wiki Patch_12.0.0/API_changes. Forever shares the Midnight API one-for-one (Blizzard developer statements reported by Icy Veins and Kami Labs, September 2026).
- Settings API signatures: `Blizzard_Settings_Shared/Blizzard_Settings.lua` on the forever branch.
- Secret-argument rules for StatusBar and FontString setters: `SimpleStatusBarAPIDocumentation.lua` and `SimpleFontStringAPIDocumentation.lua`.

When a fact here and a fresh source disagree, the fresh source wins. Update this file and the validator.
