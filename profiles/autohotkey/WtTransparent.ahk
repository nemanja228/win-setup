#Requires AutoHotkey v2.0
#SingleInstance Force

; =============================================================================
; WtTransparent.ahk — toggle window transparency via global hotkeys.
;
; Managed by win-setup. Deployed by scripts/Install-Profiles.ps1, auto-launched
; on logon via a shortcut in the Startup folder.
;
; Hotkeys (work on whatever window has focus — "A" = active):
;   Ctrl + Shift + ]    Toggle current window between TLevel and OFF
;   Ctrl + Win + =      Increase opacity by 10 (more opaque)
;   Ctrl + Win + -      Decrease opacity by 10 (more transparent)
;
; TLevel default 210 (out of 255). Adjust the assignment below to taste.
; =============================================================================

SendMode "Input"
SetWorkingDir A_ScriptDir

TLevel := 210

^+]:: {
    global TLevel
    current := WinGetTransparent("A")
    if (current = "") {
        ; "" means transparency is OFF — apply the saved level.
        WinSetTransparent(TLevel, "A")
    } else {
        WinSetTransparent("OFF", "A")
    }
}

#^=:: {
    global TLevel
    TLevel += 10
    if (TLevel > 255) {
        TLevel := 255
    }
    SetTransparency()
}

#^-:: {
    global TLevel
    TLevel -= 10
    if (TLevel < 0) {
        TLevel := 0
    }
    SetTransparency()
}

SetTransparency() {
    global TLevel
    WinSetTransparent(TLevel, "A")
}
