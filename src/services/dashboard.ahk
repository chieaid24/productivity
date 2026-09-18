; Morning Dashboard: Ctrl+Alt+M toggles a two-monitor layout - a Brave
; window (Todoist first, then Gmail) maximized over Outlook on the left
; monitor, Google Calendar and a private schedule viewer split 50/50 on the
; right, plus a minimized Chrome window holding a bookmarks folder parked on
; the right. Teardown closes only windows the dashboard created and restores
; a borrowed Outlook.

global MD_Busy := false
global MD_MenuRef := 0
global MD_SettingsGui := 0

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
    m.Add()
    m.Add("Settings...", MD_OpenSettings)
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
    url := Cfg("Dashboard.Calendar", "Url", "https://calendar.google.com/calendar/u/0/r")
    return MD_LaunchBraveWindow('--app="' url '"', "Calendar")
}

MD_OpenScheduleWindow() {
    viewer := SuiteRoot "\" Cfg("Dashboard.Schedule", "Viewer", "viewer\schedule.html")
    if !FileExist(viewer)
        throw Error("Schedule viewer not found: " viewer)
    img := MD_ScheduleImagePath()
    if !FileExist(img)
        TrayTip "Schedule image missing. Set it in Morning Dashboard > Settings.", "Morning Dashboard"
    ; Viewer reads ?img=<encoded file url> and sets the picture from it.
    url := FileUrl(viewer) "?img=" UriEncode(FileUrl(img))
    return MD_LaunchBraveWindow('--app="' url '"', "Morning Dashboard Schedule")
}

; Configured schedule image resolved to a full path: absolute paths (drive
; letter or UNC) are used as-is, anything else is relative to the app folder.
MD_ScheduleImagePath() {
    p := Cfg("Dashboard.Schedule", "LocalImage", ".private\WEEKLY SCHEDULE.jpg")
    if RegExMatch(p, "^[A-Za-z]:[\\/]") || SubStr(p, 1, 2) = "\\"
        return p
    return SuiteRoot "\" p
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
        chromeBk := MD_OpenBookmarksWindow(rightMon)
        created.Push(chromeBk)
        outlook := MD_AcquireOutlook(&owned, &px, &py, &pw, &ph, &pmm)
        if owned
            created.Push(outlook)

        MD_PositionRightMonitor(rightMon, cal, sched)
        MD_StackLeftMonitor(leftMon, gmail, outlook)

        MD_StateSet("GmailHwnd", gmail)
        MD_StateSet("CalendarHwnd", cal)
        MD_StateSet("ScheduleHwnd", sched)
        MD_StateSet("ChromeHwnd", chromeBk)
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
            SafeCloseWindow(hwnd, ["brave.exe", "chrome.exe", "olk.exe", "OUTLOOK.EXE"])
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
    SafeCloseWindow(MD_StateInt("ChromeHwnd"), ["chrome.exe"])

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

; ------------------------------------------------------------ settings gui

MD_OpenSettings(*) {
    global MD_SettingsGui
    if MD_SettingsGui {
        try {
            MD_SettingsGui.Show()  ; already built and open; just focus it
            return
        }
        MD_SettingsGui := 0
    }
    g := Gui("+AlwaysOnTop -MinimizeBox", "Morning Dashboard settings")
    g.SetFont("s10")
    g.AddText("xm y+12 w110", "Schedule image")
    edImage := g.AddEdit("x+8 yp-3 w330", Cfg("Dashboard.Schedule", "LocalImage", ".private\WEEKLY SCHEDULE.jpg"))
    btnBrowse := g.AddButton("x+6 yp w76", "Browse...")
    g.AddText("xm y+10 w440 cGray", "Absolute path, or relative to the app folder. Opens on the right monitor.")
    btnConfig := g.AddButton("xm y+18 w150", "Open config file...")
    btnSave := g.AddButton("x+96 yp w76 Default", "Save")
    btnCancel := g.AddButton("x+8 yp w76", "Cancel")

    btnBrowse.OnEvent("Click", (*) => MD_BrowseImage(edImage, g))
    btnConfig.OnEvent("Click", (*) => SuiteOpenConfig())
    btnSave.OnEvent("Click", (*) => MD_SaveSettings(g, edImage))
    btnCancel.OnEvent("Click", (*) => MD_CloseSettings(g))
    g.OnEvent("Close", (*) => MD_CloseSettings(g))
    g.OnEvent("Escape", (*) => MD_CloseSettings(g))
    g.Show()
    MD_SettingsGui := g
}

MD_CloseSettings(g) {
    global MD_SettingsGui := 0
    try g.Destroy()
}

MD_BrowseImage(edImage, owner) {
    owner.Opt("+OwnDialogs")
    picked := FileSelect(1, , "Choose the schedule image", "Images (*.jpg; *.jpeg; *.png; *.gif; *.bmp; *.webp)")
    if picked != ""
        edImage.Value := picked
}

MD_SaveSettings(g, edImage) {
    img := Trim(edImage.Value, " `t`r`n")
    if img = "" {
        MsgBox "Choose a schedule image.", "Could not save settings", "Iconx Owner" g.Hwnd
        return
    }
    resolved := (RegExMatch(img, "^[A-Za-z]:[\\/]") || SubStr(img, 1, 2) = "\\") ? img : SuiteRoot "\" img
    if !FileExist(resolved) {
        MsgBox "That image file does not exist:`n" resolved, "Could not save settings", "Iconx Owner" g.Hwnd
        return
    }
    CfgSet("Dashboard.Schedule", "LocalImage", img)
    MD_CloseSettings(g)
}
