package com.himi.syncwatch.nativeplayer

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View

/**
 * 原生弹幕渲染层（原生 UI 下 Flutter 弹幕层随视频区一并退场，弹幕改由
 * 本层渲染——真机回归「弹幕开关点了没反应」）。
 *
 * 语义镜像 Flutter DanmakuOverlay/DanmakuTimeline：
 * - 滚动弹幕：穿屏 8s÷speed，x = width - progress×(width+textW)；
 * - 顶/底弹幕：驻留 4s，水平居中；
 * - 字号 25dp×倍率、行距 6dp、边距 8dp；整体不透明度由参数控制；
 * - 行冲突模型：滚动弹幕占行直到「前沿越过左缘」+0.15s 间隙（同速不追尾）；
 * - 位置纯推导（elapsed = 播放位置 - timeMs），seek 自愈、暂停冻结。
 *
 * 绘制走 Canvas（跨窗口无 GPU 合成，但弹幕是文字层，CPU 绘制足够）。
 * 描边：黑 2px stroke 打底再填充，保证亮画面上可读（与 Flutter 阴影等效）。
 */
class DanmakuLayerView(context: Context) : View(context) {

    /** 弹幕窗口（Dart 按 [当前位置-2s,+30s] 切窗推送）。 */
    private var items: List<AndroidDanmakuItem> = emptyList()

    /** 已分配行号（按 items 顺序，惰性重建）。 */
    private var lanes: IntArray = IntArray(0)

    private var enabled = false
    private var speed = 1.0
    private var fontSizeScale = 1.0
    private var opacity = 1.0

    /** 当前播放位置锚点（ms）；由宿主 tick 喂入。 */
    private var anchorPosMs = 0L

    /** 锚点的墙钟时刻（自插值：锚点间弹幕平滑滚动，不等 tick 的 500ms 跳变）。 */
    private var anchorWallMs = 0L

    /** 暂停冻结（暂停时锚点不推进）。 */
    private var paused = true

    private var lastItemsKey = ""

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        strokeMiter = 4f
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

    /** 同轨相邻弹幕间隙（ms）。 */
    private val trackGapMs = 150.0

