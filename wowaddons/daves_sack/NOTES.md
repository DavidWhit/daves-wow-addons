# Dave's Sack: project notes

A running record of what we built, why, and how it works. WoW ignores this file, so it can live in the addon folder.

## What it is

A replacement for the default bags: one combined window styled like WoW's **HUD Edit Mode** window. Items are sorted into collapsible categories, with search, sort, quality-colored slots, scrolling, corner resizing and an Options window. It's written in Lua, uses no libraries, and is built to keep working across game versions (WoW: Forever, Retail, Classic).

## How to install / update

- Unzip so the folder is `World of Warcraft\_<version>_\Interface\AddOns\daves_sack\`, replacing the old folder.
- **If the update adds new image files (`.tga`), fully restart WoW.** `/reload` doesn't pick up new files.
- `/sack` opens the bags. `/sack options` opens Options. Everything else is in the Options window (⚙ Settings button).

## Files

| File | What's in it |
| --- | --- |
| `daves_sack.toc` | Addon manifest; lists every game version it loads on |
| `Core.lua` | Version-proof API layer, item categories and sub-categories, saved settings, `/sack` |
| `UI.lua` | The bag window: item buttons, layout, scrolling, resizing, events, takeover of Blizzard's bags |
| `Options.lua` | The Options window (built the first time it's opened) |
| `Media/*.tga` | Our own art: slot shapes, glow, gear, resize grip, slider knob |

## Version history

| Version | Changes |
| --- | --- |
| 1.0 | First build. "Forged" look (concept D, a mix of A + C): gold trim, diamond corners, categories, search, sort, quality borders. |
| 1.1 | **Professions** and **Reagents** became categories. Fixed the gold border vanishing at some screen positions (pixel snapping). Applied the first advisor review: stopped Blizzard's hidden bag frames from processing events, per-slot lock updates, batched cooldowns, no grid sliding under the cursor while selling. |
| 1.2 | Dropped the gilded look for the **HUD Edit Mode** look, using Blizzard's own border and close button. |
| 1.3 | Reagents split by profession. Primary professions win over secondary ones: linen goes under Tailoring, not First Aid; Alchemy fish go under Alchemy, not Cooking. Mythic Keystones moved to Miscellaneous. |
| 1.4 | Real gold/silver/copper coin icons, built from coin art every client has. Info icon redrawn as our own texture. |
| 1.5 | Fixed item tooltips not showing (the window had been sitting on the same layer as the item slots). Added a fallback tooltip. Added scrolling with mouse wheel and a draggable bar. |
| 1.6 | **Options window** (⚙ Settings button) replaces slash commands and the info icon. **Resize grips** in both bottom corners; width snaps to whole columns. **Consumables split by type** (Alchemy: potions/elixirs/flasks; Food & Drink; First Aid (bandages, anti-venoms); Scrolls; Enhancements; Other). Sub-category on/off switches. **Start collapsed** checkboxes per category. **Minimum height** of about 3 rows. **Blizzard's own scrollbar** (`ScrollFrameTemplate`), so it scrolls like the rest of the UI: one row per wheel notch, arrows, drag, click the track. Second advisor review applied (see below). |
| 1.6.1 | **Fixed a crash** ("C stack overflow") when scrolling with Blizzard's scrollbar. A v1.6 hook rounded the scroll position to whole pixels inside Blizzard's scroll callback. Blizzard's bar sets the position back on every callback, so the two corrected each other forever. The hook is removed. The bare gear became a **⚙ Settings button** (Blizzard panel button, icon and label centered) in the toolbar next to Sort; the window is now titled "Bag Settings". |
| 1.7 | **Backpack currencies** in the footer: everything ticked "Show on Backpack" in the Currency tab, with Blizzard's own tooltips. Shift-click links one into chat; the remove-from-backpack modifier works as in Blizzard's UI; a plain click opens the Currency tab. They **wrap onto extra rows** when they don't fit, and the footer grows a row each time. **Camping** category for WoW: Forever camping gear (campfire materials, camp objects, Blueprints, sleeping bags), active only on Forever. **Free Space kept** (needed for split stacks), on by default and switchable in Settings. **Drop anywhere** on the window to store the cursor item in the first free slot; shows "Inventory is full" when there's no room. Settings window reworked into two columns. Third advisor review applied. |
| 1.7.1 | Each Consumables group (**Alchemy, Food & Drink, Bandages (now First Aid), Scrolls, Enhancements**) gets its own on/off switch in Settings; a group switched off joins "Other Consumables". "Start folded" renamed **"Start collapsed"** ("fold" → "collapse" everywhere). |
| 1.7.2 | **Auto-place split stacks:** after you split a stack, the new stack goes straight into a free slot, so it appears right beside the original in the same category and sub-group, with no scrolling to Free Space. It pauses while a merchant, mailbox, trade, bank, guild bank, auction or void storage window is open, so you can still drop the stack there. On by default; switch in Settings → Extras. (Hooks `C_Container.SplitContainerItem`, the call both Retail and Forever use, plus the older global on Classic.) |
| 1.7.3 | Consumables' "Bandages" group became **First Aid**: bandages plus anti-venoms (by item ID and name, checked before the potion subclass so an anti-venom never lands in Alchemy). First Aid's cloth (linen, wool…) stays under Reagents → Tailoring. Its on/off switch carries over. |
| 1.7.4 | **Faster refresh when merging stacks.** Gaps are now only held while your cursor is over the bags *and* a merchant, mailbox, trade, bank, guild bank, auction or void storage window is open (the rapid right-click cases). Everywhere else (merging stacks, using items) the grid tidies up immediately. |
| 1.7.5 | **No more resizing when items arrive.** "Fit height to my items" now fits when you open the bags, when you change a setting, or when you collapse or expand a section. While the bags stay open the size is locked and new items scroll. Space for the scrollbar is always reserved, so the width never jumps. |
| 1.7.7 | **Fixed "This action is only available to the Blizzard UI"** when right-clicking items with a vendor open. Closing the bags called Blizzard's `CloseAllBags` from addon code, which tainted Blizzard's bag state; the merchant window picked that up when it opened, and `UseContainerItem` was then blocked (confirmed in `Logs/taint.log`). The addon no longer calls Blizzard's bag functions; `/sack` toggles the window directly. |
| 1.7.8 | **Reagent bag.** With a reagent bag equipped (bag 5 on the modern client, `Enum.BagIndex.ReagentBag`), reagents dropped on the window, and split reagent stacks, go into it first while it has room: setting **"Prefer the reagent bag"** (Settings → Extras, on by default, greyed out on clients without the slot). Fit is decided the way the game does it for any specialty bag: the item's family bits (`C_Item.GetItemFamily`) against the bag's (`C_Container.GetContainerNumFreeSlots`). **Free space shown in two parts:** the Free Space section has a tile for your bags and a green-edged tile for the reagent bag (each with its own count; the header reads "12 bag, 8 reagent"), and the footer shows two counters and bars, "used / total" and "used / total reagents". **Hard size limits:** a width or height that can't show the window properly is never allowed, however it's set (Settings sliders, corner grips, a saved value, a reagent bag or another digit of gold arriving). Minimum width = enough columns for both counters and the gold side by side (never fewer than 6); maximum = what fits on the screen; the item area is at least ~3 rows and at most what the screen leaves under the toolbar and footer. Saved sizes are corrected at load, the sliders' ranges follow the limits, and the window widens itself when the footer grows. **Background** slider (Settings → Look, 20–100%, default 80%): darkness of the window's background. 80% is Blizzard's translucent Edit Mode dialog, 100% as solid as Blizzard's opaque dialogs; the Settings window follows it. Fourth advisor review logged below. |
| 1.7.9 | **Background style** (Settings → Look, under the Background slider): which of Blizzard's standard backgrounds shows behind your items: Dark (the default, the translucent dialog's black), Light paper and Dark paper (the papers of `DialogBorderTemplate` / `DialogBorderDarkTemplate`), and Marble and Rock (`Interface\FrameGeneral\UI-Background-Marble` / `-Rock`, tiled). Tooltip and Parchment were offered first and dropped the same day. The Background slider's darkness still applies on top as the texture's alpha, so every style keeps the translucency, and the Settings window follows both. A styled Blizzard dropdown where the client has the menu system, a cycling button elsewhere. |
| 1.7.10 | **Bag open/close sounds back.** Blizzard's container frames play them from their own OnShow/OnHide. Since 1.7.7 our close button only hid our window, so Blizzard's frames stayed "open", and the next B press closed them (close sound) while ours opened; no sound ever came on close. Now: (1) the close button is a `SecureActionButtonTemplate` "click" on `MainMenuBarBackpackButton`, so Blizzard's own `ToggleAllBags` runs untainted and closes its frames (its close sound plays); if Blizzard's bags are already closed the click just hides us. (2) After any of Blizzard's bag calls our window *follows* Blizzard's open/closed state (`IsBagOpen`, read only) instead of toggling by itself, so the two can't drift apart, and Blizzard's "bags opened by the vendor close with it" rule is inherited rather than copied. (3) Our window plays the sound itself only when it moves on its own (`/sack`; Escape goes through Blizzard's `CloseAllWindows` → `CloseAllBags` first, so it is Blizzard's sound): Blizzard's frames' OnShow/OnHide are hooked to note when theirs just played. (4) Every `ContainerFrameN` is parked on the hidden parent at load, not after its first show, so a frame can't play open+close in the same instant. (5) The secure button is parented to `UIParent` and anchored to the window, never a child of it: a frame holding a protected button becomes protected itself, and the window could not be shown, hidden, moved or resized in combat. It mirrors the window's visibility and scale outside combat (`ns.SyncCloseButton`, caught up on `PLAYER_REGEN_ENABLED`). In combat its attributes are frozen, so its PostClick hides the window regardless and Blizzard's state catches up at the next key press. With an item on the cursor the X stores it the sack's way (reagent bag preference) instead of Blizzard's "into the backpack". Clients without `IsBagOpen` fall back to toggling along with Blizzard's calls. Fifth advisor review: 1-4 and 6 applied, 5 (hide-and-reshow when only the keyring was open and B is pressed) and 7 (a `/reload` during combat blocks the button's setup once) left for an in-game check. |

### Second advisor review (v1.6) — what was fixed

- Columns/Scale sliders "ran away": the Options window was attached to the bag window, which moves as it changes size. It's now detached after placing.
- Changing Scale no longer moves the bag window. The position is saved in screen units (`db.pos`).
- Retail's empty-slot art no longer overrides our icon crop.
- Search dimming now dims the quality edge and glow too. Retail item buttons override `SetAlpha`, so the plain frame version is used.
- Free Space no longer goes stale when you drop an item on it while hovering.
- Sort shows its results immediately, even while hovering.
- Items unlocked while the bags were closed no longer stay greyed out.
- Removed the tooltip wrapper on item buttons. Hovering and using items now run entirely through Blizzard's own handlers, so there's no taint. The real tooltip fix was the frame level.
- Resizing is clamped to the screen. A sideways-only drag keeps "fit height" on. A lost mouse-up (alt-tab) stops the drag.
- Cooldown-only updates no longer rebuild the footer or re-run search. Scale changes no longer re-sort.
- Search names refresh when an item's link changes ("of the Bear" variants). Retail quality markup is stripped from names.
- Removed duplicate open/close sounds.

## Design decisions (and why)

- **Use Blizzard's own templates for chrome** (dialog border, close button, search box, buttons) so each game version draws its native art. Retail gets the modern metal style, Classic the classic style. Every template call has a plain fallback.
- **Use our own textures for our icons** (gear, grip, slider knob, slot shapes). Blizzard art can move or disappear between versions; our files can't. The help-plate "i" icon failed in game for exactly that reason.
- **Feature detection, not version checks.** For example, `C_Container` vs. the old bag API, and `C_Item` vs. old item functions. That's what "works forever" means here.
- **Categories:**
  - Junk = grey quality.
  - Quest items are detected by the game's quest flag.
  - Profession tools are a short list of item IDs, plus fishing poles.
  - Reagents and Consumables use the game's item subclass. Very old item data with generic subclasses falls back to name keywords (potion, elixir, flask…) and the item's use-spell (Food/Drink).
- **Primary over secondary professions** for shared materials (user rule).
- **Start collapsed:** categories ticked in Settings start collapsed every time the bags open. Unticked ones open expanded. You can still collapse or expand during a session. (Saved internally as `startFolded`.)
- **WoW: Forever facts (checked in Blizzard's own Forever UI source, branch `forever`, build 1.60.1, internal game type "camelot"):**
  - It runs on the modern client.
  - Currencies use `C_CurrencyInfo.GetBackpackCurrencyInfo`, with a "Show on Backpack" checkbox in the Currency tab, the same as Retail.
  - Camping items have **no item type of their own**. The Camping category therefore matches by item ID (Simple Wood, Flint and Tinder) and by English name (camp objects, "Blueprint", "Sleeping Bag", etc.). "Campaign" items are deliberately excluded.
- **Free Space stays** (user decision): every item has a category, so the tile never holds items. It's the empty slot you drop onto, for example the second half of a split stack.
- **Options over slash commands** (user request). `/sack` and `/sack options` remain as shortcuts.
- **Height model:**
  - "Fit height to my items" (default): the window fits your items (up to 80% of the screen) when the bags open, when you change a setting, or when you collapse or expand a section. While open it keeps that size, so looting never resizes it; extra items scroll.
  - Dragging a corner vertically, or turning that option off, fixes the height.
  - The item area is never shorter than about 3 rows.
- **Width snaps to whole columns** while resizing.
- **Hard size limits** (user rule, v1.7.8): sizes that don't make sense aren't allowed anywhere. `ns.MinColumns` / `ns.MaxColumns` / `ns.MaxViewHeight` are the single source: the corner grips, the Settings sliders (whose ranges are re-read on every refresh), `Layout`, `Restore Defaults` and the saved values at load all go through `ns.ClampColumns` / `ns.ClampViewHeight`.
- **Background** (v1.7.8): one setting drives the alpha of Blizzard's dialog border background on both windows. 80% is the translucent template Blizzard's Edit Mode uses; 100% matches its opaque dialogs.
- The window is anchored by its **bottom-right corner**, like the default bags, so it grows up and to the left.

### Third advisor review (v1.7) — what was fixed

- Camping matching runs only on WoW: Forever (detected via `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`). It now catches "Camping …" and "Camps …" and never claims quest items.
- Drop-anywhere checks bags live, skipping specialty and full bags, and reports a full inventory.
- Currency icons accept a dropped item. Clicking opens the Currency tab the way Blizzard does (`CharacterFrame:ToggleTokenFrame`).
- The currency refresh stops at the first gap and reuses its tables. It re-fits when the window width changes.
- The "Backpack currencies" setting is greyed out on clients without currencies (Classic Era).

### Fourth advisor review (v1.7.8) — findings as marked, and what happened to each

The reviewer (wow-addon-reviewer, advisor mode) checked the reagent bag change on forever, retail and classic_era. Validator before: 0 errors, 4 warnings; after: 0 errors, 0 warnings.

| # | Mark | Finding | Status |
| --- | --- | --- | --- |
| 1 | error, **unverified** | The vendor right-click block ("only available to the Blizzard UI") may not be fixed by 1.7.7. The only taint log on disk predates the 1.7.7 commit; its stack shows taint entering through `slotIndex`, which comes from the addon calling `SetID` on its own item buttons (`UI.lua` `NewButton`/`ScanBag`). Blizzard's docs mark `SetID`/`GetID` with the same secret-aspect pair as `SetAttribute`/`GetAttribute`, so an addon-set ID may taint Blizzard's secure click handler before it calls `UseContainerItem`. Proposed fix if confirmed: give the addon's buttons their own click handlers that call `UseContainerItem`/`PickupContainerItem` with plain numbers (small route), or borrow Blizzard's securely initialised item buttons (redesign). | **Waiting on an in-game check:** `/console taintLog 1`, right-click a grey item at a vendor, `/reload`, run `Get-WowTaintLog.ps1 -Addon daves_sack`. If the `slotIndex` line is back, apply; if the log stays clean, 1.7.7 did fix it. |
| 2 | warn | On a narrow window the reagent counter text could run into the gold (the bar budget didn't measure the strings). | **Addressed, differently:** hard size limits. The minimum column count is measured from both counter strings and the gold, so the window can't be made narrow enough to overlap. Bars are back to a fixed width. |
| 3 | suspect | The family-bit fit test depends on two values only the client can give: the reagent bag's `bagFamily` and a reagent's `C_Item.GetItemFamily`. If the bag reports 0 the reagent bag is silently never used (`FitsBagFamily` refuses family 0 for the reagent bag on purpose). | **Waiting on an in-game check:** `/dump C_Container.GetContainerNumFreeSlots(5)` and `/dump C_Item.GetItemFamily(<herb or ore id>)`; the band of the two must be non-zero. Fallback if it isn't: treat bag 5 as taking `isCraftingReagent` items (a guess at the server rule; say so here). |
| 4 | suspect | A spare reagent bag on the cursor might pass the fit test (a container's item family describes what it holds), get refused by the server and stay on the cursor without the normal bags being tried. | **Waiting on the same session:** `/dump C_Item.GetItemFamily(<reagent bag item id>)`. If non-zero, skip container items (`classID == 1`, `Enum.ItemClass.Container`) before the bit test. |
| 5 | suspect | `reagentBag[bag]` ("equipped?") is cached in `SyncBagList` (container events only). If `BAG_UPDATE` for bag 5 lands first when a reagent bag is equipped or removed with the window open, one layout runs with the stale flag until the container event arrives. | **Not applied yet** (user's call). Fix: test `n > 0 and ns.IsReagentBag(bag)` live in `Layout`. |
| 6 | suspect | `ITEM_LOCK_CHANGED` paints a slot directly; on an empty Free Space tile that could hide the count and (new) revert the reagent tile's green edge until the next update. Rare. | **Not applied, wait for a sighting.** Fix: after that `Paint`, re-run `ShowFreeCount()` for the two tiles. |
| 7 | warn | Four unused locals (`ADDON` twice, `upper`, `HEAD`). | **Applied.** |

Checked and fine by the reviewer: `bit.band` (used by Blizzard's own UI on this client; guarded anyway), `Enum.BagIndex`/`NUM_REAGENTBAG_SLOTS` guarded so classic_era never reaches the bag-5 path, footer widgets exist before any footer update, the two Free Space tiles keep their order and edge colour, Options height is derived so the extra rows fit, and `GetCursorInfo`/`PickupContainerItem`/`GetContainerNumFreeSlots` with plain numbers add no taint risk.

## Testing

`run_all.py` (kept outside the addon) runs 42 checks against a simulated WoW API in three setups:
1. WoW: Forever with Blizzard's scrollbar.
2. A Retail-like client.
3. A Classic-like client with no currency API and the fallback scrollbar.

It covers categories and sub-groups, camping, item-slot layering (tooltips), currencies (including wrapping), drop-anywhere, split stacks, merge refresh vs. vendor gap-holding, size locked while open, the scrollbar crash replay, Settings, start-collapsed, defaults and minimum height. A parser-based scan also confirms no accidental global variables.

## Lessons learned

- **Never call Blizzard's bag functions (`CloseAllBags`, `ToggleAllBags`) from addon code.** They run tainted and taint Blizzard's bag state, which spreads to the merchant window and blocks item use there (v1.7.7).
- **Never change the scroll position inside a scroll callback** when using Blizzard's scroll frame. Its bar and frame update each other, and only stop when nothing changes (v1.6 crash).
- **Blizzard's item button template pins frame level 10.** Anything we create must sit above it explicitly, or the window steals the mouse (v1.5 tooltip bug).
- **Don't depend on Blizzard art or add-ons for our own icons.** The help-plate "i" didn't render on the user's client (v1.3).
- **Money helpers move between versions** (`GetCoinTextureString` became `C_CurrencyInfo.GetCoinTextureString`). Build from texture escapes instead (v1.4).
- **Test against faithful replays of Blizzard's code paths,** not only simple fakes. The scroll crash only shows up when the frame↔bar callback cycle is reproduced.

## Performance notes

- Item buttons are created once and reused.
- Bag events only mark bags "dirty". Work happens at most once per frame, and never while the window is closed.
- A lock change repaints one slot. Cooldowns are batched. Buttons are only repainted or moved when something visibly changed.
- Blizzard's own (hidden) bag frames have their events switched off while they hold your bags, and restored for bank bags.
- While the mouse is over the window **and** a merchant, mailbox, trade, bank or auction window is open, emptied slots stay as gaps instead of the grid sliding, so the next item never slides under a right-click. It tidies up when the mouse leaves. Otherwise (e.g. merging stacks) it refreshes immediately.
- The Options window isn't built until first opened.

## Known limits / things to verify in game

- Everything is tested in a simulated version of the WoW API, not the real client. Check in game after each update.
- Consumable fallback words (potion, elixir, flask…) and the Food/Drink spell names only match English clients. Modern item data uses subclasses, which work in any language.
- Combat: using items from the bags in combat should be checked with `/console taintLog 1` (advisor flag).
- WoW: Forever was in beta at the time of writing (launch November 2026); its interface number may change at launch. If the AddOns list says "out of date", add the new number to the first line of the `.toc`.

## Design canvas

Concepts A–E (and the Forged vs. Edit Mode comparison) live in the "WoW Bags Concepts" canvas artifact.
