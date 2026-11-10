pragma Singleton
import QtQuick

// 662：播放器图标码点（Font Awesome 6 Free Solid）。
//
// 【为什么是 FontAwesome】662 起 Qt 播放器窗口的 UI 组件库换成
// EvolveUI（third_party/evolveui），其生态图标即 FontAwesome——按
// 用户决策「换 FontAwesome」统一字形。注意 Flutter/安卓/鸿蒙播放器
// 仍是 Material Icons（NativePlayerIcons），两侧**语义一一对应**、
// 字形不同（用户已确认此取舍）。
//
// 【字体加载】字体由 Main.qml 根级 `iconFont` FontLoader 提供（与
// EvolveUI 组件的 `iconFont` 上下文约定一致），Text 里用
// `font.family: iconFont.name`。
//
// 【码点来源】Font Awesome 6 Free-Solid-900.otf（Cheatsheet）。
// FA6 Solid 全部在 BMP 内，`\uXXXX` 转义即可（无 5 位码点问题）。
QtObject {
    // ── 顶栏 ──
    readonly property string arrowBack: "\uf060"          // fa-arrow-left
    readonly property string memory: "\uf2db"             // fa-microchip
    readonly property string highQuality: "\uf5fd"        // fa-layer-group（多版本）
    readonly property string aspectRatio: "\uf125"        // fa-crop（比例=原始）
    readonly property string speed: "\uf625"              // fa-gauge-high
    readonly property string fullscreen: "\uf065"         // fa-expand
    readonly property string closeFullscreen: "\uf066"    // fa-compress
    readonly property string tune: "\uf1de"               // fa-sliders（显示调节）
    readonly property string fitScreen: "\uf0b2"          // fa-arrows-alt（自适应）
    readonly property string zoomOutMap: "\uf31e"         // fa-maximize（铺满）
    readonly property string cropSimple: "\uf565"         // fa-crop-simple（裁剪）
    readonly property string rotate: "\uf3cd"             // fa-mobile-screen-button

    // ── 底栏 ──
    readonly property string playCircle: "\uf144"         // fa-circle-play
    readonly property string pauseCircle: "\uf28b"        // fa-circle-pause
    readonly property string skipPrevious: "\uf048"       // fa-backward-step
    readonly property string skipNext: "\uf051"           // fa-forward-step
    readonly property string volumeUp: "\uf028"           // fa-volume-high
    readonly property string volumeDown: "\uf027"         // fa-volume-low
    readonly property string volumeOff: "\uf6a9"          // fa-volume-xmark
    readonly property string brightness: "\uf185"         // fa-sun
    readonly property string danmakuOn: "\uf086"          // fa-comments
    readonly property string danmakuOff: "\uf4b5"         // fa-comment-slash
    readonly property string subtitles: "\uf20a"          // fa-closed-captioning
    readonly property string audioTrack: "\uf001"         // fa-music
    readonly property string playlistPlay: "\uf0cb"       // fa-list-ol（选集）
    readonly property string openInFull: "\uf08e"         // fa-arrow-up-right-from-square

    // ── 面板 ──
    readonly property string check: "\uf00c"              // fa-check
    readonly property string close: "\uf00d"              // fa-xmark
    readonly property string chevronRight: "\uf054"       // fa-chevron-right
    readonly property string expandMore: "\uf078"         // fa-chevron-down
    readonly property string radioButtonChecked: "\uf192" // fa-circle-dot
    readonly property string radioButtonUnchecked: "\uf111" // fa-circle

    // ── 其他 ──
    readonly property string lock: "\uf023"               // fa-lock
    readonly property string lockOpen: "\uf3c1"           // fa-lock-open
    readonly property string people: "\uf0c0"             // fa-user-group
    readonly property string replay10: "\uf0e2"           // fa-rotate-left
    readonly property string forward10: "\uf01e"          // fa-rotate-right
}
