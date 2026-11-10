pragma Singleton
import QtQuick

// 659：播放器 UI 视觉常量（单一真相源）。
//
// 【为什么要有这个文件】Flutter 侧 `lib/services/player/native/
// native_player_theme.dart` 已经是三端原生 UI 的常量来源（245 行），
// 安卓/鸿蒙都照它实现。QML 也照它写，才能做到「与 Flutter 一致」。
//
// 【维护约定】改这里之前先改 Dart 那份，两边必须同步。
// 测试 `windows_qt_player_656_test.dart` 会逐项比对关键值。
QtObject {
    // ── 颜色（对应 NativePlayerTheme）──
    readonly property color accent: "#6366F1"
    readonly property color white: "#FFFFFF"
    readonly property color white70: "#B3FFFFFF"
    readonly property color white54: "#8AFFFFFF"
    readonly property color white38: "#62FFFFFF"
    readonly property color white24: "#3DFFFFFF"
    readonly property color white12: "#1FFFFFFF"

    /// 面板背景（`panelTint` = 0x1F1A1D23，深色磨砂基色）
    readonly property color panelTint: "#1F1A1D23"
    readonly property color rim: "#4DFFFFFF"
    readonly property color focusRing: "#C1C2FE"
    readonly property color shadow: "#4A000000"

    /// 顶栏渐变实端（black @ 0.85，Flutter `_buildTopBar`）
    readonly property color barGradientSolid: "#D9000000"
    /// 底栏渐变实端（black @ 0.85，Flutter `_buildControls`）
    readonly property color barBottomSolid: "#D9000000"

    // ── 圆角 ──
    readonly property real radiusPanel: 16
    readonly property real radiusChip: 10
    readonly property real radiusCard: 18

    // ── 顶栏 ──
    readonly property real topBarHeight: 48
    readonly property real topIconSize: 22
    readonly property real titleSize: 16
    readonly property int titleWeight: 600
    readonly property real captionSize: 12
    readonly property real chipPadH: 9
    readonly property real chipPadV: 6

    // ── 底栏 ──
    readonly property real barPadH: 16
    readonly property real barPadTop: 10
    readonly property real barPadBottom: 12
    readonly property real timeCellWidth: 56
    readonly property real timeCellWidthWide: 78

    /// 进度条 track 6 / thumb 8
    readonly property real seekTrackHeight: 6
    readonly property real seekThumbRadius: 8

    /// 播放组：上一个 28 / 播放 36 / 下一个 28，间距 8
    readonly property real transportSideSize: 28
    readonly property real transportPlaySize: 36
    readonly property real transportGap: 8

    /// 右侧图标 24、间距 20
    readonly property real controlIconSize: 24
    readonly property real controlGap: 20

    /// 角标：9px 字，分档 15 / 19 / 24
    readonly property real badgeFontSize: 9
    readonly property real badgeMinSize: 15
    readonly property real badgeWideSize: 19
    readonly property real badgeXlSize: 24

    // ── 面板 ──
    readonly property real panelMinWidth: 260
    readonly property real panelMaxWidth: 320
    readonly property real panelRight: 12
    readonly property real panelTopOffset: 48
    readonly property real panelBottomOffset: 116
    readonly property real panelPadH: 16
    readonly property real panelPadV: 12
    readonly property real panelTitleSize: 15
    readonly property real panelOptionSize: 14
    readonly property real panelCheckSlot: 18

    // ── 动效 ──
    readonly property int controlsFadeMs: 200
    readonly property int autoHideMs: 5000

    // ── Flutter 播放页专用（截图实测，与原生 UI 规格不同）──
    //
    // 【为什么单独一组】Flutter 播放页（`_buildVolumeSlider` 等）与原生
    // UI（`NativePlayerTheme`）的规格**不同**：
    //   - Flutter 进度条 track 4 / thumb 6（原生是 6/8）
    //   - Flutter 音量滑杆 96 宽 + 数值 28/34 宽（原生无数值列）
    //   - Flutter 亮度图标 #FFD54F（原生无此色）
    // 用户给的截图是 Flutter 播放页，所以 QML 照这组。
    readonly property real fpSeekTrackHeight: 4
    readonly property real fpSeekThumbRadius: 6
    readonly property real fpSliderWidth: 96
    readonly property real fpSliderIconSize: 18
    readonly property real fpSliderTrackHeight: 4
    readonly property real fpSliderThumbRadius: 6
    readonly property real fpVolumeValueWidth: 28
    readonly property real fpBrightnessValueWidth: 34
    readonly property color fpBrightnessIcon: "#FFD54F"
    readonly property real fpLogoWidth: 240
    readonly property real fpLogoHeight: 44

    /// 角标正圆边长（按文本长度分档，与 Dart `badgeSizeFor` 一致）
    function badgeSizeFor(text) {
        var len = text.length
        if (len >= 4) return badgeXlSize
        if (len === 3) return badgeWideSize
        return badgeMinSize
    }
}
