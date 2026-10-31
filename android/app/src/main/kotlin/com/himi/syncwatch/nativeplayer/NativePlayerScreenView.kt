package com.himi.syncwatch.nativeplayer

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ClipDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView

/**
 * 原生播放器控制层（Phase 2.5）：照 Flutter 播放页（手机横屏 / TV）重画。
 *
 * 结构（自下而上）：
 *  - tapLayer   全屏点按：显隐控件（面板/浮层打开时先关浮层）
 *  - topBar     手机：返回/标题/网速 倍速 内核胶囊 字幕样式 解码 画面比例 转屏
 *               TV  ：返回/标题/网速 内核胶囊 时钟
 *  - bottomBar  Logo(240x44) / 进度条(track6 thumb8, 两侧时间数显) /
 *               播放组(28-36-28，手机精确居中) / 右侧图标(24 间距20) + 角标
 *  - lockOnly   手机锁定态：仅锁钮（与进度条左数显同列）
 *  - panelLayer 二级面板（右侧玻璃浮层 / 解码 popover / 片头片尾居中卡）
 *
 * 视觉常量来自 [NPTheme]（与 Dart `NativePlayerTheme` 同值），图标码点来自
 * [NativePlayerIcons]（与 `tool/native_icons.json` 同源，字体内置 assets）。
 *
 * 线程模型：主线程。状态由 Dart 推送（[render]），交互经 [Listener]
 * 回传命令；Dart 是唯一权威状态源。
 */
