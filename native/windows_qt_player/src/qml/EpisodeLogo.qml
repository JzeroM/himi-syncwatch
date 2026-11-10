import QtQuick
import HimiPlayer

// 662：左下角剧集 Logo（照 Flutter 播放页）。
//
// 规格：240×44，距左 16、距底 116（`logoWidth/logoHeight`）。
// 条件：`logoUrl` 非空 且 非房间模式（`!isRoom`）——与 Flutter 一致。
//
// 667：圆角徽章底（深色半透明）——PNG 透明部分原先透出挖孔黑底
// （真机截图「黑底框」）；徽章化后观感统一为浮在视频上的徽标。
Item {
    id: root
    visible: playerState.logoUrl !== "" && playerState.logoUrl !== null
             && !playerState.isRoom
    width: logo.width
    height: logo.height

    Rectangle {
        anchors.fill: parent
        anchors.margins: -6
        radius: 10
        color: Qt.rgba(0, 0, 0, 0.45)
    }

    Image {
        id: logo
        anchors.centerIn: parent
        source: root.visible ? playerState.logoUrl : ""
        fillMode: Image.PreserveAspectFit
        width: Theme.fpLogoWidth
        height: Theme.fpLogoHeight
        asynchronous: true
        sourceSize: Qt.size(Theme.fpLogoWidth * 2, Theme.fpLogoHeight * 2)
    }
}
