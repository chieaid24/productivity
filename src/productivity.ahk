#Requires AutoHotkey v2.0
#SingleInstance Force

; Productivity: a single tray app bundling four services in one process -
; the reminder timer (headline), Morning Dashboard, Focus Switcher, and
; CC Usage Tracker. Each service can be disabled and configured from the
; tray menu; everything persists in one gitignored config.local.ini.

; Per-monitor DPI awareness so work-area math matches physical pixels on
; mixed-DPI monitor setups. Best effort on older Windows builds.
try DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

SplitPath A_ScriptDir, , &suiteRoot
global SuiteRoot := suiteRoot

#Include lib\common.ahk
#Include lib\toast.ahk
#Include services\timer.ahk
#Include services\dashboard.ahk
#Include services\focus.ahk
#Include services\usage.ahk

Persistent
try DllCall("shell32\SetCurrentProcessExplicitAppUserModelID", "wstr", PT_AppId)

SuiteSetupTray()
PT_Init()
MD_Init()
FS_Init()
UT_Init()
SuiteHandleArgs()
return

; -------------------------------------------------------------------- tray

SuiteSetupTray() {
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Pause reminders", (*) => PT_Toggle())
    tray.Add("Timer settings...", PT_OpenSettings)
    tray.Add()
    mdMenu := Menu(), fsMenu := Menu(), utMenu := Menu()
    MD_BuildMenu(mdMenu)
    FS_BuildMenu(fsMenu)
    UT_BuildMenu(utMenu)
    tray.Add("Morning Dashboard", mdMenu)
    tray.Add("Focus Switcher", fsMenu)
    tray.Add("CC Usage Tracker", utMenu)
    tray.Add()
    tray.Add("Open config file", (*) => SuiteOpenConfig())
    tray.Add("Reload", (*) => Reload())
    tray.Add("Exit (until next login)", (*) => ExitApp())
    tray.Default := "Pause reminders"
}

; ---------------------------------------------------------------- services

; Enabled flags live in .state\services.ini so config.local.ini stays a
; purely user-edited file. Missing flag means enabled.
SuiteServiceEnabled(key) {
    return StateGet("services.ini", key, "1") = "1"
}

SuiteSetServiceFlag(key, on) {
    StateSet("services.ini", key, on ? "1" : "0")
}

SuiteToggleService(key) {
    on := !SuiteServiceEnabled(key)
    SuiteSetServiceFlag(key, on)
    switch key {
        case "Dashboard": MD_SetEnabled(on)
        case "FocusSwitcher": FS_SetEnabled(on)
        case "UsageTracker": UT_SetEnabled(on)
    }
}

SuiteOpenConfig() {
    path := SuiteRoot "\config.local.ini"
    if !FileExist(path)
        try FileCopy SuiteRoot "\config\config.example.ini", path
    try Run 'notepad.exe "' path '"'
}

; ------------------------------------------------------------ command line

; Testing/automation hooks; the daemon keeps running afterwards.
SuiteHandleArgs() {
    if !A_Args.Length
        return
    switch StrLower(A_Args[1]) {
        case "timer":
            if A_Args.Length > 1 {
                switch StrLower(A_Args[2]) {
                    case "fire": PT_Fire()
                    case "toggle": PT_Toggle()
                }
            }
        case "dashboard":
            if A_Args.Length > 1 {
                switch StrLower(A_Args[2]) {
                    case "open": MD_Guard(MD_Open)
                    case "close": MD_Guard(MD_Close)
                    case "toggle": MD_Guard(MD_Toggle)
                }
            }
        case "usage":
            if A_Args.Length > 1 {
                switch StrLower(A_Args[2]) {
                    case "open": UT_Open()
                    case "close": UT_Close()
                    case "toggle": UT_Toggle()
                }
            }
    }
}
