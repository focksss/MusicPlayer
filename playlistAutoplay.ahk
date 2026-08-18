#Requires AutoHotkey v2.0
#SingleInstance Force

;@Ahk2Exe-SetMainIcon player.ico
;@Ahk2Exe-ExeName PlaylistPlayer.exe

STATE_FILE := A_ScriptDir "\state.ini"
DEFAULT_STACHER_PATH := "C:\Users\" A_UserName "\AppData\Local\Stacher7\Stacher7.exe"

player := ComObject("WMPlayer.OCX")
playlist := player.newPlaylist("AHK_Playlist", "")

winWidth := 1000
winHeight := 225

loopEnabled := false
currentFolder := ""
lastTitle := ""

restorePosition := -1
restorePaused := false
restoring := false

volume := 100

myGui := Gui("-AlwaysOnTop", "AHK Playlist Player")
myGui.SetFont("s10", "Segoe UI")

playlistView := myGui.AddListView(
    "x710 y10 w280 h200 -Hdr -Multi",
    ["Playlist"]
)
playlistView.ModifyCol(1, 260)
playlistView.OnEvent("ItemSelect", PlaylistSongSelected)
playlistSyncing := false

myGui.AddText("xm y15", "Folder:")
folderText := myGui.AddText("x65 y15 w400", "No folder selected")

myGui.AddButton("x600 y10 w100 h30", "Choose Folder")
    .OnEvent("Click", ChooseFolder)
myGui.AddButton("x600 y50 w100 h30", "Open Script Dir")
    .OnEvent("Click", OpenScriptDir)
myGui.AddButton("x600 y90 w100 h30", "Open Stacher")
    .OnEvent("Click", OpenStached)
myGui.AddButton("x600 y130 w100 h30", "Set Stacher Path")
    .OnEvent("Click", RemapStached)

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

myGui.AddButton("x75 y120 w105 h35", "Previous")
    .OnEvent("Click", PreviousSong)
myGui.AddButton( "x310 y120 w105 h35", "Next")
    .OnEvent("Click", NextSong)
playBtn := myGui.AddButton(
    "x190 y120 w110 h35",
    "Play"
)
loopBtn := myGui.AddButton(
    "x425 y120 w105 h35",
    "Loop: OFF"
)
playBtn.OnEvent("Click", PlayPause)
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

; --- Fix: reverse the (backwards) default mouse-wheel direction on sliders ---
; AHK's Slider control has its own built-in WM_MOUSEWHEEL handling for
; horizontal sliders, and its direction convention feels inverted (scrolling
; up/forward decreases the value). We intercept the message ourselves,
; apply the value change in the direction users actually expect, and
; return a non-empty value so AHK's own (reversed) handling never runs.
OnMessage(0x020A, OnSliderMouseWheel)  ; WM_MOUSEWHEEL

OnSliderMouseWheel(wParam, lParam, msg, hwnd) {
    global progressSlider, volumeSlider

    guiCtrl := ""
    try guiCtrl := GuiCtrlFromHwnd(hwnd)

    if !guiCtrl
        return

    if (guiCtrl != progressSlider && guiCtrl != volumeSlider)
        return

    delta := (wParam >> 16) & 0xFFFF
    if (delta > 32767)
        delta -= 65536

    isProgress := (guiCtrl = progressSlider)
    step := isProgress ? 20 : 2
    maxVal := isProgress ? 1000 : 100

    newVal := guiCtrl.Value + (delta > 0 ? step : -step)

    if (newVal < 0)
        newVal := 0
    if (newVal > maxVal)
        newVal := maxVal

    guiCtrl.Value := newVal

    ; Setting .Value programmatically doesn't fire OnEvent("Change"),
    ; so trigger the corresponding logic ourselves.
    if isProgress
        ProgressChanged()
    else
        VolumeChanged()

    return 0
}

windowX := IniRead(STATE_FILE, "Window", "X", "")
windowY := IniRead(STATE_FILE, "Window", "Y", "")

if (windowX != "" && windowY != "") {
    try {
        myGui.Show(
            "x" windowX
            " y" windowY
            " w" winWidth
            " h" winHeight
        )
    } catch {
        myGui.Show("w" winWidth " h" winHeight)
    }
} else {
    myGui.Show("w" winWidth " h" winHeight)
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

SetTimer(UpdatePlayerStatus, 250)
SetTimer(SaveState, 2000)

LoadSavedState()

PlaylistSongSelected(guiCtrl, row, selected) {
    global player, playlist
    global playlistSyncing
    global titleText, playBtn, statusText

    if playlistSyncing
        return

    if !selected
        return

    if (row <= 0)
        return

    if (row > playlist.count)
        return

    try {
        item := playlist.item(row - 1)

        player.controls.playItem(item)

        title := item.name

        if !title
            title := guiCtrl.GetText(row, 1)

        titleText.Text := title
        playBtn.Text := "Pause"
        statusText.Text := "Playing"
    }
}
UpdatePlaylistHighlight() {
    global player, playlist
    global playlistView, playlistSyncing

    if (playlist.count = 0)
        return

    try {
        currentMedia := player.currentMedia

        if !currentMedia
            return

        currentIndex := -1

        Loop playlist.count {
            index := A_Index - 1

            try {
                item := playlist.item(index)

                if (item.isIdentical(currentMedia)) {
                    currentIndex := index
                    break
                }
            }
        }

        if (currentIndex < 0)
            return

        row := currentIndex + 1

        playlistSyncing := true

        Loop playlistView.GetCount()
            playlistView.Modify(A_Index, "-Select")

        playlistView.Modify(
            row,
            "Select Focus"
        )

        playlistSyncing := false
    } catch {
        playlistSyncing := false
    }
}

ChooseFolder(*) {
    global currentFolder

    selected := FileSelect("D1")

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
    global playlistView, playlistSyncing

    restoring := restoreSaved

    try player.controls.stop()

    playlist := player.newPlaylist(
        "AHK_Playlist",
        ""
    )

    playlistSyncing := true
    playlistView.Delete()
    playlistSyncing := false

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

                playlistView.Add(
                    "",
                    A_LoopFileName
                )

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

    UpdatePlaylistHighlight()
}

OpenScriptDir(*) {
    Run('explorer.exe "' A_ScriptDir '"')
}

OpenStached(*) {
    try {
        Run(IniRead(
            STATE_FILE,
            "Pathing",
            "Stached",
            DEFAULT_STACHER_PATH
        ))
    } catch Error as e {
        MsgBox("Failed to open stached`n`n"
         . "Message: " . e.Message . "`n"
         . "File: " . e.File . "`n"
         . "Line: " . e.Line . "`n"
         . "What: " . e.What
        )
    }
}
RemapStached(*) {
    IniWrite(
        FileSelect(, , "Select Stacher.exe", "Executable (*.exe)"),
        STATE_FILE,
        "Pathing",
        "Stached",
    )
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

; --- Fix: actually perform the seek, instead of gating on a flag that
; was never set to true anywhere in the script (progressDragging was
; declared and checked, but nothing ever flipped it on). ---
ProgressChanged(*) {
    global player, progressSlider, restoring

    if restoring
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

UpdatePlayerStatus() {
    global player, playlist
    global titleText, statusText, playBtn
    global progressSlider, progressTimeText

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

            UpdatePlaylistHighlight()

            duration := currentMedia.duration
            position := player.controls.currentPosition

            ; Only let the timer overwrite the slider while the user
            ; isn't actively holding it down mid-drag.
            if (
                duration > 0
                && !GetKeyState("LButton", "P")
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
