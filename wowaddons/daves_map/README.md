# Dave's Map (daves_map)

QuestieDB's **WoW: Forever** tracked quest objectives, ready turn-ins, optional POI layers, and tab-driven **Zone** & **Dungeon** markers drawn on a taint-free world map layer, paired with a left-rail **`Base` / `Tracker` / `Zone` / `Dungeon`** sidebar, Ready-to-Turn-In & zone quest tracker, and OpenMap `v0.8.10`'s seamless stitched world map and multi-floor dungeon/raid maps.

Targets: WoW: Forever (`## Interface: 16001`). Uses two tracked companion addons in `wowaddons/` (also packaged separately on `releases`):
- **`daves_map_data`**: QuestieDB Forever pins, objectives, turn-ins, clean sequential quest chains (`D.pre` & `D.nxt`), quest item rewards (`D.rew` & `D.iname`), structured rare monster drops with drop percentages (`D.drops`), zone level brackets, and per-zone dungeon & dungeon-quest lists (`D.dungeons`) (`tools\Update-MapData.py`)
- **`daves_map_textures`**: OpenMap `v0.8.10` seamless world & dungeon map art and tables (`tools\Update-MapTextures.py`)

## Use

- **Clean Default Map (Only Tracked Quest Objectives, Windowed & Opaque)**:
  - Keeps Blizzard's World Map windowed (drops full-screen maximize via `miniWorldMap = 1` & hiding `MaximizeMinimizeFrame`) and fully opaque when moving (`mapFade = 0`).
  - Out of the box, the World Map draws **only** the objective spawns (`...`) of quests you are actively tracking and the turn-in markers (`?`) of quests ready to turn in — keeping the map calm and uncluttered.
  - Optional non-quest POI categories (`Flight Master`, `Instance`, `Graveyard`, `Townsfolk & Services`, `Rare`, `Treasure & Lore`) default **on** and can be toggled all at once (or per group/category) via the right-aligned checkboxes at the top of **`Base`**, fading in and out smoothly with zoom distance so zoomed-out continent/world views never overload with icons. Hovering any **Rare** monster icon displays a rich **`Potential Known Drops:`** section with item icons, quality colours, slot/Lvl, and drop percentages.
  - A top-center **Zone & Coordinates Banner** shows the zone's difficulty-coloured level bracket and cursor/player `(x, y)` coordinates.
