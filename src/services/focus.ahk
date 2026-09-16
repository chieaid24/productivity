; Focus Switcher: Ctrl+Alt+Left/Right moves focus to the most recently used
; window on the adjacent monitor. Ported verbatim from focus-switcher's
; FocusSwitcher.ahk; only configuration reads and names changed.

global FS_MenuRef := 0

FS_Init() {
    CoordMode "Mouse", "Screen"
    if SuiteServiceEnabled("FocusSwitcher")
        FS_Enable()
}

FS_HotkeyLeft() {
    return Cfg("FocusSwitcher", "HotkeyLeft", "^!Left")
}

FS_HotkeyRight() {
    return Cfg("FocusSwitcher", "HotkeyRight", "^!Right")
}

FS_Enable() {
    try {
        Hotkey(FS_HotkeyLeft(), FS_SwitchLeft, "On")
        Hotkey(FS_HotkeyRight(), FS_SwitchRight, "On")
    } catch {
        try Hotkey(FS_HotkeyLeft(), "Off")
        try Hotkey(FS_HotkeyRight(), "Off")
        FS_Notify("The configured shortcuts could not be registered.")
        return false
    }
    return true
}

FS_Disable() {
    try Hotkey(FS_HotkeyLeft(), "Off")
    try Hotkey(FS_HotkeyRight(), "Off")
}

FS_BuildMenu(m) {
    global FS_MenuRef := m
    hint := "Hotkeys: " HotkeyLabel(FS_HotkeyLeft()) " / " HotkeyLabel(FS_HotkeyRight())
    m.Add(hint, (*) => "")
    m.Disable(hint)
    m.Add()
    m.Add("Enabled", (*) => SuiteToggleService("FocusSwitcher"))
    if SuiteServiceEnabled("FocusSwitcher")
        m.Check("Enabled")
    m.Add()
    m.Add("Diagnostics", FS_ShowDiagnostics)
    m.Add("Settings...", (*) => SuiteOpenConfig())
}

FS_SetEnabled(on) {
    if on
        FS_Enable()
    else
        FS_Disable()
    if FS_MenuRef {
        if on
            FS_MenuRef.Check("Enabled")
        else
            FS_MenuRef.Uncheck("Enabled")
    }
}

FS_ShowDiagnostics(*) {
    try monitors := FS_GetMonitors()
    catch {
        FS_Notify("Windows could not read the current display layout.")
        return
    }
    message := "Focus Switcher diagnostics`n`n"
        . "Monitor count: " . monitors.Length . "`n"
        . "Left hotkey: " . FS_HotkeyLeft() . "`n"
        . "Right hotkey: " . FS_HotkeyRight() . "`n"
        . "Move mouse: " . (CfgBool("FocusSwitcher", "MoveMouse") ? "true" : "false") . "`n"
        . "Wrap monitors: " . (CfgBool("FocusSwitcher", "WrapMonitors", true) ? "true" : "false")
    MsgBox(message, "Focus Switcher")
}

FS_SwitchLeft(*) {
    FS_SwitchFocus(-1)
}

FS_SwitchRight(*) {
    FS_SwitchFocus(1)
}

FS_SwitchFocus(direction) {
    moveMouse := CfgBool("FocusSwitcher", "MoveMouse")
    wrapMonitors := CfgBool("FocusSwitcher", "WrapMonitors", true)

    try monitors := FS_GetMonitors()
    catch {
        FS_Notify("Windows could not read the current display layout.")
        return
    }
    if (monitors.Length < 2) {
        FS_Notify("No second monitor is available.")
        return
    }

    sourceMonitor := FS_GetSourceMonitor(monitors)
    if !sourceMonitor {
        FS_Notify("The current monitor could not be determined.")
        return
    }

    targetMonitor := FS_SelectTargetMonitor(monitors, sourceMonitor, direction, wrapMonitors)
    if !targetMonitor {
        FS_Notify("No monitor is available in that direction.")
        return
    }

    targetWindow := FS_FindTargetWindow(targetMonitor, monitors)
    if targetWindow {
        if FS_ActivateWindow(targetWindow) {
            if moveMouse
                FS_MoveMouseToWindow(targetWindow)
            return
        }

        if moveMouse
            FS_MoveMouseToMonitor(targetMonitor)
        FS_Notify("Windows prevented the target window from receiving focus.")
        return
    }

    if moveMouse
        FS_MoveMouseToMonitor(targetMonitor)
    FS_Notify("No eligible window is open on the target monitor.")
}

