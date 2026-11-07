package com.himi.syncwatch.nativeplayer

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.util.TypedValue
import android.view.View

/**
 * 手势亮度/音量柱条（逐项复刻 Flutter `_buildVerticalBar`）。
 *
 * Flutter 结构（`player_screen.dart` `_buildVerticalBar`）：
 * ```
 * Container(width: 36, decoration: 黑54% + 圆角 18)
 *   Column
 *     SizedBox(height: 12)
 *     Icon(18, 白70)                  ← 亮度 brightness_6 / 音量 volume_*
 *     SizedBox(height: 8)
 *     Expanded(RotatedBox(-1, SliderTheme(trackHeight:4, thumbRadius:6,
 *              overlayRadius:10, accent: 亮度#FFD54F / 音量#6366F1)))
 *     Text('${(value*100).round()}%', 11sp, 白70)
 *     SizedBox(height: 8)
 * ```
 *
 * 旧实现只是一个 `TextView` 显示「45%」的圆角黑底——无图标、无轨道、
 * 无进度可视化（真机回归「手势柱条 UI 与 MDK 不一致」）。这里自绘：
 * 图标位由宿主注入字形（[setIcon]），轨道/拇指/光晕全在 onDraw 完成。
 */
internal class VerticalGaugeView(context: Context) : View(context) {

    /** 0..1 的当前值。 */
    var value: Double = 0.0
        set(v) {
            val next = v.coerceIn(0.0, 1.0)
            if (next == field) return
            field = next
            invalidate()
        }

    /** 轨道强调色（亮度 #FFD54F / 音量 #6366F1）。 */
    var accent: Int = NPTheme.GAUGE_VOLUME
        set(v) {
            if (v == field) return
            field = v
            invalidate()
        }

    /** 顶部图标字形（Material 图标字体码点；0 = 不画）。 */
    private var iconCodePoint: Int = 0
    private var iconText: String = ""
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = NPTheme.WHITE_70
        textAlign = Paint.Align.CENTER
        textSize = sp(NPTheme.GAUGE_ICON)
        typeface = NativePlayerIcons.typeface(context)
    }

    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = NPTheme.GAUGE_BG
    }
    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x3DFFFFFF // 未填充段：白 24%
    }
    private val activePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val thumbPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = NPTheme.WHITE }
    private val overlayPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val percentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = NPTheme.WHITE_70
        textAlign = Paint.Align.CENTER
        textSize = sp(NPTheme.GAUGE_PERCENT_SIZE)
    }

    private val rect = RectF()

    /** 设置顶部图标（字形码点；宿主按亮度/音量切换）。 */
    fun setIcon(codePoint: Int) {
        if (codePoint == iconCodePoint) return
        iconCodePoint = codePoint
        iconText = if (codePoint == 0) "" else String(Character.toChars(codePoint))
        invalidate()
    }

    /** 百分比文本（纯函数，可单测）：`(value*100).round()`。 */
    internal fun percentOf(value: Double): Int = Math.round(value * 100).toInt()

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        // 底：圆角 18 黑 54%
        rect.set(0f, 0f, w, h)
        val radius = dp(NPTheme.GAUGE_RADIUS).toFloat()
        canvas.drawRoundRect(rect, radius, radius, bgPaint)

        // 顶部图标（居中，12dp 处）
        val iconSize = sp(NPTheme.GAUGE_ICON)
        if (iconText.isNotEmpty()) {
            // 文本基线 = 图标框中心 + 约 1/3 字高（视觉居中）。
            val cy = dp(NPTheme.GAUGE_TOP_PAD).toFloat() + iconSize / 2f
            canvas.drawText(iconText, w / 2f, cy + iconSize / 3f, iconPaint)
        }

        // 竖向轨道区：图标下 8dp → 百分比上 8dp
        val trackTop = dp(NPTheme.GAUGE_TOP_PAD).toFloat() + iconSize +
            dp(NPTheme.GAUGE_ICON_GAP).toFloat()
        val trackBottom = h - dp(NPTheme.GAUGE_BOTTOM_PAD).toFloat() -
            sp(NPTheme.GAUGE_PERCENT_SIZE) - dp(NPTheme.GAUGE_ICON_GAP).toFloat()
        if (trackBottom <= trackTop) return

        val trackH = dp(NPTheme.GAUGE_TRACK).toFloat()
        val cx = w / 2f
        val trackW = trackH
        // 未填充整段
        rect.set(cx - trackW / 2f, trackTop, cx + trackW / 2f, trackBottom)
        val halfRound = trackW / 2f
        canvas.drawRoundRect(rect, halfRound, halfRound, trackPaint)

        // 已填充段：从**底部**往上（纵向进度条 = 值越大越高）
        val filled = (trackBottom - trackTop) * value.toFloat()
        if (filled > 0f) {
            activePaint.color = accent
            rect.set(
                cx - trackW / 2f,
                trackBottom - filled,
                cx + trackW / 2f,
                trackBottom,
            )
            canvas.drawRoundRect(rect, halfRound, halfRound, activePaint)
        }

        // 拇指：白圆 + accent 光晕（Flutter thumbRadius:6 / overlayRadius:10）
        val thumbY = trackBottom - filled
        val overlayR = dp(NPTheme.GAUGE_OVERLAY).toFloat()
        overlayPaint.color = accent
        overlayPaint.alpha = 0x40
        canvas.drawCircle(cx, thumbY, overlayR, overlayPaint)
        canvas.drawCircle(cx, thumbY, dp(NPTheme.GAUGE_THUMB).toFloat(), thumbPaint)

        // 底部百分比
        val textY = h - dp(NPTheme.GAUGE_BOTTOM_PAD).toFloat()
        // 624：三端统一为**纯数字**（无 % 号），对齐 Flutter
        // `Text('${(value * 100).round()}')`。
        canvas.drawText("${percentOf(value)}", cx, textY, percentPaint)
    }

    private fun dp(v: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics,
        ).toInt()

    /** sp 换算：字号常量有 Int（18）与 Float（11f）两种，重载统一入口。 */
    private fun sp(v: Int): Float = sp(v.toFloat())

    private fun sp(v: Float): Float =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, v, resources.displayMetrics,
        )
}
