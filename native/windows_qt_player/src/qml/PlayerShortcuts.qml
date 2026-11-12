import QtQuick
import HimiPlayer

// 668：播放器快捷键（宿主窗口与控件悬浮层共用组件）。
//
// 【为什么两处都要】控件在逐像素透明悬浮窗（Overlay.qml），但点击
// 标题栏/视频区后焦点可能落在宿主窗口（Main.qml）——两窗都挂本组件，
// 键盘永远有效。操作先本地直驱 mpvWindow，再通知 Flutter 记账。
Item {
    id: root
    anchors.fill: parent

    Shortcut { sequence: "Space"; onActivated: {
        // 677：房间观众不得键盘播放/暂停
        if (!playerState.canControl) return
        mpvWindow.togglePause()
        pipeServer.sendCommand({"type": "togglePlay"})
    } }
    Shortcut { sequence: "Left"; onActivated: {
        // 677：房间观众不得键盘 seek
        if (!playerState.canControl) return
        mpvWindow.seekTo(Math.max(0, playerState.positionMs - 10000))
        pipeServer.sendCommand({"type": "seekRelative", "deltaMs": -10000})
    } }
    Shortcut { sequence: "Right"; onActivated: {
        if (!playerState.canControl) return
        mpvWindow.seekTo(playerState.positionMs + 10000)
        pipeServer.sendCommand({"type": "seekRelative", "deltaMs": 10000})
    } }
    Shortcut { sequence: "Up"; onActivated: {
        var v = Math.min(1, playerState.volume + 0.05)
        mpvWindow.setVolume(v)
        pipeServer.sendCommand({"type": "setVolume", "volume": v})
    } }
    Shortcut { sequence: "Down"; onActivated: {
        var v = Math.max(0, playerState.volume - 0.05)
        mpvWindow.setVolume(v)
        pipeServer.sendCommand({"type": "setVolume", "volume": v})
    } }
    Shortcut { sequence: "F"; onActivated: mpvWindow.toggleHostFullscreen() }
    // 677：F11 与 F 并存（Windows 用户习惯）
    Shortcut { sequence: "F11"; onActivated: mpvWindow.toggleHostFullscreen() }
    // 686：Esc 完全禁用——C++ 侧 EscapeFilter / escapePressed 已删除，
    // 两窗 QML 也都没有 Escape Shortcut。按 Esc 不做任何动作。
}
