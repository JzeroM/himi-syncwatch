import QtQuick
import HimiPlayer

// 680：无边框窗口的 8 向拉伸区。
//
// 【为什么需要】`Qt.FramelessWindowHint` 去掉了系统边框，Windows 不再
// 提供边缘拉伸热区（真机回归「Qt 窗无法拉伸长和高」）。这里用 8 个
// 6px 宽的 MouseArea 补回系统行为，按下即调 `startSystemResize`——
// 交给系统做原生拉伸（带最小尺寸约束、DWM 吸附），比自己算 delta 稳。
//
// 【位掩码】与 `MpvWindow::startSystemResize(edges)` 约定一致：
//   1 = 左, 2 = 上, 4 = 右, 8 = 下（组合相加）
//
// 【层级】装配在 Overlay 最上层（z 最高），但只占最外 6px —— 与顶栏
// 拖拽区（startSystemMove）不重叠，按钮也不在这 6px 内。
Item {
    id: root
    anchors.fill: parent

    readonly property int edge: 6      // 热区宽度
    readonly property int corner: 10   // 角落热区（略大，好抓）

    // ── 四条边 ──
    MouseArea {
        x: root.corner
        y: 0
        width: parent.width - root.corner * 2
        height: root.edge
        cursorShape: Qt.SizeVerCursor
        onPressed: mpvWindow.startSystemResize(2)  // 上
    }
    MouseArea {
        x: root.corner
        y: parent.height - root.edge
        width: parent.width - root.corner * 2
        height: root.edge
        cursorShape: Qt.SizeVerCursor
        onPressed: mpvWindow.startSystemResize(8)  // 下
    }
    MouseArea {
        x: 0
        y: root.corner
        width: root.edge
        height: parent.height - root.corner * 2
        cursorShape: Qt.SizeHorCursor
        onPressed: mpvWindow.startSystemResize(1)  // 左
    }
    MouseArea {
        x: parent.width - root.edge
        y: root.corner
        width: root.edge
        height: parent.height - root.corner * 2
        cursorShape: Qt.SizeHorCursor
        onPressed: mpvWindow.startSystemResize(4)  // 右
    }

    // ── 四个角（放在最后 → z 序更高，优先命中）──
    MouseArea {
        x: 0
        y: 0
        width: root.corner
        height: root.corner
        cursorShape: Qt.SizeFDiagCursor
        onPressed: mpvWindow.startSystemResize(1 | 2)  // 左上 = 3
    }
    MouseArea {
        x: parent.width - root.corner
        y: 0
        width: root.corner
        height: root.corner
        cursorShape: Qt.SizeBDiagCursor
        onPressed: mpvWindow.startSystemResize(4 | 2)  // 右上 = 6
    }
    MouseArea {
        x: 0
        y: parent.height - root.corner
        width: root.corner
        height: root.corner
        cursorShape: Qt.SizeBDiagCursor
        onPressed: mpvWindow.startSystemResize(1 | 8)  // 左下 = 9
    }
    MouseArea {
        x: parent.width - root.corner
        y: parent.height - root.corner
        width: root.corner
        height: root.corner
        cursorShape: Qt.SizeFDiagCursor
        onPressed: mpvWindow.startSystemResize(4 | 8)  // 右下 = 12
    }
}
