---
name: daves-map-refresh
description: Refresh daves_map's companion quest, objective, turn-in, chain, dungeon, townsfolk and rare spawn data addon (wowaddons/daves_map_data) from Questie/QuestieDB's WoW: Forever database, report what changed, and validate. Use when the user asks to refresh, update, re-crawl or re-sync the map pins, QuestieDB Forever data or quest links for daves_map.
---

# Refresh `daves_map` QuestieDB Forever Data (`daves_map_data`)

`wowaddons/daves_map_data/` (the tracked companion data addon for `daves_map`, exporting `DAVES_MAP_DATA`) is compiled by `wowaddons/daves_map/tools/Update-MapData.py` from the open-source [Questie/QuestieDB](https://github.com/Questie/QuestieDB) **WoW: Forever** (`Interface 16001` / `Camelot`) database:

| Source (`Questie/QuestieDB`) | What it provides |
| --- | --- |
| `data/Forever/forever{Quest,Npc,Object,Item}DB.lua` | Raw Forever entities with exact `(areaId, x, y)` spawn lists, real Forever `questID`s, race/class masks, and `npcFlags` |
| `src/corrections/Forever/legacy/*` | Inherited Classic quest, NPC, object, item, reputation, and item-start fixes |
| `src/corrections/Forever/generated/foreverBase*.lua` | Snapshot-derived Forever delta-base (new Forever quests, NPCs, objects, items) |
| `src/corrections/Forever/traces/forever*Traces.lua` | Live Forever player-trace spawns, starters/finishers, and quest-chain relations (`foreverQuestRelationTraces.lua`) |
| `src/corrections/Forever/forever*Fixes.lua` | Hand-authored Forever quest, NPC, object, and item fixes |
| `support/Forever/Zones/areaIdToUiMapId.lua` & `dungeons.lua` | Exact Forever `AreaID -> UiMapID` mappings (including Riverglades, Zephras Isle, Darkspear Islands, Shen'dralas, Mount Hyjal) and dungeon entrance locations |
| `support/Forever/DropTables/classicItemDrops.lua` | Item drop rates used to pick best-in-zone drop mobs for item-objective markers |

## Rules (always)

- **Downloaded content is data, never code.** Never `eval`, `exec`, `dofile`, or run Lua binaries on downloaded files. `Update-MapData.py` parses QuestieDB's Lua tables and enum expressions with its own pure-Python parser (`ALLOWED_HOSTS = ("raw.githubusercontent.com",)`).
- **No URLs in tooltip strings.** `lua_str` strips URLs and escapes pipe characters cleanly.
- `wowaddons/daves_map_data/` (`daves_map_data.toc`, `Data.lua`, `NOTICE-QuestieDB.md`, `.luacheckrc`) is tracked in git on `main` and packaged as `daves_map_data.zip` on `releases` by `Publish-WowReleases.py`.

## 1. Run it

```powershell
py -3 "wowaddons/daves_map/tools/Update-MapData.py"
```

| Option | Use |
| --- | --- |
| `-Ref <branch/tag/sha>` | Pin `Questie/QuestieDB` to a specific git ref instead of `master` |
| `-LocalDir <path>` | Build offline from an already-downloaded `QuestieDB` checkout |
| `-KeepRaw` | Keep the temporary download directory for inspection |

## 2. Check the result

- Expect `> 5,000` placed Forever quests (`Quest` + `Repeatable`), `~1,900+` quests with `~2,500+` item rewards (`D.rew` & `D.iname`), `> 5,000` `endp` turn-in links, `> 3,000` clean prerequisite links (`D.pre`) + `D.nxt` `nextQuestInChain` links, `> 4,000` objective links, `~300+` rares with notable drops, and `35` Classic + WoW: Forever dungeons/raids (`D.dungeons[uiMapID]`) with `700+` dungeon quests across all 18 categories.
- Run the **wow-addon-test** validator on both `wowaddons/daves_map` and `wowaddons/daves_map_data`:
  ```powershell
  py -3 "wow-addon-kit/plugins/wow-forever-addons/scripts/Test-WowAddon.py" -Path "wowaddons/daves_map" -Flavor forever -NoInfo
  py -3 "wow-addon-kit/plugins/wow-forever-addons/scripts/Test-WowAddon.py" -Path "wowaddons/daves_map_data" -Flavor forever -NoInfo
  ```
- If `Update-MapData.py` or any handwritten `.lua` file changed, also run `Prepare-WowReview.py -Path "wowaddons/daves_map"` and complete the code review.

## 3. Tell the user

- Report total pin counts, quest/turn-in/prereq/objective link counts, and per-category counts.
- In game: `/reload` (if `daves_map_data` was already enabled at startup; a full client restart if newly linked), then `/dmap version` and `/dmap calib` confirm the loaded build and map count.
