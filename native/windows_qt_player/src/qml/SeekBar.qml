import QtQuick
import HimiPlayer

// 659：进度条（对应 Flutter 的 seek bar）。
//
// 规格（NativePlayerTheme）：
//   - track 高 6，圆角 3
//   - thumb 半径 8（16px 圆）
//   - 时间文本 12px white54，左右各 56 宽
//   - 已播放部分纯白，未播放 white24
Item {
    id: root

    property real position: 0      // 0.0 ~ 1.0
    property bool dragging: false
    property string leftText: "00:00"
    property string rightText: "00:00"

    signal seekStarted()
    signal seekFinished(real ratio)

    implicitHeight: 32

    // 时间标签（左当前 / 右总时长），占固定列宽
    Text {
        id: leftLabel
        anchors.left: parent.left
        anchors.verticalCenter: trackArea.verticalCenter
        width: Theme.timeCellWidth
        text: root.leftText
        color: Theme.white54
        font.pixelSize: Theme.captionSize
        horizontalAlignment: Text.AlignLeft
    }

    Text {
        id: rightLabel
        anchors.right: parent.right
        anchors.verticalCenter: trackArea.verticalCenter
        width: Theme.timeCellWidth
        text: root.rightText
        color: Theme.white54
        font.pixelSize: Theme.captionSize
        horizontalAlignment: Text.AlignRight
    }

    Item {
        id: trackArea
        anchors.left: leftLabel.right
        anchors.right: rightLabel.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        height: parent.height

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Theme.seekTrackHeight
            radius: height / 2
            color: Theme.white24

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, root.position))
                height: parent.height
                radius: parent.radius
                color: Theme.white
            }

            // thumb（hover 或拖动时显示）
            Rectangle {
                visible: mouse.containsMouse || root.dragging
                x: parent.width * Math.max(0, Math.min(1, root.position)) - radius
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.seekThumbRadius * 2
                height: width
                radius: Theme.seekThumbRadius
                color: Theme.white
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            function ratioAt(px) {
                return Math.max(0, Math.min(1, px / width))
            }

            onPressed: {
                root.dragging = true
                root.seekStarted()
                root.position = ratioAt(mouse.x)
            }
            onPositionChanged: {
                if (!root.dragging) return
                root.position = ratioAt(mouse.x)
            }
            onReleased: {
                if (!root.dragging) return
                root.dragging = false
                root.seekFinished(root.position)
            }
        }
    }
}
