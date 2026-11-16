import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer
import "evolveui" as EUI

// 694 M3b：弹幕弹窗（Qt 壳）——点击弹幕开关按钮弹出（全平台「点击弹窗」）。
//
// 【内容规格与 Flutter 壳同构】动效开关（视觉主角）+ 绑定状态行 +
// 搜索/换绑（同卡切搜索态）+ 解除绑定。搜索/绑定/记忆全在 Dart 侧
// DanmakuSearchController，本壳只发命令（searchDanmaku/bindDanmaku/
// unbindDanmaku）并渲染 playerState 回流的
// danmakuBinding/danmakuSearchResults/danmakuSearching/danmakuSearchError。
//
// 【QML 老坑（AGENTS.md）】
// - 属性名绝不能叫 playerState（遮蔽全局单例 → Binding loop）→ stateRef
// - font.pixelSize 只吃整数：一律用 Theme 字号常量或 Math.round
// - Repeater delegate 里也算数：字号声明 int
EUI.ECard {
    id: root

    // 注意：不能命名 playerState——会遮蔽全局单例（Binding loop 教训）。
    property var stateRef: null
    property bool danmakuOn: false

    property bool searchMode: false

    signal toggleRequested()
    signal searchRequested(string keyword)
    signal bindRequested(int episodeId)
    signal unbindRequested()
    signal closed()

    // 694：加宽到 460——搜索结果（剧名·集名）完整显示不省略。
    implicitWidth: 460
    padding: 16

    // 694：高度上限 = 可用高（顶栏之下、控制条/进度条之上，对齐 Panel.qml
    // 的钳制公式）；内容超出时结果区滚动，面板不许盖到进度条。
    readonly property real maxPanelHeight: parent
        ? parent.height - Theme.panelTopOffset - Theme.panelBottomOffset
        : 400
    height: Math.min(implicitHeight, maxPanelHeight)

    function openSearch() {
        searchMode = true
        if (keywordField.text === "") {
            keywordField.text = stateRef ? stateRef.title : ""
        }
    }

    component SectionLabel: Text {
        color: theme.textColor
        opacity: 0.55
        font.pixelSize: Theme.captionSize
    }

    component RowLabel: Text {
        color: theme.textColor
        font.pixelSize: Theme.panelOptionSize
    }

    ColumnLayout {
        // ECard 内容槽是内部 ColumnLayout：必须用 Layout 附着属性，
        // 写 anchors.fill 会触发「anchors on layout-managed item」告警。
        Layout.fillWidth: true
        spacing: 10

        // ── 标题行 ──
        RowLayout {
            Layout.fillWidth: true
            RowLabel {
                text: "弹幕"
                font.pixelSize: Theme.panelTitleSize
                font.weight: Theme.titleWeight
                Layout.fillWidth: true
            }
            // 构建角标（694：真机截图即诊断——装的哪版一目了然）
            RowLabel {
                text: "构建 " + (typeof buildTag !== "undefined" ? buildTag : "dev")
                opacity: 0.35
                font.pixelSize: Theme.captionSize
            }
            RowLabel {
                text: "关闭面板"
                opacity: 0.55
                font.pixelSize: Theme.captionSize
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: root.closed()
                }
            }
        }

        // ── 动效开关（弹窗视觉主角；三壳同款规格）──
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 84
            Layout.preferredHeight: 44

            Rectangle {
                id: track
                anchors.fill: parent
                radius: 22
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: root.danmakuOn ? "#FF8A3D" : "#4A4F57"
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                    GradientStop {
                        position: 1.0
                        color: root.danmakuOn ? "#E06A1B" : "#4A4F57"
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                }

                Rectangle {
                    id: knob
                    width: 36
                    height: 36
                    radius: 18
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.danmakuOn ? track.width - width - 4 : 4
                    Behavior on x {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutBack
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Icons.danmakuOn
                        font.family: iconFont.name
                        // 算出的字号必须 Math.round + int（QML 只吃整数）
                        readonly property int glyphSize: Math.round(16)
                        font.pixelSize: glyphSize
                        color: root.danmakuOn ? "#E06A1B" : "#8A9099"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.toggleRequested()
                }
            }
        }

        // ── 状态行（开关联动）──
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            color: theme.textColor
            opacity: 0.7
            font.pixelSize: Theme.captionSize
            text: root.danmakuOn
                  ? ("已开启 · " + (stateRef ? stateRef.danmakuBinding : ""))
                  : "已关闭"
            elide: Text.ElideMiddle
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: theme.textColor
            opacity: 0.15
        }

        // ── 主态：搜索/换绑入口 + 解除绑定 ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: !root.searchMode

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                RowLayout {
                    anchors.fill: parent
                    spacing: 8
                    RowLabel { text: "搜索 / 换绑"; Layout.fillWidth: true }
                    RowLabel { text: "›"; opacity: 0.55 }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.openSearch()
                }
            }
            SectionLabel {
                Layout.fillWidth: true
                text: stateRef ? stateRef.danmakuBinding : "未匹配"
                elide: Text.ElideMiddle
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                visible: stateRef ? stateRef.danmakuBinding !== "未匹配"
                                  : false
                RowLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "解除绑定（回自动匹配）"
                    opacity: 0.75
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.unbindRequested()
                }
            }
        }

        // ── 搜索态 ──
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.searchMode

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: keywordField
                    Layout.fillWidth: true
                    color: theme.textColor
                    font.pixelSize: Theme.panelOptionSize
                    placeholderText: "输入剧名搜索…"
                    background: Rectangle {
                        radius: 8
                        color: Qt.rgba(1, 1, 1, 0.10)
                    }
                }
                Rectangle {
                    width: 56
                    height: 32
                    radius: 8
                    color: "#6366F1"
                    RowLabel {
                        anchors.centerIn: parent
                        text: "搜索"
                        color: "white"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.searchRequested(keywordField.text)
                    }
                }
            }

            SectionLabel {
                visible: stateRef ? stateRef.danmakuSearching : false
                text: "搜索中…"
            }
            Text {
                Layout.fillWidth: true
                visible: stateRef
                         ? stateRef.danmakuSearchError !== "" : false
                color: "#FFA040"
                font.pixelSize: Theme.captionSize
                text: stateRef ? stateRef.danmakuSearchError : ""
                wrapMode: Text.Wrap
            }

            // 结果列表（danmakuSearchResults：{episodeId, animeTitle,
            // episodeTitle}）——结果多时滚动（694：用户反馈搜索结果很长）。
            // 【694：搜到不显示的根因修复】ScrollView 视口高必须**解析式**
            // （= 内容高钳上限），依赖 fillHeight/implicitHeight 会被压成
            // 0 高——结果推到了但看不见（Panel.qml 676 同类教训）。
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(resultsCol.implicitHeight, 320)
                clip: true
                visible: stateRef
                         ? stateRef.danmakuSearchResults.length > 0 : false

                ColumnLayout {
                id: resultsCol
                // 694 二修：**显式列宽**。ScrollView 内 ColumnLayout 的
                // 隐式宽为 0，隐式回退不生效的环境下整列塌缩 → 按钮被裁
                // 出视口、文本靠自然宽度「看起来正常」（真机回归「还是
                // 没绑定按钮」）。width 直绑 ScrollView 内容宽根治。
                width: parent ? parent.width : 460
                spacing: 4

                Repeater {
                    model: stateRef ? stateRef.danmakuSearchResults : []
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        // 行高：显式 Layout.preferredHeight（Layout 托管下
                        // 直绑 height 会被布局覆盖）。
                        Layout.preferredHeight: row.implicitHeight + 16
                        radius: 8
                        color: Qt.rgba(1, 1, 1, 0.06)

                        // 行布局：RowLayout（文本列 + 绑定胶囊），彻底
                        // 摆脱锚定组合的隐式尺寸依赖。
                        RowLayout {
                            id: row
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            Column {
                                id: hitCol
                                Layout.fillWidth: true
                                Text {
                                    width: parent.width
                                    color: theme.textColor
                                    font.pixelSize: Theme.panelOptionSize
                                    text: modelData.animeTitle !== ""
                                          ? modelData.animeTitle
                                          : ("episodeId " + modelData.episodeId)
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    width: parent.width
                                    color: theme.textColor
                                    opacity: 0.55
                                    // Repeater 内算出的字号：Math.round + int
                                    readonly property int subSize:
                                        Math.round(Theme.captionSize)
                                    font.pixelSize: subSize
                                    text: modelData.episodeTitle
                                    wrapMode: Text.WordWrap
                                }
                            }

                            // 显性「绑定」胶囊按钮
                            Rectangle {
                                Layout.preferredWidth: 56
                                Layout.preferredHeight: 32
                                radius: 16
                                color: "#6366F1"
                                Text {
                                    anchors.centerIn: parent
                                    color: "white"
                                    font.pixelSize: Theme.panelOptionSize
                                    text: "绑定"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked:
                                        root.bindRequested(modelData.episodeId)
                                }
                            }
                        }

                        // 整行点击同样绑定（快捷路径；与按钮同语义）
                        MouseArea {
                            anchors.fill: parent
                            onClicked:
                                root.bindRequested(modelData.episodeId)
                        }
                    }
                }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                RowLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "返回"
                    opacity: 0.55
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.searchMode = false
                }
            }
        }
    }
}
