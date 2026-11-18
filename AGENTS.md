# Workspace Notes & Rules (`daves-wow-addons`)

This repository contains World of Warcraft addons for **WoW: Forever** (`wowaddons/`) and the toolkit used to scaffold, validate, debug, review, and link them (`wow-addon-kit/plugins/wow-forever-addons/`).

---

## 1. Golden Rules: Use the Kit, Not Memory

Training data predates WoW: Forever, and Blizzard's API shifts across patches. Always ground API lookups, UI behavior, and debugging in the local kit tools (`wow-addon-kit/plugins/wow-forever-addons/`):

> **Note on Skill Paths:** The skills in `wow-addon-kit/plugins/wow-forever-addons/skills/` reference `${CLAUDE_PLUGIN_ROOT}`. When running commands from the repo root, substitute `wow-addon-kit/plugins/wow-forever-addons`. On Windows, invoke Python 3.14 scripts via `python` (works inside the sandbox) or `py -3`.

| Task | Tool / Workflow |
| --- | --- |
| **Check if an API, widget method, or event exists, moved, or returns/rejects secrets** | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Find-WowApi.py <pattern...> [-Events] [-Methods] [-SecretOnly]` (accepts multiple patterns in one call; `wow-forever-api` skill) |
| **Inspect how Blizzard's own UI works** | Run `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Find-WowApi.py <symbol...> -UiSource` (searches `INDEX.tsv` filtered to Forever-loaded `Mainline`/`Camelot`/`Shared`/unsuffixed folders), then read the `path:line` range under `.../data/ui-source/forever/Interface/`. |
| **Debug an in-game error, "action blocked", or odd behavior** | Follow **`wow-addon-test` Step 0** *before* reading addon code:<br>1. Recorded errors & taint probes: `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Get-WowScriptErrors.py -Addon <name>`<br>2. Client taint log (if nothing recorded or probe doesn't name what failed): `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Get-WowTaintLog.py -Addon <name>`<br>3. Only then inspect the addon's Lua code (and bisect in-game with temporary switches if needed). |
| **After any addon code change** | Follow **`wow-addon-test`**:<br>1. Build the pre-annotated review packet (runs `Test-WowAddon.py` in-process, scopes `git diff`, skips unmodified `EditModeDialog.lua`, extracts `NOTES.md` constraints/skipped items, and annotates Forever APIs/methods/events): `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Prepare-WowReview.py -Path "wowaddons/<name>" [-Full]`<br>2. Run an **advisor-mode code review** following `wow-addon-kit/plugins/wow-forever-addons/agents/wow-addon-reviewer.md` (**inline** when `RecommendedMode: inline` for small low-risk diffs; **diff-scoped subagent** with the packet pasted in when `subagent-diff` or `subagent-full`). Present numbered findings (`Confirmed` / `Suspected`) and **wait for the user's explicit approval** before applying any reviewer suggestions.<br>3. Update any affected `.md` documentation, `NOTES.md`, `README.md`, or `SKILL.md` files (see **Section 2**). |
| **After any code, script, tool, or workflow change** | **Update all affected `.md` skills and documentation** in the same task so no `.md` file goes stale (see **Section 2**). |
| **Find installed WoW: Forever client & Interface number** | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Find-WowInstall.py` |
| **Link addons into the game** | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Link-WowAddons.py [-Path <folder>] [-WhatIf]` (links the addon(s) plus `devaddons/!WowKitErrors` as junctions; moves real folders to `AddOns.backup`). Confirm with the user before modifying the game directory unless requested. |
| **Refresh stale/missing API index or UI source** | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Update-WowUiSource.py` and `Update-WowApiIndex.py -Branch forever [-FromLocal]` |
| **Refresh `daves_map` QuestieDB Forever data** | `py -3 wowaddons/daves_map/tools/Update-MapData.py` (`daves-map-refresh` skill in `.claude/skills/daves-map-refresh/SKILL.md`; writes companion addon `wowaddons/daves_map_data/`) |
| **Publish compressed `<addon>.zip` packages to the `releases` branch (run whenever committing/pushing to `main`)** | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Publish-WowReleases.py -Push [-Branch releases] [-WhatIf]` (packs all 8 tracked `daves_*` addons — including `daves_map_data` & `daves_map_textures` — into clean `<addon>.zip` archives and force-updates the orphan `releases` branch without touching the working tree) |
| **Paint / pack a target-frame theme (`daves_frames/tools`)** | `py -3 wowaddons/daves_frames/tools/Pack-FrameTemplate.py [--extended] [--layer-dir <dir>] [--layer-* <img...>]` (standalone frame-templating toolkit in `wowaddons/daves_frames/tools/`: `daves-frames-paint` skill on `guides/frame-template-ai.png` or `daves-frames-paint-extended` skill on `guides/frame-template-extended-ai.png`, plus modular `Order 1..6` per-section stencils in `guides/layers/layer-1..6-*-ai.png`, `2048×1152` `16:9`) |

---

## 2. Global Rule: Keep Markdown Skills & Documentation Updated

Whenever code, scripts, tools, workflows, slash commands, settings, files, versions, or architecture change anywhere in this project, **you must update every affected `.md` skill, rule, and documentation file as part of the same task** — never let Markdown skills or project docs drift out of sync with the codebase:

- **Skills & Agent Specs (`SKILL.md`, reference `.md`, reviewer `.md`):**
  - When kit scripts, CLI flags, validator rules, templates, API conventions, or data pipelines change, update the matching skill(s) in `wow-addon-kit/plugins/wow-forever-addons/skills/*/SKILL.md` (and companion docs like `sources.md`), `.claude/skills/*/SKILL.md`, or `.agents/skills/*/SKILL.md`, plus `.agents/skills.json` when adding/moving skill folders.
  - When code-review rules or expectations change, update `wow-addon-kit/plugins/wow-forever-addons/agents/wow-addon-reviewer.md`.
- **Addon Documentation (`README.md`, `NOTES.md`, tool/art `.md` guides):**
  - When an addon's features, slash commands, Edit Mode options, file layout, version, or behavior change, update `wowaddons/<addon>/README.md` and `wowaddons/<addon>/NOTES.md` (preserving still-applicable architecture notes and intentionally skipped/deferred review records).
  - When media generators, templates, or art layers change, update their companion guides (e.g., `wowaddons/daves_frames/tools/template/PAINT-LAYERS.md`, `tools/**/README.md`).
- **Project-Wide Rules & Root Docs (`AGENTS.md`, `CLAUDE.md`, `README.md`, `wow-addon-kit/README.md`):**
  - When addons are added/renamed, slash commands or Edit Mode integration change, house conventions evolve, or kit scripts/workflows change, update `AGENTS.md` (including the **Repository Addons Summary** table), `CLAUDE.md`, root `README.md`, and `wow-addon-kit/README.md` (plus `templates/addon/README.md` if template behavior changed).

---

## 3. WoW: Forever Client & API Architecture

- **Client Identity:** WoW: Forever runs on the **modern (Mainline) client** with the **same addon API and restrictions as Retail Midnight (12.x)**.
  - Build / Interface: `1.60.1` → `## Interface: 16001` (always verify live client via `Find-WowInstall.py`).
  - Project constant: `WOW_PROJECT_CAMELOT = 18` (`WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`).
  - TOC game type: `camelot` (inside the `mainline` family; `[Family]` = `Mainline`, `[Game]` = `Camelot`, client-specific TOC suffix `_Camelot.toc`).
  - All addons in this repository target **WoW: Forever (`16001`) only** (`## Interface: 16001`); call Forever's native `C_*` namespaces directly without Classic/Retail fallback shims.