FS_GetMonitors() {
    monitors := []
    count := MonitorGetCount()

    Loop count {
        index := A_Index
        MonitorGet(index, &left, &top, &right, &bottom)
        MonitorGetWorkArea(index, &workLeft, &workTop, &workRight, &workBottom)
        monitors.Push(Map(
            "id", index,
            "left", left,
            "top", top,
            "right", right,
            "bottom", bottom,
            "workLeft", workLeft,
            "workTop", workTop,
            "workRight", workRight,
            "workBottom", workBottom,
            "centerX", (left + right) / 2,
            "centerY", (top + bottom) / 2
        ))
    }

    return FS_SortMonitors(monitors)
}

FS_SortMonitors(monitors) {
    sorted := []
    for monitor in monitors {
        insertAt := sorted.Length + 1
        Loop sorted.Length {
            if FS_MonitorComesBefore(monitor, sorted[A_Index]) {
                insertAt := A_Index
                break
            }
        }
        sorted.InsertAt(insertAt, monitor)
    }
    return sorted
}

FS_MonitorComesBefore(first, second) {
    if (first["centerX"] != second["centerX"])
        return first["centerX"] < second["centerX"]
    if (first["centerY"] != second["centerY"])
        return first["centerY"] < second["centerY"]
    return first["id"] < second["id"]
}

FS_GetSourceMonitor(monitors) {
    activeWindow := WinExist("A")
    if activeWindow {
        rect := FS_GetWindowRect(activeWindow, false)
        if rect {
            monitor := FS_FindMonitorForRect(monitors, rect)
            if monitor
                return monitor
        }
    }

    MouseGetPos(&mouseX, &mouseY)
    return FS_FindMonitorForPoint(monitors, mouseX, mouseY)
}

FS_SelectTargetMonitor(monitors, source, direction, wrap) {
    best := 0
    bestHorizontalDistance := 0
    bestVerticalDistance := 0

    ; First choose the nearest screen whose center lies in the requested
    ; horizontal direction. Vertical distance breaks ties for stacked screens.
    for monitor in monitors {
        if (monitor["id"] = source["id"])
            continue

        horizontalDelta := monitor["centerX"] - source["centerX"]
        if (horizontalDelta * direction <= 0)
            continue

        horizontalDistance := Abs(horizontalDelta)
        verticalDistance := Abs(monitor["centerY"] - source["centerY"])
        if !best
            || (horizontalDistance < bestHorizontalDistance)
            || (horizontalDistance = bestHorizontalDistance && verticalDistance < bestVerticalDistance)
            || (horizontalDistance = bestHorizontalDistance && verticalDistance = bestVerticalDistance
                && FS_MonitorComesBefore(monitor, best)) {
            best := monitor
            bestHorizontalDistance := horizontalDistance
            bestVerticalDistance := verticalDistance
        }
    }

    if best || !wrap
        return best

    ; Wrap to the opposite horizontal edge. If every screen has the same
    ; horizontal center, choose the vertically nearest screen deterministically.
    allSameHorizontalCenter := true
    for monitor in monitors {
        if (monitor["centerX"] != source["centerX"]) {
            allSameHorizontalCenter := false
            break
        }
    }

    if allSameHorizontalCenter {
        for monitor in monitors {
            if (monitor["id"] = source["id"])
                continue
            verticalDistance := Abs(monitor["centerY"] - source["centerY"])
            if !best || verticalDistance < bestVerticalDistance
                || (verticalDistance = bestVerticalDistance && FS_MonitorComesBefore(monitor, best)) {
                best := monitor
                bestVerticalDistance := verticalDistance
            }
        }
        return best
    }

    hasExtreme := false
    extremeX := 0
    for monitor in monitors {
        if !hasExtreme
            || (direction > 0 && monitor["centerX"] < extremeX)
            || (direction < 0 && monitor["centerX"] > extremeX) {
            extremeX := monitor["centerX"]
            hasExtreme := true
        }
    }

    for monitor in monitors {
        if (monitor["id"] = source["id"] || monitor["centerX"] != extremeX)
            continue
        verticalDistance := Abs(monitor["centerY"] - source["centerY"])
        if !best || verticalDistance < bestVerticalDistance
            || (verticalDistance = bestVerticalDistance && FS_MonitorComesBefore(monitor, best)) {
            best := monitor
            bestVerticalDistance := verticalDistance
        }
    }
    return best
}

