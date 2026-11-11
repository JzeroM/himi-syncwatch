import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer
import "evolveui" as EUI

// 678：房间资源面板（Qt 播放窗内的**弹出侧栏**）。
//
// 【定位】对齐 Flutter 播放器的房间模式 320dp 资源面板 / 安卓
// `NativePlayerScreenView` 的 `roomPanel` / 鸿蒙 `roomPanelShown`：
// 房间头部（资源 / 搜索 / 在线人数 / 角色徽章）+ 资源分组（季-集折叠）
// + 底部播报板。
//
// 【与 Flutter 面板窗的分工】用户定调「两个面板：Qt 面板做播放器，
// Flutter 面板作为资源面板」。这里的 Qt 面板是**播放器内的快捷面板**
// （看视频时不用切窗口就能换集），完整资源管理仍在 Flutter 面板窗。
//
// 【观众只读】`canControl=false` 时：搜索隐藏、点集无效（对齐安卓
// `buildEpisodeContent` 的 canControl 门）。
EUI.ECard {
    id: root

    /// 面板是否展开（由 playerState.resourcePanelOpen 驱动）
    property bool open: playerState.isRoom && playerState.resourcePanelOpen

    signal episodeClicked(int index)
    signal searchClicked()
    signal closeRequested()

    width: Theme.roomPanelWidth
    height: Math.min(parent ? parent.height - Theme.topBarHeight
                                  - Theme.bottomBarHeight - 24 : 480,
                     Theme.roomPanelMaxHeight)
    radius: 16
    // 668：液态玻璃卡（半透明，视频透过来）
    cardColor: Qt.rgba(0.07, 0.07, 0.09, 0.78)
    visible: open
    padding: 10

    /// 分组折叠（本地即时响应 + 命令发给 Dart 记账）。
    ///
    /// 【参数约定】与 Dart `NativePlayerCommand` 一致：分组用 `index`
    ///（组序号），季用 `groupIndex` + `seasonIndex`。
    function toggleGroup(index) {
        pipeServer.sendCommand({"type": "toggleResourceGroup", "index": index})
    }

    function toggleSeason(groupIndex, seasonIndex) {
        pipeServer.sendCommand({
            "type": "toggleResourceSeason",
            "groupIndex": groupIndex,
            "seasonIndex": seasonIndex
        })
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // ── 头部：资源 / 搜索 / 人数 / 角色 ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "资源"
                color: Theme.white
                font.pixelSize: 14
                font.weight: 600
            }
            Item { Layout.fillWidth: true }

            // 加资源（仅房主；对齐 Flutter `_isHost && 未播放`）
            ControlButton {
                visible: playerState.isHost && playerState.canControl
                icon: Icons.search
                iconSize: 18
                tooltip: "添加资源"
                onClicked: root.searchClicked()
            }

            // 在线人数
            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: peopleRow.implicitWidth + 12
                radius: 10
                color: Theme.white12
                Row {
                    id: peopleRow
                    anchors.centerIn: parent
                    spacing: 3
                    Text {
                        text: Icons.people
                        font.family: iconFont.name
                        font.pixelSize: 11
                        color: Theme.white70
                    }
                    Text {
                        text: playerState.onlineUserCount.toString()
                        color: Theme.white70
                        font.pixelSize: 11
                    }
                }
            }

            // 角色徽章
            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: roleLabel.implicitWidth + 12
                radius: 10
                color: playerState.isHost ? Theme.accent : "#E53935"
                Text {
                    id: roleLabel
                    anchors.centerIn: parent
                    text: playerState.isHost
                          ? "房主"
                          : (playerState.audienceName !== ""
                             ? playerState.audienceName : "观众")
                    color: Theme.white
                    font.pixelSize: 11
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.white12
        }

        // ── 资源分组列表 ──
        ListView {
            id: groupList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: playerState.resourceGroups
            ScrollBar.vertical: ScrollBar {
                // 676：固定长度 + 加粗（与 Flutter 一致）
                policy: groupList.contentHeight > groupList.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                width: 10
            }

            delegate: Column {
                id: groupCol
                width: groupList.width
                required property var modelData
                required property int index

                // 折叠态来自 Dart 推送（Qt 只发命令，Dart 是唯一真相源）。
                // 【不能用 readonly property 缓存】required property 在数据
                // 更新时会被重新赋值 → 赋值会摧毁 readonly 绑定，折叠态
                // 就永远停在旧值。直接读 modelData。
                readonly property bool collapsedNow:
                    groupCol.modelData.collapsed === true

                // 组标题（电影 / 剧名）
                Rectangle {
                    width: parent.width
                    height: 32
                    color: Qt.rgba(1, 1, 1, 0.05)
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: groupCol.collapsedNow
                                  ? Icons.chevronRight : Icons.expandMore
                            font.family: iconFont.name
                            font.pixelSize: 16
                            color: Theme.white70
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 100
                            text: groupCol.modelData.name
                            color: Theme.white
                            font.pixelSize: 13
                            font.weight: 600
                            elide: Text.ElideRight
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: groupCol.modelData.isMovie
                                  ? "(" + groupCol.modelData.totalCount + ")"
                                  : "(" + groupCol.modelData.totalCount + "集)"
                            color: Theme.white38
                            font.pixelSize: 11
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleGroup(groupCol.index)
                    }
                }

                // 季分组 + 集列表（展开时）
                Repeater {
                    model: groupCol.collapsedNow
                           ? [] : groupCol.modelData.seasons
                    delegate: Column {
                        width: groupCol.width
                        required property var modelData
                        required property int index

                        // 季标题（剧集多季时才有意义，电影单季省略）
                        Rectangle {
                            width: parent.width
                            height: 26
                            visible: !groupCol.modelData.isMovie
                            color: "transparent"
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 6
                                spacing: 4
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.collapsed
                                          ? Icons.chevronRight : Icons.expandMore
                                    font.family: iconFont.name
                                    font.pixelSize: 14
                                    color: Theme.white54
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 110
                                    text: "第" + modelData.seasonNumber + "季"
                                    color: Theme.white70
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "(" + modelData.episodes.length + "集)"
                                    color: Theme.white38
                                    font.pixelSize: 11
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleSeason(
                                    groupCol.index, modelData.index)
                            }
                        }

                        // 集列表
                        Repeater {
                            model: (groupCol.modelData.isMovie
                                    || !modelData.collapsed)
                                   ? modelData.episodes : []
                            delegate: Rectangle {
                                width: groupCol.width
                                height: 44
                                required property var modelData
                                color: modelData.isPlaying
                                       ? Qt.rgba(0.39, 0.4, 0.95, 0.30)
                                       : "transparent"
                                // 当前集左侧主色竖条（与 Flutter 一致）
                                Rectangle {
                                    width: 3
                                    height: parent.height
                                    color: modelData.isPlaying
                                           ? Theme.accent : "transparent"
                                }
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 6
                                    spacing: 8
                                    // 缩略图
                                    Rectangle {
                                        width: 56
                                        height: 36
                                        anchors.verticalCenter: parent.verticalCenter
                                        radius: 4
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            source: modelData.poster !== ""
                                                    ? modelData.poster : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: true
                                            visible: source !== ""
                                        }
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 70
                                        spacing: 2
                                        Text {
                                            width: parent.width
                                            text: modelData.name
                                            color: modelData.isPlaying
                                                   ? Theme.white : Theme.white70
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    // 678：观众不得切集（对齐安卓 canControl 门）
                                    cursorShape: playerState.canControl
                                                 ? Qt.PointingHandCursor
                                                 : Qt.ArrowCursor
                                    onClicked: {
                                        if (!playerState.canControl) return
                                        root.episodeClicked(modelData.index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── 播报板（底部）──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 88
            visible: playerState.broadcasts.length > 0
            color: Qt.rgba(1, 1, 1, 0.04)
            radius: 8

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4
                Row {
                    spacing: 4
                    Text {
                        text: Icons.campaign
                        font.family: iconFont.name
                        font.pixelSize: 12
                        color: Theme.white54
                    }
                    Text {
                        text: "播报 (" + playerState.broadcasts.length + ")"
                        color: Theme.white54
                        font.pixelSize: 11
                    }
                }
                ListView {
                    id: broadcastList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: playerState.broadcasts
                    delegate: Text {
                        width: broadcastList.width
                        required property var modelData
                        text: modelData
                        color: Theme.white54
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                    // 新播报到达 → 自动滚到底
                    onCountChanged: positionViewAtEnd()
                }
            }
        }
    }
}
