; Mouse Zones - give each physical mouse its own screen.
; One Windows cursor, but each mouse remembers its own spot and stays on its own screen.
;
;   Ctrl+Alt+M  move a mouse onto a screen, then press: that mouse now owns that screen
;   Ctrl+Alt+U  unassign the mouse you moved last (it roams freely again)
;   Ctrl+Alt+F  the device you moved last is a trackpad: no own spot, follows the last mouse (toggle)
;   Ctrl+Alt+P  pause / resume
;   Ctrl+Alt+Q  quit
; Trackpad profiles (tray menu, or right-click the desktop -> Trackpad profile):
;   1 = the trackpad is the USB mouse (shares its spot)   2 = follows the latest mouse
;   3 = stays on its own screens (ini trackpadScreens), crossing from one to the next at the side edge
; Assignments are saved in mouse-zones.ini next to this script.
; Args: /trackpad1 /trackpad2 /trackpad3 = switch the running copy's profile.

#Requires AutoHotkey v2.0
#SingleInstance Off
Persistent

global INI := A_ScriptDir "\mouse-zones.ini"
global MSG_CMD := 0x5C58
global PROFILES := ["1. Default: follow the USB mouse", "2. Follow the latest mouse", "3. Screens 3 + 4 only"]
global RKEY := "HKCU\Software\Classes\DesktopBackground\Shell\0MouseZones"

; ---- one copy only; the right-click menu passes /trackpadN to the running one ----
global SWAPLABEL := '4. Swap: USB mouse on the 27", Bluetooth free'
global reqProfile := 0                  ; 1-3 = trackpad profile, 4 = toggle the mouse swap
if (A_Args.Length && RegExMatch(A_Args[1], "i)^/(?:trackpad([123])|(swap))$", &m))
    reqProfile := m[1] != "" ? Integer(m[1]) : 4
DetectHiddenWindows(true)
for hw in WinGetList(A_ScriptFullPath " ahk_class AutoHotkey") {
    if (hw = A_ScriptHwnd)
        continue
    if reqProfile {
        PostMessage(MSG_CMD, reqProfile, 0, , hw)
        ExitApp
    }
    WinClose(hw)                        ; plain start = replace the old copy
    WinWaitClose(hw, , 3)
}
DetectHiddenWindows(false)
if (reqProfile = 4)
    IniWrite(IniRead(INI, "settings", "swap", 0) = 1 ? 0 : 1, INI, "settings", "swap")
else if reqProfile
    IniWrite(reqProfile, INI, "settings", "trackpad")
global zone := Map()      ; device name -> [L, T, R, B]
global pos := Map()       ; device name -> [x, y] last cursor spot of that mouse
global names := Map()     ; raw handle -> device name (cache)
global active := ""       ; device name that owns the cursor now
global lastDev := ""      ; device name that moved last
global enabled := true
global follow := Map("(none)", 1)   ; trackpads: follow the last mouse (ini [followers])
global followerOn := false          ; the trackpad moved since the last real-mouse event
global lastFree := ""               ; last mouse with no screen of its own (the USB mouse)
global tpProfile := 1
global tpScreens := []              ; profile 3: the trackpad's screens, left to right
global ownerT := 0                  ; time of the last event from whatever is driving the cursor
global baseZone := Map()            ; zones as saved; `zone` = after the swap
global swapOn := false, swapA := "", swapB := ""   ; swap: A (normally zoned) <-> B (normally free)
global cycleState := 0, cyclePrevProfile := 1, cyclePrevSwap := false   ; trackpad 4-click cycle

LoadZones()
LoadSettings()
EnsureMenu()
OnMessage(MSG_CMD, (w, *) => (SetTimer(() => (w = 4 ? ToggleSwap() : SetProfile(w)), -1), 1))

; Listen to all mice, even when this script has no focus (RIDEV_INPUTSINK).
rid := Buffer(8 + A_PtrSize, 0)
NumPut("ushort", 1, "ushort", 2, "uint", 0x100, "ptr", A_ScriptHwnd, rid)
if !DllCall("RegisterRawInputDevices", "ptr", rid, "uint", 1, "uint", rid.Size)
    MsgBox "Could not register for raw mouse input."
OnMessage(0x00FF, OnRawInput)
OnExit((*) => (DllCall("ClipCursor", "ptr", 0), 0))   ; must return 0: non-zero cancels the exit

