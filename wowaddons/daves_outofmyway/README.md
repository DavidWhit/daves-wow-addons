# Dave's Out Of My Way (daves_outofmyway)

Blizzard frames that get in the way, moved or opened up.

Targets: Forever (`## Interface: 16001`).

## What it does

- **Loot rolls (need/greed):** open Edit Mode and drag the "Loot rolls" frame wherever you want them. Click it for its settings: Scale, whether more rolls stack above or below the first, and "Back to Blizzard's spot". Right-click resets it. Until you move it, the rolls stay exactly where Blizzard puts them.
- **Buff frame:** every buff shown, and the frame never collapses. Forever's options have no switch for this. Two settings control it: `consolidateBuffs`, which keeps the frame collapsed behind one icon whatever else you set, and `collapseExpandBuffs`, the arrow that hides long buffs.
  - "Show all buffs (never collapse)" (Esc > Options > AddOns, on to start with) turns both off and remembers what you had. Turning it off puts that back.
  - Nothing is switched while you play: the change is made as the UI shuts down (logout, quit or `/reload`), so it shows from your next reload or login, and the addon offers the reload in a small window of its own. Changing these settings mid-session would taint Blizzard's buff frame (a typed `/console` too, since Forever's runs insecure) and could block cancelling a buff in combat; switched at logout, the next UI reads them cleanly and nothing writes them again.
  - If something turns one back on, it's switched off again at the next logout. If they come back after a reload anyway (the client doesn't keep them), the addon says so once and leaves them alone; tick the option again to retry.
  - With both off, every buff shows, up to 32. Edit Mode's Icon Limit on the buff frame only sets how many sit in each row.
  - `/oomw buffs` shows the state.
- **The flight-path dismount button** (MainMenuBarVehicleLeaveButton, "request early landing") is not moved by this addon on purpose. It is one of Blizzard's own Edit Mode frames on Forever: tick **Vehicle Leave Button** in Edit Mode's settings (click Expand options, then Misc) and drag it there. An addon can't hold it anywhere. Edit Mode places it again with the action bars every time it appears, and moving it from addon code would taint the action bars, so actions would be blocked in combat. Opening Edit Mode reminds you once if that setting is off.

One known limit: while a roll is open, Blizzard's own roll container still takes its usual space, empty, above the action bars. Loot toasts stack above that gap. Changing the container would taint the managed layout it shares with protected frames, so it's left alone.

`/oomw` opens the options. Also `/oomw reset` (loot rolls back to Blizzard's spot), `/oomw buffs` (the buff frame's state), `/oomw leave` (the dismount-button tip) and `/oomw version`.

## How (and why it's taint-safe)

| Frame | How it's moved |
| --- | --- |
| Loot rolls | A `hooksecurefunc` post-hook on `GroupLootContainer_Update` re-anchors the roll frames to our own anchor after Blizzard has placed them. `GroupLootContainer` itself is a bottom-managed frame laid out with protected frames, and it's never touched. |
| Buff frame | The two CVars are set only at `PLAYER_LOGOUT` (which `/reload` fires too). `CVAR_UPDATE` is synchronous, so setting them runs Blizzard's update tainted (so does a typed `/console`); at logout that UI is being torn down, so the taint never reaches a live session. |
| Dismount button | Left to Blizzard's Edit Mode. The setting is only read, never written. |

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `Test-WowAddon.ps1 -Path . -Flavor forever` |
| Link into the game | `Link-WowAddons.ps1 -Path .` |
| Reload after editing Lua | `/reload` in game (new files or TOC changes need a full restart) |

| File | Purpose |
| --- | --- |
| `Core.lua` | Startup, saved settings, the slash command |
| `EditModeDialog.lua` | The kit's shared Edit Mode behaviour (don't edit; copy from the kit) |
| `LootRolls.lua` | The loot roll anchor and the post-hook that places the rolls |
| `EditMode.lua` | The anchor in Edit Mode: dialog, settings, the dismount-button tip |
| `Buffs.lua` | The buff CVars: off while the option is on, put back when it's off |
| `Options.lua` | Settings page |