FS_FindTargetWindow(targetMonitor, monitors) {
    minimizedFallback := 0

    ; WinGetList returns windows from topmost to bottommost. This makes the
    ; first eligible window the best available approximation of recent focus.
    for hwnd in WinGetList() {
        isMinimized := false
        try isMinimized := WinGetMinMax("ahk_id " . hwnd) = -1
        catch
            continue

        rect := FS_GetWindowRect(hwnd, isMinimized)
        if !rect || !FS_IsEligibleWindow(hwnd, rect)
            continue

        windowMonitor := FS_FindMonitorForRect(monitors, rect)
        if !windowMonitor || windowMonitor["id"] != targetMonitor["id"]
            continue

        if isMinimized {
            if !minimizedFallback
                minimizedFallback := hwnd
            continue
        }
        return hwnd
    }

    return minimizedFallback
}

FS_IsEligibleWindow(hwnd, rect) {
    static blockedClasses := Map(
        "Progman", true,
        "WorkerW", true,
        "Shell_TrayWnd", true,
        "Shell_SecondaryTrayWnd", true,
        "DV2ControlHost", true,
        "MultitaskingViewFrame", true
    )
    if (hwnd = A_ScriptHwnd)
        return false
    if !DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
        return false
    if FS_IsWindowCloaked(hwnd)
        return false

    width := rect["right"] - rect["left"]
    height := rect["bottom"] - rect["top"]
    if (width < 120 || height < 80)
        return false

    selector := "ahk_id " . hwnd
    try className := WinGetClass(selector)
    catch
        return false
    if blockedClasses.Has(className) || InStr(StrLower(className), "tooltip")
        return false

    try processId := WinGetPID(selector)
    catch
        return false
    if (processId = ProcessExist())
        return false

    try {
        style := WinGetStyle(selector)
        extendedStyle := WinGetExStyle(selector)
    } catch {
        return false
    }

    ; Child windows and WS_EX_TOOLWINDOW surfaces are not normal app windows.
    if (style & 0x40000000) || (extendedStyle & 0x00000080)
        return false
    return true
}

FS_IsWindowCloaked(hwnd) {
    cloaked := 0
    try {
        result := DllCall(
            "dwmapi\DwmGetWindowAttribute",
            "Ptr", hwnd,
            "UInt", 14,
            "UInt*", &cloaked,
            "UInt", 4,
            "Int"
        )
        return result = 0 && cloaked != 0
    } catch {
        return false
    }
}