; Window drag: when a window is dropped with 50%+ of it off its screen,
; move it fully onto the screen it was dragged toward.
global dragStart := Map()
global moveHook := CallbackCreate(OnMoveSize, , 7)
DllCall("SetWinEventHook", "uint", 0x000A, "uint", 0x000B, "ptr", 0, "ptr", moveHook
    , "uint", 0, "uint", 0, "uint", 0, "ptr")   ; MOVESIZESTART..MOVESIZEEND, out of context

A_IconTip := "Mouse Zones (Ctrl+Alt+M assign, Ctrl+Alt+P pause)"
Tip("Mouse Zones running - " zone.Count " mouse(s) assigned - trackpad " PROFILES[tpProfile])

OnRawInput(wParam, lParam, msg, hwnd) {
    global active, lastDev, followerOn, lastFree, ownerT
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
    flags := NumGet(buf, hdr, "ushort")
    dx := (flags & 1) ? 0 : NumGet(buf, hdr + 12, "int")   ; MOUSE_MOVE_ABSOLUTE has no delta
    dy := (flags & 1) ? 0 : NumGet(buf, hdr + 16, "int")
    btn := NumGet(buf, hdr + 4, "ushort")                   ; button / wheel flags
    if (!btn && !dx && !dy && !(flags & 1))
        return                              ; empty report (some Bluetooth mice send these when idle)
    ; No device handle = the precision trackpad (or injected input). Touch / pen carry the
    ; 0xFF5157xx signature: that's a touch screen, leave it alone.
    if (dev = "(none)" && (NumGet(buf, hdr + 20, "uint") & 0xFFFFFF00) = 0xFF515700)
        return
    lastDev := dev
    if !enabled
        return

    if (follow.Has(dev) && (btn & 1))       ; trackpad left click / tap (RI_MOUSE_LEFT_BUTTON_DOWN)
        CountClick()

    if follow.Has(dev) {
        if (tpProfile = 3) {
            Drive(dev, tpScreens, dx, dy, btn)   ; own screens, own spot
            return
        }
        if (tpProfile = 1 && lastFree != "" && !zone.Has(lastFree)) {
            Drive(lastFree, [], dx, dy, btn)     ; acts as the USB mouse
            return
        }
        ownerT := A_TickCount                    ; the trackpad is what's moving now
        ; profile 2: no spot of its own. Carries on from wherever the last mouse
        ; left the cursor, goes anywhere, and counts as part of that mouse.
        if !followerOn {
            followerOn := true
            if (active != "") {
                p := CursorPos()            ; the mouse's spot before the trackpad moved it
                pos[active] := p
                try IniWrite(p[1] "," p[2], INI, "pos", active)
            }
            Log("trackpad " Short(dev) " starts at the spot of " Short(active))
        }
        DllCall("ClipCursor", "ptr", 0)
        return
    }

    Drive(dev, AreaOf(dev), dx, dy, btn)
}

