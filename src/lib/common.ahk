; Shared config, state, logging, and window helpers for all services.
; The Windows INI APIs (IniRead/IniWrite) fail on some network paths
; (e.g. \\wsl.localhost), so all INI access uses plain file reads/writes.

IniLoad(path) {
    data := Map()
    section := ""
    try content := FileRead(path)
    catch
        return data
    loop parse content, "`n", "`r" {
        line := Trim(A_LoopField)
        if line = "" || SubStr(line, 1, 1) = ";"
            continue
        if SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]" {
            section := SubStr(line, 2, StrLen(line) - 2)
            continue
        }
        pos := InStr(line, "=")
        if !pos
            continue
        data[section "." Trim(SubStr(line, 1, pos - 1))] := Trim(SubStr(line, pos + 1))
    }
    return data
}

ConfigPath() {
    for p in [SuiteRoot "\config.local.ini", SuiteRoot "\config\config.local.ini"]
        if FileExist(p)
            return p
    return SuiteRoot "\config\config.example.ini"
}

Cfg(section, key, default := "") {
    global ConfigCache, ConfigCachePath, ConfigCacheTime
    path := ConfigPath()
    t := ""
    try t := FileGetTime(path)
    if !IsSet(ConfigCache) || ConfigCachePath != path || ConfigCacheTime != t {
        ConfigCache := IniLoad(path)
        ConfigCachePath := path
        ConfigCacheTime := t
    }
    k := section "." key
    return ConfigCache.Has(k) && ConfigCache[k] != "" ? ConfigCache[k] : default
}

CfgBool(section, key, default := false) {
    v := StrLower(Cfg(section, key, default ? "1" : "0"))
    return v = "1" || v = "true" || v = "yes"
}

; Surgical config write: replaces the key's line inside its section (or
; appends it) so user comments and layout survive.
CfgSet(section, key, value) {
    path := SuiteRoot "\config.local.ini"
    content := ""
    try content := FileRead(path)
    lines := StrSplit(content, "`n", "`r")
    out := []
    curSection := ""
    replaced := false
    sectionEnd := 0
    for line in lines {
        t := Trim(line)
        if SubStr(t, 1, 1) = "[" && SubStr(t, -1) = "]" {
            if curSection = section && !replaced {
                out.InsertAt(sectionEnd + 1, key "=" value)
                replaced := true
            }
            curSection := SubStr(t, 2, StrLen(t) - 2)
        } else if curSection = section && !replaced {
            pos := InStr(t, "=")
            if pos && Trim(SubStr(t, 1, pos - 1)) = key {
                line := key "=" value
                replaced := true
            }
        }
        out.Push(line)
        if Trim(line) != ""
            sectionEnd := out.Length
    }
    if !replaced {
        if curSection != section {
            out.Push("")
            out.Push("[" section "]")
        }
        out.Push(key "=" value)
    }
    text := ""
    for line in out
        text .= line "`n"
    f := FileOpen(path, "w")
    f.Write(RTrim(text, "`n") "`n")
    f.Close()
    global ConfigCacheTime := ""  ; force reload
}

; ------------------------------------------------------------- state files

StateGet(file, key, default := "") {
    data := IniLoad(SuiteRoot "\.state\" file)
    k := "State." key
    return data.Has(k) && data[k] != "" ? data[k] : default
}

StateSet(file, key, value) {
    DirCreate SuiteRoot "\.state"
    path := SuiteRoot "\.state\" file
    data := IniLoad(path)
    data["State." key] := value
    out := "[State]`n"
    for k, v in data
        if SubStr(k, 1, 6) = "State."
            out .= SubStr(k, 7) "=" v "`n"
    f := FileOpen(path, "w")
    f.Write(out)
    f.Close()
}

StateDelete(file) {
    try FileDelete SuiteRoot "\.state\" file
}

SuiteLog(msg) {
    try {
        DirCreate SuiteRoot "\.state"
        FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", SuiteRoot "\.state\productivity.log"
    }
}

; ---------------------------------------------------------- window helpers

SnapshotWindows(winTitle) {
    seen := Map()
    for hwnd in WinGetList(winTitle)
        seen[hwnd] := true
    return seen
}

; Returns the first window of winTitle not present in `before`, preferring
; one whose title contains `needle`. 0 on timeout.
WaitNewWindow(winTitle, before, needle := "", timeoutMs := 30000, excludeClass := "") {
    deadline := A_TickCount + timeoutMs
    fallback := 0
    while A_TickCount < deadline {
        for hwnd in WinGetList(winTitle) {
            if before.Has(hwnd)
                continue
            if excludeClass != "" && WindowHasClass(hwnd, excludeClass)
                continue
            if needle = ""
                return hwnd
            title := ""
            try title := WinGetTitle("ahk_id " hwnd)
            if InStr(title, needle)
                return hwnd
            if !fallback
                fallback := hwnd
        }
        Sleep 250
    }
    return fallback
}

WindowHasClass(hwnd, cls) {
    c := ""
    try c := WinGetClass("ahk_id " hwnd)
    return c = cls
}

MoveWindowTo(hwnd, x, y, w, h) {
    if !hwnd || !WinExist("ahk_id " hwnd)
        return
    if WinGetMinMax("ahk_id " hwnd) != 0
        WinRestore "ahk_id " hwnd
    WinMove x, y, w, h, "ahk_id " hwnd
}

; Positions a window so its VISIBLE frame fills the target rectangle.
; GetWindowRect includes invisible resize borders, so a plain WinMove
; leaves gaps; compensate with the DWM extended frame bounds, like Snap.
MoveWindowVisible(hwnd, x, y, w, h) {
    MoveWindowTo(hwnd, x, y, w, h)
    if !hwnd || !WinExist("ahk_id " hwnd)
        return
    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rect)
        return
    ext := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", ext, "uint", 16, "uint")
        return  ; DWMWA_EXTENDED_FRAME_BOUNDS unsupported; keep plain placement
    il := NumGet(ext, 0, "int") - NumGet(rect, 0, "int")
    it := NumGet(ext, 4, "int") - NumGet(rect, 4, "int")
    ir := NumGet(rect, 8, "int") - NumGet(ext, 8, "int")
    ib := NumGet(rect, 12, "int") - NumGet(ext, 12, "int")
    if il || it || ir || ib
        WinMove x - il, y - it, w + il + ir, h + it + ib, "ahk_id " hwnd
}