FS_GetWindowRect(hwnd, useNormalPosition) {
    if useNormalPosition {
        placementRect := FS_GetWindowPlacementRect(hwnd)
        if placementRect
            return placementRect
    }

    ; DWM extended frame bounds avoid invisible resize borders and align with
    ; physical monitor coordinates more reliably across mixed DPI displays.
    bounds := Buffer(16, 0)
    try {
        result := DllCall(
            "dwmapi\DwmGetWindowAttribute",
            "Ptr", hwnd,
            "UInt", 9,
            "Ptr", bounds.Ptr,
            "UInt", bounds.Size,
            "Int"
        )
        if (result = 0) {
            return Map(
                "left", NumGet(bounds, 0, "Int"),
                "top", NumGet(bounds, 4, "Int"),
                "right", NumGet(bounds, 8, "Int"),
                "bottom", NumGet(bounds, 12, "Int")
            )
        }
    }

    try {
        WinGetPos(&x, &y, &width, &height, "ahk_id " . hwnd)
        return Map(
            "left", x,
            "top", y,
            "right", x + width,
            "bottom", y + height
        )
    } catch {
        return 0
    }
}

FS_GetWindowPlacementRect(hwnd) {
    ; WINDOWPLACEMENT stores the restored rectangle at byte offset 28.
    placement := Buffer(44, 0)
    NumPut("UInt", placement.Size, placement, 0)
    try {
        if !DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", placement.Ptr, "Int")
            return 0
        return Map(
            "left", NumGet(placement, 28, "Int"),
            "top", NumGet(placement, 32, "Int"),
            "right", NumGet(placement, 36, "Int"),
            "bottom", NumGet(placement, 40, "Int")
        )
    } catch {
        return 0
    }
}

FS_FindMonitorForRect(monitors, rect) {
    bestMonitor := 0
    bestArea := -1

    for monitor in monitors {
        width := Max(0, Min(rect["right"], monitor["right"])
            - Max(rect["left"], monitor["left"]))
        height := Max(0, Min(rect["bottom"], monitor["bottom"])
            - Max(rect["top"], monitor["top"]))
        area := width * height
        if (area > bestArea) {
            bestArea := area
            bestMonitor := monitor
        }
    }

    if (bestArea > 0)
        return bestMonitor

    centerX := (rect["left"] + rect["right"]) / 2
    centerY := (rect["top"] + rect["bottom"]) / 2
    return FS_FindNearestMonitor(monitors, centerX, centerY)
}

FS_FindMonitorForPoint(monitors, x, y) {
    for monitor in monitors {
        if (x >= monitor["left"] && x < monitor["right"]
            && y >= monitor["top"] && y < monitor["bottom"])
            return monitor
    }
    return FS_FindNearestMonitor(monitors, x, y)
}

FS_FindNearestMonitor(monitors, x, y) {
    best := 0
    bestDistance := 0
    for monitor in monitors {
        deltaX := monitor["centerX"] - x
        deltaY := monitor["centerY"] - y
        distance := deltaX * deltaX + deltaY * deltaY
        if !best || distance < bestDistance {
            best := monitor
            bestDistance := distance
        }
    }
    return best
}

FS_ActivateWindow(hwnd) {
    selector := "ahk_id " . hwnd
    try {
        if (WinGetMinMax(selector) = -1)
            WinRestore(selector)
        WinActivate(selector)
        return WinWaitActive(selector, , 0.75) != 0
    } catch {
        return false
    }
}

FS_MoveMouseToWindow(hwnd) {
    rect := FS_GetWindowRect(hwnd, false)
    if !rect
        return
    x := Round((rect["left"] + rect["right"]) / 2)
    y := Round((rect["top"] + rect["bottom"]) / 2)
    MouseMove(x, y, 0)
}

FS_MoveMouseToMonitor(monitor) {
    x := Round((monitor["workLeft"] + monitor["workRight"]) / 2)
    y := Round((monitor["workTop"] + monitor["workBottom"]) / 2)
    MouseMove(x, y, 0)
}

FS_Notify(message) {
    TrayTip(message, "Focus Switcher", 0x1)
}
