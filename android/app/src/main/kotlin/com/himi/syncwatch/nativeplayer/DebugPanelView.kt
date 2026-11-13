package com.himi.syncwatch.nativeplayer

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * 697：播放调试面板（Android 原生 UI）。
 *
 * ## 为什么必须在原生侧重写
 *
 * 安卓原生播放器 UI 是**独立全屏宿主**（[NativePlayerScreenView]），
 * Flutter 播放页在其下方已卸载——Flutter 的 `PlaybackDebugPanel`
 * 在这里根本看不到。而 HDR/DV 排查必须能在真机上直接看参数。
 *
 * ## 与 Flutter / Windows Qt 面板的关系
 *
 * 三端消费**同一份** [AndroidNativePlayerState]（Dart 侧 1s 轮询 mpv
 * 属性后经 MethodChannel 下发），因此显示的数字必然一致——不会出现
 * 「Flutter 说 HDR 直出、原生说 SDR」这种互相矛盾。
 *
 * ## 设计
 *
 * - 半透明（alpha 0.72）+ 圆角 + 绿色描边，与 Flutter/Qt 面板同观感
 * - 标题栏可拖动（`onTouchEvent` 处理 ACTION_MOVE）
 * - 分组可折叠（点击组标题切换）
 * - 状态色：绿=正常、琥珀=可疑、红=异常
 *
 * ## 为什么用 ScrollView + 动态重建
 *
 * 指标每秒刷新，分组折叠状态由本类持有。重建比「逐行 setText」
 * 简单可靠（行数会随 DV/非 DV 变化，静态布局会残留幽灵行）。
 */
@SuppressLint("ViewConstructor")
internal class DebugPanelView(context: Context) : LinearLayout(context) {

    /** 各分组折叠状态（key → true = 已折叠）。 */
    private val collapsed = mutableSetOf<String>()

    private val headerBar = LinearLayout(context)
    private val contentScroll = ScrollView(context)
    private val contentColumn = LinearLayout(context)

    /** 最近一次渲染用的状态（拖动/折叠后重绘用）。 */
    private var lastState: AndroidNativePlayerState? = null

    /**
     * Surface 实际像素尺寸（宽, 高）。
     *
     * 【为什么必须单独传】安卓「画面变糊」的根因是 surface 被写成 1/3
     * 尺寸。这个值只有宿主知道（Dart 侧拿不到原生 Surface 的真实大小），
     * 是核验渲染分辨率的唯一可靠口径。
     */
    private var lastSurfaceSize: Pair<Int, Int> = 0 to 0

    /** 关闭回调（由宿主接回设置项）。 */
    var onClose: (() -> Unit)? = null

    /** 拖动中的按下坐标（相对父容器）。 */
    private var dragStartX = 0f
    private var dragStartY = 0f
    private var dragging = false

    init {
        orientation = VERTICAL
        visibility = GONE
        setBackgroundColor(Color.argb(184, 0, 0, 0)) // 0.72 半透明
        setPadding(dp(8), dp(6), dp(8), dp(8))

        buildHeader()
        buildContent()
    }

    // ── 构建 ────────────────────────────────────────────────────

    private fun buildHeader() {
        headerBar.orientation = HORIZONTAL
        headerBar.gravity = Gravity.CENTER_VERTICAL

        val title = TextView(context).apply {
            text = "播放调试"
            setTextColor(ACCENT_GREEN)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = Typeface.DEFAULT_BOLD
        }
        headerBar.addView(title, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))

