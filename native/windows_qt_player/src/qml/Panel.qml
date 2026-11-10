import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer

// 659：通用选择面板（对应 Flutter `_openSelectorPanel`）。
//
// 规格（NativePlayerTheme）：
//   - 宽 clamp(0.42×屏宽, 260, 320)
//   - 圆角 16，内边距 h16 v12
//   - 标题 15/w600，选项 14
//   - 选中项文字用 accent(#6366F1)，右侧对勾占 18 宽
//   - 背景 panelTint(#1F1A1D23) + rim 描边
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
    color: Theme.panelTint
    border.color: Theme.rim
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
                color: Theme.white
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

            delegate: Rectangle {
                width: ListView.view.width
                height: 44
                radius: 8
                color: modelData.selected
                       ? Theme.white12
                       : (rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06)
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
                        color: modelData.selected ? Theme.accent : Theme.white
                        font.pixelSize: Theme.panelOptionSize
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: modelData.sub !== undefined && modelData.sub !== ""
                        width: parent.width
                        text: modelData.sub || ""
                        color: Theme.white38
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
                    font.family: "Material Icons"
                    font.pixelSize: 18
                    color: Theme.accent
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
