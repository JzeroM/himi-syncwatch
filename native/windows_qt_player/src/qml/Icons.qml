pragma Singleton
import QtQuick

// 659：播放器图标码点（Material Icons）。
//
// 【单一真相源】与 `lib/services/player/native/native_player_icons.dart`
// 逐值一致。那份又由 `tool/native_icons.json` 校验，并与 Flutter
// `Icons.xxx.codePoint` 比对——所以这里用的字形与 Flutter 播放页**同款**。
//
// 【为什么之前是错的】656 首版我凭记忆写码点（如 `\ue5c4` 当返回），
// 那些是 Flutter 的 `Icons.arrow_back`，与项目统一使用的
// `NativePlayerIcons.arrowBack = 0xE092` **不是同一个字形**。
// 必须用本文件的值。
QtObject {
    // 顶栏
    readonly property string arrowBack: "\ue092"
    readonly property string memory: "\ue3db"
    readonly property string highQuality: "\ue30f"
    readonly property string aspectRatio: "\ue0a3"
    readonly property string speed: "\ue5e0"
    readonly property string fullscreen: "\ue2cb"
    readonly property string closeFullscreen: "\ue16b"
    readonly property string tune: "\ue683"
    readonly property string fitScreen: "\ue28c"
    readonly property string zoomOutMap: "\ue6ff"
    readonly property string rotate: "\uf07bf"

    // 底栏
    readonly property string playCircle: "\ue4cd"
    readonly property string pauseCircle: "\ue47e"
    readonly property string skipPrevious: "\ue5be"
    readonly property string skipNext: "\ue5bd"
    readonly property string volumeUp: "\ue6c5"
    readonly property string volumeDown: "\ue6c2"
    readonly property string volumeOff: "\ue6c4"
    readonly property string brightness: "\ue10a"
    readonly property string danmakuOn: "\ue17e"
    readonly property string danmakuOff: "\uf04d2"
    readonly property string subtitles: "\ue619"
    readonly property string audioTrack: "\ue0b6"
    readonly property string playlistPlay: "\ue4d4"
    readonly property string openInFull: "\ue45b"

    // 面板
    readonly property string check: "\ue156"
    readonly property string close: "\ue16a"
    readonly property string chevronRight: "\ue15f"
    readonly property string expandMore: "\ue246"
    readonly property string radioButtonChecked: "\ue503"
    readonly property string radioButtonUnchecked: "\ue504"

    // 其他
    readonly property string lock: "\ue3ae"
    readonly property string lockOpen: "\ue3b0"
    readonly property string people: "\ue486"
    readonly property string replay10: "\ue524"
    readonly property string forward10: "\ue2c5"
}
