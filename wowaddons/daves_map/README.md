# Dave's Map (daves_map)

QuestieDB's **WoW: Forever** quests, objectives, turn-ins, quest chains, dungeons, flight masters, townsfolk, rares, and treasures drawn on a taint-free world map layer, paired with a search/filter sidebar, Ready-to-Turn-In & zone quest tracker, and OpenMap `v0.8.10`'s seamless stitched world map and multi-floor dungeon/raid maps.

Targets: WoW: Forever (`## Interface: 16001`). Uses two tracked companion addons in `wowaddons/` (also packaged separately on `releases`):
- **`daves_map_data`**: QuestieDB Forever pins, objectives, turn-ins, and quest chains (`tools\Update-MapData.py`)
- **`daves_map_textures`**: OpenMap `v0.8.10` seamless world & dungeon map art and tables (`tools\Update-MapTextures.py`)

## Use

- Open the world map. The pins are on by default, placed directly from QuestieDB Forever's exact `(uiMapID, x, y)` zone coordinates (zero projection drift).
- **The seamless map & dungeon maps** (OpenMap's code in `Stitch\`, art & tables in companion `daves_map_textures`): every zone stitched into one map, plus multi-floor maps and boss pins for Classic and WoW Forever dungeons and raids. The wheel zooms at the cursor from the whole world down to street level, out of one zone into the next; drag pans across the whole world; left-click zooms into the place under the cursor, right-click out a level; Ctrl-click (or the map's top-right Map Pin button) drops a waypoint anywhere on the stitched world. Clicking a dungeon or raid entrance portal (or opening the map inside a dungeon) opens its multi-floor dungeon map with boss pins and a side panel for floors, bosses, quests and loot (right-click, `Esc` or `Back` returns to the world map). Once the view settles, the zone you're looking at loads underneath (its quest areas, coordinates and name; out of combat). The pins sit where they are on it, the neighbouring zones' too, and clicking a chain step, a search result or a quest glides the view there instead of switching maps (also in combat). Options: "Seamless world map" (takes a `/reload`), "Dungeon maps", "Load the zone in view", and "Open zoomed in on me". If OpenMap itself is enabled, daves_map's copy stays off. `/dmap seamless` shows what it's doing.
- **The panel** is dressed like the map: the same metal frame and background, with the quest log's list headers, tick boxes and parchment. It docks beside the windowed map, on the left if there's room, otherwise on the right. When the map is maximized it sits inside it. It opens with the map the way you left it: its X, the map icon, `/dmap panel` and the option all remember the choice. The map icon at the map's bottom left toggles it.
- **Quest focus** ("Click a tracked quest to focus it", on by default): clicking a quest in the tracker, a map `...` POI, the quest log list, or Ready to Turn In focuses it — opening its details, centring/flying the map to it, and filtering Dave's Map down to that quest's pickup, exact objective spawns, and turn-in NPC until cleared.
- **Ready to Turn In** (always on): quests whose objectives are done leave the quest tracker and are listed in a collapsible section of their own just under it, with where each is turned in. Click one to focus and show it on the map, or Shift-click for a waypoint to its turn-in. With nothing else tracked, the section takes the tracker's place with an "All Objectives" header of its own.
- **Track only my zone's quests** (on by default, a tick in the panel): the quest tracker follows the quests in your log for the zone you're in, and the rest are untracked (still in your log). It changes as you enter a new zone, and on a flight it waits until you land. **Pins:** while it's on, a small pin sits to the left of each quest in the tracker; click it to keep that quest tracked whatever zone you're in. `/dmap zone` shows what it sees.
- **Search** matches titles, NPCs, descriptions, categories and zones. While you search, the map shows only the matches, with the ones on this map first. Click a result to select it and fly to its map, or Shift/Ctrl-click to set a waypoint.
- **Filters:** factions (yours and Neutral to start with), hide completed quests (dimmed otherwise), other classes' quests, quests more than 5 levels above yours, quests more than 1 to 5 levels below it (set how many in `/dmap options`), and every group and category with its count on this map (`Quest Turn-In`, `Quest Objective`, and `Merchant` start hidden for a clean map and can be ticked on anytime).
- **Hover a pin** to draw its links:
  - Orange lines lead to the quest's mob, item, object, or scout objective spawns.
  - Gold lines lead to where the quest is turned in.
  - Blue lines lead to the quests it requires.
  - Green lines lead to the quests it leads on to.
- **Click a quest** to select its chain, numbered in order around the colour wheel with step-to-step lines, objective links, and turn-in lines; click again (or "Clear" in the panel) to clear it.
- `/dmap` (or `/davesmap`) toggles the layer. Also `/dmap panel`, `/dmap options`, `/dmap calib` (pin and Forever map counts), `/dmap zone`, `/dmap seamless`, and `/dmap version`.

## Companion Addons

### Quest & POI data: `daves_map_data` (QuestieDB Forever)

`wowaddons\daves_map_data\` (`Data.lua` + `NOTICE-QuestieDB.md`) is compiled by `tools\Update-MapData.py` from [Questie/QuestieDB](https://github.com/Questie/QuestieDB)'s WoW: Forever dataset (`data/Forever/`, `src/corrections/Forever/` including `foreverBase*`, `forever*Traces`, and `forever*Fixes`, plus `support/Forever/`). Everything fetched is parsed strictly as data in Python — nothing downloaded is ever executed.

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
| Repaint pin/ring textures | `py -3 wowaddons\daves_map\tools\Make-Media.py` |
| Check the addon & companions | `py -3 wow-addon-kit\plugins\wow-forever-addons\scripts\Test-WowAddon.py -Path wowaddons\daves_map -Flavor forever` |
| Prepare review packet | `py -3 wow-addon-kit\plugins\wow-forever-addons\scripts\Prepare-WowReview.py -Path wowaddons\daves_map` |
| Link into the game | `py -3 wow-addon-kit\plugins\wow-forever-addons\scripts\Link-WowAddons.py` |
| Reload after editing Lua | `/reload` in game (new files, TOC edits, or `.tga`/`.blp` changes need a full client restart) |

| File | Purpose |
| --- | --- |
| `Core.lua` | Startup, saved settings (`daves_mapDB`, `daves_mapCharDB`), `DAVES_MAP_DATA` handoff, quest-log/super-tracking helpers, slash command |
| `Calibrate.lua` | Direct `C_Map.GetMapRectOnMap` zone/continent coordinate resolver (`ns.PinsOnMap`, `ns.ProjectPin`) |
| `Layer.lua` | Map pins, objective/turn-in/chain lines, hover, click, quest focus filtering, and tooltips |
| `Panel.lua` | Search, factions, quest filters, categories, and chain/search results sidebar |
| `Tracker.lua` | Ready to Turn In section, "Track only my zone's quests" with tracker pins, and quest-focus clicks |
| `Options.lua` | Settings page: layer on/off, panel, pin size, quest focus, seamless map & dungeon maps |
| `Stitch/Base.lua` | Isolated `dm.OM` handoff from `DAVES_MAP_TEXTURES`, settings, and startup for OpenMap's stitched map |
| `Stitch/Stitch.lua`, `WorldMap.lua`, `Close.lua`, `Dungeons.lua`, `Combat.lua`, `Open.lua` | OpenMap's stitched world art, zoom/flight controller, close-up minimap/caves, dungeon & raid maps, combat passthrough guard, and player-zoomed start |
