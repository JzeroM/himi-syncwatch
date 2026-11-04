package com.himi.syncwatch.nativeplayer

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
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
    /** surface 视频层提供者（液态玻璃 PixelCopy 采样源；null = 降级 tint）。 */
    private val surfaceViewProvider: () -> android.view.SurfaceView? = { null },
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

        /** 字幕面板「加载本地字幕文件...」（Dart `_loadLocalSubtitle`）。 */
        fun onAddSubtitle()
        fun onSelectEpisode(index: Int)
        fun onSelectVersion(index: Int)
        fun onSwitchEngine(engine: String)
        fun onSetDecodeMode(mode: String)
        fun onToggleDanmaku()
        fun onCycleVideoFit()
        fun onToggleOrientation()
        fun onToggleLock()
        fun onShare()
        fun onAdjustDisplay(key: String, value: Double)

        /** 显示调节「恢复默认」（scope: 'subtitle' 字幕段 / 'danmaku' 弹幕段）。 */
        fun onResetDisplay(scope: String)
        fun onSetSegmentMark(kind: String, positionMs: Long)
        fun onClearSegmentMark(kind: String)

        /** 跳过片头/片尾胶囊点击（Dart `_performSkipSegment` 执行跳转）。 */
        fun onSkipSegment()
        fun onOpenPanel(panel: String)
        fun onClosePanel()

        /** 房间模式「资源面板」开关（对齐 Flutter `_showPanel`）。 */
        fun onToggleResourcePanel()

        // ── 房间资源面板交互（590）──

        /** 分组折叠切换（Dart 持有折叠态，原生只发意图）。 */
        fun onToggleResourceGroup(index: Int)

        /** 季分组折叠切换。 */
        fun onToggleResourceSeason(groupIndex: Int, seasonIndex: Int)

        /** 从资源列表移除一条（房主，对应 Flutter `_removeEpisode`）。 */
        fun onRemoveResourceEpisode(index: Int)

        /** 聚合搜索加资源（房主，对应 Flutter `pushRoomResourceSearch`）。 */
        fun onOpenResourceSearch()

        /**
         * 视频区右侧留白（像素，590）。
         *
         * 房间资源面板展开时 = 面板宽，宿主据此收窄 surface 窗，
         * 让视频只占左侧（与 Flutter `Row(Expanded(video), SizedBox(320))`
         * 等价）。收起时传 0（恢复全屏）。
         */
        fun onVideoInsetRight(insetPx: Int)

        /** 手势：相对 seek（横拖/甩动；对齐 Flutter `_seekRelative`，±60s 上限）。 */
        fun onSeekRelative(deltaMs: Long)

        /** 手势：左侧纵拖调亮度（增量 0..1，写入控件窗 `screenBrightness`）。 */
        fun onGestureBrightness(delta01: Double)

        /**
         * 手势：右侧纵拖调音量（增量 0..1）。
         * 宿主按本地乐观值累加后发 `setVolume`。
         */
        fun onGestureVolumeDelta(delta01: Double)

        /** 手势：长按临时倍速（true=升到 2×，false=还原到长按前档位）。 */
        fun onSpeedBoost(active: Boolean)
    }

    // ── 状态 ──────────────────────────────────────────────────────

    private var listener: Listener? = null
    private var controlsVisible = true
    private var hideDeadlineMs = 0L
    private var dragging = false

    /**
     * seek 提交后的保护目标（毫秒；null = 无保护）。
     *
     * 松手时 `onCommit` 只是把目标发给 Dart，权威位置要等 mpv seek 完成
     * 回读（200~500ms）。旧实现期间 500ms tick 的 `applyState()` 会用**旧
     * 位置**覆盖滑杆 value → 真机观感「拖一下就弹回之前位置」。保护期内
     * 滑杆保持目标值；收到接近目标的权威位置（或超时 2s）即释放。
     */
    private var pendingSeekMs: Long? = null

    /** 保护窗起点（超时判定用）。 */
    private var pendingSeekAtMs = 0L

    /** 保护窗时长：seek 回读最长等待（超时后交还权威值，防永久锁死）。 */
    private val pendingSeekTimeoutMs = 2000L
    private var lastState: AndroidNativePlayerState = AndroidNativePlayerState()
    private var lastStateAtMs: Long = 0L
    private var lastTvMode = false

    /**
     * 房间资源面板数据签名（只在结构/折叠态/当前集变化时重建列表）。
     *
     * 【真机回归：资源面板全空】初值必须是**不可能与真实数据相等**的哨兵。
     * 旧初值 `""` 与「零分组」产生的签名 `""` 相等 → `buildRoomPanelList`
     * 从未执行 → 连「暂无资源」空态都不渲染，列表区纯空白。
     */
    private var roomPanelSig: String = ROOM_SIG_UNBUILT

    /**
     * 播报板数据签名。
     *
     * 同上：初值 `""` 与「零播报」的 `joinToString("|") == ""` 相等 → 从不
     * 重建 → 只显示标题 `播报 (0)`、列表空白。
     */
    private var roomBroadcastSig: String = ROOM_SIG_UNBUILT

    /** 上次通知宿主的视频右侧留白（像素，0 = 全屏）。 */
    private var lastVideoInsetRightPx: Int = -1

    /** 当前打开的二级面板（null = 无）。 */
    private var activePanel: String? = null

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

    /**
     * 安全区（刘海/挖孔/手势条）内边距，像素。由宿主在窗口 insets 变化时
     * 喂入（[applySafeInsets]）。
     *
     * Flutter 侧对应 `MediaQuery.of(context).padding.top/bottom`：顶栏、
     * 面板几何、底栏内边距都要叠加它（B5/B11）。旧实现固定 0 → 横屏刘海机
     * 上顶栏被挖孔压住、面板顶到屏幕边缘。
     */
    private var safeInsetTopPx = 0
    private var safeInsetBottomPx = 0

    /** 面板顶部避让量（仅安全区；Flutter `safeTop + 48` 的 safeTop 部分）。 */
    private fun safeTopPx(): Int = safeInsetTopPx

    /** 面板底部避让量（手势条 / 横屏侧边安全区）。 */
    private fun safeBottomPx(): Int = safeInsetBottomPx

    /** 宿主喂入安全区（insets 变化时调用），并触发重排。 */
    fun applySafeInsets(topPx: Int, bottomPx: Int) {
        val t = topPx.coerceAtLeast(0)
        val b = bottomPx.coerceAtLeast(0)
        if (t == safeInsetTopPx && b == safeInsetBottomPx) return
        safeInsetTopPx = t
        safeInsetBottomPx = b
        applyBarInsets()
        requestLayout()
    }

    /** 顶/底栏内边距统一按安全区算（重排时也走这里，避免被覆盖）。 */
    private fun applyBarInsets() {
        topBar.setPadding(dp(12), dp(6) + safeInsetTopPx, dp(12), dp(6))
        bottomBar.setPadding(
            dp(NPTheme.BAR_PAD_H),
            dp(NPTheme.BAR_PAD_TOP),
            dp(NPTheme.BAR_PAD_H),
            dp(NPTheme.BAR_PAD_BOTTOM) + safeInsetBottomPx,
        )
    }

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
                    // 对齐鸿蒙 pressedFeedback：opacity 0.5 + scale 0.92。
                    // 先 cancel：applyState 的 500ms 重建会打断进行中的动画
                    //（残留半透明/缩放，观感像「控件没反应」）。
                    v.animate().cancel()
                    v.animate().alpha(0.5f).scaleX(0.92f).scaleY(0.92f)
                        .setDuration(90).start()
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    v.animate().cancel()
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

    /** 顶栏/底栏渐变：顶栏 顶部80%黑→透明；底栏 透明→底部85%黑。
     *  alpha 分别 0xCC / 0xD9，与 Flutter `_buildTopBar`（black@0.8）与
     *  `_buildControls`（black@0.85）逐项同值。 */
    private fun barGradient(topSolid: Boolean): GradientDrawable =
        GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            if (topSolid) {
                intArrayOf(NPTheme.BAR_GRADIENT_SOLID, NPTheme.BAR_GRADIENT_CLEAR)
            } else {
                intArrayOf(NPTheme.BAR_GRADIENT_CLEAR, NPTheme.BAR_BOTTOM_SOLID)
            },
        ).apply { gradientType = GradientDrawable.LINEAR_GRADIENT }

    fun setListener(listener: Listener?) {
        this.listener = listener
    }

    // ── TV 按键路由访问器（见 [TvKeyRouter]）────────────────────

    /** 控件是否可见（TV 方向键语义分支用）。 */
    fun isControlsVisible(): Boolean = controlsVisible

    /** 进度条（TV 焦点在其上时左右键改判为快进退）。 */
    fun seekBarButton(): View = seekBar

    /** 播放/暂停键（进度条上按下键时定向跳焦目标）。 */
    fun playPauseView(): View = playPauseButton

    /** 顺延自动隐藏计时（与控件交互时调用）。 */
    fun extendAutoHide() = scheduleAutoHide()

    /**
     * TV 按键路由（对齐 Flutter `PlayerHotkey`）。
     *
     * 覆写 [onKeyDown] 而非用 `Dialog.setOnKeyListener`：后者只在**焦点视图
     * 未消费**按键时触发，而我们要拦的正是「进度条焦点上的左右键」——
     * SeekBar 会自己消费掉。`onKeyDown` 在事件进入子视图链之前调用，
     * 优先级正确。
     */
    private val tvKeyRouter = TvKeyRouter(
        rootProvider = { this },
        seekBarProvider = { seekBar },
        playPauseProvider = { playPauseButton },
        // 跨界 hop 两端（Flutter hopRight/hopLeft）：左组尾 = 传输组末项
        //（nextButton，无下一集时是空占位仍可聚焦）；右组头 = trailing 首项。
        leftTailProvider = { nextButton },
        rightHeadProvider = { danmakuButton },
        controlsVisibleProvider = { controlsVisible },
        onSeekRelative = { deltaMs ->
            listener?.onSeekRelative(deltaMs)
            val seconds = Math.round(deltaMs / 1000f)
            showGestureHint("${if (seconds > 0) "+" else ""}${seconds}s")
        },
        onVolumeDelta = { deltaPercent ->
            // TV 遥控器音量键：步长 5%（Flutter `_volumeStep`）。
            volume01 = (volume01 + deltaPercent / 100.0).coerceIn(0.0, 1.0)
            listener?.onGestureVolumeDelta(deltaPercent / 100.0)
            showVerticalBar(onLeftSide = false)
        },
        onTogglePlay = { listener?.onTogglePlay() },
        onShowControls = { setControlsVisible(true) },
        onExtendAutoHide = { scheduleAutoHide() },
    )

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        // TV 模式才接管遥控器语义；手机（触摸）不拦按键。
        if (lastState.tvMode && tvKeyRouter.handleKey(keyCode, event)) {
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    // ── 视图 ──────────────────────────────────────────────────────

    /**
     * 视频区手势层：对齐 Flutter `VideoGestureLayer` + `player_screen.dart`
     * 的手势语义（§手势控制）。
     *
     * - 单击：面板/浮层打开时先关；否则切换控件显隐
     * - 双击：播放/暂停（锁定中不解绑）
     * - 横拖：累计每 100px 预览 ±5s，松手 seek（上限 ±60s；锁定中不解绑）
     * - 纵拖：左半屏亮度、右半屏音量（锁定中不解绑）
     * - 长按：临时 2× 倍速（松手还原；锁定中不解绑）
     *
     * 锁定态只保留单击（Flutter：`_lockController.locked ? null : ...`）。
     */
    private val tapLayer = View(context).apply {
        isClickable = true
        setBackgroundColor(Color.TRANSPARENT)
        setOnClickListener {
            // 长按手势（片头片尾标记/倍速）结束后 GestureDetector 仍会派发
            // tap → 会把刚弹出的片头片尾卡立刻收走（真机回归「面板弹出就
            // 自动收回」）。长按后短窗内忽略 tap。
            if (System.currentTimeMillis() < suppressTapUntilMs) return@setOnClickListener
            // 锁定态点屏不显示顶栏（Flutter：只浮现左缘解锁钮）。
            if (lastState.locked) return@setOnClickListener
            if (activePanel != null) {
                closePanel()
                return@setOnClickListener
            }
            // 片头片尾卡的关闭只由 segmentScrim 点击负责（这里不再处理，
            // 否则开卡手势自带的 tap 会立刻把它关掉）。
            setControlsVisible(!controlsVisible)
        }
    }

    /** 长按结束后抑制 tap 的截止时刻（防同一手势的 tap 关掉刚开的面板）。 */
    private var suppressTapUntilMs = 0L

    // ── 手势识别 ────────────────────────────────────────────────

    /** 横拖累计像素（每 100px 换算一次 ±5s 预览/seek）。 */
    private var hDragAccumPx = 0f

    /** 横拖累加器是否已在 UP 时提交（防 onFling 速度回退二次 seek）。 */
    private var hDragCommitted = false

    /**
     * 手势方向锁（591，真机回归「上滑会改进度」根因）。
     *
     * 旧实现在 `onScroll` 里**每帧**用 `|dx| > |dy|` 重新判定方向：`dx/dy`
     * 是 `e1→e2` 的总位移，斜着上滑时只要某一帧 `|dx| > |dy|`（先横后竖的
     * 抖动）就切进横拖分支累加 `hDragAccumPx` → 触发 seek 预览，松手时
     * `ACTION_UP` 又提交一次 seek。
     *
     * Flutter 靠手势竞技场（纵向 recognizer 胜出后横向被淘汰）天然互斥；
     * 安卓这里用单个 `onScroll` 自判方向，必须**一次性锁定**：
     * 首次超 slop 时定轴，之后只走该轴分支，不再重判。
     */
    private var dragAxis: Int = AXIS_NONE

    /** 长按临时倍速的基准档位（松手还原用）。 */
    private var boostBaseSpeed = 1.0

    /** 长按临时倍速是否激活中（松手需还原）。 */
    private var boostActive = false

    /** 纵拖起始点在左半屏（亮度）还是右半屏（音量）。 */
    private var dragOnLeftSide = false

    /** 手势提示文本（居中显示；null = 隐藏）。 */
    private val gestureHint = TextView(context).apply {
        visibility = GONE
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER
        setPadding(dp(16), dp(8), dp(16), dp(8))
        typeface = Typeface.DEFAULT_BOLD
        background = hintBackground()
    }

    /** 提示胶囊底（黑 55% + 圆角 16；Flutter `_buildGestureHint`）。 */
    private fun hintBackground(): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(16).toFloat()
            // 注意：0x8C000000 超出 Int 范围，Kotlin 推断为 Long，
            // 必须显式 toInt()（CI 实测编译错误）。
            setColor(0x8C000000.toInt())
        }

    /** 手势提示自动隐藏（每个提示各自持有，互不干扰）。 */
    private var hideGestureHint: Runnable? = null
    private var hideVerticalBar: Runnable? = null

    private fun showHintFor(
        text: String,
        ms: Long,
        iconFont: Typeface?,
        withBackground: Boolean = true,
    ) {
        hideGestureHint?.let { mainHandler.removeCallbacks(it) }
        gestureHint.text = text
        gestureHint.typeface = iconFont ?: Typeface.DEFAULT_BOLD
        // 图标态 48sp（Flutter `Icon(size: 48)`）；文本态 16sp。
        gestureHint.setTextSize(
            TypedValue.COMPLEX_UNIT_SP,
            if (iconFont != null) GESTURE_ICON_SIZE_SP else GESTURE_TEXT_SIZE_SP,
        )
        gestureHint.background = if (withBackground) hintBackground() else null
        gestureHint.visibility = VISIBLE
        if (ms <= 0L) return
        val hide = Runnable {
            gestureHint.visibility = GONE
            hideGestureHint = null
        }
        hideGestureHint = hide
        mainHandler.postDelayed(hide, ms)
    }

    /** 手势提示文本（800ms 后隐藏，与 Flutter `_showGestureHint` 同）。 */
    private fun showGestureHint(text: String) =
        showHintFor(text, GESTURE_HINT_TEXT_MS, null)

    /**
     * 手势提示图标（500ms 后隐藏，与 Flutter `_showGestureIcon` 同）。
     * 图标态**不带胶囊底**（Flutter 是裸 `Icon(white70, 48)`）。
     */
    private fun showGestureIcon(codePoint: Int) =
        showHintFor(
            String(Character.toChars(codePoint)),
            GESTURE_HINT_ICON_MS,
            NativePlayerIcons.typeface(context),
            withBackground = false,
        )

    /**
     * 长按标记片头/片尾（对齐 Flutter `_onSegmentMarkSelected` + `_markSegmentAt`
     * / 鸿蒙 `markSegmentFromGesture`）：校验（0 秒 / 片头 3 秒门槛 /
     * 结尾）→ 无旧标记直接标记并提示「已设置…」；有旧标记直开二次确认卡
     * （更新 / 清除 / 取消）。
     */
    /**
     * 片头/片尾标记范围校验（588）：片头结束点 ≤ 总时长 10%、片尾开始点
     * ≥ 总时长 70%。返回拒绝文案，null = 通过；时长未知（<=0）不校验。
     *
     * 与 Flutter `SegmentMarkRules.rejectReason` / 鸿蒙 `segmentMarkReject`
     * 逐字逐值一致。Dart 仍是权威校验点，这里前置拦截只为避免原生先弹
     * 「已设置…」乐观提示后被 Dart 拒绝（观感前后矛盾）。
     */
    internal fun segmentMarkReject(kind: String, positionMs: Long, durationMs: Long): String? {
        if (durationMs <= 0L) return null
        return if (kind == "intro") {
            if (positionMs > durationMs * 10 / 100) "片头结束点不能超过总时长的 10%" else null
        } else {
            if (positionMs < (durationMs * 70 + 99) / 100) "片尾开始点不能低于总时长的 70%" else null
        }
    }

    private fun markSegmentFromGesture(kind: String) {
        val pos = lastState.positionAt(System.currentTimeMillis(), lastStateAtMs)
        val existing = if (kind == "intro") {
            lastState.segmentIntroEndMs
        } else {
            lastState.segmentOutroStartMs
        }
        if (pos <= 0) {
            showHintFor("当前位置为 0，无法标记", 1500, null)
            return
        }
        if (kind == "intro" && pos < 3000) {
            showHintFor("播放 3 秒后才能设置片头", 1500, null)
            return
        }
        if (lastState.durationMs > 0 && pos >= lastState.durationMs) {
            showHintFor("当前位置已到结尾，无法标记", 1500, null)
            return
        }
        segmentMarkReject(kind, pos, lastState.durationMs.toLong())?.let {
            showHintFor(it, 1500, null)
            return
        }
        if (existing != null) {
            segmentCardOpen = true
            segmentConfirmKind = kind
            renderOverlays()
            return
        }
        listener?.onSetSegmentMark(kind, pos)
        val label = if (kind == "intro") "片头结束点" else "片尾开始点"
        showHintFor(
            "已设置$label ${AndroidNativePlayerState.formatPlayerTime(pos)}",
            1500,
            null,
        )
    }

    /**
     * 临时倍速胶囊（长按期间常显，无自动隐藏；松手由
     * [tapLayer] 的 ACTION_UP 隐藏）。
     */
    private fun showSpeedBoostChip() =
        showHintFor("${PlayerScreenSpeedBoostMultiplier}× 播放中", 0L, null)

    /**
     * 亮度/音量柱条（自绘 [VerticalGaugeView]，逐项复刻 Flutter
     * `_buildVerticalBar`：36dp 宽 / 圆角 18 / 黑 54% 底 / 顶部 18dp 图标 /
     * 竖向 4dp 轨道 / 白拇指 + 光晕 / 底部 11sp 百分比）。
     *
     * 旧实现是一个只显示「45%」的圆角黑底 TextView——无图标、无轨道、
     * 无进度可视化（真机回归「手势柱条 UI 与 MDK 不一致」）。
     */
    private val verticalBar = VerticalGaugeView(context).apply {
        visibility = GONE
    }

    /** 纵拖/音量柱条百分比（-1 = 隐藏）。 */
    private var verticalBarPercent: Int = -1
    /** 柱条贴哪边（true = 左侧亮度）。 */
    private var verticalBarOnLeft: Boolean = false

    /** 纵拖过程中的本地亮度/音量回显（0..1）。 */
    private var brightness01 = 1.0
    private var volume01 = 1.0

    /** 柱条 800ms 后隐藏（独立句柄，与手势提示互不干扰）。 */
    private fun scheduleVerticalBarHide() {
        hideVerticalBar?.let { mainHandler.removeCallbacks(it) }
        val hide = Runnable {
            verticalBarPercent = -1
            verticalBar.visibility = GONE
            hideVerticalBar = null
        }
        hideVerticalBar = hide
        mainHandler.postDelayed(hide, GESTURE_HINT_TEXT_MS)
    }

    /**
     * 显示纵拖柱条（[onLeftSide] 决定贴哪边）。
     *
     * Flutter 侧：`_buildBrightnessBar` 在**右**、`_buildVolumeBar` 在**左**
     * （源码注释与实现相反，以实现为准）。这里保持一致。
     */
    private fun showVerticalBar(onLeftSide: Boolean) {
        verticalBarOnLeft = onLeftSide
        // Math.round(Double) 返回 Long，需显式 toInt()（CI 实测编译错误）。
        verticalBarPercent =
            Math.round((if (onLeftSide) brightness01 else volume01) * 100).toInt()
        paintVerticalBar()
        scheduleVerticalBarHide()
    }

    /** 按当前百分比/侧别刷新柱条。 */
    private fun paintVerticalBar() {
        if (verticalBarPercent < 0) {
            verticalBar.visibility = GONE
            return
        }
        // 亮度贴右 / 音量贴左（Flutter `_buildBrightnessBar` right:20、
        // `_buildVolumeBar` left:20）；轨道色与图标随之切换。
        val brightness = verticalBarOnLeft
        verticalBar.accent =
            if (brightness) NPTheme.GAUGE_BRIGHTNESS else NPTheme.GAUGE_VOLUME
        verticalBar.setIcon(
            if (brightness) {
                NativePlayerIcons.ICON_BRIGHTNESS
            } else {
                NativePlayerIcons.volumeIcon(verticalBarPercent)
            },
        )
        verticalBar.value = verticalBarPercent / 100.0
        verticalBar.visibility = VISIBLE
        val lp = verticalBar.layoutParams as? LayoutParams
        if (lp != null) {
            lp.gravity = if (brightness) Gravity.END or Gravity.CENTER_VERTICAL
            else Gravity.START or Gravity.CENTER_VERTICAL
            lp.marginStart = if (brightness) 0 else dp(NPTheme.GAUGE_EDGE)
            lp.marginEnd = if (brightness) dp(NPTheme.GAUGE_EDGE) else 0
            verticalBar.layoutParams = lp
        }
    }

    /**
     * 手势识别器。
     *
     * 与 Flutter 的差别仅在**实现手段**：Flutter 用多个 GestureDetector
     * 回调，这里用 `SimpleOnGestureListener` 统一分发，语义（阈值、换算
     * 系数、上限）逐项照抄。
     */
    private val gestureDetector = android.view.GestureDetector(
        context,
        object : android.view.GestureDetector.SimpleOnGestureListener() {

            override fun onDown(e: MotionEvent): Boolean = true

            // 双击：播放/暂停。
            override fun onDoubleTap(e: MotionEvent): Boolean {
                if (lastState.locked || !lastState.canControl) return false
                listener?.onTogglePlay()
                // 指示器显示切换**后**的可执行动作图标（与 Flutter
                // `playPauseHintIcon` 语义一致）：播放中→暂停、暂停→播放。
                // 588 修正：旧实现读切换**前**的 `lastState.paused`（Dart
                // 回推约 200ms 才到），图标正好相反。
                showGestureIcon(
                    if (lastState.paused) {
                        NativePlayerIcons.ICON_PAUSE_CIRCLE
                    } else {
                        NativePlayerIcons.ICON_PLAY_CIRCLE
                    },
                )
                return true
            }

            // 长按：三分区（对齐 Flutter `_onVideoLongPressStart` / 鸿蒙
            // `onLongPressZone`）——左 1/3 标片头、右 1/3 标片尾、中间临时
            // 2× 倍速；片头片尾功能未开（或 TV/面板开）时全区退化为倍速。
            override fun onLongPress(e: MotionEvent) {
                if (lastState.locked || !lastState.canControl) return
                if (lastState.tvMode || activePanel != null) return
                // 长按手势结束会派发 tap：抑制紧随的 tap（防关掉刚开的卡）。
                suppressTapUntilMs = System.currentTimeMillis() + 500
                if (lastState.segmentEnabled) {
                    if (e.x < width / 3f) {
                        markSegmentFromGesture("intro")
                        return
                    }
                    if (e.x > width * 2f / 3f) {
                        markSegmentFromGesture("outro")
                        return
                    }
                }
                if (boostActive) return
                boostBaseSpeed = lastState.speed
                boostActive = true
                listener?.onSpeedBoost(true)
                showSpeedBoostChip()
            }

            override fun onScroll(
                e1: MotionEvent?,
                e2: MotionEvent,
                distanceX: Float,
                distanceY: Float,
            ): Boolean {
                if (lastState.locked || !lastState.canControl) return false
                if (e1 == null) return false
                // 方向锁（591）：首次超 slop 时**一次性定轴**，之后只走该轴，
                // 不再每帧重判——否则斜向拖动会在横/纵之间来回切换，上滑
                // 时误触发 seek（真机回归「向上滑进度条会变」）。
                val slop = android.view.ViewConfiguration.get(context).scaledTouchSlop
                if (dragAxis == AXIS_NONE) {
                    val dx = e2.x - e1.x
                    val dy = e2.y - e1.y
                    if (Math.abs(dx) <= slop && Math.abs(dy) <= slop) {
                        return false // 位移未超阈值，方向未定
                    }
                    dragAxis =
                        if (Math.abs(dx) > Math.abs(dy)) AXIS_HORIZONTAL else AXIS_VERTICAL
                }
                if (dragAxis == AXIS_HORIZONTAL) {
                    // 横拖 seek：每累计 100px 预览一次（±5s）。
                    hDragAccumPx -= distanceX
                    if (Math.abs(hDragAccumPx) > DRAG_PX_PER_5S) {
                        val deltaMs = (hDragAccumPx / DRAG_PX_PER_5S * DRAG_MS_PER_5S)
                            .toLong().coerceIn(-SEEK_MAX_DELTA_MS, SEEK_MAX_DELTA_MS)
                        val preview = (lastState.positionMs + deltaMs)
                            .coerceIn(0L, lastState.durationMs.toLong())
                        showGestureHint(AndroidNativePlayerState.formatPlayerTime(preview))
                    }
                    return true
                }
                // 纵拖：左亮度 / 右音量。
                //
                // 【方向语义（591 修正）】Android `GestureDetector.onScroll` 的
                // `distanceY` **正值 = 手指上滑**（e2.y < e1.y 时为正）。所以
                // 上滑 → 正值 → 增大，直接加即可。
                //
                // 旧实现写成 `-distanceY`（注释误以为「distanceY 正值=上滑，
                // 而 Flutter 正值=下滑所以要取负」），结果上滑减小、下滑增大，
                // 方向完全反了（真机回归）。
                //
                // 对照 Flutter `_onVerticalDragUpdate`：
                //   `primaryDelta` 上滑为负 → `_brightness - delta/600` 后增大 ✅
                if (Math.abs(distanceY) > 0f) {
                    val delta01 = (distanceY / VERTICAL_PX_PER_FULL).toDouble()
                    if (dragOnLeftSide) {
                        brightness01 = (brightness01 + delta01).coerceIn(0.0, 1.0)
                        listener?.onGestureBrightness(delta01)
                    } else {
                        volume01 = (volume01 + delta01).coerceIn(0.0, 1.0)
                        listener?.onGestureVolumeDelta(delta01)
                    }
                    showVerticalBar(dragOnLeftSide)
                }
                return true
            }

            override fun onFling(
                e1: MotionEvent?,
                e2: MotionEvent,
                velocityX: Float,
                velocityY: Float,
            ): Boolean {
                if (lastState.locked || !lastState.canControl) return false
                // 累加器已提交过（ACTION_UP）则不再走速度回退（防二次 seek）。
                if (hDragCommitted) return false
                // 只有锁定为横向才是 seek（591）：纵向手势的横向速度分量不该
                // 触发 seek（旧实现无守卫，上滑结束的抖动速度会被当横拖）。
                if (dragAxis != AXIS_HORIZONTAL) return false
                // 无足够拖动距离时用速度回退（与 Flutter `_onHorizontalDragEnd`
                // 的 `deltaMs == 0 → primaryVelocity` 分支一致）。
                val deltaMs = (velocityX / DRAG_PX_PER_5S * DRAG_MS_PER_5S)
                    .toLong().coerceIn(-SEEK_MAX_DELTA_MS, SEEK_MAX_DELTA_MS)
                if (deltaMs == 0L) return false
                listener?.onSeekRelative(deltaMs)
                val seconds = Math.round(deltaMs / 1000f)
                showGestureHint("${if (seconds > 0) "+" else ""}${seconds}s")
                return true
            }
        },
    )

    init {
        tapLayer.setOnTouchListener { _, event ->
            // 纵拖起始侧：DOWN 时判定（Flutter 用 globalPosition.dx < 半屏宽）。
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                hDragAccumPx = 0f
                hDragCommitted = false
                // 591：方向锁复位（每个新手势重新定轴）。
                dragAxis = AXIS_NONE
                dragOnLeftSide = event.x < width / 2f
            }
            // 长按临时倍速：松手/取消时还原到长按前档位（Flutter
            // `_onSpeedBoostEnd`）。
            if (event.actionMasked == MotionEvent.ACTION_UP ||
                event.actionMasked == MotionEvent.ACTION_CANCEL
            ) {
                if (boostActive) {
                    boostActive = false
                    listener?.onSpeedBoost(false)
                    gestureHint.visibility = GONE
                }
                // 横拖松手提交（对齐 Flutter `_onHorizontalDragEnd`）：累加器
                // 非零 → 按累加器 seek（与预览同基准，预览/落点一致）；零 →
                // onFling 速度回退。旧实现只在 onFling 里 seek，慢速拖动松手
                // 不 seek（真机回归「拖了没反应」）。
                //
                // 591：只在锁定为横向时提交——纵向手势的 hDragAccumPx 恒 0，
                // 但加这层守卫可防止未来改动引入误触发。
                if (dragAxis == AXIS_HORIZONTAL &&
                    Math.abs(hDragAccumPx) > 0f &&
                    !lastState.locked && lastState.canControl
                ) {
                    val deltaMs = (hDragAccumPx / DRAG_PX_PER_5S * DRAG_MS_PER_5S)
                        .toLong().coerceIn(-SEEK_MAX_DELTA_MS, SEEK_MAX_DELTA_MS)
                    hDragAccumPx = 0f
                    hDragCommitted = true
                    if (deltaMs != 0L) {
                        listener?.onSeekRelative(deltaMs)
                        val seconds = Math.round(deltaMs / 1000f)
                        showGestureHint("${if (seconds > 0) "+" else ""}${seconds}s")
                    }
                }
            }
            gestureDetector.onTouchEvent(event)
            // 不消费：让 click 照常触发（单击语义）。
            false
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
    /** 顶栏分享（房间模式；对齐 Flutter showShare）。 */
    private val shareButton = TextView(context)
    /** 顶栏右侧簇（网速~转屏）：小屏整组等比缩（自适应不出屏）。 */
    private val topTail = LinearLayout(context)
    /**
     * 顶栏右侧簇的测量级缩放容器（等价 Flutter `FittedBox(scaleDown)`）。
     * `reservedPx` = 标题保底宽，保证尾簇再挤也不会把标题压成 0。
     */
    private val topTailBox = ScaleDownBox(context)
    private val clockWrap = FrameLayout(context)
    private val clockText = TextView(context)

    // 底栏
    private val bottomBar = LinearLayout(context)
    private val logoImage = ImageView(context)
    private val logoSpacer = View(context)
    private val seekRow = LinearLayout(context)
    private val positionLabel = TextView(context)
    /** 玻璃滑杆（自绘，完全复刻鸿蒙 GlassSlider.ets；替换系统 SeekBar）。 */
    private val seekBar = GlassSeekBarView(context)
    private val durationLabel = TextView(context)
    /**
     * 控件行：`leading槽(权重1, 贴左) | 传输组 | trailing槽(权重1, 贴右)`。
     * 结构等价 Flutter `PlayerBottomRow(centered: true)`——两个 `Expanded`
     * 让传输组**精确居中**，trailing 槽可用宽 = `(行宽-传输组)/2`。
     */
    private val buttonRow = LinearLayout(context)
    private val transportGroup = LinearLayout(context)
    private val prevButton = TextView(context)
    private val playPauseButton = TextView(context)
    private val nextButton = TextView(context)
    private val leadingGroup = LinearLayout(context)
    /** leading 槽（权重 1，贴左）：内部放定宽 [leadingGroup]，锁钮与时间数显同列。 */
    private val leadingSlot = LinearLayout(context)
    private val lockButton = TextView(context)
    /** 跳过片头/片尾胶囊（照抄鸿蒙 ControlRow leading 槽；显隐由 skipPrompt 驱动）。 */
    private val skipPromptChip = LinearLayout(context)
    private val skipPromptIcon = TextView(context)
    private val skipPromptLabel = TextView(context)
    private val trailingGroup = LinearLayout(context)
    /** trailing 的测量级缩放容器（等价 Flutter FittedBox(scaleDown)）。 */
    private val trailingBox = ScaleDownBox(context)
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
    /**
     * 加载指示器：自绘弧线转圈（复刻 Flutter `CircularProgressIndicator`）。
     *
     * 旧实现用系统 [ProgressBar]：弧长/转速/是否动画全由 ROM 的
     * `progressBarStyle` 决定，真机反馈「就一个圈、不是动态的」。自绘后
     * 任何机型都是同一个「旋转 + 弧长伸缩」的圈（见 [PlayerSpinnerView]）。
     */
    private val bufferingView = PlayerSpinnerView(context)

    // 面板层
    private val danmakuLayer = DanmakuLayerView(context)

    // 注意：.apply 只能接在 View 声明后面——接在 Runnable 的 object 表达式
    // 后面会被 Kotlin 解析到外层 this（整个控件层根视图），把根视图设成
    // GONE → 控件全消失（真机回归「只有画面没控件」）。
    private val panelScrim = View(context).apply {
        // 深色面板用中等遮罩区分层次（587：黑 45%）。
        setBackgroundColor(NPTheme.SCRIM_DIM)
        visibility = GONE
        setOnClickListener { closePanel() }
    }

    /**
     * 播放器弹层「深色磨砂」背景（纯渐变，不做任何背景采样）。
     *
     * 【为什么删掉 PixelCopy 采样】旧实现每 600ms 回读面板矩形做折射背景，
     * 视频运动时面板背景**一帧一帧地跳**（1.7fps 静帧序列），与 MDK
     * （Flutter `BackdropFilter` 实时模糊）差距极大。Android 无节点级
     * backdrop blur API，真·实时只能让面板独立成窗口走系统 cross-window
     * blur——但那会迫使视频层从硬件 overlay 降级为 GPU 合成（HDR 直通
     * 失效）、且窗口插入可能打断 surface 绑定。权衡后改纯深色渐变：
     * **零回读、零循环、零跳帧、零黑屏风险**。
     */
    private val glassPanel =
        PanelGlassDrawable(NPTheme.RADIUS_PANEL, resources.displayMetrics.density)
    private val glassCard =
        PanelGlassDrawable(NPTheme.RADIUS_CARD, resources.displayMetrics.density)
    private val panelContainer = LinearLayout(context)
    private val decodePopover = LinearLayout(context)
    private val segmentCard = LinearLayout(context)
    private val segmentScrim = View(context).apply {
        setBackgroundColor(NPTheme.SCRIM_DIM)
        visibility = GONE
        setOnClickListener {
            segmentCardOpen = false
            segmentConfirmKind = null
            renderOverlays()
        }
    }

    // ── 房间资源面板（590）──────────────────────────────────────
    //
    // 【为什么必须原生实现】原生 UI 是全屏 Dialog，盖在 Flutter Scaffold
    // 之上——即使 Flutter 侧还画着 320dp 资源面板，也被原生窗口完全遮住。
    // 旧实现 `ToggleResourcePanel` 命令只打一行日志（什么都不做），真机
    // 表现为「房间模式一播放就全屏、资源面板展不开」。
    //
    // 现在：原生 Dialog 内自带右侧面板，展开时把 mpv surface 收窄 320dp
    // （否则视频被面板盖住一部分）。
    private val roomPanel = LinearLayout(context)
    private val roomPanelScroll = ScrollView(context)
    private val roomPanelList = LinearLayout(context)
    private val roomPanelHeader = LinearLayout(context)
    private val roomPanelTitle = TextView(context)
    private val roomPanelSearch = TextView(context)
    private val roomPanelOnline = TextView(context)
    private val roomPanelRole = TextView(context)
    private val roomBroadcastHeader = TextView(context)
    private val roomBroadcastList = LinearLayout(context)
    /** 播报板滚动容器（新消息自动滚到底用）。 */
    private val roomBroadcastScroll = ScrollView(context)
    /** 人数胶囊（people 图标 + 数字，对齐 Flutter）。 */
    private val roomOnlineChip = LinearLayout(context)
    private val roomOnlineIcon = TextView(context)
    /** 播报标题图标（campaign，对齐 Flutter）。 */
    private val roomBroadcastIcon = TextView(context)

    // ── 视图装配 ──────────────────────────────────────────────────

    /** 组装层级：tapLayer → topBar → bottomBar → 面板层。 */
    private fun buildHierarchy() {
        // 角标伸出命中框右缘（marginEnd=-2），任何一级父容器默认
        // clipChildren=true 都会把它右半切掉（真机截图回归）。整链关闭。
        clipChildren = false
        clipToPadding = false
        addView(
            tapLayer,
            lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        // 弹幕层：视频之上、控件之下（与 Flutter DanmakuOverlay 位置一致）。
        addView(danmakuLayer, lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        // 加载指示器：居中转圈。颜色/尺寸/动画对齐 Flutter `_buildVideoArea`
        // 的 `CircularProgressIndicator(color: Color(0xFF6366F1))`——旧值
        // WHITE_70 与 Flutter 观感不一致（B8），系统 ProgressBar 的动画
        // 又随 ROM 变化（587 改自绘）。
        //
        // 【层级修正（586）】必须**先于** topBar/bottomBar 添加：Flutter 的
        // 转圈画在控件层**之下**（「转圈期间顶栏/底栏仍可点返回」），而旧
        // 实现加在 bars 之后 → 转圈盖住控件区，与 Flutter 观感相反。
        bufferingView.visibility = GONE
        addView(bufferingView, lp(dp(36), dp(36), Gravity.CENTER))

        addView(topBar, lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.TOP))
        topBar.clipChildren = false
        topBar.clipToPadding = false
        addView(bottomBar, lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))
        bottomBar.clipChildren = false
        bottomBar.clipToPadding = false

        // 手势提示（居中胶囊）与亮度/音量柱条：视频之上、控件之下，
        // 与 Flutter `_buildGestureHint` / `_buildVerticalBar` 的层级一致。
        addView(
            gestureHint,
            lp(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER),
        )
        addView(
            verticalBar,
            lp(dp(NPTheme.GAUGE_WIDTH), dp(160), Gravity.END or Gravity.CENTER_VERTICAL),
        )

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
        // 房间资源面板（590）：右侧 320dp 分栏，铺满高度。
        addView(
            roomPanel,
            lp(dp(NPTheme.ROOM_PANEL_WIDTH), LayoutParams.MATCH_PARENT, Gravity.END),
        )

        configureTopBar()
        configureBottomBar()
        configureOverlays()
        // 【必须在此接线】旧实现只在 rebuildBars() 里调这两个函数，而
        // rebuildBars() 仅由 `state.tvMode != lastTvMode`（手机↔TV 切换）
        // 触发——手机端 tvMode 恒 false，监听器从未挂上（真机回归：
        // 「进度条拖不动」「播放/暂停、上下一集点了没反应」）。初始化
        // 路径必须自己接一次，rebuildBars() 里的调用保留供 TV 重排后重绑。
        configureSeekListeners()
        configureTransportListeners()
    }

    /** 顶栏：返回 / 标题 / 网速 /（手机）倍速·内核·字幕样式·解码·画面比例·转屏 /（TV）时钟。 */
    private fun configureTopBar() {
        // 幂等：重排（手机↔TV）会二次进入本函数，必须先清空容器，
        // 否则对已有 parent 的子视图重复 addView 会抛 IllegalStateException。
        topBar.removeAllViews()
        clockWrap.removeAllViews()
        topBar.orientation = LinearLayout.HORIZONTAL
        topBar.gravity = Gravity.CENTER_VERTICAL
        applyBarInsets()
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

        // 标题：Expanded（权重 1）+ **保底宽**。Flutter 的 Expanded 会被尾簇
        // 挤到 0 宽（极窄屏标题彻底消失）；这里保底 56dp 并 ellipsize，观感
        // 一致（同样是「剩余空间」）但不会塌成 0。
        titleText.setTextColor(Color.WHITE)
        titleText.setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.TITLE_SIZE)
        titleText.maxLines = 1
        titleText.ellipsize = TextUtils.TruncateAt.END
        titleText.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        titleText.minimumWidth = dp(NPTheme.TITLE_MIN_WIDTH)
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
        // 与玻璃胶囊同高（32dp），同排芯片高低一致（截图回归）。
        speedChip.minimumHeight = dp(32)
        // 点击弹倍速面板（对齐 Flutter SpeedMenuPanel 入口；旧实现循环切换
        // 无面板 →「倍速控件缺少弹出面板」）。
        speedChip.setOnClickListener { openPanel(PANEL_SPEED) }
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
        kernelChip.includeFontPadding = false
        kernelChip.setPadding(dp(9), dp(6), dp(9), dp(6))
        kernelChip.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        kernelChip.background = chipBackground(false)
        kernelChip.isClickable = true
        // 与图标胶囊同高（32dp）：内容不同的芯片各自成高 → 高低不齐。
        kernelChip.minimumHeight = dp(32)
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

        // 分享（仅房间模式；对齐 Flutter showShare: roomCode != null）。
        shareButton.text = String(Character.toChars(NativePlayerIcons.ICON_SHARE))
        shareButton.typeface = NativePlayerIcons.typeface(context)
        shareButton.setTextColor(Color.WHITE)
        shareButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        shareButton.gravity = Gravity.CENTER
        shareButton.includeFontPadding = false
        shareButton.setPadding(dp(6), dp(6), dp(6), dp(6))
        shareButton.isClickable = true
        shareButton.setOnClickListener { listener?.onShare() }
        applyPressFeedback(shareButton)
        topTail.addView(shareButton, llp(dp(34), dp(34), 8))

        // 尾簇装进测量级缩放容器：小屏/竖屏整组等比缩小（等价 Flutter
        // FittedBox(scaleDown)），保证不出屏、不与标题/传输组重叠。
        topTailBox.removeAllViews()
        topTailBox.addView(
            topTail,
            LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        topBar.addView(topTailBox, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ))

        // 时钟（TV：右贴边，100×48，13sp white70）。
        // Flutter PlayerClockLayer 是**独立于顶栏 Row 的定位层**，但用
        // `reserveClockSpace` 在 Row 尾部留 100dp 空位避免控件压到时间——
        // 这里等价：时钟直接作顶栏最后一个子项（100dp 定宽），既占位又显示。
        clockText.setTextColor(NPTheme.WHITE_70)
        clockText.setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.CLOCK_FONT_SIZE)
        clockText.gravity = Gravity.CENTER
        clockText.visibility = GONE
        clockWrap.removeAllViews()
        clockWrap.addView(clockText, lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        topBar.addView(
            clockWrap,
            llp(dp(NPTheme.CLOCK_WIDTH), dp(NPTheme.CLOCK_HEIGHT)),
        )
    }

    /** 顶栏玻璃图标胶囊（内核/字幕样式/解码共用）。 */
    private fun configureIconChip(chip: TextView, codePoint: Int) {
        chip.text = String(Character.toChars(codePoint))
        chip.typeface = NativePlayerIcons.typeface(context)
        chip.setTextColor(Color.WHITE)
        chip.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
        chip.gravity = Gravity.CENTER
        chip.includeFontPadding = false
        chip.setPadding(dp(6), dp(6), dp(6), dp(6))
        chip.background = chipBackground(false)
        chip.isClickable = true
        // 统一最小高（照抄鸿蒙 Chip/IconChip 观感一致）：文本芯片与图标
        // 芯片内容高度不同 → 各自成高，同排高低不齐（截图回归）。
        chip.minimumHeight = dp(32)
    }

    // ── 交互绑定（可重入：手机 ↔ TV 切换时重建布局后重绑）──────────

    /**
     * 进度条：拖动预览时间数显、松手回传 seek。
     *
     * 玻璃滑杆自带绘制（[GlassSeekBarView]），此处只接值映射回调：
     * 值即毫秒（无 SEEK_STEPS 换算），拖动中 `onChanged` 预览、抬手
     * `onCommit` 一次性 seek。
     */
    private fun configureSeekListeners() {
        seekBar.step = 1000f // 1s 吸附（同鸿蒙 ProgressRow step: 1000）
        seekBar.onChanged = { v ->
            dragging = true
            positionLabel.text = AndroidNativePlayerState.formatPlayerTime(v.toLong())
            scheduleAutoHide()
        }
        seekBar.onCommit = { v ->
            dragging = false
            // 保护窗：等权威位置追上目标前，禁止 tick 把滑杆写回旧值。
            pendingSeekMs = v.toLong()
            pendingSeekAtMs = System.currentTimeMillis()
            listener?.onSeek(v.toLong())
            scheduleAutoHide()
        }
        // TV 长按进度条 → 片头片尾标记卡片（与 Flutter onLongPress 一致）。
        seekBar.setOnLongClickListener {
            if (lastState.segmentEnabled && lastState.tvMode) {
                suppressTapUntilMs = System.currentTimeMillis() + 500
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
                // 【不改几何】焦点只画环（照抄鸿蒙 BORDER_FOCUS）：旧实现
                // scaleX/Y 1.1 会连带放大命中区 → 焦点态相邻控件误触。
            }
        }
    }

    /** 底栏重排前清空所有容器（幂等）。 */
    private fun clearBarContainers() {
        bottomBar.removeAllViews()
        seekRow.removeAllViews()
        buttonRow.removeAllViews()
        leadingSlot.removeAllViews()
        leadingGroup.removeAllViews()
        // 跳过胶囊内容重建（子视图复用，不清会在重排时重复 addView 抛异常）。
        skipPromptChip.removeAllViews()
        transportGroup.removeAllViews()
        trailingBox.removeAllViews()
        trailingGroup.removeAllViews()
        // speedChip 属于顶栏内容，由 configureTopBar 填充；这里清掉会导致
        // 速度胶囊整块消失（v1.5.5 回归）。
        bottomSpeedChip.removeAllViews()
        trailingBox.reset()
    }

    /** 底栏：Logo / 进度条 / 播放组（手机居中·TV 置左）/ 右侧图标组 / 诊断行。 */
    private fun configureBottomBar() {
        // 幂等：重排（手机↔TV）会二次进入本函数，必须先清空所有容器，
        // 否则对已有 parent 的子视图重复 addView 会抛 IllegalStateException。
        clearBarContainers()
        bottomBar.orientation = LinearLayout.VERTICAL
        bottomBar.gravity = Gravity.START
        applyBarInsets()
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

        // 玻璃滑杆（自绘，GlassSeekBarView）：值即毫秒，范围随状态推进设置。
        seekBar.minValue = 0f
        seekBar.maxValue = 1f
        seekBar.value = 0f
        seekBar.isEnabled = false
        seekRow.addView(
            seekBar,
            LinearLayout.LayoutParams(0, dp(28), 1f).also {
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

        // leading 组（锁钮）：定宽 = 时间数显列宽（56/78），锁钮**列内居中**
        // （照抄鸿蒙 ControlRow：width=cellW + textAlign Center，与进度条左
        // 数显同轴）。旧实现 44dp 钮左贴 → 视觉偏左下（截图回归）。
        leadingGroup.orientation = LinearLayout.HORIZONTAL
        leadingGroup.gravity = Gravity.CENTER
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
        leadingGroup.addView(lockButton, lp(LayoutParams.MATCH_PARENT, dp(44)))

        // 跳过片头/片尾胶囊（照抄鸿蒙 ControlRow leading 槽：圆角 14 /
        // padding h12 v8 / 图标 20 + 6 + 13sp w600 / 玻璃底 #8C000000 /
        // 宽上限 132dp 防撑行）。显隐由 Dart skipPrompt 推送驱动（8 秒
        // 自动消失、章节/手动标记解析），点击回传 skipSegment。
        skipPromptChip.orientation = LinearLayout.HORIZONTAL
        skipPromptChip.gravity = Gravity.CENTER_VERTICAL
        skipPromptChip.setPadding(dp(12), dp(8), dp(12), dp(8))
        skipPromptChip.background = glassBackground(14, 0x8C000000.toInt())
        skipPromptChip.isClickable = true
        skipPromptChip.setOnClickListener {
            listener?.onSkipSegment()
            scheduleAutoHide()
        }
        applyPressFeedback(skipPromptChip)
        skipPromptIcon.typeface = NativePlayerIcons.typeface(context)
        skipPromptIcon.setTextColor(Color.WHITE)
        skipPromptIcon.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
        skipPromptIcon.includeFontPadding = false
        skipPromptChip.addView(skipPromptIcon, lp(dp(20), dp(20)))
        skipPromptLabel.setTextColor(Color.WHITE)
        skipPromptLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        skipPromptLabel.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        skipPromptLabel.maxWidth = dp(132)
        skipPromptChip.addView(
            skipPromptLabel,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).also { it.marginStart = dp(6) },
        )
        skipPromptChip.visibility = GONE

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
            { badgeText(lastState.versions.size) },
        ) { openPanel(PANEL_VERSION) }
        trailingGroup.addView(versionButton, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))
        displayAdjustButton = iconButton(NativePlayerIcons.ICON_TUNE) { openPanel(PANEL_DISPLAY) }
        trailingGroup.addView(displayAdjustButton!!, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))
        subtitleButton = badgeButton(
            NativePlayerIcons.ICON_SUBTITLES,
            { badgeText(lastState.subtitleStreamCount) },
        ) { openPanel(PANEL_SUBTITLE) }
        trailingGroup.addView(subtitleButton, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))
        audioButton = badgeButton(
            NativePlayerIcons.ICON_AUDIO_TRACK,
            { badgeText(lastState.audioStreamCount) },
        ) { openPanel(PANEL_AUDIO) }
        trailingGroup.addView(audioButton, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))
        episodeButton = badgeButton(
            NativePlayerIcons.ICON_PLAYLIST_PLAY,
            { badgeText(lastState.episodes.size) },
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
        // 房间模式「资源面板」开关：Flutter 是切换 `_showPanel`（视频区与
        // 资源面板分栏）。旧实现发 onBack → 点一下直接退出播放页。
        panelToggleButton.setOnClickListener { listener?.onToggleResourcePanel() }
        applyPressFeedback(panelToggleButton)
        trailingGroup.addView(panelToggleButton, llp(dp(32), dp(32), NPTheme.CONTROL_GAP))

        // HDR 徽标：Flutter 控制层**没有**这个元素（只在调试面板里体现），
        // 原生多画一个会与 Flutter 观感不一致 → 移除，HDR 信息走诊断行。

        // 组装三组
        // 结构等价 Flutter PlayerBottomRow(centered: true)：
        //   Expanded(leading 贴左) | 传输组(精确居中) | Expanded(trailing 贴右 + 等比缩)
        // 两个权重槽同宽 → 传输组自然居中；trailing 槽拿到的可用宽即
        // `(行宽-传输组)/2`，与 Flutter FittedBox 的约束完全一致。
        //
        // leading 槽内部再放一个**定宽**的 [leadingGroup]：锁钮要在时间数显
        // 列（56/78dp）内居中（Flutter leading 是 SizedBox(cellWidth) + Align），
        // 不能随 Expanded 槽一起被拉宽。
        buttonRow.orientation = LinearLayout.HORIZONTAL
        buttonRow.gravity = Gravity.CENTER_VERTICAL
        leadingSlot.orientation = LinearLayout.HORIZONTAL
        leadingSlot.gravity = Gravity.CENTER_VERTICAL
        leadingSlot.addView(leadingGroup)
        leadingGroup.layoutParams = LinearLayout.LayoutParams(dp(NPTheme.TIME_CELL), dp(44))
        // 跳过胶囊挂在锁钮列后（同鸿蒙 leading 槽顺序）。
        leadingSlot.addView(
            skipPromptChip,
            llp(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
                8,
            ),
        )
        leadingSlot.layoutParams = LinearLayout.LayoutParams(
            0,
            dp(NPTheme.TRANSPORT_PLAY),
            1f,
        )

        transportGroup.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            dp(NPTheme.TRANSPORT_PLAY),
        )

        // trailing 槽：权重 1（可用宽 = (行宽-传输组)/2），内部放缩放容器。
        trailingBox.removeAllViews()
        trailingBox.addView(
            trailingGroup,
            LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                dp(NPTheme.TRANSPORT_PLAY),
            ),
        )
        trailingBox.layoutParams = LinearLayout.LayoutParams(
            0,
            dp(NPTheme.TRANSPORT_PLAY),
            1f,
        )

        buttonRow.addView(leadingSlot)
        buttonRow.addView(transportGroup)
        buttonRow.addView(trailingBox)
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
            // 关字体留白：与传输组按钮一致（鸿蒙 TransportGlyph/IconChip 无
            // fontPadding）——不关时字形基线偏移 → 底栏图标高低不齐（截图回归）。
            includeFontPadding = false
            setPadding(0, 0, 0, 0)
            isClickable = true
            setOnClickListener { onClick() }
            applyPressFeedback(this)
        }

    /**
     * 带角标的右侧图标按钮：图标 24dp 字形、角标 9sp 白字 + #6366F1 **正圆**底，
     * 贴图标右上（Flutter Stack + Positioned(right:-6,top:-4)）。
     *
     * 关键修复：
     * - 角标旧实现宽 `14+len*5`、高固定 14 → "3" 是 19×14 **椭圆**。
     *   现按数量位数分档（15/19/24）且**宽==高**，OVAL 必为正圆；
     * - 589：圆底改系统 `GradientDrawable(OVAL)`（[badgeCircleBackground]）。
     *   旧的自绘 Drawable `draw()` 依赖 `bounds`，而 View 的 `setBackground`
     *   与首次 `onSizeChanged` 时序不保证 → bounds 恒空 → **圆底完全不画**，
     *   只剩白字（真机「角标只有白色数字」）；
     * - `marginEnd=-2` 让角标伸出 host 右缘，而 FrameLayout 默认
     *   `clipChildren=true` → 右半被切（截图 1）。host 与整条链显式
     *   `clipChildren=false`（见 [buildHierarchy]）。
     */
    private fun badgeButton(
        codePoint: Int,
        badgeProvider: () -> String?,
        onClick: () -> Unit,
    ): FrameLayout {
        val host = FrameLayout(context).apply {
            clipChildren = false
            clipToPadding = false
        }
        host.addView(iconButton(codePoint, onClick), lp(dp(28), dp(28), Gravity.CENTER))
        val badge = TextView(context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.BADGE_FONT)
            gravity = Gravity.CENTER
            includeFontPadding = false
            // Flutter Container(padding: EdgeInsets.all(2))。
            setPadding(dp(2), dp(2), dp(2), dp(2))
            // 589：系统 OVAL 正圆底（自绘 Drawable 的 bounds 陷阱会让圆底
            // 完全不画，只剩白字——真机回归）。
            background = badgeCircleBackground()
            // 590：初始必须 GONE。
            //
            // 【真机回归：空白蓝圆点】applyState 的刷新用了
            // `if (badgeLastText[badge] == text) return@forEach` 做短路，而
            // badgeLastText 是 HashMap<TextView, String?>——缺失键取出来就是
            // null，与「值为 null」无法区分。首次 provider 返回 null（0 条字幕）
            // 时短路直接返回 → visibility 从未被设成 GONE，而 View 默认 VISIBLE
            // → 显示成「有靛蓝圆底、没有数字」的空白点。
            // 创建时即 GONE 把短路歧义吸收掉。
            visibility = GONE
        }
        host.addView(badge, badgeLayoutParams(""))
        // 角标数量在 applyState 中刷新
        badgeTags[badge] = badgeProvider
        return host
    }

    /**
     * 角标数量文本（590）：`count > 0` 才返回字符串，否则 null（不渲染）。
     *
     * 统一入口杜绝上游传 "0" / 空白串导致「空白圆点」。
     */
    internal fun badgeText(count: Int): String? =
        if (count > 0) count.toString() else null

    /**
     * 角标定位（590：收进 32dp 命中框，不再伸出 host）。
     *
     * 结构：`Padding(all:4)` → 命中区 32dp，内含 24dp 图标（居中占 2..30）；
     * 角标 `topMargin = 0 / marginEnd = 0` → 完整落在 host 内部。
     *
     * 【真机回归：角标被裁剪】旧实现 `marginEnd = -dp(2)` 让角标伸出 host
     * 右缘，靠逐级 `clipChildren = false` 兜住。但裁剪链只显式关了根 /
     * topBar / bottomBar，中间层 `buttonRow`、`trailingGroup` 仍是默认
     * `true` → 角标右缘与上缘被切。
     *
     * 现在角标四边都在 host 内，父级裁不裁都切不到它——不依赖任何中间层。
     * 视觉上仍贴图标右上角（Flutter `Positioned(right:-6, top:-4)` 的
     * `Stack(clipBehavior: Clip.none)` 语义由容器内留白等价实现）。
     *
     * 尺寸按数量文本长度分档（与 Flutter `NativePlayerTheme.badgeSizeFor`、
     * 鸿蒙 `badgeSide` 逐值一致）。
     */
    private fun badgeLayoutParams(text: String): LayoutParams {
        val sidePx = dp(badgeDiameterDp(text.length))
        return LayoutParams(sidePx, sidePx, Gravity.TOP or Gravity.END).apply {
            topMargin = 0
            marginEnd = 0
        }
    }

    /**
     * 角标正圆边长（dp，纯函数可单测）：1~2 位 15、3 位 19、4 位起 24。
     *
     * 与 Flutter `NativePlayerTheme.badgeSizeFor(String)` / 鸿蒙
     * `badgeSide(badge)` 同值；[textLength] 是数量文本的字符数。
     */
    internal fun badgeDiameterDp(textLength: Int): Int = when {
        textLength >= 4 -> NPTheme.BADGE_XL
        textLength == 3 -> NPTheme.BADGE_WIDE
        else -> NPTheme.BADGE_MIN
    }

    /** 角标刷新表（TextView → 数量提供者）。 */
    private val badgeTags = HashMap<TextView, () -> String?>()

    /** 角标上次文本（数值不变则跳过 layoutParams 重算，防 500ms 抖动）。 */
    private val badgeLastText = HashMap<TextView, String?>()


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
        configureRoomPanel()
    }

    /**
     * 房间资源面板（590）结构：头部（资源标题 + 搜索 + 在线人数 + 房主徽章）
     * → 分组列表（滚动）→ 底部播报板 120dp。
     *
     * 视觉对齐 Flutter `_buildResourcePanel`：`0xFF1A1A2E` 底、头部底边
     * 白 12% 分隔线、组标题 `0xFF16213E` 底、当前集 accent 左 3dp 边 + 20% 底。
     */
    private fun configureRoomPanel() {
        roomPanel.orientation = LinearLayout.VERTICAL
        roomPanel.visibility = GONE
        roomPanel.setBackgroundColor(0xFF1A1A2E.toInt())

        roomPanelHeader.orientation = LinearLayout.HORIZONTAL
        roomPanelHeader.gravity = Gravity.CENTER_VERTICAL
        roomPanelHeader.setPadding(dp(12), dp(10), dp(12), dp(10))
        // 头部底边白 12% 分隔线（Flutter Border(bottom: BorderSide(white12))）。
        roomPanelHeader.foreground = rowBottomDivider()
        roomPanelTitle.text = "资源"
        roomPanelTitle.setTextColor(Color.WHITE)
        roomPanelTitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        roomPanelTitle.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        roomPanelTitle.maxLines = 1
        roomPanelTitle.ellipsize = TextUtils.TruncateAt.END
        // 591：标题只占剩余空间（layoutWeight=1），但**必须给搜索/人数/角色
        // 预留固定宽度**，否则标题撑满后把三者挤到最右（真机截图「资源」
        // 与人数/角色贴在一起、中间大片空白）。
        // 对齐 Flutter `Expanded(资源) | 搜索 | 人数胶囊 | 角色徽章`。
        roomPanelHeader.addView(
            roomPanelTitle,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )
        // 搜索（房主且暂停时才显示，与 Flutter 一致）
        roomPanelSearch.text = String(Character.toChars(NativePlayerIcons.ICON_SEARCH))
        roomPanelSearch.typeface = NativePlayerIcons.typeface(context)
        roomPanelSearch.setTextColor(NPTheme.WHITE_70)
        roomPanelSearch.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
        roomPanelSearch.gravity = Gravity.CENTER
        roomPanelSearch.includeFontPadding = false
        roomPanelSearch.isClickable = true
        roomPanelSearch.setOnClickListener {
            listener?.onOpenResourceSearch()
            scheduleAutoHide()
        }
        applyPressFeedback(roomPanelSearch)
        roomPanelHeader.addView(roomPanelSearch, llp(dp(28), dp(28), 12))

        // 人数胶囊（Flutter：people 图标 12 + 数字 11 white70，
        // 底 white12 圆角 8，padding h6 v2）。
        roomOnlineChip.orientation = LinearLayout.HORIZONTAL
        roomOnlineChip.gravity = Gravity.CENTER_VERTICAL
        roomOnlineChip.setPadding(dp(6), dp(2), dp(6), dp(2))
        roomOnlineChip.background = GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(0x1FFFFFFF)
        }
        roomOnlineIcon.text = String(Character.toChars(NativePlayerIcons.ICON_PEOPLE))
        roomOnlineIcon.typeface = NativePlayerIcons.typeface(context)
        roomOnlineIcon.setTextColor(NPTheme.WHITE_70)
        roomOnlineIcon.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        roomOnlineIcon.gravity = Gravity.CENTER
        roomOnlineIcon.includeFontPadding = false
        roomOnlineChip.addView(roomOnlineIcon, llp(dp(12), dp(12)))
        roomPanelOnline.setTextColor(NPTheme.WHITE_70)
        roomPanelOnline.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        roomOnlineChip.addView(
            roomPanelOnline,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).also { it.marginStart = dp(3) },
        )
        roomPanelHeader.addView(roomOnlineChip, llp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(20), 12))

        // 角色徽章（房主 accent / 观众红，圆角 8，padding h6 v2）。
        roomPanelRole.setTextColor(Color.WHITE)
        roomPanelRole.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        roomPanelRole.setPadding(dp(6), dp(2), dp(6), dp(2))
        roomPanelHeader.addView(roomPanelRole, llp(LinearLayout.LayoutParams.WRAP_CONTENT, dp(20), 6))
        roomPanel.addView(
            roomPanelHeader,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT),
        )

        // 分组列表（滚动；Flutter `ListView.padding: vertical 4`）。
        roomPanelList.orientation = LinearLayout.VERTICAL
        roomPanelList.setPadding(0, dp(4), 0, dp(4))
        roomPanelScroll.isFillViewport = true
        roomPanelScroll.addView(roomPanelList)
        roomPanel.addView(
            roomPanelScroll,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f),
        )

        // 播报板 120dp（Flutter：campaign 图标 12 + `播报 (N)` white70 11，
        // padding h10 v6；列表 h10）。
        roomBroadcastIcon.text = String(Character.toChars(NativePlayerIcons.ICON_CAMPAIGN))
        roomBroadcastIcon.typeface = NativePlayerIcons.typeface(context)
        roomBroadcastIcon.setTextColor(NPTheme.WHITE_70)
        roomBroadcastIcon.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        roomBroadcastIcon.gravity = Gravity.CENTER
        roomBroadcastIcon.includeFontPadding = false
        roomBroadcastHeader.setTextColor(NPTheme.WHITE_70)
        roomBroadcastHeader.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        roomBroadcastHeader.typeface = NPTheme.bodyTypeface
        roomBroadcastList.orientation = LinearLayout.VERTICAL
        roomBroadcastList.setPadding(dp(10), 0, dp(10), 0)
        // 【嵌套 apply 陷阱】内层 `ScrollView(context).apply { addView(...) }`
        // 里的 addView 会解析到**外层** LinearLayout（Kotlin 隐式 this），
        // 不是 ScrollView——584 真机回归踩过同类坑。这里显式建变量再挂。
        roomBroadcastScroll.isFillViewport = true
        roomBroadcastScroll.addView(roomBroadcastList)
        // 标题行：campaign 图标 + `播报 (N)`（对齐 Flutter Row）。
        val broadcastTitleRow = LinearLayout(context)
        broadcastTitleRow.orientation = LinearLayout.HORIZONTAL
        broadcastTitleRow.gravity = Gravity.CENTER_VERTICAL
        broadcastTitleRow.setPadding(dp(10), dp(6), dp(10), dp(6))
        broadcastTitleRow.addView(roomBroadcastIcon, llp(dp(12), dp(12)))
        broadcastTitleRow.addView(
            roomBroadcastHeader,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).also { it.marginStart = dp(4) },
        )
        val broadcastWrap = LinearLayout(context)
        broadcastWrap.orientation = LinearLayout.VERTICAL
        broadcastWrap.foreground = rowBottomDivider()
        broadcastWrap.addView(
            broadcastTitleRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        broadcastWrap.addView(
            roomBroadcastScroll,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f),
        )
        roomPanel.addView(
            broadcastWrap,
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(120)),
        )
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
        listener?.onOpenPanel(panel)
        renderOverlays()
        scheduleAutoHide()
    }

    /** 关闭面板。 */
    fun closePanel() {
        if (activePanel == null) return
        activePanel = null
        // 关面板即取消选集封面队列里还没跑的任务（正在跑的 4 个在回贴前
        // 退出），避免关面板后仍在下载几十张图（588 封面提速的配套）。
        NativeLogoLoader.cancelPending()
        listener?.onClosePanel()
        renderOverlays()
    }

    /**
     * 返回键三层语义（对齐 Flutter 播放页 / 鸿蒙 `handleBack`）：
     * 关面板/片尾卡 → 隐控件 → `requestBack` 退出。恒消费。
     *
     * 旧实现 BACK 直接发 requestBack（按返回就退出播放页，缺中间两层，
     * 与 Flutter 操作不一致——真机回归）。
     */
    fun handleBack(): Boolean {
        if (activePanel != null) {
            closePanel()
            return true
        }
        if (segmentCardOpen) {
            segmentCardOpen = false
            segmentConfirmKind = null
            renderOverlays()
            return true
        }
        if (controlsVisible) {
            setControlsVisible(false)
            return true
        }
        listener?.onBack()
        return true
    }

    /**
     * 面板层总渲染：按 activePanel / segmentCardOpen 决定显示哪一层。
     * 决定显示哪一层；无则全部隐藏。
     */
    /**
     * 面板层总渲染：按 activePanel / segmentCardOpen 决定显示哪一层。
     *
     * `PANEL_DECODE` 是特例：Flutter 的解码面板是贴右上的 **180dp popover**
     * （非 260~320 通栏，见 player_screen.dart:7736），故单独走
     * [renderDecodePopover]。
     */
    private fun renderOverlays() {
        val panel = activePanel
        // 解码 popover 与通栏面板互斥（Flutter 同一时刻只显示一个选择器）。
        if (panel == PANEL_DECODE) {
            panelScrim.visibility = VISIBLE
            panelContainer.visibility = GONE
            renderDecodePopover()
        } else {
            decodePopover.visibility = GONE
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
                // 深色磨砂（播放器弹层统一）：深色渐变 + 顶部高光 + 亮描边，
                // 不做背景采样（零跳帧）。选集面板全高贴边时右侧圆角放平。
                panelContainer.background = if (fullBleed) {
                    PanelGlassDrawable(
                        NPTheme.RADIUS_PANEL,
                        resources.displayMetrics.density,
                        flattenRight = true,
                    )
                } else {
                    glassPanel
                }
                panelContainer.layoutParams = lp(
                    panelWidthDp(),
                    LayoutParams.MATCH_PARENT,
                ).also {
                    it.topMargin =
                        if (fullBleed) 0 else dp(NPTheme.PANEL_TOP_OFFSET) + safeTopPx()
                    it.bottomMargin =
                        if (fullBleed) 0 else dp(NPTheme.PANEL_BOTTOM_OFFSET) + safeBottomPx()
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
                    PANEL_EPISODE -> buildEpisodeContent()
                    PANEL_VERSION -> buildListContent(
                        lastState.versions.map { it.displayLabel to it.index },
                        lastState.currentVersionIndex,
                    ) { listener?.onSelectVersion(it) }
                    PANEL_KERNEL -> buildKernelContent()
                    PANEL_DISPLAY -> buildDisplayContent()
                    // PANEL_DECODE 走独立 popover（见函数开头分支）。
                    else -> Unit
                }
            }
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

    /** 面板标题（15sp / w600，左对齐）。 */
    private fun panelHeader(title: String): TextView =
        TextView(context).apply {
            text = title
            // 深色磨砂弹层（587）：标题纯白（顶/底栏同样白字，观感统一）。
            setTextColor(NPTheme.PANEL_TEXT)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_TITLE_SIZE)
            // 586：标题由 BOLD(700) 降到 w600，与 Flutter w600 逐值对齐。
            typeface = NPTheme.mediumTypeface
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
     * 选项行：文字左对齐 + 右侧对勾占 18dp 槽位。
     *
     * 586 统一排版：正文一律纯白 + w500，选中态只靠行底（[NPTheme.SEL_BG]）
     * 与右侧强调色对勾区分——旧实现选中行文字改强调色 + BOLD，同一面板
     * 出现两种字色/字重，观感散乱（用户真机反馈「字体不统一」）。
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
                    setTextColor(NPTheme.PANEL_TEXT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_BODY_SIZE)
                    typeface = NPTheme.bodyTypeface
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
        // 对齐 Flutter SubtitleMenuPanel：「关闭字幕」。
        if (allowOff) items.add("关闭字幕" to (0 to (selectedId == 0)))
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
        // 无轨道占位（对齐 Flutter：「当前视频无内嵌字幕轨道」/「无音轨选项」）。
        if (tracks.isEmpty()) {
            list.addView(
                TextView(context).apply {
                    text = if (allowOff) "当前视频无内嵌字幕轨道" else "当前视频无音轨选项"
                    setTextColor(NPTheme.PANEL_TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_CAPTION_SIZE)
                    typeface = NPTheme.bodyTypeface
                    setPadding(dp(NPTheme.PANEL_PAD_H), dp(8), dp(NPTheme.PANEL_PAD_H), dp(8))
                },
            )
        }
        // 字幕面板底部：分隔线 + 「加载本地字幕文件...」（对齐 Flutter）。
        if (allowOff) {
            list.addView(dividerLine(1f))
            list.addView(
                optionRow("加载本地字幕文件...", false) {
                    listener?.onAddSubtitle()
                    closePanel()
                },
            )
        }
        panelContainer.addView(scrollWrap(list))
    }

    /** 通用列表（选集/线路）。 */
    /**
     * 选集卡片（对齐 Flutter EpisodeSelectPanel）：16:9 封面在上 + `1.集名`
     * 标题在下；选中集主色 2dp 描边 + 右上角半透明黑圆对勾。
     */
    private fun buildEpisodeContent() {
        val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        // 卡片宽 = 面板内容宽（面板 padding h12 对齐 Flutter ListView h12）。
        val cardW = panelWidthDp() - dp(24)
        val coverH = cardW * 9 / 16
        // 按卡片目标宽解码（588）：旧实现固定 960px 上限，900px 宽的封面
        // 也被整图解码——解码耗时与内存都翻倍，20 集排队就更慢。
        val targetPx = cardW.coerceAtLeast(1)
        val currentIdx = lastState.currentEpisodeIndex
        lastState.episodes.forEach { ep ->
            val selected = ep.index == currentIdx
            // 优先级：当前集 0 → 邻集 1 → 其余 2（当前集先出图）。
            val priority = when {
                ep.index == currentIdx -> NativeLogoLoader.PRIORITY_CURRENT
                (ep.index - currentIdx).let { it == 1 || it == -1 } ->
                    NativeLogoLoader.PRIORITY_NEIGHBOR
                else -> NativeLogoLoader.PRIORITY_REST
            }
            val card = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(12), 0, dp(12), dp(10))
                isClickable = true
                setOnClickListener {
                    listener?.onSelectEpisode(ep.index)
                    closePanel()
                }
            }
            // 封面：选中主色描边框（2dp）+ 内裁圆角 8（外框 10）。
            val cover = ImageView(context).apply {
                scaleType = ImageView.ScaleType.CENTER_CROP
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(8).toFloat()
                    setColor(0xFF1A1D23.toInt())
                }
                NativeLogoLoader.load(this, ep.poster.ifBlank { null }, targetPx, priority)
            }
            val coverWrap = FrameLayout(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.RECTANGLE
                    cornerRadius = dp(10).toFloat()
                    setColor(Color.TRANSPARENT)
                    setStroke(dp(2), if (selected) NPTheme.ACCENT else Color.TRANSPARENT)
                }
                addView(cover, lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
                if (selected) {
                    // 对勾徽标：右上角半透明黑圆 + 主色 check（与 Flutter 一致）。
                    val badge = TextView(context).apply {
                        text = String(Character.toChars(NativePlayerIcons.ICON_CHECK))
                        typeface = NativePlayerIcons.typeface(context)
                        setTextColor(NPTheme.ACCENT)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                        gravity = Gravity.CENTER
                        background = GradientDrawable().apply {
                            shape = GradientDrawable.OVAL
                            setColor(0x8C000000.toInt())
                        }
                    }
                    addView(
                        badge,
                        lp(dp(22), dp(22), Gravity.TOP or Gravity.END).also {
                            it.topMargin = dp(6)
                            it.marginEnd = dp(6)
                        },
                    )
                }
            }
            card.addView(coverWrap, lp(cardW, coverH))
            card.addView(
                TextView(context).apply {
                    text = ep.cardTitle
                    // 586 统一排版：正文一律纯白 + w500（选中只靠封面描边与
                    // 对勾表达；旧实现未选中行用次色、选中行 BOLD，同面板两种灰度）。
                    setTextColor(NPTheme.PANEL_TEXT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_BODY_SIZE)
                    typeface = NPTheme.bodyTypeface
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(0, dp(6), 0, 0)
                },
                LinearLayout.LayoutParams(cardW, LinearLayout.LayoutParams.WRAP_CONTENT),
            )
            list.addView(card)
        }
        val scroll = scrollWrap(list)
        panelContainer.addView(scroll)
        // 打开时把当前集滚进视口（与 Flutter EpisodeSelectPanel initState 一致）。
        val selIdx = lastState.episodes.indexOfFirst { it.index == lastState.currentEpisodeIndex }
        if (selIdx > 0) {
            val rowH = coverH + dp(13 + 6 + 10) // 封面 + 标题(13+margin6) + 底距10
            scroll.post { scroll.scrollTo(0, selIdx * rowH) }
        }
    }

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
            // 单行「短名 · 简介」（对齐 Flutter PlayerKernelPanel 的
            // `label: '${shortLabel} · ${descriptionOf(engine)}'`；旧实现
            // 双行堆叠 → 列表行高与 Flutter 不一致）。
            row.addView(
                TextView(context).apply {
                    // 单行「短名 · 简介」：中间的「·」分隔与 Flutter
                    // PlayerKernelPanel 的 label 拼法逐字一致。
                    text = if (opt.description.isEmpty()) {
                        opt.label
                    } else {
                        "${opt.label} · ${opt.description}"
                    }
                    setTextColor(NPTheme.PANEL_TEXT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_BODY_SIZE)
                    typeface = NPTheme.bodyTypeface
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
            )
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
        // 底部说明（对齐 Flutter PlayerKernelPanel 的 Divider + 说明文字）。
        list.addView(dividerLine())
        list.addView(
            TextView(context).apply {
                text = "切换仅影响当前播放，不改变默认引擎；下一集沿用当前内核"
                setTextColor(NPTheme.PANEL_TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_CAPTION_SIZE)
                typeface = NPTheme.bodyTypeface
                setPadding(dp(NPTheme.PANEL_PAD_H), dp(10), dp(NPTheme.PANEL_PAD_H), dp(10))
            },
        )
        panelContainer.addView(scrollWrap(list))
    }

    // ── 显示调节面板（对齐 Flutter DisplayAdjustPanel：字幕段 + 弹幕段
    //    各含滑杆行 + 分隔线 + 「恢复默认」行；段标题 11sp white38 l16 t10）──

    private fun buildDisplayContent() {
        val list = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        list.addView(sectionTitle("字幕"))
        if (lastState.subtitleStyleDisabled) {
            // 位图字幕（PGS/VobSub/DVB）无法重设样式（对齐 Flutter
            // `subtitleStyleDisabled` 分支：提示文案替换字幕滑杆段）。
            list.addView(
                TextView(context).apply {
                    text = "位图字幕（PGS 等）不支持样式调节"
                    setTextColor(NPTheme.PANEL_TEXT_DIM)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_CAPTION_SIZE)
                    typeface = NPTheme.bodyTypeface
                    setPadding(dp(NPTheme.PANEL_PAD_H), dp(8), dp(NPTheme.PANEL_PAD_H), dp(12))
                },
            )
        } else {
            list.addView(sliderRow("大小", lastState.subtitleScale, 0.5, 3.0, 0.05, ::formatScale) {
                listener?.onAdjustDisplay("subtitleScale", it)
            })
            list.addView(sliderRow("位置", lastState.subtitleMarginY.toDouble(), 0.0, 200.0, 2.0, ::formatMarginY) {
                listener?.onAdjustDisplay("subtitleMarginY", it)
            })
            list.addView(sliderRow("延迟", lastState.subtitleDelayMs, -5000.0, 5000.0, 100.0, ::formatDelayMs) {
                listener?.onAdjustDisplay("subtitleDelayMs", it)
            })
            list.addView(sectionDivider())
            list.addView(resetRow("subtitle", isSubtitleDefault()))
        }
        list.addView(sectionDivider())
        list.addView(sectionTitle("弹幕"))
        list.addView(sliderRow("速度", lastState.danmakuSpeed, 0.5, 2.0, 0.05, ::formatScale) {
            listener?.onAdjustDisplay("danmakuSpeed", it)
        })
        list.addView(sliderRow("大小", lastState.danmakuFontSize, 0.5, 2.0, 0.05, ::formatScale) {
            listener?.onAdjustDisplay("danmakuFontSize", it)
        })
        list.addView(sliderRow("透明度", lastState.danmakuOpacity, 0.1, 1.0, 0.05, ::formatPercent) {
            listener?.onAdjustDisplay("danmakuOpacity", it)
        })
        list.addView(sectionDivider())
        list.addView(resetRow("danmaku", isDanmakuDefault()))
        panelContainer.addView(scrollWrap(list))
    }

    /** 字幕段是否处于默认态（恢复默认行的选中态，对齐 Flutter selected 语义）。 */
    private fun isSubtitleDefault(): Boolean =
        Math.abs(lastState.subtitleScale - 1.0) < 1e-6 &&
            lastState.subtitleMarginY == 22 &&
            lastState.subtitleDelayMs.toInt() == 0

    /** 弹幕段是否处于默认态（速度 0.7 / 大小 0.5 / 透明度 0.8，同 Dart 默认）。 */
    private fun isDanmakuDefault(): Boolean =
        Math.abs(lastState.danmakuSpeed - 0.7) < 1e-6 &&
            Math.abs(lastState.danmakuFontSize - 0.5) < 1e-6 &&
            Math.abs(lastState.danmakuOpacity - 0.8) < 1e-6

    /** 段分隔线（Flutter `Divider(color: Colors.white24, height: 1)`）。 */
    private fun sectionDivider(): View =
        View(context).apply {
            setBackgroundColor(NPTheme.PANEL_DIVIDER)
        }.also {
            it.layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(1),
            )
        }

    /** 「恢复默认」行（Flutter `SideOptionRow(label: '恢复默认')`，选中=当前默认态）。 */
    private fun resetRow(scope: String, isDefault: Boolean): View =
        optionRow("恢复默认", isDefault) {
            listener?.onResetDisplay(scope)
            // 面板内容签名不含显示调节数值（防拖动重建）→ 恢复默认后显式
            // 强制重建一次，滑杆/数值回默认位。
            overlayContentSig = ""
            renderOverlays()
            scheduleAutoHide()
        }

    /** 段标题（586 统一排版：12sp 纯白 w500，padding l16 t10 r16 b0）。 */
    private fun sectionTitle(title: String): TextView =
        TextView(context).apply {
            text = title
            setTextColor(NPTheme.PANEL_TEXT)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_CAPTION_SIZE)
            typeface = NPTheme.bodyTypeface
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(NPTheme.PANEL_PAD_H), dp(10), dp(NPTheme.PANEL_PAD_H), 0)
        }

    /**
     * 显示调节滑杆行（对齐 Flutter `styleSliderRow`）：
     * 标签 44dp / **玻璃滑杆**（thumb 18 / 光晕 32，同 Flutter
     * `glassSliderTheme(thumbRadius: 9, overlayRadius: 16)`）/ 数值 48dp 右对齐。
     * 586 统一排版：标签 14sp / w500 纯白，数值 13sp / w500 纯白（旧实现
     * 两者都用次色 54%，在同一面板里比正文浅一档，观感「灰糊」）。
     */
    private fun sliderRow(
        label: String,
        value: Double,
        rangeMin: Double,
        rangeMax: Double,
        step: Double,
        format: (Double) -> String,
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
                setTextColor(NPTheme.PANEL_TEXT)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_BODY_SIZE)
                typeface = NPTheme.bodyTypeface
            },
            LinearLayout.LayoutParams(dp(NPTheme.ADJUST_LABEL_WIDTH), LinearLayout.LayoutParams.WRAP_CONTENT),
        )
        val valueText = TextView(context).apply {
            text = format(value)
            setTextColor(NPTheme.PANEL_TEXT)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = NPTheme.bodyTypeface
            gravity = Gravity.CENTER or Gravity.END
        }
        val bar = GlassSeekBarView(context).apply {
            thumbDp = 18f
            glowDp = 32f
            // 587 面板改深色磨砂：轨道走深色档（白色渐变），黑系轨道在
            // 深底上几乎不可见（与旧「白底看不清白轨道」是同一个问题反向）。
            minValue = rangeMin.toFloat()
            maxValue = rangeMax.toFloat()
            this.step = step.toFloat()
            this.value = value.toFloat()
            onChanged = { v ->
                valueText.text = format(v.toDouble())
                onChange(v.toDouble())
                scheduleAutoHide()
            }
            onCommit = { v ->
                onChange(v.toDouble())
                scheduleAutoHide()
            }
        }
        row.addView(bar, LinearLayout.LayoutParams(0, dp(32), 1f))
        row.addView(
            valueText,
            LinearLayout.LayoutParams(dp(NPTheme.ADJUST_VALUE_WIDTH), LinearLayout.LayoutParams.WRAP_CONTENT),
        )
        return row
    }

    // 数值格式（逐字对齐 Flutter：SubtitleStylePanel / DanmakuStylePanel）。
    private fun formatScale(v: Double): String = String.format(java.util.Locale.US, "%.2f×", v)

    private fun formatMarginY(v: Double): String = "${Math.round(v)}px"

    private fun formatDelayMs(ms: Double): String {
        val sign = if (ms < 0) "-" else "+"
        return "$sign${String.format(java.util.Locale.US, "%.1f", Math.abs(ms) / 1000.0)}s"
    }

    private fun formatPercent(v: Double): String = "${Math.round(v * 100)}%"

    // ── 解码模式（对齐 Flutter DecodeModePanel：180dp 独立 popover）──

    /**
     * 解码 popover：**180dp** 宽、深色磨砂（587）、圆角 8、亮描边、
     * `top = 安全区+48 / right = 12`。
     *
     * Flutter 的解码面板不是右侧 260~320 通栏，而是贴右上角的小 popover
     * （`player_screen.dart:7736` `Positioned(top: padding.top+48, right: 12)`）。
     * 旧实现把它塞进通栏面板，观感与 Flutter 不一致（B10）。
     */
    private fun renderDecodePopover() {
        decodePopover.visibility = VISIBLE
        decodePopover.removeAllViews()
        decodePopover.orientation = LinearLayout.VERTICAL
        // 深色磨砂（与侧栏/片头片尾卡同款），圆角 8 对齐 Flutter。
        decodePopover.background =
            PanelGlassDrawable(NPTheme.RADIUS_DECODE, resources.displayMetrics.density)
        decodePopover.clipToOutline = true
        decodePopover.layoutParams =
            lp(dp(NPTheme.DECODE_PANEL_WIDTH), LayoutParams.WRAP_CONTENT).also {
                it.gravity = Gravity.TOP or Gravity.END
                it.topMargin = dp(NPTheme.PANEL_TOP_OFFSET) + safeTopPx()
                it.marginEnd = dp(NPTheme.PANEL_RIGHT)
            }

        // 标题行：`解码模式` 15 w600 + 当前档位 14 w500（正文一律纯白，
        // 档位不用强调色——强调只由选项行的单选圈/行底表达）。
        val titleRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(8))
            addView(
                TextView(context).apply {
                    text = "解码模式"
                    setTextColor(NPTheme.PANEL_TEXT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.DECODE_TITLE_SIZE)
                    typeface = NPTheme.mediumTypeface
                },
            )
            addView(
                TextView(context).apply {
                    text = decodeModeLabel(lastState.decodeMode)
                    setTextColor(NPTheme.PANEL_TEXT)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.DECODE_VALUE_SIZE)
                    typeface = NPTheme.bodyTypeface
                    setPadding(dp(8), 0, 0, 0)
                },
            )
        }
        decodePopover.addView(titleRow)
        decodePopover.addView(dividerLine())

        DECODE_MODES.forEach { mode ->
            decodePopover.addView(
                decodeOptionRow(mode, selected = lastState.decodeMode == mode) {
                    listener?.onSetDecodeMode(mode)
                    closePanel()
                },
            )
        }
    }

    /** 0.5dp 白 12% 分隔线（Flutter `BorderSide(color: Colors.white12, width: 0.5)`）。 */
    private fun dividerLine(heightDp: Float = 0.5f): View =
        View(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                (heightDp * resources.displayMetrics.density).toInt().coerceAtLeast(1),
            )
            setBackgroundColor(NPTheme.PANEL_DIVIDER)
        }

    /**
     * 解码选项行（逐项对齐 Flutter DecodeModePanel 的行）：
     * radio 图标 16 + 间距 8 + (档位名 14 w500 / 说明 12 w500 白 70%)。
     * 选中行铺 accent@20% 底（统一排版：字色字重不随选中变化）；
     * 每行底边通栏 0.5dp 分隔线（**含末行**，与 Flutter Border bottom 一致）。
     */
    private fun decodeOptionRow(mode: String, selected: Boolean, onTap: () -> Unit): LinearLayout =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            isClickable = true
            setOnClickListener { onTap() }
            if (selected) setBackgroundColor(NPTheme.SEL_BG)
            // 每行底边通栏分隔线：用行容器的前景 drawable 画，不额外插 View
            //（插 View 会让行高多 1px，与 Flutter 的 border 内描边不同）。
            foreground = rowBottomDivider()
            addView(
                iconView(
                    if (selected) NativePlayerIcons.ICON_RADIO_BUTTON_CHECKED
                    else NativePlayerIcons.ICON_RADIO_BUTTON_UNCHECKED,
                    NPTheme.DECODE_RADIO.toFloat(),
                    if (selected) NPTheme.ACCENT else NPTheme.PANEL_TEXT_DIM,
                ),
                llp(dp(NPTheme.DECODE_RADIO), dp(NPTheme.DECODE_RADIO)),
            )
            val col = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(
                    TextView(context).apply {
                        text = decodeModeLabel(mode)
                        setTextColor(NPTheme.PANEL_TEXT)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.DECODE_VALUE_SIZE)
                        typeface = NPTheme.bodyTypeface
                    },
                )
                addView(
                    TextView(context).apply {
                        text = decodeModeDesc(mode)
                        setTextColor(NPTheme.PANEL_TEXT_DIM)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.DECODE_DESC_SIZE)
                        typeface = NPTheme.bodyTypeface
                    },
                )
            }
            // 图标 → 文字 8dp（Flutter SizedBox(width: 8)；旧实现漏了这 8dp）。
            addView(
                col,
                llp(0, LinearLayout.LayoutParams.WRAP_CONTENT).also {
                    it.weight = 1f
                    it.marginStart = dp(8)
                },
            )
        }

    /**
     * 行底 0.5dp 分隔线（只画底边，不占布局高度）。
     *
     * Flutter 的 `Border(bottom: 0.5)` 是内描边；插一个 1px View 会挤高
     * 行高。这里作为 `foreground` 直接画在行底。
     */
    private fun rowBottomDivider(): Drawable = object : Drawable() {
        private val paint = Paint().apply { color = NPTheme.PANEL_DIVIDER }

        override fun draw(canvas: Canvas) {
            val b = bounds
            if (b.isEmpty) return
            val h = (0.5f * resources.displayMetrics.density).toInt().coerceAtLeast(1)
            canvas.drawRect(
                b.left.toFloat(),
                (b.bottom - h).toFloat(),
                b.right.toFloat(),
                b.bottom.toFloat(),
                paint,
            )
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    /** 解码档位中文标签：与 Flutter 播放页 `DecodeModePanel` 同值。 */
    private fun decodeModeLabel(mode: String): String = when (mode) {
        "auto" -> "智能"
        "hw" -> "硬解"
        "sw" -> "软解"
        else -> mode
    }

    /** 解码档位说明（Flutter DecodeModePanel `descriptions`）。 */
    private fun decodeModeDesc(mode: String): String = when (mode) {
        "auto" -> "优先硬解，失败回退软解"
        "hw" -> "纯硬解，失败不回退"
        "sw" -> "纯软解，CPU 占用高"
        else -> ""
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
        segmentCard.background = glassCard
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
                setTextColor(NPTheme.PANEL_TEXT_DIM)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_CAPTION_SIZE)
                typeface = NPTheme.bodyTypeface
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
            val pos = lastState.positionMs.toLong()
            val reject = segmentMarkReject(kind, pos, lastState.durationMs.toLong())
            if (reject != null) {
                // 二次确认也走范围校验：不关卡片，提示原因后可改位置再试。
                showHintFor(reject, 1500, null)
                return@segmentAction
            }
            listener?.onSetSegmentMark(kind, pos)
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
            setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_BODY_SIZE)
            typeface = NPTheme.mediumTypeface
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
                    setTextColor(NPTheme.PANEL_TEXT)
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
                        setTextColor(NPTheme.PANEL_TEXT)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_BODY_SIZE)
                        typeface = NPTheme.bodyTypeface
                    },
                )
                addView(
                    TextView(context).apply {
                        text = hint
                        setTextColor(NPTheme.PANEL_TEXT_DIM)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, NPTheme.PANEL_CAPTION_SIZE)
                        typeface = NPTheme.bodyTypeface
                    },
                )
            }
            addView(col, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).also { it.marginStart = dp(10) })
            addView(
                TextView(context).apply {
                    text = String(Character.toChars(NativePlayerIcons.ICON_CHEVRON_RIGHT))
                    typeface = NativePlayerIcons.typeface(context)
                    setTextColor(NPTheme.PANEL_TEXT_DIM)
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
        // 手势提示/柱条定时器：不清理会在窗口销毁后仍回调（泄漏 + 触空指针）。
        hideGestureHint?.let { mainHandler.removeCallbacks(it) }
        hideGestureHint = null
        hideVerticalBar?.let { mainHandler.removeCallbacks(it) }
        hideVerticalBar = null
        listener = null
    }

    /** 用 Dart 推送的权威快照覆盖本地状态并刷新控件。 */
    fun render(state: AndroidNativePlayerState, snapshotAtMs: Long = System.currentTimeMillis()) {
        lastState = state
        lastStateAtMs = snapshotAtMs
        applyState()
    }

    /**
     * 转屏/小屏自适应：交给 [ScaleDownBox]（顶栏尾簇 / 底栏 trailing）。
     *
     * 旧方案 `applyGroupGap` 只逐级收窄组内间距（20→8→4→0）：间距归零后
     * 内容宽仍可能超过可用宽，流式布局会把控件推出屏外（真机竖屏截图回归）。
     * 单纯 `scaleX/Y` 也只改绘制不改测量宽，同样溢出。改为**测量级**等比
     * 缩小——缩小后的宽度就是容器的测量宽度，父级按它排布兄弟控件，
     * 结构上不可能再溢出。
     *
     * 本函数只负责在状态/布局变化后请求重测（[ScaleDownBox] 的可用宽由
     * 父级传入，必须等一次布局才有值）。
     */
    private fun requestAdaptiveRelayout() {
        topTailBox.requestLayout()
        trailingBox.requestLayout()
    }

    /**
     * 房间资源面板渲染（590）。
     *
     * 展开条件：房间模式 + `state.resourcePanelOpen`。展开时同步通知宿主把
     * surface 收窄 [NPTheme.ROOM_PANEL_WIDTH]（否则视频被面板盖住）。
     *
     * 只在「数据签名」变化时重建列表，避免 500ms tick 反复销毁滚动视图
     * （滚动位置丢失、封面重载闪烁）。
     */
    /**
     * 房间资源面板渲染（592，逐项复刻 Flutter `_buildResourcePanel`）。
     *
     * 展开条件：房间模式 + `state.resourcePanelOpen`。展开时同步通知宿主把
     * surface 收窄 [NPTheme.ROOM_PANEL_WIDTH]（否则视频被面板盖住）。
     *
     * 只在「数据签名」变化时重建列表，避免 500ms tick 反复销毁滚动视图
     * （滚动位置丢失、封面重载闪烁）。
     */
    private fun renderRoomPanel() {
        val state = lastState
        val show = state.isRoom && state.resourcePanelOpen
        val panelPx = if (show) dp(NPTheme.ROOM_PANEL_WIDTH) else 0
        if (panelPx != lastVideoInsetRightPx) {
            lastVideoInsetRightPx = panelPx
            listener?.onVideoInsetRight(panelPx)
        }
        roomPanel.visibility = if (show) VISIBLE else GONE
        if (!show) return

        // ── 头部（对齐 Flutter：Expanded(资源) | 搜索 | 人数 | 角色）──
        roomPanelTitle.text = "资源"
        roomPanelOnline.text = "${state.onlineUserCount}"
        // 搜索按钮：房主 **且未在播放** 才显示（Flutter
        // `_roomData != null && _isHost && state != playing`）。
        // 旧实现只看 isHost（观众端也占位、只调 alpha），逻辑反了。
        roomPanelSearch.visibility =
            if (state.isHost && !state.paused) VISIBLE else GONE
        roomPanelRole.text = if (state.isHost) {
            "房主"
        } else {
            state.audienceName?.takeIf { it.isNotBlank() } ?: "观众"
        }
        roomPanelRole.background = GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(if (state.isHost) NPTheme.ACCENT else 0xFFE53935.toInt())
        }

        // 列表签名：分组/季/集结构 + 折叠态 + 当前集
        val sig = buildString {
            for (g in state.resourceGroups) {
                append(g.name).append('|').append(g.isMovie).append('|')
                    .append(g.collapsed).append(';')
                for (s in g.seasons) {
                    append(s.seasonNumber).append('|').append(s.collapsed).append(';')
                    for (e in s.episodes) {
                        append(e.index).append('|').append(e.isPlaying).append(',')
                    }
                }
                append('/')
            }
        }
        if (sig != roomPanelSig) {
            roomPanelSig = sig
            buildRoomPanelList(state)
        }

        // ── 播报板（对齐 Flutter `_buildBroadcastBoardInPanel`）──
        roomBroadcastHeader.text = "播报 (${state.broadcasts.size})"
        val bsig = state.broadcasts.joinToString("|")
        if (bsig != roomBroadcastSig) {
            roomBroadcastSig = bsig
            roomBroadcastList.removeAllViews()
            if (state.broadcasts.isEmpty()) {
                roomBroadcastList.addView(
                    TextView(context).apply {
                        text = "暂无消息"
                        setTextColor(NPTheme.WHITE_24)
                        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                        gravity = Gravity.CENTER
                        setPadding(0, dp(8), 0, dp(8))
                    },
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ),
                )
            } else {
                for (line in state.broadcasts) {
                    roomBroadcastList.addView(
                        TextView(context).apply {
                            text = line
                            setTextColor(NPTheme.WHITE_54)
                            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                            setPadding(0, dp(2), 0, dp(2))
                        },
                    )
                }
                // 新消息自动滚到底（Flutter `animateTo(maxScrollExtent)`）。
                roomBroadcastScroll.post {
                    roomBroadcastScroll.fullScroll(View.FOCUS_DOWN)
                }
            }
        }
    }

    /** 重建资源分组列表（分组 → 季 → 集，对齐 Flutter `_buildGroupWidget`）。 */
    private fun buildRoomPanelList(state: AndroidNativePlayerState) {
        roomPanelList.removeAllViews()
        if (state.resourceGroups.isEmpty()) {
            roomPanelList.addView(
                TextView(context).apply {
                    text = "暂无资源"
                    setTextColor(NPTheme.WHITE_24)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                    gravity = Gravity.CENTER
                    setPadding(0, dp(24), 0, dp(24))
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
            return
        }
        state.resourceGroups.forEachIndexed { gi, group ->
            roomPanelList.addView(buildRoomGroupHeader(gi, group))
            if (group.collapsed) return@forEachIndexed

            // 电影组：直接列出（Flutter `group.isMovie` 分支不套季循环）。
            if (group.isMovie) {
                group.seasons.firstOrNull()?.episodes?.forEach { ep ->
                    roomPanelList.addView(
                        buildRoomEpisodeRow(ep),
                        LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT,
                        ),
                    )
                }
                return@forEachIndexed
            }

            // 剧集组：按季分组（季标题只在剧集组显示，与 Flutter 一致）。
            group.seasons.forEachIndexed { si, season ->
                roomPanelList.addView(buildRoomSeasonHeader(gi, si, season))
                if (season.collapsed) return@forEachIndexed
                for (ep in season.episodes) {
                    roomPanelList.addView(
                        buildRoomEpisodeRow(ep),
                        LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT,
                        ),
                    )
                }
            }
        }
    }

    /** 分组标题行（chevron + 组名 + 计数），对齐 Flutter 组标题。 */
    private fun buildRoomGroupHeader(
        groupIndex: Int,
        group: AndroidResourceGroup,
    ): LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(8), dp(12), dp(8))
        setBackgroundColor(0xFF16213E.toInt())
        isClickable = true
        setOnClickListener {
            listener?.onToggleResourceGroup(groupIndex)
            scheduleAutoHide()
        }
        applyPressFeedback(this)
        addView(
            iconView(
                if (group.collapsed) NativePlayerIcons.ICON_CHEVRON_RIGHT
                else NativePlayerIcons.ICON_EXPAND_MORE,
                20f,
                NPTheme.WHITE_70,
            ),
            llp(dp(20), dp(20)),
        )
        addView(
            TextView(context).apply {
                text = group.name
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            },
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                .also { it.marginStart = dp(4) },
        )
        addView(
            TextView(context).apply {
                text = group.countLabel
                // Flutter `Colors.white54` 12px（旧实现 WHITE_70 11sp）。
                setTextColor(NPTheme.WHITE_54)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            },
        )
    }

    /** 季标题行（chevron + 第N季 + (N集)），对齐 Flutter `_buildSeasonWidget`。 */
    private fun buildRoomSeasonHeader(
        groupIndex: Int,
        seasonIndex: Int,
        season: AndroidSeasonGroup,
    ): LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        // Flutter `EdgeInsets.only(left: 24, right: 12, top: 6, bottom: 6)`。
        setPadding(dp(24), dp(6), dp(12), dp(6))
        setBackgroundColor(0xFF1A1A2E.toInt())
        isClickable = true
        setOnClickListener {
            listener?.onToggleResourceSeason(groupIndex, seasonIndex)
            scheduleAutoHide()
        }
        applyPressFeedback(this)
        addView(
            iconView(
                if (season.collapsed) NativePlayerIcons.ICON_CHEVRON_RIGHT
                else NativePlayerIcons.ICON_EXPAND_MORE,
                // Flutter `size: 16` + `Colors.white54`。
                16f,
                NPTheme.WHITE_54,
            ),
            llp(dp(16), dp(16)),
        )
        addView(
            TextView(context).apply {
                text = "第${season.seasonNumber}季"
                // Flutter white70 12 w500。
                setTextColor(NPTheme.WHITE_70)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                typeface = NPTheme.bodyTypeface
            },
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                .also { it.marginStart = dp(4) },
        )
        addView(
            TextView(context).apply {
                // Flutter 季标题右侧 `(N集)` white38 11px。
                text = "(${season.episodes.size}集)"
                setTextColor(NPTheme.WHITE_38)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            },
        )
    }

    /**
     * 单条资源行（逐项复刻 Flutter `_buildEpisodeListItem`）。
     *
     * 结构：`[左 3dp accent 边] 播放/暂停(房主) 缩略图56×36 集信息 删除(房主)`
     * 当前集：accent@30% 底 + 左 3dp accent 边。
     */
    private fun buildRoomEpisodeRow(ep: AndroidResourceItem): LinearLayout =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            // Flutter `EdgeInsets.symmetric(horizontal: 8, vertical: 6)`。
            setPadding(dp(8), dp(6), dp(8), dp(6))
            if (ep.isPlaying) {
                // Flutter `Color(0xFF6366F1).withValues(alpha: 0.3)`。
                setBackgroundColor(0x4D6366F1)
            }
            isClickable = true
            setOnClickListener {
                if (lastState.isHost) {
                    if (ep.isPlaying) listener?.onTogglePlay()
                    else listener?.onSelectEpisode(ep.index)
                }
                scheduleAutoHide()
            }
            applyPressFeedback(this)

            // 当前集左侧 3dp accent 竖条（Flutter `Border(left: BorderSide(accent, 3))`）。
            // 旧实现只有底色、缺左边框。
            if (ep.isPlaying) {
                addView(
                    View(context).apply { setBackgroundColor(NPTheme.ACCENT) },
                    llp(dp(3), dp(44)),
                )
            }

            // 播放/暂停（房主）
            if (lastState.isHost) {
                addView(
                    iconView(
                        if (ep.isPlaying && !lastState.paused) {
                            NativePlayerIcons.ICON_PAUSE_CIRCLE
                        } else {
                            NativePlayerIcons.ICON_PLAY_CIRCLE
                        },
                        22f,
                        if (ep.isPlaying) NPTheme.ACCENT else NPTheme.WHITE_54,
                    ),
                    llp(dp(22), dp(22)),
                )
                addView(View(context), llp(dp(8), dp(1)))
            }

            // 缩略图 56×36（圆角 4；无图时灰底 + movie 图标，与 Flutter 一致）。
            addView(
                FrameLayout(context).apply {
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.RECTANGLE
                        cornerRadius = dp(4).toFloat()
                        setColor(0xFF424242.toInt())
                    }
                    if (ep.poster.isBlank()) {
                        addView(
                            iconView(NativePlayerIcons.ICON_MOVIE, 16f, 0xFF9E9E9E.toInt()),
                            lp(dp(16), dp(16), Gravity.CENTER),
                        )
                    } else {
                        addView(
                            ImageView(context).apply {
                                scaleType = ImageView.ScaleType.CENTER_CROP
                                NativeLogoLoader.load(
                                    this,
                                    ep.poster,
                                    dp(56),
                                    NativeLogoLoader.PRIORITY_REST,
                                )
                            },
                            FrameLayout.LayoutParams(
                                FrameLayout.LayoutParams.MATCH_PARENT,
                                FrameLayout.LayoutParams.MATCH_PARENT,
                            ),
                        )
                    }
                },
                llp(dp(56), dp(36)),
            )
            addView(View(context), llp(dp(8), dp(1)))

            // 集信息
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    if (ep.isMovie) {
                        addView(
                            TextView(context).apply {
                                text = ep.name
                                setTextColor(if (ep.isPlaying) Color.WHITE else NPTheme.WHITE_54)
                                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                                maxLines = 1
                                ellipsize = TextUtils.TruncateAt.END
                            },
                        )
                    } else {
                        addView(
                            TextView(context).apply {
                                text = ep.episodeCode
                                setTextColor(if (ep.isPlaying) NPTheme.ACCENT else NPTheme.WHITE_70)
                                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                            },
                        )
                        addView(
                            TextView(context).apply {
                                text = ep.name
                                setTextColor(if (ep.isPlaying) Color.WHITE else NPTheme.WHITE_54)
                                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                                maxLines = 1
                                ellipsize = TextUtils.TruncateAt.END
                            },
                        )
                    }
                },
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
            )

            // 删除（房主）
            if (lastState.isHost) {
                addView(
                    iconView(NativePlayerIcons.ICON_CLOSE, 18f, NPTheme.WHITE_24).apply {
                        isClickable = true
                        setOnClickListener {
                            listener?.onRemoveResourceEpisode(ep.index)
                            scheduleAutoHide()
                        }
                        applyPressFeedback(this)
                    },
                    llp(dp(24), dp(24)),
                )
            }
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

        // 竖屏隐藏标题（照抄鸿蒙：竖屏可用宽窄，标题会被尾簇压成「…」；
        // 空文本 + 取消保底宽，仍占权重防尾簇左移贴返回键）。
        val portrait = height > width
        titleText.text = if (portrait) "" else state.displayTitle
        titleText.minimumWidth = if (portrait) 0 else dp(NPTheme.TITLE_MIN_WIDTH)
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
        // 【不禁用】isEnabled=false 的 View 不触发 onClick（真机回归「播放/
        // 上下集点了没反应」）：颜色置灰表达不可用，点击仍有按下反馈、
        // onClick 内部条件守卫不执行动作（对齐 Flutter TransportGlyph）。

        // 角标：仅数值变化时重算尺寸/重排（旧实现每 500ms 重设 layoutParams
        // → 角标视觉抖动，与其他引擎观感不一致）。
        //
        // 590 兜底：对 provider 结果再做一次 `toIntOrNull()?.takeIf { > 0 }`，
        // 挡住上游可能传来的 "0" / " " / 负数（否则显示空白圆点）。
        badgeTags.forEach { (badge, provider) ->
            val raw = provider()
            val text = raw?.trim()?.toIntOrNull()?.takeIf { it > 0 }?.toString()
            if (badgeLastText[badge] == text) return@forEach
            badgeLastText[badge] = text
            badge.text = text ?: ""
            badge.visibility = if (text.isNullOrEmpty()) GONE else VISIBLE
            badge.layoutParams = badgeLayoutParams(text.orEmpty())
        }

        // 顶栏网速
        networkText.text = state.networkSpeedText ?: ""
        networkText.visibility = if (state.networkSpeedText != null) VISIBLE else GONE

        // 房间资源面板（590）：显隐 + 列表 + 播报 + surface 收窄。
        renderRoomPanel()

        // 弹幕层：状态参数 + 时间窗（原生渲染，Flutter 弹幕层随视频区退场）。
        danmakuLayer.update(
            state.danmakuItems,
            state.danmakuEnabled && !state.isRoom,
            state.danmakuSpeed,
            state.danmakuFontSize,
            state.danmakuOpacity,
            state.danmakuScrollRows,
            state.danmakuTopRows,
            state.danmakuBottomRows,
        )

        // 时间数显
        if (!dragging) {
            val pos = state.positionAt(now, lastStateAtMs)
            positionLabel.text = AndroidNativePlayerState.formatPlayerTime(pos)
            danmakuLayer.setClock(pos, state.paused)
            // 玻璃滑杆：值即毫秒（玻璃滑杆内部完成 ratio 映射，无步进换算）。
            // durationMs 未就绪（起播早期为 0）时不覆盖 value（防归零抖动）。
            if (state.durationMs > 0) {
                seekBar.minValue = 0f
                seekBar.maxValue = state.durationMs.toFloat()
                // seek 保护窗：提交后权威位置还没追上目标时保持目标值，
                // 否则 tick 会用旧位置覆盖 → 观感「拖一下就弹回去」。
                val target = pendingSeekMs
                if (target != null) {
                    val reached = Math.abs(pos - target) <= PENDING_SEEK_TOLERANCE_MS
                    val expired = now - pendingSeekAtMs > pendingSeekTimeoutMs
                    if (reached || expired) {
                        pendingSeekMs = null
                        seekBar.value = pos.toFloat()
                    } else {
                        // 保护期内滑杆停在目标位（数显也停在目标，避免数字
                        // 与滑块自相矛盾）。
                        seekBar.value = target.toFloat()
                        positionLabel.text =
                            AndroidNativePlayerState.formatPlayerTime(target)
                    }
                } else {
                    seekBar.value = pos.toFloat()
                }
            }
        }
        durationLabel.text = AndroidNativePlayerState.formatPlayerTime(state.durationMs.toLong())
        // 恒可触摸（真机回归「进度条拖不动」）：旧实现 `!isLiveLike`（duration<=0
        // 即禁用）把起播早期的滑杆锁死；空范围由 GlassSeekBarView 自守卫。
        seekBar.isEnabled = true

        // 诊断行
        val diag = buildDiag(state)
        diagText.text = diag
        diagText.visibility = if (state.showDebug && diag.isNotEmpty()) VISIBLE else GONE

        // 加载指示器（586）：统一读快照的 `showLoading`（首帧未出 **或**
        // 缓冲中），不再自己判 `state.buffering`——否则 Flutter 首帧转圈时
        // 安卓不转、安卓中途缓冲转时 Flutter 不转。
        bufferingView.visibility = if (state.showLoading) VISIBLE else GONE

        // TV / 手机布局差异
        applyLayoutMode(state)

        // 面板开着时按内容签名重建（高亮跟随）。签名**不含显示调节数值**：
        // 否则拖滑杆时每帧变签名 → 面板每帧重建打断拖动（真机回归）；
        // 旧实现每 500ms 无条件重建 → 拖动被打断、TV 焦点丢。
        if (activePanel != null || segmentCardOpen) {
            val sig = "$activePanel|$segmentCardOpen|$segmentConfirmKind|" +
                "${lastState.selectedAudioId}|${lastState.selectedSubtitleId}|" +
                "${lastState.tracks.size}|${lastState.engineLabel}|" +
                "${lastState.versions.size}|${lastState.currentVersionIndex}|" +
                "${lastState.episodes.size}|${lastState.currentEpisodeIndex}|" +
                "${lastState.segmentIntroEndMs}|${lastState.segmentOutroStartMs}"
            if (sig != overlayContentSig) {
                overlayContentSig = sig
                renderOverlays()
            }
        }
    }

    /** 面板内容签名（见 applyState：仅签名变化才重建面板）。 */
    private var overlayContentSig = ""

    private fun applyLayoutMode(state: AndroidNativePlayerState) {
        val tv = state.tvMode
        // 顶栏可见项
        speedChip.visibility = if (!tv && !state.isRoom) VISIBLE else GONE
        subtitleStyleChip.visibility = if (!tv) VISIBLE else GONE
        // 解码：Erika 无解码档位 → 隐藏（对齐 Flutter showDecodeButton && !erika）。
        decodeChip.visibility = if (!tv && state.engineLabel != "Erika") VISIBLE else GONE
        // 画面比例：Erika 缩放不可用、房间不显示（对齐 Flutter 判定）。
        videoFitIcon.visibility =
            if (!tv && !state.isRoom && state.engineLabel != "Erika") VISIBLE else GONE
        rotateIcon.visibility = if (!tv) VISIBLE else GONE
        // 分享：仅房间模式（对齐 Flutter showShare）。
        shareButton.visibility = if (state.isRoom) VISIBLE else GONE
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

        // 跳过片头/片尾胶囊（照抄鸿蒙 ControlRow）：图标/文案随 intro/outro
        // 切换，显隐由 Dart skipPrompt + segmentEnabled 驱动。
        if (state.skipPrompt.isNotEmpty()) {
            val intro = state.skipPrompt == "intro"
            skipPromptIcon.text = String(
                Character.toChars(
                    if (intro) NativePlayerIcons.ICON_SKIP_NEXT
                    else NativePlayerIcons.ICON_SKIP_PREVIOUS,
                ),
            )
            skipPromptLabel.text = if (intro) "跳过片头" else "跳过片尾"
        }
        skipPromptChip.visibility =
            if (state.skipPrompt.isNotEmpty() && state.segmentEnabled) VISIBLE else GONE

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
        (leadingGroup.layoutParams as? LinearLayout.LayoutParams)?.width = cellW

        // Logo（房间模式/无图时隐藏）
        val showLogo = state.logoUrl != null && state.logoUrl!!.isNotEmpty() && !state.isRoom
        // 网络加载失败时加载器会隐藏 logoImage（与 Flutter EmbyImage 一致）。
        // 按展示宽解码（588）：Logo 容器 240dp 宽，旧实现按 960px 解码。
        NativeLogoLoader.load(
            logoImage,
            if (showLogo) state.logoUrl else null,
            dp(NPTheme.LOGO_WIDTH),
        )
        // Logo 与进度条间的 4dp 间隙只在显示 Logo 时存在（Flutter if(showLogo) 块内）。
        logoSpacer.visibility = if (showLogo) VISIBLE else GONE

        // 锁定态（对齐 Flutter _buildLockOnlyControls）：顶栏整体隐藏、底栏
        // 只留锁钮（与时间数显同列）、进度条/Logo/面板全关。
        if (!tv && state.locked) {
            topBar.visibility = GONE
            // 底栏不藏：锁定态锁钮在底栏 leading 槽（对齐 Flutter
            // _buildLockOnlyControls 只留锁钮）。
            seekRow.visibility = GONE
            logoImage.visibility = GONE
            logoSpacer.visibility = GONE
            diagText.visibility = GONE
            transportGroup.visibility = GONE
            trailingGroup.visibility = GONE
            skipPromptChip.visibility = GONE
            leadingGroup.visibility = VISIBLE
            lockButton.text = String(Character.toChars(NativePlayerIcons.ICON_LOCK))
            // 锁定中不允许面板（Flutter 面板层带 !locked 条件）。
            if (activePanel != null || segmentCardOpen) {
                activePanel = null
                segmentCardOpen = false
                segmentConfirmKind = null
                listener?.onClosePanel()
            }
        } else {
            // 【必须尊重 controlsVisible】旧代码无条件设 VISIBLE，会把
            // setControlsVisible(false) 刚隐藏的控件立刻强制显示回来
            //（真机回归：控件不会自动隐藏）。只恢复子控件，顶栏/底栏
            // 的显隐由 setControlsVisible 统一控制。
            seekRow.visibility = VISIBLE
            transportGroup.visibility = VISIBLE
            trailingGroup.visibility = VISIBLE
            leadingGroup.visibility = if (!tv) VISIBLE else GONE
            // 顶栏/底栏不强制 VISIBLE，交给 setControlsVisible。
            topBar.visibility = if (controlsVisible) VISIBLE else GONE
            bottomBar.visibility = if (controlsVisible) VISIBLE else GONE
        }

        // 转屏/小窗自适应：交给 ScaleDownBox（测量级等比缩，不出屏、不与
        // 传输组重叠）。
        requestAdaptiveRelayout()
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

    /**
     * 尺寸变化（转屏 / 折叠展开 / 分屏）→ 重测两个缩放容器。
     *
     * [ScaleDownBox] 的可用宽来自父级 MeasureSpec，父级尺寸变了必须重新
     * 走一遍测量，否则竖屏/横屏切换后仍按旧比例渲染（真机回归：转屏后
     * 控件不重排）。
     */
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w != oldw || h != oldh) {
            requestAdaptiveRelayout()
        }
    }

    companion object {
        const val SEEK_STEPS = 1000
        const val TICK_MS = 500L
        const val AUTO_HIDE_MS = 5000L
        /**
         * seek 保护窗的「已追上」判定容差。
         *
         * mpv 实际落点通常与目标有几十毫秒偏差（关键帧对齐），容差过小会
         * 让保护窗永远不释放（只能等 2s 超时）；1s 足够宽松又能及时解锁。
         */
        const val PENDING_SEEK_TOLERANCE_MS = 1000L


        // ── 手势（对齐 Flutter player_screen.dart）──
        /** 长按临时倍速倍率（Flutter `PlayerScreen.speedBoostMultiplier`）。 */
        const val PlayerScreenSpeedBoostMultiplier = 2.0
        /** 手势文本提示显示时长（Flutter `_showGestureHint` 800ms）。 */
        const val GESTURE_HINT_TEXT_MS = 800L
        /** 手势图标提示显示时长（Flutter `_showGestureIcon` 500ms）。 */
        const val GESTURE_HINT_ICON_MS = 500L
        /** 手势提示字号：图标态 48sp（Flutter `Icon(size: 48)`）/ 文本态 16sp。 */
        const val GESTURE_ICON_SIZE_SP = 48f
        const val GESTURE_TEXT_SIZE_SP = 16f
        /** 横拖换算系数：每 100px → 5000ms（Flutter `_onHorizontalDragUpdate`）。 */
        const val DRAG_PX_PER_5S = 100f
        const val DRAG_MS_PER_5S = 5000L
        /** seek 相对跳转上限（Flutter `_seekRelative` ±60s）。 */
        const val SEEK_MAX_DELTA_MS = 60_000L
        /** 纵拖换算系数：600px → 全量程（Flutter `_onVerticalDragUpdate`）。 */
        const val VERTICAL_PX_PER_FULL = 600f

        // ── 手势方向锁（591）──
        // 旧实现每帧用 |dx|>|dy| 重判方向 → 斜向拖动会在横/纵之间来回切换，
        // 上滑时误改进度。现在首次超 slop 时一次性定轴。
        const val AXIS_NONE = 0
        const val AXIS_HORIZONTAL = 1
        const val AXIS_VERTICAL = 2

        /** 房间面板签名哨兵（不可能与真实数据相等，见 roomPanelSig 注释）。 */
        const val ROOM_SIG_UNBUILT = "\u0000unbuilt"

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
