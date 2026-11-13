import QtQuick

/// 697：调试面板的单行指标（标签 + 值 + 状态色）。
///
/// 【为什么是独立文件而不是内联组件】
/// QML 的内联组件（`component X: Item {}`）**不与外层文档共享作用域**，
/// 拿不到 `root` 的辅助函数（如 `sevColor`）。而状态色映射是纯逻辑，
/// 放在组件内部反而更内聚——组件自带「值怎么染色」的知识。
///
/// 【宽度】Column 不会自动撑满子项，这里用 `parent.width`（父级 Column
/// 已显式设宽），与 `DisplayAdjustPanel` 的 `SectionHeader` 同款做法。
Item {
    id: row

    /// 左侧标签（固定 66px 宽）。
    property string label: ""

    /// 右侧值（可省略号截断）。
    property string value: ""

    /// 状态色语义：`good` / `warn` / `error` / 其他=普通。
    property string severity: "normal"

    /// 标签列宽（右侧值从 `labelWidth + 16` 开始）。
    property real labelWidth: 66

    implicitHeight: 15
    height: 15
    width: parent ? parent.width : 0

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: row.labelWidth
        text: row.label
        color: "#61FFFFFF"
        font.pixelSize: 10.5
        elide: Text.ElideRight
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: row.labelWidth + 16
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: row.value
        color: row.severityColor(row.severity)
        font.pixelSize: 10.5
        elide: Text.ElideRight
    }

    /// 状态色映射（与 Flutter 面板 `_severityColor` 一一对应）。
    ///
    /// | 语义 | 颜色 | 用于 |
    /// |---|---|---|
    /// | good | `#6EE7A0` 绿 | 正常 / 已识别 / HDR 直出 |
    /// | warn | `#FBBF24` 琥珀 | 可疑 / 降级（如软解、丢帧少） |
    /// | error | `#F87171` 红 | 异常（DV 未识别、P5 后端不支持） |
    /// | normal | 白 70% | 中性信息 |
    function severityColor(sev) {
        if (sev === "good") return "#6EE7A0"
        if (sev === "warn") return "#FBBF24"
        if (sev === "error") return "#F87171"
        return "#B3FFFFFF"
    }
}
