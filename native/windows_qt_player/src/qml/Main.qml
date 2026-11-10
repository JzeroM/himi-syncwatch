import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// 656：播放器主窗口。
//
// 【层次】
//   底层：原生视频子窗口（mpv，由 C++ 创建，永远在 QML 之上）
//   上层：QML 控件（顶栏/底栏/面板）——通过视频子窗口的 inset 让出区域
//
// 【为什么控件能看见】原生子 HWND 会盖住 QML（Win32 硬规则），所以
// C++ 侧把视频窗口高度减去 `insetTop + insetBottom`（48 + 96），
// 顶栏/底栏所在的那两条区域没有视频窗口，QML 就能正常显示。
ApplicationWindow {
    id: root
    width: 1280
    height: 720
    minimumWidth: 640
    minimumHeight: 360
    visible: true
    title: playerState.title !== "" ? playerState.title + " — HIMI" : "HIMI Player"
    color: "#000000"
    flags: Qt.Window | Qt.FramelessWindowHint

    // Material Icons 字体（与 Flutter/安卓/鸿蒙同字形，图标用码点渲染）
    FontLoader {
        id: materialIcons
        source: "qrc:/qt/qml/HimiPlayer/fonts/MaterialIcons-Regular.otf"
    }

    // 控件自动隐藏（播放中 5 秒无操作）
    property bool controlsVisible: true
    property bool cursorHidden: false

    Timer {
        id: hideTimer
        interval: 5000
        running: !playerState.paused && controlsVisible
        onTriggered: root.controlsVisible = false
    }

    function showControls() {
        controlsVisible = true
        hideTimer.restart()
    }

    // 窗口内任意鼠标移动都重新计时
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: root.showControls()
    }

    // ── 顶栏 ──
    TopBar {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        showControls: root.controlsVisible
        onBackClicked: {
            pipeServer.sendCommand({"type": "requestExit"})
            root.close()
        }
        onKernelClicked: {
            pipeServer.sendCommand({"type": "switchEngine"})
        }
        onDecodeClicked: {
            pipeServer.sendCommand({"type": "setDecodeMode"})
        }
        onVideoFitClicked: {
            pipeServer.sendCommand({"type": "cycleVideoFit"})
        }
        onSpeedClicked: openSpeedPanel()
        onFullscreenClicked: toggleFullscreen()
    }

    // ── 底栏 ──
    BottomBar {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        showControls: root.controlsVisible

        onPlayPauseClicked: pipeServer.sendCommand({"type": "togglePlay"})
        onNextEpisodeClicked: {
            pipeServer.sendCommand({
                "type": "selectEpisode",
                "index": playerState.currentEpisodeIndex + 1
            })
        }
        onDanmakuClicked: pipeServer.sendCommand({"type": "toggleDanmaku"})
        onSubtitleClicked: openSubtitlePanel()
        onAudioClicked: openAudioPanel()
        onEpisodeClicked: openEpisodePanel()
        onSpeedClicked: openSpeedPanel()
        onFullscreenClicked: toggleFullscreen()
        onVolumeChanged: (v) => pipeServer.sendCommand({
            "type": "setVolume", "volume": v
        })
        onSeekFinished: (ratio) => pipeServer.sendCommand({
            "type": "seekTo",
            "positionMs": Math.round(ratio * playerState.durationMs)
        })
    }

    // ── 加载指示器 ──
    BusyIndicator {
        anchors.centerIn: parent
        running: playerState.showLoading
        visible: playerState.showLoading
        width: 56
        height: 56
    }

    // ── 等待主程序连接 ──
    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: !pipeServer.hasClient

        BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter
                        running: true; width: 48; height: 48 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "等待主程序连接…"
            color: "#80FFFFFF"
            font.pixelSize: 14
        }
    }

    // ── 面板 ──
    Panel {
        id: panel
        anchors.right: parent.right
        anchors.bottom: bottomBar.top
        anchors.rightMargin: 16
        anchors.bottomMargin: 8
        onClosed: panel.visible = false
        onItemClicked: (id) => {
            handlePanelItem(id)
            panel.visible = false
        }
    }

    // ── 面板内容填充 ──
    function openEpisodePanel() {
        var list = []
        for (var i = 0; i < playerState.episodes.length; i++) {
            var e = playerState.episodes[i]
            list.push({
                id: e.index,
                label: "第 " + e.number + " 集",
                sub: e.title,
                selected: e.index === playerState.currentEpisodeIndex
            })
        }
        panel.title = "选集"
        panel.items = list
        panel.visible = true
    }

    function openAudioPanel() {
        var list = []
        for (var i = 0; i < playerState.audioTracks.length; i++) {
            var t = playerState.audioTracks[i]
            list.push({
                id: t.id,
                label: t.label !== "" ? t.label : (t.title !== "" ? t.title : "音轨 " + t.id),
                sub: t.lang,
                selected: t.selected
            })
        }
        panel.title = "音轨"
        panel.items = list
        panel.visible = true
    }

    function openSubtitlePanel() {
        var list = [{ id: -1, label: "关闭字幕", sub: "", selected: false }]
        for (var i = 0; i < playerState.subtitleTracks.length; i++) {
            var t = playerState.subtitleTracks[i]
            list.push({
                id: t.id,
                label: t.label !== "" ? t.label : (t.title !== "" ? t.title : "字幕 " + t.id),
                sub: t.lang,
                selected: t.selected
            })
        }
        panel.title = "字幕"
        panel.items = list
        panel.visible = true
    }

    function openSpeedPanel() {
        var speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
        var list = []
        for (var i = 0; i < speeds.length; i++) {
            list.push({
                id: speeds[i],
                label: speeds[i].toFixed(2) + "x",
                sub: "",
                selected: Math.abs(speeds[i] - playerState.speed) < 0.01
            })
        }
        panel.title = "播放速度"
        panel.items = list
        panel.visible = true
    }

    function handlePanelItem(id) {
        if (panel.title === "选集") {
            pipeServer.sendCommand({"type": "selectEpisode", "index": id})
        } else if (panel.title === "音轨") {
            pipeServer.sendCommand({"type": "selectAudio", "id": id})
        } else if (panel.title === "字幕") {
            pipeServer.sendCommand({"type": "selectSubtitle", "id": id})
        } else if (panel.title === "播放速度") {
            pipeServer.sendCommand({"type": "setSpeed", "speed": id})
        }
    }

    function toggleFullscreen() {
        if (visibility === Window.FullScreen) {
            showNormal()
        } else {
            showFullScreen()
        }
    }

    // ── 键盘快捷键 ──
    Shortcut { sequence: "Space"; onActivated: pipeServer.sendCommand({"type": "togglePlay"}) }
    Shortcut { sequence: "Left"; onActivated: pipeServer.sendCommand({"type": "seekRelative", "deltaMs": -10000}) }
    Shortcut { sequence: "Right"; onActivated: pipeServer.sendCommand({"type": "seekRelative", "deltaMs": 10000}) }
    Shortcut { sequence: "Up"; onActivated: pipeServer.sendCommand({"type": "setVolume", "volume": Math.min(1, playerState.volume + 0.05)}) }
    Shortcut { sequence: "Down"; onActivated: pipeServer.sendCommand({"type": "setVolume", "volume": Math.max(0, playerState.volume - 0.05)}) }
    Shortcut { sequence: "F"; onActivated: root.toggleFullscreen() }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (root.visibility === Window.FullScreen) {
                root.showNormal()
            } else {
                root.close()
            }
        }
    }
}
