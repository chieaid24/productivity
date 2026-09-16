; CC Usage Tracker: Ctrl+Alt+U toggles two frameless Chrome app popups with
; the Claude and Codex usage pages, centered side by side on the monitor
; under the mouse. Ported from the C# CCUsageTracker: same Chrome discovery
; order, window detection, layout math, styles, and scoped Escape behavior.

global UT_Windows := []   ; [{hwnd, name}]
global UT_Busy := false
global UT_MenuRef := 0
global UT_SettingsGui := 0

UT_Init() {
    HotIf UT_EscActive
    Hotkey "Esc", (*) => UT_Close()
    HotIf
    if SuiteServiceEnabled("UsageTracker")
        UT_Enable()
}

UT_Hotkey() {
    return Cfg("UsageTracker", "Hotkey", "^!u")
}

UT_Enable() {
    try Hotkey(UT_Hotkey(), (*) => UT_Toggle(), "On")
    catch as err
        SuiteLog("usage: could not register hotkey: " err.Message)
}

UT_Disable() {
    try Hotkey(UT_Hotkey(), "Off")
    UT_Close()
}

UT_BuildMenu(m) {
    global UT_MenuRef := m
    hint := HotkeyLabel(UT_Hotkey())
    m.Add(hint, (*) => "")
    m.Disable(hint)
    m.Add()
    m.Add("Enabled", (*) => SuiteToggleService("UsageTracker"))
    if SuiteServiceEnabled("UsageTracker")
        m.Check("Enabled")
    m.Add()
    m.Add("Show usage", (*) => UT_Open())
    m.Add("Close usage", (*) => UT_Close())
    m.Add("Refresh usage", (*) => UT_Refresh())
    m.Add("Open full pages", (*) => UT_OpenFullPages())
    m.Add()
    m.Add("Settings...", UT_OpenSettings)
}

UT_SetEnabled(on) {
    if on
        UT_Enable()
    else
        UT_Disable()
    if UT_MenuRef {
        if on
            UT_MenuRef.Check("Enabled")
        else
            UT_MenuRef.Uncheck("Enabled")
        for item in ["Show usage", "Close usage", "Refresh usage", "Open full pages"]
            on ? UT_MenuRef.Enable(item) : UT_MenuRef.Disable(item)
    }
}

; ------------------------------------------------------------------ actions

UT_Toggle() {
    UT_RemoveStale()
    if UT_Windows.Length
        UT_Close()
    else
        UT_Open()
}

UT_Open() {
    global UT_Busy
    if UT_Busy
        return
    UT_Busy := true
    try {
        UT_RemoveStale()
        if UT_Windows.Length
            return
        chrome := UT_LocateChrome()
        if chrome = "" {
            TrayTip "Google Chrome was not found. Select chrome.exe in Settings.", "CC Usage Tracker", 0x2
            return
        }
        UT_GetMonitorArea(&waL, &waT, &waR, &waB, &dpi)
        UT_CalculateLayout(waL, waT, waR, waB, dpi, &claudeRect, &codexRect)
        topmost := CfgBool("UsageTracker", "KeepOnTop")
        try {
            claude := UT_LaunchAppWindow(chrome, Cfg("UsageTracker", "ClaudeUrl", "https://claude.ai/settings/usage"))
            UT_Windows.Push({hwnd: claude, name: "Claude"})
            UT_ApplyStyle(claude, claudeRect, topmost)
            codex := UT_LaunchAppWindow(chrome, Cfg("UsageTracker", "CodexUrl", "https://chatgpt.com/codex/settings/usage"))
            UT_Windows.Push({hwnd: codex, name: "Codex"})
            UT_ApplyStyle(codex, codexRect, topmost)
            SuiteLog("usage: opened Claude and Codex usage windows")
        } catch as err {
            UT_CloseCore()
            SuiteLog("usage: open failed: " err.Message)
            TrayTip err.Message, "CC Usage Tracker", 0x2
        }
    } finally
        UT_Busy := false
}

UT_Close() {
    global UT_Busy
    if UT_Busy
        return
    UT_Busy := true
    try UT_CloseCore()
    finally
        UT_Busy := false
}

UT_Refresh() {
    UT_Close()
    UT_Open()
}

UT_OpenFullPages() {
    Run Cfg("UsageTracker", "ClaudeUrl", "https://claude.ai/settings/usage")
    Run Cfg("UsageTracker", "CodexUrl", "https://chatgpt.com/codex/settings/usage")
}

