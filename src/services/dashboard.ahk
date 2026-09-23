; Morning Dashboard: Ctrl+Alt+M toggles a Google-Calendar-centered layout.
; Two monitors: a Brave window (Todoist first, then Gmail) maximized over
; Outlook on the left monitor; Google Calendar (day view) beside a Google
; Calendar tasks view split 50/50 on the right, plus a minimized Chrome
; window holding a bookmarks folder parked on the right. One monitor: just
; the calendar day view and the tasks view split 50/50. Teardown closes only
; windows the dashboard created and restores a borrowed Outlook. Open state
; is tracked in memory only, so a fresh process starts closed and stale
; window handles never linger.

global MD_Busy := false
global MD_MenuRef := 0
global MD_OpenWindows := []     ; [{hwnd, exes}] created this session
global MD_OutlookRestore := 0   ; {hwnd,x,y,w,h,mm} for a borrowed Outlook

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
    hint := HotkeyLabel(MD_Hotkey())
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
    if !SuiteServiceEnabled("Dashboard")
        for item in ["Open dashboard", "Close dashboard", "Toggle dashboard"]
            m.Disable(item)
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

; Open state is derived from the tracked windows, not a saved flag, so it
; self-corrects when the user closes windows by hand or the app restarts.
MD_Active() {
    global MD_OpenWindows
    for w in MD_OpenWindows
        if w.hwnd && WinExist("ahk_id " w.hwnd)
            return true
    return false
}

MD_Track(hwnd, exes) {
    global MD_OpenWindows
    if hwnd
        MD_OpenWindows.Push({hwnd: hwnd, exes: exes})
}

; ----------------------------------------------------------------- monitors

; Left = smallest work-area center X, right = largest. Coordinates can be
; negative. [Dashboard.Monitors] overrides by AutoHotkey index. Returns
; false with a single monitor (or a config that collapses both to one).
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