- **Secret Values (12.x / Forever):**
  - In restricted contexts (combat, instances, other units), many APIs (`UnitHealth`, `UnitPower`, `UnitName`, `UnitCastingInfo`, `C_UnitAuras`, `UNIT_SPELLCAST_*` payloads) return opaque **secret values** (`SecretReturns = true` or `SecretWhen* = true`).
  - **Forbidden on secrets (runtime Lua error):** comparisons (`<`, `==`), math (`+`, `-`, `*`, `/`), string concatenation (`..`), or using as table keys.
  - **Allowed on secrets:** passing directly into widget setters marked `SecretArguments = "AllowedWhenTainted"` (`StatusBar:SetMinMaxValues`, `StatusBar:SetValue`, `FontString:SetText`, `FontString:SetFormattedText`, `Texture:SetVertexColorFromBoolean`, `Region:SetAlphaFromBoolean`, `AbbreviateNumbers`, `UnitHealthPercent`, `UnitPowerPercent`).
  - Always guard values with `not issecretvalue(v)` before indexing tables (e.g., `RAID_CLASS_COLORS[class]`) or branching on them.
  - Do not treat a secret event payload (such as `interruptedBy` on `UNIT_SPELLCAST_CHANNEL_STOP`) as truthy; infer state from readable values instead.
