---
name: wow-forever-pitfalls
description: Hard-won WoW Forever UI, font, taint, scrollbar, dialog-styling, and map-layer lessons to prevent one-off bugs from recurring across daves_* addons. Read whenever building or modifying WoW Forever addon UI strings, translucent dialogs, scrollbars, Blizzard Settings sync, virtualized lists, or World Map / Quest Map integrations.
---

# WoW: Forever Addon Pitfalls & Anti-Regression Playbook

Concrete, source-verified lessons captured from real bugs in `daves_*` addons on **WoW: Forever** (`camelot`, Interface `16001`). Check these before editing UI code so none of these one-off bugs ever reappear.

---

## 1. Fonts & Missing-Glyph `[]` Tofu Boxes (`FRIZQT__.TTF`)

- **Rule: Pure 7-bit ASCII only in `GameFont*` / `FRIZQT__.TTF` strings.**
  - Never put `●` (`U+25CF`), `▸` (`U+25B8`), `▾` (`U+25BE`), `•` (`U+2022`), `—` (`U+2014`), `–` (`U+2013`), `…` (`U+2026`), `×` (`U+00D7`), `→`/`←`, or `✓`/`✕` inside `GameFont*` strings (`GameFontHighlightSmall`, `GameFontDisableSmall`, `GameFontNormal`, `GameTooltip` lines). Blizzard's own UI avoids `•` in `FRIZQT__.TTF` (switching to `ARIALN.TTF` for bullet widgets).
  - **Use instead:** Pure ASCII separators (`"-"`, `" - "`, `"/"`, `"[+]"`, `"[-]"`, `"x"`, `"..."`), real `.tga` textures (`Media/dot.tga` for active-layer indicator dots), or verified Forever atlases (`common-button-list-plus`, `common-button-list-minus`, `common-icon-backarrow`).
- **Rule: Truncation helpers (`Shorten`) must be UTF-8 and color-code safe.**
  - Raw `s:sub(1, lim - 3)` can split a multi-byte UTF-8 character (from user input or localized text), producing invalid UTF-8 bytes that WoW renders as `[]`, or split a `|cAARRGGBB` color tag mid-escape.
  - Always walk back past UTF-8 continuation bytes (`0x80..0xBF`), drop incomplete lead bytes (`>= 0xC0`), strip trailing incomplete `|c...` / `|`, and append `|r` if open `|c` tags outnumber `|r`.

---

## 2. HUD Edit Mode Dialog Chrome & Background Styles (`DialogBorderTranslucentTemplate`)

- **Rule: Reset `SetVertexColor(1, 1, 1, 1)` when switching back to `SetColorTexture`.**
  - Textured styles (`Light paper`, `Dark paper`, `Marble`, `Rock`) call `bg:SetVertexColor(1, 1, 1, a)`. If switching back to `"dark"` calls `bg:SetColorTexture(0, 0, 0, a)` **without** `bg:SetVertexColor(1, 1, 1, 1)`, WoW multiplies color-texture alpha `a` by vertex alpha `a` (`a * a`, so `50%` renders at `25%`).
- **Rule: Keep inner scrims style-aware.**
  - Stacking an unconditional `0.35–0.60` black box over `leftRail` or `listBg` hides `Dark paper` / `Rock` textures and breaks `20%` low-opacity translucency, while still leaving grey `GameFontDisableSmall` text illegible on bright `Marble`.
  - Use light scrims (`0.08–0.10`) on `dark` / `darkdialog` / `rock`, modest (`0.18–0.24`) on `dialog` (Light paper), and a darker readability scrim (`0.48–0.50`) on `marble`.
- **Rule: Never anchor a Settings/Style dialog to the frame it scales or resizes.**
  - If a Settings window is anchored `TOPLEFT -> TOPRIGHT` of the frame it controls, dragging the **Scale** slider shifts the parent frame's edge and moves the dialog out from under the cursor. Compute screen coordinates once on open and anchor the dialog to `UIParent` instead.
- **Rule: Two-way sync with `Esc > Options > AddOns` needs a re-entrancy guard.**
  - In windowed UIs, players can have `Esc > Options > AddOns` open beside the addon. Call `Settings.NotifyUpdate(ADDON .. "_" .. key)` when `SettingsPanel and SettingsPanel:IsShown()`, wrapped in a `syncingSettings` boolean checked at the top of every `SetValueChangedCallback` — because `SettingMixin:NotifyUpdate()` synchronously re-fires `SetValueChangedCallback`.

---

## 3. Scrollbars, Virtualized Lists & Row Geometry

