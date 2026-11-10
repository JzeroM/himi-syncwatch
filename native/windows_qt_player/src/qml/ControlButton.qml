import QtQuick
import QtQuick.Controls.Basic
import HimiPlayer
import "evolveui" as EUI

// 662：可复用图标按钮（EvolveUI `EButton` 封装）。
//
// 【662 瑕疵修复】
//   - 按钮底**自绘**（悬停白 12%）：EButton 的 background 即便传
//     containerColor:"transparent"，真机仍见深色圆底（疑其默认绑定/
//     MultiEffect 覆盖），自绘彻底排除不确定因素；EButton 只出图标
//     与按压缩放动效
//   - 字号档拉层级（EButton 只有 12/16/20/24/32 五档）：
//     播放 36→xl(32) > 侧键 28→l(24) > 小钮 18→m(20)
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

    // 自绘悬停底（透明 → 白 12%）
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.enabled && hover.hovered
               ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12)
                               : Qt.rgba(0, 0, 0, 0.08))
               : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    EUI.EButton {
        anchors.fill: parent
        text: ""
        backgroundVisible: false
        shadowEnabled: false
        size: root.iconSize >= 32 ? "xl"
            : (root.iconSize >= 22 ? "l"
            : (root.iconSize >= 18 ? "m" : "s"))
        iconCharacter: root.icon
        iconFontFamily: iconFont.name
        iconColor: root.enabled ? root.iconColor : theme.borderColor
        radius: 8
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

    // 悬停/tooltip（HoverHandler 不抢 EButton 的 MouseArea）
    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered && root.tooltip !== "" && root.enabled
    ToolTip.text: root.tooltip
    ToolTip.delay: 800
}