- **Other Restrictions & Removed Globals:**
  - **Combat Log Removed:** Registering `COMBAT_LOG_EVENT_UNFILTERED` or `COMBAT_LOG_EVENT` errors immediately.
  - **Addon Comms Lockdown:** Check `C_ChatInfo.InChatMessagingLockdown()` before `C_ChatInfo.SendAddonMessage`.
  - **Moved Globals:** `GetSpellInfo` → `C_Spell.*`, `UnitAura`/`UnitBuff`/`UnitDebuff` → `C_UnitAuras.*`, `GetAddOnMetadata` → `C_AddOns.*`, `GetItemInfo` → `C_Item.*`, `GetCoinTextureString` → `C_CurrencyInfo.GetCoinTextureString`, `InterfaceOptions_AddCategory` → `Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnCategory`.
- **Taint Prevention:**
  - Keep all symbols `local` and share state on the addon table (`local ADDON, ns = ...`).
  - Never call Blizzard state-changing UI functions (`CloseAllBags`, `ToggleAllBags`, `ToggleCharacter`, `ShowUIPanel`) directly from addon code — doing so taints Blizzard's frames and blocks protected actions (`UseContainerItem`, `C_Bank.PurchaseBankTab`) later. Observe with `hooksecurefunc`, or use a `SecureActionButtonTemplate` (parked off-window on `PLAYER_REGEN_DISABLED`) when a click must invoke Blizzard UI.
  - Never `UnregisterEvent` on Blizzard's parked container frames.
  - Check `InCombatLockdown()` before moving, showing, hiding, or changing attributes on protected frames.

---

## 4. House Conventions & Edit Mode Standard

- **Edit Mode Shared Dialog (`EditModeDialog.lua`):**
  - Every addon that integrates with Edit Mode **must** include an unmodified copy of `wow-addon-kit/plugins/wow-forever-addons/templates/editmode/EditModeDialog.lua` listed right after `Core.lua` in its `.toc`.
  - Use `ns.EditMode.CreateDialog` and `ns.EditMode.Attach` (or `CreateSelection` + `SnapRect`/`SnapEdge` for custom resize/drag handles).
  - Never build custom Edit Mode settings windows, sliders, checkboxes, or grid-snapping math (`editmode-dialog`, `editmode-ui`, and `editmode-snap` validator rules enforce this; use `-- editmode-ui: ok` only on genuine non-Edit-Mode UI frames).
  - If `EditModeDialog.lua` itself needs a change, edit `wow-addon-kit/plugins/wow-forever-addons/templates/editmode/EditModeDialog.lua` and copy it to every Edit Mode addon (`daves_balls`, `daves_castbar`, `daves_chat`, `daves_outofmyway`).
  - `ns.EditMode.Attach` takes over the attached frame's `OnUpdate` while dragging — always run per-frame animations or watchers on a separate child/watcher frame.
