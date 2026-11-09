import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiWin

// 654：Windows 播放器窗口 spike 的外壳。
//
// 【为什么这里几乎是空的】
// 视频**不**由 QML 绘制——mpv 直接拥有一个原生子 HWND（`wid` 直出），
// 这样 HDR 才能由 mpv 与显示器直接协商。QML 负责的只是窗口本身。
//
// 【提示条为什么能看见】
// 原生子 HWND 永远画在 QML/Skia 内容之上（Win32 硬规则）。所以 C++ 侧
// 会把 mpv 子窗口的高度减去提示条高度，给 QML 留出可见区域——这同时
// 也是对「几何同步是否可靠」的验证。全屏时提示条隐藏、inset 归零。
//
// 655 之后提示条会变成真正的底栏（进度条/播放控制/音量/倍速/全屏）。
ApplicationWindow {
    id: root
    width: 1280
    height: 720
    visible: true
    minimumWidth: 480
    minimumHeight: 270
    title: "HIMI Qt Spike — 等待 mpv 初始化…"

    // 黑底：HDR 首帧到来前不闪白。
    color: "#000000"

    readonly property bool fullScreen: visibility === Window.FullScreen

    // 底部提示条（不遮挡视频关键区域，仅作操作说明）
    Rectangle {
        id: hintBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 28
        visible: !root.fullScreen
        color: "#B0000000"

        Text {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            color: "#CCFFFFFF"
            font.pointSize: 9
            text: "空格=暂停   F=全屏   H=切HDR   S=验证步骤   Esc=退出"
        }
    }
}
