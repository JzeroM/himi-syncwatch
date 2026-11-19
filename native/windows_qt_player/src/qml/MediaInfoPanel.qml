import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import HimiPlayer

// 695：「视频详细信息」面板——可滚动；每个分组一张矩形玻璃卡片；
// 组内每条信息纵向独占一行（左中文标签、右英文值）。数据为 Dart 预格式化
// JSON（playerState.mediaInfoJson），本组件只解析渲染（四壳同构）。
Rectangle {
    id: root
    visible: false
    radius: 12
    color: Qt.rgba(0.07, 0.08, 0.10, 0.92)
    border.color: Qt.rgba(1, 1, 1, 0.12)
    border.width: 1

    /// 关闭请求（Esc 第一层也会经 closePanels 关本面板）。
    signal closeRequested()

    readonly property var mediaGroups: {
        var out = []
        try {
            var o = JSON.parse(playerState.mediaInfoJson || '{}')
            out = o.groups || []
        } catch (e) { out = [] }
        out
    }

    // 整体可滚动
    Flickable {
        anchors.fill: parent
        anchors.margins: 12
        contentHeight: col.implicitHeight
        clip: true

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 10

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "视频详细信息"
                color: "white"
                font.pixelSize: 15
                font.bold: true
            }

            Repeater {
                model: root.mediaGroups
                delegate: Rectangle {
                    // 每个分组 = 一张矩形玻璃卡片
                    Layout.fillWidth: true
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.07)
                    border.color: Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1
                    implicitHeight: groupCol.implicitHeight + 20

                    ColumnLayout {
                        id: groupCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 3

                        Text {
                            text: modelData.title
                            color: Qt.rgba(1, 1, 1, 0.7)
                            font.pixelSize: 13
                            font.bold: true
                        }

                        Repeater {
                            model: modelData.rows
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                // 每条信息纵向独占一行
                                Text {
                                    Layout.preferredWidth: 96
                                    text: modelData.label
                                    color: Qt.rgba(1, 1, 1, 0.54)
                                    font.pixelSize: 12
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.value
                                    color: "white"
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignRight
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
