#Requires AutoHotkey v2.0
#SingleInstance Force

;@Ahk2Exe-SetMainIcon player.ico
;@Ahk2Exe-ExeName PlaylistPlayer.exe

STATE_FILE := A_ScriptDir "\state.ini"

player := ComObject("WMPlayer.OCX")
playlist := player.newPlaylist("AHK_Playlist", "")

winWidth := 1000
winHeight := 260

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
myGui.AddButton("x600 y90 w100 h30", "Download Playlist")
    .OnEvent("Click", DownloadPlaylist)
myGui.AddButton("x600 y130 w100 h30", "Remap Storage")
    .OnEvent("Click", SetStorageFolder)
myGui.AddButton("x600 y170 w100 h30", "View Download Log")
    .OnEvent("Click", ViewDownloadLog)
myGui.AddButton("x600 y210 w100 h30", "Update (nightly)")
    .OnEvent("Click", UpdateYtDlp)

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

OnMessage(0x020A, OnSliderMouseWheel) ; WM_MOUSEWHEEL

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

GetStoragePath() {
    global STATE_FILE

    return IniRead(STATE_FILE, "Paths", "storage", "")
}

DenoAvailable() {
    if FileExist(A_ScriptDir "\deno.exe")
        return true

    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec(A_ComSpec ' /c where deno')

        while !exec.StdOut.AtEndOfStream
            exec.StdOut.ReadLine()

        return (exec.ExitCode = 0)
    } catch {
        return false
    }
}

FFmpegAvailable() {
    if (FileExist(A_ScriptDir "\ffmpeg.exe") && FileExist(A_ScriptDir "\ffprobe.exe"))
        return true

    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec(A_ComSpec ' /c where ffmpeg')

        while !exec.StdOut.AtEndOfStream
            exec.StdOut.ReadLine()

        return (exec.ExitCode = 0)
    } catch {
        return false
    }
}

UpdateYtDlp(*) {
    global statusText

    ytdlpPath := A_ScriptDir "\yt-dlp.exe"

    if !FileExist(ytdlpPath) {
        MsgBox(
            "yt-dlp.exe was not found in:`n" A_ScriptDir,
            "Error",
            "Icon!"
        )
        return
    }

    logPath := A_ScriptDir "\yt-dlp_update_log.txt"
    batPath := A_ScriptDir "\_ytdlp_update.bat"

    batContent := "@echo off`r`n"
        . '"' ytdlpPath '" --update-to nightly'
        . ' > "' logPath '" 2>&1'
        . "`r`n"

    try FileDelete(batPath)
    try FileDelete(logPath)

    try {
        FileAppend(batContent, batPath, "UTF-8")
    } catch as err {
        MsgBox(
            "Failed to write updater script: " err.Message,
            "Error",
            "Icon!"
        )
        return
    }

    try {
        RunWait('"' batPath '"', A_ScriptDir, "Hide")

        result := ""

        if FileExist(logPath) {
            result := FileRead(logPath)
        }

        statusText.Text := "yt-dlp update finished. See log for details."

        MsgBox(
            result ? result : "Update finished, but no output was captured.",
            "yt-dlp Update",
            "Iconi"
        )
    } catch as err {
        MsgBox(
            "Failed to run yt-dlp update: " err.Message,
            "Error",
            "Icon!"
        )
    }
}

SetStorageFolder(*) {
    global STATE_FILE, statusText, myGui

    currentStorage := GetStoragePath()

    selected := FileSelect(
        "D1",
        currentStorage,
        "Select Music Storage Folder"
    )

    if !selected
        return

    IniWrite(
        selected,
        STATE_FILE,
        "Paths",
        "storage"
    )

    statusText.Text := "Music storage folder set to: " selected
}

ViewDownloadLog(*) {
    logPath := A_ScriptDir "\yt-dlp_log.txt"

    if !FileExist(logPath) {
        MsgBox(
            "No download log yet. Run a download first.",
            "No Log",
            "Icon!"
        )
        return
    }

    Run(logPath)
}

