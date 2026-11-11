import QtQuick
import QtQuick.Controls.Basic
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
    // 670：由 main.cpp 控制显示时机（--prewarm 隐藏待命，收到 load 才弹出）
    visible: false
    title: (playerState.title !== "" ? playerState.title + " — HIMI" : "HIMI Player")
           + (playerState.windowDiag !== "" ? " [" + playerState.windowDiag + "]" : "")
    color: "#000000"
    flags: Qt.Window

    // 播放快捷键（两窗共用组件；焦点在任一窗都有效）
    PlayerShortcuts { }

    // 669：手势兜底实例（共享组件，两窗 z-order 互斥只有一份收到事件）。
    // 悬浮层失活时点击穿透（视频子窗 WS_EX_TRANSPARENT）落到本窗——
    // 双击暂停/横滑 seek/点击唤出控件仍然有效。
    VideoGestures { }

    // 677：Escape 已由 C++ 统一拦截（`MpvWindow::escapePressed`），
    // 本窗**不再**挂 Escape Shortcut。
    //
    // 【真凶】旧实现这里是 `requestExit + Qt.quit()`，而 Overlay 才有
    // 「收面板→退全屏→退出」三层。焦点落在宿主窗（点标题栏/视频区）
    // 时按 Esc，全屏状态下会**直接关掉播放器**（用户要求「房间模式
    // 全屏别出问题」，这条必须先堵）。
}
