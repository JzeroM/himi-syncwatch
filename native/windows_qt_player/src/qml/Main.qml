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
    // 687：**默认带原生标题栏**（单人播放需要最小化/最大化/关闭三钮）。
    //
    // 房间模式由 C++ 的 `MpvWindow::setRoomChrome(true)` 去掉边框——
    // 那里改 `GWL_STYLE` 位，不会重建窗口（QML 改 flags 会销毁重建，
    // 导致播放中断 + `wid` 绑定失效黑屏）。
    //
    // 【680 真机回归：Qt 窗不进任务栏】必须显式保留 `Qt.Window` 类型位，
    // 否则退化成 `WS_POPUP`，Win32 不给它任务栏图标。
    flags: Qt.Window

    // 播放快捷键（两窗共用组件；焦点在任一窗都有效）
    PlayerShortcuts { }

    // 669：手势兜底实例（共享组件，两窗 z-order 互斥只有一份收到事件）。
    // 悬浮层失活时点击穿透（视频子窗 WS_EX_TRANSPARENT）落到本窗——
    // 双击暂停/横滑 seek/点击唤出控件仍然有效。
    VideoGestures { }

    // 695：Esc 由 C++ `KeyRouter` 窗口级转发（escapePressed 信号），
    // 三层阶梯（收面板 → 退全屏 → requestExit）单点连接在 Overlay.qml。
    // 686 曾完全禁用 Esc（真凶：本窗旧实现 requestExit+Qt.quit()，全屏时
    // 会直接关掉播放器）——现全屏先退全屏，阶梯语义根治该问题。
}
