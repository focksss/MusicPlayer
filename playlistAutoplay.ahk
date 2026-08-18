#Requires AutoHotkey v2.0
#SingleInstance Force

;@Ahk2Exe-SetMainIcon player.ico
;@Ahk2Exe-ExeName PlaylistPlayer.exe

STATE_FILE := A_ScriptDir "\state.ini"

player := ComObject("WMPlayer.OCX")
playlist := player.newPlaylist("AHK_Playlist", "")

loopEnabled := false
currentFolder := ""
lastTitle := ""

restorePosition := -1
restorePaused := false
restoring := false

volume := 100

progressDragging := false

myGui := Gui("-AlwaysOnTop", "AHK Playlist Player")
myGui.SetFont("s10", "Segoe UI")

myGui.AddText("xm y15", "Folder:")
folderText := myGui.AddText("x65 y15 w400", "No folder selected")
myGui.AddButton("x350 y10 w100", "Choose Folder")
    .OnEvent("Click", ChooseFolder)
myGui.AddButton("x480 y10 w100", "Open Script Dir")
    .OnEvent("Click", OpenScriptDir)
myGui.AddText("xm y55", "Now Playing:")
titleText := myGui.AddText("x105 y55 w475", "Nothing playing")

progressSlider := myGui.AddSlider(
    "xm y85 w500 h25 Range0-1000 ToolTip",
    0
)

progressSlider.OnEvent("Change", ProgressChanged)

progressTimeText := myGui.AddText(
    "x510 y88 w90",
    "0:00 / 0:00"
)

prevBtn := myGui.AddButton(
    "x75 y120 w105 h35",
    "Previous"
)

playBtn := myGui.AddButton(
    "x190 y120 w110 h35",
    "Play"
)

nextBtn := myGui.AddButton(
    "x310 y120 w105 h35",
    "Next"
)

loopBtn := myGui.AddButton(
    "x425 y120 w105 h35",
    "Loop: OFF"
)

prevBtn.OnEvent("Click", PreviousSong)
playBtn.OnEvent("Click", PlayPause)
nextBtn.OnEvent("Click", NextSong)
loopBtn.OnEvent("Click", ToggleLoop)

myGui.AddText("xm y165", "Volume:")

volumeSlider := myGui.AddSlider(
    "x75 y160 w400 h25 Range0-100 ToolTip",
    volume
)

volumeSlider.OnEvent("Change", VolumeChanged)

volumeText := myGui.AddText(
    "x485 y165 w60",
    volume "%"
)

statusText := myGui.AddText(
    "xm y195 w575",
    "Select a folder to begin."
)

myGui.OnEvent("Close", ExitPlayer)

windowX := IniRead(STATE_FILE, "Window", "X", "")
windowY := IniRead(STATE_FILE, "Window", "Y", "")

if (windowX != "" && windowY != "") {
    try {
        myGui.Show(
            "x" windowX
            " y" windowY
            " w600 h225"
        )
    } catch {
        myGui.Show("w600 h225")
    }
} else {
    myGui.Show("w600 h225")
}

savedVolume := IniRead(
    STATE_FILE,
    "Player",
    "Volume",
    "100"
)

try {
    volume := Integer(savedVolume)
} catch {
    volume := 100
}

if (volume < 0)
    volume := 0

if (volume > 100)
    volume := 100

volumeSlider.Value := volume
volumeText.Text := volume "%"

try player.settings.volume := volume

; WM_LBUTTONDOWN
OnMessage(0x0201, MouseLeftDown)
; WM_LBUTTONUP
OnMessage(0x0202, MouseLeftUp)
; WM_MOUSEWHEEL
OnMessage(0x020A, MouseWheel)

SetTimer(UpdatePlayerStatus, 250)
SetTimer(SaveState, 2000)

LoadSavedState()

