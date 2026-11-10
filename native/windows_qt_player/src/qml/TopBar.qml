import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// 656：顶栏（对应 Flutter 的 PlayerTopBar）。
//
// 元素：返回 / 标题 / 网速 / 内核 / 解码 / 画面比例 / 倍速 / 全屏
Rectangle {
    id: root

    property bool showControls: true
    signal backClicked()
    signal kernelClicked()
    signal decodeClicked()
    signal videoFitClicked()
    signal speedClicked()
    signal fullscreenClicked()

    height: 48
    color: Qt.rgba(0, 0, 0, 0.45)
    visible: opacity > 0
    opacity: showControls ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 12
        spacing: 8

        // 返回
        ControlButton {
            icon: "\ue5c4"   // arrow_back
            tooltip: "返回"
            onClicked: root.backClicked()
        }

        // 标题
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            text: playerState.title
            color: "#FFFFFF"
            font.pixelSize: 15
            elide: Text.ElideRight
        }

        // 网速
        Text {
            visible: playerState.networkSpeedText !== ""
            text: playerState.networkSpeedText
            color: "#B0FFFFFF"
            font.pixelSize: 12
        }

        // 内核（点击切换引擎）
        ControlButton {
            icon: "\ue322"   // memory
            badge: playerState.engineLabel
            tooltip: "播放内核"
            onClicked: root.kernelClicked()
        }

        // 解码模式
        ControlButton {
            icon: "\ue3c9"   // high_quality
            tooltip: "解码方式"
            onClicked: root.decodeClicked()
        }

        // 画面比例
        ControlButton {
            icon: "\ue3c4"   // aspect_ratio
            tooltip: "画面比例：" + playerState.videoFit
            onClicked: root.videoFitClicked()
        }

        // 倍速
        ControlButton {
            icon: "\ue9e4"   // speed
            badge: playerState.speed.toFixed(1)
            tooltip: "播放速度"
            onClicked: root.speedClicked()
        }

        // 全屏
        ControlButton {
            icon: "\ue5d0"   // fullscreen
            tooltip: "全屏"
            onClicked: root.fullscreenClicked()
        }
    }
}
