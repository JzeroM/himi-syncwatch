import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer
import "evolveui" as EUI

// 662：播放器主窗口。
//
// 【层次】
//   底层：原生视频子窗口（mpv，由 C++ 创建，永远在 QML 之上）
//   上层：QML 控件（顶栏/底栏/面板）——通过视频子窗口的 inset 让出区域
//
// 【为什么控件能看见】原生子 HWND 会盖住 QML（Win32 硬规则），所以
// C++ 侧把视频窗口高度减去 `insetTop + insetBottom`，顶栏/底栏所在的
// 那两条区域没有视频窗口，QML 就能正常显示。
//
// 【659】inset 按 DPI 换算（QML 逻辑像素 → Win32 物理像素），
// 数值取自 Theme，与 Flutter 完全一致。
//
// 【662】UI 组件库换 EvolveUI（third_party/evolveui，MIT）：
//   - 本文件根级 `id: theme`（ETheme）与 `id: iconFont`（FontAwesome
//     FontLoader）按 EvolveUI 的上下文链约定提供给所有子组件
//     （EButton/ESlider/ECard/ELoader 内部直接用 `theme`/`iconFont`）
//   - 功能不变：左缘锁钮（toggleLock 回环）、多版本面板（selectVersion）、
//     解码面板（setDecodeMode）、显示调节（adjustDisplay/resetDisplay）
ApplicationWindow {
    id: root
    width: 1280
    height: 720
    minimumWidth: 640
    minimumHeight: 360
    visible: true
    title: playerState.title !== "" ? playerState.title + " — HIMI" : "HIMI Player"
    color: "#000000"
    flags: Qt.Window

    // FontAwesome 图标字体（EvolveUI 生态字形；Flutter/安卓/鸿蒙仍是
    // Material Icons，两侧语义一一对应）
    FontLoader {
        id: iconFont
        source: "qrc:/new/prefix1/fonts/fontawesome-free-6.7.2-desktop/otfs/Font Awesome 6 Free-Solid-900.otf"
    }

    // EvolveUI 主题（暗色 + 沿用 #6366F1 强调色）
    EUI.ETheme {
        id: theme
        isDark: true
        focusColor: "#6366F1"
    }

    // 控件自动隐藏（播放中 5 秒无操作，与 Flutter `autoHideMs` 一致）
    property bool controlsVisible: true

    /// 列表面板（Panel）是否展开
    property bool panelOpen: false
    /// 显示调节面板是否展开
    property bool adjustOpen: false

    Timer {
        id: hideTimer
        interval: Theme.autoHideMs
        running: !playerState.paused && controlsVisible
        onTriggered: root.controlsVisible = false
    }

    function showControls() {
        controlsVisible = true
        hideTimer.restart()
    }

    /// 关闭所有面板（开新面板/锁定时调用）
    function closePanels() {
        panelOpen = false
        adjustOpen = false
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
        showControls: root.controlsVisible && !playerState.locked
        // 662 瑕疵修复：高亮由面板**真实可见性**驱动（不再用字符串插销）
        decodeOpen: panel.visible && panel.title === "解码方式"
        adjustOpen: adjustPanel.visible
        onBackClicked: {
            pipeServer.sendCommand({"type": "requestExit"})
            root.close()
        }
        onKernelClicked: pipeServer.sendCommand({"type": "switchEngine"})
        onDecodeClicked: root.openDecodePanel()
        onSubtitleStyleClicked: root.openAdjustPanel()
        onVideoFitClicked: pipeServer.sendCommand({"type": "cycleVideoFit"})
    }

    // ── 底栏 ──
    BottomBar {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        showControls: root.controlsVisible && !playerState.locked

        // 664 控件本地化：播放控制先直驱本地 mpv（Flutter 侧无人应答时
        // 控件仍可用），同时把命令发给 Flutter 做记账（弹幕同步等）——
        // 两边都幂等，重复应用无副作用。
        onPlayPauseClicked: {
            mpvWindow.togglePause()
            pipeServer.sendCommand({"type": "togglePlay"})
        }
        onPrevEpisodeClicked: pipeServer.sendCommand({
            "type": "selectEpisode",
            "index": playerState.currentEpisodeIndex - 1
        })
        onNextEpisodeClicked: pipeServer.sendCommand({
            "type": "selectEpisode",
            "index": playerState.currentEpisodeIndex + 1
        })
        onDanmakuClicked: pipeServer.sendCommand({"type": "toggleDanmaku"})
        onVersionClicked: root.openVersionPanel()
        onSubtitleClicked: root.openSubtitlePanel()
        onAudioClicked: root.openAudioPanel()
        onEpisodeClicked: root.openEpisodePanel()
        onSpeedClicked: root.openSpeedPanel()
        onFullscreenClicked: root.toggleFullscreen()
        onVolumeChanged: (v) => {
            mpvWindow.setVolume(v)
            pipeServer.sendCommand({"type": "setVolume", "volume": v})
        }
        onBrightnessChanged: (v) => pipeServer.sendCommand({
            "type": "setBrightness", "brightness": v
        })
        onSeekFinished: (ratio) => {
            var ms = Math.round(ratio * playerState.durationMs)
            mpvWindow.seekTo(ms)
            pipeServer.sendCommand({"type": "seekTo", "positionMs": ms})
        }
    }

    // ── 左缘锁钮（662，照 Flutter PlayerLockButton）──
    //
    // 圆形半黑底 + lock_open/lock，画面左缘垂直居中。
    // 显隐跟随控件栏；锁定态顶栏/底栏被 locked 门禁，点视频任意处
    // 仅浮现锁钮供解锁（与 Flutter「锁定态点屏」同语义）。
    EUI.EButton {
        id: lockButton
        visible: root.controlsVisible
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 38
        height: 38
        text: ""
        size: "m"
        iconCharacter: playerState.locked ? Icons.lock : Icons.lockOpen
        iconFontFamily: iconFont.name
        iconColor: theme.textColor
        radius: width / 2
        containerColor: Qt.rgba(0, 0, 0, 0.45)
        hoverColor: Qt.rgba(0, 0, 0, 0.65)
        onClicked: {
            pipeServer.sendCommand({"type": "toggleLock"})
            root.closePanels()
        }
    }

    // ── 加载指示器 ──
    EUI.ELoader {
        id: loadingLoader
        anchors.centerIn: parent
        running: playerState.showLoading
        visible: playerState.showLoading
        size: 56
    }

    // ── 等待主程序连接 ──
    //
    // 【662 瑕疵修复】深色圆角底衬 + 白色文案：loader.gif 是深色系，
    // 黑窗口里裸放完全看不见（真机截图中央全黑）。
    Rectangle {
        id: waitingOverlay
        anchors.centerIn: parent
        width: waitingCol.implicitWidth + 48
        height: waitingCol.implicitHeight + 32
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.55)
        border.color: theme.borderColor
        border.width: 1
        visible: !pipeServer.hasClient

        Column {
            id: waitingCol
            anchors.centerIn: parent
            spacing: 12

            EUI.ELoader {
                anchors.horizontalCenter: parent.horizontalCenter
                running: true
                size: 48
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "等待主程序连接…"
                color: Theme.white
                font.pixelSize: Theme.panelOptionSize
            }
        }
    }

    // ── 左下角剧集 Logo（660 照 Flutter 截图）──
    EpisodeLogo {
        id: episodeLogo
        anchors.left: parent.left
        anchors.bottom: bottomBar.top
        anchors.leftMargin: Theme.barPadH
        anchors.bottomMargin: 8
    }

    // ── 664：视频 HWND 挖孔联动 ──
    //
    // 原生视频子窗口永远盖住 QML（Win32 硬规则），QML 浮层落在视频上
    // 会被盖住（真机截图：面板点不到、锁钮/Logo 不可见）。
    //
    // 665：视频**满铺全窗口**（main.cpp inset 归零），顶栏/底栏也走
    // 挖孔——观感与 Flutter「视频满窗、控件浮在视频上」同构：
    //   - 16:9 内容横向到边（不再被上下 inset 逼出黑边）
    //   - 控件带可点（孔内鼠标落给 QML）
    //   - 控件自动隐藏时浮层 visible=false → **孔随之消失 = 纯视频**
    // QML 每 150ms 把浮层矩形交给 mpvWindow.setOverlayHoles 挖孔，
    // C++ 侧几何/孔无变化不重建区域。
    Timer {
        interval: 150
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.updateOverlayHoles()
    }

    function updateOverlayHoles() {
        var holes = []
        function add(it) {
            if (!it.visible || it.width <= 0 || it.height <= 0) return
            var p = it.mapToItem(null, 0, 0)
            holes.push(Qt.rect(p.x, p.y, it.width, it.height))
        }
        // 顶/底栏整条带（visible 跟随 opacity：自动隐藏后孔消失）
        add(topBar)
        add(bottomBar)
        add(lockButton)
        add(episodeLogo)
        add(loadingLoader)
        add(waitingOverlay)
        if (panel.visible) add(panel)
        if (adjustPanel.visible) add(adjustPanel)
        mpvWindow.setOverlayHoles(holes)
    }

    // ── 列表面板（右侧浮层，与 Flutter 位置一致）──
    Panel {
        id: panel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: bottomBar.top
        anchors.rightMargin: Theme.panelRight
        anchors.topMargin: Theme.panelTopOffset
        anchors.bottomMargin: 8
        visible: root.panelOpen && !playerState.locked
        onClosed: {
            root.panelOpen = false
        }
        onItemClicked: (id) => {
            root.handlePanelItem(id)
            root.panelOpen = false
        }
    }

    // ── 显示调节面板（662，顶栏 tune 入口）──
    DisplayAdjustPanel {
        id: adjustPanel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: Theme.panelRight
        anchors.topMargin: Theme.panelTopOffset
        visible: root.adjustOpen && !playerState.locked
        onClosed: {
            root.adjustOpen = false
        }
        onAdjust: (key, value) => pipeServer.sendCommand({
            "type": "adjustDisplay", "key": key, "value": value
        })
        onReset: (scope) => pipeServer.sendCommand({
            "type": "resetDisplay", "scope": scope
        })
    }

    // ── 面板内容 ──
    function openEpisodePanel() {
        var list = []
        for (var i = 0; i < playerState.episodes.length; i++) {
            var e = playerState.episodes[i]
            list.push({
                id: e.index,
                display: "第 " + e.number + " 集",
                sub: e.title,
                selected: e.index === playerState.currentEpisodeIndex
            })
        }
        panel.title = "选集"
        panel.items = list
        adjustOpen = false
        panelOpen = true
    }

    function openAudioPanel() {
        var list = []
        for (var i = 0; i < playerState.audioTracks.length; i++) {
            var t = playerState.audioTracks[i]
            list.push({
                id: t.id,
                display: t.label !== "" ? t.label
                       : (t.title !== "" ? t.title : "音轨 " + t.id),
                sub: t.lang,
                selected: t.selected
            })
        }
        panel.title = "音轨"
        panel.items = list
        adjustOpen = false
        panelOpen = true
    }

    function openSubtitlePanel() {
        var list = [{ id: -1, display: "关闭字幕", sub: "", selected: false }]
        for (var i = 0; i < playerState.subtitleTracks.length; i++) {
            var t = playerState.subtitleTracks[i]
            list.push({
                id: t.id,
                display: t.label !== "" ? t.label
                       : (t.title !== "" ? t.title : "字幕 " + t.id),
                sub: t.lang,
                selected: t.selected
            })
        }
        panel.title = "字幕"
        panel.items = list
        adjustOpen = false
        panelOpen = true
    }

    function openSpeedPanel() {
        var speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
        var list = []
        for (var i = 0; i < speeds.length; i++) {
            list.push({
                id: speeds[i],
                // 与 Flutter `SpeedMenuPanel.formatSpeedLabel` 同格式
                display: formatSpeedLabel(speeds[i]),
                sub: "",
                selected: Math.abs(speeds[i] - playerState.speed) < 0.01
            })
        }
        panel.title = "播放速度"
        panel.items = list
        adjustOpen = false
        panelOpen = true
    }

    /// 倍速标签（与 Flutter `formatSpeedLabel` = '${speed}x' 一致）
    function formatSpeedLabel(v) {
        var s = v.toString()
        if (s.indexOf(".") < 0) s += ".0"
        return s + "x"
    }

    // ── 662：多版本面板（照 Flutter VersionMenuPanel）──
    function openVersionPanel() {
        var list = []
        for (var i = 0; i < playerState.versions.length; i++) {
            var v = playerState.versions[i]
            list.push({
                id: v.index,
                display: v.title !== "" ? v.title : "版本 " + (i + 1),
                sub: "",
                selected: v.index === playerState.currentVersionIndex
            })
        }
        panel.title = "版本"
        panel.items = list
        adjustOpen = false
        panelOpen = true
    }

    // ── 662：解码方式面板（照 Flutter DecodeModePanel 三档）──
    function openDecodePanel() {
        panel.title = "解码方式"
        panel.items = [
            { id: "auto", display: "智能", sub: "优先硬解，失败回退软解",
              selected: playerState.decodeMode === "auto" },
            { id: "hw", display: "硬解", sub: "纯硬解，失败不回退",
              selected: playerState.decodeMode === "hw" },
            { id: "sw", display: "软解", sub: "纯软解，CPU 占用高",
              selected: playerState.decodeMode === "sw" }
        ]
        adjustOpen = false
        panelOpen = true
    }

    // ── 662：显示调节面板 ──
    function openAdjustPanel() {
        panelOpen = false
        adjustOpen = true
    }

    function handlePanelItem(id) {
        if (panel.title === "选集") {
            pipeServer.sendCommand({"type": "selectEpisode", "index": id})
        } else if (panel.title === "音轨") {
            // 664：切轨先本地生效（id = Emby 索引 + 1 → mpv 序号），再通知
            mpvWindow.selectTrack("audio", id > 0 ? id - 1 : -1)
            pipeServer.sendCommand({"type": "selectAudio", "id": id})
        } else if (panel.title === "字幕") {
            mpvWindow.selectTrack("subtitle", id > 0 ? id - 1 : -1)
            pipeServer.sendCommand({"type": "selectSubtitle", "id": id})
        } else if (panel.title === "播放速度") {
            mpvWindow.setSpeed(id)
            pipeServer.sendCommand({"type": "setSpeed", "speed": id})
        } else if (panel.title === "版本") {
            pipeServer.sendCommand({"type": "selectVersion", "index": id})
        } else if (panel.title === "解码方式") {
            pipeServer.sendCommand({"type": "setDecodeMode", "mode": id})
        }
    }

    function toggleFullscreen() {
        if (visibility === Window.FullScreen) showNormal()
        else showFullScreen()
    }

    // ── 键盘快捷键（664：与控件同策略——本地直驱 + 通知 Flutter）──
    Shortcut { sequence: "Space"; onActivated: {
        mpvWindow.togglePause()
        pipeServer.sendCommand({"type": "togglePlay"})
    } }
    Shortcut { sequence: "Left"; onActivated: {
        mpvWindow.seekTo(Math.max(0, playerState.positionMs - 10000))
        pipeServer.sendCommand({"type": "seekRelative", "deltaMs": -10000})
    } }
    Shortcut { sequence: "Right"; onActivated: {
        mpvWindow.seekTo(playerState.positionMs + 10000)
        pipeServer.sendCommand({"type": "seekRelative", "deltaMs": 10000})
    } }
    Shortcut { sequence: "Up"; onActivated: {
        mpvWindow.setVolume(Math.min(1, playerState.volume + 0.05))
        pipeServer.sendCommand({"type": "setVolume", "volume": Math.min(1, playerState.volume + 0.05)})
    } }
    Shortcut { sequence: "Down"; onActivated: {
        mpvWindow.setVolume(Math.max(0, playerState.volume - 0.05))
        pipeServer.sendCommand({"type": "setVolume", "volume": Math.max(0, playerState.volume - 0.05)})
    } }
    Shortcut { sequence: "F"; onActivated: root.toggleFullscreen() }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (root.visibility === Window.FullScreen) root.showNormal()
            else if (root.panelOpen || root.adjustOpen) root.closePanels()
            else root.close()
        }
    }
}
