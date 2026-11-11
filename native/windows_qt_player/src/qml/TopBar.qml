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

    signal decodeClicked()
    signal subtitleStyleClicked()
    signal videoFitClicked()

    height: Theme.topBarHeight
    color: "transparent"
    visible: opacity > 0
    opacity: showControls ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.controlsFadeMs } }

    // 668：渐变玻璃条（透明→黑 85%）——控件悬浮层逐像素透明，
    // 视频透过玻璃层 = Flutter 同款液态玻璃观感。
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.barGradientSolid }
        }
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

    // ── 679：顶栏拖拽区（无边框窗口的移动手柄）──
    //
    // 放在 RowLayout **之前**（z 序在下），按钮先消费事件，空白处才落到
    // 这里 → 拖动不会误触按钮。整条顶栏可拖（用户选定的方案）。
    MouseArea {
        anchors.fill: parent
        // 只在按到空白区域时接管（子控件已处理的不再冒泡到这里）
        propagateComposedEvents: false
        onPressed: (mouse) => {
            mpvWindow.startSystemMove()
            mouse.accepted = true
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.barPadH
        anchors.rightMargin: Theme.barPadH
        spacing: 8

        // 679：返回按钮已移除（退出统一走 Flutter 面板窗关闭 + Esc）
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
        // 677：房间模式不显示（对齐安卓 `videoFitIcon.visibility` 与
        // 鸿蒙 `!this.state().isRoom` 判定）。
        ControlButton {
            visible: !playerState.isRoom
            icon: root.videoFitIconFor(root.videoFitMode)
            iconSize: Theme.topIconSize
            tooltip: "画面比例：" + root.videoFitLabelFor(root.videoFitMode)
            onClicked: root.videoFitClicked()
        }
    }
}
