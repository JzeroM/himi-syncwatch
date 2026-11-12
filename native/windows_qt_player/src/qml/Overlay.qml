import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import HimiPlayer
import "evolveui" as EUI

// 668：控件悬浮层（液态玻璃播放器 UI）。
//
// 【架构】逐像素透明顶层工具窗（main.cpp 创建，恒贴附视频宿主客户区）
// ——顶层窗口永远盖住 mpv 视频子窗口 = **真合成**：控件半透明玻璃直接
// 叠在视频上（Flutter 同款观感），零黑底、无挖孔、HDR 不损失。
//
// 【交互（Flutter `_onVideoAreaTap` / `video_gesture_layer` 语义）】
//   单击：面板开→收回；否则切控件显隐（隐藏后点击重新唤出不秒消）
//   双击：播放/暂停 + 手势图标；横拖 seek（100px≈5s）；纵拖右音量/左亮度
//
// 【功能全集】弹幕 ASS 旁路 / 播完自动下一集 / 画面比例循环 / 跳过
// 片头尾 / 本地字幕 / 面板（选集海报卡片·字幕·音轨·版本·倍速·解码·
// 显示调节）/ 显示调节六滑杆（恢复默认值同 Flutter）。
ApplicationWindow {
    id: root
    width: 1280
    height: 720
    // 669：隐藏创建→main.cpp 配置完 flags/alpha/几何再 show（防重建丢 alpha）
    visible: false
    flags: Qt.Tool | Qt.FramelessWindowHint
    color: "transparent"
    title: "HIMI 控件层"

    // FontAwesome 图标字体（上下文链注入子组件）
    FontLoader {
        id: iconFont
        source: "qrc:/new/prefix1/fonts/fontawesome-free-6.7.2-desktop/otfs/Font Awesome 6 Free-Solid-900.otf"
    }

    // EvolveUI 主题（暗色 + #6366F1 强调色）
    EUI.ETheme {
        id: theme
        isDark: true
        focusColor: "#6366F1"
    }

    // 控件显隐走**共享状态** playerState.controlsVisible（VideoGestures
    // 双窗实例任一被点击都能唤出本层）。
    property bool panelOpen: false
    property bool adjustOpen: false
    // 675 D：开面板即取消滑杆选中（点别处语义）
    onPanelOpenChanged: if (panelOpen) selectedSlider = ""
    onAdjustOpenChanged: if (adjustOpen) selectedSlider = ""

    // 670 A1：SAFE 深底降级（main.cpp 自检 alphaBuffer 失败时置 true）
    // ——透明合成不可靠机器上保控件可见（0.35 深底，视频仍透出）。
    property bool safeMode: false

    // 画面比例（本地循环：contain→cover→fill→none）
    readonly property var fitModes: ["contain", "cover", "fill", "none"]
    property int fitIndex: 0

    // 手势图标/通知
    property string gestureIcon: ""
    property string notice: ""

    // 弹幕开关本地态（ASS 重生成随开关增减弹幕行；遮罩常驻）
    property bool danmakuOn: true

    // 672：滑杆选中态（"" / "volume" / "brightness"）——选中后窗口任意
    // 位置滚轮调节该滑杆；悬停胶囊滚轮直接调该胶囊（BottomBar 内）。
    property string selectedSlider: ""

    function adjustByWheel(which, dir) {
        if (which === "volume") {
            var v = Math.max(0, Math.min(1, playerState.volume + dir * 0.05))
            root.patchState("volume", v)
            mpvWindow.setVolume(v)
            pipeServer.sendCommand({"type": "setVolume", "volume": v})
        } else if (which === "brightness") {
            var b = Math.max(0, Math.min(1, playerState.brightness + dir * 0.05))
            root.patchState("brightness", b)
            pipeServer.sendCommand({"type": "setBrightness", "brightness": b})
        }
    }

    /// 672 D2：片头/片尾标记（范围约束与全平台一致——588 权威：
    /// 片头 ≤10%、片尾 ≥70%；Flutter 侧 _markSegmentAt 同规则兜底）。
    function markSegment(kind) {
        segmentMenu.visible = false
        var pos = playerState.positionMs
        var dur = playerState.durationMs
        if (dur <= 0) { showNotice("影片未就绪"); return }
        if (kind === "intro" && pos > dur * 0.10) {
            showNotice("片头结束需在影片前 10% 内标记")
            return
        }
        if (kind === "outro" && pos < dur * 0.70) {
            showNotice("片尾开始需在影片后 30%（≥70%）标记")
            return
        }
        pipeServer.sendCommand({"type": "setSegmentMark",
                                "kind": kind, "positionMs": pos})
        showNotice(kind === "intro" ? "已标记片头结束" : "已标记片尾开始")
    }

    Timer {
        id: hideTimer
        interval: Theme.autoHideMs
        // 670 A3：媒体就绪前控件**常驻**（防加载窗口期自动隐藏，
        // 用户正好没看见）；开播后才走 5 秒自动隐藏。
        // 675 G：就绪判定补 durationMs>0（playerReady 在 Qt 模式可能
        // 恒 false → 自动隐藏永不启动，真机回归「长期无操作不隐藏」）。
        running: !playerState.paused
                 && (playerState.playerReady || playerState.durationMs > 0)
                 && playerState.controlsVisible
        onTriggered: playerState.controlsVisible = false
    }

    function showControls() {
        playerState.controlsVisible = true
        hideTimer.restart()
    }

    /// 674 A2：本地镜像容错封装——镜像失败只影响刷新，绝不中断
    /// 处理器（真机回归「patchValue is not a function → 全控件失效」）。
    /// 错误只记一次，防日志刷屏。
    property bool _patchWarned: false
    function patchState(key, v) {
        try {
            playerState.patchValue(key, v)
        } catch (e) {
            if (!_patchWarned) {
                _patchWarned = true
                console.warn("[overlay] patchState 失败（仅影响刷新）: " + e)
            }
        }
    }

    function closePanels() {
        panelOpen = false
        adjustOpen = false
        segmentMenu.visible = false
        // 675 D：点别处（含开面板）取消音量/亮度选中态
        selectedSlider = ""
    }

    function showGesture(iconOrText) {
        gestureIcon = iconOrText
        gestureTimer.restart()
    }

    function showNotice(text) {
        notice = text
        noticeTimer.restart()
    }

    Component.onCompleted: console.log(
        "[overlay] QML 就绪 controlsVisible=" + playerState.controlsVisible
        + " size=" + width + "x" + height)

    Timer { id: gestureTimer; interval: 700; onTriggered: root.gestureIcon = "" }
    Timer { id: noticeTimer; interval: 3000; onTriggered: root.notice = "" }

    // ── 669 A3：alpha≈0 全窗底（1/255，肉眼不可见）──
    // 保证每个像素都参与命中测试，堵死「全透明像素点击穿透」。
    // 670 A1：SAFE 降级时变深底（保证控件在任何合成环境下可见）。
    Rectangle {
        anchors.fill: parent
        z: -1000
        color: root.safeMode ? Qt.rgba(0.05, 0.05, 0.08, 0.35)
                             : Qt.rgba(0, 0, 0, 0.004)
    }

    // ── 手势层（669：共享组件 VideoGestures，与宿主双窗各挂一份）──
    VideoGestures {
        panelsOpen: () => root.panelOpen || root.adjustOpen
                         || segmentMenu.visible
        closePanels: root.closePanels
        showControls: () => hideTimer.restart()
        showGesture: (iconOrText) => root.showGesture(iconOrText)
        showSegmentMenu: (mx, my) => segmentMenu.openAt(mx, my)
        onTap: () => root.selectedSlider = ""
        wheelHandler: (dir) => {
            if (root.selectedSlider !== "") {
                root.adjustByWheel(root.selectedSlider, dir)
            }
        }
    }

    // ── 播放快捷键（与宿主共用组件）──
    PlayerShortcuts { }

    // 686：Esc **完全禁用**（用户明确要求「Esc 不做任何动作」）。
    //
    // 677 时这里有 `Connections { target: mpvWindow; onEscapePressed }`
    // 三层语义（收面板 → 退全屏 → requestExit + Qt.quit()）。C++ 的
    // EscapeFilter 已移除，信号不再发射，这段连接一并删除。
    //
    // 退出方式：单人点窗口关闭按钮，房间点面板窗 X（有确认框）。

    // ── 681：未播放占位（三端统一）──
    //
    // 【真机回归：房间内未播放时三端表现不一致】安卓/鸿蒙都有
    // 「▶ + 请从资源面板选择要播放的内容」，Windows 只是一片黑。
    //
    // 对齐基准（安卓 `NativePlayerScreenView` / 鸿蒙 `HimiNativePlayerView`）：
    // - 图标 `play_circle` 64，白 24%（`#3DFFFFFF`）
    // - 文字「请从资源面板选择要播放的内容」14，白 38%（`#62FFFFFF`）
    // - 间距 16，黑底居中
    //
    // 【层级】放在顶栏/底栏**之下**（z 低于控件），只在无内容时显示；
    // `enabled: false` 保证不抢手势（点屏仍可唤出控件）。
    Rectangle {
        id: placeholder
        anchors.fill: parent
        // 681：无内容时显示。`playerReady` 由 Dart 侧 `_prepared && !_disposed`
        // 决定（删空资源 / 尚未起播时为 false）。
        visible: !playerState.playerReady
        color: "#000000"
        z: -1

        Column {
            anchors.centerIn: parent
            spacing: 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Icons.playCircle
                font.family: iconFont.name
                font.pixelSize: 64
                color: Theme.white24
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "请从资源面板选择要播放的内容"
                color: Theme.white38
                font.pixelSize: 14
            }
        }
    }

    // ── 顶栏（渐变玻璃条：透明→黑 85%，视频透过来）──
    TopBar {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        showControls: playerState.controlsVisible
        decodeOpen: panel.visible && panel.title === "解码方式"
        adjustOpen: adjustPanel.visible
        videoFitMode: root.fitModes[root.fitIndex]
        onDecodeClicked: root.openDecodePanel()
        onSubtitleStyleClicked: root.openAdjustPanel()
        onVideoFitClicked: root.cycleVideoFitLocal()
    }

    // ── 底栏（渐变玻璃条）──
    BottomBar {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        showControls: playerState.controlsVisible

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
            danmakuOn = !danmakuOn
            root.patchState("danmakuEnabled", danmakuOn)
            // 676：签名同步置位（开关只重建一次，不再被 onChanged 重复触发）
            root.danmakuStyleSig = root.danmakuOn + "|"
                    + playerState.danmakuFontSize + "|"
                    + playerState.danmakuSpeed + "|"
                    + playerState.danmakuOpacity
            danmakuBuildTimer.restart()
            pipeServer.sendCommand({"type": "toggleDanmaku"})
        }
        onVersionClicked: root.openVersionPanel()
        onSubtitleClicked: root.openSubtitlePanel()
        onAudioClicked: root.openAudioPanel()
        onEpisodeClicked: root.openEpisodePanel()
        onSpeedClicked: root.openSpeedPanel()
        onFullscreenClicked: mpvWindow.toggleHostFullscreen()
        onSkipSegmentClicked: {
            // 677：房间观众不得跳片头/片尾（切集/seek 均属播放控制）
            if (!playerState.canControl) return
            pipeServer.sendCommand({"type": "skipSegment"})
        }
        selectedSlider: root.selectedSlider
        onSliderSelected: (which) => {
            root.selectedSlider = (root.selectedSlider === which) ? "" : which
        }
        onWheelAdjust: (which, dir) => root.adjustByWheel(which, dir)
        onVolumeChanged: (v) => {
            mpvWindow.setVolume(v)
            pipeServer.sendCommand({"type": "setVolume", "volume": v})
            root.patchState("volume", v)
        }
        onBrightnessChanged: (v) => {
            pipeServer.sendCommand({
                "type": "setBrightness", "brightness": v
            })
            root.patchState("brightness", v)
        }
        onSeekFinished: (ratio) => {
            var ms = Math.round(ratio * playerState.durationMs)
            mpvWindow.seekTo(ms)
            pipeServer.sendCommand({"type": "seekTo", "positionMs": ms})
            root.patchState("positionMs", ms)
        }
    }

    // ── 690/691：跳过片头/片尾**独立胶囊**（底栏水平居中）──
    //
    // 【为什么独立于 BottomBar】BottomBar 整体由 `controlsVisible` 控制
    // 透明度，胶囊放里面会跟着控件一起隐藏（真机反馈「跳过提示不该跟随
    // 其他控件隐藏，有自己的倒计时」）。
    //
    // 【位置】底栏高 96、胶囊高 34 → 垂直居中在底栏内 = bottomMargin 31。
    Rectangle {
        id: skipCapsule
        visible: playerState.skipPrompt === "intro"
                 || playerState.skipPrompt === "outro"
        // 底栏水平居中
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 31
        width: skipLabel.implicitWidth + 32
        height: 34
        radius: 17
        color: Qt.rgba(1, 1, 1, 0.16)
        border.color: theme.focusColor
        border.width: 1.2

        Behavior on opacity { NumberAnimation { duration: 160 } }
        opacity: visible ? 1 : 0

        Text {
            id: skipLabel
            anchors.centerIn: parent
            text: playerState.skipPrompt === "intro" ? "跳过片头" : "跳过片尾"
            color: Theme.white
            font.pixelSize: Theme.panelOptionSize
            font.weight: 600
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                // 677：房间观众不得跳片头/片尾
                if (!playerState.canControl) return
                pipeServer.sendCommand({"type": "skipSegment"})
            }
        }
    }

    // ── 左下角剧集 Logo（直接叠视频，无黑底）──
    EpisodeLogo {
        id: episodeLogo
        anchors.left: parent.left
        anchors.bottom: bottomBar.top
        anchors.leftMargin: Theme.barPadH
        anchors.bottomMargin: 8
    }

    // ── 673：选集封面预取（对齐安卓优先级预载的简化版）──
    // 播放期把全部选集封面按**卡片同尺寸**（544×300 = 272×150 ×2）
    // 预热进磁盘+内存缓存——首次开面板即秒开；Repeater 随 episodes
    // 变化自动增删，隐藏不渲染只解码。
    Item {
        visible: false
        width: 1
        height: 1
        Repeater {
            model: playerState.episodes
            delegate: Image {
                required property var modelData
                visible: false
                source: modelData.poster || ""
                sourceSize: Qt.size(544, 300)
                asynchronous: true
            }
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
        color: Qt.rgba(0, 0, 0, 0.55)

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

    // ── 674 C：片头/片尾标记面板（复刻安卓 TV `SegmentMarkPanel`）──
    // 标题行（剪刀 + 「片头 / 片尾」+ 当前位置）+ 两行设置项（行内
    // 范围红字警示：片头 ≤10%、片尾 ≥70%，点前即知）+ 已有标记走
    // 二次确认（更新 / 清除 / 取消），与安卓 TV 同交互。
    Rectangle {
        id: segmentMenu
        property real menuX: 0
        property real menuY: 0
        property string mode: "main"   // main / confirmIntro / confirmOutro

        readonly property int pos: playerState.positionMs
        readonly property int dur: playerState.durationMs
        readonly property bool hasIntro: playerState.segmentIntroEndMs >= 0
        readonly property bool hasOutro: playerState.segmentOutroStartMs >= 0
        readonly property string introReject:
            (dur > 0 && pos > dur * 0.10) ? "超出范围（片头 ≤10%）" : ""
        readonly property string outroReject:
            (dur > 0 && pos < dur * 0.70) ? "超出范围（片尾 ≥70%）" : ""

        function formatMs(ms) {
            var t = Math.max(0, ms)
            var h = Math.floor(t / 3600000)
            var m = Math.floor((t % 3600000) / 60000)
            var s = Math.floor((t % 60000) / 1000)
            var mm = (m < 10 ? "0" : "") + m
            var ss = (s < 10 ? "0" : "") + s
            return h > 0 ? (h + ":" + mm + ":" + ss) : (m + ":" + ss)
        }

        function openAt(mx, my) {
            menuX = mx
            menuY = my
            mode = "main"
            visible = true
        }

        function onMarkRow(kind) {
            // 已有标记 → 二次确认（安卓 TV 交互）
            if (kind === "intro" && hasIntro) { mode = "confirmIntro"; return }
            if (kind === "outro" && hasOutro) { mode = "confirmOutro"; return }
            markSegment(kind)
        }

        function existingMark(kind) {
            return kind === "intro" ? playerState.segmentIntroEndMs
                                   : playerState.segmentOutroStartMs
        }

        visible: false
        x: Math.max(8, Math.min(menuX, root.width - width - 8))
        y: Math.max(8, Math.min(menuY, root.height - height - 8))
        width: 320
        height: contentCol.implicitHeight + 28
        radius: 18
        color: Qt.rgba(0.07, 0.07, 0.09, 0.92)
        border.color: Qt.rgba(1, 1, 1, 0.12)
        border.width: 1

        Column {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 8

            // ── 标题行（照安卓：剪刀 + 片头/片尾 + 当前位置）──
            RowLayout {
                width: parent.width
                height: 28
                Text {
                    text: "\uf0c4"          // fa-scissors
                    font.family: iconFont.name
                    font.pixelSize: 18
                    color: Theme.mutedText
                }
                Item { Layout.preferredWidth: 8 }
                Text {
                    text: "片头 / 片尾"
                    color: theme.textColor
                    font.pixelSize: Theme.panelTitleSize
                    font.weight: 600
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "当前位置 " + segmentMenu.formatMs(segmentMenu.pos)
                    color: Theme.mutedText
                    font.pixelSize: Theme.captionSize
                }
            }

            // ── 主模式：两行设置项 ──
            Repeater {
                model: segmentMenu.mode === "main"
                       ? [
                           { kind: "intro", icon: Icons.skipNext,
                             title: "设置片头",
                             hint: "当前位置作为片头结束 / 正片开始" },
                           { kind: "outro", icon: Icons.skipPrevious,
                             title: "设置片尾",
                             hint: "当前位置作为片尾开始" }
                         ]
                       : []
                delegate: Rectangle {
                    required property var modelData
                    width: contentCol.width
                    height: 58
                    radius: 10
                    color: markRowMouse.containsMouse
                           ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

                    readonly property string reject:
                        modelData.kind === "intro" ? segmentMenu.introReject
                                                   : segmentMenu.outroReject
                    readonly property bool has:
                        modelData.kind === "intro" ? segmentMenu.hasIntro
                                                   : segmentMenu.hasOutro

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10
                        Text {
                            text: modelData.icon
                            font.family: iconFont.name
                            font.pixelSize: 18
                            color: theme.textColor
                        }
                        Column {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                width: parent.width
                                text: modelData.title
                                color: theme.textColor
                                font.pixelSize: Theme.panelOptionSize
                                font.weight: 600
                            }
                            Text {
                                width: parent.width
                                // 行内提示：超范围红字（点前即知，不用点了才被拒）
                                text: reject !== "" ? reject
                                      : (has ? "当前标记 "
                                             + segmentMenu.formatMs(
                                                 segmentMenu.existingMark(modelData.kind))
                                             + "（再点更新 / 清除）"
                                             : modelData.hint)
                                color: reject !== "" ? "#FF6B6B"
                                       : Theme.mutedText
                                font.pixelSize: Theme.captionSize
                                elide: Text.ElideRight
                            }
                        }
                    }
                    MouseArea {
                        id: markRowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: segmentMenu.onMarkRow(modelData.kind)
                    }
                }
            }

            // ── 二次确认（安卓 TV：更新 / 清除 / 取消）──
            Text {
                visible: segmentMenu.mode !== "main"
                width: contentCol.width
                wrapMode: Text.WordWrap
                text: "当前标记："
                      + segmentMenu.formatMs(segmentMenu.existingMark(
                          segmentMenu.mode === "confirmIntro" ? "intro" : "outro"))
                      + "\n要用当前位置（" + segmentMenu.formatMs(segmentMenu.pos)
                      + "）更新，还是清除？"
                color: theme.textColor
                font.pixelSize: Theme.panelOptionSize
            }
            Repeater {
                model: segmentMenu.mode !== "main"
                       ? [
                           { act: "update", label: "更新" },
                           { act: "clear", label: "清除" },
                           { act: "cancel", label: "取消" }
                         ]
                       : []
                delegate: Rectangle {
                    required property var modelData
                    width: contentCol.width
                    height: 40
                    radius: 8
                    color: confirmRowMouse.containsMouse
                           ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: modelData.act === "clear" ? "#FF6B6B"
                               : theme.textColor
                        font.pixelSize: Theme.panelOptionSize
                    }
                    MouseArea {
                        id: confirmRowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var kind = segmentMenu.mode === "confirmIntro"
                                    ? "intro" : "outro"
                            if (modelData.act === "update") {
                                markSegment(kind)
                            } else if (modelData.act === "clear") {
                                segmentMenu.visible = false
                                pipeServer.sendCommand({
                                    "type": "clearSegmentMark", "kind": kind})
                                root.showNotice("已清除片头/片尾标记")
                            } else {
                                segmentMenu.mode = "main"
                            }
                        }
                    }
                }
            }
        }
    }

    // ── 列表面板（液态玻璃卡；无 ✕：toggle/点空白收回）──
    Panel {
        id: panel
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: Theme.panelRight
        anchors.topMargin: Theme.panelTopOffset
        visible: root.panelOpen
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
        visible: root.adjustOpen
        onClosed: root.closePanels()
        onAdjust: (key, value) => {
            root.patchState(key, value)
            pipeServer.sendCommand({
                "type": "adjustDisplay", "key": key, "value": value
            })
        }
        onReset: (scope) => {
            // 672 A2：本地一次镜像全部默认值（滑杆齐回默认位）+ 命令
            if (scope !== "danmaku") {
                root.patchState("subtitleScale", 1.0)
                root.patchState("subtitleMarginY", 22)
                root.patchState("subtitleDelayMs", 0.0)
            }
            if (scope !== "subtitle") {
                root.patchState("danmakuSpeed", 0.7)
                root.patchState("danmakuFontSize", 0.5)
                root.patchState("danmakuOpacity", 0.8)
            }
            pipeServer.sendCommand({"type": "resetDisplay", "scope": scope})
        }
    }

    // ── 本地字幕文件选择 ──
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

    // ── 播完自动下一集 ──
    Connections {
        target: mpvWindow
        function onPlaybackEnded() {
            // 677：房间观众不得自动切集（切集是房主节奏）
            if (!playerState.canControl) return
            if (playerState.currentEpisodeIndex >= 0
                && playerState.currentEpisodeIndex < playerState.episodeCount - 1) {
                pipeServer.sendCommand({"type": "selectEpisode",
                                        "index": playerState.currentEpisodeIndex + 1})
            } else {
                root.showNotice("所有剧集播放完毕")
            }
        }
    }

    // ── 弹幕 ASS 旁路（弹幕行 + 渐变遮罩同轨；开关只增减弹幕行）──
    Timer {
        id: danmakuBuildTimer
        interval: 600
        onTriggered: root.buildDanmakuAss()
    }
    Connections {
        target: playerState
        function onDanmakuChanged() { danmakuBuildTimer.restart() }
    }
    // 【676】显示调节的弹幕三键（大小/速度/透明度）变化即重建 ASS。
    // 旧实现只有新弹幕到达（onDanmakuChanged）才重建 → 拖滑杆"没有任何
    // 反应"（675 的速度/透明度渲染逻辑因此也从未激活）。用签名比对，
    // 避免 20Hz 状态推送把 ASS 重建刷爆。
    property string danmakuStyleSig: ""
    Connections {
        target: playerState
        function onChanged() {
            var sig = root.danmakuOn + "|" + playerState.danmakuFontSize
                    + "|" + playerState.danmakuSpeed
                    + "|" + playerState.danmakuOpacity
            if (sig === root.danmakuStyleSig) return
            root.danmakuStyleSig = sig
            danmakuBuildTimer.restart()
        }
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
        var c = (hex || "#FFFFFF").replace("#", "")
        if (c.length < 6) c = "FFFFFF"
        return "&H00" + c.substring(4, 6) + c.substring(2, 4)
                 + c.substring(0, 2)
    }

    function buildDanmakuAss() {
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

        lines.push("")
        lines.push("[Events]")
        lines.push("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text")

        var rows = Math.max(4, Math.floor((H - 80) / (fs + 6)))
        // 【675 E】速度 → 飞过时长（speed 越大越快）；透明度 → ASS alpha
        var speed = Math.max(0.5, playerState.danmakuSpeed)
        var opacity = Math.max(0.1, Math.min(1.0, playerState.danmakuOpacity))
        var alphaTag = "\\alpha&H"
                + ("0" + Math.round((1 - opacity) * 255).toString(16)).slice(-2)
                + "&"
        // 【675 E】防叠行：每行/每槽「最早可用时刻」，来弹幕优先取
        // 空闲槽，同槽必有间隔——不再叠成一坨。
        var rowFreeAt = [], topFreeAt = [], botFreeAt = []
        for (var r = 0; r < rows; r++) rowFreeAt.push(0)
        for (var r = 0; r < 3; r++) { topFreeAt.push(0); botFreeAt.push(0) }
        function pickSlot(freeArr, t0) {
            var best = 0
            for (var k = 0; k < freeArr.length; k++) {
                if (freeArr[k] <= t0) return k
                if (freeArr[k] < freeArr[best]) best = k
            }
            return best
        }
        var sorted = items.slice().sort(function (a, b) {
            return a.timeMs - b.timeMs
        })
        for (var i = 0; i < sorted.length; i++) {
            var it = sorted[i]
            var t0 = it.timeMs / 1000
            var body = (it.text || "").replace(/\\\\/g, "\\")
                                     .replace(/\{/g, "(")
                                     .replace(/\}/g, ")")
                                     .replace(/\n/g, " ")
            var col = assColor(it.color) + alphaTag
            var dur = (it.mode === "scroll") ? (8.0 / speed) : 4
            var eff2
            if (it.mode === "top") {
                var slotT = pickSlot(topFreeAt, t0)
                topFreeAt[slotT] = t0 + 4
                eff2 = "{\\an8\\pos(" + Math.round(W / 2) + ","
                        + (30 + slotT * (fs + 6)) + ")\\c" + col + "}"
            } else if (it.mode === "bottom") {
                var slotB = pickSlot(botFreeAt, t0)
                botFreeAt[slotB] = t0 + 4
                eff2 = "{\\an2\\pos(" + Math.round(W / 2) + ","
                        + ((H - 30) - slotB * (fs + 6)) + ")\\c" + col + "}"
            } else {
                var slotS = pickSlot(rowFreeAt, t0)
                rowFreeAt[slotS] = t0 + dur * 0.55
                var y2 = 20 + slotS * (fs + 6)
                eff2 = "{\\move(" + (W + 120) + "," + y2 + "," + -120 + "," + y2
                        + ")\\c" + col + "}"
            }
            lines.push("Dialogue: 0," + assTime(t0) + "," + assTime(t0 + dur)
                        + ",Danmaku,,0,0,0,," + eff2 + body)
        }
        mpvWindow.setDanmakuAss(lines.join("\n"))
    }

    // ── 面板内容（内容/标题对齐 Flutter）──
    function openEpisodePanel() {
        if (panelOpen && panel.title === "选集") { closePanels(); return }
        var list = []
        for (var i = 0; i < playerState.episodes.length; i++) {
            var e = playerState.episodes[i]
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
        panel.currentIndex = playerState.currentEpisodeIndex
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
                // 672 B1：选中真相 = 顶层 selectedAudioId（与安卓/鸿蒙
                // 同源；每轨 selected 在 Qt 模式可能恒 false）
                display: t.label !== "" ? t.label
                         : (t.title !== "" ? t.title : "音轨 " + t.id),
                sub: t.lang,
                selected: t.id === playerState.selectedAudioId || t.selected
            })
        }
        if (list.length === 0) {
            list.push({id: -1, display: "无可用音轨", sub: "", selected: false})
        }
        panel.title = "音轨"
        panel.cardMode = false
        panel.items = list
        adjustOpen = false
        panelOpen = true
    }

    function openSubtitlePanel() {
        if (panelOpen && panel.title === "字幕") { closePanels(); return }
        // 672 B1：选中真相 = 顶层 selectedSubtitleId（0 = 关闭字幕）
        var list = [{
            id: -1,
            display: "关闭字幕",
            sub: "",
            selected: playerState.selectedSubtitleId <= 0
        }]
        for (var i = 0; i < playerState.subtitleTracks.length; i++) {
            var t = playerState.subtitleTracks[i]
            list.push({
                id: t.id,
                display: t.label !== "" ? t.label
                         : (t.title !== "" ? t.title : "字幕 " + t.id),
                sub: t.lang,
                selected: t.id === playerState.selectedSubtitleId || t.selected
            })
        }
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

    /// 倍速标签（与 Flutter `formatSpeedLabel` 一致）
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
        // 677：房间观众不得切集/切版本/改倍速（对齐安卓
        // `buildEpisodeContent` 的 canControl 门 + 鸿蒙同款）。
        // 字幕/音轨是本地 UI，两端都保留。
        // 674 A2：命令先行、镜像后置（镜像失效不影响操作）
        if (panel.title === "选集") {
            if (!playerState.canControl) return
            pipeServer.sendCommand({"type": "selectEpisode", "index": id})
            root.patchState("currentEpisodeIndex", id)
        } else if (panel.title === "音轨") {
            mpvWindow.selectTrack("audio", id > 0 ? id - 1 : -1)
            pipeServer.sendCommand({"type": "selectAudio", "id": id})
            root.patchState("selectedAudioId", id > 0 ? id : 0)
        } else if (panel.title === "字幕") {
            if (id === -2) {
                subDialog.open()
                return
            }
            mpvWindow.selectTrack("subtitle", id > 0 ? id - 1 : -1)
            pipeServer.sendCommand({"type": "selectSubtitle", "id": id})
            root.patchState("selectedSubtitleId", id > 0 ? id : 0)
        } else if (panel.title === "倍速") {
            if (!playerState.canControl) return
            mpvWindow.setSpeed(id)
            pipeServer.sendCommand({"type": "setSpeed", "speed": id})
            root.patchState("speed", id)
        } else if (panel.title === "版本") {
            if (!playerState.canControl) return
            pipeServer.sendCommand({"type": "selectVersion", "index": id})
            root.patchState("currentVersionIndex", id)
        } else if (panel.title === "解码方式") {
            pipeServer.sendCommand({"type": "setDecodeMode", "mode": id})
            root.patchState("decodeMode", id)
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
        root.patchState("videoFit", m)
        pipeServer.sendCommand({"type": "cycleVideoFit"})
    }

    /// 跳过片头/片尾
    function skipSegmentLocal() {
        // 677：房间观众不得跳片头片尾（切集/seek 都属于播放控制）
        if (!playerState.canControl) return
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

    // ── 680/687：无边框窗口的 8 向拉伸热区（**仅房间模式**）──
    //
    // 单人模式有原生边框，缩放交给系统；这里必须隐藏，
    // 否则最外 6px 会拦截系统缩放。
    //
    // 【为什么放最后】QML 后声明者 z 序更高。热区只在窗口最外 6px，
    // 与顶栏拖拽区（startSystemMove）、按钮区域都不重叠。
    WindowResizeEdges {
        anchors.fill: parent
        visible: playerState.isRoom
    }
}
