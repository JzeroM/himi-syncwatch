import QtQuick
import QtQuick.Controls.Basic
import HimiPlayer
import "evolveui" as EUI

// 662：可复用图标按钮（EvolveUI `EButton` 封装，对应 Flutter 的
// `_buildControlButton`）。
//
// 【封装点】
//   - EButton 尺寸档位的字号取 l/m/l（24/20/16），命中区仍是我们
//     的 40×40（anchors.fill 覆盖其 implicit 尺寸，不改上游源码）
//   - 图标按钮 `text: ""`（否则 EButton 会显示默认 "Button"）
//   - 角标 9px 字、正圆、尺寸按位数分档 15/19/24（Theme.badgeSizeFor）
//   - tooltip 用 HoverHandler + ToolTip（不抢 EButton 的 MouseArea）
Item {
    id: root

    property string icon: ""
    property string badge: ""
    property string tooltip: ""
    property bool enabled: true
    property real iconSize: Theme.controlIconSize
    property color iconColor: theme.textColor

    signal clicked()

    implicitWidth: Math.max(iconSize + 16, 40)
    implicitHeight: Math.max(iconSize + 16, 40)

    EUI.EButton {
        anchors.fill: parent
        text: ""
        size: root.iconSize >= 22 ? "l" : (root.iconSize >= 18 ? "m" : "s")
        iconCharacter: root.icon
        iconFontFamily: iconFont.name
        iconColor: root.enabled ? root.iconColor
                                : theme.getBorderColor(false)
        containerColor: "transparent"
        hoverColor: theme.isDark ? Qt.rgba(1, 1, 1, 0.12)
                                 : Qt.rgba(0, 0, 0, 0.08)
        radius: 8
        shadowEnabled: false
        enabled: root.enabled
        onClicked: root.clicked()
    }

    // 角标（与 Flutter `_buildBadge` 同规格）
    Rectangle {
        visible: root.badge !== ""
        anchors.right: parent.right
        anchors.top: parent.top
        width: Theme.badgeSizeFor(root.badge)
        height: width
        radius: width / 2
        color: theme.focusColor

        Text {
            anchors.centerIn: parent
            text: root.badge
            color: theme.textColor
            font.pixelSize: Theme.badgeFontSize
            font.bold: true
        }
    }

    // tooltip（HoverHandler 不与 EButton 的 MouseArea 抢事件）
    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered && root.tooltip !== "" && root.enabled
    ToolTip.text: root.tooltip
    ToolTip.delay: 800
}
