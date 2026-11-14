import QtQuick
import HimiPlayer

/// 697：播放调试信息（Windows Qt 播放窗）——**纯文字叠加**。
///
/// ## 为什么是文字而不是浮层面板
///
/// 真机回归：浮层面板把 `height` 绑定到内容列的 `implicitHeight`，而
/// 指标定时刷新、某些行（如「P5 风险」）会随数据出现/消失 → 行数变化
/// → 面板高度跳变 → 透明叠加窗每秒重绘 → 与下面 mpv 的 D3D11 交换链
/// 合成冲突 → **视频画面每秒闪一下**。
///
/// 用户实测确认「不打开面板就不闪」，直接证实了这条链路。
///
/// 文字叠加的差别：
/// - 根节点就是 `Column`，**没有**任何 `height`/`width` 绑定到内容
/// - 无背景矩形、无圆角、无边框（合成层极简）
/// - 行数变化只影响自身绘制，不改变任何窗口几何
///
/// ## 数据来源（Windows 独有）
///
/// `playerState.debugText` 由 Qt 侧 `MpvWindow::debugText()` 生成
///（`main.cpp` 的 2s 定时器）。
///
/// 【为什么不是 Flutter 下发】Qt 模式下 mpv 跑在独立进程里，Dart 的
/// `_player` 是空闲引擎（`_prepared` 恒 false）——从它读属性恒为空
///（真机截图：色彩/位深/gpu-api 全空）。这是 Windows 与其他三端的
/// **必要差异**：其他三端 Flutter 与 mpv 同进程，可以下发。
Column {
    id: root

    /// 设置项开关（Dart 侧下发 `showDebug`）。
    property bool shown: false

    /// 本次开关周期内是否被用户手动关闭过。
    ///
    /// 【为什么需要】关闭按钮不能直接写 `shown = false`——那会打断
    /// `shown: playerState.showDebug` 的绑定，之后在设置里重新打开也
    /// 不会生效。改为本地置 `dismissed`，等 `shown` 再次变 true 时复位。
    property bool dismissed: false

    /// 关闭请求（由 Overlay 接到设置项）。
    signal closed()

    /// 锁定态隐藏（与安卓/鸿蒙一致：锁定后只留锁钮）。
    visible: shown && !dismissed && !playerState.locked

    // 设置项重新打开时复位 dismissed（否则手动关过一次就再也打不开）
    onShownChanged: {
        if (shown) dismissed = false
    }

    // 【根节点就是 Column】不设 height/width 绑定——彻底断开
    // 「内容高度 → 容器高度」这条链。可读性由文字 Outline 描边保证。
    spacing: 2

    // 左上角固定锚定：让开顶栏。
    // 【为什么不会闪】本项不是窗口根；外层 Overlay 是固定尺寸的 Window，
    // 子项尺寸变化不会引起窗口重排/重绘。
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.leftMargin: 16
    anchors.topMargin: 56
    z: 100

    /// 文字块宽度上限（超出换行，避免长文本横向撑开）。
    readonly property int textMaxWidth: 420

    // ── 标题行（带关闭按钮）──
    Row {
        spacing: 8

        Text {
            text: "播放调试"
            color: "#66FF99"
            font.pixelSize: 11
            font.bold: true
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.85)
        }

        Text {
            text: "\u2715"
            color: "#8AFFFFFF"
            font.pixelSize: 12
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.85)
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.dismissed = true
                    root.closed()
                }
            }
        }
    }

    // ── 指标正文（多行）──
    Text {
        width: root.textMaxWidth
        text: playerState.debugText
        color: "#CCFFFFFF"
        font.pixelSize: 11
        // 描边保证在亮画面上也能看清（不依赖任何背景）
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.85)
        lineHeight: 1.35
        wrapMode: Text.WordWrap
    }

    // ── 空态提示（数据尚未就绪）──
    Text {
        visible: playerState.debugText.length === 0
        text: "（等待播放数据）"
        color: "#8AFFFFFF"
        font.pixelSize: 11
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.85)
    }
}
