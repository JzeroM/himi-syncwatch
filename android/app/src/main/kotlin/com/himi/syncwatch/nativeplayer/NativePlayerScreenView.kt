package com.himi.syncwatch.nativeplayer

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView

/**
 * 原生播放器最小壳（计划书 Phase 1 / §6.5）：
 * SurfaceView 渲染 mpv 直出，上方叠加触控层 + 顶栏 + 底栏。
 *
 * 【为什么用经典 View 而不是 Compose】
 * 计划书原定 Compose，但 Compose 需要额外引入 compose-bom / compiler
 * 插件，本仓库本机与 CI 都没有可验证的构建回路；经典 View 零新增依赖、
 * 与现有 AGP/Kotlin 配置完全兼容，且能在本机用 android.jar 编译校验。
 * 功能面与 Compose 版一致（Dart 仍是唯一权威状态源），后续如需复杂面板
 * 可在同一套 [Listener] 契约下替换实现，不影响 Dart 协议。
 *
 * 线程模型：所有公开方法都在主线程调用（Dart 平台通道回调即在主线程），
 * 内部定时器也走主线程 Handler，不做跨线程加锁。
 */
@SuppressLint("ViewConstructor")
class NativePlayerScreenView(context: Context) : FrameLayout(context) {

    /** 视图 → 宿主 → Dart 的交互回调。 */
    interface Listener {
        fun onBack()
        fun onTogglePlay()
        fun onSeek(positionMs: Long)
        fun onCycleSpeed()
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val surface = com.himi.mpv.android.HimiMpvSurfaceView(
        context,
        SURFACE_VIEW_ID,
        // Dialog 是独立窗口，media overlay 反而会被 Flutter 窗口表面盖住。
        false,
    )

    private val tapLayer = View(context).apply {
        isClickable = true
        setBackgroundColor(Color.TRANSPARENT)
        setOnClickListener { setControlsVisible(!controlsVisible) }
    }

