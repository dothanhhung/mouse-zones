# Mouse Zones

An AutoHotkey v2 script for Windows that gives each physical mouse its own screen.

Windows has a single cursor, and every mouse you plug in moves it. With two mice and several screens, you keep dragging the cursor back from wherever the other mouse left it. Mouse Zones keeps one cursor, but:

- each mouse is kept on its own screen;
- each mouse remembers where it left the cursor, so when you pick up the other mouse, the cursor jumps back to that mouse's spot;
- a mouse you haven't assigned can still go anywhere.

No driver is needed. The script reads Windows Raw Input, which already says which device each movement came from.

## Install
1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Download `mouse-zones.ahk` into a folder of its own. It writes `mouse-zones.ini` next to itself.
3. Double-click it. A green "H" appears in the system tray.
4. To start it with Windows, put a shortcut to it in `shell:startup`.

## Set up (once)
1. Move **mouse 1** onto the screen it should own and press **Ctrl+Alt+M**.
2. Move **mouse 2** onto its screen and press **Ctrl+Alt+M**.

The assignments are saved and come back after a restart.

## Keys
| Keys | What it does |
|---|---|
| Ctrl+Alt+M | The mouse you moved last now owns the screen under the cursor |
| Ctrl+Alt+U | Unassign the mouse you moved last (it can go anywhere again) |
| Ctrl+Alt+F | The device you moved last is a trackpad (toggle): see below |
| Ctrl+Alt+P | Pause / resume |

## Trackpads
A trackpad has no spot of its own. It carries on from wherever the last mouse left the cursor and can go to any screen. It counts as part of that mouse, so when you pick that mouse up again it carries on from where the trackpad stopped. The one exception: if the mouse has its own screen and the trackpad left the cursor on another screen, the mouse jumps back to its own spot.

Move the trackpad, then press **Ctrl+Alt+F** to mark it (press again to undo). Input with no device handle (some precision touchpads, injected input) always counts as a trackpad.
| Ctrl+Alt+Q | Quit |

## Moving windows to another screen
Your mouse can't leave its screen, so you can't drag a window all the way across. Drag it toward the other screen until **half or more of it** is past the edge, then let go. The script moves the whole window onto that screen, next to the edge you crossed.

Your mouse stops at the screen edge, so grab the title bar on the side away from the target screen: the left side to move a window right, the right side to move it left. A window grabbed in the middle only gets about halfway out.

Windows' own shortcut works too: **Win+Shift+←/→** moves the active window to the next screen.

## How it works
- `RegisterRawInputDevices` with `RIDEV_INPUTSINK` sends the script every mouse event, along with the handle of the device it came from. Mice are saved by their hardware ID (the `VID/PID` part of `RIDI_DEVICENAME`, without the instance part), so a mouse keeps its screen after a restart, a Bluetooth reconnect or a move to another USB port. Two mice of the exact same model share one setting.
- When a different mouse moves, the script saves the cursor position for the mouse it is leaving, calls `SetCursorPos` to put the cursor at the new mouse's last spot, and calls `ClipCursor` to keep it inside that mouse's screen. The clip is set again on every event, because Windows drops it on some focus changes.
- Window moves are detected with a `SetWinEventHook` on `EVENT_SYSTEM_MOVESIZESTART`/`END`. Resizes are ignored. Maximized or snapped windows are left alone.
- The thread runs per-monitor DPI aware, so the coordinates stay correct on screens with different scaling.

## Limits
- There is still one cursor. You can't use both mice at the same moment.
- Move a mouse slightly before you click with it. Windows can handle a click before the script has moved the cursor, so a click straight after using the other mouse may land at the other mouse's spot.
- If you change the screen layout in Display settings, press Ctrl+Alt+M again for each mouse.
- Ctrl+Alt+Del always releases the cursor clip; the next mouse movement sets it again.

## License
MIT
