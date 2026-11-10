import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer

// 660：底栏（照 Flutter `PlayerBottomRow` 截图实测布局）。
//
// 【布局（两行）】
//   第一行：00:33  [进度条─────────────]  38:51
//   第二行：⏮ ⏸ ⏭  🔊 ── 80  ☀ ── 38%  💬 📄 🎵 ⋮ 1.0x ⛶
//
// 【与 Flutter 截图逐项对齐】
//   进度条：track 4 / thumb 6（比原生 UI 的 6/8 更细）
//   音量：图标 18(white70) + 滑杆 96 + 数值列 28(11px)
//   亮度：图标 18(#FFD54F) + 滑杆 96 + 数值列 34(11px)
//   播放组：28/36/28，间距 8，紧接音量左侧
//   右侧：弹幕/字幕/音轨/选集/倍速/全屏，间距 20
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
    signal subtitleClicked()
    signal audioClicked()
    signal episodeClicked()
    signal speedClicked()
    signal fullscreenClicked()
    signal volumeChanged(real v)
    signal brightnessChanged(real v)
    signal seekFinished(real ratio)

    height: 96
    color: "transparent"
    visible: opacity > 0
    opacity: showControls ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.controlsFadeMs } }

    // 渐变背景：透明 → black@0.85
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.barBottomSolid }
        }
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
                Layout.preferredWidth: Theme.timeCellWidth
                text: formatTime(playerState.positionMs)
                color: Theme.white54
                font.pixelSize: Theme.captionSize
            }
            GlassSlider {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                value: root.seekRatio
                trackHeight: Theme.fpSeekTrackHeight
                thumbRadius: Theme.fpSeekThumbRadius
                onSeekFinished: (ratio) => root.seekFinished(ratio)
            }
            Text {
                Layout.preferredWidth: Theme.timeCellWidth
                text: formatTime(playerState.durationMs)
                color: Theme.white54
                font.pixelSize: Theme.captionSize
                horizontalAlignment: Text.AlignRight
            }
        }

        // ── 第二行：控制条 ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            // 播放组（紧接左侧，间距 8）
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

            Item { Layout.preferredWidth: 8 }

            // 音量：图标 18 + 滑杆 96 + 数值 28
            RowLayout {
                spacing: 4
                Text {
                    text: playerState.volume <= 0.001 ? Icons.volumeOff
                          : playerState.volume < 0.5 ? Icons.volumeDown
                          : Icons.volumeUp
                    font.family: "Material Icons"
                    font.pixelSize: Theme.fpSliderIconSize
                    color: Theme.white70
                }
                GlassSlider {
                    Layout.preferredWidth: Theme.fpSliderWidth
                    Layout.preferredHeight: 24
                    value: playerState.volume
                    onSeekFinished: (v) => root.volumeChanged(v)
                    onSeekStarted: root.volumeChanged(value)
                }
                Text {
                    Layout.preferredWidth: Theme.fpVolumeValueWidth
                    text: Math.round(playerState.volume * 100).toString()
                    color: Theme.white70
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignRight
                }
            }

            Item { Layout.preferredWidth: 16 }

            // 亮度：图标 18(#FFD54F) + 滑杆 96 + 数值 34
            RowLayout {
                spacing: 4
                Text {
                    text: Icons.brightness
                    font.family: "Material Icons"
                    font.pixelSize: Theme.fpSliderIconSize
                    color: Theme.fpBrightnessIcon
                }
                GlassSlider {
                    Layout.preferredWidth: Theme.fpSliderWidth
                    Layout.preferredHeight: 24
                    value: playerState.brightness
                    accent: Theme.fpBrightnessIcon
                    onSeekFinished: (v) => root.brightnessChanged(v)
                    onSeekStarted: root.brightnessChanged(value)
                }
                Text {
                    Layout.preferredWidth: Theme.fpBrightnessValueWidth
                    text: Math.round(playerState.brightness * 100) + "%"
                    color: Theme.white70
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignRight
                }
            }

            Item { Layout.fillWidth: true }

            // 右侧：弹幕/字幕/音轨/选集/倍速/全屏
            ControlButton {
                icon: playerState.danmakuEnabled ? Icons.danmakuOn : Icons.danmakuOff
                tooltip: "弹幕"
                onClicked: root.danmakuClicked()
            }
            ControlButton {
                icon: Icons.subtitles
                badge: playerState.subtitleCount > 0
                       ? playerState.subtitleCount.toString() : ""
                tooltip: "字幕"
                onClicked: root.subtitleClicked()
            }
            ControlButton {
                icon: Icons.audioTrack
                badge: playerState.audioCount > 0
                       ? playerState.audioCount.toString() : ""
                tooltip: "音轨"
                onClicked: root.audioClicked()
            }
            ControlButton {
                icon: Icons.playlistPlay
                enabled: playerState.episodeCount > 1
                badge: playerState.episodeCount > 1
                       ? playerState.episodeCount.toString() : ""
                tooltip: "选集"
                onClicked: root.episodeClicked()
            }
            ControlButton {
                icon: Icons.speed
                badge: playerState.speed.toFixed(1)
                tooltip: "播放速度"
                onClicked: root.speedClicked()
            }
            ControlButton {
                icon: Icons.fullscreen
                tooltip: "全屏"
                onClicked: root.fullscreenClicked()
            }
        }
    }

    /// 毫秒 → `mm:ss` 或 `h:mm:ss`
    function formatTime(ms) {
        if (ms <= 0) return "00:00"
        var total = Math.floor(ms / 1000)
        var h = Math.floor(total / 3600)
        var m = Math.floor((total % 3600) / 60)
        var s = total % 60
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s)
    }
}
