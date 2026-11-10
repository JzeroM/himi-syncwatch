import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// 656：通用选择面板（对应 Flutter 的 _openSelectorPanel）。
//
// 同一套 UI 服务四个场景：选集 / 音轨 / 字幕 / 倍速。
// 通过 `items`（[{label, sub, selected}]）驱动，避免四份重复 QML。
Rectangle {
    id: root

    property string title: ""
    property var items: []          // [{ id, label, sub, selected }]
    property int selectedIndex: -1

    signal itemClicked(int id)
    signal closed()

    width: 320
    height: Math.min(420, 56 + items.length * 52 + 16)
    radius: 12
    color: Qt.rgba(0.11, 0.11, 0.14, 0.96)
    border.color: Qt.rgba(1, 1, 1, 0.12)
    border.width: 1
    visible: false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        // 标题栏
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 4

            Text {
                Layout.fillWidth: true
                text: root.title
                color: "#FFFFFF"
                font.pixelSize: 15
                font.bold: true
            }
            ControlButton {
                icon: "\ue5cd"   // close
                iconSize: 18
                tooltip: "关闭"
                onClicked: root.closed()
            }
        }

        // 列表
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.items
            spacing: 2

            delegate: Rectangle {
                width: ListView.view.width
                height: 48
                radius: 6
                color: modelData.selected
                       ? Qt.rgba(1, 1, 1, 0.16)
                       : (itemMouse.containsMouse
                          ? Qt.rgba(1, 1, 1, 0.08) : "transparent")

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: modelData.label
                        color: modelData.selected ? "#FFFFFF" : "#DDDDDD"
                        font.pixelSize: 14
                    }
                    Text {
                        visible: modelData.sub !== undefined && modelData.sub !== ""
                        text: modelData.sub || ""
                        color: "#80FFFFFF"
                        font.pixelSize: 11
                    }
                }

                // 选中标记
                Text {
                    visible: modelData.selected === true
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\ue5ca"   // check
                    font.family: "Material Icons"
                    font.pixelSize: 18
                    color: "#4CAF50"
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.itemClicked(modelData.id)
                }
            }
        }
    }
}
