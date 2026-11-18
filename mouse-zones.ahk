; Mouse Zones - give each physical mouse its own screen.
; One Windows cursor, but each mouse remembers its own spot and stays on its own screen.
;
;   Ctrl+Alt+M  move a mouse onto a screen, then press: that mouse now owns that screen
;   Ctrl+Alt+U  unassign the mouse you moved last (it roams freely again)
;   Ctrl+Alt+P  pause / resume
;   Ctrl+Alt+Q  quit
; Assignments are saved in mouse-zones.ini next to this script.

#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

global INI := A_ScriptDir "\mouse-zones.ini"
global zone := Map()      ; device name -> [L, T, R, B]
global pos := Map()       ; device name -> [x, y] last cursor spot of that mouse
global names := Map()     ; raw handle -> device name (cache)
global active := ""       ; device name that owns the cursor now
global lastDev := ""      ; device name that moved last
global enabled := true

LoadZones()

; Listen to all mice, even when this script has no focus (RIDEV_INPUTSINK).
rid := Buffer(8 + A_PtrSize, 0)
NumPut("ushort", 1, "ushort", 2, "uint", 0x100, "ptr", A_ScriptHwnd, rid)
if !DllCall("RegisterRawInputDevices", "ptr", rid, "uint", 1, "uint", rid.Size)
    MsgBox "Could not register for raw mouse input."
OnMessage(0x00FF, OnRawInput)
OnExit((*) => DllCall("ClipCursor", "ptr", 0))

; Window drag: when a window is dropped with 50%+ of it off its screen,
; move it fully onto the screen it was dragged toward.
global dragStart := Map()
global moveHook := CallbackCreate(OnMoveSize, , 7)
DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B, "ptr", 0, "ptr", moveHook
    , "uint", 0, "uint", 0, "uint", 0, "ptr")   ; MOVESIZESTART..MOVESIZEEND, out of context

A_IconTip := "Mouse Zones (Ctrl+Alt+M assign, Ctrl+Alt+P pause)"
Tip("Mouse Zones running - " zone.Count " mouse(s) assigned")

OnRawInput(wParam, lParam, msg, hwnd) {
    global active, lastDev
    PMA()
    hdr := 8 + 2 * A_PtrSize
    size := 0
    DllCall("GetRawInputData", "ptr", lParam, "uint", 0x10000003, "ptr", 0, "uint*", &size, "uint", hdr)
    if !size
        return
    buf := Buffer(size, 0)
    DllCall("GetRawInputData", "ptr", lParam, "uint", 0x10000003, "ptr", buf, "uint*", &size, "uint", hdr)
    if NumGet(buf, 0, "uint") != 0          ; not a mouse
        return
    hDev := NumGet(buf, 8, "ptr")
    dev := hDev ? DevName(hDev) : "(none)"  ; 0 = injected / some touchpads
    lastDev := dev
    if !enabled
        return

    if (dev = active) {
        if zone.Has(dev)
            Clip(zone[dev])                 ; Windows drops the clip on some focus changes
        return
    }

    ; another mouse took over: remember where the old one left the cursor
    if (active != "")
        pos[active] := CursorPos()
    active := dev

    if zone.Has(dev) {
        z := zone[dev]
        p := pos.Has(dev) ? pos[dev] : [(z[1] + z[3]) // 2, (z[2] + z[4]) // 2]
        Clip(z)
        DllCall("SetCursorPos", "int", p[1], "int", p[2])
    } else {
        DllCall("ClipCursor", "ptr", 0)     ; unassigned mouse roams freely
    }
}

^!m:: {
    global active
    PMA()
    if (lastDev = "" || lastDev = "(none)") {
        Tip("Move the mouse you want to assign first")
        return
    }
    p := CursorPos()
    z := MonitorRect(p[1], p[2])
    zone[lastDev] := z
    pos[lastDev] := p
    IniWrite(z[1] "," z[2] "," z[3] "," z[4], INI, "zones", lastDev)
    active := lastDev
    Clip(z)
    Tip("This mouse now owns the screen at " z[1] "," z[2] " (" z[3] - z[1] "x" z[4] - z[2] ")")
}

^!u:: {
    if zone.Has(lastDev) {
        zone.Delete(lastDev)
        try IniDelete(INI, "zones", lastDev)
    }
    DllCall("ClipCursor", "ptr", 0)
    Tip("Mouse unassigned - it roams freely")
}

^!p:: {
    global enabled
    enabled := !enabled
    if !enabled
        DllCall("ClipCursor", "ptr", 0)
    Tip(enabled ? "Mouse Zones ON" : "Mouse Zones PAUSED")
}

^!q:: ExitApp

OnMoveSize(hHook, event, hwnd, idObject, idChild, thread, time) {
    if idObject != 0
        return
    PMA()
    r := FrameRect(hwnd)
    if !r
        return
    if (event = 0x000A) {               ; drag started
        dragStart[hwnd] := r
        return
    }
    if !dragStart.Has(hwnd)
        return
    s := dragStart[hwnd]
    dragStart.Delete(hwnd)
    if !enabled
        return
    if (r[3] - r[1] != s[3] - s[1] || r[4] - r[2] != s[4] - s[2])   ; a resize, not a move
        return
    SetTimer(() => SlideToOtherScreen(hwnd, s), -60)   ; let Windows finish the drop (Snap etc.)
}

SlideToOtherScreen(hwnd, s) {
    PMA()
    mm := 1
    try mm := WinGetMinMax(hwnd)
    if mm != 0                          ; maximized/minimized (e.g. snapped to top)
        return
    r := FrameRect(hwnd)
    if !r
        return
    w := r[3] - r[1], h := r[4] - r[2]
    area := w * h
    if area <= 0
        return
    src := BestMonitor(s)               ; the screen the window started on
    if !src || Overlap(r, MonRect(src)) / area > 0.5
        return                          ; still mostly on its own screen
    best := 0, bestA := 0
    loop MonitorGetCount() {
        if A_Index = src
            continue
        a := Overlap(r, MonRect(A_Index))
        if a > bestA
            best := A_Index, bestA := a
    }
    if !best
        return
    MonitorGetWorkArea(best, &L, &T, &R, &B)
    nx := Max(L, Min(r[1], R - w))
    ny := Max(T, Min(r[2], B - h))
    wr := Buffer(16, 0)
    DllCall("GetWindowRect", "ptr", hwnd, "ptr", wr)
    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0
        , "int", NumGet(wr, 0, "int") + nx - r[1], "int", NumGet(wr, 4, "int") + ny - r[2]
        , "int", 0, "int", 0, "uint", 0x15)   ; NOSIZE|NOZORDER|NOACTIVATE
}

