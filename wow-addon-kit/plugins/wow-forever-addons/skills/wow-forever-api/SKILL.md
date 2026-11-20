---
name: wow-forever-api
description: Facts, architecture-first modularity rules, Lua 5.1 conventions, and API rules for writing World of Warcraft addon Lua that works on WoW Forever (internal game type "camelot", client 1.60.x, Interface 16001). Covers pre-code architecture design, modular code splitting, standard WoW Lua conventions, secret values, combat-log removal, addon-comms lockdown, TOC game-type rules, API lookups, and the shared Edit Mode settings dialog every movable addon frame must use. Use whenever planning, writing, reviewing or debugging WoW addon code, choosing a WoW API, or answering "does X exist / work on Forever".
---

# WoW: Forever addon API

WoW: Forever runs on the **modern (Mainline) client** with the **same addon API and restrictions as Retail Midnight (12.x)**, no lighter version. Code written for Classic Era's old API will not work there unchanged.

## Something broke in game? Read the evidence first

For a Lua error, "action blocked", "only available to the Blizzard UI" or odd behaviour, read what the game recorded **before** the code. Start with the recorded addon errors (`${CLAUDE_PLUGIN_ROOT}/scripts/Get-WowScriptErrors.py -Addon <name>`). If nothing was recorded, read the taint log (`${CLAUDE_PLUGIN_ROOT}/scripts/Get-WowTaintLog.py -Addon <name>`). Then read the code. The full steps are in step 0 of the **wow-addon-test** skill (`${CLAUDE_PLUGIN_ROOT}/skills/wow-addon-test/SKILL.md`). Follow them.

## Rule zero: look it up, don't recall it

Your training data predates Forever, and APIs move every patch. Before you use or recommend any API, check it against the local index built from Blizzard's own client source:

```powershell
py -3 "${CLAUDE_PLUGIN_ROOT}/scripts/Find-WowApi.py" GetSpellInfo UnitHealth :SetTimerDuration
py -3 "${CLAUDE_PLUGIN_ROOT}/scripts/Find-WowApi.py" "C_UnitAuras.*"
py -3 "${CLAUDE_PLUGIN_ROOT}/scripts/Find-WowApi.py" UNIT_AURA -Events
py -3 "${CLAUDE_PLUGIN_ROOT}/scripts/Find-WowApi.py" "Unit*" -SecretOnly
```

If the index is missing or older than a patch, rebuild it: `scripts/Update-WowApiIndex.py -Branch forever` (add `-FromLocal` to rebuild offline from `data/ui-source/forever/`).
For behaviour details, read Blizzard's own code in `data/ui-source/forever/Interface/` (every .lua, .xml and .toc). Look symbols up via `Find-WowApi.py -UiSource` first (searches `INDEX.tsv` in <0.1s and filters to Forever-loaded folders), then read that file at that line:

```powershell
py -3 "${CLAUDE_PLUGIN_ROOT}/scripts/Find-WowApi.py" ContainerFrameItemButton_OnClick EditModeManagerFrame -UiSource
```

On Forever only `Mainline`, `Camelot`, `Shared` and unsuffixed folders load; `Vanilla`/`TBC`/`Wrath`/`Cata`/`Mists` copies don't (the addon's TOC decides). If the folder is missing or older than the installed build (`SOURCE.txt` has the commit and date), run `scripts/Update-WowUiSource.py` (about a minute). Also see the API pages on https://warcraft.wiki.gg. See [sources.md](sources.md) for what each source is good for.

## Rule one: design architecture & module boundaries before writing code

Never jump straight into adding flags, hooks, or UI code inside an existing file without mapping how the addon fits together first. Skipping this step causes modules to step on each other's state and creates sprawling multi-thousand-line files that are hard to read and debug.

