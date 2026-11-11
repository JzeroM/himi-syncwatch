import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer
import "evolveui" as EUI

// 662：底栏（EvolveUI 组件化；布局照 Flutter `player_bottom_row.dart`）。
//
// 【布局（两行）】
//   第一行：00:33  [进度条─────────────]  38:51
//   第二行：⏮ ⏸ ⏭  🔊 ── 80  ☀ ── 38%  [留白]  💬 HDⁿ 📄ⁿ 🎵ⁿ ⋮ⁿ speed 1.0x ⛶
//
// 【右组顺序（Flutter trailing）】弹幕 → 多版本 → 字幕 → 音轨 → 选集
//   → 倍速（图标+文字）→ 全屏（用户明确：全屏只在底栏）
//
// 【组件】按钮 = ControlButton（EvolveUI EButton 封装）；滑杆 =
// PlayerSlider（EvolveUI ESlider 封装，含点击跳转/绑定保护）。
Rectangle {
    id: root

    property bool showControls: true
    property real seekRatio: playerState.durationMs > 0
                              ? playerState.positionMs / playerState.durationMs
                              : 0

    signal playPauseClicked()
    signal prevEpisodeClicked()
    signal nextEpisodeClicked()
    signal danmakuClicked()
    signal versionClicked()
    signal subtitleClicked()
    signal audioClicked()
    signal episodeClicked()
    signal speedClicked()
    signal fullscreenClicked()
    signal volumeChanged(real v)
    signal brightnessChanged(real v)
    // 672：滑杆选中态（点击胶囊选中；选中后窗口滚轮调节该滑杆）
    property string selectedSlider: ""
    signal sliderSelected(string which)
    signal wheelAdjust(string which, int dir)
    signal seekFinished(real ratio)
    signal skipSegmentClicked()

    height: 96
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
            GradientStop { position: 1.0; color: Theme.barBottomSolid }
        }
    }

    /// 毫秒 → `mm:ss` 或 `h:mm:ss`（与 Flutter `SeekTimeLabels` 一致）
    function formatTime(ms) {
        if (ms <= 0) return "00:00"
        var total = Math.floor(ms / 1000)
        var h = Math.floor(total / 3600)
        var m = Math.floor((total % 3600) / 60)
        var s = total % 60
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s)
    }

    /// 时间列宽（≥1 小时用宽列，与 Flutter `SeekTimeLabels.cellWidth` 一致）
    function timeCellWidthFor(ms) {
        return ms >= 3600000 ? Theme.timeCellWidthWide : Theme.timeCellWidth
    }

    /// 倍速文字（与 Flutter `SpeedMenuPanel.formatSpeedLabel` 同格式）
    function formatSpeed(v) {
        var s = v.toString()
        if (s.indexOf(".") < 0) s += ".0"
        return s + "x"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.barPadH
        anchors.rightMargin: Theme.barPadH
        anchors.topMargin: Theme.barPadTop
        anchors.bottomMargin: Theme.barPadBottom
        spacing: 2

        // ── 第一行：进度条 + 时间 ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.preferredWidth: root.timeCellWidthFor(playerState.durationMs)
                text: formatTime(playerState.positionMs)
                color: Theme.mutedText
                font.pixelSize: Theme.captionSize
            }
            PlayerSlider {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                text: ""
                labelWidth: 0
                showValue: false
                minimumValue: 0
                maximumValue: Math.max(1, playerState.durationMs)
                value: playerState.positionMs
                onFinished: (v) => root.seekFinished(
                    playerState.durationMs > 0 ? v / playerState.durationMs : 0)
            }
            Text {
                Layout.preferredWidth: root.timeCellWidthFor(playerState.durationMs)
                text: formatTime(playerState.durationMs)
                color: Theme.mutedText
                font.pixelSize: Theme.captionSize
                horizontalAlignment: Text.AlignRight
            }
        }

        // ── 第二行：控制条 ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            // 播放组（28/36/28，间距 8）
            RowLayout {
                spacing: Theme.transportGap
                ControlButton {
                    icon: Icons.skipPrevious
                    iconSize: Theme.transportSideSize
                    enabled: playerState.currentEpisodeIndex > 0
                    tooltip: "上一集"
                    onClicked: root.prevEpisodeClicked()
                }
                ControlButton {
                    icon: playerState.paused ? Icons.playCircle : Icons.pauseCircle
                    iconSize: Theme.transportPlaySize
                    tooltip: playerState.paused ? "播放" : "暂停"
                    onClicked: root.playPauseClicked()
                }
                ControlButton {
                    icon: Icons.skipNext
                    iconSize: Theme.transportSideSize
                    enabled: playerState.currentEpisodeIndex >= 0
                             && playerState.currentEpisodeIndex < playerState.episodeCount - 1
                    tooltip: "下一集"
                    onClicked: root.nextEpisodeClicked()
                }
            }

            // Flutter：transport 尾 8 + leading 头 16
            Item { Layout.preferredWidth: 24 }

            // 【671 B1】音量玻璃胶囊：图标 + 加长滑杆 + 数值包裹一体（无 %）
            // 【672】点击选中（描边高亮）+ 滚轮调节
            Rectangle {
                id: volCapsule
                Layout.preferredHeight: 32
                Layout.preferredWidth: 210
                radius: 16
                color: Qt.rgba(1, 1, 1, 0.10)
                border.width: root.selectedSlider === "volume" ? 2 : 0
                border.color: theme.focusColor

                // 胶囊点击/滚轮（在滑杆之下：滑杆区域优先归滑杆）
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sliderSelected("volume")
                    onWheel: (wheel) => {
                        root.wheelAdjust("volume", wheel.angleDelta.y > 0 ? 1 : -1)
                        wheel.accepted = true
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    spacing: 6

                    Text {
                        text: playerState.volume <= 0.001 ? Icons.volumeOff
                              : playerState.volume < 0.5 ? Icons.volumeDown
                              : Icons.volumeUp
                        font.family: iconFont.name
                        font.pixelSize: Theme.fpSliderIconSize
                        color: Theme.mutedText
                    }
                    PlayerSlider {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        text: ""
                        labelWidth: 0
                        showValue: false
                        minimumValue: 0
                        maximumValue: 100
                        value: playerState.volume * 100
                        onMoved: (v) => root.volumeChanged(v / 100)
                    }
                    // 数值（包裹进小圆角盒；数值不带 %）
                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 22
                        radius: 6
                        color: Qt.rgba(1, 1, 1, 0.10)
                        Text {
                            anchors.centerIn: parent
                            text: Math.round(playerState.volume * 100)
                            color: theme.textColor
                            font.pixelSize: Theme.captionSize
                        }
                    }
                }
            }

            // 【672 D1】跳过片头/片尾**文字胶囊**（skipPrompt 驱动，与安卓/
            // 鸿蒙同字段；放音量控件右边保持间距——两侧各 10，隐藏不占位）
            Item {
                Layout.preferredWidth: 10
                visible: skipCapsule.visible
            }
            Rectangle {
                id: skipCapsule
                visible: playerState.skipPrompt === "intro"
                         || playerState.skipPrompt === "outro"
                Layout.preferredHeight: 32
                Layout.preferredWidth: skipLabel.implicitWidth + 28
                radius: 16
                color: Qt.rgba(1, 1, 1, 0.14)
                border.color: theme.borderColor
                border.width: 1

                Text {
                    id: skipLabel
                    anchors.centerIn: parent
                    text: playerState.skipPrompt === "intro"
                          ? "跳过片头" : "跳过片尾"
                    color: theme.textColor
                    font.pixelSize: Theme.captionSize
                    font.weight: 600
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.skipSegmentClicked()
                }
            }

            Item { Layout.preferredWidth: 10 }

            // 【671 B1】亮度玻璃胶囊（同音量；数值不带 %）
            Rectangle {
                id: briCapsule
                Layout.preferredHeight: 32
                Layout.preferredWidth: 210
                radius: 16
                color: Qt.rgba(1, 1, 1, 0.10)
                border.width: root.selectedSlider === "brightness" ? 2 : 0
                border.color: theme.focusColor

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sliderSelected("brightness")
                    onWheel: (wheel) => {
                        root.wheelAdjust("brightness", wheel.angleDelta.y > 0 ? 1 : -1)
                        wheel.accepted = true
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 6
                    spacing: 6

                    Text {
                        text: Icons.brightness
                        font.family: iconFont.name
                        font.pixelSize: Theme.fpSliderIconSize
                        color: Theme.fpBrightnessIcon
                    }
                    PlayerSlider {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        text: ""
                        labelWidth: 0
                        showValue: false
                        fillColor: Theme.fpBrightnessIcon
                        minimumValue: 0
                        maximumValue: 100
                        value: playerState.brightness * 100
                        onMoved: (v) => root.brightnessChanged(v / 100)
                    }
                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 22
                        radius: 6
                        color: Qt.rgba(1, 1, 1, 0.10)
                        Text {
                            anchors.centerIn: parent
                            text: Math.round(playerState.brightness * 100)
                            color: theme.textColor
                            font.pixelSize: Theme.captionSize
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // ── 右组（Flutter trailing）──
            RowLayout {
                spacing: 8

                // 弹幕开关
                ControlButton {
                    icon: playerState.danmakuEnabled ? Icons.danmakuOn : Icons.danmakuOff
                    tooltip: "弹幕"
                    onClicked: root.danmakuClicked()
                }

                // 多版本（仅非房间且多版本时显示）
                ControlButton {
                    visible: !playerState.isRoom && playerState.versionCount > 1
                    icon: Icons.highQuality
                    badge: playerState.versionCount > 0
                           ? playerState.versionCount.toString() : ""
                    tooltip: "版本"
                    onClicked: root.versionClicked()
                }

                // 字幕
                ControlButton {
                    icon: Icons.subtitles
                    badge: playerState.subtitleCount > 0
                           ? playerState.subtitleCount.toString() : ""
                    tooltip: "字幕"
                    onClicked: root.subtitleClicked()
                }

                // 音轨
                ControlButton {
                    icon: Icons.audioTrack
                    badge: playerState.audioCount > 0
                           ? playerState.audioCount.toString() : ""
                    tooltip: "音轨"
                    onClicked: root.audioClicked()
                }

                // 选集（仅非房间且多集显示）
                ControlButton {
                    visible: !playerState.isRoom && playerState.episodeCount > 1
                    icon: Icons.playlistPlay
                    badge: playerState.episodeCount > 0
                           ? playerState.episodeCount.toString() : ""
                    tooltip: "选集"
                    onClicked: root.episodeClicked()
                }

                // 倍速（662 瑕疵修复：EButton 的 label 强制 bold，"1.0x"
                // 渲染得发糊发斜——改「图标 + 独立 Text(12px)」，与
                // Flutter `Icon(speed,24) + Text(12px white70)` 同构）
                Item {
                    visible: !playerState.isRoom
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: speedRow.implicitWidth + 16

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: speedHover.hovered
                               ? (theme.isDark ? Qt.rgba(1, 1, 1, 0.12)
                                               : Qt.rgba(0, 0, 0, 0.08))
                               : "transparent"
                    }
                    Row {
                        id: speedRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            text: Icons.speed
                            font.family: iconFont.name
                            font.pixelSize: Theme.controlIconSize
                            color: theme.textColor
                        }
                        Text {
                            text: root.formatSpeed(playerState.speed)
                            color: Theme.mutedText
                            font.pixelSize: Theme.captionSize
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.speedClicked()
                    }
                    HoverHandler { id: speedHover }
                    ToolTip.visible: speedHover.hovered
                    ToolTip.text: "播放速度"
                    ToolTip.delay: 800
                }

                // 窗口全屏（仅底栏，用户明确）
                ControlButton {
                    icon: Icons.fullscreen
                    tooltip: "全屏"
                    onClicked: root.fullscreenClicked()
                }
            }
        }
    }
}
