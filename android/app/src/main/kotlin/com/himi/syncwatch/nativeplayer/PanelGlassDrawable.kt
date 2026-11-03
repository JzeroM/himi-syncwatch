package com.himi.syncwatch.nativeplayer

import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable

/**
 * 播放器弹层「暖白磨砂」绘制（对齐 Flutter `GlassContainer(light: true)`）。
 *
 * 【为什么不做背景采样】
 * 旧实现按 600ms 周期回读视频帧（GPU→CPU）做折射背景。真机反馈：视频
 * 在动时面板背景**一帧一帧地跳**（约 1.7fps 的静帧序列），与 MDK
 *（Flutter `BackdropFilter` 实时模糊）差距极大。
 *
 * Android 没有节点级 backdrop blur API；要真·实时只能把面板做成独立窗口
 * 走系统 cross-window blur——但那会迫使视频层从硬件 overlay 改为 GPU
 * 合成（HDR 直通失效），且窗口插入可能打断 surface 绑定。权衡后改为
 * **纯暖白渐变磨砂**（不做任何回读）：
 * - 零 GPU→CPU 拷贝、零循环、零跳帧、零黑屏风险；
 * - 暖白基渐变 + 顶部高光 + 暗描边 + 投影，玻璃质感靠光学层表达。
 *
 * 586 由纯白改暖白：纯白在暗适应状态下亮度差近 20:1，弹层弹出时刺眼；
 * 暖白（R>G>B 微弱偏暖）压住亮度，黑字仍然可读。
 *
 * 绘制层次（自下而上）：
 * 1. 暖白基竖向渐变（顶部提亮 = 菲涅尔近似）；
 * 2. 顶部高光带（18% 高度，白 22% → 透明）；
 * 3. 外圈暗描边（1dp 黑 15%）；
 * 4. 内圈细高光线（0.5dp 白 6%，玻璃厚度暗示）。
 */
internal class PanelGlassDrawable(
    private val cornerRadiusDp: Int,
    /**
     * 视图密度（必须由宿主传入，**不能用** `Resources.getSystem()`：
     * 分屏 / 密度覆盖 / 折叠展开时窗口密度与系统密度不一致，会导致
     * 圆角与描边粗细失真）。
     */
    private val density: Float,
    /** 右上/右下是否放平（选集面板全高贴边）。 */
    private val flattenRight: Boolean = false,
) : Drawable() {

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val highlightPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = NPTheme.PANEL_LIGHT_RIM
        style = Paint.Style.STROKE
    }
    private val innerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = NPTheme.PANEL_LIGHT_INNER
        style = Paint.Style.STROKE
    }
    private val rect = RectF()
    private val path = Path()

    override fun draw(canvas: Canvas) {
        val b = bounds
        if (b.isEmpty) return
        val r = dp(cornerRadiusDp).toFloat()
        rect.set(b.left.toFloat(), b.top.toFloat(), b.right.toFloat(), b.bottom.toFloat())

        // 1. 暖白基竖向渐变（顶部提亮 → 基色 → 底部略透）。
        fillPaint.shader = LinearGradient(
            0f, rect.top, 0f, rect.bottom,
            intArrayOf(
                NPTheme.PANEL_LIGHT_TOP,
                NPTheme.PANEL_LIGHT_BASE,
                NPTheme.PANEL_LIGHT_BOTTOM,
            ),
            null as FloatArray?,
            Shader.TileMode.CLAMP,
        )
        buildPath(rect, r)
        canvas.drawPath(path, fillPaint)
        fillPaint.shader = null

        // 2. 顶部高光带（18% 高度，上亮下隐）。
        val hiH = rect.height() * 0.18f
        highlightPaint.shader = LinearGradient(
            0f, rect.top, 0f, rect.top + hiH,
            0x38FFFFFF, 0x00FFFFFF,
            Shader.TileMode.CLAMP,
        )
        buildPath(RectF(rect.left, rect.top, rect.right, rect.top + hiH), r)
        canvas.drawPath(path, highlightPaint)
        highlightPaint.shader = null

        // 3. 外圈暗描边（1dp）。
        buildPath(rect, r)
        rimPaint.strokeWidth = dp(1).toFloat()
        canvas.drawPath(path, rimPaint)

        // 4. 内圈细高光线（0.5dp，暗示玻璃厚度）。
        val inset = dp(1).toFloat()
        buildPath(
            RectF(rect.left + inset, rect.top + inset, rect.right - inset, rect.bottom - inset),
            (r - inset).coerceAtLeast(0f),
        )
        innerPaint.strokeWidth = dp(1).toFloat() / 2f
        canvas.drawPath(path, innerPaint)
    }

    /** 按圆角（可右侧放平）构建圆角矩形路径。 */
    private fun buildPath(target: RectF, radius: Float) {
        path.reset()
        // 圆角顺序：左上、右上、右下、左下（每角 x/y 一对）。
        val radii = if (flattenRight) {
            floatArrayOf(radius, radius, 0f, 0f, 0f, 0f, radius, radius)
        } else {
            floatArrayOf(radius, radius, radius, radius, radius, radius, radius, radius)
        }
        path.addRoundRect(target, radii, Path.Direction.CW)
    }

    private fun dp(v: Int): Int = (v * density).toInt()

    override fun setAlpha(alpha: Int) {
        fillPaint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {
        fillPaint.colorFilter = colorFilter
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = android.graphics.PixelFormat.TRANSLUCENT
}