- **Version Announcements, Reload & Release Branch Rules:**
  - Every addon reads `ns.VERSION` from `## Version:` in its TOC and prints `v<version> loaded` on `PLAYER_LOGIN` (enforced by validator rule `load-version`). Bump `## Version:` whenever preparing changes for the user to test in-game.
  - Lua edits take effect on `/reload` in-game. New files, `.toc` edits, or new/updated `.tga` textures require a **full game client restart**.
  - Whenever committing and pushing to `main` (or `master`), also run `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Publish-WowReleases.py -Push` so the orphan `releases` branch stays updated with fresh `<addon>.zip` packages for all 8 tracked `daves_*` addons.
- **Media & Tooling:**
  - Custom textures are uncompressed 32-bit `.tga` files (power-of-two dimensions, 18-byte header with byte 2 = `2`, byte 16 = `32`, byte 17 = `0x28` top-left origin) in `Media/`, generated by scripts in `tools/`.
  - Prefer Python (`py -3`) for all new scripts and texture generators. Existing GDI+ scripts in `daves_castbar/tools/` (`Make-CastbarMedia.ps1`, `Show-Preview.ps1`) and `daves_frames/tools/Preview-Tga.ps1` use Windows PowerShell 5.1 (watch out for case-insensitive variable collisions, integer overload rounding in `[math]::Max(0, $x)` vs `0.0`, and never use `Get-ChildItem -Include` for bulk text replacements).
- **Respect Handoff Notes (`NOTES.md`):**
  - Several addons (`daves_chat/NOTES.md`, `daves_sack/NOTES.md`) maintain detailed handoff logs, architecture constraints, and lists of reviewer findings that the user intentionally skipped or deferred. **Always read the addon's `NOTES.md` and `README.md` before modifying it**, and never apply previously skipped review findings unless the user explicitly asks for them by number.

---

## 5. Repository Addons Summary

