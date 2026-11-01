# Dave's Chat

Movable chat dock for wide screens (`v0.3.4`). Party, whispers, and say on the first tab, the combat log on the second, and general on the third — with a collapsible, auto-fitted, scrollable tab list on the left inside the window, chat messages in their own bordered inner frame on the right (expanding to full width when tabs are hidden), a choice of text direction (stock bottom-up or newest on top), and an optional faint mode that shows only the chat text until you hover the window.

Targets: forever (`## Interface: 16001, 11509, 20506`).

## Use

- **Window, Margins & Resizing**: The window opens on the bottom left (`520×320` default, minimum `300×180`) with comfortable inner margins around all four sides. Drag the empty part of the top header row or left tab list to move it, right-click that drag area to reset its position, or drag either bottom corner grip to resize it. Edit Mode (`Esc > Edit Mode`) moves it and snaps it to the grid as well.
- **Collapsible, Auto-Fitted & Scrollable Left-Side Chat Tabs**:
  - Click the **Show/Hide Chat Tabs** eye button on the left of the header bar to toggle the left-side tab list (`Chat`, `Combat Log`, `General`, plus any custom tabs or temporary whisper tabs).
  - **When shown**: the tab list auto-fits its width to the widest tab name before truncating, capped at **1/3 of the window frame width** (`min 76px`). Longer names clip cleanly with a hover tooltip, unread background tabs pulse softly, right-clicking any tab opens a menu to **Rename Window**, tick **Default Window**, **Create New Window**, **Close Window**, or open **Chat Settings** (middle-click also closes extra tabs), and when too many tabs exist to fit vertically, the list scrolls smoothly with the mouse wheel or its slim thumb scrollbar.
  - **When hidden**: the inner chat frame and chat input box expand across the full inner width of the window (and the header eye button pulses softly if a hidden background tab receives an unread alert).
- **Default Window**: Right-click any tab (except temporary whisper tabs) and tick **Default Window** to make it the tab selected on login / `/reload` and whenever you reopen the window from the message-bubble icon. The default tab shows a small gold star (hover it for a reminder). Unticking it, or closing / deleting that window, sets the default back to the main **Chat** window.
- **Inner Chat Frame & Aligned Input Box**: The chat text and scrollbar sit inside a bordered inner frame (`InsetFrameTemplate`) with generous inner text padding. The chat input box (`ChatFrameEditBox`) aligns pixel-flush left-to-right with the inner chat frame (both when tabs are shown and when expanded to full width), with equal visual margin above and below it.
- **Text Direction (Window Settings)**: **Bottom** (default, stock WoW) adds new messages at the bottom and pushes older ones up. **Top** (`SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP`) puts the newest message at the top of the inner chat frame and grows older ones downward. Switching applies right away to every docked tab, and the mouse wheel and scrollbar follow the chosen direction. Empty chat space still passes 3D camera clicks through while links stay clickable.
- **Faint (Window Settings)**: When ticked, the border, background, header, tab list, inner frame border, scrollbar, resize grips, and idle input box fade out about half a second after the mouse leaves the window, leaving only the chat text. Hovering the window (or typing, resizing, having Window Settings open, or being in Edit Mode) fades everything back in.
- **Header Controls**:
  - **Left**: Blizzard's **Social** button at the far left (`QuickJoinToastButton` on Forever / Mainline; on Classic, the chat friends button `FriendsMicroButton` if that client has one — Classic clients don't load Blizzard's QuickJoin addon), **Show/Hide Chat Tabs** (eye icon), **Channels** (`ChatFrameChannelButton`), and **Text-to-Speech** (only when TTS is enabled).
  - **Right**: **Chat Settings** (message-bubble icon, opens Blizzard's `ChatConfigFrame` for the active tab with extra inner padding), **Window Settings** (window icon, opens the Edit Mode dialog for `Scale`, `Width`, `Height`, `Background` darkness, `Background style` — `Dark`, `Light paper`, `Dark paper`, `Marble`, `Rock` — `Text direction`, `Faint`, `Whisper alert`, `Restore defaults`, `Reset tabs`, `Reset position`), and the standard WoW **Close (`X`)** button (`UIPanelCloseButton`) in the top-right corner.
- **Say Box Never Floats Over Controls**: Clicking any window control while the Say box is focused or holds unsent text (header icons, Social, Channels, the tab list, drag strip, resize grips, the close `X`, or the Window Settings dialog) clears the Say box first, so it never sits on top of what you clicked. Clicking the chat text itself leaves it alone, so shift-clicking links into the box still works.
- **Tooltips**: Every header tooltip, including Blizzard's own Social and Channels buttons, opens right beside its icon (above it in the lower half of the screen, below it in the upper half).
- **Clean Close & Draggable Message-Bubble Open Icon**: Clicking the top-right **`X`** button cleans up any unsent text, autocomplete popup, and keyboard focus in the chat input box (without tainting `chatType` or `SendChatMessage`) and collapses the window down to a draggable **message-bubble icon**. Drag the icon anywhere; click it (or press `Enter` to type) to reopen the window at its saved size and position.
- **Whisper Alert**: Flashes the message-bubble open icon (while closed) or the `Chat` tab / `Show Tabs` eye button (while viewing another tab) when a whisper arrives. The usual whisper sound still plays while closed.
- **Slash Commands**:
  - `/daveschat`, `/daveschat window`, or `/daveschat settings` — open **Window Settings**
  - `/daveschat chat` or `/daveschat config` — open Blizzard's **Chat Settings** (`ChatConfigFrame`)
  - `/daveschat options` or `/daveschat addon` — open **AddOn Options** (`Esc > Options > AddOns > Dave's Chat`)
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

Files: `daves_chat.toc`, `Core.lua`, `EditModeDialog.lua`, `Tabs.lua`, `Dock.lua`, `Header.lua`, `Window.lua`, `EditMode.lua`, `Options.lua`, `Media/grip.tga`. See `NOTES.md` for architecture details and Forever UI constraints.