; dev takes (or keeps) the cursor. area = the screens it may use, left to right ([] = anywhere).
Drive(dev, area, dx, dy := 0, btn := 1) {
    global active, followerOn, lastFree, ownerT
    static accX := Map(), accY := Map(), accN := Map(), accT := Map()
    if (dev != active || followerOn) {
        ; Take over only on a real move in one direction, or a click / scroll. A mouse lying
        ; still sends jitter (+1/-1, fast on 1000 Hz receivers): it cancels out in the sum.
        ; Need more while another device is moving right now.
        if (!accT.Has(dev) || A_TickCount - accT[dev] > 250)
            accX[dev] := 0, accY[dev] := 0, accN[dev] := 0
        accT[dev] := A_TickCount
        accX[dev] += dx, accY[dev] += dy, accN[dev] += 1
        need := (A_TickCount - ownerT < 150) ? 40 : 12
        if (!btn && (Abs(accX[dev]) + Abs(accY[dev]) < need || accN[dev] < 3))
            return
        accX[dev] := 0, accY[dev] := 0, accN[dev] := 0
    }
    ownerT := A_TickCount
    if !zone.Has(dev) && !follow.Has(dev)
        lastFree := dev
    cur := CursorPos()
    target := 0
    if (dev != active) {
        ; remember where the old device left the cursor. After trackpad use (profile 2) its
        ; spot was already saved when the trackpad started: the trackpad never changes it.
        if (active != "" && !followerOn) {
            pos[active] := cur
            try IniWrite(cur[1] "," cur[2], INI, "pos", active)   ; survives a restart
        }
        Log("switch " Short(active) " -> " Short(dev) "  left " cur[1] "," cur[2]
            "  goto " (pos.Has(dev) ? pos[dev][1] "," pos[dev][2] : "-"))
        active := dev
        try IniWrite(dev, INI, "state", "active")
        if pos.Has(dev)
            target := pos[dev]
        else if area.Length
            target := Center(area[1])
    } else if followerOn {                  ; same mouse again after the trackpad: its own spot
        if pos.Has(dev)
            target := pos[dev]
        else if area.Length
            target := Center(area[1])
        Log("back to " Short(dev) " after trackpad  goto " (target ? target[1] "," target[2] : "-"))
    }
    followerOn := false

    if !area.Length {
        DllCall("ClipCursor", "ptr", 0)     ; free device: goes anywhere, keeps its own spot
        if target
            SetCur(target)
        return
    }
    p := target ? target : cur
    i := AreaIndex(area, p)
    if !i {
        i := 1
        target := p
    } else if (!target && area.Length > 1 && dx) {
        j := EdgeJump(area, i, p, dx)       ; pushed past the side edge -> next screen
        if j {
            i := j[1]
            target := j[2]
        }
    }
    Clip(area[i])                           ; also re-set: Windows drops it on some focus changes
    if target
        SetCur(ClampTo(target, area[i]))
}

AreaOf(d) {
    if follow.Has(d)
        return tpProfile = 3 ? tpScreens : []
    return zone.Has(d) ? [zone[d]] : []
}

AreaIndex(area, p) {
    for i, z in area
        if InZone(p, z)
            return i
    return 0
}

InArea(area, p) => !area.Length || AreaIndex(area, p) > 0

EdgeJump(area, i, p, dx) {
    z := area[i]
    if (dx > 0 && p[1] >= z[3] - 1 && i < area.Length) {
        n := area[i + 1]
        return [i + 1, [n[1], MapY(p[2], z, n)]]
    }
    if (dx < 0 && p[1] <= z[1] && i > 1) {
        n := area[i - 1]
        return [i - 1, [n[3] - 1, MapY(p[2], z, n)]]
    }
    return 0
}

MapY(y, a, b) => b[2] + Round((y - a[2]) * (b[4] - b[2]) / (a[4] - a[2]))

; 4 trackpad clicks/taps in a row (each within 0.45 s): step through the cycle
;   1st: trackpad profile 3   2nd: + mouse swap on   3rd: back to how it was before
CountClick() {
    static n := 0, t := 0
    n := (A_TickCount - t < 450) ? n + 1 : 1
    t := A_TickCount
    if (n >= 4) {
        n := 0
        SetTimer(QuadClick, -1)
    }
}

QuadClick() {
    global cycleState, cyclePrevProfile, cyclePrevSwap
    if (cycleState = 0) {
        cyclePrevProfile := tpProfile, cyclePrevSwap := swapOn
        SetProfile(3, true)
        cycleState := 1
        Tip("4 clicks: trackpad " PROFILES[3] "`n4 clicks again: + mouse swap")
    } else if (cycleState = 1) {
        if !swapOn
            ToggleSwap(true)
        cycleState := 2
        Tip("4 clicks: " SWAPLABEL "`n4 clicks again: back to normal")
    } else {
        SetProfile(cyclePrevProfile, true)
        if (swapOn != cyclePrevSwap)
            ToggleSwap(true)
        cycleState := 0
        Tip("4 clicks: back to normal - trackpad " PROFILES[tpProfile] (swapOn ? ", swap on" : ""))
    }
    Log("4-click cycle -> step " cycleState)
}

SetProfile(n, fromCycle := false) {
    global tpProfile, active, followerOn, cycleState
    if (n < 1 || n > 3)
        return
    if !fromCycle
        cycleState := 0                     ; a manual choice ends the 4-click cycle
    tpProfile := n
    IniWrite(n, INI, "settings", "trackpad")
    if follow.Has(active)
        active := ""
    followerOn := false
    DllCall("ClipCursor", "ptr", 0)
    UpdateMenus()
    Tip("Trackpad: " PROFILES[n])
}

