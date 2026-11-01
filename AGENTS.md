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
| **Find installed WoW clients & Interface numbers** | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Find-WowInstall.py` |
| **Link addons into the game** | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Link-WowAddons.py [-Path <folder>] [-WhatIf]` (links the addon(s) plus `devaddons/!WowKitErrors` as junctions; moves real folders to `AddOns.backup`). Confirm with the user before modifying the game directory unless requested. |
| **Refresh stale/missing API index or UI source** | `py -3 wow-addon-kit/plugins/wow-forever-addons/scripts/Update-WowUiSource.py` and `Update-WowApiIndex.py -Branch forever [-FromLocal]` |
| **Refresh `daves_map` Map Genie & pfQuest data** | `py -3 wowaddons/daves_map/tools/Update-MapData.py` (`daves-map-refresh` skill in `.claude/skills/daves-map-refresh/SKILL.md`) |
| **Paint / pack a `daves_frames` AI target-frame theme** | `py -3 wowaddons/daves_frames/tools/Pack-FrameTemplate.py` (`daves-frames-paint` skill in `.claude/skills/daves-frames-paint/SKILL.md`; always paint on `guides/frame-template-ai.png` `2048×1152` `16:9`) |

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
  - Prefer **feature detection** (e.g., `(C_Item and C_Item.GetItemInfo) or GetItemInfo`) over project ID checks unless behavior is strictly Forever-specific (like Camping item categorization).
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
  - If `EditModeDialog.lua` itself needs a change, edit `wow-addon-kit/plugins/wow-forever-addons/templates/editmode/EditModeDialog.lua` and copy it to every Edit Mode addon (`daves_balls`, `daves_castbar`, `daves_chat`, `daves_frames`, `daves_outofmyway`).
  - `ns.EditMode.Attach` takes over the attached frame's `OnUpdate` while dragging — always run per-frame animations or watchers on a separate child/watcher frame.
- **Version Announcements & Reload Rules:**
  - Every addon reads `ns.VERSION` from `## Version:` in its TOC and prints `v<version> loaded` on `PLAYER_LOGIN` (enforced by validator rule `load-version`). Bump `## Version:` whenever preparing changes for the user to test in-game.
  - Lua edits take effect on `/reload` in-game. New files, `.toc` edits, or new/updated `.tga` textures require a **full game client restart**.
- **Media & Tooling:**
  - Custom textures are uncompressed 32-bit `.tga` files (power-of-two dimensions, 18-byte header with byte 2 = `2`, byte 16 = `32`, byte 17 = `0x28` top-left origin) in `Media/`, generated by scripts in `tools/`.
  - Prefer Python (`py -3`) for all new scripts and texture generators. Existing GDI+ scripts in `daves_castbar/tools/` (`Make-CastbarMedia.ps1`, `Show-Preview.ps1`) and `daves_frames/tools/Preview-Tga.ps1` use Windows PowerShell 5.1 (watch out for case-insensitive variable collisions, integer overload rounding in `[math]::Max(0, $x)` vs `0.0`, and never use `Get-ChildItem -Include` for bulk text replacements).
- **Respect Handoff Notes (`NOTES.md`):**
  - Several addons (`daves_chat/NOTES.md`, `daves_frames/NOTES.md`, `daves_sack/NOTES.md`) maintain detailed handoff logs, architecture constraints, and lists of reviewer findings that the user intentionally skipped or deferred. **Always read the addon's `NOTES.md` and `README.md` before modifying it**, and never apply previously skipped review findings unless the user explicitly asks for them by number.

---

## 5. Repository Addons Summary

| Addon (`wowaddons/`) | Slash | Edit Mode | Summary & Key Notes |
| --- | --- | --- | --- |
| **`daves_balls`** | `/balls` | Yes | Diablo-style health and power orbs with sloshing liquid, cursor specular highlight, and optional player-frame replacement. Art generated by `tools/Make-OrbMedia.py` & `Preview-Orb.py`. |
| **`daves_castbar`** | `/castbar` | Yes | Replaces player cast bar with 20 procedural animated looks (7 elements, 4 gathering & 6 crafting professions, Disenchant, First Aid, Plain). Split across `Bar.lua`, `Elements.lua`, and `Effects_*.lua` (to stay under Lua's 200-local limit). |
| **`daves_chat`** | `/daveschat` | Yes | Movable wide-screen chat dock (`Chat`, `Combat Log`, `General`) with a header eye button to show/hide a clean scrollable left-side tab list (auto-fitted up to `1/3` window width, or full-width chat when hidden), bordered inner chat-text pane with aligned input box, Window Settings `Text direction` (`Bottom` stock default / `Top`) and `Faint` (only chat text until hovered) options, Social/Channels/Chat Settings/Window Settings header icons, taint-free unsent-text close cleanup, and standard `X` close / draggable message-bubble open icon. **Read `daves_chat/NOTES.md` first** for seating/anchoring/taint rules. |
| **`daves_frames`** | `/davesframes` | Yes | Custom target unit frame: central portrait ring, health (left) & resource (right) bars emptying inward toward the portrait, damage trail, heal/shield bars, cast overlay/stack, and hanging aura boards on chains (a thin border, not the packed plate strip). Players use one of nine class plates when the class token can be read. **Read `daves_frames/NOTES.md` & `tools/template/PAINT-LAYERS.md`** (and use the `daves-frames-paint` skill) for the zero-drift `1024×300` single-box standard (`guides/frame-template-ai.png` `2048×1152` exact `16:9`, no external ornaments) and `Pack-FrameTemplate.py` AI painting pipeline. |
| **`daves_map`** | `/dmap`, `/davesmap` | No | Map Genie pin layer on the world map, flight-master affine calibration (`Calibrate.lua`), quest chain links, sidebar search/filter panel (`Panel.lua`), Ready-to-Turn-In & zone quest tracker (`Tracker.lua`), and OpenMap seamless stitched map (`Stitch/`). |
| **`daves_map_data`** | *(companion)* | No | **Generated & gitignored** (`wowaddons/daves_map/tools/Update-MapData.py`). Holds Map Genie + pfQuest data (`DAVES_MAP_DATA`) and builds `wowaddons/daves_map_data.zip` for testers. **Never commit.** |
| **`daves_map_textures`** | *(companion)* | No | **Generated & gitignored** (`wowaddons/daves_map/tools/Update-MapTextures.py` from `OpenMap/`). Holds stitched world map tile art and data tables. **Never commit.** |
| **`daves_outofmyway`** | `/oomw` | Yes | Moves Need/Greed loot rolls via a `hooksecurefunc` post-hook on `GroupLootContainer_Update`, and keeps the buff frame expanded by toggling `consolidateBuffs` / `collapseExpandBuffs` at `PLAYER_LOGOUT`. |
| **`daves_sack`** | `/sack` | No | All-in-one HUD Edit Mode styled bag replacement with collapsible categories (including Forever Camping & Keys), reagent bag routing, item delete/trash button (with `"Confirm delete (trash)"` in Bag Settings & `Esc > Options > AddOns`), and taint-safe `SecureActionButtonTemplate` close & currency buttons. **Read `daves_sack/NOTES.md` first.** |
| **`ForeverLoot`** | — | No | Dungeon and raid loot browser (`ForeverLoot.toc` / `ForeverLoot_Camelot.toc`). **Gitignored by user rule — never commit.** |
