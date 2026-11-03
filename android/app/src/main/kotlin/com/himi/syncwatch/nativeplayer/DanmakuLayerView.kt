package com.himi.syncwatch.nativeplayer

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.view.View

/**
 * 原生弹幕渲染层（安卓）。
 *
 * 原生 UI 下 Flutter 弹幕层随视频区一并退场，弹幕改由本层渲染（真机回归
 * 「弹幕开关点了没反应」）。语义**逐条镜像** Flutter
 * `DanmakuOverlay` + `DanmakuTimeline`（即 MDK 路径的弹幕实现），并复用
 * 鸿蒙 `DanmakuLayer` 已验证的五条修法。
 *
 * 589 重写要点（对照旧实现逐项）：
 * 1. **行号绑定生命周期**（旧：每次 items 变化全量重分配 → 最老条目滑出后
 *    后续条目全部拿到更小行号 → 整屏上移/跳行）。改为 `laneOf` 增量分配，
 *    与 Flutter `_pickRow` 同构（三组独立冲突表：滚动/顶/底）。
 * 2. **飞行缓存**（旧：窗口滑出即丢弃 → 滚到一半被拦腰斩断）。已入屏的
 *    弹幕画到穿屏结束（+500ms 余量）才移除，同时释放行号。
 * 3. **倍速外推**（旧：`anchorPos + (now - anchorWall)` 没乘 speed → 2× 播
 *    放时锚点间弹幕只有半速、每 500ms 跳一下）。改为乘 speed，与宿主
 *    `positionAt` 同速（同鸿蒙 `positionNowMs`）。
 * 4. **底部弹幕位置**（旧：`H - edgePad - lane*rowH` 贴屏幕底缘）。改
 *    `H - edgePad - (lane+1)*rowH + fontSize`，对齐 Flutter `(row+1)`。
 * 5. **顶/底冲突检测**（旧：纯轮转 `(row+1)%n` → 同屏重叠）。改冲突表 +
 *    溢出丢弃（同 Flutter `if (row < 0) continue`）。
 * 6. **行数自适应扣边距**（旧：`height/rowH` 未扣 `edgePad*2`，末行出屏）。
 * 7. **固定弹幕淡入淡出**（旧：硬出现/硬消失），对齐 Flutter `_fixedFade`
 *    首尾各 10% 生命周期。
 * 8. **文本宽度测量缓存**（旧：每帧对每条 measureText，60fps × 数十条）。
 * 9. **转屏/尺寸变化重排**（旧：`autoRows` 用 update 时的 height，key 不变
 *    就永不重算 → 竖屏只铺横屏那几行）。
 * 10. **无活跃弹幕不重绘**（旧：`onDraw` 末尾无条件 postInvalidate）。
 *
 * 观感照抄 Flutter `_buildItem`：w500 + 黑 54% blur3 描影（深色/亮色画面
 * 上都可读）。
 */
class DanmakuLayerView(context: Context) : View(context) {

    /** 弹幕窗口（Dart 按 [当前位置-保留时长, 当前位置+30s] 切窗推送）。 */
    private var items: List<AndroidDanmakuItem> = emptyList()

    private var enabled = false
    private var speed = 1.0
    private var fontSizeScale = 1.0
    private var opacity = 1.0

    /** 行数设置（滚动 = 上限按屏高自适应；顶/底 = 行数）。 */
    private var scrollRows = 30
    private var topRows = 4
    private var bottomRows = 4

    /** 当前播放位置锚点（ms）；由宿主 tick 喂入。 */
    private var anchorPosMs = 0L

    /** 锚点的墙钟时刻（锚点间自插值，不等 tick 的 500ms 跳变）。 */
    private var anchorWallMs = 0L

    /** 暂停冻结（暂停时锚点不推进）。 */
    private var paused = true

    /**
     * 行号绑定表（`timeMs:text` → lane），**一旦分配不再变**。
     *
     * -1 = 轨道满被丢弃（不渲染，同 Flutter `if (row < 0) continue`）。
     */
    private val laneOf = HashMap<String, Int>()

    /** 三组独立冲突表（各行「轨道空闲起始时刻」，ms）。 */
    private var scrollAvail = DoubleArray(0)
    private var topAvail = DoubleArray(0)
    private var bottomAvail = DoubleArray(0)

    /** 飞行中弹幕缓存：窗口滑出后仍画到生命周期结束（防「滚到一半消失」）。 */
    private var flying: MutableList<AndroidDanmakuItem> = ArrayList()

