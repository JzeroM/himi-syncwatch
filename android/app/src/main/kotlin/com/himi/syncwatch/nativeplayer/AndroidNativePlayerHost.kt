package com.himi.syncwatch.nativeplayer

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.os.Build
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowInsets
import android.view.WindowManager

/**
 * 全屏原生播放器宿主（计划书 §6.2 / §11 风险1 兜底升级）：持有 surface 窗
 * 与控件窗两层窗口，并把用户交互转成命令回传 Dart。
 *
 * 【为什么要两个窗口】
 * SurfaceView 默认走 punch-hole：surface 在窗口表面之后，窗口在 SurfaceView
 * 区域不透明就把它盖死。v1.5.4 真机（SM8550）上 mpv fps=60、vo 配置成功、
 * 硬解在跑却全黑——帧渲染了但没到屏幕，透明背景 + setFormat(TRANSLUCENT)
 * 都救不回，即 punch-hole 在该设备失效。改为：
 * - surface 窗：只放 [HimiMpvSurfaceView]（setZOrderOnTop(true)），surface
 *   提到本窗口表面之上，不打洞、不依赖窗口透明；
 * - 控件窗：透明背景，画触控层/顶栏/底栏，后创建保证 z-order 高于 surface 窗。
 *
 * 只做「宿主」职责：
 * - open/close 幂等（重复调用不会叠加窗口）；
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

    private var surfaceDialog: Dialog? = null
    private var controlsDialog: Dialog? = null
    private var surfaceView: com.himi.mpv.android.HimiMpvSurfaceView? = null
    private var view: NativePlayerScreenView? = null

    /** 最近一次 Dart 推送的快照（新视图首次渲染直接复用）。 */
    private var lastState: AndroidNativePlayerState = AndroidNativePlayerState()
    private var lastStateAtMs: Long = 0L

    /** 长按临时倍速的基准档位（松手还原用；见 [Listener.onSpeedBoost]）。 */
    private var boostBaseSpeed = 1.0

    /**
     * 最近一次视频区右侧留白（像素，603）。
     *
     * `resume()` 里 `show()` 会把窗口尺寸重置回全屏，需要按这个值重新
     * 收窄——否则恢复后视频区又变回全屏、盖住资源面板。
     */
    private var lastVideoInsetPx = 0

    val isOpen: Boolean get() = controlsDialog != null

    /** 打开 surface 窗 + 控件窗（幂等）。 */
    fun open() {
        if (controlsDialog != null) return

        // ── 窗 A：surface 窗（只放 surface，置顶，不打洞）──────────
        val surf = com.himi.mpv.android.HimiMpvSurfaceView(
            activity,
            SURFACE_VIEW_ID,
            // 独立窗口内不需要 media overlay（它只解决 Flutter 内嵌的遮挡）。
            false,
            // 来源标识：原生播放器 UI 的 surface，Dart 只在 nativeUiActive
            // 时接受 src=native 的事件（防平台视图的过期事件抢回绑定）。
            "native",
            // 关键：surface 提到本窗口表面之上，绕开 punch-hole。
            true,
        )
        val surfDlg = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen)
        surfDlg.requestWindowFeature(Window.FEATURE_NO_TITLE)
        surfDlg.setContentView(
            surf,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        surfDlg.setCanceledOnTouchOutside(false)
        surfDlg.setCancelable(false) // BACK 由控件窗接管，surface 窗不响应
        applyFullscreen(surfDlg)
        surfaceDialog = surfDlg
        surfaceView = surf
        surfDlg.show()

        // ── 窗 B：控件窗（后创建 → z-order 高于 surface 窗）─────────
        // 兜底：控件窗构造/render 抛异常时必须关掉 surface 窗。否则 surface
        // 窗（不透明纯黑底）已 show 却无人关闭，会盖住一切 →「有声无画」。
        // 异常继续上抛，让 Dart 侧走「原生 UI 打开失败」回退 Flutter 播放页。
        try {
            buildControlsWindow(surfaceSizeProvider = { surfaceSize() })
        } catch (t: Throwable) {
            android.util.Log.e("NativePlayerHost", "控件窗构建失败，回退", t)
            try {
                surfDlg.dismiss()
            } catch (_: Throwable) {
            }
            surfaceDialog = null
            surfaceView = null
            throw t
        }
    }

    private fun buildControlsWindow(surfaceSizeProvider: () -> Pair<Int, Int>) {
        val controls = NativePlayerScreenView(
            activity,
            surfaceSizeProvider,
            surfaceViewProvider = { surfaceView },
        )
        controls.setListener(object : NativePlayerScreenView.Listener {
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

            // ── Phase 2 面板命令（与鸿蒙 optimistic* 同构）──
            override fun onSetSpeed(speed: Double) {
                lastState = lastState.copy(speed = speed)
                commandSink.send(mapOf("type" to "setSpeed", "speed" to speed))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onSelectAudio(trackId: Int) {
                lastState = lastState.copy(
                    selectedAudioId = trackId,
                    tracks = lastState.tracks.map {
                        if (it.type == "audio") it.copy(selected = it.id == trackId) else it
                    },
                )
                commandSink.send(mapOf("type" to "selectAudio", "id" to trackId))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onSelectSubtitle(trackId: Int) {
                lastState = lastState.copy(
                    selectedSubtitleId = trackId,
                    tracks = lastState.tracks.map {
                        if (it.type == "sub") it.copy(selected = it.id == trackId) else it
                    },
                )
                commandSink.send(mapOf("type" to "selectSubtitle", "id" to trackId))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onAddSubtitle() {
                // 「加载本地字幕文件...」：交给 Dart `_loadLocalSubtitle`
                //（文件选择器只能由 Flutter 侧调起）。
                commandSink.send(mapOf("type" to "addSubtitle"))
            }

            override fun onSelectEpisode(index: Int) {
                lastState = lastState.copy(currentEpisodeIndex = index)
                commandSink.send(mapOf("type" to "selectEpisode", "index" to index))
            }

            override fun onSelectVersion(index: Int) {
                lastState = lastState.copy(currentVersionIndex = index)
                commandSink.send(mapOf("type" to "selectVersion", "index" to index))
            }

            // ── Phase 2.5 控制层命令 ──
            override fun onSwitchEngine(engine: String) {
                commandSink.send(mapOf("type" to "switchEngine", "engine" to engine))
            }

            override fun onSetDecodeMode(mode: String) {
                lastState = lastState.copy(decodeMode = mode)
                commandSink.send(mapOf("type" to "setDecodeMode", "mode" to mode))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onToggleDanmaku() {
                lastState = lastState.copy(danmakuEnabled = !lastState.danmakuEnabled)
                commandSink.send(mapOf("type" to "toggleDanmaku"))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onCycleVideoFit() {
                val next = when (lastState.videoFit) {
                    "contain" -> "cover"
                    "cover" -> "fill"
                    "fill" -> "none"
                    else -> "contain"
                }
                lastState = lastState.copy(videoFit = next)
                commandSink.send(mapOf("type" to "cycleVideoFit"))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onToggleOrientation() {
                commandSink.send(mapOf("type" to "toggleOrientation"))
            }

            override fun onToggleLock() {
                lastState = lastState.copy(locked = !lastState.locked)
                commandSink.send(mapOf("type" to "toggleLock"))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onShare() {
                commandSink.send(mapOf("type" to "shareRoom"))
            }

            override fun onAdjustDisplay(key: String, value: Double) {
                lastState = AndroidNativePlayerState.applyAdjustDisplay(lastState, key, value)
                commandSink.send(mapOf("type" to "adjustDisplay", "key" to key, "value" to value))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onResetDisplay(scope: String) {
                // 乐观重置（默认值与 Dart 侧 reset 语义一致）+ 回传命令。
                lastState = when (scope) {
                    "subtitle" -> lastState.copy(
                        subtitleScale = 1.0,
                        subtitleMarginY = 22,
                        subtitleDelayMs = 0.0,
                    )
                    else -> lastState.copy(
                        danmakuSpeed = 0.7,
                        danmakuFontSize = 0.5,
                        danmakuOpacity = 0.8,
                    )
                }
                commandSink.send(mapOf("type" to "resetDisplay", "scope" to scope))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onSetSegmentMark(kind: String, positionMs: Long) {
                lastState = if (kind == "intro") {
                    lastState.copy(segmentIntroEndMs = positionMs.toInt())
                } else {
                    lastState.copy(segmentOutroStartMs = positionMs.toInt())
                }
                commandSink.send(
                    mapOf("type" to "setSegmentMark", "kind" to kind, "positionMs" to positionMs),
                )
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onClearSegmentMark(kind: String) {
                lastState = if (kind == "intro") {
                    lastState.copy(segmentIntroEndMs = null)
                } else {
                    lastState.copy(segmentOutroStartMs = null)
                }
                commandSink.send(mapOf("type" to "clearSegmentMark", "kind" to kind))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onSkipSegment() {
                // 跳过片头/片尾：跳转语义由 Dart `_performSkipSegment` 执行。
                commandSink.send(mapOf("type" to "skipSegment"))
            }

            override fun onOpenPanel(panel: String) {
                // 面板显隐由视图自理；此处仅记录，返回键经视图 closePanel。
            }

            override fun onClosePanel() {
                // 同上。
            }

            override fun onToggleResourcePanel() {
                // 房间模式资源面板开关（对齐 Flutter `_showPanel`）。
                // **不能发 requestBack**（旧实现点一下直接退出播放页）。
                commandSink.send(mapOf("type" to "toggleResourcePanel"))
            }

            // ── 房间资源面板交互（590）──
            override fun onToggleResourceGroup(index: Int) {
                commandSink.send(
                    mapOf("type" to "toggleResourceGroup", "index" to index),
                )
            }

            override fun onToggleResourceSeason(groupIndex: Int, seasonIndex: Int) {
                commandSink.send(
                    mapOf(
                        "type" to "toggleResourceSeason",
                        "groupIndex" to groupIndex,
                        "seasonIndex" to seasonIndex,
                    ),
                )
            }

            override fun onRemoveResourceEpisode(index: Int) {
                commandSink.send(
                    mapOf("type" to "removeResourceEpisode", "index" to index),
                )
            }

            override fun onOpenResourceSearch() {
                commandSink.send(mapOf("type" to "openResourceSearch"))
            }

            /**
             * 视频区右侧留白（590）：房间资源面板展开时收窄 surface 窗。
             *
             * 旧实现视频始终全屏，面板只能盖在视频上（视频被遮一部分）。
             * 现在 surface 窗按 inset 收窄，视频只占左侧，与 Flutter
             * `Row(Expanded(video), SizedBox(320))` 等价。
             */
            override fun onVideoInsetRight(insetPx: Int) {
                applyVideoInsetRight(insetPx)
            }

            // ── 手机手势（对齐 Flutter player_screen.dart 手势控制）──

            override fun onSeekRelative(deltaMs: Long) {
                commandSink.send(mapOf("type" to "seekRelative", "deltaMs" to deltaMs))
            }

            override fun onGestureBrightness(delta01: Double) {
                // 亮度写入**控件窗**的 screenBrightness（Flutter 走
                // `WindowManager.LayoutParams.screenBrightness`）。相对增量
                // 累加到当前值，范围 0..1。
                val win = controlsDialog?.window ?: return
                val attrs = win.attributes
                val current = if (attrs.screenBrightness >= 0f) attrs.screenBrightness else 1f
                attrs.screenBrightness =
                    (current + delta01.toFloat()).coerceIn(0f, 1f)
                win.attributes = attrs
            }

            override fun onGestureVolumeDelta(delta01: Double) {
                // 音量走播放器属性（与 Flutter `_player.volume = x` 一致，
                // 0..1）。本地乐观更新 + 回传 Dart。
                val next = (lastState.volume + delta01).coerceIn(0.0, 1.0)
                lastState = lastState.copy(volume = next)
                commandSink.send(mapOf("type" to "setVolume", "volume" to next))
                view?.render(lastState, System.currentTimeMillis())
            }

            override fun onSpeedBoost(active: Boolean) {
                // 长按临时倍速：激活升到 2×，松手还原到长按前档位。
                val base = if (active) {
                    boostBaseSpeed = lastState.speed
                    boostBaseSpeed
                } else {
                    boostBaseSpeed
                }
                val target = if (active) {
                    base * NativePlayerScreenView.PlayerScreenSpeedBoostMultiplier
                } else {
                    base
                }
                lastState = lastState.copy(speed = target)
                commandSink.send(mapOf("type" to "setSpeed", "speed" to target))
                view?.render(lastState, System.currentTimeMillis())
            }
        })
        controls.render(lastState, lastStateAtMs)
        val ctrlDlg = Dialog(activity, android.R.style.Theme_Translucent_NoTitleBar_Fullscreen)
        ctrlDlg.requestWindowFeature(Window.FEATURE_NO_TITLE)
        ctrlDlg.setContentView(controls)
        ctrlDlg.setCanceledOnTouchOutside(false)
        ctrlDlg.setCancelable(true)
        ctrlDlg.setOnDismissListener { close() }
        ctrlDlg.setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_BACK && event.action == KeyEvent.ACTION_UP) {
                // 三层返回语义（关面板 → 隐控件 → 退出），对齐 Flutter；
                // 旧实现直接 requestBack（按返回就退出播放页）。
                controls.handleBack()
                true
            } else {
                false
            }
        }
        applyFullscreen(ctrlDlg)
        // 控件窗背景透明（顶/底栏自带半透明黑，中间区域透出 surface 窗）。
        ctrlDlg.window?.setBackgroundDrawable(
            android.graphics.drawable.ColorDrawable(Color.TRANSPARENT),
        )
        controlsDialog = ctrlDlg
        view = controls
        ctrlDlg.show()
        // 安全区喂给控件层（顶/底栏避让刘海与手势条）。必须在 show() 之后：
        // decorView 在 show 前拿不到 insets。
        wireSafeInsets(ctrlDlg, controls)
    }

    /** surface 实测尺寸（诊断行用；未就绪返回 0x0）。 */
    private fun surfaceSize(): Pair<Int, Int> {
        val surf = surfaceView ?: return 0 to 0
        return surf.width to surf.height
    }

    /**
     * 视频区右侧留白（593）：房间资源面板展开时收窄 surface 窗。
     *
     * 【真机回归：面板盖在视频上、视频仍全屏】旧实现只改
     * `window.attributes.width`：
     * - `applyFullscreen()` 里已经 `setLayout(MATCH_PARENT, MATCH_PARENT)`，
     *   之后改 `attributes.width` 与它冲突，实际生效的仍是全屏；
     * - 还有 `if (lp.width == targetW) return` 短路——首次调用时
     *   `lp.width` 可能已是 `MATCH_PARENT(-1)`，与 targetW 不等所以不拦，
     *   但 `show()` 时 `setContentView` 又会把宽度重置回全屏。
     *
     * 正确做法：**每次都调 `window.setLayout(w, MATCH_PARENT)`**（它会写
     * attributes 并立即 apply），且必须发生在 `applyFullscreen` 之后。
     */
    private fun applyVideoInsetRight(insetPx: Int) {
        lastVideoInsetPx = insetPx.coerceAtLeast(0)
        val dlg = surfaceDialog ?: return
        val win = dlg.window ?: return
        val metrics = activity.resources.displayMetrics
        val screenW = metrics.widthPixels
        val screenH = metrics.heightPixels
        val inset = insetPx.coerceAtLeast(0)
        // 594：竖屏时面板占**高度**（上下结构），横屏占**宽度**（左右分栏）。
        val portrait = screenH > screenW
        val targetW: Int
        val targetH: Int
        val gravity: Int
        if (portrait) {
            targetW = screenW
            // 681：高度 +1px 让面板边缘覆盖，消除「视频与面板之间漏底光」
            // （inset 由 Flutter 侧按 dp 算、面板按 dp(320) 定位，两条
            // 独立取整路径必然差 1~2px，多盖 1px 即无缝）。
            targetH = (screenH - inset + 1).coerceAtLeast(1)
            // 视频贴左上，面板在其下。
            gravity = android.view.Gravity.START or android.view.Gravity.TOP
        } else {
            targetW = (screenW - inset + 1).coerceAtLeast(1)
            targetH = screenH
            gravity = android.view.Gravity.START or android.view.Gravity.TOP
        }
        // 用 setLayout 而非改 attributes.width：后者会被之前 setLayout 的
        // MATCH_PARENT 覆盖。不设短路——show() 后可能被重置，必须每次重申。
        win.setLayout(targetW, targetH)
        win.attributes = win.attributes.apply { this.gravity = gravity }
    }

    /** 全屏 + 刘海 + 沉浸式（两个窗口共用）。 */
    private fun applyFullscreen(dlg: Dialog) {
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
        }
    }

    /**
     * 把安全区（刘海 / 手势条）喂给控件层。
     *
     * 窗口开了 `LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES`，内容会延伸进
     * 刘海区——不避让时横屏顶栏被挖孔压住、底栏被手势条盖住（Flutter 靠
     * `MediaQuery.padding` 避让，原生必须自己读 insets）。
     */
    private fun wireSafeInsets(dlg: Dialog, target: NativePlayerScreenView) {
        val decor = dlg.window?.decorView ?: return
        val listener = View.OnApplyWindowInsetsListener { _, insets ->
            val top: Int
            val bottom: Int
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // 【只取 DisplayCutout】窗口是全屏沉浸式（FLAG_FULLSCREEN +
                // HIDE_NAVIGATION），状态栏本不可见；若再叠加 statusBars 的
                // inset 会把顶栏无故下移 ~24-48dp（真机截图回归）。
                val cutout = insets.displayCutout
                top = cutout?.safeInsetTop ?: 0
                // 底部：手势条导航栏高度（全屏时 navigationBars 的 inset
                // 不会被隐藏，仍会返回）。
                bottom = insets.getInsetsIgnoringVisibility(
                    WindowInsets.Type.navigationBars(),
                ).bottom
            } else {
                // 旧 API：全屏沉浸式下 status bar 不可见，top 直接取 0
                //（只避让 DisplayCutout 需要 API 30+，旧 API 无法单独取）。
                // 底部：导航条高度。
                top = 0
                @Suppress("DEPRECATION")
                bottom = insets.systemWindowInsetBottom
            }
            target.applySafeInsets(top, bottom)
            insets
        }
        decor.setOnApplyWindowInsetsListener(listener)
        // 立即取一次当前值（listener 只在 insets 变化时触发）。
        decor.requestApplyInsets()
    }

    /**
     * 临时隐藏双窗（**不销毁**，session / surface 绑定全部保留）。
     *
     * 【603 真机回归：点「取消」后播任何视频都白屏】原生窗口是独立
     * Dialog，z-order 在 Flutter 页面**之上**——不隐藏会盖住 Flutter 的
     * 「解散房间」确认框 / 资源搜索页。
     *
     * 与 [close] 的区别：本方法只 `hide()`，Dialog 与 SurfaceView 都不
     * 销毁 → [resume] 恢复时画面立刻回来，**零白屏**。
     * 旧实现用 `close()` + 重开（`reopenNativeUi()`），要重建窗口并重新
     * 绑定 surface，有「两个 SurfaceView 抢绑定」的风险（v1.5.4 黑屏根因）。
     */
    /**
     * 隐藏双窗（弹窗/搜索页期间让位）。
     *
     * 【681 真机回归：分享弹窗关闭后视频从头播放】旧实现用
     * `Dialog.hide()` —— Android 在窗口不可见时会**回收 SurfaceView 的
     * surface**，`show()` 时重建 → mpv 检测到 surface 变化 → 重配 vo →
     * 从头播放。
     *
     * 现在改为 **alpha=0 + FLAG_NOT_TOUCHABLE**：窗口仍"显示"（surface
     * 全程存活，mpv 不重配），但完全透明且不接收触摸。与鸿蒙
     * （`visibility` 控制，XComponent 不销毁）、Windows（Qt 独立进程）
     * 的语义对齐。
     */
    fun suspend() {
        val surf = surfaceDialog
        if (surf != null) {
            try {
                val w = surf.window
                if (w != null) {
                    w.attributes = w.attributes.apply {
                        alpha = 0f
                        addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
                    }
                }
            } catch (_: Throwable) {
            }
        }
        val ctrl = controlsDialog
        if (ctrl != null) {
            try {
                val w = ctrl.window
                if (w != null) {
                    w.attributes = w.attributes.apply {
                        alpha = 0f
                        addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
                    }
                }
            } catch (_: Throwable) {
            }
        }
    }

    /** 恢复被 [suspend] 隐藏的双窗（幂等；未 suspend 时无副作用）。 */
    fun resume() {
        val surf = surfaceDialog
        if (surf != null) {
            try {
                val w = surf.window
                if (w != null) {
                    w.attributes = w.attributes.apply {
                        alpha = 1f
                        clearFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
                    }
                }
                // show()/属性变更可能重置布局，重申分栏（681）
                if (lastVideoInsetPx > 0) applyVideoInsetRight(lastVideoInsetPx)
            } catch (_: Throwable) {
            }
        }
        // 控件窗后恢复 → z-order 保持在 surface 窗之上。
        val ctrl = controlsDialog
        if (ctrl != null) {
            try {
                val w = ctrl.window
                if (w != null) {
                    w.attributes = w.attributes.apply {
                        alpha = 1f
                        clearFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
                    }
                }
                // 属性变更可能丢掉全屏/沉浸标志，重申一次
                applyFullscreen(ctrl)
            } catch (_: Throwable) {
            }
        }
    }
            // 重新应用全屏布局与视频区收窄（show() 可能把尺寸重置回全屏）。
            try {
                applyFullscreen(ctrl)
                if (lastVideoInsetPx > 0) applyVideoInsetRight(lastVideoInsetPx)
            } catch (_: Throwable) {
            }
        }
    }

    /** 关闭双窗并释放 surface（幂等）。 */
    fun close() {
        // 先关控件窗（z-order 高），再关 surface 窗；顺序反了会看到控件
        // 短暂悬空在黑底上。
        val ctrl = controlsDialog
        controlsDialog = null
        if (ctrl != null) {
            try {
                ctrl.setOnDismissListener(null)
                ctrl.setOnKeyListener(null)
                ctrl.dismiss()
            } catch (_: Throwable) {
            }
        }
        val surf = surfaceDialog
        surfaceDialog = null
        if (surf != null) {
            try {
                surf.dismiss()
            } catch (_: Throwable) {
            }
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

    /** Activity 销毁 / 引擎解绑时调用：关闭窗口并释放 JNI surface 引用。 */
    fun release() {
        close()
    }

    /** 清空视图引用并释放 surface（只做一次，避免重复释放）。 */
    private fun releaseView() {
        val controls = view
        view = null
        try {
            controls?.release()
        } catch (_: Throwable) {
        }
        // surface 的 JNI global ref 由 surface 窗的 View 自己 dispose
        // （window 销毁 → surfaceDestroyed → 事件 + 释放）。
        val surf = surfaceView
        surfaceView = null
        try {
            surf?.dispose()
        } catch (_: Throwable) {
        }
    }

    private companion object {
        const val SURFACE_VIEW_ID = -1

        /** 倍速循环档位，与 Flutter 侧常用档位保持一致。 */
        val SPEED_STEPS = listOf(1.0, 1.25, 1.5, 2.0, 0.75)

        fun nextSpeed(current: Double): Double {
            val idx = SPEED_STEPS.indexOfFirst { Math.abs(it - current) < 0.01 }
            return SPEED_STEPS[(idx + 1).mod(SPEED_STEPS.size)]
        }
    }
}