    /** 滚动/顶/底行数设置（滚动 = 上限按屏高自适应；顶/底 = 行数）。 */
    private var scrollRows = 30
    private var topRows = 4
    private var bottomRows = 4

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
        val key = items.joinToString("|") { "${it.timeMs}:${it.text}:${it.mode}" } +
            "|r$scrollRows/$topRows/$bottomRows"
        if (key != lastItemsKey) {
            lastItemsKey = key
            assignLanes()
        }
        visibility = if (enabled && items.isNotEmpty()) VISIBLE else GONE
        invalidate()
    }

    /**
     * 宿主 tick 喂入位置锚点。锚点间由本层按墙钟自插值并逐帧重绘
     *（镜像 Flutter Ticker：500ms 轮询跳变间平滑滚动，暂停冻结、seek 自愈）。
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

    /** 自插值当前播放位置（锚点 + 墙钟增量）。 */
    private fun currentPositionMs(): Long =
        if (paused) anchorPosMs
        else anchorPosMs + (System.currentTimeMillis() - anchorWallMs)

    /**
     * 行分配（镜像 DanmakuTimeline 冲突模型）：
     * - 滚动：占行直到「前沿越过左缘」+0.15s；textW 按 CJK/ASCII 近似；
     * - 顶/底：各自独立循环行。
     *
     * 行数取弹幕设置（真机回归：旧实现硬编码 4~16，设置页行数失效）：
     * 滚动 = 用户值为上限、按屏高自适应铺满（同 Flutter
     * `autoRows.clamp(1, config.scrollRows)`）；顶/底 = 用户值。
     * 溢出 **丢弃**（lane=-1）：旧实现回 0 行叠加 = 弹幕重叠（对齐
     * Flutter `if (row < 0) continue` 与鸿蒙实现）。
     */
    private fun assignLanes() {
        val n = items.size
        lanes = IntArray(n) { -1 }
        if (n == 0) return
        val fontSize = baseFontSizeDp * fontSizeScale * resources.displayMetrics.density
        val rowH = fontSize + rowGapDp * resources.displayMetrics.density
        val autoRows = ((height.takeIf { it > 0 } ?: resources.displayMetrics.heightPixels) /
            rowH).toInt().coerceAtLeast(1)
        val maxScrollRows = scrollRows.coerceAtMost(autoRows)
        val topRowCount = topRows.coerceAtMost(autoRows)
        val bottomRowCount = bottomRows.coerceAtMost(autoRows)
        val scrollFreeAt = DoubleArray(maxScrollRows)
        var topRow = 0
        var bottomRow = 0
        for (i in 0 until n) {
            val item = items[i]
            when (item.mode) {
                "top" -> {
                    lanes[i] = topRow
                    topRow = (topRow + 1) % topRowCount
                }
                "bottom" -> {
                    lanes[i] = bottomRow
                    bottomRow = (bottomRow + 1) % bottomRowCount
                }
                else -> {
                    val travelMs = scrollBaseMs / speed
                    val textW = estimateTextWidth(item.text, fontSize.toFloat())
                    val screenW = (width.takeIf { it > 0 }
                        ?: resources.displayMetrics.widthPixels).toFloat()
                    // 前沿越过左缘的时刻 = 出现 + 穿屏×(screenW/(screenW+textW))。
                    val frontExitMs = item.timeMs + travelMs * (screenW / (screenW + textW))
                    var lane = 0
                    while (lane < maxScrollRows && scrollFreeAt[lane] + trackGapMs > item.timeMs) {
                        lane++
                    }
                    if (lane >= maxScrollRows) {
                        lanes[i] = -1 // 轨道满 → 丢弃（禁回 0 行叠加）
                        continue
                    }
                    lanes[i] = lane
                    scrollFreeAt[lane] = frontExitMs
                }
            }
        }
    }

    /** CJK≈1em / ASCII≈0.55em 近似（与 DanmakuTimeline 估算一致）。 */
    private fun estimateTextWidth(text: String, fontSize: Float): Float {
        var w = 0f
        for (ch in text) {
            w += if (ch.code > 0x2E80) fontSize else fontSize * 0.55f
        }
        return w
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!enabled || items.isEmpty()) return
        val positionMs = currentPositionMs()
        val density = resources.displayMetrics.density
        val fontSize = baseFontSizeDp * fontSizeScale.toFloat() * density
        val rowH = fontSize + rowGapDp * density
        val edgePad = edgePadDp * density
        val travelMs = scrollBaseMs / speed
        fillPaint.textSize = fontSize
        strokePaint.textSize = fontSize
        strokePaint.strokeWidth = fontSize * 0.12f

        for (i in items.indices) {
            val item = items[i]
            val elapsed = positionMs - item.timeMs
            val alpha = (opacity * 255).toInt().coerceIn(0, 255)
            val color = parseColor(item.color)
            fillPaint.color = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))
            strokePaint.color = Color.argb((alpha * 0.7).toInt(), 0, 0, 0)

            when (item.mode) {
                "top", "bottom" -> {
                    if (elapsed < 0 || elapsed > fixedMs) continue
                    val lane = lanes.getOrNull(i) ?: 0
                    if (lane < 0) continue // 轨道满丢弃
                    val textW = fillPaint.measureText(item.text)
                    val x = (width - textW) / 2f
                    val y = if (item.mode == "top") {
                        edgePad + fontSize + lane * rowH
                    } else {
                        height - edgePad - lane * rowH
                    }
                    canvas.drawText(item.text, x, y, strokePaint)
                    canvas.drawText(item.text, x, y, fillPaint)
                }
                else -> {
                    if (elapsed < 0 || elapsed > travelMs) continue
                    val lane = lanes.getOrNull(i) ?: 0
                    if (lane < 0) continue // 轨道满丢弃
                    val progress = (elapsed / travelMs).coerceIn(0.0, 1.0)
                    val textW = fillPaint.measureText(item.text)
                    val x = (width - progress * (width + textW)).toFloat()
                    val y = edgePad + fontSize + lane * rowH
                    canvas.drawText(item.text, x, y, strokePaint)
                    canvas.drawText(item.text, x, y, fillPaint)
                }
            }
        }
        // 自驱重绘：播放中且窗口内仍有活跃弹幕时跟随 vsync 连续滚动。
        if (!paused) {
            postInvalidateOnAnimation()
        }
    }

    private fun parseColor(hex: String): Int = try {
        Color.parseColor(hex)
    } catch (_: Exception) {
        Color.WHITE
    }
}