LoadSettings() {
    global tpProfile, tpScreens
    tpProfile := Integer(IniRead(INI, "settings", "trackpad", 1))
    if (tpProfile < 1 || tpProfile > 3)
        tpProfile := 1
    tpScreens := []
    for s in StrSplit(IniRead(INI, "settings", "trackpadScreens", ""), "|") {
        r := StrSplit(s, ",")
        if r.Length = 4
            tpScreens.Push([Integer(r[1]), Integer(r[2]), Integer(r[3]), Integer(r[4])])
    }
    ; left to right, for the edge crossing
    loop tpScreens.Length - 1
        loop tpScreens.Length - A_Index
            if tpScreens[A_Index][1] > tpScreens[A_Index + 1][1] {
                t := tpScreens[A_Index], tpScreens[A_Index] := tpScreens[A_Index + 1], tpScreens[A_Index + 1] := t
            }
    global swapOn := IniRead(INI, "settings", "swap", 0) = 1
    global swapA := IniRead(INI, "settings", "swapA", "")
    global swapB := IniRead(INI, "settings", "swapB", "")
    ApplySwap()
}

; zone = baseZone with the screens of swapA and swapB exchanged while the swap is on.
ApplySwap() {
    global zone := baseZone.Clone()
    if !(swapOn && swapA != "" && swapB != "")
        return
    za := baseZone.Has(swapA) ? baseZone[swapA] : 0
    zb := baseZone.Has(swapB) ? baseZone[swapB] : 0
    for d, z in Map(swapA, zb, swapB, za) {
        if z
            zone[d] := z
        else if zone.Has(d)
            zone.Delete(d)
    }
}

ToggleSwap(fromCycle := false) {
    global swapOn, active, followerOn, lastFree, cycleState
    if !fromCycle
        cycleState := 0
    if (swapA = "" || swapB = "") {
        Tip("Swap: set swapA / swapB in mouse-zones.ini first")
        return
    }
    swapOn := !swapOn
    IniWrite(swapOn ? 1 : 0, INI, "settings", "swap")
    ; the two mice trade spots too, so the mouse that gets the screen starts where the other was
    pa := pos.Has(swapA) ? pos[swapA] : 0, pb := pos.Has(swapB) ? pos[swapB] : 0
    for d, p in Map(swapA, pb, swapB, pa) {
        if p {
            pos[d] := p
            try IniWrite(p[1] "," p[2], INI, "pos", d)
        } else if pos.Has(d)
            pos.Delete(d)
    }
    ApplySwap()
    lastFree := zone.Has(swapA) ? swapB : swapA    ; the free mouse (trackpad profile 1 follows it)
    active := ""                                   ; next move: that mouse jumps to its spot
    followerOn := false
    DllCall("ClipCursor", "ptr", 0)
    UpdateMenus()
    Log("swap " (swapOn ? "ON" : "OFF"))
    Tip(swapOn ? 'Swapped: USB mouse on the 27", Bluetooth free' : 'Normal: Bluetooth mouse on the 27", USB free')
}

