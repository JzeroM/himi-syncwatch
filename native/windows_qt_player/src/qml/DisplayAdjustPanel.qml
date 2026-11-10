import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer
import "evolveui" as EUI

// 662：「显示调节」面板（EvolveUI `ESlider` 行，对照 Flutter
// `DisplayAdjustPanel`：字幕段 + 弹幕段）。
//
// 【构成】
//   字幕：大小(0.5~3.0×) / 位置(0~200px) / 延迟(-5.0~+5.0s) / 恢复默认
//   弹幕：速度(0.5~2.0×) / 大小(0.5~2.0×) / 透明度(10~100%) / 恢复默认
//
// 【行 = PlayerSlider（ESlider 封装）】ESlider 自带「标签 + 滑杆 +
// 数值」布局，正是 Flutter `styleSliderRow` 的等价物。
//
// 【命令】拖动 → `adjustDisplay {key,value}`（与安卓/鸿蒙同协议）；
// 恢复默认 → `resetDisplay {scope: subtitle|danmaku}`。
// 延迟滑杆以秒显示（-5~5s）但命令按毫秒发（×1000）；
// 透明度滑杆以百分比显示（10~100%）但命令按 0~1 发（÷100）。
Rectangle {
    id: root

    signal closed()
    signal adjust(string key, real value)
    signal reset(string scope)

    width: Math.max(Theme.panelMinWidth,
                    Math.min(Theme.panelMaxWidth,
                             parent ? parent.width * 0.42 : Theme.panelMinWidth))
    height: Math.min(parent ? parent.height - Theme.panelTopOffset
                                  - Theme.panelBottomOffset : 400,
                     flick.contentHeight + titleBar.height + Theme.panelPadV * 2 + 8)
    radius: Theme.radiusPanel
    color: theme.secondaryColor
    border.color: theme.borderColor
    border.width: 1
    visible: false

    // ── 恢复默认行（胶水件）──
    component ResetRow: Item {
        id: resetRow
        property string label: "恢复默认"
        property bool selected: false
        signal triggered()

        width: parent ? parent.width : 260
        height: 44

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: resetRow.selected ? theme.focusColor
                   : (resetMouse.containsMouse
                      ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.08)
                                      : Qt.rgba(0, 0, 0, 0.06))
                      : "transparent")
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.panelPadH
            anchors.verticalCenter: parent.verticalCenter
            text: resetRow.label
            color: resetRow.selected ? theme.primaryColor : theme.textColor
            font.pixelSize: Theme.panelOptionSize
        }
        MouseArea {
            id: resetMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: resetRow.triggered()
        }
    }

    // ── 段标题 ──
    component SectionHeader: Item {
        property string label: ""
        width: parent ? parent.width : 260
        height: 26
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.panelPadH
            anchors.bottom: parent.bottom
            text: parent.label
            color: Theme.mutedText
            font.pixelSize: Theme.captionSize
            font.weight: 500
        }
    }

    // ── 标题栏 ──
    RowLayout {
        id: titleBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.panelPadV
        anchors.leftMargin: Theme.panelPadH
        anchors.rightMargin: 4

        Text {
            Layout.fillWidth: true
            text: "显示调节"
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

    // ── 内容（可滚动）──
    Flickable {
        id: flick
        anchors.top: titleBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.panelPadV
        anchors.rightMargin: Theme.panelPadV
        anchors.bottomMargin: Theme.panelPadV
        contentWidth: width
        contentHeight: contentCol.implicitHeight
        clip: true

        Column {
            id: contentCol
            width: flick.width

            SectionHeader { label: "字幕" }

            PlayerSlider {
                width: contentCol.width
                text: "大小"
                minimumValue: 0.5
                maximumValue: 3.0
                decimals: 2
                valueSuffix: "×"
                value: playerState.subtitleScale
                onMoved: (v) => root.adjust("subtitleScale", v)
            }
            PlayerSlider {
                width: contentCol.width
                text: "位置"
                minimumValue: 0
                maximumValue: 200
                decimals: 0
                valueSuffix: "px"
                value: playerState.subtitleMarginY
                onMoved: (v) => root.adjust("subtitleMarginY", Math.round(v))
            }
            PlayerSlider {
                width: contentCol.width
                text: "延迟"
                minimumValue: -5
                maximumValue: 5
                decimals: 1
                valueSuffix: "s"
                value: playerState.subtitleDelayMs / 1000
                onMoved: (v) => root.adjust("subtitleDelayMs", Math.round(v * 1000))
            }
            ResetRow {
                selected: Math.abs(playerState.subtitleScale - 1.0) < 0.01
                          && playerState.subtitleMarginY === 22
                          && Math.abs(playerState.subtitleDelayMs) < 0.5
                onTriggered: root.reset("subtitle")
            }

            Rectangle {
                width: contentCol.width
                height: 1
                color: theme.borderColor
            }

            SectionHeader { label: "弹幕" }

            PlayerSlider {
                width: contentCol.width
                text: "速度"
                minimumValue: 0.5
                maximumValue: 2.0
                decimals: 2
                valueSuffix: "×"
                value: playerState.danmakuSpeed
                onMoved: (v) => root.adjust("danmakuSpeed", v)
            }
            PlayerSlider {
                width: contentCol.width
                text: "大小"
                minimumValue: 0.5
                maximumValue: 2.0
                decimals: 2
                valueSuffix: "×"
                value: playerState.danmakuFontSize
                onMoved: (v) => root.adjust("danmakuFontSize", v)
            }
            PlayerSlider {
                width: contentCol.width
                text: "透明度"
                minimumValue: 10
                maximumValue: 100
                decimals: 0
                valueSuffix: "%"
                value: playerState.danmakuOpacity * 100
                onMoved: (v) => root.adjust("danmakuOpacity", v / 100)
            }
            ResetRow {
                selected: Math.abs(playerState.danmakuSpeed - 0.7) < 0.01
                          && Math.abs(playerState.danmakuFontSize - 0.5) < 0.01
                          && Math.abs(playerState.danmakuOpacity - 0.8) < 0.01
                onTriggered: root.reset("danmaku")
            }
        }
    }
}