ChooseFolder(*) {
    global currentFolder

    selected := DirSelect(
        ,
        3,
        "Select a folder containing music"
    )

    if !selected
        return

    currentFolder := selected

    LoadFolder(currentFolder, false)
}
LoadFolder(folder, restoreSaved := false) {
    global player, playlist
    global titleText, folderText, statusText, playBtn
    global restorePosition, restorePaused, restoring
    global loopEnabled, loopBtn
    global progressSlider, progressTimeText

    restoring := restoreSaved

    try player.controls.stop()

    playlist := player.newPlaylist(
        "AHK_Playlist",
        ""
    )

    fileCount := 0

    Loop Files, folder "\*.*" {
        ext := StrLower(A_LoopFileExt)

        if (
            ext = "mp3"
            || ext = "wav"
            || ext = "m4a"
        ) {
            try {
                mediaItem := player.newMedia(
                    A_LoopFileFullPath
                )

                playlist.appendItem(mediaItem)
                fileCount++
            }
        }
    }

    displayFolder := folder
    if (InStr(displayFolder, A_ScriptDir) = 1) {
        displayFolder := SubStr(
            displayFolder,
            StrLen(A_ScriptDir) + 1
        )

        if (displayFolder = "")
            displayFolder := "\"
    }
    folderText.Text := displayFolder

    progressSlider.Value := 0
    progressTimeText.Text := "0:00 / 0:00"

    if (fileCount = 0) {
        titleText.Text := "Nothing playing"
        statusText.Text :=
            "No MP3, WAV, or M4A files found."

        playBtn.Text := "Play"
        restoring := false
        return
    }

    player.currentPlaylist := playlist

    if restoreSaved {
        RestoreSavedSong()
    } else {
        player.controls.play()

        playBtn.Text := "Pause"
        statusText.Text :=
            fileCount " song(s) loaded."
    }

    try player.settings.setMode(
        "loop",
        loopEnabled
    )

    if loopEnabled
        loopBtn.Text := "Loop: ON"
    else
        loopBtn.Text := "Loop: OFF"
}
OpenScriptDir(*) {
    Run('explorer.exe "' A_ScriptDir '"')
}

RestoreSavedSong() {
    global player, playlist
    global savedTitle
    global titleText, statusText
    global restoring

    if !savedTitle {
        player.controls.play()
        restoring := false
        return
    }

    found := false

    Loop playlist.count {
        index := A_Index - 1

        try {
            item := playlist.item(index)
            itemName := item.name

            if (itemName = savedTitle) {
                player.controls.playItem(item)

                titleText.Text := itemName
                statusText.Text :=
                    "Restoring playback..."

                found := true
                break
            }
        }
    }

    if !found {
        statusText.Text :=
            "Previous song not found. Starting playlist."

        player.controls.play()
        restoring := false
        return
    }

    SetTimer(FinishRestore, 100)
}
FinishRestore() {
    global player
    global restorePosition, restorePaused
    global restoring
    global playBtn, statusText

    try {
        if !player.currentMedia || player.playState == 9 || player.playState == 6
            return

        duration := player.currentMedia.duration

        if (
            restorePosition >= 0
            && duration > 0
        ) {
            if (restorePosition > duration - 1)
                restorePosition := duration - 1

            if (restorePosition < 0)
                restorePosition := 0

            try player.controls.currentPosition :=
                restorePosition
        }

        if restorePaused {
            try player.controls.pause()

            playBtn.Text := "Play"
            statusText.Text := "Paused"
        } else {
            try player.controls.play()

            playBtn.Text := "Pause"
            statusText.Text := "Playing"
        }

        restoring := false

        SetTimer(FinishRestore, 0)
    }
}

PlayPause(*) {
    global player, playlist, playBtn

    if (playlist.count = 0)
        return

    if (player.playState = 3) {
        player.controls.pause()
        playBtn.Text := "Play"
    } else {
        player.controls.play()
        playBtn.Text := "Pause"
    }
}

PreviousSong(*) {
    global player, playlist

    if (playlist.count = 0)
        return

    try player.controls.previous()
}

