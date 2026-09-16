; Morning Dashboard: Ctrl+Alt+M toggles a two-monitor layout - Outlook
; maximized over a Gmail Brave window on the left monitor, Google Calendar
; and a private schedule viewer split 50/50 on the right. Teardown closes
; only windows the dashboard created and restores a borrowed Outlook.

global MD_Busy := false
global MD_MenuRef := 0

MD_Init() {
    GroupAdd "MD_Outlook", "ahk_exe olk.exe"
    GroupAdd "MD_Outlook", "ahk_exe OUTLOOK.EXE"
    if SuiteServiceEnabled("Dashboard")
        MD_Enable()
}

MD_Hotkey() {
    return Cfg("Dashboard", "Hotkey", "^!m")
}

MD_Enable() {
    try Hotkey(MD_Hotkey(), (*) => MD_Guard(MD_Toggle), "On")
    catch as err
        SuiteLog("dashboard: could not register hotkey: " err.Message)
}

MD_Disable() {
    try Hotkey(MD_Hotkey(), "Off")
}

MD_BuildMenu(m) {
    global MD_MenuRef := m
    hint := "Hotkey: " HotkeyLabel(MD_Hotkey())
    m.Add(hint, (*) => "")
    m.Disable(hint)
    m.Add()
    m.Add("Enabled", (*) => SuiteToggleService("Dashboard"))
    if SuiteServiceEnabled("Dashboard")
        m.Check("Enabled")
    m.Add()
    m.Add("Open dashboard", (*) => MD_Guard(MD_Open))
    m.Add("Close dashboard", (*) => MD_Guard(MD_Close))
    m.Add("Toggle dashboard", (*) => MD_Guard(MD_Toggle))
    m.Add()
    m.Add("Settings...", (*) => SuiteOpenConfig())
}

MD_SetEnabled(on) {
    if on
        MD_Enable()
    else
        MD_Disable()
    if MD_MenuRef {
        if on
            MD_MenuRef.Check("Enabled")
        else
            MD_MenuRef.Uncheck("Enabled")
        for item in ["Open dashboard", "Close dashboard", "Toggle dashboard"]
            on ? MD_MenuRef.Enable(item) : MD_MenuRef.Disable(item)
    }
}

; Serializes open/close so repeated hotkey presses cannot run concurrently.
MD_Guard(action) {
    global MD_Busy
    if MD_Busy
        return
    MD_Busy := true
    try action()
    finally MD_Busy := false
}

MD_Toggle() {
    if MD_Active()
        MD_Close()
    else
        MD_Open()
}

; ------------------------------------------------------------ session state

MD_State(key, default := "") {
    return StateGet("dashboard.ini", key, default)
}

MD_StateInt(key) {
    v := MD_State(key, "0")
    return IsInteger(v) ? Integer(v) : 0
}

MD_StateSet(key, value) {
    StateSet("dashboard.ini", key, value)
}

MD_StateClear() {
    StateDelete("dashboard.ini")
}

MD_Active() {
    return MD_State("Active", "0") = "1"
}

; ----------------------------------------------------------------- monitors

; Left = smallest work-area center X, right = largest. Coordinates can be
; negative. [Dashboard.Monitors] overrides by AutoHotkey index.
MD_PickMonitors(&leftMon, &rightMon) {
    count := MonitorGetCount()
    if count < 2
        return false
    leftMon := rightMon := 1
    minCx := maxCx := ""
    loop count {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        cx := (l + r) / 2
        if minCx = "" || cx < minCx {
            minCx := cx
            leftMon := A_Index
        }
        if maxCx = "" || cx > maxCx {
            maxCx := cx
            rightMon := A_Index
        }
    }
    cfgL := Cfg("Dashboard.Monitors", "LeftMonitor")
    cfgR := Cfg("Dashboard.Monitors", "RightMonitor")
    if cfgL != "" && IsInteger(cfgL)
        leftMon := Integer(cfgL)
    if cfgR != "" && IsInteger(cfgR)
        rightMon := Integer(cfgR)
    return leftMon != rightMon
}

; -------------------------------------------------------------------- brave

MD_BraveExe() {
    exe := Cfg("Dashboard.Brave", "Executable")
    if exe != "" && FileExist(exe)
        return exe
    candidates := [
        "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
        EnvGet("LOCALAPPDATA") "\BraveSoftware\Brave-Browser\Application\brave.exe"
    ]
    for p in candidates
        if FileExist(p)
            return p
    throw Error("Brave not found. Set [Dashboard.Brave] Executable in config.local.ini.")
}

