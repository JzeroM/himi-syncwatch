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
     * 资源行播放/暂停图标登记表（598）：`图标视图 → 是否当前集`。
     *
     * 【真机回归：图标与实际播放状态不匹配】列表签名只含 `isPlaying`
     * （是否当前集），**不含 `paused`**；而图标判定是
     * `ep.isPlaying && !lastState.paused`。暂停/恢复时签名不变 →
     * `buildRoomPanelList()` 不重跑 → 图标停留在建列表那一刻的值
     * （播放中建的就永远是暂停圈）。
     *
     * 修法对齐 Flutter `ValueListenableBuilder` 逐行监听：**不重建列表**，
     * 只就地改图标文字/颜色（[refreshRoomPlayIcons]）。把 `paused` 加进
     * 签名也能修，但每次暂停都整表重建 → 滚动位置归零、封面重新解码闪烁。
     */
    private val roomPlayIcons = mutableListOf<Pair<TextView, Boolean>>()

    /**
     * 播报板数据签名。
     *
     * 同上：初值 `""` 与「零播报」的 `joinToString("|") == ""` 相等 → 从不
     * 重建 → 只显示标题 `播报 (0)`、列表空白。
     */
    private var roomBroadcastSig: String = ROOM_SIG_UNBUILT

    /** 上次通知宿主的视频右侧留白（像素，0 = 全屏）。 */
    private var lastVideoInsetRightPx: Int = -1

    /** 上次应用的控件层分栏留白（像素，0 = 全屏）。 */
    private var lastVideoSplitInsetPx: Int = -1


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

    /**
     * 625：把手势提示在**视频区**内居中。
     *
     * 旧实现用 `Gravity.CENTER` 相对根 FrameLayout（全屏）居中——横屏
     * 分栏时视频区只有 `屏宽 - 320dp`，居中点偏右，双击播放/暂停图标、
     * 长按 2 倍速图标、横拖 seek 预览全部落到资源面板一侧（真机回归）。
     *
     * `WRAP_CONTENT` 必须 `post{}` 拿实测宽高才能算准居中偏移。
     */
    private fun positionGestureHintInVideoArea() {
        val videoW = videoAreaWidth()
        val videoH = videoAreaHeight()
        gestureHint.post {
            val w = gestureHint.width
            val h = gestureHint.height
            if (w <= 0 || h <= 0) return@post
            (gestureHint.layoutParams as? LayoutParams)?.let {
                it.gravity = Gravity.START or Gravity.TOP
                it.leftMargin = ((videoW - w) / 2).coerceAtLeast(0)
                it.topMargin = ((videoH - h) / 2).coerceAtLeast(0)
                gestureHint.layoutParams = it
            }
        }
    }

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
        // 625：每次显示按当前视频区重算居中位置（分栏/转屏后视频区会变）。
        positionGestureHintInVideoArea()
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
        // 622：指示器在**视频区**内垂直居中（横竖屏都对）。
        //
        // 旧实现 `Gravity.CENTER_VERTICAL` 相对根 FrameLayout（全屏）居中
        // ——竖屏分栏时视频区只占上方（屏高 - 280dp 资源面板），指示器会
        // 偏下、落在资源面板区域（真机截图回归）。
        //
        // 改 `TOP` + 精确 topMargin = (视频区高 - 指示器高) / 2。
        // 624：长度统一为**视频区高 40%**（旧实现固定 dp(160)，与 Flutter
        // 的 70% 屏高、鸿蒙的 70% 视频区高都不一致）。
        val videoH = videoAreaHeight()
        val videoW = videoAreaWidth()
        val barH = (videoH * 0.4f).toInt()
        val barW = dp(NPTheme.GAUGE_WIDTH)
        val edge = dp(NPTheme.GAUGE_EDGE)
        val lp = verticalBar.layoutParams as? LayoutParams
        if (lp != null) {
            // 625：统一 `Gravity.START` + 精确 `marginStart`。
            //
            // 旧实现亮度用 `Gravity.END`（贴**全屏**右缘）+ `marginEnd`——
            // 横屏分栏时视频区只有 `屏宽 - 320dp`，亮度柱正好落在资源
            // 面板上（真机回归）。改用 START 后横向位置完全由视频区宽
            // 决定，不受根 FrameLayout 尺寸影响。
            lp.gravity = Gravity.START or Gravity.TOP
            lp.topMargin = ((videoH - barH) / 2).coerceAtLeast(0)
            lp.marginStart = if (brightness) {
                // 亮度贴**视频区**右缘
                (videoW - barW - edge).coerceAtLeast(0)
            } else {
                // 音量贴视频区左缘
                edge
            }
            lp.marginEnd = 0
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
                // 622：音量/亮度是**本地设备属性**，与房间同步无关
                // → 所有成员（含观众）都能调。只保留锁定态检查。
                // 横拖 seek 是播放控制，仍在下面单独检查 canControl。
                if (lastState.locked) return false
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
                    // 622：横拖 seek 是**播放控制** → 观众不允许（只提示不 seek）。
                    if (!lastState.canControl) return false
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
    /**
     * 642：TV 模式下的网速（移到**最右**，原系统时钟位置）。
     *
     * 手机仍用 [networkText]（在尾簇首位）。两者同时只有一个 VISIBLE，
     * 由 [applyLayoutMode] 按 tvMode 切换——不复用同一个 View，避免
     * LinearLayout 子项顺序在不同父容器间搬移。
     */
    private val networkTextTv = TextView(context)
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

    /**
     * 空态占位（610）：无播放内容时盖住视频区。
     *
     * 【真机回归：删除正在播放的资源后旧画面还在】Flutter 侧删除当前集时置
     * `_isPlayerReady = false` → 视频区走「▶ + 请从资源面板选择要播放的
     * 内容」占位分支。安卓原生侧此前**完全没有**占位 UI，mpv `stop()` 后
     * surface 上残留的最后一帧一直可见。
     *
     * **必须有不透明黑底**：mpv stop 后 surface 残留最后一帧，透明占位层
     * 会让旧画面透出来（真机截图能看到人像隐约浮现）。
     * 尺寸/颜色/间距逐值对齐 Flutter：图标 64 / 间距 16 / 文案 14。
     */
    private val placeholderView = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setBackgroundColor(Color.BLACK)
        visibility = GONE
        addView(
            iconView(NativePlayerIcons.ICON_PLAY_CIRCLE, 64f, NPTheme.WHITE_24),
            LinearLayout.LayoutParams(dp(64), dp(64)),
        )
        addView(
            TextView(context).apply {
                text = "请从资源面板选择要播放的内容"
                setTextColor(NPTheme.WHITE_38)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                gravity = Gravity.CENTER
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).also { it.topMargin = dp(16) },
        )
    }

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
        // 空态占位（610）：全屏不透明黑底，盖住 mpv stop 后的残留帧。
        // 加在 bufferingView 之前 → z-order 低于转圈（起播时转圈仍可见）。
        placeholderView.visibility = GONE
        addView(placeholderView, lp(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        bufferingView.visibility = GONE
        // 622：加载指示器在**视频区**内居中（旧实现 Gravity.CENTER 相对
        // 全屏 → 竖屏分栏时落到资源面板区域）。36dp 固定尺寸，直接算；
        // 显示时由 positionBufferingInVideoArea() 按当前视频区重算。
        addView(bufferingView, lp(dp(36), dp(36), Gravity.START or Gravity.TOP))

        addView(topBar, lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.TOP))
        topBar.clipChildren = false
        topBar.clipToPadding = false
        addView(bottomBar, lp(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))
        bottomBar.clipChildren = false
        bottomBar.clipToPadding = false

        // 手势提示（居中胶囊）与亮度/音量柱条：视频之上、控件之下，
        // 与 Flutter `_buildGestureHint` / `_buildVerticalBar` 的层级一致。
        // 625：手势提示改用 START/TOP + 精确 margin（视频区内居中）。
        //
        // 旧实现 `Gravity.CENTER` 相对**根 FrameLayout（全屏）**居中——
        // 横屏分栏时视频区只有 `屏宽 - 320dp`，居中点偏右，图标落到
        // 资源面板一侧（真机回归）。位置由
        // [positionGestureHintInVideoArea] 在每次显示时重算。
        addView(
            gestureHint,
            lp(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.START or Gravity.TOP),
        )
        addView(
            verticalBar,
            // 622：初始也用 TOP（运行时由 paintVerticalBar 按视频区高重算）。
            // 624：初始高度同步改 40%（避免首帧跳动）。
            // 625：gravity 改 START（旧 END 贴**全屏**右缘 → 横屏分栏时
            // 亮度柱落到资源面板上）；横向位置由 marginStart 精确控制。
            lp(
                dp(NPTheme.GAUGE_WIDTH),
                (videoAreaHeight() * 0.4f).toInt(),
                Gravity.START or Gravity.TOP,
            ),
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
        // 房间资源面板（590）：右侧分栏，铺满高度。
        //
        // 【681 真机回归：视频与面板之间有缝隙漏底光】
        // 旧实现用固定 `dp(ROOM_PANEL_WIDTH)` + `Gravity.END` —— 面板左缘
        // 由「屏幕宽 - dp(320)」算出，而视频窗右缘由 Flutter 下发的
        // `insetPx`（dp × dpr 取整）算出。**两条独立取整路径**必然差
        // 1~2px → 中间露一条底光。
        //
        // 改为「从视频右缘铺到屏幕右缘」：宽度 MATCH_PARENT、
        // `leftMargin = 视频区宽 - 1`（-1 让面板盖住视频右缘那 1px）。
        // 面板宽度自适应，不再依赖两个数值相等。
        addView(
            roomPanel,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ).also {
                it.gravity = Gravity.START or Gravity.TOP
                it.leftMargin = 0  // 由 renderRoomPanel 按视频区宽动态设置
            },
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

    /**
     * 顶栏：时钟 / 返回 / 标题 /（手机）网速·倍速·内核·字幕样式·解码·
     * 画面比例·转屏 /（TV）网速在最右。
     *
     * 642 结构（顺序固定，靠 visibility 切换模式）：
     * - 手机：`[返回][标题]...[网速 倍速 内核 …][（无）]`
     * - TV：`[时钟][标题]...[（尾簇）][网速]`（返回 GONE、时钟跟随设置）
     */
    private fun configureTopBar() {
        // 幂等：重排（手机↔TV）会二次进入本函数，必须先清空容器，
        // 否则对已有 parent 的子视图重复 addView 会抛 IllegalStateException。
        topBar.removeAllViews()
        clockWrap.removeAllViews()
        topBar.orientation = LinearLayout.HORIZONTAL
        topBar.gravity = Gravity.CENTER_VERTICAL
        applyBarInsets()
        topBar.background = barGradient(topSolid = true)

        // 642：TV 时钟占最左（返回按钮已隐藏，左侧空出）；手机最左仍是
        // 返回按钮。两者都常驻为 topBar 子项、只靠 visibility 切换 →
        // 顺序稳定，无需运行时搬移（configureTopBar 幂等重建即可）。
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
        // 642：网速不再挂尾簇——TV 时它在 topBar 最右（见函数末尾），
        // 手机时也在 topBar 尾簇之前独立定位，靠 visibility 切换。
        // 手机网速（12sp white70）仍在尾簇首位（Flutter 非 TV 顶栏顺序）。
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

        // 680：分享按钮已移到**房间资源面板头部**（对齐 Win 版位置），
        // 顶栏不再放（旧实现在这里 topTail.addView(shareButton)）。

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

        // 642：TV 网速（最右，原时钟位置）与手机网速（尾簇首位）二选一。
        networkTextTv.setTextColor(NPTheme.WHITE_70)
        networkTextTv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        networkTextTv.gravity = Gravity.CENTER
        networkTextTv.visibility = GONE
        topBar.addView(
            networkTextTv,
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
        seekBar.onCommit = commit@{ v ->
            // 622：房间观众不得拖进度。
            if (!lastState.canControl) {
                // 回弹到当前权威位置（否则滑杆停在观众拖到的位置）。
                seekBar.value = lastState.positionAt(
                    System.currentTimeMillis(),
                    lastStateAtMs,
                ).toFloat()
                dragging = false
                return@commit
            }
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
        // 622：房间观众不得控制播放/暂停、切集。
        // 旧实现只在**手势层**检查 `canControl`，按钮层完全没守卫 →
        // 观众点底栏播放/上一集/下一集仍然生效（真机回归）。
        prevButton.setOnClickListener {
            if (!lastState.canControl) return@setOnClickListener
            if (lastState.currentEpisodeIndex > 0) {
                listener?.onSelectEpisode(lastState.currentEpisodeIndex - 1)
            }
            scheduleAutoHide()
        }
        playPauseButton.setOnClickListener {
            if (!lastState.canControl) return@setOnClickListener
            listener?.onTogglePlay()
            scheduleAutoHide()
        }
        nextButton.setOnClickListener {
            if (!lastState.canControl) return@setOnClickListener
            if (lastState.currentEpisodeIndex < lastState.episodes.size - 1) {
                listener?.onSelectEpisode(lastState.currentEpisodeIndex + 1)
            }
            scheduleAutoHide()
        }
    }

    /** TV：为所有可交互控件开启 D-pad 焦点并挂焦点环。 */
    private fun applyFocusability() {
        // 642：TV 隐藏返回按钮 → 不加入焦点链，避免遥控焦点落到不可见控件。
        // 手机保留（触摸设备不依赖 D-pad，但保持一致的可聚焦语义）。
        val tv = lastState.tvMode
        val focusables = listOfNotNull(
            if (tv) null else backButton,
            speedChip, kernelChip, subtitleStyleChip, decodeChip,
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
        // 680：房间资源面板底——**必须不透明**。
        //
        // 【真机回归：面板文字出现两层重影】一度改成 65% 半透明
        //（0xA61A1D23）想模仿 Win 的液态玻璃，但安卓的视频层是
        // **SurfaceView**（独立硬件合成层）——半透明 View 压在它上面时，
        // 合成器会把 View 层叠加两次（截图：`资源`/剧名/集名全部错位重影）。
        //
        // 结论：SurfaceView / XComponent 这类独立硬件层之上**不能放半透明
        // 大面积容器**。这里用不透明深色（视觉仍是深色卡片 + 圆角 + 描边），
        // 只让**内部小卡片**（分组/集行/播报板）保留轻微半透明——
        // 它们面积小、且下方是同层的不透明面板底，不会触发该问题。
        roomPanel.background = GradientDrawable().apply {
            cornerRadius = dp(16).toFloat()
            setColor(0xFF1A1D23.toInt())
            setStroke(dp(1), 0x33FFFFFF)
        }
        roomPanel.elevation = dp(8).toFloat()

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

        // 680：分享按钮移到**面板头部**（对齐 Win：资源 | 搜索 | 人数 | 角色 | 分享）。
        // 旧实现放在顶栏尾簇，与 Win 版位置不一致（用户要求三端统一）。
        shareButton.text = String(Character.toChars(NativePlayerIcons.ICON_SHARE))
        shareButton.typeface = NativePlayerIcons.typeface(context)
        shareButton.setTextColor(Color.WHITE)
        shareButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
        shareButton.gravity = Gravity.CENTER
        shareButton.includeFontPadding = false
        shareButton.setPadding(dp(4), dp(4), dp(4), dp(4))
        shareButton.isClickable = true
        shareButton.setOnClickListener { listener?.onShare() }
        applyPressFeedback(shareButton)
        roomPanelHeader.addView(shareButton, llp(dp(28), dp(28), 6))

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
    /**
     * 视频区宽度（597）。
     *
     * - 横屏分栏：`屏宽 - inset`（左区）。
     * - 竖屏分栏：inset 是**面板高度**（280dp），视频区仍是全宽——
     *   旧实现统一用 `w - inset`，竖屏时会白白减掉 280dp，面板被算窄。
     * - 未分栏：全屏宽。
     */
    private fun videoAreaWidth(): Int {
        val w = width.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels
        val h = height.takeIf { it > 0 } ?: resources.displayMetrics.heightPixels
        val portrait = h > w
        return if (!portrait && lastVideoSplitInsetPx > 0) {
            (w - lastVideoSplitInsetPx).coerceAtLeast(1)
        } else {
            w
        }
    }

    /**
     * 弹出面板左偏移（597）：让面板贴**视频区**右缘，而不是根容器右缘。
     *
     * 根 FrameLayout 是全屏宽；分栏后资源面板占右侧，`Gravity.END` 会把
     * 面板推到全屏右缘、正好被资源面板盖住（真机：只看到视频区变黑）。
     */
    private fun panelLeftMarginPx(panelW: Int, fullBleed: Boolean): Int {
        // 【610 真机回归：非房间模式选集面板跑到左边】旧实现
        // `if (fullBleed) return 0` —— 把 leftMargin 设成 0 = 贴**左**边。
        // 而 Flutter 的 `selectorPanelBox(fullBleed: true)` 是
        // `right: 0.0`：贴**右**、只是没有 12dp 间距。
        //
        // 修法：fullBleed 时仍贴右，只是把右侧 12dp 间距去掉。
        val rightPad = if (fullBleed) 0 else dp(NPTheme.PANEL_RIGHT)
        return (videoAreaWidth() - panelW - rightPad).coerceAtLeast(0)
    }

    /** 视频区高度（597）：竖屏分栏时 = 屏高 - 面板高；否则全屏高。 */
    private fun videoAreaHeight(): Int {
        val w = width.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels
        val h = height.takeIf { it > 0 } ?: resources.displayMetrics.heightPixels
        val portrait = h > w
        return if (portrait && lastVideoSplitInsetPx > 0) {
            (h - lastVideoSplitInsetPx).coerceAtLeast(1)
        } else {
            h
        }
    }

    /**
     * 把浮层卡片在**视频区**内水平/垂直居中（597）。
     *
     * 旧实现用 `Gravity.CENTER`，它相对根 FrameLayout（全屏）居中——分栏
     * 后卡片会落到资源面板区域。这里改成 `START|TOP` + 精确 margin，
     * 垂直方向用 `post{}` 读实测高度（卡片是 WRAP_CONTENT）。
     */
    private fun positionVideoCenteredCard(v: View) {
        val videoW = videoAreaWidth()
        val videoH = videoAreaHeight()
        (v.layoutParams as? LayoutParams)?.let {
            it.gravity = Gravity.START or Gravity.TOP
            it.leftMargin = ((videoW - it.width) / 2).coerceAtLeast(0)
            v.layoutParams = it
        }
        v.post {
            val h = v.height
            if (h > 0) {
                (v.layoutParams as? LayoutParams)?.let {
                    val target = ((videoH - h) / 2).coerceAtLeast(0)
                    if (it.topMargin != target) {
                        it.topMargin = target
                        v.layoutParams = it
                    }
                }
            }
        }
    }

    /**
     * 622：加载指示器在**视频区**内居中。
     *
     * 竖屏分栏时视频区高 = 屏高 - 资源面板高，而根 FrameLayout 是全屏高
     * ——`Gravity.CENTER` 会落到资源面板区域（真机截图回归）。
     */
    private fun positionBufferingInVideoArea() {
        val videoW = videoAreaWidth()
        val videoH = videoAreaHeight()
        val size = dp(36)
        (bufferingView.layoutParams as? LayoutParams)?.let {
            it.gravity = Gravity.START or Gravity.TOP
            it.leftMargin = ((videoW - size) / 2).coerceAtLeast(0)
            it.topMargin = ((videoH - size) / 2).coerceAtLeast(0)
            bufferingView.layoutParams = it
        }
    }

    private fun panelWidthDp(): Int {
        // 595/597：面板按**视频区宽度**算，而不是全屏宽。
        // 旧实现用全屏宽 → 收窄后的父级只有 videoW，面板按全屏 0.42 算会
        // 过宽，右缘被父级裁掉、视觉上像「被资源面板遮挡」（真机回归）。
        val available = videoAreaWidth()
        val target = (available * 0.42f).toInt()
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
                // 【真机回归：弹出面板不显示、只让视频区变黑】597 修正。
                //
                // 旧实现用 `Gravity.END` + `marginEnd`：父级是**根
                // FrameLayout（全屏宽）**，分栏后面板贴在「全屏右缘」——
                // 正好落在资源面板下方被完全盖住；而遮罩（黑 45%）盖住
                // 视频区 → 用户只看到「视频区变黑、面板不见」。
                //
                // 改为 `Gravity.START` + `leftMargin = 视频区宽 - 面板宽 -
                // 12dp`：贴视频区右缘，与 Flutter 的
                // `Positioned(right: 12)` 在视频区内等价。
                val panelW = panelWidthDp()
                // 高度必须限制在**视频区**内（597）：旧实现用 MATCH_PARENT
                // （= 根 FrameLayout 全屏高），竖屏分栏时面板会一直伸到屏幕
                // 底、压在资源面板上。
                val panelTop =
                    if (fullBleed) 0 else dp(NPTheme.PANEL_TOP_OFFSET) + safeTopPx()
                val panelBottom =
                    if (fullBleed) 0 else dp(NPTheme.PANEL_BOTTOM_OFFSET) + safeBottomPx()
                val panelH = (videoAreaHeight() - panelTop - panelBottom).coerceAtLeast(1)
                panelContainer.layoutParams = lp(
                    panelW,
                    panelH,
                    Gravity.START or Gravity.TOP,
                ).also {
                    it.topMargin = panelTop
                    it.leftMargin = panelLeftMarginPx(panelW, fullBleed)
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
                    // 622：房间观众不得切集（鸿蒙侧早已有同款守卫，
                    // 安卓漏了 → 观众点资源行仍会切集）。
                    if (!lastState.canControl) return@setOnClickListener
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
        // 597：贴**视频区**右缘（`Gravity.END` 会贴根容器右缘，分栏后被
        // 资源面板盖住，真机「只看到视频区变黑」）。
        decodePopover.layoutParams =
            lp(dp(NPTheme.DECODE_PANEL_WIDTH), LayoutParams.WRAP_CONTENT).also {
                it.gravity = Gravity.START or Gravity.TOP
                it.topMargin = dp(NPTheme.PANEL_TOP_OFFSET) + safeTopPx()
                it.leftMargin = panelLeftMarginPx(dp(NPTheme.DECODE_PANEL_WIDTH), false)
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
    /**
     * 当前集左侧 3dp accent 边框（596）。
     *
     * 与 Flutter `Border(left: BorderSide(color: accent, width: 3))` 等价：
     * 画在容器内边缘、**不占布局宽度**。
     *
     * 旧实现用独立 `View` 占 `dp(3)` 宽——视觉上「多出一条竖条」并把右侧
     * 内容整体右推（真机截图回归）。
     */
    private fun leftAccentDivider(): Drawable = object : Drawable() {
        private val paint = Paint().apply { color = NPTheme.ACCENT }

        override fun draw(canvas: Canvas) {
            val b = bounds
            if (b.isEmpty) return
            canvas.drawRect(
                b.left.toFloat(),
                b.top.toFloat(),
                (b.left + dp(3)).toFloat(),
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
        segmentCard.layoutParams = lp(
            dp(NPTheme.SEGMENT_CARD_WIDTH),
            LayoutParams.WRAP_CONTENT,
            Gravity.START or Gravity.TOP,
        )
        positionVideoCenteredCard(segmentCard)
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
        // 594：竖屏面板占高度 280dp（Flutter `SizedBox(height: 280)`），
        // 横屏占宽度 320dp。宿主据此决定收窄方向。
        val screenW = width.takeIf { it > 0 }
            ?: resources.displayMetrics.widthPixels
        val screenH = height.takeIf { it > 0 }
            ?: resources.displayMetrics.heightPixels
        val portrait = screenH > screenW
        val panelPx = if (!show) {
            0
        } else if (portrait) {
            dp(NPTheme.ROOM_PANEL_HEIGHT)
        } else {
            dp(NPTheme.ROOM_PANEL_WIDTH)
        }
        // 【615 真机回归：非房间竖屏画面被裁切】非房间模式必须强制恢复
        // 全屏——即便 `lastVideoInsetRightPx` 残留了房间模式的分栏值，
        // 或转屏后未更新，也要立即恢复（幂等短路在「值已相等但 surface
        // 窗口尺寸不对」时会拦住恢复）。
        val forceFullscreen = !show && lastVideoInsetRightPx != 0
        if (panelPx != lastVideoInsetRightPx || forceFullscreen) {
            lastVideoInsetRightPx = panelPx
            listener?.onVideoInsetRight(panelPx)
            // 593/594：控件层同步分栏（横屏收窄宽度、竖屏收窄高度）。
            applyVideoSplit(panelPx)
        }
        roomPanel.visibility = if (show) VISIBLE else GONE
        if (!show) return

        // 681：面板从**视频区右缘**开始铺到屏幕右缘（不再固定 dp(320)）。
        // `-1` 让面板盖住视频窗那多出的 1px，彻底消除缝隙漏底光。
        run {
            val availableW = if (portrait) screenW else screenW - panelPx
            val leftMargin = if (portrait) 0 else (availableW - 1).coerceAtLeast(0)
            (roomPanel.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
                lp.leftMargin = leftMargin
                lp.width = FrameLayout.LayoutParams.MATCH_PARENT
                lp.height = if (portrait) {
                    FrameLayout.LayoutParams.MATCH_PARENT
                } else {
                    FrameLayout.LayoutParams.MATCH_PARENT
                }
                roomPanel.layoutParams = lp
            }
        }

        // ── 头部（对齐 Flutter：Expanded(资源) | 搜索 | 人数 | 角色）──
        roomPanelTitle.text = "资源"
        roomPanelOnline.text = "${state.onlineUserCount}"
        // 搜索按钮：房主 **且暂停中** 才显示（596 修正）。
        //
        // 【595 写反了】当时写成 `isHost && !paused`（播放中显示），而
        // Flutter 是 `_roomData != null && _isHost && _player.state !=
        // AdapterPlaybackState.playing`——播放中**不**显示。
        // 原生侧 `paused == (state == paused || state == stopped)`，
        // 因此等价条件就是 `isHost && paused`。
        // 真机截图回归：房主播放中仍能看到右上角放大镜。
        roomPanelSearch.visibility =
            if (state.isHost && state.paused) VISIBLE else GONE
        roomPanelRole.text = if (state.isHost) {
            "房主"
        } else {
            state.audienceName?.takeIf { it.isNotBlank() } ?: "观众"
        }
        roomPanelRole.background = GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(if (state.isHost) NPTheme.ACCENT else 0xFFE53935.toInt())
        }

        // 列表签名：分组/季/集结构 + 折叠态 + 当前集 + 角色。
        //
        // 598：补 `isHost`——播放/暂停图标只有房主看得到，角色切换
        // （房主↔观众）必须重建列表（否则图标不会出现/消失）。
        // `paused` **不进签名**（每次暂停整表重建会让滚动位置归零、封面
        // 重新解码闪烁），改由 `refreshRoomPlayIcons()` 就地刷新图标。
        val sig = buildString {
            append(state.isHost).append('|')
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
        // 598：播放/暂停图标就地刷新（`paused` 不进签名，见 roomPlayIcons
        // 注释）。列表重建时刚登记完也要跑一次，保证首帧图标正确。
        refreshRoomPlayIcons(state)

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
    /**
     * 就地刷新资源行播放/暂停图标（598）。
     *
     * 与 Flutter `ValueListenableBuilder` 逐行监听等价：**不重建列表**，
     * 只按最新 `paused` 改图标文字与颜色。
     *
     * 【为什么不在列表签名里加 `paused`】那会让每次暂停/恢复都整表重建：
     * 滚动位置回到顶部、封面重新走 `NativeLogoLoader` 解码（闪烁）。
     *
     * 颜色语义与 Flutter 一致：当前集用强调色（`isPlaying ? accent :
     * white54`），**与是否正在播无关**——Flutter 里颜色只看 `isPlaying`。
     */
    private fun refreshRoomPlayIcons(state: AndroidNativePlayerState) {
        for ((icon, isCurrent) in roomPlayIcons) {
            val text = if (isCurrent && !state.paused) {
                NativePlayerIcons.ICON_PAUSE_CIRCLE
            } else {
                NativePlayerIcons.ICON_PLAY_CIRCLE
            }
            val glyph = String(Character.toChars(text))
            if (icon.text != glyph) icon.text = glyph
            val color = if (isCurrent) NPTheme.ACCENT else NPTheme.WHITE_54
            if (icon.currentTextColor != color) icon.setTextColor(color)
        }
    }

    private fun buildRoomPanelList(state: AndroidNativePlayerState) {
        roomPanelList.removeAllViews()
        // 598：重建时重置图标登记表（旧视图已随 removeAllViews 丢弃）。
        roomPlayIcons.clear()
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
        setPadding(dp(10), dp(8), dp(10), dp(8))
        // 680：玻璃卡片（对齐 Win 分组标题：12 圆角 + 白描边 + 半透明）
        background = GradientDrawable().apply {
            cornerRadius = dp(12).toFloat()
            setColor(0x14FFFFFF)
            setStroke(dp(1), 0x1FFFFFFF)
        }
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
        // Flutter `EdgeInsets.only(left: 8, right: 4, top: 2)`（679 玻璃化后）。
        setPadding(dp(10), dp(6), dp(8), dp(6))
        // 680：玻璃条（季标题：10 圆角）
        background = GradientDrawable().apply {
            cornerRadius = dp(10).toFloat()
            setColor(0x0FFFFFFF)
            setStroke(dp(1), 0x1AFFFFFF)
        }
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
            // 680：玻璃卡片行（对齐 Win：10 圆角 + 描边；选中态主色 2dp 描边）。
            background = GradientDrawable().apply {
                cornerRadius = dp(10).toFloat()
                setColor(if (ep.isPlaying) 0x386366F1 else 0x0FFFFFFF)
                setStroke(dp(if (ep.isPlaying) 2 else 1),
                    if (ep.isPlaying) NPTheme.ACCENT else 0x1AFFFFFF)
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

            // 当前集左侧 3dp accent 边框（596 修正）。
            //
            // 【真机回归：当前集前面多了一条竖条】旧实现用独立 `View` 占
            // `dp(3)` 布局宽——视觉上「多出一条竖条」且把右侧内容整体右推。
            // Flutter 用的是 `Border(left: BorderSide(accent, 3))`——画在
            // 容器内边缘、**不占布局宽度**。
            //
            // 这里改用 `foreground` 自绘 Drawable：只在左边 3dp 涂 accent，
            // 不参与测量，与 Flutter 完全等价。
            if (ep.isPlaying) {
                foreground = leftAccentDivider()
            }

            // 播放/暂停（房主）
            if (lastState.isHost) {
                val playIcon = iconView(
                    if (ep.isPlaying && !lastState.paused) {
                        NativePlayerIcons.ICON_PAUSE_CIRCLE
                    } else {
                        NativePlayerIcons.ICON_PLAY_CIRCLE
                    },
                    22f,
                    if (ep.isPlaying) NPTheme.ACCENT else NPTheme.WHITE_54,
                )
                // 598：登记进刷新表，暂停/恢复时就地改文字（不重建列表）。
                roomPlayIcons.add(playIcon to ep.isPlaying)
                addView(playIcon, llp(dp(22), dp(22)))
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

    /**
     * 控件层分栏（593）：房间资源面板展开时，把视频区控件收窄到左区。
     *
     * 【真机回归：面板盖在视频上】surface 窗已经收窄（见
     * `AndroidNativePlayerHost.applyVideoInsetRight`），但控件层仍是全屏
     * `MATCH_PARENT`：顶栏/底栏/手势层横跨整屏、资源面板贴最右——
     * 视觉上就是「面板盖在视频右侧」。
     *
     * 现在控件层也按分栏布局：左区（`屏宽 - inset`）承载视频控件，
     * 右区（inset）只放资源面板。与 Flutter
     * `Row(Expanded(video), SizedBox(320))` 完全等价。
     */
    /**
     * 控件层分栏（593/594）：房间资源面板展开时把控件区让出给面板。
     *
     * **横屏**（与 Flutter `Row(Expanded(video), SizedBox(320))` 等价）：
     * 左区承载视频控件，右区 320dp 放资源面板。
     *
     * **竖屏**（与 Flutter `Column(Expanded(video), SizedBox(280))` 等价，
     * 594 补齐）：上区承载视频控件，下区 280dp 放资源面板。旧实现只有横向
     * 分支——竖屏时 `screenW - 320dp` 会得到极窄的 videoW（甚至 1px），
     * 整个控件区被压扁（真机回归「手动竖屏没有上下结构」）。
     */
    private fun applyVideoSplit(insetPx: Int) {
        // 【615】恢复全屏（inset<=0）必须执行——旧实现同值直接返回，若
        // `lastVideoSplitInsetPx` 已是 0 但控件层仍留着上次收窄的参数
        //（转屏时可能出现这种错位），就永远不会恢复全屏。
        if (insetPx > 0 && insetPx == lastVideoSplitInsetPx) return
        lastVideoSplitInsetPx = insetPx
        val screenW = width.takeIf { it > 0 }
            ?: resources.displayMetrics.widthPixels
        val screenH = height.takeIf { it > 0 }
            ?: resources.displayMetrics.heightPixels
        val portrait = screenH > screenW

        // 竖屏：面板高度固定 280dp（Flutter `SizedBox(height: 280)`），
        // 视频区吃掉剩余高度。横屏：面板宽 320dp，视频区吃掉剩余宽度。
        val panelSizePx = insetPx.coerceAtLeast(0)
        val videoW: Int
        val videoH: Int
        if (portrait) {
            videoW = screenW
            videoH = (screenH - panelSizePx).coerceAtLeast(1)
        } else {
            videoW = (screenW - panelSizePx).coerceAtLeast(1)
            videoH = screenH
        }

        // 左/上区：视频手势层 / 弹幕 / 顶栏 / 底栏 / 面板遮罩。
        (tapLayer.layoutParams as? LayoutParams)?.let {
            it.width = videoW; it.height = videoH; tapLayer.layoutParams = it
        }
        (danmakuLayer.layoutParams as? LayoutParams)?.let {
            it.width = videoW; it.height = videoH; danmakuLayer.layoutParams = it
        }
        (topBar.layoutParams as? LayoutParams)?.let { it.width = videoW; topBar.layoutParams = it }
        (bottomBar.layoutParams as? LayoutParams)?.let {
            // 【真机回归：进度条/底栏跑到屏幕顶部】596 修正。
            //
            // 595 把 `height` 设成 `MATCH_PARENT`（横屏）——底栏内部是
            // `LinearLayout.VERTICAL`，撑满高度后内容从**顶部**开始排，
            // 于是进度条行与控件行跑到屏幕最上方，和顶栏叠在一起。
            //
            // 底栏**根本不需要改 height**：`WRAP_CONTENT` 让它按内容量高度。
            it.width = videoW
            it.height = LayoutParams.WRAP_CONTENT
            // 竖屏**分栏时**（面板展开，inset > 0）才需要 TOP + topMargin；
            // 未分栏时 videoH == 屏高，`Gravity.BOTTOM` 本就贴底，不要多此
            // 一举（估值偏差反而让底栏浮起来）。
            val portraitSplit = portrait && panelSizePx > 0
            if (portraitSplit) {
                // 【真机回归：竖屏进度条和底栏没有】597 修正。
                //
                // 竖屏分栏后资源面板占底部 280dp，而底栏的 LayoutParams 挂在
                // **根 FrameLayout（全屏高）**：`Gravity.BOTTOM` 贴的是全屏
                // 底缘 → 底栏整个落在资源面板下方、被完全盖住（用户看到
                // 「竖屏没有进度条和底栏」）。
                //
                // 改为 `Gravity.TOP + topMargin = 视频区高 - 底栏高`，贴视频区
                // 底缘。底栏真实高度未知（随模式/字号变化），先按估值放，
                // 再在 `post{}` 里用实测 `bottomBar.height` 修正（零误差）。
                it.gravity = Gravity.START or Gravity.TOP
                it.topMargin = (videoH - dp(BOTTOM_BAR_ESTIMATED_HEIGHT)).coerceAtLeast(0)
            } else {
                // 横屏 / 竖屏未分栏：全屏高，`Gravity.BOTTOM` 天然贴底。
                it.topMargin = 0
                it.gravity = Gravity.START or Gravity.BOTTOM
            }
            bottomBar.layoutParams = it
        }
        if (portrait && panelSizePx > 0) {
            // 实测修正：布局完成后底栏才有真实高度，用它重算 topMargin。
            // 不用 `doOnLayout`（可能已被消费），直接 post 一次即可。
            bottomBar.post {
                val barH = bottomBar.height
                if (barH > 0) {
                    (bottomBar.layoutParams as? LayoutParams)?.let {
                        val target = (videoH - barH).coerceAtLeast(0)
                        if (it.topMargin != target) {
                            it.topMargin = target
                            bottomBar.layoutParams = it
                        }
                    }
                }
            }
        }
        // 615：空态占位层也要收窄到视频区（否则分栏时它会盖住资源面板，
        // 且转屏后尺寸不跟随）。
        (placeholderView.layoutParams as? LayoutParams)?.let {
            it.width = videoW; it.height = videoH; placeholderView.layoutParams = it
        }
        (panelScrim.layoutParams as? LayoutParams)?.let {
            it.width = videoW; it.height = videoH; panelScrim.layoutParams = it
        }
        // 597：分栏后同步面板的 leftMargin（贴视频区右缘，见
        // renderOverlays 注释）。面板宽度由 panelWidthDp() 决定，这里只改
        // 左偏移，不动 width（避免与 renderOverlays 冲突）。
        (panelContainer.layoutParams as? LayoutParams)?.let {
            val panelW = panelWidthDp()
            it.width = panelW
            // 高度必须扣掉 renderOverlays 设的上下避让（否则面板会溢出
            // 视频区底缘，压到底栏/资源面板上）。fullBleed（选集面板）的
            // top/bottomMargin 是 0，扣减自然为 0。
            it.height = (videoH - it.topMargin - it.bottomMargin).coerceAtLeast(1)
            it.gravity = Gravity.START or Gravity.TOP
            it.leftMargin = (videoW - panelW - dp(NPTheme.PANEL_RIGHT)).coerceAtLeast(0)
            panelContainer.layoutParams = it
        }
        // 解码 popover 与面板同区：分栏后也要贴视频区右缘，否则同样被
        // 资源面板盖住（597）。宽度保持 DECODE_PANEL_WIDTH（180dp），
        // 不能用 panelWidthDp()（那是主面板宽 260~320dp）。
        (decodePopover.layoutParams as? LayoutParams)?.let {
            val popW = dp(NPTheme.DECODE_PANEL_WIDTH)
            it.width = popW
            it.gravity = Gravity.START or Gravity.TOP
            it.leftMargin = (videoW - popW - dp(NPTheme.PANEL_RIGHT)).coerceAtLeast(0)
            decodePopover.layoutParams = it
        }
        // 【真机回归：控件弹出面板没显示】596 修正。
        //
        // 595 在这里把 panelContainer.width 改成了 videoW（整个视频区宽），
        // 而 `renderOverlays()` 用 `lp(panelWidthDp(), MATCH_PARENT)` 重建时
        // 又会重置宽度——两者顺序冲突：若 applyVideoSplit 在 renderOverlays
        // 之后跑，面板被撑满视频区，看起来像「没显示」。
        //
        // 面板宽度必须由 `panelWidthDp()` 统一决定（它已按 videoW 计算），
        // 这里只限制遮罩范围，不动面板宽度。
        (segmentScrim.layoutParams as? LayoutParams)?.let {
            it.width = videoW; it.height = videoH; segmentScrim.layoutParams = it
        }
        // 片头片尾卡：固定在**视频区内**居中（597）。
        // 旧实现 `Gravity.CENTER` 相对根 FrameLayout（全屏）居中，竖屏分栏
        // 后卡片落到资源面板区域；且 width 被撑成 videoW，与 Flutter
        // `Center + SizedBox(width: 360)` 不一致。
        (segmentCard.layoutParams as? LayoutParams)?.let {
            it.width = dp(NPTheme.SEGMENT_CARD_WIDTH)
            segmentCard.layoutParams = it
        }
        positionVideoCenteredCard(segmentCard)

        // 右/下区：资源面板
        (roomPanel.layoutParams as? LayoutParams)?.let {
            if (portrait) {
                // 竖屏：贴视频区下缘、全宽。
                it.width = videoW
                it.height = panelSizePx
                it.gravity = Gravity.START or Gravity.TOP
                it.leftMargin = 0
                it.topMargin = videoH
            } else {
                // 横屏：贴左区右缘、全高。
                it.width = panelSizePx
                it.height = LayoutParams.MATCH_PARENT
                it.gravity = Gravity.START or Gravity.TOP
                it.leftMargin = videoW
                it.topMargin = 0
            }
            roomPanel.layoutParams = it
        }
        requestLayout()
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

        // 顶栏网速（642：TV 在最右 / 手机在尾簇首位，二选一）
        val speedVisible = state.networkSpeedText != null
        networkText.text = state.networkSpeedText ?: ""
        networkTextTv.text = state.networkSpeedText ?: ""
        if (state.tvMode) {
            networkText.visibility = GONE
            networkTextTv.visibility = if (speedVisible) VISIBLE else GONE
        } else {
            networkTextTv.visibility = GONE
            networkText.visibility = if (speedVisible) VISIBLE else GONE
        }

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
            // 【618 真机回归：安卓弹幕仍然左右跳】修正。
            //
            // 616 的「自维护锚点 + drift/10 平滑收敛」已被移除——那是鸿蒙
            // 在 600 轮次已证明错误的东西（见 `DanmakuLayer.ets` 的
            //「非匀速根因」注释）。根因：`setClock` 被两条路径调用
            //（Dart 200ms 的 render + 本地 500ms 的 applyState），本地 tick
            // 传同一份**旧快照**，此时帧时间已推进 ~250ms → drift 超阈值
            // → 重锚 → 位置回退 → 左右跳。
            //
            // 现改为**无状态纯函数**（与鸿蒙 `positionNowMs()` /
            // Flutter `_nowPosition` 三者同构）：位置 = 快照 + 墙钟×倍速，
            // 重复调用同一份快照天然幂等。
            //
            // 第二参传「暂停 / 缓冲 / 播完」三态合并（与宿主 `positionAt`
            // 冻结条件一致）；第三参倍速；第四参时长（0 时不外推，防起播
            // 早期位置跑到时长上限）。
            danmakuLayer.setClock(
                state.positionMs.toLong(),
                state.paused || state.buffering || state.ended,
                state.speed,
                state.durationMs.toLong(),
            )
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
        // 622：显示时按当前视频区重算居中位置（转屏/分栏会改变视频区高）。
        if (state.showLoading) positionBufferingInVideoArea()
        // 空态占位（610）：无播放内容时显示（对齐 Flutter `_isPlayerReady`）。
        placeholderView.visibility = if (!state.playerReady) VISIBLE else GONE

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
        // 642：TV 隐藏左上角返回（遥控返回键 → handleBack() 三层语义已
        // 覆盖退出：关面板 → 收控件 → 退出；且左侧位置让给系统时钟）。
        // 手机保留（触摸设备无硬件返回键）。GONE 而非 INVISIBLE：让标题
        // 自然左移填充留白。
        backButton.visibility = if (tv) GONE else VISIBLE
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
        // 622：房间**观众**隐藏分享（只有房主能分享房间）。
        // 用 INVISIBLE 而非 GONE：保持顶栏尾部布局不塌（与 Flutter 观感一致）。
        // 680：分享按钮现在在**房间面板头部**——只在「房间 + 房主」显示
        // （旧实现在顶栏，观众用 INVISIBLE 占位；面板头部不需要占位，
        // 直接用 GONE 让角色徽章贴边）。
        shareButton.visibility =
            if (state.isRoom && state.isHost) VISIBLE else GONE
        // 642：时钟显隐跟随设置（默认 off）。原实现 TV 恒显示，导致
        // 「时钟关闭」时左侧仍占 100dp 空白，标题无法左移填充。
        clockWrap.visibility =
            if (tv && state.clockFormat != "off") VISIBLE else GONE
        // 642：网速随模式换位——TV 在最右（networkTextTv），手机在尾簇首位
        // （networkText）。两者由 applyState 按「是否有值」置 VISIBLE/GONE，
        // 这里只负责把**不属于当前模式**的那个收掉，避免同屏出现两份。
        if (tv) {
            networkText.visibility = GONE
        } else {
            networkTextTv.visibility = GONE
        }

        // 芯片打开态（Flutter：面板打开时强调色描边/文字）
        val panel = activePanel
        kernelChip.background = chipBackground(panel == PANEL_KERNEL)
        kernelChip.setTextColor(if (panel == PANEL_KERNEL) NPTheme.ACCENT else Color.WHITE)
        subtitleStyleChip.background = chipBackground(panel == PANEL_DISPLAY)
        decodeChip.background = chipBackground(panel == PANEL_DECODE)
        speedLabel.setTextColor(if (panel == PANEL_SPEED) NPTheme.ACCENT else NPTheme.WHITE_70)

        // 底栏可见项
        lockButton.visibility = if (!tv) VISIBLE else GONE
        // 622：房间**观众**隐藏播放/暂停、上一集、下一集。
        // 用 INVISIBLE 而非 GONE——保持底栏布局不塌（其余按钮不移位，
        // 与 Flutter 观感一致）。锁定按钮保留（本地 UI 锁定，非播放控制）。
        val hideTransportForAudience = state.isRoom && !state.isHost
        val transportVisibility = if (hideTransportForAudience) INVISIBLE else VISIBLE
        playPauseButton.visibility = transportVisibility
        prevButton.visibility = transportVisibility
        nextButton.visibility = transportVisibility
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
            seekRow.visibility = GONE
            logoImage.visibility = GONE
            logoSpacer.visibility = GONE
            diagText.visibility = GONE
            transportGroup.visibility = GONE
            trailingGroup.visibility = GONE
            skipPromptChip.visibility = GONE
            leadingGroup.visibility = VISIBLE
            // 【真机回归：锁定态切资源后锁控件消失】597 修正。
            //
            // 旧实现只把 `leadingGroup` 设为 VISIBLE，**没设 bottomBar 自身**
            // 的可见性——它由 `setControlsVisible()` 控制。锁定期间用户去
            // 资源面板切集/切资源时，宿主会走 `closePanel()` →
            // `renderOverlays()`，而自动隐藏计时器（5s）也可能已把
            // `controlsVisible` 置 false；之后没有任何路径把底栏显回来，
            // 锁钮就永久消失（只能解锁一次才恢复）。
            //
            // 锁定态本就该常显底栏（里面只剩锁钮），与 Flutter
            // `_buildLockOnlyControls` 一致——这里强制 VISIBLE。
            bottomBar.visibility = VISIBLE
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
        // 锁定态不自动隐藏（597）：底栏里只剩锁钮，藏掉后用户无法解锁，
        // 只能退出播放页。与 Flutter `_buildLockOnlyControls` 常显一致。
        val lockedUi = !lastState.tvMode && lastState.locked
        if (!lockedUi && controlsVisible && !lastState.paused &&
            System.currentTimeMillis() > hideDeadlineMs
        ) {
            setControlsVisible(false)
            return
        }
        if (!dragging) applyState()
    }

    private fun setControlsVisible(visible: Boolean) {
        controlsVisible = visible
        // 锁定态底栏常显（只剩锁钮，对齐 Flutter `_buildLockOnlyControls`）。
        // 597：自动隐藏计时器会在切资源/切集时把底栏藏掉，锁钮随之消失。
        if (!lastState.tvMode && lastState.locked) {
            topBar.visibility = GONE
            bottomBar.visibility = VISIBLE
            return
        }
        topBar.visibility = if (visible) VISIBLE else GONE
        bottomBar.visibility = if (visible) VISIBLE else GONE
        if (visible) scheduleAutoHide()
    }

    private fun scheduleAutoHide() {
        hideDeadlineMs = System.currentTimeMillis() + AUTO_HIDE_MS
        mainHandler.removeCallbacks(hideRunnable)
        // 锁定态不自动隐藏（Flutter 锁定态控件常显，否则锁钮无法再点）。
        if (!lastState.tvMode && lastState.locked) return
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
        if (w == oldw && h == oldh) return
        requestAdaptiveRelayout()
        // 【615 真机回归：安卓横转竖后画面被裁切、只显示左上角一块】
        //
        // 根因（590/593 引入的设计缺陷）：`applyVideoInsetRight` 用
        // `window.setLayout` 收窄 surface 窗口，但**只在 inset 值变化时**
        // 调用（`renderRoomPanel` 的幂等短路）；而这里又只在
        // `lastVideoSplitInsetPx > 0`（房间分栏）时重置。非房间模式 inset
        // 恒为 0 → 转屏后**两条短路同时拦住** → surface 窗口尺寸停留在
        // 上一方向（横屏 1900×880 在竖屏下只显示左边 880×880）→ 画面被
        // 裁切（内容比例不变，故「没拉伸、只是显示部分」）。
        //
        // 修法：转屏后**无条件**重置两个 inset 并重新应用——inset 值本身
        // 不变，但 surface 窗口必须按新屏幕尺寸重新 setLayout。
        val prevInset = lastVideoSplitInsetPx.coerceAtLeast(0)
        lastVideoSplitInsetPx = -1
        lastVideoInsetRightPx = -1
        applyVideoSplit(prevInset)
        listener?.onVideoInsetRight(prevInset)
    }

    companion object {
        const val SEEK_STEPS = 1000
        /**
         * 竖屏底栏高度估值（597）：仅作为首帧占位，`applyVideoSplit` 会在
         * `post{}` 里用实测 `bottomBar.height` 修正，最终位置零误差。
         * 取值 = 进度条行 + 控件行 + 上下 padding 的经验值。
         */
        const val BOTTOM_BAR_ESTIMATED_HEIGHT = 100
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