### 1. Pre-code architecture pass (mandatory before any edit)
- **Read `<addon>/NOTES.md`, `<addon>/README.md`, and `<addon>.toc` first.** The `.toc` file order is the addon's dependency graph. Check existing `hooksecurefunc` hooks, events, `SavedVariables` keys, and skipped/settled review decisions before touching Lua.
- **One owner per state:** Every mutable concept (current selection, active filter, navigation history, cache table) must have **one owning module** and one clear mutation path (`ns.Set*` / `ns.Clear*` notifying views). Never mirror overlapping flags across files (for example, separate selection variables in a map canvas and a sidebar that can drift out of sync, or tying a `"Clear"` button to `"< Back"` history).
- **Separate pure queries from side-effecting commands:** Data/query functions (`Get*`, `Is*`, `Format*`, list/subtitle builders) must be side-effect-free — never trigger C++/server preload requests (`RequestLoadQuestByID`, `RequestPreloadRewardData`), mutate UI state, or rebuild views inside a read getter, or list refreshes at login will hit `script ran too long`. Run preloads and camera/UI transitions only from explicit user actions or hovered elements.
- **Check interaction boundaries:** Before hooking a Blizzard frame or modifying shared callbacks, trace every existing caller of the touched `ns.*` functions so the new behaviour composes cleanly instead of stepping on an existing flow (such as pinning, zone filtering, or Edit Mode dragging).

### 2. Modularity & code splitting
- **Single-responsibility `.lua` files:** Give each file one clear job (~`150–900` lines). Split proactively when a handwritten file approaches `~800–1,000` lines or mixes data/graph logic, controller state, and widget rendering (`Test-WowAddon.py` emits `[file-size]` at `>1200` lines and `Prepare-WowReview.py` reports `ModuleHealth` on every review).
- **Layer `.toc` files top-to-bottom (lower layers never call upper layers at load time):**
  1. `Core.lua` — `local ADDON, ns = ...`, `SavedVariables` defaults on `ADDON_LOADED`, `PLAYER_LOGIN` version print, slash commands, thin client wrappers.
  2. `EditModeDialog.lua` + `EditMode.lua` *(when movable in Edit Mode)* — unmodified kit copy right after `Core.lua`.
  3. **Domain / data modules** (`Calibrate.lua`, `Quests.lua`, `Elements.lua`) — pure lookups, caches, math/graph queries, and data-invalidation events; no frames or widgets.
  4. **Controller / state modules** (`Focus.lua`, `PanelNav.lua`) — selection, navigation stack, camera/waypoint actions, and change notifications.
  5. **View / UI modules** (`Layer.lua`, `PanelData.lua`, `Panel.lua`, `Tracker.lua`, `Effects_*.lua`) — frames, pooled rows/pins, tooltips, and input scripts calling controller/domain APIs.
  6. `Options.lua` — Blizzard Settings category or companion settings dialog.
- **Respect Lua 5.1's compiler limits:** Lua 5.1 hard-fails compilation above **200 active locals** per file/function and **60 upvalues** per function. Keep file-level locals comfortably under `~120` and upvalues under `~40` by grouping module-private state and widgets into a single `local state = { ... }` or `local ui = { ... }` table instead of dozens of loose file-level `local`s.
- **Remember `.toc` reload rules:** Editing existing `.lua` files reloads with `/reload`; adding, renaming, or reordering `.lua` files in `.toc` requires a **full game client restart** once.

