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
    // 679：无边框——去掉系统标题栏（最小化/最大化/关闭三钮）。
    //
    // 【为什么】房间模式下 Qt 窗是「播放器」，退出统一走 Flutter 面板窗
    // 的确认流程（避免用户误点 X 直接杀掉播放窗、房间悬空）。
    // 无边框后拖动/缩放由 TopBar 拖拽区 + WindowResizeEdges 接管。
    //
    // 【680 真机回归：Qt 窗不进任务栏】旧值只写 `Qt.FramelessWindowHint`
    // ——这行**完全替换** flags，类型位从 `Qt::Window`(0x1) 退化成
    // `Qt::Widget`(0x0)，Qt 在 Windows 上改走 `WS_POPUP`；Win32 规则下
    // `WS_POPUP` 窗口不进任务栏（除非有 WS_EX_APPWINDOW）。
    // 必须显式保留 `Qt.Window` 类型位（C++ 侧再补 WS_EX_APPWINDOW 兜底）。
    flags: Qt.Window | Qt.FramelessWindowHint

    // 播放快捷键（两窗共用组件；焦点在任一窗都有效）
    PlayerShortcuts { }

    // 669：手势兜底实例（共享组件，两窗 z-order 互斥只有一份收到事件）。
    // 悬浮层失活时点击穿透（视频子窗 WS_EX_TRANSPARENT）落到本窗——
    // 双击暂停/横滑 seek/点击唤出控件仍然有效。
    VideoGestures { }

    // 686：Esc **完全禁用**——C++ 的 EscapeFilter 与 `escapePressed`
    // 信号均已删除，本窗也没有 Escape Shortcut。按 Esc 不做任何动作。
    //
    // 【真凶】旧实现这里是 `requestExit + Qt.quit()`，而 Overlay 才有
    // 「收面板→退全屏→退出」三层。焦点落在宿主窗（点标题栏/视频区）
    // 时按 Esc，全屏状态下会**直接关掉播放器**（用户要求「房间模式
    // 全屏别出问题」，这条必须先堵）。
}