; New-window HWNDs are found by diffing top-level Brave windows before and
; after launch; Chromium shares processes, so PIDs cannot identify windows.
MD_LaunchBraveWindow(args, titleNeedle) {
    before := SnapshotWindows("ahk_exe brave.exe")
    cmd := '"' MD_BraveExe() '"'
    prof := Cfg("Dashboard.Brave", "ProfileDirectory")
    if prof != ""
        cmd .= ' --profile-directory="' prof '"'
    cmd .= " " args
    Run cmd
    hwnd := WaitNewWindow("ahk_exe brave.exe", before, titleNeedle)
    if !hwnd
        throw Error("New Brave window did not appear (" titleNeedle ").")
    return hwnd
}

; ---------------------------------------------------------- dashboard parts

MD_OpenGmailWindow() {
    args := "--new-window"
    for key in ["Url1", "Url2", "Url3"] {
        url := Cfg("Dashboard.Gmail", key)
        if url != ""
            args .= ' "' url '"'
    }
    return MD_LaunchBraveWindow(args, "Gmail")
}

MD_OpenCalendarWindow() {
    url := Cfg("Dashboard.Calendar", "Url", "https://calendar.google.com/calendar/u/0/r")
    return MD_LaunchBraveWindow('--app="' url '"', "Calendar")
}

MD_OpenScheduleWindow() {
    viewer := SuiteRoot "\" Cfg("Dashboard.Schedule", "Viewer", "viewer\schedule.html")
    if !FileExist(viewer)
        throw Error("Schedule viewer not found: " viewer)
    img := SuiteRoot "\" Cfg("Dashboard.Schedule", "LocalImage", ".private\WEEKLY SCHEDULE.jpg")
    if !FileExist(img)
        TrayTip "Schedule image missing. Run scripts\set-schedule-image.ps1.", "Morning Dashboard"
    return MD_LaunchBraveWindow('--app="' FileUrl(viewer) '"', "Morning Dashboard Schedule")
}

; Skips #32770 dialogs (reminders, error prompts) - only a real main window
; should be reused or tracked.
MD_FindOutlookMainWindow() {
    for hwnd in WinGetList("ahk_group MD_Outlook") {
        if WindowHasClass(hwnd, "#32770")
            continue
        title := ""
        try title := WinGetTitle("ahk_id " hwnd)
        if title != ""
            return hwnd
    }
    return 0
}

MD_LaunchOutlook() {
    prefer := StrLower(Cfg("Dashboard.Outlook", "Prefer", "new"))
    exe := Cfg("Dashboard.Outlook", "Executable")
    appId := Cfg("Dashboard.Outlook", "AppId")
    if prefer = "new" && appId != "" {
        Run 'explorer.exe "shell:AppsFolder\' appId '"'
        return
    }
    if exe != "" && FileExist(exe) {
        Run '"' exe '"'
        return
    }
    if appId != "" {
        Run 'explorer.exe "shell:AppsFolder\' appId '"'
        return
    }
    Run "outlook.exe"
}

; Reuses an existing Outlook main window (recording its geometry for
; restore-on-teardown) or launches one owned by the dashboard.
MD_AcquireOutlook(&owned, &px, &py, &pw, &ph, &pmm) {
    owned := false
    px := py := pw := ph := pmm := 0
    hwnd := MD_FindOutlookMainWindow()
    if hwnd {
        WinGetPos &px, &py, &pw, &ph, "ahk_id " hwnd
        pmm := WinGetMinMax("ahk_id " hwnd)
        return hwnd
    }
    owned := true
    before := SnapshotWindows("ahk_group MD_Outlook")
    MD_LaunchOutlook()
    hwnd := WaitNewWindow("ahk_group MD_Outlook", before, "", 45000, "#32770")
    if !hwnd
        throw Error("Outlook window did not appear.")
    return hwnd
}

MD_RestoreOutlook(hwnd, x, y, w, h, mm) {
    if !hwnd || !WinExist("ahk_id " hwnd)
        return
    try {
        WinRestore "ahk_id " hwnd
        if w > 0 && h > 0 {
            ; Twice: apps that rescale on a monitor DPI change resize
            ; themselves after the first move; the second pass corrects it.
            WinMove x, y, w, h, "ahk_id " hwnd
            WinMove x, y, w, h, "ahk_id " hwnd
        }
        if mm = 1
            WinMaximize "ahk_id " hwnd
        else if mm = -1
            WinMinimize "ahk_id " hwnd
    }
}

; ------------------------------------------------------------------- layout

