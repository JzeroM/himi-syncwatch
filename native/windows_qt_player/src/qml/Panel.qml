import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer
import "evolveui" as EUI

// 665：通用选择面板（EvolveUI `ECard` 容器 + modelData 行，对应 Flutter
// `_openSelectorPanel` / `SelectorSidePanel`）。
//
// 【665 真机回归：面板全空】EList 的 `model.xxx` 播放委托对**缺失角色**
// 访问报错（我们的条目没有 iconChar 键）→ 委托创建失败 → 列表空白。
// 行改标准 `modelData` 委托（659 已验证模式）+ EvolveUI 配色。
//
// 【交互对齐 Flutter】无 ✕ 关闭钮：再点同一控件 / 点窗口空白处收回。
//
// 【两种形态】普通两行列表（SideOptionRow）；[cardMode] = 选集海报
// 卡片网格（照 `EpisodeSelectPanel`：剧照 + 选中勾 + cardTitle）。
EUI.ECard {
    id: root

    property string title: ""
    property var items: []           // [{ id, display, sub, selected, poster? }]
    property bool cardMode: false

    signal itemClicked(var id)
    signal closed()

    /// 行高合计（列表模式）
    readonly property real rowsHeight: {
        var h = 0
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            h += (it.sub !== undefined && it.sub !== "" && it.sub !== null)
                 ? 56 : 44
            if (i < items.length - 1) h += 6
        }
        return h
    }

    width: Math.max(Theme.panelMinWidth,
                    Math.min(Theme.panelMaxWidth,
                             parent ? parent.width * 0.42 : Theme.panelMinWidth))
    height: Math.min(parent ? parent.height - Theme.panelTopOffset
                                  - Theme.panelBottomOffset : 400,
                     root.padding * 2 + 36 + (cardMode
                         ? Math.ceil(items.length / 2) * 196 + 8
                         : rowsHeight))
    radius: 20
    // 668：液态玻璃卡（半透明，视频透过来）
    cardColor: Qt.rgba(0.07, 0.07, 0.09, 0.72)
    visible: false

    // ── 标题行（无 ✕：照 Flutter，点别处/再点控件收回）──
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 36

        Text {
            Layout.fillWidth: true
            text: root.title
            color: theme.textColor
            font.pixelSize: Theme.panelTitleSize
            font.weight: 600
        }
    }

    // ── 列表形态（两行：主文 + 副文 + 选中勾）──
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: root.rowsHeight
        visible: !root.cardMode
        clip: true
        spacing: 6
        model: root.items

        delegate: Rectangle {
            width: list.width
            height: (modelData.sub !== undefined && modelData.sub !== ""
                     && modelData.sub !== null) ? 56 : 44
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
                    text: modelData.display
                    color: modelData.selected ? theme.primaryColor : theme.textColor
                    font.pixelSize: Theme.panelOptionSize
                    elide: Text.ElideRight
                }
                Text {
                    visible: modelData.sub !== undefined && modelData.sub !== ""
                             && modelData.sub !== null
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
                text: ""
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

    // ── 卡片形态（选集：海报 + 选中勾 + 标题，照 EpisodeSelectPanel）──
    GridView {
        id: cards
        Layout.fillWidth: true
        Layout.preferredHeight: parent ? Math.min(
            root.height - root.padding * 2 - 36,
            Math.ceil(root.items.length / 2) * 196 + 8) : 300
        visible: root.cardMode
        clip: true
        cellWidth: width / 2
        cellHeight: 196
        model: root.items

        delegate: Item {
            width: cards.cellWidth
            height: cards.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 10
                color: cardMouse.containsMouse
                       ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.08)
                                       : Qt.rgba(0, 0, 0, 0.06))
                       : "transparent"

                // 剧照（poster 已带 api_key）
                Rectangle {
                    id: posterBox
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 150
                    radius: 8
                    clip: true
                    color: theme.isDark ? Qt.rgba(1, 1, 1, 0.06)
                                        : Qt.rgba(0, 0, 0, 0.06)

                    Image {
                        anchors.fill: parent
                        source: modelData.poster || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    // 选中勾（照 Flutter：黑底圆 + accent 勾）
                    Rectangle {
                        visible: modelData.selected === true
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        width: 22
                        height: 22
                        radius: 11
                        color: Qt.rgba(0, 0, 0, 0.55)

                        Text {
                            anchors.centerIn: parent
                            text: ""
                            font.family: iconFont.name
                            font.pixelSize: 14
                            color: theme.focusColor
                        }
                    }
                }

                Text {
                    anchors.top: posterBox.bottom
                    anchors.topMargin: 6
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: modelData.display
                    color: theme.textColor
                    font.pixelSize: Theme.captionSize
                    font.weight: 500
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.itemClicked(modelData.id)
                }
            }
        }
    }
}
