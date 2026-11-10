import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// 656：可复用的图标按钮（对应 Flutter 的 _buildControlButton）。
//
// 图标用 Material Icons 字体（与 Flutter/安卓/鸿蒙同字形），
// 通过 unicode 码点渲染，无需图片资源。
Item {
    id: root

    property string icon: ""
    property string badge: ""
    property string tooltip: ""
    property bool enabled: true
    property int iconSize: 24
    signal clicked()

    implicitWidth: Math.max(iconSize + 12, 36)
    implicitHeight: Math.max(iconSize + 12, 36)

    Rectangle {
        id: hover
        anchors.fill: parent
        radius: 6
        color: root.enabled && mouse.containsMouse
               ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Text {
        anchors.centerIn: parent
        text: root.icon
        font.family: "Material Icons"
        font.pixelSize: root.iconSize
        color: root.enabled ? "#FFFFFF" : "#60FFFFFF"
    }

    // 角标（对应 Flutter 的 badge：音轨数/字幕数/集数）
    Rectangle {
        visible: root.badge !== ""
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 2
        anchors.topMargin: 2
        width: Math.max(badgeText.implicitWidth + 8, 16)
        height: 16
        radius: 8
        color: "#E53935"

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.badge
            color: "#FFFFFF"
            font.pixelSize: 10
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()

        ToolTip.visible: containsMouse && root.tooltip !== ""
        ToolTip.text: root.tooltip
        ToolTip.delay: 800
    }
}
