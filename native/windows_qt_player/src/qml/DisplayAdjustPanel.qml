import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer
import "evolveui" as EUI

// 664：「显示调节」面板（EvolveUI `ECard` + `EList` + `ESlider` 组合，
// 对照 Flutter `DisplayAdjustPanel`：字幕段 + 弹幕段）。
//
// 【构成】
//   字幕：大小(0.5~3.0×) / 位置(0~200px) / 延迟(-5.0~+5.0s) / 恢复默认
//   弹幕：速度(0.5~2.0×) / 大小(0.5~2.0×) / 透明度(10~100%) / 恢复默认
//
// 【组件】滑杆行 = PlayerSlider（ESlider 封装，自带标签+数值列）；
// 恢复默认 = EList 单行（选中态 = 已在默认值）；容器 = ECard。
//
// 【命令】拖动 → `adjustDisplay {key,value}`（与安卓/鸿蒙同协议）；
// 恢复默认 → `resetDisplay {scope: subtitle|danmaku}`。
// 延迟滑杆以秒显示（-5~5s）但命令按毫秒发（×1000）；
// 透明度滑杆以百分比显示（10~100%）但命令按 0~1 发（÷100）。
EUI.ECard {
    id: root

    signal closed()
    signal adjust(string key, real value)
    signal reset(string scope)

    width: Math.max(Theme.panelMinWidth,
                    Math.min(Theme.panelMaxWidth,
                             parent ? parent.width * 0.42 : Theme.panelMinWidth))
    height: Math.min(parent ? parent.height - Theme.panelTopOffset
                                  - Theme.panelBottomOffset : 400,
                     root.padding * 2 + 36 + contentCol.implicitHeight)
    radius: 20
    visible: false

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

    // ── 标题栏（无 ✕：照 Flutter，点别处/再点控件收回）──
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 36

        Text {
            Layout.fillWidth: true
            text: "显示调节"
            color: theme.textColor
            font.pixelSize: Theme.panelTitleSize
            font.weight: 600
        }
    }

    // ── 内容 ──
    Column {
        id: contentCol
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight

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
        // 恢复默认（EList 单行；选中 = 当前已是默认值）
        // 恢复默认（自绘行；667：EList 播放委托缺失角色报错 → 行不显示）
        Rectangle {
            width: contentCol.width
            height: 44
            radius: 8
            color: subResetMouse.containsMouse
                   ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.08)
                                   : Qt.rgba(0, 0, 0, 0.06))
                   : "transparent"
            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.panelPadH
                anchors.verticalCenter: parent.verticalCenter
                text: "恢复默认"
                color: (Math.abs(playerState.subtitleScale - 1.0) < 0.01
                        && playerState.subtitleMarginY === 22
                        && Math.abs(playerState.subtitleDelayMs) < 0.5)
                       ? theme.focusColor : theme.textColor
                font.pixelSize: Theme.panelOptionSize
            }
            MouseArea {
                id: subResetMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.reset("subtitle")
            }
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
        Rectangle {
            width: contentCol.width
            height: 44
            radius: 8
            color: dmResetMouse.containsMouse
                   ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.08)
                                   : Qt.rgba(0, 0, 0, 0.06))
                   : "transparent"
            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.panelPadH
                anchors.verticalCenter: parent.verticalCenter
                text: "恢复默认"
                color: (Math.abs(playerState.danmakuSpeed - 0.7) < 0.01
                        && Math.abs(playerState.danmakuFontSize - 0.5) < 0.01
                        && Math.abs(playerState.danmakuOpacity - 0.8) < 0.01)
                       ? theme.focusColor : theme.textColor
                font.pixelSize: Theme.panelOptionSize
            }
            MouseArea {
                id: dmResetMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.reset("danmaku")
            }
        }
    }
}
