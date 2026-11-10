import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

// 656：底栏（对应 Flutter 的 PlayerBottomRow）。
//
// 布局（复刻 Flutter 播放页）：
//   第一行：进度条 + 时间
//   第二行：左组（音量/亮度）| 播放暂停 | 下一集 …… 右组（弹幕/字幕/音轨/选集/倍速/全屏）
Rectangle {
    id: root

    property bool showControls: true
    property real seekRatio: playerState.durationMs > 0
                              ? playerState.positionMs / playerState.durationMs
                              : 0

    signal playPauseClicked()
    signal nextEpisodeClicked()
    signal danmakuClicked()
    signal subtitleClicked()
    signal audioClicked()
    signal episodeClicked()
    signal speedClicked()
    signal fullscreenClicked()
    signal volumeChanged(real volume)
    signal seekFinished(real ratio)

    height: 96
    color: Qt.rgba(0, 0, 0, 0.55)
    visible: opacity > 0
    opacity: showControls ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 200 } }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 4
        anchors.bottomMargin: 8
        spacing: 2

        // ── 进度条 ──
        SeekBar {
            Layout.fillWidth: true
            position: root.seekRatio
            leftText: formatTime(playerState.positionMs)
            rightText: formatTime(playerState.durationMs)
            onSeekFinished: (ratio) => root.seekFinished(ratio)
        }

        // ── 控制行 ──
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 18
            spacing: 8

            // 音量图标
            ControlButton {
                icon: playerState.volume <= 0.001 ? "\ue04f" : "\ue050"
                tooltip: "音量 " + Math.round(playerState.volume * 100)
                onClicked: root.volumeChanged(playerState.volume > 0.5 ? 0 : 1)
            }

            // 音量滑杆
            Slider {
                Layout.preferredWidth: 90
                from: 0
                to: 1
                value: playerState.volume
                onMoved: root.volumeChanged(value)
            }

            Item { Layout.preferredWidth: 8 }

            // 播放 / 暂停
            ControlButton {
                icon: playerState.paused ? "\ue037" : "\ue034"
                iconSize: 32
                tooltip: playerState.paused ? "播放" : "暂停"
                onClicked: root.playPauseClicked()
            }

            // 下一集
            ControlButton {
                icon: "\ue044"   // skip_next
                enabled: playerState.currentEpisodeIndex >= 0
                tooltip: "下一集"
                onClicked: root.nextEpisodeClicked()
            }

            Item { Layout.fillWidth: true }

            // 弹幕
            ControlButton {
                icon: playerState.danmakuEnabled ? "\ue0b9" : "\ue5c4"
                tooltip: "弹幕"
                onClicked: root.danmakuClicked()
            }

            // 字幕
            ControlButton {
                icon: "\ue048"   // subtitles
                badge: playerState.subtitleCount > 0
                       ? playerState.subtitleCount.toString() : ""
                tooltip: "字幕"
                onClicked: root.subtitleClicked()
            }

            // 音轨
            ControlButton {
                icon: "\ue3a1"   // audiotrack
                badge: playerState.audioCount > 0
                       ? playerState.audioCount.toString() : ""
                tooltip: "音轨"
                onClicked: root.audioClicked()
            }

            // 选集
            ControlButton {
                icon: "\ue063"   // playlist_play
                enabled: playerState.episodeCount > 1
                badge: playerState.episodeCount > 1
                       ? playerState.episodeCount.toString() : ""
                tooltip: "选集"
                onClicked: root.episodeClicked()
            }

            // 倍速
            ControlButton {
                icon: "\ue9e4"   // speed
                badge: playerState.speed.toFixed(1)
                tooltip: "播放速度"
                onClicked: root.speedClicked()
            }

            // 全屏
            ControlButton {
                icon: "\ue5d0"   // fullscreen
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
