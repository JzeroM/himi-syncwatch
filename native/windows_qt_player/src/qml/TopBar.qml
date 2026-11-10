import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer

// 659：顶栏（对应 Flutter `PlayerTopBar`）。
//
// 视觉规格（全部取自 NativePlayerTheme）：
//   - 高度 48
//   - 渐变：透明 → black@0.85（自上而下）
//   - 图标 22px，标题 16px/w600
//   - 左右内边距 16
Rectangle {
    id: root

    property bool showControls: true

    signal backClicked()
    signal kernelClicked()
    signal decodeClicked()
    signal videoFitClicked()
    signal speedClicked()
    signal fullscreenClicked()

    height: Theme.topBarHeight
    color: "transparent"
    visible: opacity > 0
    opacity: showControls ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.controlsFadeMs } }

    // 渐变背景：透明 → black@0.85（与 Flutter `_buildTopBar` 一致）
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.barGradientSolid }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.barPadH
        anchors.rightMargin: Theme.barPadH
        spacing: 4

        // 返回
        ControlButton {
            icon: Icons.arrowBack
            iconSize: Theme.topIconSize
            tooltip: "返回"
            onClicked: root.backClicked()
        }

        // 标题（保底 56 宽，超出省略）
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 56
            Layout.leftMargin: 4
            text: playerState.title
            color: Theme.white
            font.pixelSize: Theme.titleSize
            font.weight: Theme.titleWeight
            elide: Text.ElideRight
        }

        // 网速（12px white54）
        Text {
            visible: playerState.networkSpeedText !== ""
            text: playerState.networkSpeedText
            color: Theme.white54
            font.pixelSize: Theme.captionSize
        }

        // 内核胶囊（图标 + 短名）
        Rectangle {
            visible: playerState.engineLabel !== ""
            Layout.preferredHeight: 30
            Layout.preferredWidth: kernelRow.implicitWidth + Theme.chipPadH * 2
            radius: Theme.radiusChip
            color: Theme.white12
            border.color: Theme.rim
            border.width: 1

            RowLayout {
                id: kernelRow
                anchors.centerIn: parent
                spacing: 4
                Text {
                    text: Icons.memory
                    font.family: "Material Icons"
                    font.pixelSize: 16
                    color: Theme.white
                }
                Text {
                    text: playerState.engineLabel
                    color: Theme.white
                    font.pixelSize: Theme.captionSize
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.kernelClicked()
            }
        }

        // 解码方式
        ControlButton {
            icon: Icons.highQuality
            iconSize: Theme.topIconSize
            tooltip: "解码方式：" + playerState.decodeMode
            onClicked: root.decodeClicked()
        }

        // 画面比例
        ControlButton {
            icon: Icons.aspectRatio
            iconSize: Theme.topIconSize
            tooltip: "画面比例：" + playerState.videoFit
            onClicked: root.videoFitClicked()
        }

        // 倍速
        ControlButton {
            icon: Icons.speed
            iconSize: Theme.topIconSize
            badge: playerState.speed.toFixed(1)
            tooltip: "播放速度"
            onClicked: root.speedClicked()
        }

        // 全屏
        ControlButton {
            icon: Icons.fullscreen
            iconSize: Theme.topIconSize
            tooltip: "全屏"
            onClicked: root.fullscreenClicked()
        }
    }
}