@SuppressLint("ViewConstructor")
class NativePlayerScreenView(
    ctx: Context,
    /** surface 实测尺寸提供者（诊断行 `size=WxH`）。 */
    private val surfaceSizeProvider: () -> Pair<Int, Int> = { 0 to 0 },
    /** surface 窗口提供者（液态玻璃 PixelCopy 采样源；null = 降级 tint）。 */
    private val surfaceWindowProvider: () -> android.view.Window? = { null },
) : FrameLayout(ctx) {

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
        fun onSwitchEngine(engine: String)
        fun onSetDecodeMode(mode: String)
        fun onToggleDanmaku()
        fun onCycleVideoFit()
        fun onToggleOrientation()
        fun onToggleLock()
        fun onAdjustDisplay(key: String, value: Double)
        fun onSetSegmentMark(kind: String, positionMs: Long)
        fun onClearSegmentMark(kind: String)
        fun onOpenPanel(panel: String)
        fun onClosePanel()
    }

    // ── 状态 ──────────────────────────────────────────────────────

    private var listener: Listener? = null
    private var controlsVisible = true
    private var hideDeadlineMs = 0L
    private var dragging = false
    private var lastState: AndroidNativePlayerState = AndroidNativePlayerState()
    private var lastStateAtMs: Long = 0L
    private var lastTvMode = false

    /** 当前打开的二级面板（null = 无）。 */
    private var activePanel: String? = null

    /** 解码 popover 是否展开（与右侧面板互斥；仅手机）。 */
    private var decodePopoverOpen = false

    /** 片头片尾卡片的二次确认上下文（null = 非确认态）。 */
    private var segmentConfirmKind: String? = null

    /** 片头片尾卡片是否显示（与确认态解耦：卡片可无确认态显示）。 */
    private var segmentCardOpen = false

    private val mainHandler = Handler(Looper.getMainLooper())

    private val tickRunnable = object : Runnable {
        override fun run() {
            tick()
            mainHandler.postDelayed(this, TICK_MS)
        }
    }
    private val hideRunnable = Runnable { setControlsVisible(false) }

    // ── 工具 ──────────────────────────────────────────────────────

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density + 0.5f).toInt()

    private fun lp(width: Int, height: Int): LayoutParams =
        LayoutParams(width, height)

    private fun lp(width: Int, height: Int, gravity: Int): LayoutParams =
        LayoutParams(width, height, gravity)

    /**
     * LinearLayout 子项布局。注意：lp() 造的是 FrameLayout.LayoutParams，
     * 加进 LinearLayout 会被 generateLayoutParams 重造、**margin 丢失**——
     * 间距类布局必须用本函数。
     */
    private fun llp(width: Int, height: Int, startMarginDp: Int = 0): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(width, height).also {
            if (startMarginDp != 0) it.marginStart = dp(startMarginDp)
        }

    /** Material Icons 图标视图：内置字体内取字形，支持着色/尺寸。 */
    private fun iconView(codePoint: Int, sizeSp: Float, color: Int = Color.WHITE): TextView =
        TextView(context).apply {
            text = String(Character.toChars(codePoint))
            typeface = NativePlayerIcons.typeface(context)
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
            gravity = Gravity.CENTER
            includeFontPadding = false
        }

    /**
     * 按下反馈：Flutter 的 TvFocusable/IconButton 自带 ripple/高亮，原生
     * TextView 按钮默认无任何视觉反馈——真机表现为「点了没反应」。
     * 这里用 alpha + 轻微缩放模拟按下态（ACTION_DOWN/UP/CANCEL）。
     */
    private fun applyPressFeedback(view: View) {
        view.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    v.animate().alpha(0.55f).scaleX(0.92f).scaleY(0.92f)
                        .setDuration(90).start()
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    v.animate().alpha(1f).scaleX(1f).scaleY(1f)
                        .setDuration(120).start()
                }
            }
            false // 不消费事件，click 照常触发
        }
    }

    /** 玻璃胶囊/浮层背景：着色 + rim 描边 + 圆角（跨窗口无法真模糊）。 */
    private fun glassBackground(radiusDp: Int, tint: Int = NPTheme.PANEL_TINT): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(radiusDp).toFloat()
            setColor(tint)
            setStroke(dp(1), NPTheme.RIM)
        }

    /**
     * 顶栏芯片玻璃底（Flutter player_top_bar._decodeChipDecoration）：
     * 白 22%→10% 竖向渐变 + 白 24% 描边；面板打开态强调色描边 + 光晕。
     */
    private fun chipBackground(open: Boolean): GradientDrawable =
        GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(0x38FFFFFF, 0x1AFFFFFF),
        ).apply {
            gradientType = GradientDrawable.LINEAR_GRADIENT
            cornerRadius = dp(NPTheme.RADIUS_CHIP).toFloat()
            setStroke(dp(if (open) 2 else 1), if (open) NPTheme.ACCENT else NPTheme.WHITE_24)
        }

    /** 顶栏/底栏渐变：底部透明 → 顶部 80% 黑（顶栏），反之（底栏）。 */
    private fun barGradient(topSolid: Boolean): GradientDrawable =
        GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            if (topSolid) {
                intArrayOf(NPTheme.BAR_GRADIENT_SOLID, NPTheme.BAR_GRADIENT_CLEAR)
            } else {
                intArrayOf(NPTheme.BAR_GRADIENT_CLEAR, NPTheme.BAR_GRADIENT_SOLID)
            },
        ).apply { gradientType = GradientDrawable.LINEAR_GRADIENT }

    fun setListener(listener: Listener?) {
        this.listener = listener
    }

    // ── 视图 ──────────────────────────────────────────────────────

    private val tapLayer = View(context).apply {
        isClickable = true
        setBackgroundColor(Color.TRANSPARENT)
        setOnClickListener {
            if (activePanel != null) {
                closePanel()
                return@setOnClickListener
            }
            if (decodePopoverOpen || segmentCardOpen) {
                decodePopoverOpen = false
                segmentCardOpen = false
                segmentConfirmKind = null
                renderOverlays()
                return@setOnClickListener
            }
            setControlsVisible(!controlsVisible)
        }
    }

    // 顶栏（GradientDrawable 渐变铺底，内容 Row 在其上）
    private val topBar = LinearLayout(context)
    private val backButton = TextView(context)
    private val titleText = TextView(context)
    private val networkText = TextView(context)
    private val speedChip = LinearLayout(context)
    private val speedLabel = TextView(context)
    private val kernelChip = TextView(context)
    private val subtitleStyleChip = TextView(context)
    private val decodeChip = TextView(context)
    private val videoFitIcon = TextView(context)
    private val rotateIcon = TextView(context)
    /** 顶栏右侧簇（网速~转屏）：小屏整组等比缩（自适应不出屏）。 */
    private val topTail = LinearLayout(context)
    private val clockWrap = FrameLayout(context)
    private val clockText = TextView(context)

    // 底栏
    private val bottomBar = LinearLayout(context)
    private val logoImage = ImageView(context)
    private val logoSpacer = View(context)
    private val seekRow = LinearLayout(context)
    private val positionLabel = TextView(context)
    private val seekBar = SeekBar(context)
    private val durationLabel = TextView(context)
    private val buttonRow = FrameLayout(context)
    private val transportGroup = LinearLayout(context)
    private val prevButton = TextView(context)
    private val playPauseButton = TextView(context)
    private val nextButton = TextView(context)
    private val leadingGroup = LinearLayout(context)
    private val lockButton = TextView(context)
    private val trailingGroup = LinearLayout(context)
    private val bottomSpeedChip = LinearLayout(context)
    private val bottomSpeedLabel = TextView(context)
    private val panelToggleButton = TextView(context)
    private var displayAdjustButton: TextView? = null
    private val danmakuButton = TextView(context)
    private var versionButton: View? = null
    private var subtitleButton: View? = null
    private var audioButton: View? = null
    private var episodeButton: View? = null
    private val diagText = TextView(context)
    private val bufferingView = ProgressBar(context)
    private val hdrBadge = TextView(context)

    // 面板层
    private val danmakuLayer = DanmakuLayerView(context)

    // 注意：.apply 只能接在 View 声明后面——接在 Runnable 的 object 表达式
    // 后面会被 Kotlin 解析到外层 this（整个控件层根视图），把根视图设成
    // GONE → 控件全消失（真机回归「只有画面没控件」）。
    private val panelScrim = View(context).apply {
        setBackgroundColor(Color.TRANSPARENT)
        visibility = GONE
        setOnClickListener { closePanel() }
    }

    /**
     * 液态玻璃背景（方案 A：PixelCopy 采样视频帧 + 软模糊 + 折射带）。
     * 创建失败/未开启玻璃时为 null → 走 tint 兜底，绝不影响出画（黑屏红线）。
     */
    private val glassPanel = GlassBackdropDrawable.createOrNull(
        surfaceWindowProvider,
        dp(NPTheme.RADIUS_PANEL).toFloat(),
    )
    private val glassCard = GlassBackdropDrawable.createOrNull(
        surfaceWindowProvider,
        dp(NPTheme.RADIUS_CARD).toFloat(),
    )

    /** 面板打开期间的采样节拍（4fps；关闭即停，零开销）。 */
    private val glassSampleRunnable = object : Runnable {
        override fun run() {
            glassPanel?.sampleAsync()
            glassCard?.sampleAsync()
            mainHandler.postDelayed(this, GlassBackdropDrawable.SAMPLE_INTERVAL_MS)
        }
    }
    private val panelContainer = LinearLayout(context)
    private val decodePopover = LinearLayout(context)
    private val segmentCard = LinearLayout(context)
    private val segmentScrim = View(context).apply {
        setBackgroundColor(Color.TRANSPARENT)
        visibility = GONE
        setOnClickListener {
            segmentCardOpen = false
            segmentConfirmKind = null
            renderOverlays()
        }
    }

    // ── 视图装配 ──────────────────────────────────────────────────

    /** 组装层级：tapLayer → topBar → bottomBar → 面板层。 */
    private fun buildHierarchy() {
        addView(
            tapLayer,
            lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        // 弹幕层：视频之上、控件之下（与 Flutter DanmakuOverlay 位置一致）。
        addView(danmakuLayer, lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        addView(topBar, lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.TOP))
        addView(bottomBar, lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))

        // 缓冲指示：居中细灰圆环转圈（与 Flutter CircularProgressIndicator 一致）。
        bufferingView.apply {
            isIndeterminate = true
            indeterminateTintList = ColorStateList.valueOf(NPTheme.WHITE_70)
            visibility = GONE
        }
        addView(bufferingView, lp(dp(36), dp(36), Gravity.CENTER))

        // 面板层（二级浮层）：透明遮罩 + 右侧玻璃浮层 + 解码 popover + 片头片尾卡。
        addView(panelScrim, lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(
            panelContainer,
            lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.END or Gravity.TOP),
        )
        addView(
            decodePopover,
            lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.END or Gravity.TOP),
        )
        addView(segmentScrim, lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(segmentCard, lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER))

        configureTopBar()
        configureBottomBar()
        configureOverlays()
    }

    /** 顶栏：返回 / 标题 / 网速 /（手机）倍速·内核·字幕样式·解码·画面比例·转屏 /（TV）时钟。 */
    private fun configureTopBar() {
        // 幂等：重排（手机↔TV）会二次进入本函数，必须先清空容器，
        // 否则对已有 parent 的子视图重复 addView 会抛 IllegalStateException。
        topBar.removeAllViews()
        clockWrap.removeAllViews()
        topBar.orientation = LinearLayout.HORIZONTAL
        topBar.gravity = Gravity.CENTER_VERTICAL
        topBar.setPadding(dp(12), dp(6), dp(12), dp(6))
        topBar.background = barGradient(topSolid = true)

        backButton.text = String(Character.toChars(NativePlayerIcons.ICON_ARROW_BACK))
        backButton.typeface = NativePlayerIcons.typeface(context)
        backButton.setTextColor(Color.WHITE)
        backButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        backButton.gravity = Gravity.CENTER
        backButton.includeFontPadding = false
        backButton.setPadding(dp(6), dp(6), dp(6), dp(6))
        backButton.isClickable = true
        backButton.setOnClickListener { listener?.onBack() }
        applyPressFeedback(backButton)
        topBar.addView(backButton, lp(dp(40), dp(40)))

        titleText.setTextColor(Color.WHITE)
        titleText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        titleText.maxLines = 1
        titleText.ellipsize = TextUtils.TruncateAt.END
        titleText.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        topBar.addView(
            titleText,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                .also { it.marginStart = dp(4); it.marginEnd = dp(8) },
        )

        // 右侧簇容器（网速~转屏）：小屏整组等比缩（自适应不出屏）。
        topTail.orientation = LinearLayout.HORIZONTAL
        topTail.gravity = Gravity.CENTER_VERTICAL
        // 网速（12sp white70）
        networkText.setTextColor(NPTheme.WHITE_70)
        networkText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        networkText.gravity = Gravity.CENTER_VERTICAL
        networkText.visibility = GONE
        topTail.addView(networkText, llp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(40), 8))

        // 倍速（手机，网速右侧）：Flutter 为纯图标+文字（无胶囊底），
        // icon 20 + label 12 white70，padding h4 v4。
        speedChip.orientation = LinearLayout.HORIZONTAL
        speedChip.gravity = Gravity.CENTER
        speedChip.setPadding(dp(4), dp(4), dp(4), dp(4))
        speedChip.isClickable = true
        speedChip.setOnClickListener { listener?.onCycleSpeed() }
        speedChip.addView(iconView(NativePlayerIcons.ICON_SPEED, 20f), lp(dp(20), dp(20)))
        speedLabel.setTextColor(NPTheme.WHITE_70)
        speedLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        speedChip.addView(
            speedLabel,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .also { it.marginStart = dp(4) },
        )
        topTail.addView(speedChip, llp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32), 8))

        // 内核胶囊（显示短名，点击打开右侧内核面板）
        kernelChip.setTextColor(Color.WHITE)
        kernelChip.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        kernelChip.gravity = Gravity.CENTER
        kernelChip.setPadding(dp(9), dp(6), dp(9), dp(6))
        kernelChip.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        kernelChip.background = chipBackground(false)
        kernelChip.isClickable = true
        kernelChip.setOnClickListener { openPanel(PANEL_KERNEL) }
        topTail.addView(kernelChip, llp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(34), 8))

        // 字幕样式胶囊（tune 图标，点击打开右侧显示调节面板）
        configureIconChip(subtitleStyleChip, NativePlayerIcons.ICON_TUNE)
        subtitleStyleChip.setOnClickListener { openPanel(PANEL_DISPLAY) }
        topTail.addView(subtitleStyleChip, llp(dp(30), dp(30), 8))

        // 解码胶囊（memory 图标，点击打开右侧解码模式面板）
        configureIconChip(decodeChip, NativePlayerIcons.ICON_MEMORY)
        decodeChip.setOnClickListener { openPanel(PANEL_DECODE) }
        topTail.addView(decodeChip, llp(dp(30), dp(30), 8))

        // 画面比例（循环切换）
        videoFitIcon.typeface = NativePlayerIcons.typeface(context)
        videoFitIcon.setTextColor(Color.WHITE)
        videoFitIcon.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        videoFitIcon.gravity = Gravity.CENTER
        videoFitIcon.includeFontPadding = false
        videoFitIcon.setPadding(dp(6), dp(6), dp(6), dp(6))
        videoFitIcon.isClickable = true
        videoFitIcon.setOnClickListener { listener?.onCycleVideoFit() }
        applyPressFeedback(videoFitIcon)
        topTail.addView(videoFitIcon, llp(dp(34), dp(34), 8))

        // 手动转屏（仅手机）
        rotateIcon.text = String(Character.toChars(NativePlayerIcons.ICON_ROTATE))
        rotateIcon.typeface = NativePlayerIcons.typeface(context)
        rotateIcon.setTextColor(Color.WHITE)
        rotateIcon.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        rotateIcon.gravity = Gravity.CENTER
        rotateIcon.includeFontPadding = false
        rotateIcon.setPadding(dp(6), dp(6), dp(6), dp(6))
        rotateIcon.isClickable = true
        rotateIcon.setOnClickListener { listener?.onToggleOrientation() }
        applyPressFeedback(rotateIcon)
        topTail.addView(rotateIcon, llp(dp(34), dp(34), 8))

        topBar.addView(topTail, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ))

        // 时钟（TV：右贴边，100×48，13sp white70）
        clockText.setTextColor(NPTheme.WHITE_70)
        clockText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        clockText.gravity = Gravity.CENTER
        clockText.visibility = GONE
        clockWrap.addView(clockText, lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    /** 顶栏玻璃图标胶囊（内核/字幕样式/解码共用）。 */
    private fun configureIconChip(chip: TextView, codePoint: Int) {
        chip.text = String(Character.toChars(codePoint))
        chip.typeface = NativePlayerIcons.typeface(context)
        chip.setTextColor(Color.WHITE)
        chip.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
        chip.gravity = Gravity.CENTER
        chip.setPadding(dp(6), dp(6), dp(6), dp(6))
        chip.background = chipBackground(false)
        chip.isClickable = true
    }

    // ── 交互绑定（可重入：手机 ↔ TV 切换时重建布局后重绑）──────────

    /**
     * 进度条样式（与 Flutter glass slider / NativePlayerTheme 对齐）：
     * 6dp 圆角轨（未播 WHITE_24 / 已播 ACCENT）+ 8dp 半径 ACCENT 圆点拇指，
     * 拇指外套 ACCENT_SOFT 光晕环。系统默认 SeekBar 是粗灰条，观感差异极大。
     */
    private fun applySeekBarStyle() {
        val trackH = dp(NPTheme.SEEK_TRACK)
        val thumbD = dp(NPTheme.SEEK_THUMB * 2)
        val glowD = thumbD + dp(8)
        val bg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = trackH / 2f
            setColor(NPTheme.WHITE_24)
        }
        val fg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = trackH / 2f
            setColor(NPTheme.ACCENT)
        }
        val track = LayerDrawable(
            arrayOf<Drawable>(bg, ClipDrawable(fg, Gravity.START, ClipDrawable.HORIZONTAL)),
        )
        track.setId(0, android.R.id.background)
        track.setId(1, android.R.id.progress)
        val inset = (glowD - trackH) / 2
        for (i in 0..1) {
            track.setLayerInsetTop(i, inset)
            track.setLayerInsetBottom(i, inset)
        }
        val glow = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(NPTheme.ACCENT_SOFT)
            setSize(glowD, glowD)
        }
        val core = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(NPTheme.ACCENT)
            setSize(thumbD, thumbD)
        }
        val pad = (glowD - thumbD) / 2
        val thumb = LayerDrawable(arrayOf<Drawable>(glow, core))
        thumb.setLayerInset(1, pad, pad, pad, pad)
        seekBar.progressDrawable = track
        seekBar.thumb = thumb
        seekBar.splitTrack = false
    }

    /** 进度条：拖动预览时间数显、松手回传 seek。 */
    private fun configureSeekListeners() {
        seekBar.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(bar: SeekBar, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                dragging = true
                val target = progressToMs(progress, lastState.durationMs)
                positionLabel.text = AndroidNativePlayerState.formatPlayerTime(target)
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
        // TV 长按进度条 → 片头片尾标记卡片（与 Flutter onLongPress 一致）。
        seekBar.setOnLongClickListener {
            if (lastState.segmentEnabled && lastState.tvMode) {
                segmentCardOpen = true
                segmentConfirmKind = null
                renderOverlays()
                true
            } else {
                false
            }
        }
    }

    /** 播放组：上一集 / 播放暂停 / 下一集。 */
    private fun configureTransportListeners() {
        prevButton.setOnClickListener {
            if (lastState.currentEpisodeIndex > 0) {
                listener?.onSelectEpisode(lastState.currentEpisodeIndex - 1)
            }
            scheduleAutoHide()
        }
        playPauseButton.setOnClickListener {
            listener?.onTogglePlay()
            scheduleAutoHide()
        }
        nextButton.setOnClickListener {
            if (lastState.currentEpisodeIndex < lastState.episodes.size - 1) {
                listener?.onSelectEpisode(lastState.currentEpisodeIndex + 1)
            }
            scheduleAutoHide()
        }
    }

    /** TV：为所有可交互控件开启 D-pad 焦点并挂焦点环。 */
    private fun applyFocusability() {
        val focusables = listOfNotNull(
            backButton, speedChip, kernelChip, subtitleStyleChip, decodeChip,
            videoFitIcon, rotateIcon, prevButton, playPauseButton, nextButton,
            lockButton, bottomSpeedChip, panelToggleButton,
        ) + (0 until trailingGroup.childCount).map { trailingGroup.getChildAt(it) }
        focusables.forEach { makeFocusable(it) }
    }

    /** 把一个控件变成 D-pad 可达：可聚焦 + 聚焦时画 3px #C1C2FE 环。 */
    private fun makeFocusable(view: View) {
        view.isFocusable = true
        view.isFocusableInTouchMode = false
        if (view is TextView || view is LinearLayout) {
            val base = view.background
            view.setOnFocusChangeListener { v, hasFocus ->
                v.background = if (hasFocus) {
                    GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dp(NPTheme.RADIUS_CHIP).toFloat()
                        setColor(Color.TRANSPARENT)
                        setStroke(dp(NPTheme.SEEK_FOCUS_RING), NPTheme.FOCUS_RING)
                    }
                } else {
                    base
                }
                v.scaleX = if (hasFocus) 1.1f else 1.0f
                v.scaleY = if (hasFocus) 1.1f else 1.0f
            }
        }
    }

    /** 底栏重排前清空所有容器（幂等）。 */
    private fun clearBarContainers() {
        bottomBar.removeAllViews()
        seekRow.removeAllViews()
        buttonRow.removeAllViews()
        leadingGroup.removeAllViews()
        transportGroup.removeAllViews()
        trailingGroup.removeAllViews()
        // speedChip 属于顶栏内容，由 configureTopBar 填充；这里清掉会导致
        // 速度胶囊整块消失（v1.5.5 回归）。
        bottomSpeedChip.removeAllViews()
    }

    /** 底栏：Logo / 进度条 / 播放组（手机居中·TV 置左）/ 右侧图标组 / 诊断行。 */
    private fun configureBottomBar() {
        // 幂等：重排（手机↔TV）会二次进入本函数，必须先清空所有容器，
        // 否则对已有 parent 的子视图重复 addView 会抛 IllegalStateException。
        clearBarContainers()
        bottomBar.orientation = LinearLayout.VERTICAL
        bottomBar.gravity = Gravity.START
        bottomBar.setPadding(dp(16), dp(10), dp(16), dp(12))
        bottomBar.background = barGradient(topSolid = false)

        // 标题艺术字（Logo）：进度条上方左对齐，无图时占位 4dp 保持布局稳定。
        logoImage.scaleType = ImageView.ScaleType.FIT_START
        bottomBar.addView(logoImage, lp(dp(NPTheme.LOGO_WIDTH), dp(NPTheme.LOGO_HEIGHT)))
        logoSpacer.visibility = GONE
        bottomBar.addView(logoSpacer, lp(LayoutParams.MATCH_PARENT, dp(4)))

        // 进度条行：时间(56/78) · Slider · 时间
        seekRow.orientation = LinearLayout.HORIZONTAL
        seekRow.gravity = Gravity.CENTER_VERTICAL
        positionLabel.setTextColor(NPTheme.WHITE_70)
        positionLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        positionLabel.gravity = Gravity.CENTER_VERTICAL or Gravity.END
        positionLabel.text = "00:00"
        seekRow.addView(positionLabel, lp(dp(NPTheme.TIME_CELL), dp(40)))

        seekBar.max = SEEK_STEPS
        seekBar.progress = 0
        seekBar.isEnabled = false
        applySeekBarStyle()
        seekRow.addView(
            seekBar,
            LinearLayout.LayoutParams(0, dp(NPTheme.SEEK_THUMB * 2 + 8), 1f).also {
                it.marginStart = dp(8)
                it.marginEnd = dp(8)
            },
        )

        durationLabel.setTextColor(NPTheme.WHITE_70)
        durationLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        durationLabel.gravity = Gravity.CENTER_VERTICAL or Gravity.START
        durationLabel.text = "00:00"
        seekRow.addView(durationLabel, lp(dp(NPTheme.TIME_CELL), dp(40)))
        bottomBar.addView(seekRow, lp(LayoutParams.MATCH_PARENT, dp(40)))

        // leading 组（锁钮）
        leadingGroup.orientation = LinearLayout.HORIZONTAL
        leadingGroup.gravity = Gravity.CENTER_VERTICAL
        lockButton.text = String(Character.toChars(NativePlayerIcons.ICON_LOCK))
        lockButton.typeface = NativePlayerIcons.typeface(context)
        lockButton.setTextColor(Color.WHITE)
        lockButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.LOCK_ICON.toFloat())
        lockButton.gravity = Gravity.CENTER
        lockButton.includeFontPadding = false
        lockButton.setPadding(dp(8), dp(8), dp(8), dp(8))
        lockButton.isClickable = true
        lockButton.setOnClickListener { listener?.onToggleLock() }
        applyPressFeedback(lockButton)
        leadingGroup.addView(lockButton, lp(dp(44), dp(44)))

        // transport 组（上一集 / 播放暂停 / 下一集）
        transportGroup.orientation = LinearLayout.HORIZONTAL
        transportGroup.gravity = Gravity.CENTER_VERTICAL
        configureTransportButton(prevButton, NativePlayerIcons.ICON_SKIP_PREVIOUS, NPTheme.TRANSPORT_SIDE)
        configureTransportButton(playPauseButton, NativePlayerIcons.ICON_PLAY_CIRCLE, NPTheme.TRANSPORT_PLAY)
        configureTransportButton(nextButton, NativePlayerIcons.ICON_SKIP_NEXT, NPTheme.TRANSPORT_SIDE)
        // 传输组容器 = 字形尺寸 + 8dp 余量（28sp≈33dp / 36sp≈42dp），
        // 否则字形上下被裁（真机「控件残缺」观感）。
        transportGroup.addView(prevButton, llp(dp(NPTheme.TRANSPORT_SIDE + 8), dp(NPTheme.TRANSPORT_SIDE + 8)))
        // 注：lp() 是 FrameLayout.LayoutParams，加进 LinearLayout 会丢 margin，
        // 间距必须走 llp()（Flutter 播放组间距 8）。
        transportGroup.addView(
            playPauseButton,
            llp(dp(NPTheme.TRANSPORT_PLAY + 8), dp(NPTheme.TRANSPORT_PLAY + 8), NPTheme.TRANSPORT_GAP),
        )
        transportGroup.addView(
            nextButton,
            llp(dp(NPTheme.TRANSPORT_SIDE + 8), dp(NPTheme.TRANSPORT_SIDE + 8), NPTheme.TRANSPORT_GAP),
        )

        // trailing 组（弹幕 / 版本 / 显示调节 / 字幕 / 音轨 / 选集 / 倍速 / 面板）
        // 间距 20（Flutter SizedBox(20)）；首项无前距。
        trailingGroup.orientation = LinearLayout.HORIZONTAL
        trailingGroup.gravity = Gravity.CENTER_VERTICAL
        configureTransportButton(danmakuButton, NativePlayerIcons.ICON_DANMAKU_ON, 24)
        applyPressFeedback(danmakuButton)
        danmakuButton.setOnClickListener {
            listener?.onToggleDanmaku()
            scheduleAutoHide()
        }
        trailingGroup.addView(danmakuButton, llp(dp(32), dp(32)))
        versionButton = badgeButton(
            NativePlayerIcons.ICON_HIGH_QUALITY,
            { lastState.versions.size.takeIf { n -> n > 0 }?.toString() },
        ) { openPanel(PANEL_VERSION) }
        trailingGroup.addView(versionButton, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))
        displayAdjustButton = iconButton(NativePlayerIcons.ICON_TUNE) { openPanel(PANEL_DISPLAY) }
        trailingGroup.addView(displayAdjustButton!!, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))
        subtitleButton = badgeButton(
            NativePlayerIcons.ICON_SUBTITLES,
            { lastState.subtitleStreamCount.takeIf { n -> n > 0 }?.toString() },
        ) { openPanel(PANEL_SUBTITLE) }
        trailingGroup.addView(subtitleButton, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))
        audioButton = badgeButton(
            NativePlayerIcons.ICON_AUDIO_TRACK,
            { lastState.audioStreamCount.takeIf { n -> n > 0 }?.toString() },
        ) { openPanel(PANEL_AUDIO) }
        trailingGroup.addView(audioButton, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))
        episodeButton = badgeButton(
            NativePlayerIcons.ICON_PLAYLIST_PLAY,
            { lastState.episodes.size.takeIf { n -> n > 0 }?.toString() },
        ) { openPanel(PANEL_EPISODE) }
        trailingGroup.addView(episodeButton, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))
        // 倍速胶囊（TV）
        bottomSpeedChip.orientation = LinearLayout.HORIZONTAL
        bottomSpeedChip.gravity = Gravity.CENTER
        bottomSpeedChip.setPadding(dp(8), dp(4), dp(8), dp(4))
        bottomSpeedChip.isClickable = true
        bottomSpeedChip.background = glassBackground(10)
        bottomSpeedChip.setOnClickListener { openPanel(PANEL_SPEED) }
        bottomSpeedChip.addView(iconView(NativePlayerIcons.ICON_SPEED, 20f), lp(dp(24), dp(24)))
        bottomSpeedLabel.setTextColor(NPTheme.WHITE_70)
        bottomSpeedLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        bottomSpeedChip.addView(
            bottomSpeedLabel,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .also { it.marginStart = dp(4) },
        )
        trailingGroup.addView(
            bottomSpeedChip,
            llp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(34), NPTheme.CONTROL_GAP),
        )

        // 面板切换（房间模式，点开右侧资源面板）
        panelToggleButton.text = String(Character.toChars(NativePlayerIcons.ICON_OPEN_IN_FULL))
        panelToggleButton.typeface = NativePlayerIcons.typeface(context)
        panelToggleButton.setTextColor(Color.WHITE)
        panelToggleButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
        panelToggleButton.gravity = Gravity.CENTER
        panelToggleButton.includeFontPadding = false
        panelToggleButton.setPadding(dp(4), dp(4), dp(4), dp(4))
        panelToggleButton.isClickable = true
        panelToggleButton.setOnClickListener { listener?.onBack() }
        applyPressFeedback(panelToggleButton)
        trailingGroup.addView(panelToggleButton, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))

        // HDR 徽标
        hdrBadge.text = "HDR"
        hdrBadge.setTextColor(Color.BLACK)
        hdrBadge.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        hdrBadge.setBackgroundColor(0xFFFFD54F.toInt())
        hdrBadge.setPadding(dp(6), dp(2), dp(6), dp(2))
        hdrBadge.visibility = GONE

        // 组装三组
        // leading 列宽 = 时间数显列宽（Flutter SeekTimeLabels.cellWidth），
        // 保证锁钮与上方左时间数显同轴居中。
        val leadingLp = FrameLayout.LayoutParams(
            dp(NPTheme.TIME_CELL),
            dp(44),
            Gravity.CENTER_VERTICAL or Gravity.START,
        )
        val transportLp = FrameLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            dp(NPTheme.TRANSPORT_PLAY),
            Gravity.CENTER,
        )
        val trailingLp = FrameLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            dp(NPTheme.TRANSPORT_PLAY),
            Gravity.CENTER_VERTICAL or Gravity.END,
        )
        buttonRow.addView(leadingGroup, leadingLp)
        buttonRow.addView(transportGroup, transportLp)
        buttonRow.addView(trailingGroup, trailingLp)
        // 控件行与进度条行间距 8（Flutter SizedBox(height: 8)）。
        bottomBar.addView(
            buttonRow,
            LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, dp(NPTheme.TRANSPORT_PLAY + 8))
                .also { it.topMargin = dp(8) },
        )

        // 诊断行（默认隐藏）
        diagText.setTextColor(0x99FFFFFF.toInt())
        diagText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
        diagText.maxLines = 2
        diagText.visibility = GONE
        bottomBar.addView(diagText, lp(LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
    }

    // ── 控件工厂 ──────────────────────────────────────────────────

    /** 右侧纯图标按钮（24dp 图标 + 4dp 内边距，与 Flutter _buildControlButton 一致）。 */
    /**
     * 右侧图标按钮（无角标）。
     *
     * 24sp 字形净高约 28dp（含 ascent/descent），容器必须 ≥28dp 否则裁切。
     * 统一 32dp 容器 + 4dp padding + includeFontPadding=false：
     * 内容区 24dp，字形按 fontSize 自适应居中，不再被裁。
     */
    private fun iconButton(codePoint: Int, onClick: () -> Unit): TextView =
        TextView(context).apply {
            text = String(Character.toChars(codePoint))
            typeface = NativePlayerIcons.typeface(context)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.CONTROL_ICON.toFloat())
            gravity = Gravity.CENTER
            includeFontPadding = false
            setPadding(0, 0, 0, 0)
            isClickable = true
            setOnClickListener { onClick() }
            applyPressFeedback(this)
        }

    /**
     * 带角标的右侧图标按钮：图标 24dp 字形、角标 9sp + #6366F1 圆底，
     * 贴图标右上（Flutter Stack + Positioned(right:-6,top:-4)）。
     *
     * 关键：图标容器必须 ≥ 字形净高（24sp≈28dp），旧实现给 24dp → 字形
     * 上下被裁（真机「控件残缺」观感）。这里用 28dp 容器。
     */
    private fun badgeButton(
        codePoint: Int,
        badgeProvider: () -> String?,
        onClick: () -> Unit,
    ): FrameLayout {
        val host = FrameLayout(context)
        host.addView(iconButton(codePoint, onClick), lp(dp(28), dp(28), Gravity.CENTER))
        val badge = TextView(context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.BADGE_FONT)
            gravity = Gravity.CENTER
            includeFontPadding = false
            setPadding(dp(3), dp(1), dp(3), dp(1))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(NPTheme.ACCENT)
            }
        }
        host.addView(badge, badgeLayoutParams(dp(NPTheme.BADGE_MIN)))
        // 角标数量在 applyState 中刷新
        badgeTags[badge] = badgeProvider
        return host
    }

    /**
     * 角标定位：贴图标右上角（Flutter _buildControlButton 的
     * Positioned(right: -6, top: -4)）。32dp 命中框内图标 24dp 居中，
     * 换算到命中框坐标为 top=0 / marginEnd=-2。
     */
    private fun badgeLayoutParams(widthDp: Int): LayoutParams =
        LayoutParams(widthDp, dp(NPTheme.BADGE_MIN), Gravity.TOP or Gravity.END).apply {
            topMargin = 0
            marginEnd = -dp(2)
        }

    /** 角标刷新表（TextView → 数量提供者）。 */
    private val badgeTags = HashMap<TextView, () -> String?>()


    /** 传输组按钮（上一集/播放/下一集）。 */
    private fun configureTransportButton(button: TextView, codePoint: Int, sizeSp: Int) {
        button.text = String(Character.toChars(codePoint))
        button.typeface = NativePlayerIcons.typeface(context)
        button.setTextColor(Color.WHITE)
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp.toFloat())
        button.gravity = Gravity.CENTER
        // 关字体留白：28sp/36sp 字形净高超过容器时会被裁（真机残缺观感）。
        button.includeFontPadding = false
        button.setPadding(0, 0, 0, 0)
        button.isClickable = true
        applyPressFeedback(button)
    }

    // ── 面板层 ────────────────────────────────────────────────────

    private fun configureOverlays() {
        panelContainer.orientation = LinearLayout.VERTICAL
        panelContainer.visibility = GONE
        panelContainer.clipToOutline = true
        decodePopover.orientation = LinearLayout.VERTICAL
        decodePopover.visibility = GONE
        segmentCard.orientation = LinearLayout.VERTICAL
        segmentCard.gravity = Gravity.CENTER
        segmentCard.visibility = GONE
    }

    /** 面板容器几何：宽 clamp(0.42×屏宽, 260, 320)，贴右 12、上避顶栏 48、下避控制条 116。 */
    private fun panelWidthDp(): Int {
        val w = width.takeIf { it > 0 }
            ?: resources.displayMetrics.widthPixels
        val target = (w * 0.42f).toInt()
        return target.coerceIn(dp(NPTheme.PANEL_MIN_WIDTH.toInt()), dp(NPTheme.PANEL_MAX_WIDTH.toInt()))
    }

    /** 打开面板（同类型再点为切换关闭）。 */
    private fun openPanel(panel: String) {
        activePanel = if (activePanel == panel) null else panel
        decodePopoverOpen = false
        listener?.onOpenPanel(panel)
        renderOverlays()
        scheduleAutoHide()
    }

    /** 关闭面板。 */
    fun closePanel() {
        if (activePanel == null) return
        activePanel = null
        listener?.onClosePanel()
        renderOverlays()
    }

    /**
     * 面板层总渲染：按 activePanel / decodePopoverOpen / segmentCardOpen
     * 决定显示哪一层；无则全部隐藏。
     */
    private fun renderOverlays() {
        val panel = activePanel
        if (panel == null) {
            panelScrim.visibility = GONE
            panelContainer.visibility = GONE
        } else {
            panelScrim.visibility = VISIBLE
            panelContainer.visibility = VISIBLE
            panelContainer.removeAllViews()
            // 选集面板全高贴边（Flutter fullBleed：top/bottom/right 0、右圆角放平）；
            // 常规面板上下避让（top safe+48 / bottom 116+safe），**拉伸全高**
            //（Flutter Positioned(top,bottom) 语义，非 wrap-content）。
            val fullBleed = panel == PANEL_EPISODE
            // 液态玻璃（方案 A）：玻璃可用且开启 → 真采样折射背景；
            // 否则降级 tint（GraphDrawable），全链路不抛出。
            val useGlass = lastState.glassUi && glassPanel != null
            panelContainer.background = when {
                useGlass && !fullBleed -> glassPanel
                fullBleed -> GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadii = floatArrayOf(
                        dp(NPTheme.RADIUS_PANEL).toFloat(), dp(NPTheme.RADIUS_PANEL).toFloat(),
                        0f, 0f,
                        0f, 0f,
                        dp(NPTheme.RADIUS_PANEL).toFloat(), dp(NPTheme.RADIUS_PANEL).toFloat(),
                    )
                    setColor(NPTheme.PANEL_TINT)
                    setStroke(dp(1), NPTheme.RIM)
                }
                else -> glassBackground(NPTheme.RADIUS_PANEL)
            }
            panelContainer.layoutParams = lp(
                panelWidthDp(),
                LayoutParams.MATCH_PARENT,
            ).also {
                it.topMargin = if (fullBleed) 0 else dp(NPTheme.PANEL_TOP_OFFSET)
                it.bottomMargin = if (fullBleed) 0 else dp(NPTheme.PANEL_BOTTOM_OFFSET)
                it.marginEnd = if (fullBleed) 0 else dp(NPTheme.PANEL_RIGHT)
                it.gravity = Gravity.END or Gravity.TOP
            }
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
                PANEL_KERNEL -> buildKernelContent()
                PANEL_DISPLAY -> buildDisplayContent()
                PANEL_DECODE -> buildDecodeContent()
            }
        }
        // 解码 popover
        if (decodePopoverOpen) {
            renderDecodePopover()
        } else {
            decodePopover.visibility = GONE
        }
        // 片头片尾卡
        if (segmentCardOpen) {
            renderSegmentCard()
        } else {
            segmentCard.visibility = GONE
            segmentScrim.visibility = GONE
        }
    }

    private fun panelTitle(panel: String): String = when (panel) {
        PANEL_SPEED -> "倍速"
        PANEL_AUDIO -> "音轨"
        PANEL_SUBTITLE -> "字幕"
        PANEL_EPISODE -> "选集"
        PANEL_VERSION -> "线路"
        PANEL_KERNEL -> "播放内核"
        PANEL_DISPLAY -> "显示调节"
        PANEL_DECODE -> "解码模式"
        else -> "设置"
    }

    /** 面板标题（15sp 加粗，左对齐）。 */
    private fun panelHeader(title: String): TextView =
        TextView(context).apply {
            text = title
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.START
            // Flutter SelectorSidePanel：GlassContainer(top:10) + 标题 h16 + 4 间隙。
            setPadding(dp(NPTheme.PANEL_PAD_H), dp(10), dp(NPTheme.PANEL_PAD_H), dp(4))
        }

    /** 面板内容滚动包裹（weight 1 撑满拉伸面板，超长滚动）。 */
    private fun scrollWrap(content: View): ScrollView =
        ScrollView(context).apply {
            isFillViewport = true
            addView(content)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
        }

    /**
     * 选项行：文字左对齐 + 选中主色加粗 + 右侧对勾占 18dp 槽位。
     */
    private fun optionRow(label: String, selected: Boolean, onTap: () -> Unit): LinearLayout =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(NPTheme.PANEL_PAD_H), dp(NPTheme.PANEL_PAD_V), dp(NPTheme.PANEL_PAD_H), dp(NPTheme.PANEL_PAD_V))
            isClickable = true
            setOnClickListener { onTap() }
            addView(
                TextView(context).apply {
                    text = label
                    setTextColor(if (selected) NPTheme.ACCENT else Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_OPTION_SIZE)
                    typeface = if (selected) Typeface.create(Typeface.DEFAULT, Typeface.BOLD) else Typeface.DEFAULT
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
            )
            addView(
                TextView(context).apply {
                    text = if (selected) String(Character.toChars(NativePlayerIcons.ICON_CHECK)) else ""
                    typeface = NativePlayerIcons.typeface(context)
                    setTextColor(NPTheme.ACCENT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                    gravity = Gravity.CENTER
                },
                LinearLayout.LayoutParams(dp(NPTheme.PANEL_CHECK_SLOT), LinearLayout.LayoutParams.WRAP_CONTENT),
            )
        }

    /** 倍速：纵向列表。 */
    private fun buildSpeedContent() {
        val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        SPEED_STEPS.forEach { v ->
            val selected = Math.abs(lastState.speed - v) < 0.01
            list.addView(
                optionRow("${v}x", selected) {
                    listener?.onSetSpeed(v)
                    closePanel()
                },
            )
        }
        panelContainer.addView(scrollWrap(list))
    }

    /** 轨道列表（音轨/字幕）。 */
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
        panelContainer.addView(scrollWrap(list))
    }

    /** 通用列表（选集/线路）。 */
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
        panelContainer.addView(scrollWrap(list))
    }

    // ── 内核面板 ──────────────────────────────────────────────────

    private fun buildKernelContent() {
        val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        lastState.engineOptions.forEach { opt ->
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(NPTheme.PANEL_PAD_H), dp(NPTheme.PANEL_PAD_V), dp(NPTheme.PANEL_PAD_H), dp(NPTheme.PANEL_PAD_V))
                isClickable = true
                setOnClickListener {
                    listener?.onSwitchEngine(opt.id)
                    closePanel()
                }
            }
            val textCol = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(
                    TextView(context).apply {
                        text = opt.label
                        setTextColor(Color.WHITE)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                    },
                )
                if (opt.description.isNotEmpty()) {
                    addView(
                        TextView(context).apply {
                            text = opt.description
                            setTextColor(NPTheme.WHITE_54)
                            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                            maxLines = 2
                        },
                    )
                }
            }
            row.addView(textCol, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(
                TextView(context).apply {
                    text = if (opt.label == lastState.engineLabel) "✓" else ""
                    setTextColor(NPTheme.ACCENT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                    gravity = Gravity.CENTER
                },
                LinearLayout.LayoutParams(dp(NPTheme.PANEL_CHECK_SLOT), LinearLayout.LayoutParams.WRAP_CONTENT),
            )
            list.addView(row)
        }
        panelContainer.addView(scrollWrap(list))
    }

    // ── 显示调节面板 ──────────────────────────────────────────────

    private fun buildDisplayContent() {
        val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        list.addView(sectionTitle("字幕"))
        list.addView(
            sliderRow("大小", lastState.subtitleScale, 0.5, 3.0, 0.05) {
                listener?.onAdjustDisplay("subtitleScale", it)
            },
        )
        list.addView(
            sliderRow("位置", lastState.subtitleMarginY.toDouble(), 0.0, 200.0, 2.0) {
                listener?.onAdjustDisplay("subtitleMarginY", it)
            },
        )
        list.addView(
            sliderRow("延迟", lastState.subtitleDelayMs, -5000.0, 5000.0, 100.0) {
                listener?.onAdjustDisplay("subtitleDelayMs", it)
            },
        )
        list.addView(sectionTitle("弹幕"))
        list.addView(
            sliderRow("速度", lastState.danmakuSpeed, 0.5, 2.0, 0.05) {
                listener?.onAdjustDisplay("danmakuSpeed", it)
            },
        )
        list.addView(
            sliderRow("大小", lastState.danmakuFontSize, 0.5, 2.0, 0.05) {
                listener?.onAdjustDisplay("danmakuFontSize", it)
            },
        )
        list.addView(
            sliderRow("透明度", lastState.danmakuOpacity, 0.1, 1.0, 0.05) {
                listener?.onAdjustDisplay("danmakuOpacity", it)
            },
        )
        panelContainer.addView(scrollWrap(list))
    }

    private fun sectionTitle(title: String): TextView =
        TextView(context).apply {
            text = title
            setTextColor(NPTheme.WHITE_38)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(NPTheme.PANEL_PAD_H), dp(6), dp(NPTheme.PANEL_PAD_H), dp(2))
        }

    /** 显示调节滑杆行：标签 44dp / 滑杆 / 数值 48dp，padding h16 v10。 */
    private fun sliderRow(
        label: String,
        value: Double,
        rangeMin: Double,
        rangeMax: Double,
        step: Double,
        onChange: (Double) -> Unit,
    ): LinearLayout {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(NPTheme.ADJUST_ROW_PAD_H), dp(NPTheme.ADJUST_ROW_PAD_V), dp(NPTheme.ADJUST_ROW_PAD_H), dp(NPTheme.ADJUST_ROW_PAD_V))
        }
        row.addView(
            TextView(context).apply {
                text = label
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            },
            LinearLayout.LayoutParams(dp(NPTheme.ADJUST_LABEL_WIDTH), LinearLayout.LayoutParams.WRAP_CONTENT),
        )
        val bar = SeekBar(context).apply {
            max = ((rangeMax - rangeMin) / step).toInt()
            progress = ((value - rangeMin) / step).toInt().coerceIn(0, this.max)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar, progress: Int, fromUser: Boolean) {
                    if (!fromUser) return
                    onChange(rangeMin + progress * step)
                    scheduleAutoHide()
                }

                override fun onStartTrackingTouch(bar: SeekBar) {}

                override fun onStopTrackingTouch(bar: SeekBar) {}
            })
        }
        row.addView(bar, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(
            TextView(context).apply {
                text = formatAdjustValue(value)
                setTextColor(NPTheme.WHITE_70)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                gravity = Gravity.CENTER or Gravity.END
            },
            LinearLayout.LayoutParams(dp(NPTheme.ADJUST_VALUE_WIDTH), LinearLayout.LayoutParams.WRAP_CONTENT),
        )
        return row
    }

    private fun formatAdjustValue(v: Double): String {
        val rounded = Math.round(v * 100.0) / 100.0
        return if (rounded == Math.floor(rounded) && Math.abs(rounded) < 1e9) {
            "${rounded.toLong()}"
        } else {
            "$rounded"
        }
    }

    // ── 解码模式 ──────────────────────────────────────────────────

    /** 解码 popover：180dp 宽 #1E1E2E 圆角 8，标题 13 加粗 + 当前值 12 #A5B4FC。 */
    private fun renderDecodePopover() {
        decodePopover.visibility = VISIBLE
        decodePopover.removeAllViews()
        decodePopover.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(NPTheme.RADIUS_DECODE).toFloat()
            setColor(NPTheme.DECODE_PANEL)
        }
        decodePopover.layoutParams = lp(dp(NPTheme.DECODE_PANEL_WIDTH), LayoutParams.WRAP_CONTENT).also {
            it.gravity = Gravity.BOTTOM or Gravity.END
            it.marginEnd = dp(NPTheme.PANEL_RIGHT)
            it.bottomMargin = dp(NPTheme.PANEL_BOTTOM_OFFSET)
        }
        decodePopover.addView(
            TextView(context).apply {
                text = "解码模式"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                setPadding(dp(12), dp(10), dp(12), dp(2))
            },
        )
        decodePopover.addView(
            TextView(context).apply {
                text = decodeModeLabel(lastState.decodeMode)
                setTextColor(NPTheme.DECODE_CURRENT_TEXT)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setPadding(dp(12), 0, dp(12), dp(6))
            },
        )
        DECODE_MODES.forEach { mode ->
            decodePopover.addView(
                optionRow(decodeModeLabel(mode), lastState.decodeMode == mode) {
                    listener?.onSetDecodeMode(mode)
                    decodePopoverOpen = false
                    renderOverlays()
                },
            )
        }
    }

    private fun decodeModeLabel(mode: String): String = when (mode) {
        "auto" -> "自动"
        "hw" -> "硬解"
        "sw" -> "软解"
        else -> mode
    }

    /** 解码模式面板（手机顶栏胶囊打开时用右侧浮层；TV 无入口）。 */
    private fun buildDecodeContent() {
        val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        list.addView(
            TextView(context).apply {
                text = decodeModeLabel(lastState.decodeMode)
                setTextColor(NPTheme.DECODE_CURRENT_TEXT)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setPadding(dp(NPTheme.PANEL_PAD_H), 0, dp(NPTheme.PANEL_PAD_H), dp(6))
            },
        )
        DECODE_MODES.forEach { mode ->
            list.addView(
                optionRow(decodeModeLabel(mode), lastState.decodeMode == mode) {
                    listener?.onSetDecodeMode(mode)
                    closePanel()
                },
            )
        }
        panelContainer.addView(scrollWrap(list))
    }

    // ── 片头片尾卡（居中玻璃卡 + 二次确认）────────────────────────

    /**
     * 片头片尾卡片：两行（片头/片尾），每行显示当前标记；已有标记时
     * 点击进入二次确认（更新当前位置 / 清除 / 取消）。
     */
    private fun renderSegmentCard() {
        segmentScrim.visibility = VISIBLE
        segmentCard.visibility = VISIBLE
        segmentCard.removeAllViews()
        segmentCard.background = if (lastState.glassUi && glassCard != null) {
            glassCard
        } else {
            glassBackground(NPTheme.RADIUS_CARD)
        }
        segmentCard.layoutParams = lp(dp(NPTheme.SEGMENT_CARD_WIDTH), LayoutParams.WRAP_CONTENT, Gravity.CENTER)
        val confirm = segmentConfirmKind
        if (confirm != null) {
            renderSegmentConfirm(confirm)
            return
        }
        segmentCard.addView(panelHeader("片头片尾"))
        segmentCard.addView(
            segmentRow(
                NativePlayerIcons.ICON_SKIP_NEXT,
                "片头",
                lastState.segmentIntroEndMs?.let { "已标记 ${AndroidNativePlayerState.formatPlayerTime(it.toLong())}" } ?: "点击以当前位置标记",
            ) { onSegmentRowTap("intro") },
        )
        segmentCard.addView(
            segmentRow(
                NativePlayerIcons.ICON_SKIP_PREVIOUS,
                "片尾",
                lastState.segmentOutroStartMs?.let { "已标记 ${AndroidNativePlayerState.formatPlayerTime(it.toLong())}" } ?: "点击以当前位置标记",
            ) { onSegmentRowTap("outro") },
        )
    }

    /** 片头片尾二次确认：更新（用当前位置覆盖）/ 清除 / 取消。 */
    private fun renderSegmentConfirm(kind: String) {
        val isIntro = kind == "intro"
        val existingMs = if (isIntro) lastState.segmentIntroEndMs else lastState.segmentOutroStartMs
        segmentCard.addView(panelHeader(if (isIntro) "片头已设置" else "片尾已设置"))
        segmentCard.addView(
            TextView(context).apply {
                text = "当前标记：${existingMs?.let { AndroidNativePlayerState.formatPlayerTime(it.toLong()) } ?: "无"}\n要用当前位置更新，还是清除？"
                setTextColor(NPTheme.WHITE_54)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(dp(NPTheme.PANEL_PAD_H), 0, dp(NPTheme.PANEL_PAD_H), dp(10))
            },
        )
        val actions = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            setPadding(dp(NPTheme.PANEL_PAD_H), 0, dp(NPTheme.PANEL_PAD_H), dp(NPTheme.PANEL_PAD_V))
        }
        actions.addView(segmentAction("取消") {
            segmentCardOpen = false
            segmentConfirmKind = null
            renderOverlays()
        })
        actions.addView(segmentAction("清除") {
            listener?.onClearSegmentMark(kind)
            segmentCardOpen = false
            segmentConfirmKind = null
            renderOverlays()
        })
        actions.addView(segmentAction("更新") {
            listener?.onSetSegmentMark(kind, lastState.positionMs.toLong())
            segmentCardOpen = false
            segmentConfirmKind = null
            renderOverlays()
        })
        segmentCard.addView(actions)
    }

    private fun segmentAction(label: String, onTap: () -> Unit): TextView =
        TextView(context).apply {
            text = label
            setTextColor(NPTheme.ACCENT)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setPadding(dp(12), dp(6), dp(12), dp(6))
            isClickable = true
            setOnClickListener { onTap() }
        }

    private fun segmentRow(codePoint: Int, title: String, hint: String, onTap: () -> Unit): LinearLayout =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(NPTheme.PANEL_PAD_H), dp(NPTheme.PANEL_PAD_V), dp(NPTheme.PANEL_PAD_H), dp(NPTheme.PANEL_PAD_V))
            isClickable = true
            setOnClickListener { onTap() }
            addView(
                TextView(context).apply {
                    text = String(Character.toChars(codePoint))
                    typeface = NativePlayerIcons.typeface(context)
                    setTextColor(Color.WHITE)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.SEGMENT_ROW_ICON.toFloat())
                    gravity = Gravity.CENTER
                },
                LinearLayout.LayoutParams(dp(NPTheme.SEGMENT_ROW_ICON), dp(NPTheme.SEGMENT_ROW_ICON)),
            )
            val col = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(
                    TextView(context).apply {
                        text = title
                        setTextColor(Color.WHITE)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.SEGMENT_ROW_TITLE_SIZE)
                    },
                )
                addView(
                    TextView(context).apply {
                        text = hint
                        setTextColor(NPTheme.WHITE_54)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.SEGMENT_ROW_HINT_SIZE)
                    },
                )
            }
            addView(col, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).also { it.marginStart = dp(10) })
            addView(
                TextView(context).apply {
                    text = String(Character.toChars(NativePlayerIcons.ICON_CHEVRON_RIGHT))
                    typeface = NativePlayerIcons.typeface(context)
                    setTextColor(NPTheme.WHITE_38)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.SEGMENT_CHEVRON.toFloat())
                    gravity = Gravity.CENTER
                },
                LinearLayout.LayoutParams(dp(NPTheme.SEGMENT_CHEVRON), dp(NPTheme.SEGMENT_CHEVRON)),
            )
        }

    private fun onSegmentRowTap(kind: String) {
        val existing = if (kind == "intro") lastState.segmentIntroEndMs else lastState.segmentOutroStartMs
        if (existing == null) {
            listener?.onSetSegmentMark(kind, lastState.positionMs.toLong())
            segmentCardOpen = false
            renderOverlays()
            return
        }
        segmentConfirmKind = kind
        renderOverlays()
    }

    // ── 生命周期 / 状态渲染 ───────────────────────────────────────

    /** 释放定时器与监听器。 */
    fun release() {
        mainHandler.removeCallbacks(tickRunnable)
        mainHandler.removeCallbacks(hideRunnable)
        stopGlassSampling()
        glassPanel?.release()
        glassCard?.release()
        listener = null
    }

    /** 用 Dart 推送的权威快照覆盖本地状态并刷新控件。 */
    fun render(state: AndroidNativePlayerState, snapshotAtMs: Long = System.currentTimeMillis()) {
        lastState = state
        lastStateAtMs = snapshotAtMs
        applyState()
    }

    /**
     * 转屏/小屏自适应（Flutter FittedBox(scaleDown) 语义）：右侧组超宽时
     * 整体等比缩小（锚定右缘），保证横竖屏切换/小窗下控件不出屏、不重叠
     *（真机回归：竖屏时右侧组与传输组挤压重叠）。
     */
    private fun applyAdaptiveScale() {
        buttonRow.post {
            val total = buttonRow.width
            if (total <= 0) return@post
            // Flutter PlayerBottomRow：leading/transport/trailing 三段里
            // transport 绝对居中，trailing 的 Expanded 可用宽 =（总宽-传输组）/2。
            val avail = (total - transportGroup.width) / 2 - dp(8)
            val needed = trailingGroup.width
            val s = if (needed > 0 && avail > 0 && needed > avail) {
                (avail.toFloat() / needed).coerceIn(0.2f, 1f)
            } else {
                1f
            }
            trailingGroup.pivotX = trailingGroup.width.toFloat()
            trailingGroup.pivotY = trailingGroup.height / 2f
            trailingGroup.scaleX = s
            trailingGroup.scaleY = s
        }
        topBar.post {
            val total = topBar.width
            if (total <= 0) return@post
            // 顶栏：title 为 Expanded（可压缩至 0），尾组可用 = 总宽 - 返回钮。
            val avail = total - backButton.width - dp(8)
            val needed = topTail.width
            val s = if (needed > 0 && avail > 0 && needed > avail) {
                (avail.toFloat() / needed).coerceIn(0.2f, 1f)
            } else {
                1f
            }
            topTail.pivotX = topTail.width.toFloat()
            topTail.pivotY = topTail.height / 2f
            topTail.scaleX = s
            topTail.scaleY = s
        }
    }

    private fun applyState() {
        val state = lastState
        val now = System.currentTimeMillis()

        // 模式切换（手机 ↔ TV）需重排顶/底栏的子控件组合；先做，后续
        // 赋值都作用在重排后的视图上。
        if (state.tvMode != lastTvMode) {
            lastTvMode = state.tvMode
            rebuildBars()
        }

        titleText.text = state.displayTitle
        speedLabel.text = trimSpeed(state.speed)
        bottomSpeedLabel.text = trimSpeed(state.speed)
        kernelChip.text = state.engineLabel
        videoFitIcon.text = String(
            Character.toChars(
                when (state.videoFit) {
                    "cover" -> NativePlayerIcons.ICON_FULLSCREEN
                    "fill" -> NativePlayerIcons.ICON_ZOOM_OUT_MAP
                    "none" -> NativePlayerIcons.ICON_ASPECT_RATIO
                    else -> NativePlayerIcons.ICON_FIT_SCREEN
                },
            ),
        )
        playPauseButton.text = String(
            Character.toChars(
                if (state.paused) NativePlayerIcons.ICON_PLAY_CIRCLE else NativePlayerIcons.ICON_PAUSE_CIRCLE,
            ),
        )

        // 传输组：单集/电影只保留播放键（prev/next 空占位），多集才显示图标；
        // 不可达时置灰（与 Flutter white24 一致）。
        val multiEpisode = state.episodes.size > 1
        val hasPrevEp = state.currentEpisodeIndex > 0
        val hasNextEp = state.currentEpisodeIndex >= 0 &&
            state.currentEpisodeIndex + 1 < state.episodes.size
        prevButton.text = if (multiEpisode) {
            String(Character.toChars(NativePlayerIcons.ICON_SKIP_PREVIOUS))
        } else {
            ""
        }
        nextButton.text = if (multiEpisode) {
            String(Character.toChars(NativePlayerIcons.ICON_SKIP_NEXT))
        } else {
            ""
        }
        prevButton.setTextColor(if (hasPrevEp) Color.WHITE else NPTheme.WHITE_24)
        nextButton.setTextColor(if (hasNextEp) Color.WHITE else NPTheme.WHITE_24)
        prevButton.isEnabled = multiEpisode && hasPrevEp
        nextButton.isEnabled = multiEpisode && hasNextEp

        // 角标
        badgeTags.forEach { (badge, provider) ->
            val text = provider()
            badge.text = text ?: ""
            badge.visibility = if (text.isNullOrEmpty()) GONE else VISIBLE
            badge.layoutParams = badgeLayoutParams(dp(14 + text.orEmpty().length * 5))
        }

        // 顶栏网速
        networkText.text = state.networkSpeedText ?: ""
        networkText.visibility = if (state.networkSpeedText != null) VISIBLE else GONE

        // 弹幕层：状态参数 + 时间窗（原生渲染，Flutter 弹幕层随视频区退场）。
        danmakuLayer.update(
            state.danmakuItems,
            state.danmakuEnabled && !state.isRoom,
            state.danmakuSpeed,
            state.danmakuFontSize,
            state.danmakuOpacity,
        )

        // 时间数显
        if (!dragging) {
            val pos = state.positionAt(now, lastStateAtMs)
            positionLabel.text = AndroidNativePlayerState.formatPlayerTime(pos)
            danmakuLayer.setClock(pos, state.paused)
            seekBar.progress =
                if (state.durationMs > 0) {
                    ((pos * SEEK_STEPS) / state.durationMs).toInt().coerceIn(0, SEEK_STEPS)
                } else {
                    0
                }
        }
        durationLabel.text = AndroidNativePlayerState.formatPlayerTime(state.durationMs.toLong())
        seekBar.isEnabled = !state.isLiveLike

        // 诊断行
        val diag = buildDiag(state)
        diagText.text = diag
        diagText.visibility = if (state.showDebug && diag.isNotEmpty()) VISIBLE else GONE

        // 缓冲指示：仅缓冲中显示，暂停态也保持可见（与 Flutter 加载遮罩一致）。
        bufferingView.visibility = if (state.buffering) VISIBLE else GONE

        // TV / 手机布局差异
        applyLayoutMode(state)

        // 面板开着时重建（高亮跟随）
        if (activePanel != null || decodePopoverOpen || segmentCardOpen) {
            renderOverlays()
        }
    }

    private fun applyLayoutMode(state: AndroidNativePlayerState) {
        val tv = state.tvMode
        // 顶栏可见项
        speedChip.visibility = if (!tv && !state.isRoom) VISIBLE else GONE
        subtitleStyleChip.visibility = if (!tv) VISIBLE else GONE
        decodeChip.visibility = if (!tv) VISIBLE else GONE
        videoFitIcon.visibility = if (!tv) VISIBLE else GONE
        rotateIcon.visibility = if (!tv) VISIBLE else GONE
        clockWrap.visibility = if (tv) VISIBLE else GONE

        // 芯片打开态（Flutter：面板打开时强调色描边/文字）
        val panel = activePanel
        kernelChip.background = chipBackground(panel == PANEL_KERNEL)
        kernelChip.setTextColor(if (panel == PANEL_KERNEL) NPTheme.ACCENT else Color.WHITE)
        subtitleStyleChip.background = chipBackground(panel == PANEL_DISPLAY)
        decodeChip.background = chipBackground(panel == PANEL_DECODE)
        speedLabel.setTextColor(if (panel == PANEL_SPEED) NPTheme.ACCENT else NPTheme.WHITE_70)

        // 底栏可见项
        lockButton.visibility = if (!tv) VISIBLE else GONE
        bottomSpeedChip.visibility = if (tv && !state.isRoom) VISIBLE else GONE
        displayAdjustButton?.visibility = if (tv) VISIBLE else GONE
        panelToggleButton.visibility = if (state.isRoom) VISIBLE else GONE
        hdrBadge.visibility = if (state.hdrOutput) VISIBLE else GONE

        // 版本/选集按钮：非房间且多版本/多集才显示（与 Flutter 显隐条件一致）
        versionButton?.visibility =
            if (!state.isRoom && state.versions.size > 1) VISIBLE else GONE
        episodeButton?.visibility =
            if (!state.isRoom && state.episodes.size > 1) VISIBLE else GONE

        // 弹幕图标随开关切换（comment ↔ comments_disabled）
        danmakuButton.text = String(
            Character.toChars(
                if (state.danmakuEnabled) {
                    NativePlayerIcons.ICON_DANMAKU_ON
                } else {
                    NativePlayerIcons.ICON_DANMAKU_OFF
                },
            ),
        )
        // 锁图标随锁定态切换（lock_open ↔ lock，与 Flutter PlayerLockButton 一致）
        lockButton.text = String(
            Character.toChars(
                if (state.locked) NativePlayerIcons.ICON_LOCK else NativePlayerIcons.ICON_LOCK_OPEN,
            ),
        )

        // 时间数显列宽：时长 ≥1h 用 HH:MM:SS 档（78），否则 MM:SS 档（56）
        //（与 Flutter SeekTimeLabels.cellWidth 一致；leading 锁钮列同宽对齐）。
        val cellW = dp(if (state.durationMs >= 3600000) NPTheme.TIME_CELL_WIDE else NPTheme.TIME_CELL)
        (positionLabel.layoutParams as? LinearLayout.LayoutParams)?.width = cellW
        (durationLabel.layoutParams as? LinearLayout.LayoutParams)?.width = cellW
        (leadingGroup.layoutParams as? FrameLayout.LayoutParams)?.width = cellW

        // Logo（房间模式/无图时隐藏）
        val showLogo = state.logoUrl != null && state.logoUrl!!.isNotEmpty() && !state.isRoom
        // 网络加载失败时加载器会隐藏 logoImage（与 Flutter EmbyImage 一致）。
        NativeLogoLoader.load(logoImage, if (showLogo) state.logoUrl else null)
        // Logo 与进度条间的 4dp 间隙只在显示 Logo 时存在（Flutter if(showLogo) 块内）。
        logoSpacer.visibility = if (showLogo) VISIBLE else GONE

        // 锁定态：只显示锁钮
        if (!tv && state.locked) {
            transportGroup.visibility = GONE
            trailingGroup.visibility = GONE
            leadingGroup.visibility = VISIBLE
            lockButton.text = String(Character.toChars(NativePlayerIcons.ICON_LOCK))
        } else {
            transportGroup.visibility = VISIBLE
            trailingGroup.visibility = VISIBLE
            leadingGroup.visibility = if (!tv) VISIBLE else GONE
        }

        // 转屏/小窗自适应：右侧组超宽等比缩（不出屏、不与传输组重叠）。
        applyAdaptiveScale()

        // 液态玻璃采样节拍：任一玻璃面/卡可见时开（4fps），全关即停。
        val glassActive =
            (panelContainer.visibility == VISIBLE && panelContainer.background === glassPanel) ||
                (segmentCard.visibility == VISIBLE && segmentCard.background === glassCard)
        if (glassActive) {
            startGlassSampling()
        } else {
            stopGlassSampling()
        }
    }

    private var glassSampling = false

    private fun startGlassSampling() {
        if (glassSampling) return
        glassSampling = true
        glassPanel?.sampleAsync()
        glassCard?.sampleAsync()
        mainHandler.postDelayed(glassSampleRunnable, GlassBackdropDrawable.SAMPLE_INTERVAL_MS)
    }

    private fun stopGlassSampling() {
        glassSampling = false
        mainHandler.removeCallbacks(glassSampleRunnable)
    }

    /** 手机 ↔ TV 切换时重排顶栏/底栏子控件（不递归回 applyState）。 */
    private fun rebuildBars() {
        topBar.removeAllViews()
        bottomBar.removeAllViews()
        configureTopBar()
        configureBottomBar()
        configureSeekListeners()
        configureTransportListeners()
        applyFocusability()
    }

    private fun buildDiag(state: AndroidNativePlayerState): String {
        val parts = mutableListOf<String>()
        parts.add("vo=${state.currentVo ?: state.voConfigured ?: "-"}")
        parts.add("hwdec=${state.hwdecCurrent ?: "-"}")
        parts.add("surface=${if (state.surfaceAttached) "att" else "未附着"}")
        state.surfaceId?.takeIf { it.isNotEmpty() }?.let { parts.add("handle=$it") }
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

    /**
     * 初始化顺序：本 init 块必须放在**所有**字段声明之后（Kotlin 按声明
     * 顺序初始化）。buildHierarchy() 会访问 badgeTags 等字段，若在它们
     * 声明前执行会 NPE（v1.5.5 真机回归：「有声无画」）。
     */
    init {
        buildHierarchy()
        setControlsVisible(true)
        mainHandler.postDelayed(tickRunnable, TICK_MS)
    }

    companion object {
        const val SEEK_STEPS = 1000
        const val TICK_MS = 500L
        const val AUTO_HIDE_MS = 5000L

        // 面板类型（与鸿蒙 NativePlayerPanelType 同构）
        const val PANEL_SPEED = "speed"
        const val PANEL_AUDIO = "audio"
        const val PANEL_SUBTITLE = "subtitle"
        const val PANEL_EPISODE = "episode"
        const val PANEL_VERSION = "version"
        const val PANEL_KERNEL = "kernel"
        const val PANEL_DISPLAY = "display"
        const val PANEL_DECODE = "decode"

        val SPEED_STEPS = doubleArrayOf(0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0)
        val DECODE_MODES = arrayOf("auto", "hw", "sw")

    }
}