- **Rule: Use Blizzard's native `MinimalScrollBar` (or `ScrollFrameTemplate`) with a `syncingScroll` guard.**
  - Reserve a `16px` right gutter (`SCROLL_GUTTER = 16`), call `sb:SetHideIfUnscrollable(true)`, and anchor `sb` at `+4px` right of the clipped list (note `MinimalScrollBar`'s thumb has `4px` `HitRectInsets` on each side).
  - Always guard `OnScroll` callbacks with `if ui.syncingScroll then return end` when calling `SetScrollPercentage(pct, true)`, because `ScrollBarMixin:SetScrollPercentageInternal` synchronously triggers `Event.OnScroll` (otherwise causing `C stack overflow`).
- **Rule: Full widget reset + tooltip cleanup on virtualized row reuse.**
  - `ResetRow(row)` must reset every mutable anchor, width, justification (`SetJustifyH`), color, alpha, desaturation, and child frame visibility (`header`, `header.tick`, `qcols`, `minusBtn`, `colLvl`/`colChain`/`colXP`).
  - Whenever `Render()` hides or rebinds rows, check `GameTooltip:GetOwner()` (including child buttons like `row.header` or `row.qcols` column buttons) and hide stale tooltips cleanly.
- **Rule: Pass `useAtlasSize = true` for non-square Blizzard atlases like `common-button-list-minus`.**
  - `common-button-list-plus` is square (`~14x14`), whereas `common-button-list-minus` is a wide horizontal bar (`~14x4`). Calling `tex:SetAtlas("common-button-list-minus", false)` on a square `12x12` texture stretches the minus bar vertically into a solid yellow square block. Always pass `true` (`tex:SetAtlas(atlas, true)`) so Blizzard preserves the atlas's native aspect ratio.
- **Rule: Check selection-bar and NineSlice rim geometry in pixels.**
  - Keep `row.selBar` (`width = 3`, `x = [0, 3]`) clear of `row.icon` (`x >= 5`) and tinted row backgrounds (`x >= 4`) so the selection bar never paints over the left pixel of icons.
  - On Forever (`Camelot`), `WorldMapFrame.BorderFrame` NineSlice protrudes `+2px` past `GetRight()` and `-13px` past `GetLeft()`, while `DialogBorderTranslucentTemplate`'s `Bg` is inset `7px`. Dock flush at `-4` on the right and `-10` on the left so metallic rims kiss without overlapping the left border.

---

## 4. World Map Taint, Windowed Mode & Reference Layers

- **Rule: Never call `WorldMapFrame.BorderFrame.MaximizeMinimizeFrame:Minimize()` (or `WorldMapFrame:Minimize()`) from addon code.**
  - Calling it writes `WorldMapFrame.isMaximized = false` in tainted execution context and invokes `ShowUIPanel`/`UpdateUIPanelPositions`. Pressing `M` or `Esc` during combat later reads tainted `isMaximized` inside `HandleUserActionToggleSelf()` and blocks closing the map (`CheckProtectedFunctionsAllowed`).
  - **Use instead:** Call `C_CVar.SetCVar("miniWorldMap", "1")` and `C_CVar.SetCVar("mapFade", "0")` during `ADDON_LOADED` and `PLAYER_LOGIN` (combat-guarded, before `WorldMapFrame` opens) and hide `MaximizeMinimizeFrame`. Blizzard's own `WorldMapMixin:OnShow` then opens windowed completely taint-free.
- **Rule: Selection changes must ALWAYS trigger a canvas rebuild, even when reference layers are hidden.**
  - Never gate `ns.Refresh()` behind `if state.refMode ~= nil` in `SetFocusedPin` — otherwise clicking a quest while the layer is hidden does nothing on the map until the user pans or zooms.
- **Rule: `Hide Layer` and `Show Layer` must be atomic and immediate.**
  - `Hide Layer` (`SetRefLayer(nil)`) must clear `refMode`, `refSet`, `lockedPin`, pinned dungeon context, and immediately sync HUD pills (bypassing any `0.05s` `OnUpdate` banner throttle) so no orphan pins or stale pills remain.
  - `Show Layer` must close an open dungeon floor map first (otherwise `OnUpdate` returns early while `DungeonViewShown()` is true) and pre-populate `RefreshRefLayerSet(zMap)` so counts never flash `(0)`.
- **Rule: Respect pinned context when navigating to out-of-zone quest starters.**
  - When viewing a dungeon's quest starters (e.g., Stormwind Stockade starters in Redridge/Duskwood/Westfall), pin the dungeon zone (`refPinnedMap` / `dungeonZoneLock`) so flying the camera to an out-of-zone pickup NPC never wipes out the dungeon list or starter pins. Preserve that lock across `Show Layer` and `< Back` history.

---

## 5. Quest Completion, Async Data & Zero-Restart Assets

- **Rule: Per-character quest completion on Forever.**
  - Always exclude quests currently in this character's log (`C_QuestLog.IsOnQuest`), require `C_QuestLog.IsQuestFlaggedCompleted(q) == true`, and gate account-wide quests (`C_QuestLog.IsAccountQuest(q)`) by a per-character `CharDB.doneQuests` table so alts don't show Warband completions as done.
- **Rule: Prefer verified Blizzard atlases for new UI icons & slider thumbs.**
  - Adding new `.tga` files or `.toc` entries requires a full client restart, whereas verified Forever atlases (`OptionsIcon-Brown`, `Minimal_SliderBar_Button`, `common-button-list-plus`, `common-icon-backarrow`, `Waypoint-MapPin-Tracked`) work immediately on `/reload`.
- **Rule: Never trigger async C++ preloads inside bulk list builders.**
  - Call `C_Item.RequestLoadItemDataByID` / `C_QuestLog.RequestLoadQuestByID` only on visible/hovered items, and refresh active hover tooltips on `ITEM_DATA_LOAD_RESULT` / `QUEST_DATA_LOAD_RESULT` (using in-place `RenderPanelRows()` on `ITEM_DATA_LOAD_RESULT` instead of full list rebuilds).

---

## 6. Consistent `daves_*` Gold/Brass Icons & Uniform Brass Pill Buttons

When creating custom toolbar icons or small pill buttons across any `daves_*` addon, follow the established **`daves_sack` / `daves_map` handcrafted gold/brass style** (reference generators: `wowaddons/daves_sack/tools/Make-SackMedia.py`, `wowaddons/daves_map/tools/Make-Media.py`):

- **TGA Binary Format:** Uncompressed 32-bit BGRA TGA, top-left origin (`struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)`), power-of-two dimensions (`64x64` for icons, `128x64` for `2:1` pill frames). New `.tga` files require a **full WoW client restart**.
- **Gold/Brass Palette & SDF Shading:**
  - Dark outline: `RGB(20, 12, 2)`, outer anti-aliased edge `1 - smoothstep(-0.6, 0.7, d)`, interior metal boundary `d_metal = d + 1.85..2.0`.
  - Gold metal gradient: shadow `RGB(118, 86, 22)` -> highlight `RGB(242, 200, 91)` (`diag = (1 - (px - 8) / 48) * 0.55 + (1 - (py - 6) / 52) * 0.45`, cylindrical cosine sheen `0.20 * cyl`, upper-left bevel specular boost `+0.18` where `-4.2 < d_metal < -1.1`).
  - Paint paired glyphs like `plus.tga` and `minus.tga` on identical `64x64` square canvases with identical bar half-thickness (`hy = 6.8`) so `-` never stretches.
- **Borderless Toolbar Icon Buttons (No `BackdropTemplate` Box):**
  - Use a plain `CreateFrame("Button", nil, parent)` (`22x22`) with a centered `18x18` `ARTWORK` texture (`alpha = 0.78` resting; `1.0` + `OVERLAY` `ADD` glow at `0.35` alpha when active) and a centered `18x18` `HIGHLIGHT` texture (`SetBlendMode("ADD")`, `alpha = 0.45`).
- **Uniform Brass Pill Buttons (Never Use `BackdropTemplate` `edgeSize = 1`):**
  - `BackdropTemplate` with `edgeSize = 1` suffers from sub-pixel rounding at non-`1.0` UI scales (making one edge, often the bottom, render `2px` thick while the other three stay `1px`).
  - Instead, paint a symmetric anti-aliased beveled brass **`Media/pill.tga`** (`128x64`, `corner_r = 12`, uniform `border_w = 5.4`, recessed dark fill `RGB(15, 14, 12)` @ `0.90` alpha) on a plain `Button` with `pill.tga` `ADD` highlight (`0.35` alpha), warm cream/gold text (`|cffe8d8a8...|r` resting, `|cffffd200...|r` active), and comfortable outer padding (`>= 6px` inset inside `30px` bars for `21px` buttons). For buttons wider than `2:1` (e.g., `Clear`, `Show All`, `< Back`), 3-slice `pill.tga` horizontally (`0..0.25` left cap `width = height / 2`, `0.25..0.75` center strip, `0.75..1.0` right cap `width = height / 2`) so rounded corners and vertical borders never stretch horizontally.

