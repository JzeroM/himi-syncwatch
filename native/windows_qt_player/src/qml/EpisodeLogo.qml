import QtQuick
import HimiPlayer

// 662：左下角剧集 Logo（照 Flutter 播放页）。
//
// 规格：240×44，距左 16、距底 116（`logoWidth/logoHeight`）。
// 条件：`logoUrl` 非空 且 非房间模式（`!isRoom`）——与 Flutter 一致。
//
// 668：直接叠在视频上（悬浮层真合成，PNG 透明处见视频 = 零黑底）。
Item {
    id: root
    visible: playerState.logoUrl !== "" && playerState.logoUrl !== null
             && !playerState.isRoom
    width: logo.width
    height: logo.height

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
