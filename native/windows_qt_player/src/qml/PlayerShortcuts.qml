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

    // 695：Space 移入 C++ `KeyRouter`（窗口事件过滤器）——真机回归
    // 「空格暂停/播放现状无效」：QML Shortcut 被焦点控件 shortcut-override
    // 吞掉/双窗作用域不稳，收不到键。canControl 门禁（房间观众禁用）与
    // togglePlay 记账在 KeyRouter 内完成。
    //
    // 本组件只保留不与焦点控件冲突的按键（←/→/↑/↓/F/F11）。
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
    // 695：Esc 由 C++ `KeyRouter` 窗口级转发（escapePressed 信号），
    // 三层阶梯单点连接在 Overlay.qml：收面板 → 退全屏 → requestExit
    //（单人=关 Qt 回详情页；房间=解散/离开确认）。
}
