; Native WinRT toast notifications (no helper processes). The AUMID must be
; registered under HKCU\Software\Classes\AppUserModelId or Windows silently
; drops the toast; the installer writes that key.

; sound: "" or ms-winsoundevent name for <audio src>, "silent" for a muted
; toast. Callers handle custom WAV files themselves (silent toast + SoundPlay)
; because unpackaged apps cannot use file: URIs in toast audio.
ToastShow(appId, message, sound := "") {
    xml := "<toast><visual><binding template=`"ToastText01`">"
        . "<text id=`"1`">" ToastEscapeXml(message) "</text>"
        . "</binding></visual>"
    if sound = "silent"
        xml .= "<audio silent=`"true`"/>"
    else if sound != ""
        xml .= "<audio src=`"" sound "`"/>"
    xml .= "</toast>"

    static inited := false
    if !inited {
        DllCall("combase\RoInitialize", "uint", 1, "uint")
        inited := true
    }

    hDocCls := ToastHString("Windows.Data.Xml.Dom.XmlDocument")
    hToastCls := ToastHString("Windows.UI.Notifications.ToastNotification")
    hMgrCls := ToastHString("Windows.UI.Notifications.ToastNotificationManager")
    hXml := ToastHString(xml)
    hApp := ToastHString(appId)
    insp := docIO := doc := factory := toast := mgr := notifier := 0
    try {
        DllCall("combase\RoActivateInstance", "ptr", hDocCls, "ptr*", &insp, "uint")
        ComCall(0, insp, "ptr", ToastGuid("{6CD0E74E-EE65-4489-9EBF-CA43E87BA637}"), "ptr*", &docIO)   ; IXmlDocumentIO
        ComCall(6, docIO, "ptr", hXml)                                                                 ; LoadXml
        ComCall(0, insp, "ptr", ToastGuid("{F7F3A506-1E87-42D6-BCFB-B8C809FA5494}"), "ptr*", &doc)     ; IXmlDocument

        DllCall("combase\RoGetActivationFactory", "ptr", hToastCls
            , "ptr", ToastGuid("{04124B20-82C6-4229-B109-FD9ED4662B53}"), "ptr*", &factory, "uint")    ; IToastNotificationFactory
        ComCall(6, factory, "ptr", doc, "ptr*", &toast)                                                ; CreateToastNotification

        DllCall("combase\RoGetActivationFactory", "ptr", hMgrCls
            , "ptr", ToastGuid("{50AC103F-D235-4598-BBEF-98FE4D1A3AD4}"), "ptr*", &mgr, "uint")        ; IToastNotificationManagerStatics
        ComCall(7, mgr, "ptr", hApp, "ptr*", &notifier)                                                ; CreateToastNotifierWithId
        ComCall(6, notifier, "ptr", toast)                                                             ; Show
    } finally {
        for p in [notifier, mgr, toast, factory, doc, docIO, insp]
            if p
                ObjRelease(p)
        for h in [hDocCls, hToastCls, hMgrCls, hXml, hApp]
            DllCall("combase\WindowsDeleteString", "ptr", h, "uint")
    }
}

ToastHString(s) {
    h := 0
    DllCall("combase\WindowsCreateString", "wstr", s, "uint", StrLen(s), "ptr*", &h, "uint")
    return h
}

ToastGuid(str) {
    buf := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "wstr", str, "ptr", buf, "uint")
    return buf
}

ToastEscapeXml(s) {
    s := StrReplace(s, "&", "&amp;")
    s := StrReplace(s, "<", "&lt;")
    s := StrReplace(s, ">", "&gt;")
    s := StrReplace(s, '"', "&quot;")
    return StrReplace(s, "'", "&apos;")
}