    private val topBar = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(8), dp(12), dp(8))
        setBackgroundColor(0x66000000)
    }
    private val backButton = TextView(context).apply {
        text = "‹ 返回"
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
        setPadding(dp(8), dp(6), dp(12), dp(6))
        isClickable = true
        setOnClickListener { listener?.onBack() }
    }
    private val titleText = TextView(context).apply {
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
        setPadding(dp(8), 0, dp(8), 0)
    }
    private val clockText = TextView(context).apply {
        setTextColor(0xCCFFFFFF.toInt())
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
    }

    private val bottomBar = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(12), dp(6), dp(12), dp(10))
        setBackgroundColor(0x66000000)
    }
    private val row = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
    }
    private val playPauseButton = TextView(context).apply {
        text = "▶"
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
        setPadding(dp(12), dp(6), dp(12), dp(6))
        isClickable = true
        setOnClickListener {
            listener?.onTogglePlay()
            scheduleAutoHide()
        }
    }
    private val seekBar = SeekBar(context).apply {
        max = SEEK_STEPS
        progress = 0
        isEnabled = false
    }
    private val timeText = TextView(context).apply {
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        setPadding(dp(8), 0, dp(8), 0)
        text = "0:00 / 0:00"
    }
    private val speedButton = TextView(context).apply {
        text = "1.0x"
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        setPadding(dp(12), dp(6), dp(12), dp(6))
        isClickable = true
        setOnClickListener {
            listener?.onCycleSpeed()
            scheduleAutoHide()
        }
    }
    private val hdrBadge = TextView(context).apply {
        text = "HDR"
        setTextColor(Color.BLACK)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        setBackgroundColor(0xFFFFD54F.toInt())
        setPadding(dp(6), dp(2), dp(6), dp(2))
        visibility = GONE
    }
    private val diagText = TextView(context).apply {
        setTextColor(0x99FFFFFF.toInt())
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
        maxLines = 2
        setPadding(0, dp(4), 0, 0)
        visibility = GONE
    }

    private var listener: Listener? = null
    private var controlsVisible = true
    private var hideDeadlineMs = 0L
    private var dragging = false
    private var lastState: AndroidNativePlayerState = AndroidNativePlayerState()
    private var lastStateAtMs: Long = 0L

    private val tickRunnable = object : Runnable {
        override fun run() {
            tick()
            mainHandler.postDelayed(this, TICK_MS)
        }
    }
    private val hideRunnable = Runnable { setControlsVisible(false) }

    init {
        addView(
            surface,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        addView(
            tapLayer,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )

        topBar.addView(
            backButton,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        topBar.addView(
            titleText,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )
        topBar.addView(
            clockText,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        row.addView(
            playPauseButton,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        row.addView(
            seekBar,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )
        row.addView(
            timeText,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        row.addView(
            hdrBadge,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).also { it.marginStart = dp(6) },
        )
        row.addView(
            speedButton,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        bottomBar.addView(
            row,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        bottomBar.addView(
            diagText,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        addView(
            topBar,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.TOP),
        )
        addView(
            bottomBar,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM),
        )

        seekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                dragging = true
                val target = progressToMs(progress, lastState.durationMs)
                timeText.text = "${AndroidNativePlayerState.formatTime(target)} / " +
                    AndroidNativePlayerState.formatTime(lastState.durationMs.toLong())
                scheduleAutoHide()
            }

            override fun onStartTrackingTouch(bar: SeekBar) {
                dragging = true
            }

            override fun onStopTrackingTouch(bar: SeekBar) {
                dragging = false
                listener?.onSeek(progressToMs(bar.progress, lastState.durationMs))
                scheduleAutoHide()
            }
        })

        setControlsVisible(true)
        mainHandler.postDelayed(tickRunnable, TICK_MS)
    }

    fun setListener(listener: Listener?) {
        this.listener = listener
    }

    /** 释放 surface（JNI global ref）并停止内部定时器。 */
    fun release() {
        mainHandler.removeCallbacks(tickRunnable)
        mainHandler.removeCallbacks(hideRunnable)
        listener = null
        surface.dispose()
    }

    /** 用 Dart 推送的权威快照覆盖本地状态并刷新控件。 */
    fun render(state: AndroidNativePlayerState, snapshotAtMs: Long = System.currentTimeMillis()) {
        lastState = state
        lastStateAtMs = snapshotAtMs
        applyState()
    }

    private fun applyState() {
        val state = lastState
        val now = System.currentTimeMillis()
        titleText.text = state.displayTitle
        playPauseButton.text = if (state.paused) "▶" else "⏸"
        speedButton.text = trimSpeed(state.speed)
        hdrBadge.visibility = if (state.hdrOutput) VISIBLE else GONE

        if (!dragging) {
            val pos = state.positionAt(now, lastStateAtMs)
            val progress = if (state.durationMs > 0) {
                ((pos * SEEK_STEPS) / state.durationMs).toInt().coerceIn(0, SEEK_STEPS)
            } else {
                0
            }
            seekBar.progress = progress
            timeText.text = "${AndroidNativePlayerState.formatTime(pos)} / " +
                AndroidNativePlayerState.formatTime(state.durationMs.toLong())
        }
        // 直播/时长未知时禁止拖动（与 Flutter 侧一致：时长未知不显示进度）。
        seekBar.isEnabled = !state.isLiveLike

        val diag = buildDiag(state)
        diagText.text = diag
        diagText.visibility = if (diag.isEmpty()) GONE else VISIBLE
    }

    private fun buildDiag(state: AndroidNativePlayerState): String {
        val parts = mutableListOf<String>()
        parts.add("vo=${state.currentVo ?: state.voConfigured ?: "-"}")
        parts.add("hwdec=${state.hwdecCurrent ?: "-"}")
        if (!state.surfaceAttached) parts.add("surface未附着")
        state.surfaceError?.let { parts.add("err=$it") }
        if (state.buffering) parts.add("缓冲中")
        parts.addAll(state.debugLines)
        return parts.joinToString(" · ")
    }

    private fun tick() {
        clockText.text = currentClock()
        if (controlsVisible && !lastState.paused && System.currentTimeMillis() > hideDeadlineMs) {
            setControlsVisible(false)
            return
        }
        if (!dragging) applyState()
    }

    private fun setControlsVisible(visible: Boolean) {
        controlsVisible = visible
        topBar.visibility = if (visible) VISIBLE else GONE
        bottomBar.visibility = if (visible) VISIBLE else GONE
        if (visible) scheduleAutoHide()
    }

    private fun scheduleAutoHide() {
        hideDeadlineMs = System.currentTimeMillis() + AUTO_HIDE_MS
        mainHandler.removeCallbacks(hideRunnable)
        // 暂停时保持控件常显，避免"暂停却看不到进度"。
        if (!lastState.paused) mainHandler.postDelayed(hideRunnable, AUTO_HIDE_MS)
    }

    private fun currentClock(): String {
        val cal = java.util.Calendar.getInstance()
        return String.format(
            java.util.Locale.US,
            "%02d:%02d",
            cal.get(java.util.Calendar.HOUR_OF_DAY),
            cal.get(java.util.Calendar.MINUTE),
        )
    }

    private fun trimSpeed(speed: Double): String {
        val rounded = Math.round(speed * 10.0) / 10.0
        return "${rounded}x"
    }

    private fun progressToMs(progress: Int, durationMs: Int): Long {
        if (durationMs <= 0) return 0
        return (progress.toLong() * durationMs) / SEEK_STEPS
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private companion object {
        const val SURFACE_VIEW_ID = -1
        const val SEEK_STEPS = 1000
        const val TICK_MS = 500L
        const val AUTO_HIDE_MS = 4000L
    }
}