UT_CloseCore() {
    global UT_Windows
    handles := []
    for w in UT_Windows
        if WinExist("ahk_id " w.hwnd)
            handles.Push(w.hwnd)
    for hwnd in handles
        DllCall("PostMessage", "ptr", hwnd, "uint", 0x0010, "ptr", 0, "ptr", 0)  ; WM_CLOSE
    deadline := A_TickCount + 2000
    while A_TickCount < deadline {
        alive := false
        for hwnd in handles
            if DllCall("IsWindow", "ptr", hwnd)
                alive := true
        if !alive
            break
        Sleep 50
    }
    UT_Windows := []
}

UT_RemoveStale() {
    global UT_Windows
    kept := []
    for w in UT_Windows
        if DllCall("IsWindow", "ptr", w.hwnd)
            kept.Push(w)
    UT_Windows := kept
}

UT_EscActive(*) {
    if !SuiteServiceEnabled("UsageTracker")
        return false
    UT_RemoveStale()
    if !UT_Windows.Length
        return false
    fg := DllCall("GetForegroundWindow", "ptr")
    for w in UT_Windows
        if w.hwnd = fg
            return true
    return false
}

; ------------------------------------------------------------------- chrome

; Override path first, then common install dirs, then App Paths, exactly
; like the C# ChromeLocator.
UT_LocateChrome() {
    override := Cfg("UsageTracker", "ChromeExecutable")
    if UT_IsChromeExe(override)
        return override
    candidates := [
        EnvGet("LOCALAPPDATA") "\Google\Chrome\Application\chrome.exe",
        EnvGet("ProgramFiles") "\Google\Chrome\Application\chrome.exe",
        EnvGet("ProgramFiles(x86)") "\Google\Chrome\Application\chrome.exe"
    ]
    for p in candidates
        if UT_IsChromeExe(p)
            return p
    for key in ["SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
                "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"] {
        for hive in ["HKCU", "HKLM"] {
            p := ""
            try p := RegRead(hive "\" key)
            if UT_IsChromeExe(p)
                return p
        }
    }
    return ""
}

UT_IsChromeExe(path) {
    if path = "" || !FileExist(path)
        return false
    SplitPath path, &name
    return StrLower(name) = "chrome.exe"
}

; New-window detection by diffing visible, unowned top-level chrome.exe
; windows, preferring class Chrome_WidgetWin_1. PIDs cannot identify
; Chromium windows because processes are shared.
UT_SnapshotChrome() {
    seen := Map()
    for hwnd in UT_ChromeCandidates()
        seen[hwnd.hwnd] := true
    return seen
}

UT_ChromeCandidates() {
    out := []
    for hwnd in WinGetList("ahk_exe chrome.exe") {
        if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")  ; GW_OWNER
            continue
        rect := Buffer(16, 0)
        if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rect)
            continue
        if NumGet(rect, 8, "int") <= NumGet(rect, 0, "int") || NumGet(rect, 12, "int") <= NumGet(rect, 4, "int")
            continue
        out.Push({hwnd: hwnd, preferred: WindowHasClass(hwnd, "Chrome_WidgetWin_1")})
    }
    return out
}

UT_LaunchAppWindow(chrome, url) {
    before := UT_SnapshotChrome()
    Run '"' chrome '" --app="' url '"'
    deadline := A_TickCount + 15000
    while A_TickCount < deadline {
        fallback := 0
        for cand in UT_ChromeCandidates() {
            if before.Has(cand.hwnd)
                continue
            if cand.preferred
                return cand.hwnd
            if !fallback
                fallback := cand.hwnd
        }
        if fallback
            return fallback
        Sleep 100
    }
    throw Error("Chrome opened, but its app window could not be identified.")
}

; ------------------------------------------------------------------- layout

; Work area and DPI of the monitor per [UsageTracker] MonitorSelection:
; mouse (default), foreground, or primary.
UT_GetMonitorArea(&l, &t, &r, &b, &dpi) {
    mode := StrLower(Cfg("UsageTracker", "MonitorSelection", "mouse"))
    if mode = "primary" {
        pt := 0  ; point (0,0)
        hmon := DllCall("MonitorFromPoint", "int64", pt, "uint", 1, "ptr")  ; DEFAULTTOPRIMARY
    } else if mode = "foreground" {
        hmon := DllCall("MonitorFromWindow", "ptr", DllCall("GetForegroundWindow", "ptr"), "uint", 2, "ptr")  ; DEFAULTTONEAREST
    } else {
        ptBuf := Buffer(8, 0)
        DllCall("GetCursorPos", "ptr", ptBuf)
        pt := NumGet(ptBuf, 0, "int64")
        hmon := DllCall("MonitorFromPoint", "int64", pt, "uint", 1, "ptr")
    }
    info := Buffer(40, 0)
    NumPut("uint", 40, info, 0)
    if !hmon || !DllCall("GetMonitorInfo", "ptr", hmon, "ptr", info)
        throw Error("Windows did not return monitor information.")
    l := NumGet(info, 20, "int"), t := NumGet(info, 24, "int")
    r := NumGet(info, 28, "int"), b := NumGet(info, 32, "int")
    dpi := 96
    try {
        dpiX := 0, dpiY := 0
        if !DllCall("shcore\GetDpiForMonitor", "ptr", hmon, "int", 0, "uint*", &dpiX, "uint*", &dpiY, "uint")
            dpi := dpiX
    }
}

