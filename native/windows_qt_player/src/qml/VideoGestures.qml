import QtQuick
import HimiPlayer

// 669：视频区手势层（宿主窗口与控件悬浮层**共用组件**，两窗各挂一份）。
//
// 【为什么双份】手势必须落在「鼠标事件实际到达的那个窗口」。悬浮层在
// 视频之上时事件落在悬浮层；悬浮层意外失活时点击穿透（视频子窗
// WS_EX_TRANSPARENT）落到宿主——两份实例由 Win32 z-order 天然互斥，
// 永远只有一份收到事件，不会双触发。
//
// 【手势语义（Flutter video_gesture_layer 同构）】
//   单击：面板开→收回；否则切控件显隐（按下瞬间快照判定，防唤出秒消）
//   双击：播放/暂停 + 手势图标；横拖 seek（100px≈5s）；纵拖右音量/左亮度
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
        acceptedButtons: Qt.LeftButton

        property real startX: 0
        property real startY: 0
        property real pressX: 0
        property real startVolume: 0
        property real startBrightness: 0
        property real seekAccum: 0
        property bool dragging: false
        // 按下瞬间的显隐快照（tapTimer 按它判定，防「唤出秒消」）。
        property bool wasVisible: true

        onPositionChanged: (mouse) => {
            root.doShowControls()
            if (!pressed) return
            var dx = mouse.x - startX
            var dy = mouse.y - startY
            if (!dragging && (Math.abs(dx) > 12 || Math.abs(dy) > 12)) {
                dragging = true
            }
            if (!dragging) return
            if (Math.abs(dx) > Math.abs(dy)) {
                seekAccum = dx / 100 * 5000
                var deltaS = Math.round(seekAccum / 1000)
                root.notifyGesture((deltaS >= 0 ? "+" : "") + deltaS + "s")
            } else if (pressX > width / 2) {
                var v = Math.max(0, Math.min(1, startVolume - dy / 300))
                mpvWindow.setVolume(v)
                pipeServer.sendCommand({"type": "setVolume", "volume": v})
                root.notifyGesture(Icons.volumeUp)
            } else {
                var b = Math.max(0, Math.min(1, startBrightness - dy / 300))
                pipeServer.sendCommand({"type": "setBrightness", "brightness": b})
                root.notifyGesture(Icons.brightness)
            }
        }

        onPressed: (mouse) => {
            startX = mouse.x
            startY = mouse.y
            pressX = mouse.x
            startVolume = playerState.volume
            startBrightness = playerState.brightness
            seekAccum = 0
            dragging = false
            wasVisible = playerState.controlsVisible
            root.doShowControls()
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

        onClicked: tapTimer.restart()
        onDoubleClicked: {
            tapTimer.stop()
            mpvWindow.togglePause()
            pipeServer.sendCommand({"type": "togglePlay"})
            root.notifyGesture(playerState.paused ? Icons.playCircle
                                                  : Icons.pauseCircle)
        }
    }

    Timer {
        id: tapTimer
        interval: 250
        onTriggered: {
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