    /** 文本宽度测量缓存 `text|px → width`（字号变化即清空）。 */
    private val measureCache = HashMap<String, Float>()
    private var measuredFontSizePx = -1f

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        // Flutter `fontWeight: FontWeight.w500`。
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }

    /** 基准字号（dp，与 Flutter baseFontSize=25 对齐）。 */
    private val baseFontSizeDp = 25f

    /** 行间附加间距（dp，与 Flutter rowGap=6 对齐）。 */
    private val rowGapDp = 6f

    /** 顶/底安全边距（dp，与 Flutter edgePadding=8 对齐）。 */
    private val edgePadDp = 8f

    /** 滚动穿屏基准时长（ms÷speed）。 */
    private val scrollBaseMs = 8000.0

    /** 顶/底驻留时长（ms，不受速度影响）。 */
    private val fixedMs = 4000.0

    /** 同轨相邻弹幕间隙（ms，Flutter trackGapSeconds=0.15）。 */
    private val trackGapMs = 150.0

    /** 飞行缓存丢弃余量（ms）：生命周期结束后再留这么久。 */
    private val lifeSlackMs = 500.0

    /**
     * 向前保留余量（ms）：弹幕时间比当前位置超前的部分最长保留 35s
     * （Dart 窗口是 +30s）。超过即视为「换集/大跨度 seek」的旧数据，清掉
     * 行号绑定（防 laneOf 无限增长 + 旧集残留）。
     */
    private val keepAheadMs = 35000.0

    fun update(
        items: List<AndroidDanmakuItem>,
        enabled: Boolean,
        speed: Double,
        fontSizeScale: Double,
        opacity: Double,
        scrollRows: Int = 30,
        topRows: Int = 4,
        bottomRows: Int = 4,
    ) {
        this.items = items
        this.enabled = enabled
        this.speed = speed.coerceIn(0.25, 4.0)
        this.fontSizeScale = fontSizeScale.coerceIn(0.25, 4.0)
        this.opacity = opacity.coerceIn(0.0, 1.0)
        this.scrollRows = scrollRows.coerceAtLeast(1)
        this.topRows = topRows.coerceAtLeast(1)
        this.bottomRows = bottomRows.coerceAtLeast(1)
        if (!enabled) {
            // 关闭弹幕：清空一切派生状态（重新打开时从头分配，避免旧集残留）。
            flying.clear()
            laneOf.clear()
            scrollAvail = DoubleArray(0)
            topAvail = DoubleArray(0)
            bottomAvail = DoubleArray(0)
        }
        visibility = if (enabled && items.isNotEmpty()) VISIBLE else GONE
        invalidate()
    }

    /**
     * 宿主 tick 喂入位置锚点。锚点间由本层按墙钟×倍速自插值并逐帧重绘
     * （镜像 Flutter Ticker：500ms 轮询跳变间平滑滚动，暂停冻结、seek 自愈）。
     */
    fun setClock(positionMs: Long, paused: Boolean) {
        this.anchorPosMs = positionMs
        this.anchorWallMs = System.currentTimeMillis()
        this.paused = paused
        if (visibility == VISIBLE && !paused) {
            postInvalidateOnAnimation()
        } else if (visibility == VISIBLE) {
            invalidate()
        }
    }

    /**
     * 自插值当前播放位置：锚点 + 墙钟增量 **× 倍速**。
     *
     * 旧实现漏了倍速因子：2× 播放时播放位置每墙钟秒走 2s，而弹幕只走 1s
     * → 锚点间弹幕半速、每 500ms 跳一下（真机「弹幕忽快忽慢」）。
     */
    private fun currentPositionMs(): Long =
        if (paused) anchorPosMs
        else anchorPosMs + ((System.currentTimeMillis() - anchorWallMs) * speed).toLong()

    /** 转屏/尺寸变化：行容量变了，行号与冲突表必须重排（否则只铺旧行数）。 */
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w == oldw && h == oldh) return
        laneOf.clear()
        scrollAvail = DoubleArray(0)
        topAvail = DoubleArray(0)
        bottomAvail = DoubleArray(0)
    }

    /** 条目键（与鸿蒙 `timeMs:text` 同构）。 */
    private fun keyOf(item: AndroidDanmakuItem): String = "${item.timeMs}:${item.text}"

    /** 当前屏高（未布局时退回屏幕高，与旧实现一致）。 */
    private fun screenHeightPx(): Float =
        if (height > 0) height.toFloat() else resources.displayMetrics.heightPixels.toFloat()

    /** 当前屏宽（未布局时退回屏幕宽）。 */
    private fun screenWidthPx(): Float =
        if (width > 0) width.toFloat() else resources.displayMetrics.widthPixels.toFloat()

    /**
     * 飞行缓存维护：窗口新条目并入（`timeMs:text` 去重），生命周期结束才移除
     * 并释放行号绑定。
     *
     * 【防「莫名消失」】数据源窗口随播放滑动，旧实现窗口一移出就不再渲染 →
     * 滚动弹幕滚到一半被拦腰斩断。缓存保证已入屏的弹幕一定画到生命周期结束。
     */
    private fun syncFlying(all: List<AndroidDanmakuItem>, pos: Double, travelMs: Double) {
        for (item in all) {
            var seen = false
            for (f in flying) {
                if (f.timeMs == item.timeMs && f.text == item.text) {
                    seen = true
                    break
                }
            }
            if (!seen) flying.add(item)
        }
        val alive = ArrayList<AndroidDanmakuItem>(flying.size)
        for (f in flying) {
            val elapsed = pos - f.timeMs
            val life = if (f.mode == "top" || f.mode == "bottom") fixedMs else travelMs
            // 生命周期结束 + 余量 → 移除；超前过多（换集/大跨度 seek）→ 丢弃。
            if (elapsed > life + lifeSlackMs) {
                laneOf.remove(keyOf(f))
                continue
            }
            if (elapsed < -keepAheadMs) {
                laneOf.remove(keyOf(f))
                continue
            }
            alive.add(f)
        }
        flying = alive
    }

    /**
     * 增量行分配（完全复刻 Flutter `DanmakuTimeline._pickRow`）：
     * - 滚动：占行到「完全入屏」+150ms（`textW/(W+textW)` 为完全入屏进度）；
     * - 顶/底：占行 `fixedMs+150ms`；
     * - **轨道满 → 丢弃（lane=-1，不渲染）**，旧实现溢出回 0 行叠加 = 重叠。
     *
     * 只给**新条目**分配；已分配的不再变（防上移/跳行）。
     */
    private fun assignLanes(
        all: List<AndroidDanmakuItem>,
        fontSizePx: Float,
        screenW: Float,
        screenH: Float,
    ) {
        val density = resources.displayMetrics.density
        val rowH = fontSizePx + rowGapDp * density
        val edgePadPx = edgePadDp * density
        // 扣掉上下安全边距再算容量（旧实现漏扣 → 末行出屏）。
        val autoRows = ((screenH - 2 * edgePadPx) / rowH).toInt().coerceAtLeast(1)
        val maxScrollRows = scrollRows.coerceAtMost(autoRows).coerceAtLeast(1)
        val topRowCount = topRows.coerceAtMost(autoRows).coerceAtLeast(1)
        val bottomRowCount = bottomRows.coerceAtMost(autoRows).coerceAtLeast(1)
        if (scrollAvail.size != maxScrollRows) {
            scrollAvail = DoubleArray(maxScrollRows)
            // 行容量变化：旧行号可能越界，整表重排（同 Flutter 重建 timeline）。
            laneOf.clear()
        }
        if (topAvail.size != topRowCount) {
            topAvail = DoubleArray(topRowCount)
            laneOf.clear()
        }
        if (bottomAvail.size != bottomRowCount) {
            bottomAvail = DoubleArray(bottomRowCount)
            laneOf.clear()
        }
        val travelMs = scrollBaseMs / speed
        for (item in all) {
            val key = keyOf(item)
            if (laneOf.containsKey(key)) continue // 已分配（含 -1 丢弃）：不重分配
            val textW = estimateTextWidth(item.text, fontSizePx)
            val isFixed = item.mode == "top" || item.mode == "bottom"
            val occupancy = if (isFixed) {
                fixedMs + trackGapMs
            } else {
                val fullyEntered = if (textW <= 0f) 0.0 else textW.toDouble() / (screenW + textW)
                travelMs * fullyEntered + trackGapMs
            }
            val avail = when (item.mode) {
                "top" -> topAvail
                "bottom" -> bottomAvail
                else -> scrollAvail
            }
            var lane = -1
            for (r in avail.indices) {
                if (avail[r] <= item.timeMs.toDouble()) {
                    avail[r] = item.timeMs + occupancy
                    lane = r
                    break
                }
            }
            // lane = -1 → 轨道满丢弃（对齐 Flutter `if (row < 0) continue`）。
            laneOf[key] = lane
        }
    }

    /**
     * 文本宽度近似（逐字复刻 Flutter `DanmakuTimeline.estimateTextWidth`）：
     * CJK/全角按 1.0×字号，其余按 0.55×。
     *
     * 旧实现只判 `code > 0x2E80`，漏掉韩文/全角标点等区段 → 行冲突估算偏小
     * → 追尾重叠。
     */
    private fun estimateTextWidth(text: String, fontSize: Float): Float {
        var units = 0.0
        for (ch in text) {
            val cp = ch.code
            val isWide = cp >= 0x1100 && (
                cp <= 0x115F ||
                    cp == 0x2329 ||
                    cp == 0x232A ||
                    (cp in 0x2E80..0xA4CF && cp != 0x303F) ||
                    cp in 0xAC00..0xD7A3 ||
                    cp in 0xF900..0xFAFF ||
                    cp in 0xFE30..0xFE4F ||
                    cp in 0xFF00..0xFF60 ||
                    cp in 0xFFE0..0xFFE6
                )
            units += if (isWide) 1.0 else 0.55
        }
        return (units * fontSize).toFloat()
    }

    /** 真实文本宽度（带缓存；字号变化清空缓存）。 */
    private fun textWidth(text: String, fontSizePx: Float): Float {
        if (measuredFontSizePx != fontSizePx) {
            measureCache.clear()
            measuredFontSizePx = fontSizePx
        }
        val key = "$text|$fontSizePx"
        val cached = measureCache[key]
        if (cached != null) return cached
        val w = fillPaint.measureText(text)
        measureCache[key] = w
        return w
    }

    /**
     * 固定弹幕淡入淡出（照抄 Flutter `_fixedFade`）：首尾各 10% 生命周期。
     */
    private fun fixedFade(progress: Double): Double = when {
        progress < 0.1 -> progress / 0.1
        progress > 0.9 -> (1.0 - progress) / 0.1
        else -> 1.0
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!enabled || items.isEmpty()) return
        val pos = currentPositionMs()
        val density = resources.displayMetrics.density
        val fontSizePx = baseFontSizeDp * fontSizeScale.toFloat() * density
        val rowH = fontSizePx + rowGapDp * density
        val edgePadPx = edgePadDp * density
        val travelMs = scrollBaseMs / speed
        val screenW = screenWidthPx()
        val screenH = screenHeightPx()

        // 飞行缓存 ∪ 当前窗口，按 timeMs 排序后增量分配行号
        //（旧实现按原始顺序分配 → 冲突表乱序推进，误丢/跳行）。
        syncFlying(items, pos.toDouble(), travelMs)
        val all = ArrayList<AndroidDanmakuItem>(flying)
        // 按时间升序（旧实现按原始顺序分配 → 冲突表乱序推进，误丢/跳行）。
        all.sortBy { it.timeMs }
        assignLanes(all, fontSizePx, screenW, screenH)

        fillPaint.textSize = fontSizePx
        // Flutter `Shadow(color: Colors.black54, blurRadius: 3)`。
        fillPaint.setShadowLayer(3f * density, 0f, 0f, 0x8A000000.toInt())

        val baseAlpha = (opacity * 255).toInt().coerceIn(0, 255)
        var drewAny = false

        for (item in all) {
            val elapsed = pos - item.timeMs
            val lane = laneOf[keyOf(item)] ?: continue
            if (lane < 0) continue // 轨道满丢弃
            val color = parseColor(item.color)
            if (item.mode == "top" || item.mode == "bottom") {
                if (elapsed < 0 || elapsed > fixedMs) continue
                val progress = (elapsed / fixedMs).coerceIn(0.0, 1.0)
                val alpha = (baseAlpha * fixedFade(progress)).toInt().coerceIn(0, 255)
                if (alpha <= 0) continue
                fillPaint.color = Color.argb(
                    alpha, Color.red(color), Color.green(color), Color.blue(color),
                )
                val textW = textWidth(item.text, fontSizePx)
                val x = (screenW - textW) / 2f
                // baseline：顶部 `edgePad + lane*rowH` 是文本盒顶；底部
                // Flutter 用 `(row+1)`，旧实现漏了 +1 → 贴屏幕底缘。
                val baselineY = if (item.mode == "top") {
                    edgePadPx + lane * rowH + fontSizePx
                } else {
                    screenH - edgePadPx - (lane + 1) * rowH + fontSizePx
                }
                if (baselineY < -fontSizePx || baselineY > screenH) continue
                canvas.drawText(item.text, x, baselineY, fillPaint)
                drewAny = true
            } else {
                if (elapsed < 0 || elapsed > travelMs) continue
                val progress = (elapsed / travelMs).coerceIn(0.0, 1.0)
                fillPaint.color = Color.argb(
                    baseAlpha, Color.red(color), Color.green(color), Color.blue(color),
                )
                val textW = textWidth(item.text, fontSizePx)
                // progress=0 前沿贴右缘外，progress=1 完全离开左缘。
                val x = (screenW - progress * (screenW + textW)).toFloat()
                val baselineY = edgePadPx + lane * rowH + fontSizePx
                if (baselineY < -fontSizePx || baselineY > screenH) continue
                canvas.drawText(item.text, x, baselineY, fillPaint)
                drewAny = true
            }
        }

        // 自驱重绘：仅在「播放中且有弹幕真的画出来」时继续（旧实现无条件
        // postInvalidate → 空层也 60fps 重绘，白耗电）。
        if (!paused && drewAny) {
            postInvalidateOnAnimation()
        }
    }

    private fun parseColor(hex: String): Int = try {
        Color.parseColor(hex)
    } catch (_: Exception) {
        Color.WHITE
    }
}
