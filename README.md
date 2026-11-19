# Mouse Zones

An AutoHotkey v2 script for Windows that gives each physical mouse its own screen.

Windows has a single cursor, and every mouse you plug in moves it. With two mice and several screens, you keep dragging the cursor back from wherever the other mouse left it. Mouse Zones keeps one cursor, but:

- each mouse is kept on its own screen;
- each mouse remembers where it left the cursor, so when you pick up the other mouse, the cursor jumps back to that mouse's spot;
- a mouse you haven't assigned can still go anywhere.

No driver is needed. The script reads Windows Raw Input, which already says which device each movement came from.

On start, a small message says "Mouse Zones is starting…" and then "Mouse Zones ready ✓" with the trackpad profile, so after logging in you can see when it's working. Each start and exit is written to `mouse-zones.log`.

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
Move the trackpad, then press **Ctrl+Alt+F** to mark it as a trackpad (press again to undo). Input with no device handle counts as a trackpad too: Windows precision touchpads send their input that way. Touch-screen and pen input (signature `0xFF5157xx`) is ignored.

A trackpad has three profiles. Switch between them from the tray menu, from **right-click the desktop → Trackpad profile** (the script adds this entry itself, and ● marks the active profile), or by running `mouse-zones.ahk /trackpad1`, `/trackpad2` or `/trackpad3`:

| Profile | What the trackpad does |
|---|---|
| 1. Separate: trackpad has its own spot | Works like one more free mouse: keeps its own spot, apart from the mice, and goes anywhere. Touch the trackpad and the cursor jumps to the trackpad's spot; touch a mouse and it jumps back to that mouse's spot |
| 2. Follow the latest mouse | Has no spot of its own: starts wherever the last mouse left the cursor and goes anywhere. It never changes a mouse's spot, so the next mouse you touch (the same one or another) comes back to its own spot |
| 3. Own screens only | Stays on the screens listed in `trackpadScreens` and keeps its own spot there. Push past the side edge of one screen and it comes in on the next one, even when other screens sit between them |

### Swap two mice
Item **4. Swap** in the same menus (or `mouse-zones.ahk /swap`) is an on/off switch: the two mice in `swapA` / `swapB` trade their screens and their spots, and ● shows when it's on. Example: normally the Bluetooth mouse owns the big screen and the USB mouse is free; swapped, the USB mouse owns the big screen and the Bluetooth mouse is free. Ctrl+Alt+M / U are locked while the swap is on.
```
[settings]
swap=0
swapA=<device key of the mouse that normally owns a screen>
swapB=<device key of the mouse that is normally free>
```
The device keys are the ones written under `[zones]` / `[pos]`.

### Free USB mouse
Item **5. Free USB mouse** (or `mouse-zones.ahk /freeusb`) is another on/off switch: the `swapB` mouse never has a fixed screen, whatever else is set. Nothing else changes: with the swap on, both mice are free; with the swap off, the USB mouse was free anyway. Saved as `usbFree=1` under `[settings]`. Turning it off puts the cursor in the middle of the big screen (the USB mouse's screen while swapped, else `swapA`'s), unless it is already on that screen: then it stays where it is.

Shortcut: **3 quick right clicks on the USB mouse** (the `swapB` mouse), each within 0.6 s. Each one is still a right click; if the last one left a context menu under the cursor, the script closes it with Esc. (Left-right-left would be a bad shortcut: it's the normal "right-click, pick an item" move.)

### 3- and 4-finger taps
| Tap | Shortcut | What it does |
|---|---|---|
| 3 fingers | **Ctrl+Alt+Shift+3** (or F9) | On profile 1/2: profile 3, on the **first** trackpad screen. On profile 3: back to profile 1, where the cursor was before it went to the trackpad screens (saved as `TRACKPAD-HOME` under `[pos]`) |
| 4 fingers | **Ctrl+Alt+Shift+4** (or F10) | On profile 1/2: profile 3, on the **second** trackpad screen. On profile 3: hops to the other trackpad screen |

Each trackpad screen keeps the trackpad's last spot on it (`TRACKPAD-S1` / `TRACKPAD-S2`).

The mice keep their own spots. `mouse-zones.ahk /tap` and `/hop` do the same from a command line.

To put them on the taps: Windows Settings → Bluetooth & devices → Touchpad → Advanced gestures → Tap → Custom shortcut → record the keys. Windows' key recorder ignores F-keys, which is why the digit versions exist. The setting lives in `HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad`:
```
ThreeFingerTapEnabled        = 0xFFFF       (custom shortcut)
CustomThreeFingerTap         = 7            (Ctrl + Shift + Alt)
CustomThreeFingerTapKeyParams = 0x00330013  (high word = virtual key, 0x33 = "3")
```
and the same values with `Four` for the 4-finger tap (`0x00340013` = "4"). Windows then opens Search and Notification center with Win+S and Win+N only.

### 4-click shortcut on the trackpad
Click or tap the trackpad 4 times quickly (each within 0.45 s) to step through a cycle:
1. trackpad profile 3;
2. also the mouse swap on;
3. back to how it was before the first step (the old trackpad profile, and the swap as it was).

Choosing a profile or the swap from a menu ends the cycle. The clicks still reach whatever is under the cursor.

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

A device takes over the cursor only on a click/scroll, or on a real move in one direction: a net 12+ counts over 3+ reports within 0.25 s, or 40+ while another device is moving at that moment. A mouse lying still can send empty reports or back-and-forth jitter (fast on 1000 Hz receivers). The empty ones are ignored and the jitter cancels out in the sum, so neither can steal the cursor. Each mouse's spot is saved in `mouse-zones.ini`, so it survives a restart. Every switch is written to `mouse-zones.log`.

## Limits
- There is still one cursor. You can't use both mice at the same moment.
- Move a mouse slightly before you click with it. Windows can handle a click before the script has moved the cursor, so a click straight after using the other mouse may land at the other mouse's spot.
- If you change the screen layout in Display settings, press Ctrl+Alt+M again for each mouse.
- Ctrl+Alt+Del always releases the cursor clip; the next mouse movement sets it again.

## License
MIT