NextSong(*) {
    global player, playlist

    if (playlist.count = 0)
        return

    try player.controls.next()
}

ToggleLoop(*) {
    global player
    global loopEnabled, loopBtn

    loopEnabled := !loopEnabled

    try player.settings.setMode(
        "loop",
        loopEnabled
    )

    if loopEnabled
        loopBtn.Text := "Loop: ON"
    else
        loopBtn.Text := "Loop: OFF"
}

ProgressChanged(*) {
    global player
    global progressSlider
    global progressDragging
    global restoring

    if restoring
        return

    if !progressDragging
        return

    try {
        if !player.currentMedia
            return

        duration := player.currentMedia.duration

        if (duration <= 0)
            return

        newPosition :=
            (progressSlider.Value / 1000) * duration

        player.controls.currentPosition :=
            newPosition
    }
}
VolumeChanged(*) {
    global player
    global volumeSlider, volumeText
    global volume

    volume := volumeSlider.Value

    volumeText.Text := volume "%"

    try player.settings.volume := volume
}

MouseLeftDown(wParam, lParam, msg, hwnd) {
    global progressSlider
    global progressDragging

    MouseGetPos(
        ,
        ,
        ,
        &controlHwnd
    )

    if (controlHwnd = progressSlider.Hwnd) {
        progressDragging := true
    }
}
MouseLeftUp(wParam, lParam, msg, hwnd) {
    global progressSlider
    global progressDragging
    global player

    if !progressDragging
        return

    progressDragging := false

    try {
        if !player.currentMedia
            return

        duration := player.currentMedia.duration

        if (duration <= 0)
            return

        newPosition :=
            (progressSlider.Value / 1000) * duration

        player.controls.currentPosition :=
            newPosition
    }
}
MouseWheel(wParam, lParam, msg, hwnd) {
    global progressSlider
    global volumeSlider
    global player

    MouseGetPos(,,,&controlHwnd) ; ?

    if (controlHwnd = progressSlider.Hwnd) {
        try {
            if !player.currentMedia
                return

            duration := player.currentMedia.duration

            if (duration <= 0)
                return

            currentPosition :=
                player.controls.currentPosition

            wheelDelta := GetWheelDelta(wParam)

            newPosition :=
                currentPosition + (wheelDelta * 5)

            if (newPosition < 0)
                newPosition := 0

            if (newPosition > duration)
                newPosition := duration

            player.controls.currentPosition :=
                newPosition
        }

        return
    }

    if (controlHwnd = volumeSlider.Hwnd) {
        wheelDelta := GetWheelDelta(wParam)

        newVolume :=
            volumeSlider.Value + (wheelDelta * 5)

        if (newVolume < 0)
            newVolume := 0

        if (newVolume > 100)
            newVolume := 100

        volumeSlider.Value := newVolume
        VolumeChanged()

        return
    }
}
GetWheelDelta(wParam) {
    delta := (wParam >> 16) & 0xFFFF

    if (delta >= 0x8000)
        delta -= 0x10000

    if (delta > 0)
        return 1

    if (delta < 0)
        return -1

    return 0
}

