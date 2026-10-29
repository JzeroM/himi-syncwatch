package com.himi.syncwatch.nativeplayer

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.os.Build
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowManager

/**
 * 全屏原生播放器宿主（计划书 §6.2）：持有 [Dialog] 与
 * [NativePlayerScreenView] 的生命周期，并把用户交互转成命令回传 Dart。
 *
 * 只做「宿主」职责：
 * - open/close 幂等（重复调用不会叠加多个 Dialog）；
 * - 状态推送由 Dart 驱动（[pushState]），此处不轮询 mpv；
 * - 退出语义与 Flutter 一致：BACK 键统一转 `requestBack`，由 Dart 决定
 *   是否关闭宿主并退出播放页。
 *
 * 线程模型：全部方法须在主线程调用（MethodChannel 回调即主线程）。
 */
class AndroidNativePlayerHost(
    private val activity: Activity,
    private val commandSink: CommandSink,
) {

    /** 视图交互 → Dart 命令（map 结构与 `NativePlayerCommand.fromMap` 对齐）。 */
    fun interface CommandSink {
        fun send(command: Map<String, Any?>)
    }

    private var dialog: Dialog? = null
    private var view: NativePlayerScreenView? = null

    /** 最近一次 Dart 推送的快照（新视图首次渲染直接复用）。 */
    private var lastState: AndroidNativePlayerState = AndroidNativePlayerState()
    private var lastStateAtMs: Long = 0L

    val isOpen: Boolean get() = dialog != null

    /** 打开全屏 Dialog（幂等）。 */
    fun open() {
        if (dialog != null) return
        val dlg = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        dlg.requestWindowFeature(Window.FEATURE_NO_TITLE)
        val playerView = NativePlayerScreenView(activity)
        playerView.setListener(object : NativePlayerScreenView.Listener {
            override fun onBack() {
                commandSink.send(mapOf("type" to "requestBack"))
            }

            override fun onTogglePlay() {
                commandSink.send(mapOf("type" to "togglePlay"))
            }

            override fun onSeek(positionMs: Long) {
                commandSink.send(mapOf("type" to "seekTo", "positionMs" to positionMs))
            }

            override fun onCycleSpeed() {
                commandSink.send(
                    mapOf("type" to "setSpeed", "speed" to nextSpeed(lastState.speed)),
                )
            }
        })
        playerView.render(lastState, lastStateAtMs)
        dlg.setContentView(playerView)
        dlg.setCanceledOnTouchOutside(false)
        dlg.setCancelable(true)
        dlg.setOnDismissListener { releaseView() }
        dlg.setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                commandSink.send(mapOf("type" to "requestBack"))
                true
            } else {
                false
            }
        }
        dlg.window?.apply {
            setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            decorView.systemUiVisibility = decorView.systemUiVisibility or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                attributes.layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
            decorView.setBackgroundColor(Color.BLACK)
        }
        dialog = dlg
        view = playerView
        dlg.show()
    }

    /** 关闭 Dialog 并释放 surface（幂等）。 */
    fun close() {
        val current = dialog ?: run {
            // 未打开也要保证视图引用被清掉（防止残留 JNI 引用）。
            releaseView()
            return
        }
        dialog = null
        try {
            current.setOnDismissListener(null)
            current.setOnKeyListener(null)
            current.dismiss()
        } catch (_: Throwable) {
            // Activity 已销毁等场景：忽略，避免崩溃。
        }
        releaseView()
    }

    /** 用 Dart 推送的 JSON 快照刷新视图；解析失败返回 false（不崩溃）。 */
    fun pushState(json: String): Boolean {
        val state = try {
            AndroidNativePlayerState.fromJson(org.json.JSONObject(json))
        } catch (_: Throwable) {
            return false
        }
        val at = System.currentTimeMillis()
        lastState = state
        lastStateAtMs = at
        view?.render(state, at)
        return true
    }

    /** Activity 销毁 / 引擎解绑时调用：关闭 Dialog 并释放 JNI surface 引用。 */
    fun release() {
        close()
    }

    /** 清空视图引用并释放 surface（只做一次，避免重复释放）。 */
    private fun releaseView() {
        val playerView = view
        view = null
        try {
            playerView?.release()
        } catch (_: Throwable) {
        }
    }

    private companion object {
        /** 倍速循环档位，与 Flutter 侧常用档位保持一致。 */
        val SPEED_STEPS = listOf(1.0, 1.25, 1.5, 2.0, 0.75)

        fun nextSpeed(current: Double): Double {
            val idx = SPEED_STEPS.indexOfFirst { Math.abs(it - current) < 0.01 }
            return SPEED_STEPS[(idx + 1).mod(SPEED_STEPS.size)]
        }
    }
}
