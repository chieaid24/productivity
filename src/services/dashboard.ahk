; Morning Dashboard: Ctrl+Alt+M toggles a Google-Calendar-centered layout.
; Two monitors: a Brave window with the three Gmail inboxes maximized over
; Outlook on the left monitor; Google Calendar (day view) beside a Google
; Calendar tasks view split 50/50 on the right, plus a minimized Chrome
; window holding a bookmarks folder parked on the right. One monitor: the
; same windows on one screen, with the calendar day view and tasks view
; split 50/50 in front of the maximized Gmail and Outlook. Cold browsers
; start bare and their restored windows close, so old tabs never join.
; Teardown closes only windows the dashboard created and restores a
; borrowed Outlook. Open state is tracked in memory only, so a fresh
; process starts closed and stale window handles never linger.

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

MD_BraveProfileArg() {
    prof := Cfg("Dashboard.Brave", "ProfileDirectory")
    return prof = "" ? "" : ' --profile-directory="' prof '"'
}

; Finds the new window by diffing Brave's windows, without waiting for its page.
MD_LaunchBraveWindow(args, label) {
    before := SnapshotBrowserWindows("brave.exe")
    Run '"' MD_BraveExe() '"' MD_BraveProfileArg() " " args
    hwnd := WaitNewBrowserWindow("brave.exe", before)
    if !hwnd
        throw Error("New Brave window did not appear (" label ").")
    return hwnd
}

; -------------------------------------------------------------- cold starts

; A cold browser appends command-line URLs to its restored session, so start it bare.
MD_StartBrowser(exe, profileArg) {
    SplitPath exe, &name
    if ProcessExist(name)
        return {exe: name, before: 0}
    before := SnapshotBrowserWindows(name)
    Run '"' exe '"' profileArg
    return {exe: name, before: before}
}

; Windows a bare start restored, once they stop appearing; [] if already running.
MD_WaitRestored(start) {
    if !start.before
        return []
    restored := []
    changedAt := A_TickCount
    deadline := A_TickCount + 20000
    while A_TickCount < deadline {
        now := NewBrowserWindows(start.exe, start.before)
        if now.Length != restored.Length {
            restored := now
            changedAt := A_TickCount
        } else if restored.Length && A_TickCount - changedAt >= 500
            break
        Sleep 100
    }
    return restored
}

; ---------------------------------------------------------- dashboard parts