; Exact port of WindowLayoutService.Calculate.
UT_CalculateLayout(waL, waT, waR, waB, dpi, &claudeRect, &codexRect) {
    width := waR - waL, height := waB - waT
    scale := Max(1, dpi) / 96.0
    margin := Min(Round(Integer(Cfg("UsageTracker", "OuterMargin", "24")) * scale), width // 4)
    gap := Min(Round(Integer(Cfg("UsageTracker", "Gap", "12")) * scale), width // 4)
    usableWidth := Max(2, width - 2 * margin)
    usableHeight := Max(1, height - 2 * margin)
    combinedWidth := Min(usableWidth, Max(2, Round(width * Integer(Cfg("UsageTracker", "WidthPercent", "86")) / 100.0)))
    popupHeight := Min(usableHeight, Max(1, Round(height * Integer(Cfg("UsageTracker", "HeightPercent", "80")) / 100.0)))
    gap := Min(gap, Max(0, combinedWidth - 2))
    contentWidth := combinedWidth - gap
    leftWidth := contentWidth // 2
    rightWidth := contentWidth - leftWidth
    x := waL + (width - combinedWidth) // 2
    y := waT + (height - popupHeight) // 2
    claudeRect := {x: x, y: y, w: leftWidth, h: popupHeight}
    codexRect := {x: x + leftWidth + gap, y: y, w: rightWidth, h: popupHeight}
}

; WS_EX_TOOLWINDOW on, WS_EX_APPWINDOW off (no taskbar entry), then
; place with SWP_FRAMECHANGED, topmost when configured.
UT_ApplyStyle(hwnd, rect, topmost) {
    if !DllCall("IsWindow", "ptr", hwnd)
        throw Error("The Chrome window no longer exists.")
    ex := DllCall("GetWindowLongPtr", "ptr", hwnd, "int", -20, "ptr")
    ex := (ex | 0x80) & ~0x40000
    DllCall("SetWindowLongPtr", "ptr", hwnd, "int", -20, "ptr", ex, "ptr")
    insertAfter := topmost ? -1 : -2
    if !DllCall("SetWindowPos", "ptr", hwnd, "ptr", insertAfter
        , "int", rect.x, "int", rect.y, "int", rect.w, "int", rect.h
        , "uint", 0x20 | 0x40)  ; SWP_FRAMECHANGED | SWP_SHOWWINDOW
        throw Error("Windows blocked the Chrome window change.")
    SuiteLog("usage: styled hwnd=" hwnd " at " rect.x "," rect.y " " rect.w "x" rect.h)
}

; ------------------------------------------------------------ settings gui

UT_OpenSettings(*) {
    global UT_SettingsGui
    if UT_SettingsGui {
        try {
            UT_SettingsGui.Show()
            return
        }
        UT_SettingsGui := 0
    }
    g := Gui("+AlwaysOnTop -MinimizeBox", "CC Usage Tracker settings")
    g.SetFont("s10")
    g.AddText("xm y+12 w130", "Claude usage URL")
    edClaude := g.AddEdit("x+8 yp-3 w320", Cfg("UsageTracker", "ClaudeUrl", "https://claude.ai/settings/usage"))
    g.AddText("xm y+14 w130", "Codex usage URL")
    edCodex := g.AddEdit("x+8 yp-3 w320", Cfg("UsageTracker", "CodexUrl", "https://chatgpt.com/codex/settings/usage"))
    g.AddText("xm y+14 w130", "Chrome path")
    edChrome := g.AddEdit("x+8 yp-3 w240", Cfg("UsageTracker", "ChromeExecutable"))
    btnBrowse := g.AddButton("x+6 yp w74", "Browse...")
    g.AddText("xm y+14 w130", "Monitor")
    static monLabels := ["Mouse", "Foreground window", "Primary"]
    static monValues := ["mouse", "foreground", "primary"]
    cur := StrLower(Cfg("UsageTracker", "MonitorSelection", "mouse"))
    monSel := 1
    for i, v in monValues
        if v = cur
            monSel := i
    ddMon := g.AddDropDownList("x+8 yp-3 w200 Choose" monSel, monLabels)
    g.AddText("xm y+14 w130", "Width percent")
    edWidth := g.AddEdit("x+8 yp-3 w70 Number", Cfg("UsageTracker", "WidthPercent", "86"))
    g.AddText("x+16", "Height percent")
    edHeight := g.AddEdit("x+8 yp-3 w70 Number", Cfg("UsageTracker", "HeightPercent", "80"))
    g.AddText("xm y+14 w130", "Gap")
    edGap := g.AddEdit("x+8 yp-3 w70 Number", Cfg("UsageTracker", "Gap", "12"))
    g.AddText("x+16", "Outer margin")
    edMargin := g.AddEdit("x+8 yp-3 w70 Number", Cfg("UsageTracker", "OuterMargin", "24"))
    cbTop := g.AddCheckbox("xm y+16", "Keep usage windows on top")
    cbTop.Value := CfgBool("UsageTracker", "KeepOnTop")
    btnSave := g.AddButton("xm+290 y+18 w76 Default", "Save")
    btnCancel := g.AddButton("x+8 yp w76", "Cancel")

    btnBrowse.OnEvent("Click", (*) => UT_BrowseChrome(edChrome, g))
    btnSave.OnEvent("Click", (*) => UT_SaveSettings(g, edClaude, edCodex, edChrome, ddMon, edWidth, edHeight, edGap, edMargin, cbTop, monValues))
    btnCancel.OnEvent("Click", (*) => UT_CloseSettings(g))
    g.OnEvent("Close", (*) => UT_CloseSettings(g))
    g.OnEvent("Escape", (*) => UT_CloseSettings(g))
    g.Show()
    UT_SettingsGui := g
}

UT_CloseSettings(g) {
    global UT_SettingsGui := 0
    try g.Destroy()
}

UT_BrowseChrome(edChrome, owner) {
    owner.Opt("+OwnDialogs")
    picked := FileSelect(1, , "Select chrome.exe", "Chrome (chrome.exe)")
    if picked != ""
        edChrome.Value := picked
}

UT_SaveSettings(g, edClaude, edCodex, edChrome, ddMon, edWidth, edHeight, edGap, edMargin, cbTop, monValues) {
    errors := []
    if !UT_IsHttpsUrl(edClaude.Value)
        errors.Push("Claude usage URL must be an absolute HTTPS URL.")
    if !UT_IsHttpsUrl(edCodex.Value)
        errors.Push("Codex usage URL must be an absolute HTTPS URL.")
    if edChrome.Value != "" && !UT_IsChromeExe(edChrome.Value)
        errors.Push("Chrome executable path must point to an existing chrome.exe file.")
    if !UT_IntInRange(edWidth.Value, 30, 100)
        errors.Push("Width must be between 30 and 100 percent.")
    if !UT_IntInRange(edHeight.Value, 30, 100)
        errors.Push("Height must be between 30 and 100 percent.")
    if !UT_IntInRange(edGap.Value, 0, 200)
        errors.Push("Gap must be between 0 and 200 logical pixels.")
    if !UT_IntInRange(edMargin.Value, 0, 400)
        errors.Push("Outer margin must be between 0 and 400 logical pixels.")
    if errors.Length {
        msg := ""
        for e in errors
            msg .= e "`n"
        MsgBox RTrim(msg, "`n"), "Could not save settings", "Iconx Owner" g.Hwnd
        return
    }
    CfgSet("UsageTracker", "ClaudeUrl", edClaude.Value)
    CfgSet("UsageTracker", "CodexUrl", edCodex.Value)
    CfgSet("UsageTracker", "ChromeExecutable", edChrome.Value)
    CfgSet("UsageTracker", "MonitorSelection", monValues[ddMon.Value])
    CfgSet("UsageTracker", "WidthPercent", Integer(edWidth.Value))
    CfgSet("UsageTracker", "HeightPercent", Integer(edHeight.Value))
    CfgSet("UsageTracker", "Gap", Integer(edGap.Value))
    CfgSet("UsageTracker", "OuterMargin", Integer(edMargin.Value))
    CfgSet("UsageTracker", "KeepOnTop", cbTop.Value ? "1" : "0")
    UT_CloseSettings(g)
}

UT_IsHttpsUrl(v) {
    return RegExMatch(v, "i)^https://[^/\s]+") ? true : false
}

UT_IntInRange(v, lo, hi) {
    return IsInteger(v) && Integer(v) >= lo && Integer(v) <= hi
}