; Desktop right-click menu "Trackpad profile" (sorts right after 0ClipStack) + tray menu.
EnsureMenu() {
    cmd := '"' A_AhkPath '" "' A_ScriptFullPath '" /trackpad'
    try {
        RegWrite("Trackpad profile", "REG_SZ", RKEY, "MUIVerb")
        RegWrite("", "REG_SZ", RKEY, "SubCommands")
        RegWrite("C:\Windows\System32\main.cpl,0", "REG_SZ", RKEY, "Icon")
        RegWrite("Top", "REG_SZ", RKEY, "Position")
        for i, label in PROFILES
            RegWrite(cmd i, "REG_SZ", RKEY "\shell\" i "profile\command")
        RegWrite('"' A_AhkPath '" "' A_ScriptFullPath '" /swap', "REG_SZ", RKEY "\shell\4profile\command")
    }
    A_TrayMenu.Add()
    for i, label in PROFILES
        A_TrayMenu.Add("Trackpad " label, ((n, *) => SetProfile(n)).Bind(i))
    A_TrayMenu.Add(SWAPLABEL, (*) => ToggleSwap())
    UpdateMenus()
}

UpdateMenus() {
    for i, label in PROFILES {
        try RegWrite((i = tpProfile ? "● " : "") label, "REG_SZ", RKEY "\shell\" i "profile", "MUIVerb")
        try (i = tpProfile) ? A_TrayMenu.Check("Trackpad " label) : A_TrayMenu.Uncheck("Trackpad " label)
    }
    try RegWrite((swapOn ? "● " : "") SWAPLABEL, "REG_SZ", RKEY "\shell\4profile", "MUIVerb")
    try swapOn ? A_TrayMenu.Check(SWAPLABEL) : A_TrayMenu.Uncheck(SWAPLABEL)
}

^!m:: {
    global active
    PMA()
    if (lastDev = "" || follow.Has(lastDev)) {
        Tip(lastDev = "" ? "Move the mouse you want to assign first"
            : "That's a trackpad (it follows the last mouse). Ctrl+Alt+F to make it a normal mouse")
        return
    }
    if swapOn {
        Tip("Turn the mouse swap (4) off first")
        return
    }
    p := CursorPos()
    z := MonitorRect(p[1], p[2])
    zone[lastDev] := z
    baseZone[lastDev] := z
    pos[lastDev] := p
    IniWrite(z[1] "," z[2] "," z[3] "," z[4], INI, "zones", lastDev)
    active := lastDev
    Clip(z)
    Tip("This mouse now owns the screen at " z[1] "," z[2] " (" z[3] - z[1] "x" z[4] - z[2] ")")
}

^!u:: {
    if swapOn {
        Tip("Turn the mouse swap (4) off first")
        return
    }
    if zone.Has(lastDev) {
        zone.Delete(lastDev)
        try baseZone.Delete(lastDev)
        try IniDelete(INI, "zones", lastDev)
    }
    DllCall("ClipCursor", "ptr", 0)
    Tip("Mouse unassigned - it roams freely")
}

^!f:: {
    if (lastDev = "" || lastDev = "(none)")
        return
    if follow.Has(lastDev) {
        follow.Delete(lastDev)
        try IniDelete(INI, "followers", lastDev)
        Tip("Now a normal mouse (keeps its own spot)")
    } else {
        follow[lastDev] := 1
        if zone.Has(lastDev) {
            zone.Delete(lastDev)
            try baseZone.Delete(lastDev)
            try IniDelete(INI, "zones", lastDev)
        }
        IniWrite(1, INI, "followers", lastDev)
        Tip("Now a trackpad: follows the last mouse")
    }
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
    global baseZone := zone.Clone()
    for line in StrSplit(IniRead(INI, "followers", , ""), "`n", "`r") {
        eq := InStr(line, "=", , -1)
        if eq
            follow[SubStr(line, 1, eq - 1)] := 1
    }
    for line in StrSplit(IniRead(INI, "pos", , ""), "`n", "`r") {   ; each mouse's last spot
        eq := InStr(line, "=", , -1)
        r := eq ? StrSplit(SubStr(line, eq + 1), ",") : []
        if r.Length = 2
            pos[SubStr(line, 1, eq - 1)] := [Integer(r[1]), Integer(r[2])]
    }
    global active := IniRead(INI, "state", "active", "")
}

; Short label for the log: VID:PID (or VEN) of a device key.
Short(d) => RegExMatch(d, "i)(?:VID[_&]0*|VEN_)([0-9A-F]+)(?:.*?PID[_&]([0-9A-F]+))?", &m) ? m[1] (m[2] != "" ? ":" m[2] : "") : (d = "" ? "-" : d)

Log(s) {
    static f := A_ScriptDir "\mouse-zones.log"
    try {
        if FileExist(f) && FileGetSize(f) > 200000
            FileDelete(f)
        FileAppend(FormatTime(, "HH:mm:ss") " " s "`n", f)
    }
}

InZone(p, z) => p[1] >= z[1] && p[1] < z[3] && p[2] >= z[2] && p[2] < z[4]
ClampTo(p, z) => [Max(z[1], Min(p[1], z[3] - 1)), Max(z[2], Min(p[2], z[4] - 1))]
Center(z) => [(z[1] + z[3]) // 2, (z[2] + z[4]) // 2]
SetCur(p) => DllCall("SetCursorPos", "int", p[1], "int", p[2])

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