; The three Gmail inboxes as tabs in one new Brave window, left to right;
; Chromium focuses the first.
MD_OpenGmailWindow() {
    args := "--new-window"
    for key in ["Url1", "Url2", "Url3"] {
        url := Cfg("Dashboard.Gmail", key)
        if url != ""
            args .= ' "' url '"'
    }
    return MD_LaunchBraveWindow(args, "Gmail")
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

MD_ChromeProfile() {
    return Cfg("Dashboard.Chrome", "ProfileDirectory", "Default")
}

MD_ChromeExe() {
    chrome := LocateChrome(Cfg("Dashboard.Chrome", "Executable"))
    if chrome = ""
        throw Error("Google Chrome not found. Set [Dashboard.Chrome] Executable in config.local.ini.")
    return chrome
}

; URLs of the configured bookmarks folder, or [] when none is configured.
MD_BookmarkUrls() {
    folder := Cfg("Dashboard.Chrome", "BookmarkFolder")
    return folder = "" ? [] : MD_ChromeBookmarkUrls(MD_ChromeProfile(), folder)
}

; Opens the bookmark URLs as tabs in a new Chrome window on the user's
; chosen profile, then parks it maximized-then-minimized on `mon` so
; restoring it lands there without covering the split.
MD_OpenBookmarksWindow(chrome, urls, mon) {
    args := ""
    for u in urls
        args .= ' "' u '"'
    before := SnapshotBrowserWindows("chrome.exe")
    Run '"' chrome '" --profile-directory="' MD_ChromeProfile() '" --new-window' args
    hwnd := WaitNewBrowserWindow("chrome.exe", before)
    if !hwnd
        throw Error("New Chrome window did not appear.")
    MonitorGetWorkArea(mon, &l, &t, &r, &b)
    MoveWindowTo(hwnd, l, t, r - l, b - t)
    try WinMaximize "ahk_id " hwnd
    WinMinimize "ahk_id " hwnd
    return hwnd
}

MD_OpenCalendarWindow() {
    url := Cfg("Dashboard.Calendar", "Url", "https://calendar.google.com/calendar/u/0/r/day")
    return MD_LaunchBraveWindow('--app="' url '"', "calendar")
}

MD_OpenTasksWindow() {
    url := Cfg("Dashboard.Tasks", "Url", "https://calendar.google.com/calendar/u/0/r/tasks")
    return MD_LaunchBraveWindow('--app="' url '"', "tasks")
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

; Launches Outlook if needed without waiting, so its startup overlaps the browsers'.
MD_StartOutlook() {
    if hwnd := MD_FindOutlookMainWindow()
        return {hwnd: hwnd, before: 0}
    before := SnapshotWindows("ahk_group MD_Outlook")
    MD_LaunchOutlook()
    return {hwnd: 0, before: before}
}

; Tracks a launched Outlook for closing, or saves a borrowed one's geometry for restore.
MD_FinishOutlook(start) {
    global MD_OutlookRestore
    if hwnd := start.hwnd {
        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
        MD_OutlookRestore := {hwnd: hwnd, x: x, y: y, w: w, h: h, mm: WinGetMinMax("ahk_id " hwnd)}
        return hwnd
    }
    hwnd := WaitNewWindow("ahk_group MD_Outlook", start.before, "", 45000, "#32770")
    if !hwnd
        throw Error("Outlook window did not appear.")
    MD_Track(hwnd, ["olk.exe", "OUTLOOK.EXE"])
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

; Raises a window to the top of the z-order without moving, sizing, or
; focusing it.
MD_RaiseWindow(hwnd) {
    if !hwnd || !WinExist("ahk_id " hwnd)
        return
    flags := 0x1 | 0x2 | 0x10  ; SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE
    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", flags)
}

; Calendar and tasks split 50/50, raised above the maximized windows behind
; them, with the calendar focused. Used on a single monitor.
MD_SplitFront(mon, calHwnd, tasksHwnd) {
    MD_PositionRightMonitor(mon, calHwnd, tasksHwnd)
    MD_RaiseWindow(tasksHwnd)
    MD_RaiseWindow(calHwnd)
    try WinActivate "ahk_id " calHwnd
}

; Both maximized on the left monitor; the Gmail Brave window on top, Outlook
; directly beneath so closing Brave reveals a full-monitor Outlook. Z-order
; is enforced with SetWindowPos because
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
    SetWinDelay 0  ; the 100 ms default after every window command adds up
    started := A_TickCount
    try {
        if MD_PickMonitors(&leftMon, &rightMon)
            MD_BuildTwoMonitor(leftMon, rightMon)
        else
            MD_BuildOneMonitor()
        SuiteLog("dashboard: opened in " (A_TickCount - started) " ms")
        TrayTip "Morning Dashboard opened.", "Morning Dashboard"
    } catch as err {
        MD_Teardown()
        SuiteLog("dashboard: open failed: " err.Message " (" err.What ", line " err.Line ")")
        TrayTip "Dashboard failed to open: " err.Message, "Morning Dashboard"
    }
}

; Starts slow apps first so startups overlap. Restored windows close last,
; once dashboard windows keep their browser alive.
MD_LaunchAll(bookmarkMon) {
    outlook := MD_StartOutlook()
    brave := MD_StartBrowser(MD_BraveExe(), MD_BraveProfileArg())
    urls := MD_BookmarkUrls()
    if urls.Length {
        chromeExe := MD_ChromeExe()
        chrome := MD_StartBrowser(chromeExe, ' --profile-directory="' MD_ChromeProfile() '"')
    }
    restored := MD_WaitRestored(brave)
    w := {}
    w.gmail := MD_OpenGmailWindow()
    MD_Track(w.gmail, ["brave.exe"])
    w.cal := MD_OpenCalendarWindow()
    MD_Track(w.cal, ["brave.exe"])
    w.tasks := MD_OpenTasksWindow()
    MD_Track(w.tasks, ["brave.exe"])
    if urls.Length {
        for hwnd in MD_WaitRestored(chrome)
            restored.Push(hwnd)
        MD_Track(MD_OpenBookmarksWindow(chromeExe, urls, bookmarkMon), ["chrome.exe"])
    }
    for hwnd in restored
        SafeCloseWindow(hwnd, ["brave.exe", "chrome.exe"], false)
    w.outlook := MD_FinishOutlook(outlook)
    return w
}

; Two monitors: Gmail over Outlook on the left; calendar day view and tasks
; split on the right; bookmarks parked minimized on the right.
MD_BuildTwoMonitor(leftMon, rightMon) {
    w := MD_LaunchAll(rightMon)
    MD_PositionRightMonitor(rightMon, w.cal, w.tasks)
    MD_StackLeftMonitor(leftMon, w.gmail, w.outlook)
}

; One monitor: the full set on one screen. Gmail over Outlook maximized
; behind, calendar day view and tasks split 50/50 in front, bookmarks parked
; minimized.
MD_BuildOneMonitor() {
    mon := MD_SingleMonitor()
    w := MD_LaunchAll(mon)
    MD_StackLeftMonitor(mon, w.gmail, w.outlook)
    MD_SplitFront(mon, w.cal, w.tasks)
}

; Closes only tracked dashboard windows (skipping any the user already
; closed) and restores a borrowed Outlook. Safe when nothing is tracked.
; All closes are requested at once, then awaited together.
MD_Teardown() {
    global MD_OpenWindows, MD_OutlookRestore
    for w in MD_OpenWindows
        SafeCloseWindow(w.hwnd, w.exes, false)
    deadline := A_TickCount + 5000
    for w in MD_OpenWindows
        WinWaitClose "ahk_id " w.hwnd, , Max(0.1, (deadline - A_TickCount) / 1000)
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