        val close = TextView(context).apply {
            text = "✕"
            setTextColor(0x8AFFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setPadding(dp(8), dp(2), dp(2), dp(2))
            setOnClickListener { onClose?.invoke() }
        }
        headerBar.addView(close)

        // 拖动：整条标题栏（关闭按钮有自己的点击处理，不会被吞）
        headerBar.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    dragStartX = event.rawX
                    dragStartY = event.rawY
                    dragging = true
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!dragging) return@setOnTouchListener false
                    x += event.rawX - dragStartX
                    y += event.rawY - dragStartY
                    dragStartX = event.rawX
                    dragStartY = event.rawY
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    dragging = false
                    true
                }
                else -> false
            }
        }

        addView(
            headerBar,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT),
        )
    }

    private fun buildContent() {
        contentColumn.orientation = VERTICAL
        contentScroll.addView(contentColumn)
        contentScroll.isFillViewport = false
        addView(
            contentScroll,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
                .also { it.topMargin = dp(4) },
        )
    }

    /**
     * 限制面板总高（屏高 78%）。
     *
     * 【为什么必须限高】ScrollView 用 WRAP_CONTENT 会撑到内容全高——
     * HDR/DV 分组全展开时接近 30 行，小屏手机上会超出屏幕、底部行
     * 永远看不到。宿主在 addView 后调用本方法按实测屏高设上限。
     */
    fun applyMaxHeight(screenHeightPx: Int) {
        val cap = (screenHeightPx * 0.78f).toInt()
        layoutParams = layoutParams.also { it.height = cap }
    }

    // ── 外部入口 ────────────────────────────────────────────────

    /**
     * 应用新状态并重建面板内容。
     *
     * 由宿主在每次状态快照到达时调用（`showDebug` 为假时隐藏）。
     */
    fun apply(
        state: AndroidNativePlayerState,
        surfaceWidthPx: Int = 0,
        surfaceHeightPx: Int = 0,
    ) {
        // 锁定态隐藏（与顶栏/进度条一致：锁定后只留锁钮）。
        // 【必须在 apply 里判】旧实现在锁定分支单独设 GONE，但每次状态
        // 推送都会再调 apply → 立刻把面板重新显示出来，锁定态形同虚设。
        if (!state.showDebug || state.locked) {
            visibility = GONE
            return
        }
        lastState = state
        lastSurfaceSize = surfaceWidthPx to surfaceHeightPx
        visibility = VISIBLE
        render(state)
    }

    private fun render(state: AndroidNativePlayerState) {
        contentColumn.removeAllViews()
        val fmt = DebugPanelFormat

        // ── 播放 ──
        addGroup(KEY_PLAYBACK, "播放", highlighted = false)
        if (!isCollapsed(KEY_PLAYBACK)) {
            addRow(
                "状态",
                if (state.paused) "PAUSED" else "PLAYING",
                if (state.paused) fmt.SEV_WARN else fmt.SEV_GOOD,
            )
            addRow(
                "位置",
                "${fmt.fmtMs(state.positionMs)} / ${fmt.fmtMs(state.durationMs)}",
            )
            addRow("缓冲", "${state.bufferedMs}ms")
            addRow("倍速", String.format("%.2f", state.speed))
            addRow(
                "实际帧率",
                if (state.estimatedVfFps > 0) {
                    String.format("%.2f", state.estimatedVfFps)
                } else {
                    "-"
                },
            )
            addRow(
                "丢帧",
                "渲染 ${state.frameDropCount} / 解码 ${state.decoderFrameDropCount}",
                fmt.dropSeverity(state.frameDropCount, state.decoderFrameDropCount),
            )
        }

        // ── HDR 输入 ──
        addGroup(KEY_INPUT, "HDR 输入", highlighted = true)
        if (!isCollapsed(KEY_INPUT)) {
            val gamma = state.videoParamsGamma
            addRow(
                "色彩",
                "${fmt.orDash(state.videoParamsPrimaries)} / ${fmt.orDash(gamma)}",
                if (gamma == "pq" || gamma == "hlg") fmt.SEV_GOOD else fmt.SEV_NORMAL,
            )
            addRow(
                "位深",
                "${state.videoParamsBitDepth}bit · " +
                    fmt.orDash(state.videoParamsPixelFormat),
            )
            addRow(
                "峰值",
                // mpv 的 sig-peak 是 max_luma/100 的倍数，×100 才是 nits
                if (state.videoParamsSigPeak > 0) {
                    "${(state.videoParamsSigPeak * 100).toInt()} nits"
                } else {
                    "-"
                },
            )
            addRow("编码", fmt.orDash(state.videoFormat))
            val hwdec = state.hwdecCurrent
            addRow(
                "硬解",
                fmt.orDash(hwdec),
                if (hwdec.isNullOrEmpty() || hwdec == "no") {
                    fmt.SEV_WARN
                } else {
                    fmt.SEV_GOOD
                },
            )
        }

        // ── HDR 输出 ──
        addGroup(KEY_OUTPUT, "HDR 输出", highlighted = true)
        if (!isCollapsed(KEY_OUTPUT)) {
            addRow(
                "路径",
                if (state.hdrOutput) {
                    "Surface · HDR 直出"
                } else {
                    "Surface · SDR（tone map）"
                },
                if (state.hdrOutput) fmt.SEV_GOOD else fmt.SEV_NORMAL,
            )
            addRow(
                "目标",
                "${fmt.orDash(state.targetPrim)} / ${fmt.orDash(state.targetTrc)}",
                if (fmt.isHdrOutput(state.targetTrc)) fmt.SEV_GOOD else fmt.SEV_NORMAL,
            )
            // 【697 真机回归：P5 显示「非 DV 内容」】mpv 的
            // dolby-vision-profile 在自建 libmpv 上可能读不到（恒 0），
            // 必须用 Emby 元数据（dvContent）兜底。
            val isDv = state.doviProfile > 0 || state.dvContent
            val mappingMode =
                if (state.toneMappingMode.isEmpty()) "" else " (${state.toneMappingMode})"
            addRow(
                "映射",
                fmt.orDash(state.toneMapping) + mappingMode,
                if (fmt.dvToneMappingOk(isDv, state.toneMapping)) {
                    fmt.SEV_GOOD
                } else {
                    fmt.SEV_ERROR
                },
            )
            addRow("峰值计算", fmt.orDash(state.hdrComputePeak))
        }

        // ── 杜比视界 ──
        addGroup(KEY_DV, "杜比视界", highlighted = true)
        if (!isCollapsed(KEY_DV)) {
            val isDv = state.doviProfile > 0 || state.dvContent
            addRow(
                "Profile",
                if (state.doviProfile > 0) {
                    fmt.dvProfileText(state.doviProfile, state.doviLevel)
                } else if (state.dvContent) {
                    "DV（Profile 未知 · Emby 元数据）"
                } else {
                    fmt.dvProfileText(0, 0)
                },
            )
            if (isDv) {
                addRow(
                    "识别",
                    if (state.dvContent) {
                        "已识别为 DV"
                    } else {
                        "未识别（按普通 HDR 处理）"
                    },
                    if (state.dvContent) fmt.SEV_GOOD else fmt.SEV_ERROR,
                )
                val supportsDv = fmt.backendSupportsDv(state.gpuContext)
                addRow(
                    "后端",
                    fmt.orDash(state.gpuContext) +
                        if (supportsDv) " · 支持 DV" else " · 不支持 DV",
                    if (supportsDv) fmt.SEV_GOOD else fmt.SEV_WARN,
                )
                // P5 单层 IPT + 后端不支持 → 画面必偏色
                if (state.doviProfile == 5 && !supportsDv) {
                    addRow("P5 风险", "后端不支持 DV，画面会偏色", fmt.SEV_ERROR)
                }
            }
        }

        // ── 渲染管线 ──
        addGroup(KEY_PIPELINE, "渲染管线", highlighted = false)
        if (!isCollapsed(KEY_PIPELINE)) {
            addRow("vo", fmt.orDash(state.currentVo, state.voConfigured))
            addRow("gpu-api", fmt.orDash(state.gpuApi))
            addRow("gpu-context", fmt.orDash(state.gpuContext))
            addRow("输出", fmt.orDash(state.videoOutputActual))
            val (sw, sh) = lastSurfaceSize
            if (sw > 0 && sh > 0) addRow("Surface 尺寸", "${sw}x$sh")
            if (!state.surfaceAttached) {
                addRow("Surface", "未附着", fmt.SEV_ERROR)
            }
            state.surfaceError?.takeIf { it.isNotEmpty() }?.let {
                addRow("Surface 错误", it, fmt.SEV_ERROR)
            }
        }
    }

    // ── 行/组构建 ───────────────────────────────────────────────

    private fun addGroup(key: String, title: String, highlighted: Boolean) {
        val row = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(5), 0, dp(2))
            setOnClickListener {
                if (collapsed.contains(key)) {
                    collapsed.remove(key)
                } else {
                    collapsed.add(key)
                }
                lastState?.let { render(it) }
            }
        }
        val arrow = TextView(context).apply {
            text = if (collapsed.contains(key)) "\u203A" else "\u2304"
            setTextColor(if (highlighted) ACCENT_GREEN else 0x61FFFFFF)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        }
        row.addView(arrow)
        val label = TextView(context).apply {
            text = title
            // 【必须 .toInt()】0xB3FFFFFF > Int.MAX_VALUE，Kotlin 会推断成
            // Long → `setTextColor` 匹配不到重载（编译失败）。
            setTextColor(if (highlighted) ACCENT_GREEN else 0xB3FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            typeface = Typeface.DEFAULT_BOLD
        }
        row.addView(label)
        contentColumn.addView(row)
    }

    private fun addRow(label: String, value: String, severity: String = DebugPanelFormat.SEV_NORMAL) {
        val row = LinearLayout(context).apply {
            orientation = HORIZONTAL
            setPadding(dp(14), dp(1), 0, dp(1))
        }
        val labelView = TextView(context).apply {
            text = label
            setTextColor(0x61FFFFFF)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
            isSingleLine = true
        }
        row.addView(labelView, LayoutParams(dp(66), LayoutParams.WRAP_CONTENT))

        val valueView = TextView(context).apply {
            text = value
            setTextColor(severityColor(severity))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
            isSingleLine = true
        }
        row.addView(valueView, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
        contentColumn.addView(row)
    }

    // ── 工具 ────────────────────────────────────────────────────

    private fun isCollapsed(key: String) = collapsed.contains(key)

    private fun severityColor(severity: String): Int = when (severity) {
        DebugPanelFormat.SEV_GOOD -> 0xFF6EE7A0.toInt()
        DebugPanelFormat.SEV_WARN -> 0xFFFBBF24.toInt()
        DebugPanelFormat.SEV_ERROR -> 0xFFF87171.toInt()
        else -> 0xB3FFFFFF.toInt()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private companion object {
        /** 面板主色（与 Flutter/Qt 面板的 greenAccent 一致）。 */
        const val ACCENT_GREEN = 0xFF66FF99.toInt()

        // 分组折叠键（用常量而非标题反查：标题是展示文案，改名不该破坏折叠态）
        const val KEY_PLAYBACK = "playback"
        const val KEY_INPUT = "input"
        const val KEY_OUTPUT = "output"
        const val KEY_DV = "dv"
        const val KEY_PIPELINE = "pipeline"
    }
}
