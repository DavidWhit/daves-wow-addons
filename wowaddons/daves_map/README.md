# Dave's Map (daves_map)

Map Genie's WoW Forever map, the points of interest, travel, quests and treasure, drawn as a layer of its own on Blizzard's world map. A search and filter panel sits beside it, modelled on Map Genie's sidebar, and quests are linked into chains.

Targets: Forever (`## Interface: 16001`).

## Use

- Open the world map. The pins are on by default.
- **The panel** is dressed like the map: the same metal frame and background, with the quest log's list headers, tick boxes and parchment. It docks beside the windowed map, on the left if there's room, otherwise on the right. When the map is maximized it sits inside it. The map icon at the map's bottom left toggles it.
- **Search** matches titles, NPCs, descriptions, categories and zones. While you search, the map shows only the matches, and the list shows them with the ones on this map first. Click a result to select it, or shift-click to set a waypoint.
- **Filters:** factions (yours and Neutral to start with), hide completed quests (dimmed otherwise), other classes' quests, quests above your level, and every group and category with its count on this map. Click a group's header to show or hide all of it.
- **Hover a pin** to draw its links. They reach into other zones too: a pin off this map is held at the map's edge in the direction it lies.
  - Gold lines lead to where a quest is turned in.
  - Blue lines lead to the quests it requires.
  - Green lines lead to the quests it leads on to.
  - Cyan lines show transport routes.
- **Click a quest** to select its chain, and click again (or "Clear" in the panel) to clear it.
  - The chain runs from its prerequisites back to the first quest, and through its follow-ups on to the last.
  - Each step is numbered in order on the map; the selected quest's number is gold.
  - Green lines join the steps, and thin gold lines show each step's turn-in.
  - Steps in other zones sit at the map's edge with their zone name.
  - The panel lists the steps in order. Click one to set a waypoint to it.
- `/dmap` (or `/davesmap`) toggles the layer. Also `/dmap panel`, `/dmap options`, `/dmap calib` (how well the pins line up) and `/dmap version` (the data's date).

## Where the data comes from

`Data.lua` is generated, and it is **not in git**: Map Genie's data is theirs and this repo is public. Build or refresh it with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Update-MapData.ps1
```

The `daves-map-refresh` skill (in `.claude/skills/`) runs it, checks the result and tells you what changed.

1. **Map Genie** (`mapgenie.io/world-of-warcraft-forever/maps/azeroth`): the groups and categories come from the page, and the pins from the map's public data endpoint. Links in descriptions are dropped. A link to another pin on the same map, such as a zeppelin's destination, becomes a pin-to-pin link. No media or icons are copied, and nothing behind a login is read.
2. **pfQuest** (`github.com/shagu/pfQuest`, MIT licence): Classic quest IDs, prerequisites and turn-in NPCs. Quests are matched by title, plus start NPC, faction and level where there's a choice. About 87% of Map Genie's quest pins match; the rest are mostly Forever's own quests.

Everything downloaded is read as data, never run. The script saves downloads into a new temporary folder, parses them with a JSON parser and its own small Lua-literal reader, and then deletes them.

### How positions line up

Map Genie's positions are pixels on their own picture of Azeroth. `Calibrate.lua` matches Map Genie's flight master pins to the game's flight points by name, using `C_TaxiMap.GetTaxiNodesForMap`, which also returns undiscovered nodes. It then fits an affine transform per continent. Each pin gets its continent position, its zone and its world position, and from those its position on any map. `/dmap calib` prints the anchors used and the error.

### Why a layer of its own

The pins are plain textures on a frame of ours on the map canvas. One small button follows the hovered pin for clicks. Blizzard's `AddDataProvider`/`AcquirePin` would run Blizzard's map code from addon code, and its pins then call `SetPassThroughButtons`, which is blocked in combat once tainted. Nothing is registered with the map; the addon only reads the map's ID, zoom and cursor.

## Develop

| Task | Command |
| --- | --- |
| Rebuild the data | `tools\Update-MapData.ps1` (`-KeepRaw` keeps the downloads, `-NoQuestDb` skips pfQuest) |
| Repaint the textures | `tools\Make-Media.ps1` |
| Check the addon | `Test-WowAddon.ps1 -Path . -Flavor forever` |
| Link into the game | `Link-WowAddons.ps1 -Path .` |
| Reload after editing Lua | `/reload` in game (new files or TOC changes need a full restart) |

| File | Purpose |
| --- | --- |
| `Core.lua` | Startup, saved settings, the slash command |
| `Data.lua` | Generated: groups, categories, pins (columns), links |
| `Calibrate.lua` | Map Genie pixels to game map positions, using the flight points |
| `Layer.lua` | The pins, link lines, hover, click and tooltip on the world map |
| `Panel.lua` | Search, factions, quest filters, categories, results |
| `Options.lua` | Settings page: layer on/off, panel, pin size |
