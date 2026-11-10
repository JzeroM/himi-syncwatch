import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import HimiPlayer
import "evolveui" as EUI

// 665：播放器主窗口（功能全量对齐 Flutter 播放器；房间模式暂缓）。
//
// 【层次】底层 = 原生视频子窗口（mpv wid 直出，保 HDR）；上层 = QML。
// 视频窗口满铺 + WS_EX_TRANSPARENT 点击穿透 + SetWindowRgn 挖孔：
// 鼠标事件全部落给 QML（手势层），浮层通过挖孔可见可点。
//
// 【交互（照 Flutter `_onVideoAreaTap` / `video_gesture_layer`）】
//   单击视频：有面板→收回；无面板→切换控件显隐；锁定态只浮现锁钮
//   双击视频：播放/暂停 + 手势图标
//   横向拖动：seek（100px ≈ 5s，松手提交）
//   纵向拖动：右半屏音量 / 左半屏亮度（实时生效）
//
// 【665 新增功能】播完自动下一集、弹幕 ASS 旁路（secondary-sid 双字幕
// 轨）、跳过片头/片尾胶囊、本地字幕加载、内核面板、选集海报卡片、
// 画面比例本地循环、面板 toggle/点空白收回（无 ✕）。
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

    // FontAwesome 图标字体（EvolveUI 生态字形；上下文链注入子组件）
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

    // 控件自动隐藏（播放中 5 秒无操作）
    property bool controlsVisible: true
    property bool panelOpen: false
    property bool adjustOpen: false

    // 画面比例（本地循环：contain→cover→fill→none）
    readonly property var fitModes: ["contain", "cover", "fill", "none"]
    property int fitIndex: 0

    // 手势/提示浮层
    property string gestureIcon: ""
    property string notice: ""

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

    function toggleControls() {
        if (controlsVisible) {
            controlsVisible = false
        } else {
            showControls()
        }
    }

    function closePanels() {
        panelOpen = false
        adjustOpen = false
    }

    function showGesture(iconOrText) {
        gestureIcon = iconOrText
        gestureTimer.restart()
    }

    function showNotice(text) {
        notice = text
        noticeTimer.restart()
    }

    Timer { id: gestureTimer; interval: 700; onTriggered: root.gestureIcon = "" }
    Timer { id: noticeTimer; interval: 3000; onTriggered: root.notice = "" }

    // ── 手势层（视频区单击/双击/拖动；Flutter video_gesture_layer 语义）──
    MouseArea {
        id: videoArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton

        property real pressX: 0
        property real pressY: 0
        property real startX: 0
        property real startY: 0
        property real startVolume: 0
        property real startBrightness: 0
        property real seekAccum: 0
        property bool dragging: false

        onPositionChanged: (mouse) => {
            root.showControls()
            if (!pressed) return
            var dx = mouse.x - startX
            var dy = mouse.y - startY
            if (!dragging && (Math.abs(dx) > 12 || Math.abs(dy) > 12)) {
                dragging = true
            }
            if (!dragging) return
            if (Math.abs(dx) > Math.abs(dy)) {
                // 横向：seek 预览（100px ≈ 5s，与 Flutter 一致）
                seekAccum = dx / 100 * 5000
                var deltaS = Math.round(seekAccum / 1000)
                root.showGesture((deltaS >= 0 ? "+" : "") + deltaS + "s")
            } else if (pressX > width / 2) {
                // 右半纵向：音量
                var v = Math.max(0, Math.min(1, startVolume - dy / 300))
                mpvWindow.setVolume(v)
                pipeServer.sendCommand({"type": "setVolume", "volume": v})
                root.showGesture(Icons.volumeUp)
            } else {
                // 左半纵向：亮度
                var b = Math.max(0, Math.min(1, startBrightness - dy / 300))
                pipeServer.sendCommand({"type": "setBrightness", "brightness": b})
                root.showGesture(Icons.brightness)
            }
        }

        // 667：按下瞬间的控件显隐快照（tapTimer 按它决定动作）。
        // showControls 会把状态置真，直接用当前值会让「唤出」被
        // 250ms 后的 toggle 藏掉（真机回归：点击唤出立马隐藏）。
        property bool wasVisible: true

        onPressed: (mouse) => {
            startX = mouse.x
            startY = mouse.y
            pressX = mouse.x
            pressY = mouse.y
            startVolume = playerState.volume
            startBrightness = playerState.brightness
            seekAccum = 0
            dragging = false
            wasVisible = root.controlsVisible
            root.showControls()
        }

        onReleased: {
            if (dragging && Math.abs(seekAccum) > 500) {
                var target = Math.max(0, playerState.positionMs + Math.round(seekAccum))
                mpvWindow.seekTo(target)
                pipeServer.sendCommand({"type": "seekTo", "positionMs": target})
            }
            dragging = false
            seekAccum = 0
        }

        // 单击延迟 250ms 执行（等双击判定，与 Flutter 手势仲裁一致）
        onClicked: tapTimer.restart()
        onDoubleClicked: {
            tapTimer.stop()
            mpvWindow.togglePause()
            pipeServer.sendCommand({"type": "togglePlay"})
            root.showGesture(playerState.paused ? Icons.playCircle
                                                : Icons.pauseCircle)
        }
    }

    Timer {
        id: tapTimer
        interval: 250
        onTriggered: {
            // Flutter `_onVideoAreaTap` 语义（667：按按下瞬间快照判定）
            if (playerState.locked) {
                root.showControls()
                return
            }
            if (root.panelOpen || root.adjustOpen) {
                root.closePanels()
                return
            }
            if (videoArea.wasVisible) {
                root.controlsVisible = false
            } else {
                root.showControls()
            }
        }
    }

    // ── 顶栏 ──
    TopBar {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        showControls: root.controlsVisible && !playerState.locked
        decodeOpen: panel.visible && panel.title === "解码方式"
        adjustOpen: adjustPanel.visible
        videoFitMode: root.fitModes[root.fitIndex]
        onBackClicked: {
            pipeServer.sendCommand({"type": "requestExit"})
            root.close()
        }
        onDecodeClicked: root.openDecodePanel()
        onSubtitleStyleClicked: root.openAdjustPanel()
        onVideoFitClicked: root.cycleVideoFitLocal()
    }

    // ── 底栏 ──
    BottomBar {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        showControls: root.controlsVisible && !playerState.locked

        // 播放控制：本地直驱 + 通知 Flutter 双写（幂等）
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
        onDanmakuClicked: {
            // 弹幕 = mpv 次字幕轨（ASS 旁路）。667：开关改**重生成 ASS**
            // （遮罩常驻、弹幕行随开关）——直接藏轨会把渐变遮罩一起藏掉。
            danmakuOn = !danmakuOn
            danmakuBuildTimer.restart()
            pipeServer.sendCommand({"type": "toggleDanmaku"})
        }
        onVersionClicked: root.openVersionPanel()
        onSubtitleClicked: root.openSubtitlePanel()
        onAudioClicked: root.openAudioPanel()
        onEpisodeClicked: root.openEpisodePanel()
        onSpeedClicked: root.openSpeedPanel()
        onFullscreenClicked: root.toggleFullscreen()
        onSkipSegmentClicked: root.skipSegmentLocal()
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

    // 弹幕开关本地态（次字幕轨可见性）
    property bool danmakuOn: true

    // ── 左缘锁钮（圆形半黑底；锁定态控件被门禁，仅锁钮供解锁）──
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

    // ── 手势图标/提示 ──
    Text {
        visible: root.gestureIcon !== ""
        anchors.centerIn: parent
        text: root.gestureIcon
        font.family: iconFont.name
        font.pixelSize: 48
        color: Theme.white
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.6)
    }

    // ── 通知（所有剧集播放完毕 等）──
    Rectangle {
        visible: root.notice !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: bottomBar.top
        anchors.bottomMargin: 24
        width: noticeText.implicitWidth + 32
        height: 36
        radius: 18
        color: Qt.rgba(0, 0, 0, 0.65)

        Text {
            id: noticeText
            anchors.centerIn: parent
            text: root.notice
            color: Theme.white
            font.pixelSize: Theme.panelOptionSize
        }
    }

    // ── 等待主程序连接 ──
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

    // ── 左下角剧集 Logo ──
    EpisodeLogo {
        id: episodeLogo
        anchors.left: parent.left
        anchors.bottom: bottomBar.top
        anchors.leftMargin: Theme.barPadH
        anchors.bottomMargin: 8
    }

    // ── 视频 HWND 挖孔联动（150ms 轮询；显隐自动收放）──
    Timer {
        interval: 150
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.updateOverlayHoles()
    }

    function updateOverlayHoles() {
        var holes = []
        // 667：圆角孔（直角孔在圆形按钮/胶囊四周露黑角）
        function add(it, r, inset) {
            if (!it.visible || it.width <= 0 || it.height <= 0) return
            var p = it.mapToItem(null, 0, 0)
            var ins = inset || 0
            holes.push({
                x: p.x + ins, y: p.y + ins,
                w: it.width - ins * 2, h: it.height - ins * 2,
                r: r
            })
        }
        add(topBar, 20, 4)          // 浮岛胶囊
        add(bottomBar, 20, 4)
        add(lockButton, 19, 0)      // 圆孔贴合圆钮
        add(episodeLogo, 10, 0)     // 徽章底圆角
        add(loadingLoader, 12, 0)
        add(waitingOverlay, 12, 0)
        if (panel.visible) add(panel, 20, 0)
        if (adjustPanel.visible) add(adjustPanel, 20, 0)
        mpvWindow.setOverlayHoles(holes)
    }

    // ── 列表面板（无 ✕：toggle / 点空白收回）──
    Panel {
        id: panel
        anchors.right: parent.right
        anchors.top: parent.top
        // 667：**不能锚 bottom**——top+bottom 双锚会把面板高度撑满
        // （排版丑根因：行漂在中部、大片空白）。高度由 Panel 自身
        // 内容自适应绑定决定。
        anchors.rightMargin: Theme.panelRight
        anchors.topMargin: Theme.panelTopOffset
        visible: root.panelOpen && !playerState.locked
        onClosed: root.closePanels()
        onItemClicked: (id) => {
            root.handlePanelItem(id)
            root.closePanels()
        }
    }

    // ── 显示调节面板 ──
    DisplayAdjustPanel {
        id: adjustPanel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: Theme.panelRight
        anchors.topMargin: Theme.panelTopOffset
        visible: root.adjustOpen && !playerState.locked
        onClosed: root.closePanels()
        onAdjust: (key, value) => pipeServer.sendCommand({
            "type": "adjustDisplay", "key": key, "value": value
        })
        onReset: (scope) => pipeServer.sendCommand({
            "type": "resetDisplay", "scope": scope
        })
    }

    // ── 本地字幕文件选择（照 Flutter「加载本地字幕文件...」）──
    FileDialog {
        id: subDialog
        title: "选择字幕文件"
        nameFilters: ["字幕文件 (*.srt *.ass *.ssa *.sub *.vtt)",
                      "所有文件 (*)"]
        onAccepted: {
            var url = currentFile.toString()
            mpvWindow.command(["sub-add", url, "select"])
            pipeServer.sendCommand({"type": "addSubtitle", "url": url,
                                    "title": "external", "lang": "auto"})
            root.showNotice("已加载本地字幕")
        }
    }

    // ── 播完自动下一集（照 Flutter autoNext）──
    Connections {
        target: mpvWindow
        function onPlaybackEnded() {
            if (playerState.currentEpisodeIndex >= 0
                && playerState.currentEpisodeIndex < playerState.episodeCount - 1) {
                pipeServer.sendCommand({"type": "selectEpisode",
                                        "index": playerState.currentEpisodeIndex + 1})
            } else {
                root.showNotice("所有剧集播放完毕")
            }
        }
    }

    // ── 弹幕 ASS 旁路（danmakuItems → ASS → mpv 次字幕轨）──
    Timer {
        id: danmakuBuildTimer
        interval: 600
        onTriggered: root.buildDanmakuAss()
    }
    Connections {
        target: playerState
        function onDanmakuChanged() { danmakuBuildTimer.restart() }
    }

    function assTime(sec) {
        var h = Math.floor(sec / 3600)
        var m = Math.floor((sec % 3600) / 60)
        var s = sec - h * 3600 - m * 60
        function pad(n, w) {
            var t = n.toString()
            while (t.length < w) t = "0" + t
            return t
        }
        return h + ":" + pad(m, 2) + ":" + pad(Math.floor(s), 2)
                 + "." + pad(Math.floor((s % 1) * 100), 2)
    }

    function assColor(hex) {
        // #RRGGBB → &H00BBGGRR
        var c = (hex || "#FFFFFF").replace("#", "")
        if (c.length < 6) c = "FFFFFF"
        return "&H00" + c.substring(4, 6) + c.substring(2, 4)
                 + c.substring(0, 2)
    }

    function buildDanmakuAss() {
        // 667：ASS 里**常驻渐变遮罩**（顶/底全宽软渐变，mpv 画进视频 =
        // 真半透明压视频，同 Flutter 控件层观感）；弹幕行随开关增减。
        var items = danmakuOn ? playerState.danmakuItems : []
        var W = 1280, H = 720
        var fs = Math.round(28 * playerState.danmakuFontSize)
        var lines = []
        lines.push("[Script Info]")
        lines.push("ScriptType: v4.00+")
        lines.push("PlayResX: " + W)
        lines.push("PlayResY: " + H)
        lines.push("")
        lines.push("[V4+ Styles]")
        lines.push("Format: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding")
        lines.push("Style: Danmaku, sans-serif, " + fs + ", &H00FFFFFF, &H00000000, &H7F000000, 0, 0, 0, 0, 100, 100, 0, 0, 1, 1, 0, 5, 0, 0, 0")
        lines.push("Style: Scrim, sans-serif, 28, &H00000000, &H00000000, &H00000000, 0, 0, 0, 0, 100, 100, 0, 0, 1, 0, 0, 7, 0, 0, 0")
        lines.push("")
        lines.push("[Events]")
        lines.push("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text")

        // ── 渐变遮罩（多条递减 alpha 带近似渐变；FF=全透明）──
        function pushScrim(y, bandH, alphaStart) {
            var eff = "{\\an7\\pos(0," + y + ")\\alpha&H"
                    + ("0" + Math.round(alphaStart * 255).toString(16)).slice(-2)
                    + "&\\p1}m 0 0 l " + W + " 0 " + W + " " + bandH
                    + " 0 " + bandH + "{\\p0}"
            lines.push("Dialogue: 1,0:00:00.00,99:00:00.00,Scrim,,0,0,0,," + eff)
        }
        // 顶部 6 带（高 64，alpha 0.55→0）
        for (var t = 0; t < 6; t++) {
            pushScrim(Math.round(t * 64 / 6), Math.ceil(64 / 6) + 1,
                      0.55 * (1 - t / 6))
        }
        // 底部 8 带（高 110，alpha 0.70→0，从下往上递减）
        for (var b = 0; b < 8; b++) {
            pushScrim(Math.round(H - 110 + b * 110 / 8), Math.ceil(110 / 8) + 1,
                      0.70 * (1 - b / 8))
        }

        var rows = Math.max(4, Math.floor((H - 80) / (fs + 6)))
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            var t0 = it.timeMs / 1000
            var body = (it.text || "").replace(/\\\\/g, "\\")
                                     .replace(/\{/g, "(")
                                     .replace(/\}/g, ")")
                                     .replace(/\n/g, " ")
            var col = assColor(it.color)
            var dur = (it.mode === "scroll") ? 8 : 4
            var eff
            if (it.mode === "top") {
                eff = "{\\an8\\pos(" + Math.round(W / 2) + ",30)\\c" + col + "}"
            } else if (it.mode === "bottom") {
                eff = "{\\an2\\pos(" + Math.round(W / 2) + "," + (H - 30) + ")\\c" + col + "}"
            } else {
                var y = 20 + (i % rows) * (fs + 6)
                eff = "{\\move(" + (W + 120) + "," + y + "," + -120 + "," + y
                        + ")\\c" + col + "}"
            }
            lines.push("Dialogue: 0," + assTime(t0) + "," + assTime(t0 + dur)
                        + ",Danmaku,,0,0,0,," + eff + body)
        }
        mpvWindow.setDanmakuAss(lines.join("\n"))
    }

    // ── 面板内容 ──
    function openEpisodePanel() {
        if (panelOpen && panel.title === "选集") { closePanels(); return }
        var list = []
        for (var i = 0; i < playerState.episodes.length; i++) {
            var e = playerState.episodes[i]
            // cardTitle 照 Flutter：`number.name`（电影/无编号 = 纯名）
            var name = (e.number > 0) ? (e.number + "." + e.title) : e.title
            list.push({
                id: e.index,
                display: name,
                sub: "",
                poster: e.poster,
                selected: e.index === playerState.currentEpisodeIndex
            })
        }
        panel.title = "选集"
        panel.cardMode = true
        panel.items = list
        adjustOpen = false
        panelOpen = true
    }

    function openAudioPanel() {
        if (panelOpen && panel.title === "音轨") { closePanels(); return }
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
        panel.cardMode = false
        panel.items = list
        adjustOpen = false
        panelOpen = true
    }

    function openSubtitlePanel() {
        if (panelOpen && panel.title === "字幕") { closePanels(); return }
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
        // 照 Flutter SubtitleMenuPanel 末行
        list.push({ id: -2, display: "加载本地字幕文件...", sub: "", selected: false })
        panel.title = "字幕"
        panel.cardMode = false
        panel.items = list
        adjustOpen = false
        panelOpen = true
    }

    function openSpeedPanel() {
        if (panelOpen && panel.title === "倍速") { closePanels(); return }
        var speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
        var list = []
        for (var i = 0; i < speeds.length; i++) {
            list.push({
                id: speeds[i],
                display: formatSpeedLabel(speeds[i]),
                sub: "",
                selected: Math.abs(speeds[i] - playerState.speed) < 0.01
            })
        }
        panel.title = "倍速"
        panel.cardMode = false
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

    function openVersionPanel() {
        if (panelOpen && panel.title === "版本") { closePanels(); return }
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
        panel.cardMode = false
        panel.items = list
        adjustOpen = false
        panelOpen = true
    }

    function openDecodePanel() {
        if (panelOpen && panel.title === "解码方式") { closePanels(); return }
        panel.title = "解码方式"
        panel.cardMode = false
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

    function openAdjustPanel() {
        if (adjustOpen) { closePanels(); return }
        panelOpen = false
        adjustOpen = true
    }

    function handlePanelItem(id) {
        if (panel.title === "选集") {
            pipeServer.sendCommand({"type": "selectEpisode", "index": id})
        } else if (panel.title === "音轨") {
            mpvWindow.selectTrack("audio", id > 0 ? id - 1 : -1)
            pipeServer.sendCommand({"type": "selectAudio", "id": id})
        } else if (panel.title === "字幕") {
            if (id === -2) {
                subDialog.open()
                return
            }
            mpvWindow.selectTrack("subtitle", id > 0 ? id - 1 : -1)
            pipeServer.sendCommand({"type": "selectSubtitle", "id": id})
        } else if (panel.title === "倍速") {
            mpvWindow.setSpeed(id)
            pipeServer.sendCommand({"type": "setSpeed", "speed": id})
        } else if (panel.title === "版本") {
            pipeServer.sendCommand({"type": "selectVersion", "index": id})
        } else if (panel.title === "解码方式") {
            pipeServer.sendCommand({"type": "setDecodeMode", "mode": id})
        }
    }

    /// 画面比例循环（contain→cover→fill→none，本地 mpv 生效）
    function cycleVideoFitLocal() {
        fitIndex = (fitIndex + 1) % fitModes.length
        var m = fitModes[fitIndex]
        if (m === "contain") {
            mpvWindow.command(["set", "panscan", "0"])
            mpvWindow.command(["set", "video-unscaled", "no"])
            mpvWindow.command(["set", "video-aspect-override", "0"])
        } else if (m === "cover") {
            mpvWindow.command(["set", "panscan", "1.0"])
            mpvWindow.command(["set", "video-unscaled", "no"])
            mpvWindow.command(["set", "video-aspect-override", "0"])
        } else if (m === "fill") {
            mpvWindow.command(["set", "panscan", "0"])
            mpvWindow.command(["set", "video-unscaled", "no"])
            mpvWindow.command(["set", "video-aspect-override", "-1"])
        } else {
            mpvWindow.command(["set", "panscan", "0"])
            mpvWindow.command(["set", "video-unscaled", "yes"])
            mpvWindow.command(["set", "video-aspect-override", "0"])
        }
        pipeServer.sendCommand({"type": "cycleVideoFit"})
    }

    /// 跳过片头/片尾（胶囊点击）
    function skipSegmentLocal() {
        if (playerState.segmentIntroEndMs >= 0
            && playerState.positionMs < playerState.segmentIntroEndMs) {
            mpvWindow.seekTo(playerState.segmentIntroEndMs)
            pipeServer.sendCommand({"type": "seekTo",
                                    "positionMs": playerState.segmentIntroEndMs})
        } else {
            pipeServer.sendCommand({"type": "selectEpisode",
                                    "index": playerState.currentEpisodeIndex + 1})
        }
    }

    function toggleFullscreen() {
        if (visibility === Window.FullScreen) showNormal()
        else showFullScreen()
    }

    // ── 键盘快捷键（本地直驱 + 通知）──
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
