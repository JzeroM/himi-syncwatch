import QtQuick

/// 697：调试面板的分组标题（可点击折叠）。
///
/// 【为什么是独立文件】内联组件不与外层文档共享作用域，拿不到外层的
/// 折叠状态与回调；独立组件通过属性/信号通信，边界清晰。
Item {
    id: header

    /// 分组名（如「HDR 输入」）。
    property string title: ""

    /// 是否已折叠。
    property bool collapsed: false

    /// 是否高亮（HDR/DV 等排查重点分组用主色标题）。
    property bool highlighted: false

    /// 点击标题请求切换折叠态。
    signal toggleRequested()

    implicitHeight: 22
    height: 22
    width: parent ? parent.width : 0

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            text: header.collapsed ? "\u203A" : "\u2304"
            color: header.highlighted ? "#66FF99" : "#61FFFFFF"
            font.pixelSize: 11
        }
        Text {
            text: header.title
            color: header.highlighted ? "#66FF99" : "#B3FFFFFF"
            font.pixelSize: 11
            font.bold: true
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: header.toggleRequested()
    }
}
