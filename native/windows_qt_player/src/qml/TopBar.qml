import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer
import "evolveui" as EUI

// 662：顶栏（EvolveUI 组件化；布局照 Flutter `player_top_bar.dart`）。
//
// 【布局（Flutter 顺序）】
//   ← 返回 | 标题 | 网速 | MPV 内核胶囊（纯文字） | [≡]显示调节 | [▣]解码 | 画面比例
//
// 【662 修正】
//   - 内核胶囊纯文字（Flutter Text(kernelLabel)，无图标）
//   - 解码图标 = Icons.memory（原 highQuality 是「HD」错字形）
//   - 新增「显示调节」按钮（解码左侧）；倍速/全屏不在顶栏
//   - 画面比例图标随模式切换（Flutter `_videoFitIcons` 语义映射）
//   - 样式组件走 EvolveUI（EButton 胶囊/图标钮），展开态用主题高亮色
Rectangle {
    id: root

    property bool showControls: true
    /// 面板真实可见性驱动的高亮（662 瑕疵修复：不再用字符串插销
    /// openMenu——面板创建失败/被锁隐藏时插销会残留，图标卡在高亮色）
    property bool decodeOpen: false
    property bool adjustOpen: false
    /// 当前画面比例（665：本地循环状态，图标随之切换）
    property string videoFitMode: "contain"

    signal backClicked()
    signal decodeClicked()
    signal subtitleStyleClicked()
    signal videoFitClicked()

    height: Theme.topBarHeight
    color: "transparent"
    visible: opacity > 0
    opacity: showControls ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.controlsFadeMs } }

    // 667：浮岛圆角胶囊底（孔 = 胶囊矩形 + 圆角孔，不露黑角）。
    // 全宽渐变遮罩改由 mpv ASS 画进视频（真半透明压视频，同 Flutter）。
    Rectangle {
        id: chip
        anchors.fill: parent
        anchors.margins: 4
        radius: 20
        color: Qt.rgba(0.08, 0.08, 0.10, 0.82)
    }

    // ── 画面比例图标映射（与 Flutter `_videoFitModes/_videoFitIcons` 同序）──
    function videoFitIconFor(mode) {
        if (mode === "cover") return Icons.cropSimple   // 裁剪
        if (mode === "fill") return Icons.zoomOutMap    // 铺满
        if (mode === "none") return Icons.aspectRatio   // 原始
        return Icons.fitScreen                          // 自适应
    }
    function videoFitLabelFor(mode) {
        if (mode === "cover") return "裁剪"
        if (mode === "fill") return "铺满"
        if (mode === "none") return "原始"
        return "自适应"
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.barPadH
        anchors.rightMargin: Theme.barPadH
        spacing: 8

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
            text: playerState.title
            color: theme.textColor
            font.pixelSize: Theme.titleSize
            font.weight: Theme.titleWeight
            elide: Text.ElideRight
        }

        // 网速
        Text {
            visible: playerState.networkSpeedText !== ""
            text: playerState.networkSpeedText
            color: Theme.mutedText
            font.pixelSize: Theme.captionSize
        }

        // 显示调节（面板可见时高亮）
        ControlButton {
            icon: Icons.tune
            iconSize: 18
            iconColor: root.adjustOpen
                       ? theme.focusColor : theme.textColor
            tooltip: "显示调节"
            onClicked: root.subtitleStyleClicked()
        }

        // 解码方式（面板可见时高亮）
        ControlButton {
            icon: Icons.memory
            iconSize: 18
            iconColor: root.decodeOpen
                       ? theme.focusColor : theme.textColor
            tooltip: "解码方式：" + playerState.decodeMode
            onClicked: root.decodeClicked()
        }

        // 画面比例（图标随模式）
        ControlButton {
            icon: root.videoFitIconFor(root.videoFitMode)
            iconSize: Theme.topIconSize
            tooltip: "画面比例：" + root.videoFitLabelFor(root.videoFitMode)
            onClicked: root.videoFitClicked()
        }
    }
}
