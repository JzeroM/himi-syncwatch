package com.himi.syncwatch.nativeplayer

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
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

    /** 片头片尾卡片的二次确认上下文（null = 无卡片）。 */
    private var segmentConfirmKind: String? = null

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

    /** 玻璃胶囊/浮层背景：着色 + rim 描边 + 圆角（跨窗口无法真模糊）。 */
    private fun glassBackground(radiusDp: Int, tint: Int = NPTheme.PANEL_TINT): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(radiusDp).toFloat()
            setColor(tint)
            setStroke(dp(1), NPTheme.RIM)
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
            if (decodePopoverOpen || segmentConfirmKind != null) {
                decodePopoverOpen = false
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
    private val diagText = TextView(context)
    private val bufferingView = TextView(context)
    private val hdrBadge = TextView(context)

    // 面板层
    private val panelScrim = View(context).apply {
        setBackgroundColor(Color.TRANSPARENT)
        visibility = GONE
        setOnClickListener { closePanel() }
    }
    private val panelContainer = LinearLayout(context)
    private val decodePopover = LinearLayout(context)
    private val segmentCard = LinearLayout(context)
    private val segmentScrim = View(context).apply {
        setBackgroundColor(Color.TRANSPARENT)
        visibility = GONE
        setOnClickListener {
            segmentConfirmKind = null
            renderOverlays()
        }
    }

    init {
        buildHierarchy()
        setControlsVisible(true)
        mainHandler.postDelayed(tickRunnable, TICK_MS)
    }

    // ── 视图装配 ──────────────────────────────────────────────────

    /** 组装层级：tapLayer → topBar → bottomBar → 面板层。 */
    private fun buildHierarchy() {
        addView(
            tapLayer,
            lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )

        addView(topBar, lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.TOP))
        addView(bottomBar, lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))

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
        topBar.orientation = LinearLayout.HORIZONTAL
        topBar.gravity = Gravity.CENTER_VERTICAL
        topBar.setPadding(dp(12), dp(6), dp(12), dp(6))
        topBar.background = barGradient(topSolid = true)

        backButton.text = String(Character.toChars(NativePlayerIcons.ICON_ARROW_BACK))
        backButton.typeface = NativePlayerIcons.typeface(context)
        backButton.setTextColor(Color.WHITE)
        backButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        backButton.gravity = Gravity.CENTER
        backButton.setPadding(dp(6), dp(6), dp(6), dp(6))
        backButton.isClickable = true
        backButton.setOnClickListener { listener?.onBack() }
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

        // 网速（12sp white70）
        networkText.setTextColor(NPTheme.WHITE_70)
        networkText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        networkText.gravity = Gravity.CENTER_VERTICAL
        networkText.visibility = GONE
        topBar.addView(networkText, lp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(40)))

        // 倍速胶囊（手机）
        speedChip.orientation = LinearLayout.HORIZONTAL
        speedChip.gravity = Gravity.CENTER
        speedChip.setPadding(dp(8), dp(4), dp(8), dp(4))
        speedChip.isClickable = true
        speedChip.background = glassBackground(10)
        speedChip.setOnClickListener { listener?.onCycleSpeed() }
        speedChip.addView(iconView(NativePlayerIcons.ICON_SPEED, 16f), lp(dp(20), dp(20)))
        speedLabel.setTextColor(Color.WHITE)
        speedLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        speedChip.addView(
            speedLabel,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .also { it.marginStart = dp(4) },
        )
        topBar.addView(speedChip, lp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)))

        // 内核胶囊（显示短名，点击打开右侧内核面板）
        kernelChip.setTextColor(Color.WHITE)
        kernelChip.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        kernelChip.gravity = Gravity.CENTER
        kernelChip.setPadding(dp(9), dp(6), dp(9), dp(6))
        kernelChip.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        kernelChip.background = glassBackground(10)
        kernelChip.isClickable = true
        kernelChip.setOnClickListener { openPanel(PANEL_KERNEL) }
        topBar.addView(kernelChip, lp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(34)))

        // 字幕样式胶囊（tune 图标，点击打开右侧显示调节面板）
        configureIconChip(subtitleStyleChip, NativePlayerIcons.ICON_TUNE)
        subtitleStyleChip.setOnClickListener { openPanel(PANEL_DISPLAY) }
        topBar.addView(subtitleStyleChip, lp(dp(30), dp(30)))

        // 解码胶囊（memory 图标，点击打开右侧解码模式面板）
        configureIconChip(decodeChip, NativePlayerIcons.ICON_MEMORY)
        decodeChip.setOnClickListener { openPanel(PANEL_DECODE) }
        topBar.addView(decodeChip, lp(dp(30), dp(30)))

        // 画面比例（循环切换）
        videoFitIcon.setTextColor(Color.WHITE)
        videoFitIcon.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        videoFitIcon.gravity = Gravity.CENTER
        videoFitIcon.setPadding(dp(6), dp(6), dp(6), dp(6))
        videoFitIcon.isClickable = true
        videoFitIcon.setOnClickListener { listener?.onCycleVideoFit() }
        topBar.addView(videoFitIcon, lp(dp(34), dp(34)))

        // 手动转屏（仅手机）
        rotateIcon.text = String(Character.toChars(NativePlayerIcons.ICON_ROTATE))
        rotateIcon.typeface = NativePlayerIcons.typeface(context)
        rotateIcon.setTextColor(Color.WHITE)
        rotateIcon.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        rotateIcon.gravity = Gravity.CENTER
        rotateIcon.setPadding(dp(6), dp(6), dp(6), dp(6))
        rotateIcon.isClickable = true
        rotateIcon.setOnClickListener { listener?.onToggleOrientation() }
        topBar.addView(rotateIcon, lp(dp(34), dp(34)))

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
        chip.background = glassBackground(10)
        chip.isClickable = true
    }

    // ── 交互绑定（可重入：手机 ↔ TV 切换时重建布局后重绑）──────────

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

    /** 底栏：Logo / 进度条 / 播放组（手机居中·TV 置左）/ 右侧图标组 / 诊断行。 */
    private fun configureBottomBar() {
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
        seekRow.addView(
            seekBar,
            LinearLayout.LayoutParams(0, dp(NPTheme.SEEK_TRACK + 16), 1f).also {
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

        // 控件行：FrameLayout 承载 3 组（leading START / transport CENTER / trailing END）
        buttonRow.layoutParams = lp(LayoutParams.MATCH_PARENT, dp(NPTheme.TRANSPORT_PLAY + 8))

        // leading 组（锁钮）
        leadingGroup.orientation = LinearLayout.HORIZONTAL
        leadingGroup.gravity = Gravity.CENTER_VERTICAL
        lockButton.text = String(Character.toChars(NativePlayerIcons.ICON_LOCK))
        lockButton.typeface = NativePlayerIcons.typeface(context)
        lockButton.setTextColor(Color.WHITE)
        lockButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.LOCK_ICON.toFloat())
        lockButton.gravity = Gravity.CENTER
        lockButton.setPadding(dp(8), dp(8), dp(8), dp(8))
        lockButton.isClickable = true
        lockButton.setOnClickListener { listener?.onToggleLock() }
        leadingGroup.addView(lockButton, lp(dp(44), dp(44)))

        // transport 组（上一集 / 播放暂停 / 下一集）
        transportGroup.orientation = LinearLayout.HORIZONTAL
        transportGroup.gravity = Gravity.CENTER_VERTICAL
        configureTransportButton(prevButton, NativePlayerIcons.ICON_SKIP_PREVIOUS, NPTheme.TRANSPORT_SIDE)
        configureTransportButton(playPauseButton, NativePlayerIcons.ICON_PLAY_CIRCLE, NPTheme.TRANSPORT_PLAY)
        configureTransportButton(nextButton, NativePlayerIcons.ICON_SKIP_NEXT, NPTheme.TRANSPORT_SIDE)
        transportGroup.addView(prevButton, lp(dp(NPTheme.TRANSPORT_SIDE), dp(NPTheme.TRANSPORT_SIDE)))
        transportGroup.addView(
            playPauseButton,
            lp(dp(NPTheme.TRANSPORT_PLAY), dp(NPTheme.TRANSPORT_PLAY)).also {
                it.marginStart = dp(NPTheme.TRANSPORT_GAP)
                it.marginEnd = dp(NPTheme.TRANSPORT_GAP)
            },
        )
        transportGroup.addView(nextButton, lp(dp(NPTheme.TRANSPORT_SIDE), dp(NPTheme.TRANSPORT_SIDE)))

        // trailing 组（弹幕 / 版本 / 显示调节 / 字幕 / 音轨 / 选集 / 倍速 / 面板）
        trailingGroup.orientation = LinearLayout.HORIZONTAL
        trailingGroup.gravity = Gravity.CENTER_VERTICAL
        trailingGroup.addView(
            iconButton(NativePlayerIcons.ICON_DANMAKU_ON) {
                listener?.onToggleDanmaku()
                scheduleAutoHide()
            },
            lp(dp(32), dp(32)),
        )
        trailingGroup.addView(
            badgeButton(
                NativePlayerIcons.ICON_HIGH_QUALITY,
                { lastState.versions.size.takeIf { n -> n > 1 }?.toString() },
            ) { openPanel(PANEL_VERSION) },
            lp(dp(32), dp(32)),
        )
        displayAdjustButton = iconButton(NativePlayerIcons.ICON_TUNE) { openPanel(PANEL_DISPLAY) }
        trailingGroup.addView(displayAdjustButton!!, lp(dp(32), dp(32)))
        trailingGroup.addView(
            badgeButton(NativePlayerIcons.ICON_SUBTITLES, { lastState.subtitleStreamCount.toString() }) {
                openPanel(PANEL_SUBTITLE)
            },
            lp(dp(32), dp(32)),
        )
        trailingGroup.addView(
            badgeButton(NativePlayerIcons.ICON_AUDIO_TRACK, { lastState.audioStreamCount.toString() }) {
                openPanel(PANEL_AUDIO)
            },
            lp(dp(32), dp(32)),
        )
        trailingGroup.addView(
            badgeButton(NativePlayerIcons.ICON_PLAYLIST_PLAY, { lastState.episodes.size.toString() }) {
                openPanel(PANEL_EPISODE)
            },
            lp(dp(32), dp(32)),
        )
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
        trailingGroup.addView(bottomSpeedChip, lp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(34)))

        // 面板切换（房间模式，点开右侧资源面板）
        panelToggleButton.text = String(Character.toChars(NativePlayerIcons.ICON_OPEN_IN_FULL))
        panelToggleButton.typeface = NativePlayerIcons.typeface(context)
        panelToggleButton.setTextColor(Color.WHITE)
        panelToggleButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
        panelToggleButton.gravity = Gravity.CENTER
        panelToggleButton.setPadding(dp(4), dp(4), dp(4), dp(4))
        panelToggleButton.isClickable = true
        panelToggleButton.setOnClickListener { listener?.onBack() }
        trailingGroup.addView(panelToggleButton, lp(dp(32), dp(32)))

        // HDR 徽标
        hdrBadge.text = "HDR"
        hdrBadge.setTextColor(Color.BLACK)
        hdrBadge.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        hdrBadge.setBackgroundColor(0xFFFFD54F.toInt())
        hdrBadge.setPadding(dp(6), dp(2), dp(6), dp(2))
        hdrBadge.visibility = GONE

        // 组装三组
        val leadingLp = FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER_VERTICAL or Gravity.START)
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
        bottomBar.addView(buttonRow, lp(LayoutParams.MATCH_PARENT, dp(NPTheme.TRANSPORT_PLAY + 8)))

        // 诊断行（默认隐藏）
        diagText.setTextColor(0x99FFFFFF.toInt())
        diagText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
        diagText.maxLines = 2
        diagText.visibility = GONE
        bottomBar.addView(diagText, lp(LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
    }

    // ── 控件工厂 ──────────────────────────────────────────────────

    /** 右侧纯图标按钮（24dp 图标 + 4dp 内边距，与 Flutter _buildControlButton 一致）。 */
    private fun iconButton(codePoint: Int, onClick: () -> Unit): TextView =
        TextView(context).apply {
            text = String(Character.toChars(codePoint))
            typeface = NativePlayerIcons.typeface(context)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            gravity = Gravity.CENTER
            setPadding(dp(4), dp(4), dp(4), dp(4))
            isClickable = true
            setOnClickListener { onClick() }
        }

    /**
     * 带角标的右侧图标按钮：图标 24dp，角标为 9sp 文字 + #6366F1 圆底，
     * 贴在图标右上（Flutter Stack + Positioned(right:-6,top:-4)）。
     */
    private fun badgeButton(
        codePoint: Int,
        badgeProvider: () -> String?,
        onClick: () -> Unit,
    ): FrameLayout {
        val host = FrameLayout(context)
        host.addView(iconButton(codePoint, onClick), lp(dp(24), dp(24)))
        val badge = TextView(context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.BADGE_FONT)
            gravity = Gravity.CENTER
            setPadding(dp(3), dp(1), dp(3), dp(1))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(NPTheme.ACCENT)
            }
        }
        host.addView(badge, lp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(NPTheme.BADGE_MIN)))
        // 角标数量在 applyState 中刷新
        badgeTags[badge] = badgeProvider
        return host
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
        button.setPadding(dp(4), dp(4), dp(4), dp(4))
        button.isClickable = true
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
     * 面板层总渲染：按 activePanel / decodePopoverOpen / segmentConfirmKind
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
            panelContainer.background = glassBackground(NPTheme.RADIUS_PANEL)
            panelContainer.layoutParams = lp(
                panelWidthDp(),
                LayoutParams.WRAP_CONTENT,
            ).also {
                it.topMargin = dp(NPTheme.PANEL_TOP_OFFSET)
                it.bottomMargin = dp(NPTheme.PANEL_BOTTOM_OFFSET)
                it.marginEnd = dp(NPTheme.PANEL_RIGHT)
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
        if (segmentConfirmKind != null) {
            renderSegmentCard()
        } else {
            segmentCard.visibility = GONE
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
            setPadding(dp(NPTheme.PANEL_PAD_H), 0, dp(NPTheme.PANEL_PAD_H), dp(4))
        }

    /** 面板内容滚动包裹（限高）。 */
    private fun scrollWrap(content: View): ScrollView =
        ScrollView(context).apply {
            isFillViewport = true
            addView(content)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
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
                    text = if (selected) "✓" else ""
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
        segmentCard.background = glassBackground(NPTheme.RADIUS_CARD)
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
        actions.addView(segmentAction("取消") { segmentConfirmKind = null; renderOverlays() })
        actions.addView(segmentAction("清除") {
            listener?.onClearSegmentMark(kind)
            segmentConfirmKind = null
            renderOverlays()
        })
        actions.addView(segmentAction("更新") {
            listener?.onSetSegmentMark(kind, lastState.positionMs.toLong())
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

        // 角标
        badgeTags.forEach { (badge, provider) ->
            val text = provider()
            badge.text = text ?: ""
            badge.visibility = if (text.isNullOrEmpty()) GONE else VISIBLE
            badge.layoutParams = lp(dp(14 + text.orEmpty().length * 5), dp(NPTheme.BADGE_MIN))
        }

        // 顶栏网速
        networkText.text = state.networkSpeedText ?: ""
        networkText.visibility = if (state.networkSpeedText != null) VISIBLE else GONE

        // 时间数显
        if (!dragging) {
            val pos = state.positionAt(now, lastStateAtMs)
            positionLabel.text = AndroidNativePlayerState.formatPlayerTime(pos)
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

        // TV / 手机布局差异
        applyLayoutMode(state)

        // 面板开着时重建（高亮跟随）
        if (activePanel != null || decodePopoverOpen || segmentConfirmKind != null) {
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

        // 底栏可见项
        lockButton.visibility = if (!tv) VISIBLE else GONE
        bottomSpeedChip.visibility = if (tv && !state.isRoom) VISIBLE else GONE
        displayAdjustButton?.visibility = if (tv) VISIBLE else GONE
        panelToggleButton.visibility = if (state.isRoom) VISIBLE else GONE
        hdrBadge.visibility = if (state.hdrOutput) VISIBLE else GONE

        // Logo（房间模式/无图时隐藏）
        val showLogo = state.logoUrl != null && state.logoUrl!!.isNotEmpty() && !state.isRoom
        logoImage.visibility = if (showLogo) VISIBLE else GONE
        logoSpacer.visibility = if (showLogo) GONE else VISIBLE

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
