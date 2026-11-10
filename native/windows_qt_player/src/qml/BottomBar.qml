import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import HimiPlayer

// 659：底栏（对应 Flutter `PlayerBottomRow`）。
//
// 规格（NativePlayerTheme）：
//   - 渐变：透明 → black@0.85
//   - 内边距 h16 / top10 / bottom12
//   - 进度条 track 6 / thumb 8，时间列 56
//   - 播放组：上一个 28 / 播放 36 / 下一个 28，间距 8
//   - 右侧图标 24、间距 20
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
    signal volumeChanged(real volume)
    signal brightnessChanged(real value)
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
        spacing: 0

        // ── 进度条 ──
        SeekBar {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            position: root.seekRatio
            leftText: formatTime(playerState.positionMs)
            rightText: formatTime(playerState.durationMs)
            onSeekFinished: (ratio) => root.seekFinished(ratio)
        }

        Item { Layout.fillHeight: true }

        // ── 控制行 ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.controlGap

            // 左槽：音量（图标 + 滑杆）
            RowLayout {
                spacing: 6
                ControlButton {
                    icon: playerState.volume <= 0.001 ? Icons.volumeOff
                                                      : Icons.volumeUp
                    tooltip: "音量 " + Math.round(playerState.volume * 100)
                    onClicked: root.volumeChanged(playerState.volume > 0.5 ? 0 : 1)
                }
                Slider {
                    Layout.preferredWidth: 80
                    from: 0; to: 1
                    value: playerState.volume
                    onMoved: root.volumeChanged(value)
                }
            }

            Item { Layout.preferredWidth: 8 }

            // 播放组：上一个 / 播放暂停 / 下一个
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

            Item { Layout.fillWidth: true }

            // 右组：弹幕 / 字幕 / 音轨 / 选集 / 倍速 / 全屏
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
