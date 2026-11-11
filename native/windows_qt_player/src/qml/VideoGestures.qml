import QtQuick
import HimiPlayer

// 672：视频区手势层（宿主窗口与控件悬浮层**共用组件**，两窗各挂一份）。
//
// 【为什么双份】手势必须落在「鼠标事件实际到达的那个窗口」。悬浮层在
// 视频之上时事件落在悬浮层；悬浮层意外失活时点击穿透（视频子窗
// WS_EX_TRANSPARENT）落到宿主——两份实例由 Win32 z-order 天然互斥，
// 永远只有一份收到事件，不会双触发。
//
// 【手势语义（672 定稿）】
//   单击：面板开→收回；否则切控件显隐（按下瞬间快照判定，防唤出秒消）
//   双击：播放/暂停 + 手势图标
//   右击：片头/片尾标记菜单（画面任意位置；范围校验片头 ≤10%、片尾 ≥70%）
//   滚轮：转交 wheelHandler（选中滑杆调节）；拖拽类手势（seek/音量/
//   亮度）按用户要求**全部去除**
//
// 【控件显隐走共享状态】playerState.controlsVisible——悬浮层绑定渲染，
// 任一实例都能唤出控件层（点击唤出在任何 z-order 状态下都有效）。
Item {
    id: root
    anchors.fill: parent

    /// 面板是否开着（点击=收回面板）。宿主实例无面板 → 默认恒 false。
    property var panelsOpen: () => false
    /// 收起面板（悬浮层注入）。
    property var closePanels: () => {}
    /// 唤出控件的补充动作（悬浮层注入：重启自动隐藏计时）。
    /// 轻量实例留 null：只写共享状态也生效。
    property var showControls: null
    /// 手势图标提示（悬浮层注入）；宿主实例留 null = 不提示。
    property var showGesture: null
    /// 672：右键标记菜单（悬浮层注入：(x, y) 弹片头/片尾菜单）。
    property var showSegmentMenu: null
    /// 672：滚轮转交（悬浮层注入：(delta) 调选中滑杆）；null = 忽略。
    property var wheelHandler: null
    /// 675 D：点视频区（tap 判定落定时）回调——取消音量/亮度选中态。
    property var onTap: null

    function doShowControls() {
        playerState.controlsVisible = true
        if (showControls) showControls()
    }

    function notifyGesture(iconOrText) {
        if (showGesture) showGesture(iconOrText)
    }

    MouseArea {
        id: videoArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        // 按下瞬间的显隐快照（tapTimer 按它判定，防「唤出秒消」）。
        property bool wasVisible: true

        onPositionChanged: (mouse) => root.doShowControls()

        onPressed: (mouse) => {
            wasVisible = playerState.controlsVisible
            root.doShowControls()
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                if (root.showSegmentMenu) {
                    root.showSegmentMenu(mouse.x, mouse.y)
                }
                return
            }
            tapTimer.restart()
        }

        onDoubleClicked: {
            tapTimer.stop()
            // 【675 H】Flutter 语义（playPauseHintIcon 测试钉死）：显示
            // 切换后的「当前可执行动作」——播完→⏸、暂停后→▶。
            // **先算目标态再切换**：toggle 后读 playerState.paused 是
            // 旧值（mpv 事件异步回填）→ 图标恰好相反（真机回归）。
            var willBePlaying = playerState.paused
            mpvWindow.togglePause()
            pipeServer.sendCommand({"type": "togglePlay"})
            root.notifyGesture(willBePlaying ? Icons.pauseCircle
                                             : Icons.playCircle)
        }

        onWheel: (wheel) => {
            if (root.wheelHandler) {
                root.wheelHandler(wheel.angleDelta.y > 0 ? 1 : -1)
                wheel.accepted = true
            }
        }
    }

    Timer {
        id: tapTimer
        interval: 250
        onTriggered: {
            // 675 D：点别处取消滑杆选中态
            if (root.onTap) root.onTap()
            // Flutter `_onVideoAreaTap` 语义（按下瞬间快照判定）
            if (root.panelsOpen()) {
                root.closePanels()
                return
            }
            if (videoArea.wasVisible) {
                playerState.controlsVisible = false
            } else {
                root.doShowControls()
            }
        }
    }
}
