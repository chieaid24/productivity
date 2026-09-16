; Reminder timer: the suite's headline service. Interval toasts with the
; same pause/resume semantics as the original Productivity Timer: pausing
; keeps the pending trigger, resuming continues it if still ahead, and an
; interval change restarts the countdown.

global PT_AppId := "Chieaid24.Productivity"
global PT_Running := false
global PT_NextTrigger := ""      ; UTC yyyyMMddHHmmss while scheduled
global PT_PendingNext := ""      ; kept across a pause
global PT_LastTriggered := ""
global PT_MenuRef := 0
global PT_SettingsGui := 0

PT_BuildMenu(m) {
    global PT_MenuRef := m
    m.Add("Enabled", (*) => PT_Toggle())
    if SuiteServiceEnabled("Timer")
        m.Check("Enabled")
    m.Add()
    m.Add("Settings...", PT_OpenSettings)
}

PT_Init() {
    global PT_LastTriggered, PT_Running
    PT_LastTriggered := StateGet("timer.ini", "LastTriggered")
    PT_Running := false
    if SuiteServiceEnabled("Timer")
        PT_Resume()
    else
        PT_UpdateUi()
}

PT_IntervalMinutes() {
    v := Cfg("Timer", "IntervalMinutes", "20")
    n := IsInteger(v) ? Integer(v) : 20
    return Min(1440, Max(1, n))
}

PT_Schedule(seconds) {
    global PT_NextTrigger
    PT_NextTrigger := DateAdd(UtcNow(), seconds, "Seconds")
    SetTimer PT_Fire, -Max(1000, seconds * 1000)
}

PT_Resume() {
    global PT_Running, PT_PendingNext
    if PT_Running
        return
    PT_Running := true
    ; Continue a pending trigger that is still ahead; otherwise start fresh.
    if PT_PendingNext != "" {
        remaining := DateDiff(PT_PendingNext, UtcNow(), "Seconds")
        PT_PendingNext := ""
        if remaining > 0 {
            PT_Schedule(remaining)
            PT_UpdateUi()
            return
        }
    }
    PT_Schedule(PT_IntervalMinutes() * 60)
    PT_UpdateUi()
}

PT_Pause() {
    global PT_Running, PT_PendingNext, PT_NextTrigger
    if !PT_Running
        return
    PT_Running := false
    SetTimer PT_Fire, 0
    PT_PendingNext := PT_NextTrigger
    PT_NextTrigger := ""
    PT_UpdateUi()
}

PT_Toggle() {
    if PT_Running {
        PT_Pause()
        SuiteSetServiceFlag("Timer", false)
    } else {
        PT_Resume()
        SuiteSetServiceFlag("Timer", true)
    }
}

PT_Fire() {
    global PT_LastTriggered, PT_Running
    try PT_Notify()
    catch as err
        SuiteLog("timer: notification failed: " err.Message)
    else {
        PT_LastTriggered := UtcNow()
        StateSet("timer.ini", "LastTriggered", PT_LastTriggered)
    }
    if PT_Running
        PT_Schedule(PT_IntervalMinutes() * 60)
    PT_UpdateUi()
}

PT_Notify() {
    message := Cfg("Timer", "Message", "Water, breathe, flat, posture")
    sound := StrLower(Cfg("Timer", "Sound", "default"))
    static sources := Map(
        "default", "ms-winsoundevent:Notification.Default",
        "reminder", "ms-winsoundevent:Notification.Reminder",
        "mail", "ms-winsoundevent:Notification.Mail",
        "instant_message", "ms-winsoundevent:Notification.IM",
        "text_message", "ms-winsoundevent:Notification.SMS")
    if sound = "silent" {
        ToastShow(PT_AppId, message, "silent")
    } else if sound = "custom" {
        ; Unpackaged toasts cannot reference file: audio; play the WAV directly.
        ToastShow(PT_AppId, message, "silent")
        wav := Cfg("Timer", "CustomSound")
        if wav != "" && FileExist(wav)
            try SoundPlay wav
    } else {
        src := sources.Has(sound) ? sources[sound] : sources["default"]
        ToastShow(PT_AppId, message, src)
    }
}

PT_UpdateUi() {
    if PT_MenuRef {
        if PT_Running {
            try PT_MenuRef.Check("Enabled")
        } else {
            try PT_MenuRef.Uncheck("Enabled")
        }
    }
    icon := SuiteRoot "\assets\" (PT_Running ? "productivity-running.ico" : "productivity-paused.ico")
    try TraySetIcon(icon, , true)
    last := FormatMoment(PT_LastTriggered, "never")
    next := PT_Running ? FormatMoment(PT_NextTrigger, "paused") : "paused"
    A_IconTip := "Productivity`nLast: " last "`nNext: " next
}