### 3. Standard WoW Lua 5.1 conventions
- **Header & scope:** Start every file with `local ADDON, ns = ...` (or `local _, ns = ...`). Keep every helper, constant, and state table `local`; expose cross-file contracts intentionally as `ns.PascalCase`. Zero accidental globals (`luacheck` W111/W112).
- **Naming & style:** Indent with tabs (matching existing files); `UPPER_SNAKE_CASE` for constants, `PascalCase` for `ns.*` APIs and major local functions, `camelCase` for local variables, parameters, and table fields. Prefer guard-clause early `return`s over deeply nested `if` blocks.
- **Never use `cond and a or b` when `a` can be `false` or `nil`:** In Lua, `cond and false or true` evaluates to `true`. Write explicit `if v == nil then v = default end` for boolean settings and nullable lookups.
- **Reset pooled widgets completely:** Whenever reusing a pooled frame, button, texture, fontstring, or line, reset all mutable properties (`ClearAllPoints`, `SetSize`, `SetTexCoord(0, 1, 0, 1)`, `SetVertexColor(1, 1, 1, 1)`, `SetDesaturated(false)`, `SetAlpha(1)`, scripts) before configuring the new item so state never bleeds across pool reuses.
- **Defer hidden UI work:** Never build large lists, pin layouts, or preload loops during `ADDON_LOADED` while the parent window is hidden; mark a dirty flag and build on `OnShow` / `PLAYER_LOGIN`.

## Facts (verified 2026-10-03)

| Fact | Value | Source |
| --- | --- | --- |
| Client version / Interface | 1.60.1 → `## Interface: 16001` | warcraft.wiki.gg Public_client_builds; installed `.build.info` |
| Project ID | `WOW_PROJECT_CAMELOT = 18`, `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` | `Blizzard_ProjectConstants/Camelot/ProjectConstants.lua` |
| TOC game type | `camelot`, inside the `mainline` family | Blizzard's own TOCs, e.g. `Blizzard_UnitFrame.toc` |
| TOC path variables | `[Family]` → `Mainline`, `[Game]` → `Camelot` | same |
| Client-specific TOC | `<Name>_Camelot.toc` | warcraft.wiki.gg TOC_format |
| Install folder | `_forever_` (product `wowf`) | local install; always confirm via `Find-WowInstall.py` |

The Interface number can change at launch (expected November 2026) or with any patch. `Find-WowInstall.py` reads it from the installed build, so prefer that over this table.

### TOC targeting

- Target WoW: Forever in the TOC: `## Interface: 16001`.
- `[AllowLoadGameType mainline]` **includes Forever**. Blizzard itself has to add `[ExcludeLoadGameType camelot]` to opt Forever out. Use `camelot` to target Forever only.
- Per-file variants: `[Game]\Feature.lua` loads `Camelot\Feature.lua` on Forever.
- TOC or new-file changes need a full client restart; `/reload` only re-runs Lua/XML.

## Secret values (Midnight and Forever)

In restricted contexts (combat, instances, other players), many APIs return **secret values**: opaque values addon code can't inspect. Source: warcraft.wiki.gg Patch_12.0.0/API_changes, plus the `Secret*` fields in Blizzard_APIDocumentationGenerated.

**Errors at runtime on a secret:** comparison (`<`, `==`), arithmetic, concatenation (`..`), using it as a table key.

**Allowed:** passing it to widget methods Blizzard marks `SecretArguments = "AllowedWhenTainted"`. These include `StatusBar:SetMinMaxValues`, `StatusBar:SetValue`, `FontString:SetText` and `FontString:SetFormattedText`. Methods marked `"AllowedWhenUntainted"` accept secrets only from Blizzard's secure code, never from addons.

How Blizzard's docs mark what can be secret: `SecretReturns = true` (always, e.g. `UnitHealth`) and `SecretWhen<Condition> = true` (conditional, e.g. `UnitHealthMax`: `SecretWhenUnitHealthMaxRestricted`; `UnitName`: `SecretWhenUnitNameIdentityRestricted`). `Find-WowApi.py -SecretOnly` lists them.

```lua
-- Right: straight into widget setters
bar:SetMinMaxValues(0, UnitHealthMax(unit))
bar:SetValue(UnitHealth(unit))
text:SetFormattedText("%d / %d", UnitHealth(unit), UnitHealthMax(unit))

-- Wrong: errors when the value is secret
if UnitHealth(unit) < 1000 then ... end
label:SetText("HP: " .. UnitHealth(unit))

-- Guard before using a value as a key or in logic
local _, class = UnitClass(unit)
if class and not issecretvalue(class) then color = RAID_CLASS_COLORS[class] end
```

