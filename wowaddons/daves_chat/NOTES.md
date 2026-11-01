# Dave's Chat — Architecture & Handoff Notes

Start here on the next run. WoW does not load this file.

Last updated 2026-10-31. Addon version **0.3.0**. Flavor **Forever** (`## Interface: 16001, 11509, 20506`). Folder `wowaddons/daves_chat`. Slash `/daveschat`. Icon `Interface\Icons\INV_Misc_Note_01`. Author `davidwhit5`. Edit Mode is enabled via the unmodified kit copy `EditModeDialog.lua`.

---

## 1. Overview & Default Tabs

Blizzard still owns message rendering, chat filters, the combat log, and `ChatConfigFrame`. Dave's Chat seats Blizzard's dock inside a movable/resizable dialog window with a left-side vertical tab stack, a bordered inner chat-text frame on the right, top-down message growth (newest on top), a clean top header bar (`Social`, `Channels`, optional `TTS`, `Settings`, and top-right `X` close button), a separate `Settings` launcher dialog, and three default tabs configured once (`layoutVersion = 1`):

| Tab | Frame | Contents |
| --- | --- | --- |
| **Chat** | `ChatFrame1` | Say, emote, party, instance party, whispers (including Battle.net) |
| **Combat Log** | `ChatFrame2` | Blizzard's combat log (`COMBAT_LOG`); filters untouched; `CombatLogQuickButtonFrame_Custom` reparented to `DavesChatAnchor` inside `ns.chatBox` while we hide `ChatFrame2Tab` |
| **General** | `ChatFrame4` | Yell, guild, raid, numbered channels, loot, system, ping, guild achievements, and remaining non-combat groups (`ChatFrame3` is Blizzard's voice transcription window and is left alone) |

SavedVariables (`daves_chatDB`): `enabled` (`true`), `routeChannels` (`true`), `layoutVersion` (`0` until first tab apply), `width` (`520`, min `430`), `height` (`320`, min `180`), `scale` (`1`, `0.5`–`2.0`), `background` (`0.8`, `0.2`–`1.0`), `backgroundStyle` (`"dark"`), `collapsed` (`false`), `whisperAlert` (`true`), plus `pos` (window anchor) and `iconPos` (draggable `"Chat"` open button, initialized to the window's bottom-left corner on first collapse).

---

## 2. File Map & Load Order

Load order in `daves_chat.toc`:

| File | Responsibility |
| --- | --- |
| `Core.lua` | Constants (`MIN_WIDTH = 430`, `MIN_HEIGHT = 180`, `TAB_WIDTH = 100`, `DEFAULT_POS`, `DEFAULTS`), helpers (`Clamp`, `Sound`, `Defer`, `HasAtlas`, `Print`), `ADDON_LOADED` / `PLAYER_LOGIN`, `/daveschat` (`settings`, `chat`, `window`, `options`, `tabs`, `reset`, `version`), compartment click |
| `EditModeDialog.lua` | **Unmodified kit copy** (`wow-addon-kit/plugins/wow-forever-addons/templates/editmode/EditModeDialog.lua`). Never edit in-place. |
| `Tabs.lua` | Default message groups, `ns:ApplyTabLayout`, `ns:RouteChannels`, vertical left-side `UIPanelButtonTemplate` tab stack inside `ns.tabColumn` (`ns:RefreshTabs`) with active highlight lock, truncation tooltips, and unread/whisper pulse, plus login & channel routing events |
| `Dock.lua` | Deduplicated `ns.EachDocked`, `ns:ContentTop`, `ns:MinFrameHeight`, top-down message growth (`ApplyInsertMode` using `SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP` / `BOTTOM`), owned scale (`ns:ApplyOwnedScale`, `ns:ResetOwnedScale`, `ns:ApplyScale`), unified chrome sync (`ns:SyncChatChrome` for `"open"`, `"closed"`, `"restore"` + `ns:EnforceOwnedChrome`), synchronous per-message flicker guards (`ns:HookChatFlickerGuards`), synchronous pre-draw position/size guards (`ns:HookChatPositionGuards`, `ns:IsChatSeated`), and `ns:SeatChat` (`ClearAllPointsBase` / `SetPointBase`) |
| `Header.lua` | Internal top header bar (`ns.settingsBar`), top-right `UIPanelCloseButton` (`ns.closeButton`), single `"Settings"` gear button (`ns.settingsButton`), separate `"Settings"` launcher dialog (`DavesChatSettingsMenu` opening `Chat Settings`, `Window Settings`, and `AddOn Options` independently), synchronous `QuickJoinToastButton` / `ChatFrameChannelButton` / `TextToSpeechButtonFrame` pinning & restore, and combat-guarded `ns:PadChatConfig` / `ns:OpenChatConfig` |
| `Window.lua` | Background styles & `ns:ApplyBackground` (outer dialog fill, recessed `ns.chatBoxFill`, light/dark divider contrast, plus `Settings` and `Window Settings` fills), shared `MakeSnapMover`, outer dialog border + `BACKGROUND` `ns.fill`, left `ns.tabColumn`, bordered inner `ns.chatBox` (`InsetFrameTemplate`), corner resize grips, draggable `"Chat"` open button (`DavesChatToggle`), `ns.messageWheel`, whisper pulse, single-pass `ns:LayoutWindow`, `ns:ApplyEnabled`, `ns:SetCollapsed`, `ns:Init` |
| `EditMode.lua` | `ns:ApplyPosition`, `ns:ResetPosition`, `ns:InitEditMode` (`d.OpenFor` keeps `"Window Settings"` title; `d.Layout` adds `8px` inner padding while keeping `Divider` centered) |
| `Options.lua` | `Esc > Options > AddOns > Dave's Chat` checkboxes (`enabled`, `routeChannels`, `whisperAlert`) and combat-guarded `ns:OpenOptions` |
| `Media/gear.tga`, `Media/grip.tga` | Uncompressed 32-bit `.tga` icons shared with Dave's Sack |

---

## 3. Architecture & Verified Forever UI Facts

- **Single-Pass Layout (`ns:LayoutWindow`)**: `PlaceSettings`, `PlaceHeaderButtons`, `SeatChat`, and `RefreshTabs` are decoupled (none calls the others) and run once in dependency order inside `ns:LayoutWindow()`.
- **Top-Down Message Growth (`ScrollingMessageFrame.lua:297, 591-605, 898-900`)**:
  - `ScrollingMessageFrameSecureMixin:SetInsertMode(insertMode)` is an official untainted elevation barrier exposed for addons.
  - Owned docked frames use `SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP` (`1`, fallback `"TOP"`), which anchors `visibleLines[1]` (the newest line at `scrollOffset == 0`) at `TOPLEFT` and grows older messages downward. Both `ScrollUtil.InitScrollingMessageFrameWithScrollBar` (`ScrollUtil.lua:159-211`) and `ns.ScrollFrameByWheel` automatically invert scrollbar percentage and wheel direction when `GetInsertMode() == SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP`.
  - Undocked frames and `"restore"` mode reset `SetInsertMode` back to `SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM` (`2`, fallback `"BOTTOM"`).
- **No Reparenting or Script Hooks on `ChatFrameN` — Why We Seat `ChatFrame1..10` Synchronously Before Draw Instead of a Separate Target Frame**:
  - **Why not a separate custom `ScrollingMessageFrame` target?** On Forever (12.x), `ChatFrame1..10` own secure `CircularBuffer` message history (`CircularBuffer.lua:160` `SecureTypes.CreateSecureNumber()`), `SetItemRef(link, text, button, chatFrame)` player report / whisper / mature-language uncensor callbacks (`TransformMessages` / `RemoveMessagesByPredicate` / `UpdateColorByID` keyed on `ChatFrameN:GetID()`), `CombatLogDriverFrame` + `CombatLogQuickButtonFrame_Custom` (`Blizzard_CombatLog.lua:1576, 1696` measuring and writing directly to `ChatFrame2`), and `$parentEditBox` anchoring (`ChatFrame1EditBox..ChatFrame10EditBox` anchored directly to `ChatFrameN`).
  - **Why `ChatFrame1` previously flashed or stayed in Blizzard's real chat window, and how synchronous pre-draw seating eliminates it**:
    - `ScrollingMessageFrame` (`ScrollingMessageFrame.xml:10, 14`, `ScrollingMessageFrame.lua:370-381, 578-667`) clips children to its own rectangle and does **not** lay out or populate `FontString`s during `:AddMessage` or `:SetSize` — those only mark `isDisplayDirty` / `isLayoutDirty`, and actual line layout happens later in `OnPostUpdate` (`RefreshIfNecessary`) right before C++ renders the frame.
    - Previously, reseating on `EditModeManagerFrame:UpdateLayoutInfo`, `EDIT_MODE_LAYOUTS_UPDATED`, and `UPDATE_CHAT_WINDOWS` was deferred via `C_Timer.After(0)` (allowing 1 frame to render at Blizzard's Edit Mode chat position), `ChatFrame1:ApplySystemAnchor` / `UpdateSystem` / `UpdateSystemSettingWidth` / `UpdateSystemSettingHeight` weren't hooked directly, `Window.lua`'s `watcher` early-returned whenever `DavesChatAnchor` hadn't moved (ignoring `ChatFrame1` drift), and `SeatChat` called `ChatFrame1:SetPoint` (`EditModeSystemMixin:SetPointOverride`) instead of `SetPointBase`.
    - Now `ns:SeatChat()` uses `ClearAllPointsBase` / `SetPointBase` (`EditModeSystemTemplates.lua:13-17`, avoiding `SetSnappedToFrame` and `OnEditModeSystemAnchorChanged`), `ns:HookChatPositionGuards()` attaches synchronous `hooksecurefunc` post-hooks to `ChatFrame1`'s existing Lua mixin methods (`ApplySystemAnchor`, `UpdateSystem`, `UpdateSystemSettingWidth`, `UpdateSystemSettingHeight`, `SetPoint`, `SetScale`) plus `FloatingChatFrame_Update`, `FCF_RestorePositionAndDimensions`, `FCF_DockUpdate`, `FCFDock_ForceReanchoring`, and `EditModeManagerFrame` (`UpdateLayoutInfo`, `ExitEditMode`, `RevertAllChanges`), event handlers (`UPDATE_CHAT_WINDOWS`, `UPDATE_FLOATING_CHAT_WINDOWS`, `EDIT_MODE_LAYOUTS_UPDATED`, `DISPLAY_SIZE_CHANGED`, `UI_SCALE_CHANGED`, `PLAYER_REGEN_ENABLED`) reseat synchronously, and `watcher` checks `ns:IsChatSeated()` (pausing only while the user actively selects/drags `ChatFrame1` itself inside Edit Mode so `EditModeManagerFrameMixin:UpdateSystemAnchorInfo` never serializes `DavesChatAnchor`). Every Blizzard reset is undone in the exact same Lua call stack **before** `OnPostUpdate` lays out text and before any frame draws.
  - `ChatFrame1` is anchored inside `ns.chatBox` (relative to `DavesChatAnchor`), never reparented, never `Hide()`d (`OnHide` marks the chat window hidden in `SetChatWindowShown`), and never shrunk to `1x1`. Docked tabs follow `ChatFrame1`'s rectangle via Blizzard's dock (`ChatFrame2` drops its `TOPLEFT` by `24px` in `Blizzard_CombatLog_AdjustCombatLogHeight` so `CombatLogQuickButtonFrame_Custom` at `+3px` sits inside `ns.chatBox`'s `8px` top inset). Turning `"Move the chat window"` off restores `ChatFrame1`'s Blizzard Edit Mode position and size via `ApplySystemAnchor` + `UpdateSystemSettingWidth` / `UpdateSystemSettingHeight`.
  - Never `SetParent`, `HookScript`, `SetScript`, or `UnregisterEvent` on `ChatFrameN`, and never call non-elevated `ScrollingMessageFrameMixin` internals (`RefreshIfNecessary`) from addon code. Use `hooksecurefunc` only (checking `rawget(ChatFrame1, method)` so we never shadow C metatable methods with new table keys).
- **Strata, Inner Chat Frame & Background Fill**:
  - `ChatFrameTemplate` (`ChatFrame.xml:3`) is `LOW` strata, while `DavesChatAnchor`, `DialogBorderTranslucentTemplate`, and `ns.chatBox` (`InsetFrameTemplate`) are `MEDIUM` strata.
  - Both `border.Bg` and `chatBox.Bg` stay hidden (`chatBox` and `chatBox.NineSlice` also have `EnableMouse(false)`) so `MEDIUM`-strata frames draw crisp borders around the window and inner chat pane without ever covering `LOW`-strata chat text or blocking hyperlinks / 3D camera clicks.
  - `ns.fill` is parented to `UIParent` at `BACKGROUND` strata, anchored to `ns.anchor`, and scaled to `ns.db.scale`, holding `ns.fillTex` (sublevel `0`, `7px` inset) and `ns.chatBoxFill` (sublevel `1`, `3px` inset inside `ns.chatBox`).
- **Flicker Elimination on New Messages**:
  - Previously, `GENERAL_CHAT_DOCK` stayed at `Alpha(1)` above `ChatFrame1`, and Blizzard's per-message `FCF_StartAlertFlash`, `FCF_FadeInChatFrame`, and `FloatingChatFrame_UpdateScroll` → `FCF_FadeInScrollbar` called `UIFrameFadeIn` on hidden `ChatFrameNTab`s, `ScrollToBottomButton`, and `ScrollBar` (fighting `0.60` vs `0.65` alpha for 1 frame), while `ChatAlertFrame:UpdateAnchors` deferred icon re-pinning via `C_Timer.After(0)`.
  - Now `GENERAL_CHAT_DOCK` stays at `Alpha(0)` whenever owned (`not restoring`), `ns:HookChatFlickerGuards()` clamps `ScrollBar`, `ScrollToBottomButton`, and `ChatFrameNTab` synchronously inside `hooksecurefunc` post-hooks before the frame renders, and `HookChatAlerts()` re-pins `QuickJoinToastButton` / `TextToSpeechButtonFrame` synchronously inside `hooksecurefunc(ChatAlertFrame, "UpdateAnchors", ...)`.
- **Independent `"Settings"` Launcher Dialog vs `EditModeDialog` Mutex**:
  - `EditModeDialog.lua:346, 661` closes all other `EditMode.CreateDialog` instances when one opens. Keeping `Window Settings` (`ns.editDialog`) on `ns.EditMode.CreateDialog` (where all sliders/checkboxes/button-grid live) while implementing `Settings` (`DavesChatSettingsMenu`) as a 3-button launcher dialog (`Chat Settings`, `Window Settings`, `AddOn Options`) lets the user open each settings window independently without force-closing `Settings`.
- **EditBox Scaling & Alignment (`FloatingChatFrame.xml:555-560`, `ChatFrameEditBox.lua:354`)**:
  - `$parentEditBox` anchors `TOPLEFT` to `chatFrame` `BOTTOMLEFT (-5, -2)` and `RIGHT` to `chatFrame.ScrollBar` `RIGHT (+8, 0)`, and reparents itself to `UIParent` on load. Anchoring `ScrollBar` `+6px` right of `chatFrame` inside `ns.chatBox`'s `22px` right gutter centers the `8px` `MinimalScrollBar` (`8px` from `ns.chatBox`'s right border) and aligns `editBox` (`y = 22..54`) flush left-to-right beneath `ns.chatBox`, clear of both bottom corner resize grips (`y = 6..22`).
- **Social / Alert Buttons (`AlertFrames.lua:423`, `QuickJoinToast.lua:154`, `TextToSpeech.lua:30`)**:
  - While owned, `TextToSpeechButtonFrame` and `QuickJoinToastButton` set `IsInDefaultPosition = NotDefaultPosition` (`return false`) so Battle.net friend-online toasts stay on `ChatAlertFrame`, `QuickJoinToastButton:SetToastDirection(true)` grows Quick Join banners left, and header space for `TextToSpeechButtonFrame` is reserved only when `ns.TtsWanted()` is true.

---

## 4. Hard Rules ("Do Not Do These")

- Do **not** edit `wowaddons/daves_chat/EditModeDialog.lua` directly; edit `wow-addon-kit/plugins/wow-forever-addons/templates/editmode/EditModeDialog.lua` and sync all Edit Mode addons if the shared dialog ever changes.
- Do **not** register `COMBAT_LOG_EVENT_UNFILTERED` or `COMBAT_LOG_EVENT` (removed on Forever).
- Do **not** build custom settings sliders, checkboxes, or grid-snapping math outside `ns.EditMode.CreateDialog` or `Settings.RegisterVerticalLayoutCategory` (`DavesChatSettingsMenu` is strictly a 3-button launcher menu).
- Do **not** leave a permanent `OnUpdate` on `DavesChatAnchor` (`ns.EditMode.Attach` owns `anchor`'s `OnUpdate` during drags); keep per-frame watching on the separate `UIParent` watcher frame.
- Always guard potentially secret strings (`ChatFrameNTab:GetText()`, `CHAT_MSG_CHANNEL_NOTICE` payload) with `not (issecretvalue and issecretvalue(v))` before any comparison or string operation.

---

## 5. Open Design Questions & Known Tradeoffs

1. **`/daveschat tabs` when "Keep public channels on General" is off**: `ns:ApplyTabLayout()` currently moves numbered channels from `ChatFrame1` to `ChatFrame4` whenever tabs are reset; `routeChannels` only gates subsequent channel joins.
2. **Social buttons while collapsed**: While chat is collapsed to the `"Chat"` button, `QuickJoinToastButton` and `ChatFrameChannelButton` stay hidden with `ns.settingsBar` so only the `"Chat"` button remains on screen (`QuickJoinToastMixin:OnHide` pauses Quick Join queue toasts while hidden).
3. **Combat lockdown & Blizzard UI panels**: `ns:OpenChatConfig()` and `ns:OpenOptions()` check `InCombatLockdown()` and print a clean notice in combat rather than calling `ToggleUIPanel(ChatConfigFrame)` / `Settings.OpenToCategory()` while `UIParentPanelManager` blocks non-secure panel opens (`Window Settings` works in and out of combat). Clicking reparented `QuickJoinToastButton` or `ChatFrameChannelButton` during combat may still be refused by `UIParentPanelManager` until combat ends; press `O` (keybinding runs secure) to open Social in combat.
4. **Edit Mode inner `ChatFrame1` box**: `Esc > Edit Mode` shows both `DavesChatAnchor`'s selection box and Blizzard's inner `ChatFrame1` selection box (dragging `ChatFrame1` is undone on exit by the `UpdateLayoutInfo` post-hook).

---

## 6. In-Game Verification Checklist

- `/reload` (no new files or `.toc` file-list changes in **0.3.0**, so `/reload` is sufficient if `0.2.0` was already loaded; full client restart if first time loading `daves_chat`) and verify login prints `Dave's Chat: v0.3.0 loaded. /daveschat opens settings.`
- **Left-Side Stacked Tabs & Inner Chat Frame**: Verify `Chat`, `Combat Log`, and `General` stack vertically on the left inside the main window, and chat text + scrollbar sit inside the bordered inner frame on the right with the edit box aligned directly below the inner chat frame. On `Combat Log`, verify the filter bar (`My actions` / `What happened to me?`) fits inside the top of the inner chat frame.
- **Top-Down Chat Growth**: Send or receive several chat lines and verify the newest message appears at the **top** of the inner chat frame and older messages push downward; verify mouse-wheel down and scrollbar thumb drag scroll down through older messages and up back to newest at the top.
- **Header & No Flicker on New Text**: Verify the header shows **Social** (`QuickJoinToastButton`), **Channels** (`ChatFrameChannelButton`), **Settings** on the right, and the standard WoW **`X`** close button in the top-right corner (with no speech-bubble icon and no eye button). Click **Social** to open Friends/Social. Have messages arrive on both the active tab and background tabs and verify zero header/button/scrollbar flicker (background tabs with unread alerts pulse softly in the left stack).
- **Independent Settings Launcher**: Click **Settings** (or run `/daveschat`) to open the **Settings** dialog. Click **Chat Settings**, **Window Settings**, and **AddOn Options** and verify each opens independently without closing **Settings**, and pressing `Escape` or its `X` closes **Settings**.
- **Standard Close `X` & Draggable `Chat` Button**: Click the top-right **`X`** button to collapse chat to the standard **`Chat`** button; verify all chat text, scrollbars, and unfocused IM edit boxes hide and 3D camera clicks/zoom work over the closed area. Drag **`Chat`**, then click **`Chat`** (or press `Enter`) to reopen.
- **Disable / Restore**: Uncheck `Move the chat window` in `AddOn Options` and verify Blizzard's chat frame border, bottom-up message growth, real tabs, and side buttons restore cleanly.
- Run `python wow-addon-kit/plugins/wow-forever-addons/scripts/Get-WowScriptErrors.py -Addon daves_chat` (and `Get-WowTaintLog.py -Addon daves_chat` if anything is blocked).