MD_PositionRightMonitor(mon, calHwnd, schedHwnd) {
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    w := r - l, h := b - t, half := w // 2
    MoveWindowVisible(calHwnd, l, t, half, h)
    MoveWindowVisible(schedHwnd, l + half, t, w - half, h)
}

; Both maximized on the left monitor; Outlook on top, Gmail directly
; beneath so closing Outlook reveals a full-monitor Gmail. Z-order is
; enforced with SetWindowPos because WinActivate can be blocked by
; foreground-lock when the user is interacting with another window.
MD_StackLeftMonitor(mon, gmailHwnd, outlookHwnd) {
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    MoveWindowTo(gmailHwnd, l, t, r - l, b - t)
    WinMaximize "ahk_id " gmailHwnd
    MoveWindowTo(outlookHwnd, l, t, r - l, b - t)
    WinMaximize "ahk_id " outlookHwnd
    try WinActivate "ahk_id " outlookHwnd
    flags := 0x1 | 0x2 | 0x10  ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
    DllCall("SetWindowPos", "ptr", outlookHwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", flags)
    DllCall("SetWindowPos", "ptr", gmailHwnd, "ptr", outlookHwnd, "int", 0, "int", 0, "int", 0, "int", 0, "uint", flags)
}

; ------------------------------------------------------------- open / close

MD_Open() {
    if MD_Active() {
        TrayTip "Dashboard is already open.", "Morning Dashboard"
        return
    }
    if !MD_PickMonitors(&leftMon, &rightMon) {
        TrayTip "Two monitors are required for the Morning Dashboard.", "Morning Dashboard"
        return
    }
    created := []
    outlook := 0
    owned := true
    px := py := pw := ph := pmm := 0
    try {
        gmail := MD_OpenGmailWindow()
        created.Push(gmail)
        cal := MD_OpenCalendarWindow()
        created.Push(cal)
        sched := MD_OpenScheduleWindow()
        created.Push(sched)
        outlook := MD_AcquireOutlook(&owned, &px, &py, &pw, &ph, &pmm)
        if owned
            created.Push(outlook)

        MD_PositionRightMonitor(rightMon, cal, sched)
        MD_StackLeftMonitor(leftMon, gmail, outlook)

        MD_StateSet("GmailHwnd", gmail)
        MD_StateSet("CalendarHwnd", cal)
        MD_StateSet("ScheduleHwnd", sched)
        MD_StateSet("OutlookHwnd", outlook)
        MD_StateSet("OutlookOwned", owned ? "1" : "0")
        MD_StateSet("OutlookPrevX", px)
        MD_StateSet("OutlookPrevY", py)
        MD_StateSet("OutlookPrevW", pw)
        MD_StateSet("OutlookPrevH", ph)
        MD_StateSet("OutlookPrevMinMax", pmm)
        MD_StateSet("Active", "1")
        TrayTip "Morning Dashboard opened.", "Morning Dashboard"
    } catch as err {
        for hwnd in created
            SafeCloseWindow(hwnd, ["brave.exe", "olk.exe", "OUTLOOK.EXE"])
        if outlook && !owned
            MD_RestoreOutlook(outlook, px, py, pw, ph, pmm)
        MD_StateClear()
        SuiteLog("dashboard: open failed: " err.Message " (" err.What ", line " err.Line ")")
        TrayTip "Dashboard failed to open: " err.Message, "Morning Dashboard"
    }
}

; Closes only tracked dashboard windows; skips any the user already closed.
MD_Close() {
    if !MD_Active() {
        TrayTip "Dashboard is not open.", "Morning Dashboard"
        return
    }
    SafeCloseWindow(MD_StateInt("ScheduleHwnd"), ["brave.exe"])
    SafeCloseWindow(MD_StateInt("CalendarHwnd"), ["brave.exe"])
    SafeCloseWindow(MD_StateInt("GmailHwnd"), ["brave.exe"])

    outlook := MD_StateInt("OutlookHwnd")
    if MD_State("OutlookOwned", "0") = "1"
        SafeCloseWindow(outlook, ["olk.exe", "OUTLOOK.EXE"])
    else
        MD_RestoreOutlook(outlook
            , MD_StateInt("OutlookPrevX"), MD_StateInt("OutlookPrevY")
            , MD_StateInt("OutlookPrevW"), MD_StateInt("OutlookPrevH")
            , MD_StateInt("OutlookPrevMinMax"))

    MD_StateClear()
    TrayTip "Morning Dashboard closed.", "Morning Dashboard"
}
