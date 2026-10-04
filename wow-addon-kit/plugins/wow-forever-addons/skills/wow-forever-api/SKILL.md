---
name: wow-forever-api
description: Facts and rules for writing World of Warcraft addon Lua that works on WoW Forever (internal game type "camelot", client 1.60.x, Interface 16001), plus Retail/Midnight and Classic. Covers secret values, combat-log removal, addon-comms lockdown, TOC game-type rules, Forever detection, API lookups, and the shared Edit Mode settings dialog every movable addon frame must use. Use whenever writing, reviewing or debugging WoW addon code, choosing a WoW API, or answering "does X exist / work on Forever".
---

# WoW: Forever addon API

WoW: Forever runs on the **modern (Mainline) client** with the **same addon API and restrictions as Retail Midnight (12.x)**, no lighter version. Code written for Classic Era's old API will not work there unchanged.

## Rule zero: look it up, don't recall it

Your training data predates Forever, and APIs move every patch. Before you use or recommend any API, check it against the local index built from Blizzard's own client source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Find-WowApi.ps1" GetSpellInfo
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Find-WowApi.ps1" "C_UnitAuras.*"
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Find-WowApi.ps1" UNIT_AURA -Events
powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Find-WowApi.ps1" "Unit*" -SecretOnly
```

If the index is missing or older than a patch, rebuild it (about one minute): `scripts/Update-WowApiIndex.ps1 -Branch forever`.
For behaviour details, read Blizzard's own code in the `forever` branch of https://github.com/Gethe/wow-ui-source, and the API pages on https://warcraft.wiki.gg. See [sources.md](sources.md) for what each source is good for.

## Facts (verified 2026-10-03)

| Fact | Value | Source |
| --- | --- | --- |
| Client version / Interface | 1.60.1 → `## Interface: 16001` | warcraft.wiki.gg Public_client_builds; installed `.build.info` |
| Project ID | `WOW_PROJECT_CAMELOT = 18`, `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` | `Blizzard_ProjectConstants/Camelot/ProjectConstants.lua` |
| TOC game type | `camelot`, inside the `mainline` family | Blizzard's own TOCs, e.g. `Blizzard_UnitFrame.toc` |
| TOC path variables | `[Family]` → `Mainline`, `[Game]` → `Camelot` | same |
| Client-specific TOC | `<Name>_Camelot.toc` | warcraft.wiki.gg TOC_format |
| Beta install folder | `_classic_beta_` (product `wow_classic_beta`) | local install; the launch folder may differ, so use `Find-WowInstall.ps1` |

The Interface number can change at launch (expected November 2026) or with any patch. `Find-WowInstall.ps1` reads it from the installed build, so prefer that over this table.

### Detecting Forever at runtime

```lua
local IS_FOREVER = WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
```

Prefer **feature detection** over project checks for API differences, so one file runs everywhere:

```lua
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local GetItemInfo      = (C_Item and C_Item.GetItemInfo) or GetItemInfo
```

### TOC targeting

- One TOC for every flavor: `## Interface: 16001, 120100, 11509`.
- `[AllowLoadGameType mainline]` **includes Forever**. Blizzard itself has to add `[ExcludeLoadGameType camelot]` to opt Forever out. Use `camelot` to target Forever only.
- Per-file variants: `[Game]\Feature.lua` loads `Camelot\Feature.lua` on Forever.
- TOC or new-file changes need a full client restart; `/reload` only re-runs Lua/XML.

## Secret values (Midnight and Forever)

In restricted contexts (combat, instances, other players), many APIs return **secret values**: opaque values addon code can't inspect. Source: warcraft.wiki.gg Patch_12.0.0/API_changes, plus the `Secret*` fields in Blizzard_APIDocumentationGenerated.

**Errors at runtime on a secret:** comparison (`<`, `==`), arithmetic, concatenation (`..`), using it as a table key.

**Allowed:** passing it to widget methods Blizzard marks `SecretArguments = "AllowedWhenTainted"`. These include `StatusBar:SetMinMaxValues`, `StatusBar:SetValue`, `FontString:SetText` and `FontString:SetFormattedText`. Methods marked `"AllowedWhenUntainted"` accept secrets only from Blizzard's secure code, never from addons.

How Blizzard's docs mark what can be secret: `SecretReturns = true` (always, e.g. `UnitHealth`) and `SecretWhen<Condition> = true` (conditional, e.g. `UnitHealthMax`: `SecretWhenUnitHealthMaxRestricted`; `UnitName`: `SecretWhenUnitNameIdentityRestricted`). `Find-WowApi.ps1 -SecretOnly` lists them.

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

## Other Midnight/Forever restrictions

- **Combat log is gone for addons.** Registering `COMBAT_LOG_EVENT_UNFILTERED` or `COMBAT_LOG_EVENT` **errors**. Don't build damage meters or interrupt trackers on it.
- **Addon messages lock down in instances.** Check `C_ChatInfo.InChatMessagingLockdown()` before `C_ChatInfo.SendAddonMessage`.
- **Display, not calculation.** Blizzard's line: addons can rearrange and restyle information (unit frames, bags, maps, quest helpers, alerts the player configures), but not compute combat decisions (auto-marking, solving mechanics, reading other players' debuffs).
- **Protected actions** (casting, targeting, moving secure frames) still require hardware events and are blocked in combat. Check `InCombatLockdown()` before touching secure frames.

## Removed or moved APIs: common traps

All checked against the forever index. Re-check with `Find-WowApi.ps1` for anything else.

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

Any addon frame the player places in Edit Mode uses the kit's **`templates/editmode/EditModeDialog.lua`** for its outline, dragging, snapping and settings dialog. Copy it into the addon **unchanged** and list it in the TOC right after `Core.lua`. `New-WowAddon.ps1 -EditMode` does that and also adds an `EditMode.lua` already wired up with `ns.EditMode.Attach`. Never hand-build any of it.

The validator enforces this in any addon that listens for `EditMode.Enter`/`EditMode.Exit` or uses `ns.EditMode`:
- `editmode-dialog`: error when the copy is missing, warning when a copy differs from the kit's.
- `editmode-ui`: error for a hand-built panel, slider or checkbox.
- `editmode-snap`: error for hand-rolled grid snapping (`gridSpacing`, `IsSnapEnabled`, `EditModeMagnetismManager`), warning for a frame dragged without `ns.EditMode.SnapRect` or `Attach`.

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
- Use plain color textures or your own `.tga` files for art. Blizzard texture paths move between clients.
- Initialise SavedVariables in your own `ADDON_LOADED` (when `name == ADDON`).
- Run the **wow-addon-test** skill after every change to addon code. It validates, then has the **wow-addon-reviewer** agent review the code in advisor mode. Show the user its findings and wait for their go-ahead before applying any.