Helpers (global, documented): `issecretvalue`, `canaccessvalue`, `issecrettable`, `hasanysecretvalues`, `scrubsecretvalues`, plus the `C_Secrets.Should*BeSecret` predicates. Durations and curves come from `C_DurationUtil.CreateDuration()` and `C_CurveUtil.CreateCurve()`.

**Event payloads are secret too.** `UNIT_SPELLCAST_*` events are `SecretWhenUnitSpellCastRestricted`, so in combat `interruptedBy` on `UNIT_SPELLCAST_CHANNEL_STOP` / `EMPOWER_STOP` can't be read. Don't treat "secret" as a yes. daves_castbar once showed every combat channel (Blizzard) as interrupted that way. When the deciding value is secret, decide from something you can read: here, whether the cast stopped before its scheduled end (`UnitChannelInfo` end time).

### Unit frame toolbox: showing secrets without touching them (verified 2026-10-20)

Looked up for daves_frames (a target frame) in `Blizzard_APIDocumentationGenerated` on the forever branch. "Tainted OK" = `SecretArguments = "AllowedWhenTainted"`: an addon may pass a secret. "Untainted only" = only Blizzard's own code may pass a secret.

| Need | Use | Notes |
| --- | --- | --- |
| Health, power bars | `bar:SetMinMaxValues(0, UnitHealthMax(u))`, `bar:SetValue(UnitHealth(u), Enum.StatusBarInterpolation.ExponentialEaseOut)` | Interpolation enum: `Immediate`, `ExponentialEaseOut` |
| Heal / absorb segments after the health | `UnitGetIncomingHeals(u)`, `UnitGetTotalAbsorbs(u)` (always secret) into their own bars, anchored to the health bar's fill texture edge | No maths needed; a clipping frame (`SetClipsChildren(true)`) hides overflow. `CreateUnitHealPredictionCalculator()` exists for clamped/overflow values |
| Percent text | `UnitHealthPercent(u, false, CurveConstants.ScaleTo100)` / `UnitPowerPercent(u, type, false, CurveConstants.ScaleTo100)` → `fs:SetFormattedText("%.0f%%", pct)` | Secret result; `CurveConstants` is in `Blizzard_SharedXMLBase/CurveConstants.lua` |
| Short numbers | `AbbreviateNumbers(UnitHealth(u))` → `fs:SetText(...)` | Tainted OK |
| Colour or show/hide from a secret boolean | `tex:SetVertexColorFromBoolean(b, colorIfTrue, colorIfFalse)`, `region:SetAlphaFromBoolean(b, a1, a0)`, `C_CurveUtil.EvaluateColorFromBoolean` | Tainted OK. Use for `notInterruptible` from `UnitCastingInfo` |
| Enemy cast progress | `UnitCastingInfo(u)` start/end ms (secret when restricted) straight into `SetMinMaxValues(startMs, endMs)`, then `SetValue(GetTime() * 1000)` each frame | Never subtract them. `UnitCastingDuration` returns a **secret** duration object and `StatusBar:SetTimerDuration` is untainted only, so don't rely on that pair |
| Aura list | `C_UnitAuras.GetUnitAuraInstanceIDs(u, "HARMFUL|PLAYER")` then `GetAuraDataByAuraInstanceID(u, id)` (secret when restricted) | Icon into `tex:SetTexture(...)` (tainted OK) |
| Aura time left | `C_UnitAuras.GetAuraDuration(u, id)` is **not** secret → `C_DurationUtil.CreateDurationTextBinding()`: `:SetFontString(fs)`, `:SetDuration(d)`, `:SetEnabled(not d:IsZero())` | Blizzard's pattern: `Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua`. `Cooldown:SetCooldownFromDurationObject` is a **protected** function: avoid in addon code |
| Aura stacks | `C_UnitAuras.GetAuraApplicationDisplayCount(u, id, 2, 99)` → string ("" below 2) into `SetText` | |
| Dispel colour | `C_UnitAuras.GetAuraDispelTypeColor(u, id, colorCurve)` with a `C_CurveUtil.CreateColorCurve()` keyed by dispel type ID | Untainted-only arguments; read `auraData.dispelName` when it isn't secret instead |
| Unit 2D portrait | `SetPortraitTexture(tex, u)` (leave 3rd arg `disableMasking` omitted/`false`; oversize `tex` slightly and crop with `MaskTexture`) | Passing `true` unmasks the engine's shared per-unit portrait texture in VRAM and puts a dark `#000E21` square behind Blizzard's stock unit frames |
| Player movement | `IsPlayerMoving()`, `GetPlayerFacing()` (nil in instances) | |

