# Dave's WoW addons

WoW addons (`wowaddons/`) plus the kit that builds and checks them (`wow-addon-kit/`, plugin `wow-forever-addons`).

## Use the plugin for anything WoW

For any World of Warcraft work here, use the `wow-forever-addons` plugin's skills, agent and scripts, not recall or the web:

| Task | Use |
| --- | --- |
| Does an API/method/event exist, is it secret, did it move | `wow-forever-api` skill → `scripts/Find-WowApi.py <pattern...> [-Events] [-Methods]` (batch multiple names in one call) |
| How Blizzard's own UI does something | `scripts/Find-WowApi.py <symbol...> -UiSource` (searches `INDEX.tsv` filtered to Forever-loaded folders), then read under `wow-addon-kit/plugins/wow-forever-addons/data/ui-source/forever/` |
| Something broke in game (error, "action blocked", "only available to the Blizzard UI", odd behaviour) | `wow-addon-test` skill, step 0 (the one full statement of the order). **Before reading code**: the recorded addon errors (`scripts/Get-WowScriptErrors.py -Addon <name>`). If nothing was recorded, the taint log (`scripts/Get-WowTaintLog.py -Addon <name>`). Then the code |
| After any addon change | `wow-addon-test` skill → `scripts/Prepare-WowReview.py -Path <addon>` (validates + builds diff/API/NOTES packet; inline advisor review when `RecommendedMode: inline`, or pass packet to `wow-addon-reviewer` agent) |
| New addon / install, link, Interface number / release | `wow-addon-new` / `wow-addon-setup` / `wow-addon-release` |
| Refresh daves_map's Map Genie pins and quest links | `daves-map-refresh` skill (`.claude/skills/`) → `wowaddons/daves_map/tools/Update-MapData.py`; generates the companion addon `wowaddons/daves_map_data/`, never committed |
| Paint or pack a `daves_frames` AI target-frame theme | `daves-frames-paint` skill (`.claude/skills/`) → `guides/frame-template-ai.png` (`2048×1152`, `16:9`) + `wowaddons/daves_frames/tools/Pack-FrameTemplate.py` |

When a plugin script or the local source is missing or stale, refresh it (`Update-WowApiIndex.py`, `Update-WowUiSource.py`) rather than working around it.

## Always keep Markdown skills and documentation updated

Whenever code, scripts, tools, workflows, slash commands, settings, files, versions, or architecture change anywhere in this project, update every affected `.md` file in the same task so skills and docs never drift out of sync:

- **Skills & reviewer agent:** `wow-addon-kit/plugins/wow-forever-addons/skills/*/SKILL.md` (and `sources.md`), `.claude/skills/*/SKILL.md`, `.agents/skills/*/SKILL.md`, and `wow-addon-kit/plugins/wow-forever-addons/agents/wow-addon-reviewer.md`.
- **Addon & tool docs:** `wowaddons/<addon>/README.md`, `wowaddons/<addon>/NOTES.md` (keep still-valid architecture notes and deferred/skipped review logs intact), and tool/template guides (e.g., `PAINT-LAYERS.md`, `tools/**/README.md`).
- **Root & kit docs:** `AGENTS.md`, `CLAUDE.md`, `README.md`, and `wow-addon-kit/README.md` (plus `templates/addon/README.md` when templates change).
