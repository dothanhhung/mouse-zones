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
Move the trackpad, then press **Ctrl+Alt+F** to mark it as a trackpad (press again to undo). Input with no device handle (some precision touchpads, injected input) always counts as a trackpad and uses profile 2.

A trackpad has three profiles. Switch between them from the tray menu, from **right-click the desktop → Trackpad profile** (the script adds this entry itself, and ● marks the active profile), or by running `mouse-zones.ahk /trackpad1`, `/trackpad2` or `/trackpad3`:

| Profile | What the trackpad does |
|---|---|
| 1. Default: follow the USB mouse | Acts as the last mouse that has no screen of its own: it shares that mouse's spot and moves it |
| 2. Follow the latest mouse | Has no spot of its own: starts wherever the last mouse left the cursor and goes anywhere. It never changes a mouse's spot, so the next mouse you touch (the same one or another) comes back to its own spot |
| 3. Own screens only | Stays on the screens listed in `trackpadScreens` and keeps its own spot there. Push past the side edge of one screen and it comes in on the next one, even when other screens sit between them |

Profile 3 reads its screens from `mouse-zones.ini`, ordered left to right (`L,T,R,B` in real pixels, separated by `|`):
```
[settings]
trackpad=3
trackpadScreens=0,0,1920,1080|3840,29,5760,1109
```
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

A mouse takes over the cursor only on a real move (4+ counts within 0.3 s) or a click/scroll. Empty or jitter reports, which some Bluetooth mice send while lying still, are ignored. Each mouse's spot is saved in `mouse-zones.ini`, so it survives a restart. Every switch is written to `mouse-zones.log`.

## Limits
- There is still one cursor. You can't use both mice at the same moment.
- Move a mouse slightly before you click with it. Windows can handle a click before the script has moved the cursor, so a click straight after using the other mouse may land at the other mouse's spot.
- If you change the screen layout in Display settings, press Ctrl+Alt+M again for each mouse.
- Ctrl+Alt+Del always releases the cursor clip; the next mouse movement sets it again.

## License
MIT
