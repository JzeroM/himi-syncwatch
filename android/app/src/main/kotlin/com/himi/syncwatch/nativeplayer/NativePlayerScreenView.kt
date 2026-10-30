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
import android.widget.ScrollView
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
class NativePlayerScreenView(
    context: Context,
    /**
     * surface 实测尺寸提供者（诊断行 `size=WxH`）。双窗口方案里 surface
     * 已剥离到独立 surface 窗，控件层不再持有它，尺寸由宿主注入。
     */
    private val surfaceSizeProvider: () -> Pair<Int, Int> = { 0 to 0 },
) : FrameLayout(context) {

    /** 视图 → 宿主 → Dart 的交互回调。 */
    interface Listener {
        fun onBack()
        fun onTogglePlay()
        fun onSeek(positionMs: Long)
        fun onCycleSpeed()
        fun onSetSpeed(speed: Double)
        fun onSelectAudio(trackId: Int)
        fun onSelectSubtitle(trackId: Int)
        fun onSelectEpisode(index: Int)
        fun onSelectVersion(index: Int)
        fun onOpenPanel(panel: String)
        fun onClosePanel()
    }

    private val mainHandler = Handler(Looper.getMainLooper())

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
        // Phase 2：点开倍速面板（面板内选档）。
    }
    private val audioButton = TextView(context).apply {
        text = "音轨"
        setTextColor(0xCCFFFFFF.toInt())
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        setPadding(dp(8), dp(6), dp(8), dp(6))
        isClickable = true
        visibility = GONE
    }
    private val subtitleButton = TextView(context).apply {
        text = "字幕"
        setTextColor(0xCCFFFFFF.toInt())
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        setPadding(dp(8), dp(6), dp(8), dp(6))
        isClickable = true
        visibility = GONE
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

    /** 当前打开的二级面板（null = 无）。与鸿蒙 activePanel 同构。 */
    private var activePanel: String? = null

    /** 面板遮罩：全屏透明（点外关闭；Flutter 面板不带暗遮罩）。 */
    private val panelScrim = View(context).apply {
        setBackgroundColor(Color.TRANSPARENT)
        visibility = GONE
        setOnClickListener { closePanel() }
    }

    /**
     * 面板容器：右侧玻璃浮层（照抄 Flutter SelectorSidePanel——贴右 12、
     * 宽 320、上避顶栏 48、下避控制条 116、圆角 16、rim 边框）。
     *
     * Android 经典 View 跨窗口无法对 surface 真模糊，用「半透明着色 +
     * rim 边框 + 圆角」近似 GlassContainer（见 Phase 2 样式对齐说明）。
     */
    private val panelContainer = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        visibility = GONE
        // 圆角 16 + 着色 + rim 边框（GradientDrawable 近似玻璃卡片）。
        background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = dp(16).toFloat()
            setColor(PANEL_TINT)
            setStroke(dp(1), RIM_COLOR)
        }
        clipToOutline = true
        // 标题区留白：左 16 / 上 10 / 下 4（照抄 Flutter padding top:10 bottom:4）。
        setPadding(0, dp(10), 0, dp(4))
    }

    private val tickRunnable = object : Runnable {
        override fun run() {
            tick()
            mainHandler.postDelayed(this, TICK_MS)
        }
    }
    private val hideRunnable = Runnable { setControlsVisible(false) }

    init {
        // surface 已剥离到独立 surface 窗（双窗口方案，zOrderOnTop 不打洞），
        // 控件层只保留触控层 + 顶栏 + 底栏，全部画在透明的控件窗上，浮在
        // surface 窗之上。
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
        row.addView(
            audioButton,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        row.addView(
            subtitleButton,
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

        // 面板层（Phase 2）：透明遮罩 + 右侧玻璃浮层，浮于控件之上。
        addView(
            panelScrim,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        addView(
            panelContainer,
            LayoutParams(dp(PANEL_WIDTH_DP), LayoutParams.WRAP_CONTENT, Gravity.END or Gravity.TOP).apply {
                rightMargin = dp(12)
                topMargin = dp(48)
                bottomMargin = dp(116)
            },
        )

        // 底部条面板入口（倍速/音轨/字幕）。
        speedButton.setOnClickListener { openPanel(PANEL_SPEED) }
        audioButton.setOnClickListener { openPanel(PANEL_AUDIO) }
        subtitleButton.setOnClickListener { openPanel(PANEL_SUBTITLE) }

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

    // ── Phase 2 面板（与鸿蒙 NativePlayerPanel 同构）──────────────

    /** 打开面板（同类型再点为切换关闭）。 */
    private fun openPanel(panel: String) {
        activePanel = if (activePanel == panel) null else panel
        listener?.onOpenPanel(panel)
        renderPanel()
        scheduleAutoHide()
    }

    /** 关闭面板。 */
    fun closePanel() {
        if (activePanel == null) return
        activePanel = null
        listener?.onClosePanel()
        renderPanel()
    }

    /** 按 activePanel 重建面板内容；无面板则隐藏。 */
    private fun renderPanel() {
        val panel = activePanel
        if (panel == null) {
            panelScrim.visibility = GONE
            panelContainer.visibility = GONE
            return
        }
        panelScrim.visibility = VISIBLE
        panelContainer.visibility = VISIBLE
        panelContainer.removeAllViews()
        panelContainer.addView(panelHeader(panelTitle(panel)))
        when (panel) {
            PANEL_SPEED -> buildSpeedContent()
            PANEL_AUDIO -> buildTrackContent(
                lastState.tracks.filter { it.type == "audio" },
                lastState.selectedAudioId,
                allowOff = false,
            ) { listener?.onSelectAudio(it) }
            PANEL_SUBTITLE -> buildTrackContent(
                lastState.tracks.filter { it.type == "sub" },
                lastState.selectedSubtitleId,
                allowOff = true,
            ) { listener?.onSelectSubtitle(it) }
            PANEL_EPISODE -> buildListContent(
                lastState.episodes.map { it.displayLabel to it.index },
                lastState.currentEpisodeIndex,
            ) { listener?.onSelectEpisode(it) }
            PANEL_VERSION -> buildListContent(
                lastState.versions.map { it.displayLabel to it.index },
                lastState.currentVersionIndex,
            ) { listener?.onSelectVersion(it) }
        }
    }

    private fun panelTitle(panel: String): String = when (panel) {
        PANEL_SPEED -> "倍速"
        PANEL_AUDIO -> "音轨"
        PANEL_SUBTITLE -> "字幕"
        PANEL_EPISODE -> "选集"
        PANEL_VERSION -> "线路"
        else -> "设置"
    }

    /** 面板标题（照抄 Flutter：fontSize 15 加粗、左对齐、无关闭钮）。 */
    private fun panelHeader(title: String): View {
        return TextView(context).apply {
            text = title
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.START
            setPadding(dp(16), 0, dp(16), dp(4))
        }
    }

    /** 倍速：纵向列表（照抄 Flutter SpeedMenuPanel 的 ListView，非网格）。 */
    private fun buildSpeedContent() {
        val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        val state = lastState
        SPEED_STEPS.forEach { v ->
            val selected = Math.abs(state.speed - v) < 0.01
            list.addView(
                optionRow("${v}x", selected) {
                    listener?.onSetSpeed(v)
                    closePanel()
                },
            )
        }
        panelContainer.addView(wrapScroll(list), panelMatch())
    }

    /** 通用轨道列表（音轨/字幕）：首项可选「关闭」。 */
    private fun buildTrackContent(
        tracks: List<AndroidTrack>,
        selectedId: Int,
        allowOff: Boolean,
        onSelect: (Int) -> Unit,
    ) {
        val items = ArrayList<Pair<String, Pair<Int, Boolean>>>()
        if (allowOff) items.add("关闭" to (0 to (selectedId == 0)))
        tracks.forEach { items.add(it.displayLabel to (it.id to it.selected)) }
        val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        items.forEach { (label, meta) ->
            val (id, selected) = meta
            list.addView(
                optionRow(label, selected) {
                    onSelect(id)
                    closePanel()
                },
            )
        }
        panelContainer.addView(wrapScroll(list), panelMatch())
    }

    /** 通用「标签 + 选中标记」列表（选集/线路）。 */
    private fun buildListContent(
        items: List<Pair<String, Int>>,
        selectedIndex: Int,
        onSelect: (Int) -> Unit,
    ) {
        val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        items.forEach { (label, index) ->
            list.addView(
                optionRow(label, index == selectedIndex) {
                    onSelect(index)
                    closePanel()
                },
            )
        }
        panelContainer.addView(wrapScroll(list), panelMatch())
    }

    /**
     * 选项行（照抄 Flutter SideOptionRow）：文字左对齐、选中主色加粗、
     * 右侧对勾占 18px 槽位（未选中也占位，保证各行对齐）、padding h16 v12。
     */
    private fun optionRow(label: String, selected: Boolean, onTap: () -> Unit): View {
        return LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            isClickable = true
            setOnClickListener { onTap() }
            addView(
                TextView(context).apply {
                    text = label
                    setTextColor(if (selected) SEL_COLOR else Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    typeface = if (selected) android.graphics.Typeface.DEFAULT_BOLD
                    else android.graphics.Typeface.DEFAULT
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
            )
            // 未选中占空位，保证各行文字/对勾对齐（与 Flutter SizedBox(width:18) 一致）。
            addView(
                TextView(context).apply {
                    text = if (selected) "✓" else ""
                    setTextColor(SEL_COLOR)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                    gravity = Gravity.CENTER
                },
                LinearLayout.LayoutParams(dp(18), LinearLayout.LayoutParams.WRAP_CONTENT),
            )
        }
    }

    /** 面板内统一布局参数（限高 + 底部圆角留白）。 */
    private fun panelMatch(): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)

    private fun wrapScroll(content: View): View {
        val maxH = (resources.displayMetrics.heightPixels * 0.55).toInt()
        return ScrollView(context).apply {
            isFillViewport = true
            addView(content)
            minimumHeight = 0
        }.also { it.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, maxH) }
    }

    /** 渲染后同步入口：外部状态刷新时，若面板开着则重建（高亮跟随）。 */
    private fun refreshOpenPanel() {
        if (activePanel != null) renderPanel()
    }

    /** 释放 surface（JNI global ref）并停止内部定时器。 */
    fun release() {
        mainHandler.removeCallbacks(tickRunnable)
        mainHandler.removeCallbacks(hideRunnable)
        listener = null
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
        // 有音轨/字幕数据才显示入口（与鸿蒙按数据条件一致）。
        audioButton.visibility = if (state.tracks.any { it.type == "audio" }) VISIBLE else GONE
        subtitleButton.visibility = if (state.tracks.any { it.type == "sub" }) VISIBLE else GONE
        // 面板开着时，权威快照到达后重建（选中高亮跟随）。
        refreshOpenPanel()

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
        // surface 绑定是 Android 黑屏的第一现场：att + handle 必须可见
        // （原诊断只有「surface未附着」一个布尔，看不出绑的是哪个 handle）。
        parts.add("surface=${if (state.surfaceAttached) "att" else "未附着"}")
        state.surfaceId?.takeIf { it.isNotEmpty() }?.let { parts.add("handle=$it") }
        // surface 实测尺寸（宿主注入，来自独立 surface 窗）：punch-hole
        // 失效 / surfaceChanged 未到达时会是 0x0，与窗口不符即可判定为
        // 「画面没透出来」而不是解码问题。
        val (sw, sh) = surfaceSizeProvider()
        parts.add("size=${sw}x$sh")
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
        const val SEEK_STEPS = 1000
        const val TICK_MS = 500L
        const val AUTO_HIDE_MS = 4000L

        // ── Phase 2 面板类型（与鸿蒙 NativePlayerPanelType 同构）──
        const val PANEL_SPEED = "speed"
        const val PANEL_AUDIO = "audio"
        const val PANEL_SUBTITLE = "subtitle"
        const val PANEL_EPISODE = "episode"
        const val PANEL_VERSION = "version"
        val SPEED_STEPS = doubleArrayOf(0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0)

        // ── Flutter 风格对齐（照抄 glass_config / selector_side_panel）──
        /** 选中主色 Color(0xFF6366F1)。 */
        const val SEL_COLOR = 0xFF6366F1.toInt()
        /** 面板着色 GlassConfig.panelTint = 0x1F1A1D23。 */
        const val PANEL_TINT = 0x1F1A1D23.toInt()
        /** rim 边框近似色。 */
        const val RIM_COLOR = 0x33FFFFFF
        /** 面板宽（照抄 Flutter 侧 320）。 */
        const val PANEL_WIDTH_DP = 320
    }
}