- **Left-Side Tab Rail + Right-Side Visual Content (`Dave's Map` Sidebar, `Panel.lua`)**:
  - **Movable, Resizable & Dockable (Always Opens/Closes with the Map)**: Starts docked flush beside Blizzard's World Map (`588px` default & enforced minimum width with a slim `46px` skill-icon left tab rail), or drag its title bar / frame anywhere on screen and drag the bottom-right resize grip to widen or resize it freely (persisted across sessions while still automatically opening and closing with `WorldMapFrame`). Double-click the title bar, click **`Dock to Map (Reset Size)`** inside **Window Style**, or run `/dmap dock` (`/dmap reset`) to snap back beside the World Map at default width.
  - **HUD Edit Mode Styling & Proper Right-Side Scrollbar (Same Look & Controls as `Dave's Sack`)**: Uses Blizzard's translucent dialog frame (`DialogBorderTranslucentTemplate`), tight left alignment on quest rows, Blizzard's native right-side **`MinimalScrollBar`** (wheel, arrows, draggable thumb, track click, auto-hiding when unscrollable), square beveled brass skill-icon tab buttons (`Media/slot.tga`, `tab_base.tga`, `tab_tracker.tga`, `tab_zone.tga`, `tab_dungeon.tga`, `back.tga`), 3-sliced beveled brass pill buttons (`Media/pill.tga`, `plus.tga`, `minus.tga`), and matching gold toolbar icon buttons (`findme.tga`, `waypoint.tga`, `gear.tga`) including **Window Style** (`/dmap style`) with draggable sliders (**Window scale** `50%`–`150%`, **Pin size** `50%`–`200%`, **Background** opacity `20%`–`100%`) and Blizzard's **Background style** dropdown (`Dark`, `Light paper`, `Dark paper`, `Marble`, `Rock`), live-synced with **`Esc > Options > AddOns`**.
  - **`Base` Tab**: Toggles optional POI icon layers (`Locations & Travel`, `Townsfolk & Services`, `World & Rare Spawns` — all on by default, with right-side checkboxes on the top header and each group header to toggle all on/off) and embeds **Map Settings** directly in one place (`Alliance`/`Horde`/`Neutral` factions, `"Track only my zone's quests"`, `"Click a tracked quest to focus it"`, `"Hide completed quests"`, `"Show the map layer"`, `"Show zone & coordinates banner"`, and `Seamless & Dungeon Maps` options).
  - **`Tracker` Tab (Focused, Ready to Turn In, Pinned & Tracking on the Base Map Layer)**:
    - Stays on the clean **Base** map layer (tracked/focused objectives + checked optional POI layers, without `Zone`/`Dungeon` quest clutter) and pulls live quest data from `daves_map_data` into collapsible **`Focused`**, **`Ready to Turn In`**, **`Pinned`**, and **`Tracking`** sections using the same sortable 4-column grid (`Quest` | `Starter` | `Lvl` | `XP`), inline chain steps, clickable Starter links, and item rewards (or a clean `No map data` notice if QuestieDB Forever doesn't have pin data for a quest yet).
    - Clicking a quest in Blizzard's Objective Tracker or **Ready to Turn In** focuses its pins on the **Base** map layer, flies straight to its active objective/turn-in, opens Quest Details beside the map, and opens the **`Tracker`** tab with that quest under **`Focused`**.
  - **`Zone` Tab (Zone Quests & Inline Quest Chains)**:
    - Always shows quests for the zone you're in or the zone you move the map to (switching back to **`Base`** returns the map to tracked objectives + checked optional POI layers).
    - **Sidebar Reference Precedence**: Clicking any quest, chain step, Starter link, or item reward inside **`Zone`** or **`Dungeon`** pins your current `Zone`/`Dungeon` list and markers (and suspends background host-map switching before the map moves) so flying to an out-of-zone pickup, objective, or turn-in never swaps what's viewable, flickers, or shifts rows. Navigating from Blizzard's real Quest Log / Objective Tracker, directly navigating on the World Map (clicking a zone/continent, right-clicking out to a parent map, dragging to another zone, or clicking **Find Me**), or clicking the active **`Zone`**/**`Dungeon`** tab again releases the lock and switches naturally.
    - Multi-step quest chains stay grouped **under the quest that started the chain**, rendered in a structured 4-column sortable grid (**`Quest` | `Starter` | `Lvl` | `XP`**) with clickable column headers to sort by **Level**, **XP**, **Starter**, or **Quest Name** (remembered across reloads). Each chained quest has a dedicated **`+`/`-` pill button** right beside the quest icon to easily expand or collapse its indented numbered bullet steps (`1.`, `2.`, `3.`, ...) right underneath, and each quest/step displays its own clickable **Starter** link column to fly straight to the pickup NPC/location.
    - Clicking a chained quest (or its `+`/`-` pill button) in `Dave's Map` expands or collapses its numbered bullet steps right underneath the starter quest (and chains you are currently on expand automatically): **completed steps are greyed out**, **uncompleted steps are green**, and **the focused step is highlighted**.
    - Clicking any quest mark on the World Map (available `!`, repeatable `!`, turn-in `?`, objective, completed checkmark, or Blizzard map quest pin) automatically opens the matching **`Zone`** (or **`Dungeon`**) tab, unfolds its section & chain if needed, highlights it, and scrolls straight to that quest.
    - **All item rewards across a chain** display right at the bottom of the chain when collapsed (tagged with step number), and move directly under the specific quest step that grants them when expanded (hover for full Blizzard item stats & gear comparison tooltip, Shift-click to link in chat).
  - **`Dungeon` Tab (Zone Dungeons, Floor Maps & Quest Starters)**:
    - Always shows the dungeon(s)/raid(s) in your current zone or the zone you move the map to (with total remaining XP, a 1-click **`<Dungeon> Map`** multi-floor map & boss-pin opener, and dungeon quest starters on the map), keeping chains collapsed by default with rewards shown below each quest or chain.
    - Clicking any item inside **`Dungeon`** pins that dungeon zone in context via the same sidebar precedence rule so flying to an out-of-zone pickup NPC never swaps away what's viewable, and releases automatically on direct World Map or real Quest Log navigation.
  - **Quest Text Beside the Map (Click Sound Only)**: Clicking any quest or chain step inside `Dave's Map` plays only WoW's crisp UI click sound (`IG_MAINMENU_OPTION_CHECKBOX_ON`, never the paper page-flip sound) and opens Blizzard's **Quest Details** text pane right beside the World Map whenever the quest (or active step of its chain) is in this character's Quest Book.
  - **`< Back` Button & Search**: Bottom-left **`< Back`** button (and **Mouse Button 4** anywhere on `Dave's Map`) restores your previous tab, reference layer, dungeon floor map, camera view, and scroll position; the top search box searches titles, descriptions, zones, and reward item names.
- **Objective Tracker & Ready to Turn In (`Tracker.lua`)**:
  - Quests whose objectives are done move into a collapsible **Ready to Turn In** section below Blizzard's tracker. With **"Track only my zone's quests"** on, Blizzard's tracker follows quests for your current zone while a clickable **Pin** beside each tracked quest keeps pinned quests tracked across zones.
  - Clicking a quest in the Objective Tracker or **Ready to Turn In** focuses its objectives/turn-in on the **Base** map layer, flies straight to its pin, opens its Quest Text beside the map, and switches to the **`Tracker`** tab under **`Focused`** (with a **`Show All`** button to unfocus back to all tracked quests).
- **The seamless map & dungeon maps** (`Stitch\` + `daves_map_textures`): every zone stitched into one continuous map with smooth cursor wheel zoom, progressive left-click zoom-in on empty map space all the way down to street level (and matching step-by-step right-click zoom-out), drag panning, middle-click / **Find Me** glide, Ctrl-click / **Drop Waypoint** (left-click or right-click a placed map pin to remove it without zooming out), and multi-floor dungeon & raid maps with boss pins.
- `/dmap` (or `/davesmap`) toggles the layer. Also `/dmap dock` (`/dmap reset`), `/dmap style` (`/dmap look`), `/dmap options`, `/dmap check [questID]`, `/dmap calib`, `/dmap zone`, `/dmap seamless`, and `/dmap version`. (`Dave's Map` opens and closes automatically with the World Map.)

## Companion Addons

### Quest & POI data: `daves_map_data` (QuestieDB Forever)

`wowaddons\daves_map_data\` (`Data.lua` + `NOTICE-QuestieDB.md`) is compiled by `tools\Update-MapData.py` from [Questie/QuestieDB](https://github.com/Questie/QuestieDB)'s WoW: Forever dataset (`data/Forever/`, `src/corrections/Forever/`, and `support/Forever/`). Everything fetched is parsed strictly as data in Python — nothing downloaded is ever executed.

```powershell
py -3 wowaddons\daves_map\tools\Update-MapData.py
```

### Seamless world & dungeon art: `daves_map_textures` (OpenMap)

`wowaddons\daves_map_textures\` (`Data\*.lua` + `Media\Textures\` + `LICENSE-OpenMap.txt` + `NOTICE-OpenMap.md`) is built by `tools\Update-MapTextures.py` from a local [OpenMap](https://github.com/openmap-world/openmap) WoW: Forever release (`v0.8.10`).

```powershell
py -3 wowaddons\daves_map\tools\Update-MapTextures.py [-Source <OpenMap folder or zip>]
```

## Develop

| Task | Command |
| --- | --- |
| Refresh QuestieDB Forever data | `py -3 wowaddons\daves_map\tools\Update-MapData.py` (`-Ref <sha>`, `-LocalDir <dir>`, `-KeepRaw`) |
| Update OpenMap tables & textures | `py -3 wowaddons\daves_map\tools\Update-MapTextures.py [-Source <OpenMap folder or zip>]` |
| Repaint pin/ring & gold toolbar icons | `py -3 wowaddons\daves_map\tools\Make-Media.py` |
| Check the addon & companions | `py -3 wow-addon-kit\plugins\wow-forever-addons\scripts\Test-WowAddon.py -Path wowaddons\daves_map -Flavor forever` |
| Prepare review packet | `py -3 wow-addon-kit\plugins\wow-forever-addons\scripts\Prepare-WowReview.py -Path wowaddons\daves_map` |
| Link into the game | `py -3 wow-addon-kit\plugins\wow-forever-addons\scripts\Link-WowAddons.py` |
| Reload after editing Lua | `/reload` in game (new files, TOC edits, or `.tga`/`.blp` changes need a full client restart) |

| File | Purpose |
| --- | --- |
| `Core.lua` | Startup, saved settings (`daves_mapDB`, `daves_mapCharDB`), `layerOn` schema migration, map audio helper (`ns.Sound`), quest-log/super-tracking wrappers, slash command |
| `Calibrate.lua` | Direct `C_Map.GetMapRectOnMap` zone/continent coordinate resolver, OpenMap stitched world UV bridge (`ns.WorldUV`), progressive zoom-tier LOD calculator (`ns.ComputeLodFades`), active zone lookup (`ns.ViewZoneMap`), and user waypoints |
| `Quests.lua` | Pure quest domain model: per-character completion indexing, `O(1)` Quest Book lookup (`ns.LogQuestIDForPin`), sequential quest-chain graph (`ns.ChainFor`, `ns.ChainProgress`, `ns.ResolveActiveChainPin`), live/estimated quest XP, item rewards, chain worthiness (`ns.ChainWorth`), and dungeon quest helpers |
| `Focus.lua` | Single owner of tracked quest objective/turn-in map pins (`ns.UpdateFocus`, `ns.TrackedContains`), explicit `Zone` / `Dungeon` reference marker layers (`ns.SetRefLayer`, `ns.RefreshRefLayerSet`), single-pin highlight (`ns.SetFocusedPin`), side-by-side Quest Text sync (`ns.SyncQuestDetailsPane`), and map camera flight |
| `Layer.lua` | Taint-free world map canvas overlay: tracked objectives, optional POI layers, `Zone`/`Dungeon` reference markers, zoom-distance LOD unloading & smooth fades, category icon styles, and hover/click hit-testing |
| `Tooltip.lua` | Rich map pin tooltips (`ns.ShowTooltip`), top-center Zone Level & Coordinates Banner, clickable Reference Layer HUD pill (`ns.UpdateMapBanner`), and unmapped-quest HUD veil (`ns.ShowUnmappedQuestFallback`) |
| `PanelNav.lua` | Sidebar shared state (`ns.PanelUI`), left-rail tab selection (`ns.SelectSidebarTab`), inline chain expansion state, Objective Tracker reveal (`ns.RevealQuestInPanel`), `< Back` history (`ns.GoBack`), Dungeon View sync, and full-text search |
| `PanelData.lua` | Pure view-model & variable-height item builders for `Base` (optional POI toggles + Map Settings), `Tracker` (`Focused`, `Ready to Turn In`, `Pinned`, `Tracking` quests from loaded data), `Zone` (chains under starter quest + bottom rewards), `Dungeon` (dungeon quest starters + bottom rewards), and `Search` (origin-frozen stable sort) |
| `PanelRows.lua` | Clipped variable-height virtualized row pool (`ns.RenderPanelRows`) with full property reset on reuse, greyed completed vs green uncompleted chain steps, item-only hover tooltips on reward rows, and row click dispatch |
| `Panel.lua` | Movable & resizable horizontal-split sidebar frame (`min width 628px`, `[ Left Tab Rail | Right Visual Content ]`), 3-sliced brass pill buttons, Search/Focus bar, `Zone` progress bar, and map docking |
| `Tracker.lua` | Ready to Turn In section, "Track only my zone's quests" with tracker pins (no custom tracker tooltips), and quest-focus clicks |
| `Options.lua` | `DavesMapStyleOptions` Window Style dialog (including `Dock to Map (Reset Size)`), synced `Esc > Options > AddOns` Settings category, and `/dmap options` opener |
| `Stitch/Base.lua` | Isolated `dm.OM` handoff from `DAVES_MAP_TEXTURES`, settings, and startup for OpenMap's stitched map |
| `Stitch/Stitch.lua`, `WorldMap.lua`, `Close.lua`, `Dungeons.lua`, `Combat.lua`, `Open.lua` | OpenMap's stitched world art, zoom/flight/FindMe controller, close-up minimap/caves, dungeon & raid maps, combat passthrough guard, and player-zoomed start |