PromptForURL() {
    global myGui

    result := ""
    submittedUrl := ""

    dlgGui := Gui(
        "+Owner" myGui.Hwnd,
        "Download Playlist"
    )
    dlgGui.SetFont("s10", "Segoe UI")

    dlgGui.AddText("xm y10", "Playlist URL:")
    urlEdit := dlgGui.AddEdit("xm y30 w400 h25")

    okBtn := dlgGui.AddButton(
        "x235 y65 w80 h30 Default",
        "OK"
    )
    cancelBtn := dlgGui.AddButton(
        "x325 y65 w80 h30",
        "Cancel"
    )

    okBtn.OnEvent("Click", (*) => (
        submittedUrl := urlEdit.Text,
        result := "ok",
        dlgGui.Destroy()
    ))

    cancelBtn.OnEvent("Click", (*) => (
        result := "cancel",
        dlgGui.Destroy()
    ))

    dlgGui.OnEvent("Close", (*) => (
        result := "cancel",
        dlgGui.Destroy()
    ))

    dlgGui.OnEvent("Escape", (*) => (
        result := "cancel",
        dlgGui.Destroy()
    ))

    dlgGui.Show("w420 h110")

    urlEdit.Focus()

    while (result = "")
        Sleep(50)

    if (result != "ok")
        return ""

    return Trim(submittedUrl)
}

DownloadPlaylist(*) {
    global statusText

    storage := GetStoragePath()

    if (storage = "" || !DirExist(storage)) {
        answer := MsgBox(
            "No music storage folder is set yet. Choose one now?",
            "Set Storage Folder",
            "YesNo Icon!"
        )

        if (answer != "Yes")
            return

        SetStorageFolder()

        storage := GetStoragePath()

        if (storage = "" || !DirExist(storage)) {
            statusText.Text := "Download cancelled: no storage folder set."
            return
        }
    }

    url := PromptForURL()

    if (url = "")
        return

    ytdlpPath := A_ScriptDir "\yt-dlp.exe"

    if !FileExist(ytdlpPath) {
        MsgBox(
            "yt-dlp.exe was not found in:`n" A_ScriptDir,
            "Error",
            "Icon!"
        )
        return
    }

    if !DenoAvailable() {
        answer := MsgBox(
            "yt-dlp needs the Deno JavaScript runtime to download from "
            . "YouTube reliably. Without it, downloads often fail with "
            . "HTTP 403 errors.`n`n"
            . "Download deno.exe from:`n"
            . "https://github.com/denoland/deno/releases/latest`n"
            . "and place it in:`n" A_ScriptDir
            . "`n`nContinue anyway?",
            "Deno Not Found",
            "YesNo Icon!"
        )

        if (answer != "Yes")
            return
    }

    if !FFmpegAvailable() {
        answer := MsgBox(
            "FFmpeg was not found. yt-dlp needs ffmpeg.exe and ffprobe.exe "
            . "to extract/convert audio to mp3 — without them, downloads "
            . "will fail at the conversion step.`n`n"
            . "Download a Windows build (the 'full' or 'essentials' zip) "
            . "from:`n"
            . "https://www.gyan.dev/ffmpeg/builds/`n"
            . "and place ffmpeg.exe and ffprobe.exe (from its bin folder) "
            . "in:`n" A_ScriptDir
            . "`n`nContinue anyway?",
            "FFmpeg Not Found",
            "YesNo Icon!"
        )

        if (answer != "Yes")
            return
    }

    outputTemplate := storage
        . "\%(playlist_title)s\%(artist)s - %(playlist_title)s - %(title)s.%(ext)s"

    logPath := A_ScriptDir "\yt-dlp_log.txt"
    batPath := A_ScriptDir "\_ytdlp_run.bat"

    outputTemplateEscaped := StrReplace(outputTemplate, "%", "%%")

    ffmpegLocationArg := ""
    if FileExist(A_ScriptDir "\ffmpeg.exe")
        ffmpegLocationArg := ' --ffmpeg-location "' A_ScriptDir '"'

    batContent := "@echo off`r`n"
        . '"' ytdlpPath '"'
        . ' -x --audio-format mp3'
        . ' --no-abort-on-error'
        . ' --ignore-errors'
        . ' --extractor-args "youtube:player_client=visionos"'
        . ffmpegLocationArg
        . ' -o "' outputTemplateEscaped '"'
        . ' "' url '"'
        . ' > "' logPath '" 2>&1'
        . "`r`n"

    try {
        FileDelete(batPath)
    }
    try {
        FileDelete(logPath)
    }

    try {
        FileAppend(batContent, batPath, "UTF-8")
    } catch as err {
        MsgBox(
            "Failed to write launcher script: " err.Message,
            "Error",
            "Icon!"
        )
        return
    }

    try {
        Run('"' batPath '"', A_ScriptDir, "Hide")

        statusText.Text := "Downloading playlist to " storage
            . "  (log: " logPath ")"
    } catch as err {
        MsgBox(
            "Failed to start yt-dlp: " err.Message,
            "Error",
            "Icon!"
        )
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
            || ext = "webm"
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