; The sole monitor to use when there is no distinct left/right pair.
MD_SingleMonitor() {
    m := MonitorGetPrimary()
    return m ? m : 1
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

; Todoist opens first so Chromium makes it the focused tab, then the Gmail
; inboxes. Title needle tracks the active tab, so it becomes Todoist.
MD_OpenGmailWindow() {
    args := "--new-window"
    todoist := Cfg("Dashboard.Todoist", "Url")
    if todoist != ""
        args .= ' "' todoist '"'
    for key in ["Url1", "Url2", "Url3"] {
        url := Cfg("Dashboard.Gmail", key)
        if url != ""
            args .= ' "' url '"'
    }
    return MD_LaunchBraveWindow(args, todoist != "" ? "Todoist" : "Gmail")
}

; Direct-child bookmark URLs of the first folder named `folderName` in the
; given Chrome profile, searching the bookmark bar, other, then synced roots.
MD_ChromeBookmarkUrls(profile, folderName) {
    file := EnvGet("LOCALAPPDATA") "\Google\Chrome\User Data\" profile "\Bookmarks"
    if !FileExist(file)
        throw Error("Chrome bookmarks file not found: " file)
    roots := JSON.Parse(FileRead(file, "UTF-8"))["roots"]
    folder := 0
    for key in ["bookmark_bar", "other", "synced"]
        if roots.Has(key) && (folder := MD_FindBookmarkFolder(roots[key], folderName))
            break
    if !folder
        throw Error("Bookmark folder not found: " folderName)
    urls := []
    for child in folder["children"]
        if child.Has("type") && child["type"] = "url" && child.Has("url")
            urls.Push(child["url"])
    if !urls.Length
        throw Error("Bookmark folder has no links: " folderName)
    return urls
}

; Depth-first search for a folder node matching `name` (case-insensitive).
MD_FindBookmarkFolder(node, name) {
    if !(node is Map)
        return 0
    if node.Has("type") && node["type"] = "folder" && node.Has("name") && StrLower(node["name"]) = StrLower(name)
        return node
    if node.Has("children")
        for child in node["children"]
            if found := MD_FindBookmarkFolder(child, name)
                return found
    return 0
}

; Opens the configured bookmarks folder as tabs in a new Chrome window on the
; user's chosen profile, then parks it maximized-then-minimized on the right
; monitor so restoring it lands there without covering the split.
MD_OpenBookmarksWindow(rightMon) {
    profile := Cfg("Dashboard.Chrome", "ProfileDirectory", "Default")
    folder := Cfg("Dashboard.Chrome", "BookmarkFolder")
    if folder = ""
        throw Error("Set [Dashboard.Chrome] BookmarkFolder in config.local.ini.")
    urls := MD_ChromeBookmarkUrls(profile, folder)
    chrome := LocateChrome(Cfg("Dashboard.Chrome", "Executable"))
    if chrome = ""
        throw Error("Google Chrome not found. Set [Dashboard.Chrome] Executable in config.local.ini.")
    args := ""
    for u in urls
        args .= ' "' u '"'
    before := SnapshotChromeWindows()
    Run '"' chrome '" --profile-directory="' profile '" --new-window' args
    hwnd := WaitNewChromeWindow(before)
    if !hwnd
        throw Error("New Chrome window did not appear.")
    MonitorGetWorkArea(rightMon, &l, &t, &r, &b)
    MoveWindowTo(hwnd, l, t, r - l, b - t)
    try WinMaximize "ahk_id " hwnd
    WinMinimize "ahk_id " hwnd
    return hwnd
}

MD_OpenCalendarWindow() {
    url := Cfg("Dashboard.Calendar", "Url", "https://calendar.google.com/calendar/u/0/r/day")
    return MD_LaunchBraveWindow('--app="' url '"', "Calendar")
}

MD_OpenTasksWindow() {
    url := Cfg("Dashboard.Tasks", "Url", "https://calendar.google.com/calendar/u/0/r/tasks")
    return MD_LaunchBraveWindow('--app="' url '"', "Tasks")
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

; Acquires Outlook and records how teardown should treat it: an owned window
; is tracked for closing, a borrowed one is remembered for restore.
MD_AcquireOutlookTracked() {
    global MD_OutlookRestore
    owned := false
    px := py := pw := ph := pmm := 0
    hwnd := MD_AcquireOutlook(&owned, &px, &py, &pw, &ph, &pmm)
    if owned
        MD_Track(hwnd, ["olk.exe", "OUTLOOK.EXE"])
    else
        MD_OutlookRestore := {hwnd: hwnd, x: px, y: py, w: pw, h: ph, mm: pmm}
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

MD_PositionRightMonitor(mon, calHwnd, tasksHwnd) {
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    w := r - l, h := b - t, half := w // 2
    MoveWindowVisible(calHwnd, l, t, half, h)
    MoveWindowVisible(tasksHwnd, l + half, t, w - half, h)
}

; Both maximized on the left monitor; the Brave window (Todoist + Gmail) on
; top so tasks show first, Outlook directly beneath so closing Brave reveals
; a full-monitor Outlook. Z-order is enforced with SetWindowPos because
; WinActivate can be blocked by foreground-lock when the user is interacting
; with another window.
MD_StackLeftMonitor(mon, gmailHwnd, outlookHwnd) {
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    MoveWindowTo(outlookHwnd, l, t, r - l, b - t)
    WinMaximize "ahk_id " outlookHwnd
    MoveWindowTo(gmailHwnd, l, t, r - l, b - t)
    WinMaximize "ahk_id " gmailHwnd
    try WinActivate "ahk_id " gmailHwnd
    flags := 0x1 | 0x2 | 0x10  ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
    DllCall("SetWindowPos", "ptr", gmailHwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", flags)
    DllCall("SetWindowPos", "ptr", outlookHwnd, "ptr", gmailHwnd, "int", 0, "int", 0, "int", 0, "int", 0, "uint", flags)
}

; ------------------------------------------------------------- open / close

MD_Open() {
    if MD_Active() {
        TrayTip "Dashboard is already open.", "Morning Dashboard"
        return
    }
    global MD_OpenWindows := []
    global MD_OutlookRestore := 0
    try {
        if MD_PickMonitors(&leftMon, &rightMon)
            MD_BuildTwoMonitor(leftMon, rightMon)
        else
            MD_BuildOneMonitor()
        TrayTip "Morning Dashboard opened.", "Morning Dashboard"
    } catch as err {
        MD_Teardown()
        SuiteLog("dashboard: open failed: " err.Message " (" err.What ", line " err.Line ")")
        TrayTip "Dashboard failed to open: " err.Message, "Morning Dashboard"
    }
}

; Two monitors: Todoist+Gmail over Outlook on the left; calendar day view
; and tasks split on the right; bookmarks parked minimized on the right.
MD_BuildTwoMonitor(leftMon, rightMon) {
    gmail := MD_OpenGmailWindow()
    MD_Track(gmail, ["brave.exe"])
    cal := MD_OpenCalendarWindow()
    MD_Track(cal, ["brave.exe"])
    tasks := MD_OpenTasksWindow()
    MD_Track(tasks, ["brave.exe"])
    MD_Track(MD_OpenBookmarksWindow(rightMon), ["chrome.exe"])
    outlook := MD_AcquireOutlookTracked()
    MD_PositionRightMonitor(rightMon, cal, tasks)
    MD_StackLeftMonitor(leftMon, gmail, outlook)
}

; One monitor: calendar day view on the left half, tasks view on the right.
MD_BuildOneMonitor() {
    mon := MD_SingleMonitor()
    cal := MD_OpenCalendarWindow()
    MD_Track(cal, ["brave.exe"])
    tasks := MD_OpenTasksWindow()
    MD_Track(tasks, ["brave.exe"])
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    w := r - l, h := b - t, half := w // 2
    MoveWindowVisible(cal, l, t, half, h)
    MoveWindowVisible(tasks, l + half, t, w - half, h)
}

; Closes only tracked dashboard windows (skipping any the user already
; closed) and restores a borrowed Outlook. Safe when nothing is tracked.
MD_Teardown() {
    global MD_OpenWindows, MD_OutlookRestore
    for w in MD_OpenWindows
        SafeCloseWindow(w.hwnd, w.exes)
    if MD_OutlookRestore
        MD_RestoreOutlook(MD_OutlookRestore.hwnd, MD_OutlookRestore.x
            , MD_OutlookRestore.y, MD_OutlookRestore.w
            , MD_OutlookRestore.h, MD_OutlookRestore.mm)
    MD_OpenWindows := []
    MD_OutlookRestore := 0
}

MD_Close() {
    msg := MD_Active() ? "Morning Dashboard closed." : "Dashboard is not open."
    MD_Teardown()
    TrayTip msg, "Morning Dashboard"
}
