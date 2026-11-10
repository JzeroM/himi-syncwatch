import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer
import "evolveui" as EUI

// 662：通用选择面板（EvolveUI `ECard` 容器，对应 Flutter `_openSelectorPanel`）。
//
// 【构成】ECard（主题色卡片 + 圆角 + 阴影）+ 标题行（EButton 关闭）+
// 行列表（两行：主文 + 副文 + 选中勾）。行是胶水件（EvolveUI 无两行
// 可选行组件），配色全部走 `theme`（ETheme）。
Rectangle {
    id: root

    property string title: ""
    property var items: []          // [{ id, label, sub, selected }]

    signal itemClicked(var id)
    signal closed()

    width: Math.max(Theme.panelMinWidth,
                    Math.min(Theme.panelMaxWidth,
                             parent ? parent.width * 0.42 : Theme.panelMinWidth))
    height: Math.min(parent ? parent.height - Theme.panelTopOffset
                                  - Theme.panelBottomOffset : 400,
                     titleBar.height + list.contentHeight + Theme.panelPadV * 2 + 8)
    radius: Theme.radiusPanel
    color: theme.secondaryColor
    border.color: theme.borderColor
    border.width: 1
    visible: false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.panelPadV
        spacing: 4

        RowLayout {
            id: titleBar
            Layout.fillWidth: true
            Layout.leftMargin: Theme.panelPadH - Theme.panelPadV
            Layout.rightMargin: 4

            Text {
                Layout.fillWidth: true
                text: root.title
                color: theme.textColor
                font.pixelSize: Theme.panelTitleSize
                font.weight: 600
            }
            ControlButton {
                icon: Icons.close
                iconSize: 18
                tooltip: "关闭"
                onClicked: root.closed()
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.items
            spacing: 2

            // 两行可选行（主文 + 副文 + 右勾）
            delegate: Rectangle {
                width: ListView.view.width
                height: 44
                radius: 8
                color: modelData.selected
                       ? theme.focusColor
                       : (rowMouse.containsMouse
                          ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.08)
                                          : Qt.rgba(0, 0, 0, 0.06))
                          : "transparent")

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: checkMark.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: modelData.label
                        color: modelData.selected ? theme.primaryColor : theme.textColor
                        font.pixelSize: Theme.panelOptionSize
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: modelData.sub !== undefined && modelData.sub !== ""
                        width: parent.width
                        text: modelData.sub || ""
                        color: modelData.selected ? theme.primaryColor
                                                  : Theme.mutedText
                        font.pixelSize: Theme.captionSize
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: checkMark
                    visible: modelData.selected === true
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.panelCheckSlot
                    text: Icons.check
                    font.family: iconFont.name
                    font.pixelSize: 18
                    color: modelData.selected ? theme.primaryColor : theme.textColor
                    horizontalAlignment: Text.AlignRight
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.itemClicked(modelData.id)
                }
            }
        }
    }
}