## Other Midnight/Forever restrictions

- **Combat log is gone for addons.** Registering `COMBAT_LOG_EVENT_UNFILTERED` or `COMBAT_LOG_EVENT` **errors**. Don't build damage meters or interrupt trackers on it.
- **Addon messages lock down in instances.** Check `C_ChatInfo.InChatMessagingLockdown()` before `C_ChatInfo.SendAddonMessage`.
- **Display, not calculation.** Blizzard's line: addons can rearrange and restyle information (unit frames, bags, maps, quest helpers, alerts the player configures), but not compute combat decisions (auto-marking, solving mechanics, reading other players' debuffs).
- **Protected actions** (casting, targeting, moving secure frames) still require hardware events and are blocked in combat. Check `InCombatLockdown()` before touching secure frames.

## Removed or moved APIs: common traps

All checked against the forever index. Re-check with `Find-WowApi.py` for anything else.

| Old global | On Forever |
| --- | --- |
| `GetSpellInfo`, `GetSpellCooldown`, `GetSpellTexture` | gone → `C_Spell.*` (removed 11.0.2, warcraft.wiki.gg Patch_11.0.0/API_changes) |
| `UnitAura`, `UnitBuff`, `UnitDebuff` | gone → `C_UnitAuras.GetAuraDataByIndex` / `GetBuffDataByIndex` / `GetDebuffDataByIndex` |
| `GetAddOnMetadata`, `IsAddOnLoaded`, `LoadAddOn`, `GetNumAddOns` | gone → `C_AddOns.*` |
| `GetItemInfo`, `GetItemInfoInstant`, `GetItemQualityByID` | gone → `C_Item.*` |
| `SendAddonMessage` | gone → `C_ChatInfo.SendAddonMessage` |
| `GetCoinTextureString` | gone → `C_CurrencyInfo.GetCoinTextureString` |
| `EasyMenu` | removed; `UIDropDownMenu` is compatibility-only (warcraft.wiki.gg Patch_11.0.0) |
| `InterfaceOptions_AddCategory` | use `Settings.RegisterVerticalLayoutCategory` / `RegisterCanvasLayoutCategory` + `Settings.RegisterAddOnCategory` |

## Settings panel (verified signatures, Blizzard_Settings_Shared/Blizzard_Settings.lua)

```lua
local category = Settings.RegisterVerticalLayoutCategory("My Addon")
local setting  = Settings.RegisterAddOnSetting(category, "MyAddon_enabled", "enabled", MyAddonDB,
                     Settings.VarType.Boolean, "Enabled", true)
Settings.CreateCheckbox(category, setting, "tooltip")
local opts = Settings.CreateSliderOptions(0.5, 2, 0.05)
opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return ("%.2f"):format(v) end)
Settings.CreateSlider(category, numberSetting, opts, "tooltip")
setting:SetValueChangedCallback(function() ... end)
Settings.RegisterAddOnCategory(category)
Settings.OpenToCategory(category:GetID())
```

