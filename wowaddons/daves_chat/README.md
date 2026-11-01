# Dave's Chat

Movable chat dock for wide screens (`v0.3.0`). Party, whispers, and say on the first tab, the combat log on the second, and general on the third — with stacked tabs on the left inside the window, chat messages in their own inner frame on the right, and newest messages at the top growing downward.

Targets: forever (`## Interface: 16001, 11509, 20506`).

## Use

- **Window & Resizing**: The window opens on the bottom left (`520×320` default, minimum `430×180`). Drag the empty part of the top header row or left tab column to move it, right-click that drag area to reset its position, or drag either bottom corner grip to resize it. Edit Mode (`Esc > Edit Mode`) moves it and snaps it to the grid as well.
- **Left-Side Stacked Tabs & Inner Chat Frame**: Chat tabs (`Chat`, `Combat Log`, `General`, plus any extra docked tabs) stack vertically on the left side *inside* the main window frame (`UIPanelButtonTemplate`). Long tab names clip cleanly and show a tooltip on hover, and unread background tabs pulse softly. Next to the tab column, the chat text and scrollbar sit inside their own bordered inner frame (`InsetFrameTemplate`), with the chat input box aligned directly underneath it.
- **Top-Down Chat Growth (Newest on Top)**: Docked chat frames use top-insert mode (`SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP`) so the newest messages appear at the top of the inner chat frame and older messages grow downward. Rolling the mouse wheel down (or dragging the scrollbar thumb down) scrolls down through older history; empty chat space still passes 3D camera clicks through while links remain clickable.
- **Header & Independent Settings Dialog**: The top header bar holds Blizzard's **Social** button (`QuickJoinToastButton`), the **Channels** button (`ChatFrameChannelButton`), the **Text-to-Speech** button (only when TTS is enabled), a single **Settings** gear button on the right, and a standard WoW **Close (`X`)** button (`UIPanelCloseButton`) in the top-right corner. Clicking **Settings** (or typing `/daveschat`) opens a separate **Settings** dialog that opens each settings window independently:
  - **Chat Settings** — opens Blizzard's `ChatConfigFrame` for the active chat tab (with extra inner padding).
  - **Window Settings** — opens the Edit Mode dialog (`Scale`, `Width`, `Height`, `Background` darkness, `Background style` — `Dark`, `Light paper`, `Dark paper`, `Marble`, `Rock` — `Whisper alert`, `Restore defaults`, `Reset tabs`, `Reset position`). Both **Settings** and **Window Settings** share the selected background style and darkness.
  - **AddOn Options** — opens `Esc > Options > AddOns > Dave's Chat`.
- **Standard Open & Close**: Clicking the top-right **`X`** button closes the window down to a draggable standard WoW **`Chat`** button (`UIPanelButtonTemplate`). Drag **`Chat`** anywhere; click it (or press `Enter` to type) to reopen the window at its saved size and position.
- **Whisper Alert**: Flashes the **`Chat`** open button (while closed) or the **`Chat`** tab (while viewing another tab) when a whisper arrives. The usual whisper sound still plays while closed.
- **Slash Commands**:
  - `/daveschat` or `/daveschat settings` — open the **Settings** dialog
  - `/daveschat chat` — open Blizzard's **Chat Settings** (`ChatConfigFrame`)
  - `/daveschat window` — open **Window Settings**
  - `/daveschat options` — open **AddOn Options** (`Esc > Options > AddOns > Dave's Chat`)
  - `/daveschat tabs` — reapply the default `Chat`, `Combat Log`, `General` tab layout
  - `/daveschat reset` — reset the window position to the bottom left
  - `/daveschat version` — print the loaded addon version
- The first time it loads, the three default tabs are configured once (`layoutVersion = 1`). After that, filters you change in Chat Settings stay until `/daveschat tabs`. Numbered public channels (`General`, `Trade`, etc.) route to the `General` tab while `"Keep public channels on General"` is enabled.

## Develop

| Task | Command |
| --- | --- |
| Check the addon | `python wow-addon-kit/plugins/wow-forever-addons/scripts/Test-WowAddon.py -Path wowaddons/daves_chat -Flavor forever` |
| Prepare review packet | `python wow-addon-kit/plugins/wow-forever-addons/scripts/Prepare-WowReview.py -Path wowaddons/daves_chat` |
| Link into the game | `python wow-addon-kit/plugins/wow-forever-addons/scripts/Link-WowAddons.py -Path wowaddons/daves_chat` |
| Reload after editing Lua | `/reload` in game (new files or TOC changes need a full restart) |

Files: `daves_chat.toc`, `Core.lua`, `EditModeDialog.lua`, `Tabs.lua`, `Dock.lua`, `Header.lua`, `Window.lua`, `EditMode.lua`, `Options.lua`, `Media/gear.tga`, `Media/grip.tga`. See `NOTES.md` for architecture details and Forever UI constraints.
