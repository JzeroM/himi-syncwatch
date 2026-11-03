package com.himi.syncwatch.nativeplayer

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.View
import android.view.animation.LinearInterpolator
import kotlin.math.cos

/**
 * 加载指示器（自绘，复刻 Flutter `CircularProgressIndicator`）。
 *
 * 【为什么不用系统 ProgressBar】系统 `ProgressBar` 的转圈由 ROM 的
 * `progressBarStyle` 决定：不同厂商的弧长、转速、甚至是否动画都不同
 * （部分 ROM 在「动画缩放 0.5x」下几乎静止），真机反馈「就一个圈不好看、
 * 不是动态的」。自绘后任何机型都是同一个「旋转 + 弧长伸缩」的圈。
 *
 * 动画语义对齐 Flutter 的 indeterminate 实现：
 * - 整体以 [ROTATION_MS]（1333ms）线性匀速旋转；
 * - 弧长在 [MIN_SWEEP]~[MAX_SWEEP] 之间平滑往复（首尾交替伸缩），
 *   与旋转同一周期，用余弦缓动近似 Flutter 的曲线。
 *
 * 尺寸/颜色由构造参数设定（本项目固定 36dp / 4dp 描边 / `#6366F1`）。
 * 视图不可见时自动停动画（`onVisibilityAggregated`），零后台空转。
 */
internal class PlayerSpinnerView(
    context: Context,
    /** 直径（dp）。Flutter `CircularProgressIndicator` 默认 36。 */
    private val diameterDp: Float = 36f,
    /** 描边宽（dp）。Flutter 默认 4。 */
    private val strokeDp: Float = 4f,
    /** 弧线颜色。 */
    color: Int = NPTheme.ACCENT,
) : View(context) {

    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = strokeDp * density
        this.color = color
        // Flutter 用 RoundCap：弧线两端是圆头。
        strokeCap = Paint.Cap.ROUND
    }
    private val arcRect = RectF()

    /** 整体旋转角（度）。 */
    private var rotationDeg = 0f
    /** 当前弧长（度）。 */
    private var sweepDeg = MAX_SWEEP / 2f

    private var animator: ValueAnimator? = null

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val size = (diameterDp * density).toInt()
        setMeasuredDimension(size, size)
    }

    override fun onDraw(canvas: Canvas) {
        val inset = paint.strokeWidth / 2f
        arcRect.set(inset, inset, width - inset, height - inset)
        // 起始角 -90°：Flutter 从 12 点方向起画。
        canvas.drawArc(arcRect, rotationDeg - 90f, sweepDeg, false, paint)
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        if (isVisible) start() else stop()
    }

    override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
    }

    private fun start() {
        if (animator?.isRunning == true) return
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = ROTATION_MS
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                val t = it.animatedValue as Float
                rotationDeg = t * 360f
                // 三角波 0→1→0：弧长先伸长再收缩（与 Flutter 首尾交替一致）。
                val phase = if (t < 0.5f) t * 2f else (1f - t) * 2f
                // 余弦缓动：0..1 平滑往复，端点速度为 0（视觉接近 Flutter 曲线）。
                val eased = 0.5f - 0.5f * cos(phase * Math.PI.toFloat())
                sweepDeg = MIN_SWEEP + (MAX_SWEEP - MIN_SWEEP) * eased
                invalidate()
            }
            start()
        }
    }

    private fun stop() {
        animator?.cancel()
        animator = null
    }

    private companion object {
        /** 与 Flutter `_kIndeterminateRotationDuration` 同值。 */
        const val ROTATION_MS = 1333L
        /** 最短弧长（度）：留一点可见弧，避免收缩到 0 时「消失一帧」。 */
        const val MIN_SWEEP = 4f
        const val MAX_SWEEP = 360f
    }
}