The Addon Compartment (minimap addon menu) loads on the mainline family, which includes Forever. Add `## AddonCompartmentFunc: GlobalFunctionName` to the TOC.

## Edit Mode: one shared behaviour (house rule, enforced)

Any addon frame the player places in Edit Mode uses the kit's **`templates/editmode/EditModeDialog.lua`** for its outline, dragging, snapping and settings dialog. Copy it into the addon **unchanged** and list it in the TOC right after `Core.lua`. `New-WowAddon.py -EditMode` does that and also adds an `EditMode.lua` already wired up with `ns.EditMode.Attach`. Never hand-build any of it.

The validator enforces this in any addon that listens for `EditMode.Enter`/`EditMode.Exit` or uses `ns.EditMode`:
- `editmode-dialog`: error when the copy is missing, warning when a copy differs from the kit's.
- `editmode-ui`: error for a hand-built panel, slider or checkbox.
- `editmode-snap`: error for hand-rolled grid snapping (`gridSpacing`, `IsSnapEnabled`, `EditModeMagnetismManager`), warning for a frame dragged without `ns.EditMode.SnapRect` or `Attach`.
- `editmode-onupdate`: warning when `SetScript("OnUpdate")` is placed directly on a frame passed to `ns.EditMode.Attach` (which overwrites `OnUpdate` while dragging).
- `editmode-openfor`: warning when an `ns.EditMode.CreateDialog` dialog is anchored via `:SetPoint()` instead of opened via `dialog:OpenFor(frame)`.

Everything is modelled on Blizzard's own Edit Mode (`Blizzard_EditMode/Shared/EditModeDialogs.xml`, `EditModeUtil.lua`, forever branch):
- **Same look:** translucent dialog border, large title, close button, a label column, sliders with their number on the right, 32px checkboxes, full-width buttons under a divider. Frames get Blizzard's Edit Mode outline: blue while movable, yellow while selected, a glow on hover, and it stays solid while the frame fades.
- **Text fits:** every width is measured from the real strings, including each slider's widest number, so nothing runs past the border.
- **Nothing layered over:**
  - Only one settings dialog is open at a time, across Blizzard's and every addon's. Opening one clears Blizzard's selection (`EditModeManagerFrame:ClearSelectedSystem()`, a secure delegate, so it's taint-safe) and closes other addons' dialogs.
  - It opens beside its frame, clear of that frame, Edit Mode's window and the screen edges.
  - If a setting (Scale, Reset) moves the frame under the dialog, the dialog steps aside once the mouse is off it, unless the user has dragged the dialog themselves.
- **Same snapping as Blizzard's frames:** it only works with "Snap" ticked. The frame moves freely and pulls onto something within 8 screen pixels: grid lines, the screen edges and centre, the facing edge of a Blizzard Edit Mode frame beside it, or the addon's other frames. Shift places freely. Resized edges snap the same way (`SnapEdge`).

```lua
-- The standard way: one call does the outline, Edit Mode on/off, snapping drag, click, right-click, tooltip.
local d = ns.EditMode.CreateDialog("MyAddonEditDialog", "My Frame")
d:AddSlider({ label = "Width", min = 80, max = 800, step = 1, format = "%d",
	get = function() return db.width end, set = function(v) db.width = v; ns:Layout() end })
d:AddCheckbox({ label = "Show text", tooltip = "...", get = ..., set = ... })
d:AddColor({ label = "Colour", get = function(frame) ... end, set = function(c, frame) ... end,
	saved = function(frame) ... end })   -- frame: the one the colour picker was opened for
d:AddButtonGrid({ label = "Position", columns = 3, buttons = { { key = "left", text = "Left" }, ... },
	onClick = ..., isActive = ... })     -- also the way to offer a choice of a few options
d:AddNote({ text = function() return "" end })   -- "" hides it
d:AddButton({ text = "Reset position", onClick = ... })
local handle = ns.EditMode.Attach(frame, { label = "My Frame", dialog = d,
	onMoved = function(f) --[[save f:GetPoint(1)]] end, onReset = function(f) end,
	canMove = function() return not db.locked end })   -- optional: movable outside Edit Mode too
-- handle:Update() after changing what canMove() reads; d:Refresh() after settings change elsewhere;
-- d:RefreshValues() every frame during a live drag (values only, no relayout).

-- Frames with extra handles (a resize grip, a secure child) can use the pieces instead, as
-- daves_castbar and daves_balls do: CreateSelection, SnapRect/SnapEdge in the drag's OnUpdate,
-- dialog:OpenFor(frame) on click.
```

