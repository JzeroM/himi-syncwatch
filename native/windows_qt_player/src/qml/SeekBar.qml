import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// 656：可拖动的进度条（对应 Flutter 的 SeekBar + 时间标签）。
//
// 【为什么不用 Slider】Qt Quick Controls 的 Slider 默认带手柄和主题样式，
// 与播放器观感差距大，且拖拽时无法方便地「拖中不跟播放位置」。这里用
// 自绘轨道 + MouseArea，逻辑更可控。
Item {
    id: root

    property real position: 0      // 0.0 ~ 1.0
    property bool dragging: false
    property string leftText: "00:00"
    property string rightText: "00:00"

    signal seekStarted()
    signal seekFinished(real ratio)

    implicitHeight: 36

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        height: 4
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.3)

        // 已播放部分
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.position))
            height: parent.height
            radius: parent.radius
            color: "#FFFFFF"
        }

        // 拖拽手柄（hover 或拖动时显示）
        Rectangle {
            visible: mouse.containsMouse || root.dragging
            x: parent.width * Math.max(0, Math.min(1, root.position)) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            radius: 6
            color: "#FFFFFF"
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onPressed: {
            root.dragging = true
            root.seekStarted()
            root.position = Math.max(0, Math.min(1, mouse.x / width))
        }
        onPositionChanged: {
            if (!root.dragging) return
            root.position = Math.max(0, Math.min(1, mouse.x / width))
        }
        onReleased: {
            if (!root.dragging) return
            root.dragging = false
            root.seekFinished(root.position)
        }
    }

    // 时间标签（左当前 / 右总时长）
    Text {
        anchors.left: parent.left
        anchors.top: parent.bottom
        anchors.topMargin: 2
        text: root.leftText
        color: "#CCFFFFFF"
        font.pixelSize: 12
    }
    Text {
        anchors.right: parent.right
        anchors.top: parent.bottom
        anchors.topMargin: 2
        text: root.rightText
        color: "#CCFFFFFF"
        font.pixelSize: 12
    }
}