UpdatePlayerStatus() {
    global player, playlist
    global titleText, statusText, playBtn
    global progressSlider, progressTimeText
    global progressDragging

    if (playlist.count = 0)
        return

    try {
        currentMedia := player.currentMedia

        if currentMedia {
            title := currentMedia.name

            if !title
                title := currentMedia.getItemInfo(
                    "Title"
                )

            if !title
                title := "Unknown"

            titleText.Text := title

            duration := currentMedia.duration
            position := player.controls.currentPosition

            if (
                duration > 0
                && !progressDragging
            ) {
                sliderValue :=
                    Round((position / duration) * 1000)

                if (sliderValue < 0)
                    sliderValue := 0

                if (sliderValue > 1000)
                    sliderValue := 1000

                progressSlider.Value := sliderValue
            }

            progressTimeText.Text := FormatTime(position) " / " FormatTime(duration)
        }

        if (player.playState = 3) {
            playBtn.Text := "Pause"
            statusText.Text := "Playing"
        }
        else if (player.playState = 2) {
            playBtn.Text := "Play"
            statusText.Text := "Paused"
        }
        else if (player.playState = 1) {
            playBtn.Text := "Play"
            statusText.Text := "Stopped"
        }
        else if (player.playState = 6) {
            statusText.Text := "Buffering..."
        }
        else if (player.playState = 9) {
            statusText.Text := "Preparing..."
        }
    }
}
FormatTime(seconds) {
    if (seconds < 0)
        seconds := 0

    totalSeconds := Floor(seconds)

    hours := Floor(totalSeconds / 3600)
    minutes := Floor(Mod(totalSeconds, 3600) / 60)
    secs := Mod(totalSeconds, 60)

    if (hours > 0) {
        return Format(
            "{}:{:02}:{:02}",
            hours,
            minutes,
            secs
        )
    }

    return Format(
        "{}:{:02}",
        minutes,
        secs
    )
}

SaveState(*) {
    global player, playlist
    global currentFolder, loopEnabled
    global restoring, myGui, volume

    try {
        myGui.GetPos(
            &windowX,
            &windowY,
            &windowWidth,
            &windowHeight
        )

        IniWrite(
            windowX,
            STATE_FILE,
            "Window",
            "X"
        )

        IniWrite(
            windowY,
            STATE_FILE,
            "Window",
            "Y"
        )
    }

    IniWrite(
        volume,
        STATE_FILE,
        "Player",
        "Volume"
    )

    if restoring
        return

    if (playlist.count = 0)
        return

    try {
        currentMedia := player.currentMedia

        if !currentMedia
            return

        title := currentMedia.name

        if !title
            return

        position :=
            player.controls.currentPosition

        if (player.playState = 2)
            playbackState := "paused"
        else if (player.playState = 3)
            playbackState := "playing"
        else
            playbackState := "stopped"

        IniWrite(
            currentFolder,
            STATE_FILE,
            "Player",
            "Folder"
        )

        IniWrite(
            title,
            STATE_FILE,
            "Player",
            "Song"
        )

        IniWrite(
            position,
            STATE_FILE,
            "Player",
            "Position"
        )

        IniWrite(
            playbackState,
            STATE_FILE,
            "Player",
            "State"
        )

        IniWrite(
            loopEnabled ? "1" : "0",
            STATE_FILE,
            "Player",
            "Loop"
        )
    }
}

LoadSavedState() {
    global STATE_FILE
    global currentFolder
    global savedTitle
    global restorePosition
    global restorePaused
    global loopEnabled

    if !FileExist(STATE_FILE)
        return

    savedFolder := IniRead(
        STATE_FILE,
        "Player",
        "Folder",
        ""
    )

    savedTitle := IniRead(
        STATE_FILE,
        "Player",
        "Song",
        ""
    )

    savedPosition := IniRead(
        STATE_FILE,
        "Player",
        "Position",
        "0"
    )

    savedState := IniRead(
        STATE_FILE,
        "Player",
        "State",
        "paused"
    )

    savedLoop := IniRead(
        STATE_FILE,
        "Player",
        "Loop",
        "0"
    )

    if !savedFolder
        return

    if !DirExist(savedFolder)
        return

    currentFolder := savedFolder

    try {
        restorePosition := Float(savedPosition)
    } catch {
        restorePosition := 0
    }

    restorePaused := (savedState != "playing")
    loopEnabled := (savedLoop = "1")

    LoadFolder(
        savedFolder,
        true
    )
}

ExitPlayer(*) {
    global player

    SaveState()

    SetTimer(UpdatePlayerStatus, 0)
    SetTimer(SaveState, 0)
    SetTimer(FinishRestore, 0)

    try player.controls.stop()

    ExitApp
}