import QtQuick
import QtQuick.Controls.Basic
import HimiPlayer

// 659：可复用图标按钮（对应 Flutter 的 `_buildControlButton`）。
//
// 视觉规格全部取自 Theme（即 NativePlayerTheme），与 Flutter 一致：
//   - 图标 24px（底栏）/ 22px（顶栏）
//   - hover 底色 white12，圆角 8
//   - 角标 9px 字，正圆，尺寸按位数分档 15/19/24
//   - 角标底色 accent(#6366F1)
Item {
    id: root

    property string icon: ""
    property string badge: ""
    property string tooltip: ""
    property bool enabled: true
    property real iconSize: Theme.controlIconSize
    property color iconColor: Theme.white

    signal clicked()

    implicitWidth: Math.max(iconSize + 16, 40)
    implicitHeight: Math.max(iconSize + 16, 40)

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.enabled && mouse.containsMouse
               ? Theme.white12 : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Text {
        anchors.centerIn: parent
        text: root.icon
        font.family: "Material Icons"
        font.pixelSize: root.iconSize
        color: root.enabled ? root.iconColor : Theme.white24
    }

    // 角标（与 Flutter `_buildBadge` 同规格）
    Rectangle {
        visible: root.badge !== ""
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 0
        anchors.topMargin: 0
        width: Theme.badgeSizeFor(root.badge)
        height: width
        radius: width / 2
        color: Theme.accent

        Text {
            anchors.centerIn: parent
            text: root.badge
            color: Theme.white
            font.pixelSize: Theme.badgeFontSize
            font.bold: true
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