To change the look or behaviour, edit the kit's file, then copy it into every addon that has one.

## Habits that keep addons working across patches

- Keep everything `local` and share state through the addon namespace (`local ADDON, ns = ...`). Accidental globals cause taint and name clashes.
- Bag replacements: hide Blizzard's container frames (`ContainerFrameN`, `ContainerFrameCombinedBags`) by parking them on a hidden parent, and **leave their events alone** (verified in game 2026-10-21, daves_sack 1.7.14). daves_sack also `UnregisterEvent`ed them from addon code, while showing its own window from `hooksecurefunc` hooks on the bag functions. Together those two tainted every window whose OnShow calls `OpenAllBags`, which means the bank and the mailbox. The bank's free first tab was blocked (`C_Bank.PurchaseBankTab`). Every item used from the bags in combat after a bank visit was blocked too (`UseContainerItem`), because Blizzard's item click reads `BankPanel.bankType` even with the bank closed (Forever's `BankPanel` never hides). Either piece alone left no taint.
- Use plain color textures, verified Forever atlases (`OptionsIcon-Brown`, `Minimal_SliderBar_Button`, `common-button-list-plus`, `common-icon-backarrow`), or your own `.tga` files for art. Blizzard loose texture paths move between clients, and verified atlases work immediately on `/reload` without a client restart.
- Keep `GameFont*` / `FRIZQT__.TTF` strings pure 7-bit ASCII (no `●`, `▸`, `▾`, `•`, `—`, `–`, `…`, `×`, which render as `[]` tofu boxes) and keep string truncation UTF-8 and `|c...|r` color-escape safe.
- On `DialogBorderTranslucentTemplate` backgrounds, reset `bg:SetVertexColor(1, 1, 1, 1)` after `bg:SetColorTexture(0, 0, 0, a)` (prevents `a * a` double-alpha after textured styles), anchor settings dialogs to `UIParent` rather than the frame they scale, guard `MinimalScrollBar` `OnScroll` callbacks with a `syncingScroll` flag, and guard `Settings.NotifyUpdate` calls with a `syncingSettings` re-entrancy flag.
- Never call `WorldMapFrame:Minimize()` or `WorldMapFrame.BorderFrame.MaximizeMinimizeFrame:Minimize()` from addon code (taints `WorldMapFrame.isMaximized` and blocks closing the map in combat); set `miniWorldMap = "1"` / `mapFade = "0"` via `C_CVar.SetCVar` at `ADDON_LOADED`/`PLAYER_LOGIN` instead.
- See `.claude/skills/wow-forever-pitfalls/SKILL.md` for the full checklist of one-off Forever UI, font, scrollbar, dialog, and map-layer lessons.
- Initialise SavedVariables in your own `ADDON_LOADED` (when `name == ADDON`).
- Run the **wow-addon-test** skill after every change to addon code. It builds the `Prepare-WowReview.py` packet (static validation, `ModuleHealth`, diff, `NOTES.md`, and Forever API annotations), then runs the **wow-addon-reviewer** review (inline for small clean diffs, or subagent with the packet): auto-apply clear, unambiguous `Confirmed` fixes right away, re-validate, and list what was fixed — prompting the user only when a finding genuinely needs design/direction input (`Needs Direction`).