FrameRect(hwnd) {
    rc := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", rc, "uint", 16) != 0
        if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc)
            return 0
    return [NumGet(rc, 0, "int"), NumGet(rc, 4, "int"), NumGet(rc, 8, "int"), NumGet(rc, 12, "int")]
}

MonRect(i) {
    MonitorGet(i, &L, &T, &R, &B)
    return [L, T, R, B]
}

BestMonitor(r) {
    best := 0, bestA := 0
    loop MonitorGetCount() {
        a := Overlap(r, MonRect(A_Index))
        if a > bestA
            best := A_Index, bestA := a
    }
    return best
}

Overlap(a, b) => Max(0, Min(a[3], b[3]) - Max(a[1], b[1])) * Max(0, Min(a[4], b[4]) - Max(a[2], b[2]))

LoadZones() {
    if !FileExist(INI)
        return
    for line in StrSplit(IniRead(INI, "zones", , ""), "`n", "`r") {
        eq := InStr(line, "=", , -1)
        if !eq
            continue
        r := StrSplit(SubStr(line, eq + 1), ",")
        if r.Length = 4
            zone[SubStr(line, 1, eq - 1)] := [Integer(r[1]), Integer(r[2]), Integer(r[3]), Integer(r[4])]
    }
}

DevName(hDev) {
    if names.Has(hDev)
        return names[hDev]
    n := 0
    DllCall("GetRawInputDeviceInfo", "ptr", hDev, "uint", 0x20000007, "ptr", 0, "uint*", &n)
    buf := Buffer(n * 2 + 2, 0)
    DllCall("GetRawInputDeviceInfo", "ptr", hDev, "uint", 0x20000007, "ptr", buf, "uint*", &n)
    ; Key by hardware id only (\\?\HID#VID_..&PID_..&COL01), dropping the instance part,
    ; so a mouse keeps its screen after a Bluetooth reconnect or a different USB port.
    parts := StrSplit(StrGet(buf), "#")
    name := parts.Length >= 2 ? parts[1] "#" parts[2] : parts[1]
    name := StrUpper(StrReplace(name, "=", "_"))
    names[hDev] := name
    return name
}

CursorPos() {
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    return [NumGet(pt, 0, "int"), NumGet(pt, 4, "int")]
}

MonitorRect(x, y) {
    hMon := DllCall("MonitorFromPoint", "int64", (y << 32) | (x & 0xFFFFFFFF), "uint", 2, "ptr")
    mi := Buffer(40, 0)
    NumPut("uint", 40, mi)
    DllCall("GetMonitorInfo", "ptr", hMon, "ptr", mi)
    return [NumGet(mi, 4, "int"), NumGet(mi, 8, "int"), NumGet(mi, 12, "int"), NumGet(mi, 16, "int")]
}

Clip(z) {
    r := Buffer(16, 0)
    NumPut("int", z[1], "int", z[2], "int", z[3], "int", z[4], r)
    DllCall("ClipCursor", "ptr", r)
}

PMA() => DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")   ; real pixels on mixed-DPI screens

Tip(t) {
    ToolTip t
    SetTimer () => ToolTip(), -2500
}
