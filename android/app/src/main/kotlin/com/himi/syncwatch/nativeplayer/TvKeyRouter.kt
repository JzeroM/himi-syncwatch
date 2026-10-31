package com.himi.syncwatch.nativeplayer

import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup

/**
 * TV 遥控器按键路由（对齐 Flutter `PlayerHotkey` + `TvFocusable`）。
 *
 * 语义逐项照抄 `lib/screens/player/player_hotkey.dart`（唯一基准）：
 *
 * | 场景 | 按键 | 行为 |
 * |---|---|---|
 * | 任意 | 音量 ± | ±5%，长按连续（KeyRepeat） |
 * | 控件隐藏 | ← / → | seek ±10s |
 * | 控件隐藏 | ↑ / ↓ | 唤出控件 |
 * | 控件可见 | 方向键 | 交给焦点导航，仅顺延自动隐藏 |
 * | 进度条焦点 | ← / → | 单击 ±5s；长按每步 ±10s |
 * | 进度条焦点 | ↓ | 定向落到播放/暂停键（左侧组几何不可达） |
 * | 任意 | OK / Enter | 控件隐藏时只唤出控件（不触发播放） |
 * | 任意 | 媒体播放键 | 播放/暂停 + 唤出控件 |
 *
 * 与 Flutter 的差别只在实现手段：Flutter 用 `FocusNode.hasPrimaryFocus`
 * 判定焦点位置，这里用 `ViewGroup.findFocus()`。
 *
 * 方向键的**焦点遍历**本身由 Android 焦点系统完成（`makeFocusable` 已让
 * 所有控件可聚焦），本类只接管「全局语义」那一部分。
 */
internal class TvKeyRouter(
    private val rootProvider: () -> ViewGroup?,
    private val seekBarProvider: () -> View?,
    private val playPauseProvider: () -> View?,
    private val controlsVisibleProvider: () -> Boolean,
    private val onSeekRelative: (Long) -> Unit,
    private val onVolumeDelta: (Double) -> Unit,
    private val onTogglePlay: () -> Unit,
    private val onShowControls: () -> Unit,
    private val onExtendAutoHide: () -> Unit,
) {

    /**
     * 处理一次按键。
     *
     * @return true = 已消费（调用方不再走默认焦点遍历）。
     */
    fun handleKey(keyCode: Int, event: KeyEvent): Boolean {
        // 只在按下与重复时处理；抬起放行（与 Flutter `isDown || isRepeat` 一致）。
        val isDown = event.action == KeyEvent.ACTION_DOWN
        val isRepeat = event.action == KeyEvent.ACTION_MULTIPLE ||
            (isDown && event.repeatCount > 0)
        if (!isDown && event.action != KeyEvent.ACTION_MULTIPLE) return false

        // ── 音量键：任意时刻生效，长按连续 ────────────────────────
        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                onVolumeDelta(SEEK_VOLUME_STEP)
                return true
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                onVolumeDelta(-SEEK_VOLUME_STEP)
                return true
            }
        }

        // ── 媒体键（遥控器专用播放/暂停）────────────────────────
        when (keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PAUSE,
            -> {
                if (!isDown) return true
                onTogglePlay()
                onShowControls()
                return true
            }
        }

        // ── 进度条焦点：左右键接管为快进退 ──────────────────────
        val seekBar = seekBarProvider()
        val focused = rootProvider()?.findFocus()
        if (seekBar != null && focused === seekBar) {
            when (keyCode) {
                KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT -> {
                    val dir = if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT) -1 else 1
                    // 单击 ±5s；长按每步 ±10s（Flutter `isRepeat ? 10000 : 5000`）。
                    val stepMs = if (isRepeat) REPEAT_SEEK_MS else SINGLE_SEEK_MS
                    onSeekRelative(dir * stepMs)
                    onShowControls()
                    return true
                }
                KeyEvent.KEYCODE_DPAD_DOWN -> {
                    // 左侧组（播放键）几何不可达，定向跳焦。
                    playPauseProvider()?.let {
                        it.requestFocus()
                        onShowControls()
                    }
                    return true
                }
            }
        }

        // ── OK / Enter：控件隐藏时只唤出控件 ────────────────────
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER,
            KeyEvent.KEYCODE_BUTTON_SELECT,
            -> {
                if (!controlsVisibleProvider()) {
                    onShowControls()
                    return true
                }
                // 控件可见：放行走焦点遍历（触发被聚焦控件的点击）。
                return false
            }
        }

        // ── 方向键 ────────────────────────────────────────────
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_UP,
            KeyEvent.KEYCODE_DPAD_DOWN,
            -> {
                if (!controlsVisibleProvider()) {
                    // 控件隐藏：左右 seek ±10s、上下唤出控件。
                    if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT) {
                        onSeekRelative(-HIDDEN_SEEK_MS)
                        return true
                    }
                    if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) {
                        onSeekRelative(HIDDEN_SEEK_MS)
                        return true
                    }
                    onShowControls()
                    return true
                }
                // 控件可见：交给焦点导航，仅顺延自动隐藏。
                onExtendAutoHide()
                return false
            }
        }

        return false
    }

    companion object {
        /** 控件隐藏时方向键 seek 步长（Flutter `_seekStepMs` = 10s）。 */
        const val HIDDEN_SEEK_MS = 10_000L
        /** 进度条焦点单击 seek 步长（Flutter `5000`）。 */
        const val SINGLE_SEEK_MS = 5_000L
        /** 进度条焦点长按每步 seek（Flutter `10000`）。 */
        const val REPEAT_SEEK_MS = 10_000L
        /** 音量步长（Flutter `_volumeStep` = 5%）。 */
        const val SEEK_VOLUME_STEP = 5.0
    }
}