; ------------------------------------------------------------ settings gui

PT_OpenSettings(*) {
    global PT_SettingsGui
    if PT_SettingsGui {
        try {
            PT_SettingsGui.Show()  ; already built and open; just focus it
            return
        }
        PT_SettingsGui := 0
    }
    g := Gui("+AlwaysOnTop -MinimizeBox", "Productivity settings")
    g.SetFont("s10")
    g.AddText("xm y+12 w110", "Break interval")
    edInterval := g.AddEdit("x+8 yp-3 w70 Number", PT_IntervalMinutes())
    g.AddUpDown("Range1-1440", PT_IntervalMinutes())
    g.AddText("x+6 yp+3", "minutes")
    g.AddText("xm y+16 w110", "Message")
    edMessage := g.AddEdit("x+8 yp-3 w300 r4 Multi", Cfg("Timer", "Message", "Water, breathe, flat, posture"))
    g.AddText("xm y+16 w110", "Sound")
    static labels := ["Windows default", "Reminder", "Mail", "Instant message", "Text message", "Silent", "Custom WAV"]
    static values := ["default", "reminder", "mail", "instant_message", "text_message", "silent", "custom"]
    current := StrLower(Cfg("Timer", "Sound", "default"))
    sel := 1
    for i, v in values
        if v = current
            sel := i
    ddSound := g.AddDropDownList("x+8 yp-3 w200 Choose" sel, labels)
    txtWav := g.AddText("xm y+16 w110", "WAV file")
    edWav := g.AddEdit("x+8 yp-3 w220 ReadOnly", Cfg("Timer", "CustomSound"))
    btnBrowse := g.AddButton("x+6 yp w76", "Browse...")
    btnBrowse.OnEvent("Click", (*) => PT_BrowseWav(edWav, g))
    btnSave := g.AddButton("xm+230 y+20 w76 Default", "Save")
    btnCancel := g.AddButton("x+8 yp w76", "Cancel")

    syncWav := (*) => (PT_ShowWavRow(txtWav, edWav, btnBrowse, values[ddSound.Value] = "custom"))
    ddSound.OnEvent("Change", syncWav)
    syncWav()

    btnSave.OnEvent("Click", (*) => PT_SaveSettings(g, edInterval, edMessage, ddSound, edWav, values))
    btnCancel.OnEvent("Click", (*) => PT_CloseSettings(g))
    g.OnEvent("Close", (*) => PT_CloseSettings(g))
    g.OnEvent("Escape", (*) => PT_CloseSettings(g))
    g.Show()
    PT_SettingsGui := g
}

PT_CloseSettings(g) {
    global PT_SettingsGui := 0
    try g.Destroy()
}

PT_ShowWavRow(txt, ed, btn, show) {
    txt.Visible := show
    ed.Visible := show
    btn.Visible := show
}

PT_BrowseWav(edWav, owner) {
    owner.Opt("+OwnDialogs")
    picked := FileSelect(1, , "Choose a notification sound", "WAV audio (*.wav)")
    if picked != ""
        edWav.Value := picked
}

PT_SaveSettings(g, edInterval, edMessage, ddSound, edWav, values) {
    interval := edInterval.Value
    message := Trim(edMessage.Value, " `t`r`n")
    sound := values[ddSound.Value]
    wav := edWav.Value
    if !IsInteger(interval) || Integer(interval) < 1 || Integer(interval) > 1440 {
        MsgBox "Interval must be between 1 and 1440 minutes.", "Could not save settings", "Iconx Owner" g.Hwnd
        return
    }
    if message = "" || StrLen(message) > 500 {
        MsgBox "Message must be 1 to 500 characters.", "Could not save settings", "Iconx Owner" g.Hwnd
        return
    }
    if sound = "custom" && (wav = "" || !FileExist(wav) || StrLower(SubStr(wav, -4)) != ".wav") {
        MsgBox "Choose an existing custom WAV file.", "Could not save settings", "Iconx Owner" g.Hwnd
        return
    }
    previousInterval := PT_IntervalMinutes()
    CfgSet("Timer", "IntervalMinutes", Integer(interval))
    CfgSet("Timer", "Message", message)
    CfgSet("Timer", "Sound", sound)
    CfgSet("Timer", "CustomSound", wav)
    ; Interval change restarts the countdown while running.
    if Integer(interval) != previousInterval && PT_Running {
        global PT_PendingNext := ""
        SetTimer PT_Fire, 0
        PT_Schedule(Integer(interval) * 60)
        PT_UpdateUi()
    }
    PT_CloseSettings(g)
}