| Addon (`wowaddons/`) | Slash | Edit Mode | Summary & Key Notes |
| --- | --- | --- | --- |
| **`daves_balls`** | `/balls` | Yes | Diablo-style health and power orbs with sloshing liquid, cursor specular highlight, and optional player-frame replacement. Art generated by `tools/Make-OrbMedia.py` & `Preview-Orb.py`. |
| **`daves_castbar`** | `/castbar` | Yes | Replaces player cast bar with 21 animated looks (7 elements, 4 gathering & 7 crafting professions, Disenchant, First Aid, Plain). Split across `Bar.lua`, `Elements.lua`, and `Effects_*.lua` (to stay under Lua's 200-local limit). |
| **`daves_chat`** | `/daveschat` | Yes | Movable wide-screen chat dock (`Chat`, `Combat Log`, `General`) with a header eye button to show/hide a clean scrollable left-side tab list (auto-fitted up to `1/3` window width, and auto-closing back to full-width chat when the cursor leaves the window), bordered inner chat-text pane with aligned input box, Window Settings `Text direction` (`Bottom` stock default / `Top`) and `Faint` (fades chrome to a translucent frosted-glass backing on the chat section only — with `Faint glass` strength slider, `Faint glass color` picker, and auto-fade to `0` when chat lines fade out — art generated by `tools/Make-FrostMedia.py`) options, Social/Channels/Chat Settings/Window Settings header icons, taint-free unsent-text close cleanup, and standard `X` close / draggable message-bubble open icon. **Read `daves_chat/NOTES.md` first** for seating/anchoring/taint rules. |
| **`daves_frames/tools`** | *(toolkit)* | No | Standalone target-frame templating setup (the `daves_frames` addon itself was removed from git): zero-drift `1024×300` single-box standard (`guides/frame-template-ai.png` `2048×1152` exact `16:9`), branched extended template (`guides/frame-template-extended-ai.png` with top `#FF8000` orange crest circle and `#FF0000` Red intricate-art backdrop), and 6 modular `Order 1..6` per-section stencils (`guides/layers/layer-1..6-*-ai.png`) + `Build-FrameTemplate.py` & `Pack-FrameTemplate.py` (`tools/template/PAINT-LAYERS.md`, `daves-frames-paint` / `daves-frames-paint-extended` skills). |
| **`daves_map`** | `/dmap`, `/davesmap` | No | QuestieDB Forever quest, objective, turn-in, chain, dungeon, flight-master, townsfolk, rare & treasure layer (`OptionalDeps: daves_map_data, daves_map_textures`), direct `C_Map.GetMapRectOnMap` placement (`Calibrate.lua`), sidebar search/filter panel (`Panel.lua`), Ready-to-Turn-In & zone quest tracker (`Tracker.lua`), and OpenMap `v0.8.10` seamless stitched world map & multi-floor dungeon/raid maps (`Stitch/`). |
| **`daves_map_data`** | *(companion)* | No | Tracked companion data addon for `daves_map` (`DAVES_MAP_DATA` in `Data.lua`, generated by `daves_map/tools/Update-MapData.py` from `Questie/QuestieDB` Forever; `NOTICE-QuestieDB.md`). |
| **`daves_map_textures`** | *(companion)* | No | Tracked companion art/tables addon for `daves_map` (`DAVES_MAP_TEXTURES`: OpenMap `v0.8.10` `Data/*.lua` + `Media/Textures/`, generated by `daves_map/tools/Update-MapTextures.py`; `LICENSE-OpenMap.txt`, `NOTICE-OpenMap.md`). |
| **`daves_outofmyway`** | `/oomw` | Yes | Moves Need/Greed loot rolls via a `hooksecurefunc` post-hook on `GroupLootContainer_Update`, and keeps the buff frame expanded by toggling `consolidateBuffs` / `collapseExpandBuffs` at `PLAYER_LOGOUT`. |
| **`daves_sack`** | `/sack` | No | All-in-one HUD Edit Mode styled bag replacement with collapsible categories (including Ammo, Forever Camping, Keys, and an **Item Sets** sub-category under Equipment with `[Locked]` / `[Unlocked]` item-set protection via `C_Item.LockItem` / `UnlockItem` and drag-and-drop custom set membership) or an optional **"One big bag"** flat slot grid, reagent-bag & ammo-bag (quiver / ammo pouch) Free Space, footer capacity & priority routing (plus post-Sort reagent & ammo sweep), matching gold toolbar icon buttons (`Media/trash.tga` to the left of the search bar; `Media/gavel.tga`, `Media/gear.tga`, and `Media/sort.tga` to the right; item delete/trash has `"Confirm delete (trash)"` in Bag Settings & `Esc > Options > AddOns`), local Auction House price & market caching (`db.ahPrices` + `db.ahMarket` + `db.ahRecipes`; fast bag cache on every AH visit, 2-hour cooldown on completed full AH deep cache, and `/sack scan` manual rescan) with item tooltip unit/stack prices, a bottom bag-value/cache-age footer row, a `716px` companion **Market Analysis & Insights** window (`Market.lua`: global search bar above the main tabs that temporarily replaces the tabs with a global search across all AH & bag items until cleared, **Margin** comparing lowest buyout vs. next highest offer, **Scarce**, **Professions** fitting all 9 profession tabs side-by-side with **Cost to Make vs. Sell** & **Top Trades**, **Bag Advisor**, and **Bait & Snipe** (`/sack bait`, `/sack counter`) 1-unit commodity undercut trap, **Counter-Snipe Top 50** radar for eating rival sniper baits & mispriced stacks, and standalone `DavesSackSnipeAlert` popup), and taint-safe `SecureActionButtonTemplate` close & currency buttons. **Read `daves_sack/NOTES.md` first.** |
| **`ForeverLoot`** | — | No | Dungeon and raid loot browser (`ForeverLoot.toc` / `ForeverLoot_Camelot.toc`). **Gitignored by user rule — never commit.** |