; Closes hwnd only if it still exists and belongs to an expected executable.
SafeCloseWindow(hwnd, expectedExes) {
    if !hwnd || !WinExist("ahk_id " hwnd)
        return
    exe := ""
    try exe := WinGetProcessName("ahk_id " hwnd)
    match := false
    for e in expectedExes
        if StrLower(exe) = StrLower(e)
            match := true
    if !match
        return
    try WinClose "ahk_id " hwnd, , 5
}

FileUrl(path) {
    p := StrReplace(path, "\", "/")
    p := StrReplace(p, " ", "%20")
    return SubStr(p, 1, 2) = "//" ? "file:" p : "file:///" p
}

; ---------------------------------------------------------- chrome helpers

IsChromeExe(path) {
    if path = "" || !FileExist(path)
        return false
    SplitPath path, &name
    return StrLower(name) = "chrome.exe"
}

; Override path first, then common install dirs, then App Paths registry.
LocateChrome(override := "") {
    if IsChromeExe(override)
        return override
    for p in [EnvGet("LOCALAPPDATA") "\Google\Chrome\Application\chrome.exe",
              EnvGet("ProgramFiles") "\Google\Chrome\Application\chrome.exe",
              EnvGet("ProgramFiles(x86)") "\Google\Chrome\Application\chrome.exe"]
        if IsChromeExe(p)
            return p
    for key in ["SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
                "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"]
        for hive in ["HKCU", "HKLM"] {
            p := ""
            try p := RegRead(hive "\" key)
            if IsChromeExe(p)
                return p
        }
    return ""
}

; Visible, unowned top-level chrome.exe windows; preferred = the main
; Chrome_WidgetWin_1 class. PIDs cannot identify Chromium windows because
; the browser shares processes across windows.
ChromeWindowCandidates() {
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

SnapshotChromeWindows() {
    seen := Map()
    for c in ChromeWindowCandidates()
        seen[c.hwnd] := true
    return seen
}

; First candidate window that appeared after a launch, preferring the main
; class. 0 on timeout.
WaitNewChromeWindow(before, timeoutMs := 15000) {
    deadline := A_TickCount + timeoutMs
    while A_TickCount < deadline {
        fallback := 0
        for c in ChromeWindowCandidates() {
            if before.Has(c.hwnd)
                continue
            if c.preferred
                return c.hwnd
            if !fallback
                fallback := c.hwnd
        }
        if fallback
            return fallback
        Sleep 100
    }
    return 0
}

; UTC "yyyyMMddHHmmss" timestamps; AHK date math handles the rest.
UtcNow() {
    return A_NowUTC
}

UtcToLocal(utcStamp) {
    offset := DateDiff(A_Now, A_NowUTC, "Seconds")
    return DateAdd(utcStamp, offset, "Seconds")
}

; Human-readable label for an AutoHotkey hotkey string, e.g. ^!m -> Ctrl+Alt+M.
HotkeyLabel(hk) {
    label := ""
    i := 1
    while i <= StrLen(hk) {
        c := SubStr(hk, i, 1)
        switch c {
            case "^": label .= "Ctrl+"
            case "!": label .= "Alt+"
            case "+": label .= "Shift+"
            case "#": label .= "Win+"
            case "<", ">", "*", "~", "$":  ; prefix modifiers with no display form
            default:
                key := SubStr(hk, i)
                return label (StrLen(key) = 1 ? StrUpper(key) : key)
        }
        i++
    }
    return label
}

; "today at HH:mm:ss" for same-day local moments, else full date.
FormatMoment(utcStamp, missing) {
    if utcStamp = ""
        return missing
    localTs := UtcToLocal(utcStamp)
    if FormatTime(localTs, "yyyyMMdd") = FormatTime(, "yyyyMMdd")
        return "today at " FormatTime(localTs, "HH:mm:ss")
    return FormatTime(localTs, "yyyy-MM-dd HH:mm:ss")
}
