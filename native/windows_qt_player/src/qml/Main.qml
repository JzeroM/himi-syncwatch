import QtQuick
import HimiPlayer

// 668：视频宿主窗口（主窗口）。
//
// 【架构】mpv wid 直出在本窗客户区（HDR 零拷贝路径不变）；全部控件
// 在**逐像素透明悬浮窗** Overlay.qml（顶层窗口盖住视频子窗口 = 真
// 合成，液态玻璃任意半透明、零黑底）。本窗只承载视频 + 标题栏 + 共享
// 快捷键；Overlay 由 main.cpp 创建并恒贴附本窗客户区。
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

    // 播放快捷键（两窗共用组件；焦点在任一窗都有效）
    PlayerShortcuts { }

    Shortcut {
        sequence: "Escape"
        onActivated: {
            pipeServer.sendCommand({"type": "requestExit"})
            Qt.quit()
        }
    }
}
