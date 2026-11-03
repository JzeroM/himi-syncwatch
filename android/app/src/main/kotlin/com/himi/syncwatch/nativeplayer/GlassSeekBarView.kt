package com.himi.syncwatch.nativeplayer

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 玻璃质感滑杆——**完全复刻鸿蒙 [GlassSlider]（ArkTS）**，等价 Flutter
 * `glassSliderTheme`（GlassSliderTrackShape + GlassSliderThumbShape）。
 *
 * 轨道：6dp 圆角，未播段三段垂直渐变（白 22% 提亮 → 本色 → 黑 18% 压暗），
 * 顶部高光线并入渐变首档；已播段 accent 三段渐变 + 柔光晕（blur6 30%）。
 *
 * 拇指：28dp accent 30% 光晕圆 + 16dp 三段玻璃渐变圆体（白 38% 提亮 →
 * accent → 黑 16% 压暗）+ 顶部高光**弧**（描边圆环半径 6.4dp、扫角 ±75.6°、
 * 白 75%/1.6dp 圆头，同 Flutter drawArc）。
 *
 * 交互：`onTouchEvent` 单指按下/移动 → [onChanged]（按 [step] 吸附），抬起
 * → [onCommit]。触点映射 `x → ratio` 与拇指 `ratio × trackW` 同基准（真机
 * 「拖动触摸位置不一致」教训）。
 *
 * 【几何】轨道横向内缩 [GLOW_D]/2：光晕直径 28dp 大于视图时 canvas 会裁掉
 * 溢出部分（Android View 画不出界），内缩保证两端光晕完整；值映射按内缩后
 * 的轨道宽计算，触摸与拇指同基准。
 */
class GlassSeekBarView(context: Context) : View(context) {

    companion object {
        /** 轨道高（dp）。 */
        const val TRACK_H = 6f

        /** 拇指体直径（dp）。 */
        const val THUMB_D = 16f

        /** 拇指光晕直径（dp）。 */
        const val GLOW_D = 28f

        /** 高光弧描边宽（dp）。 */
        const val HIGHLIGHT_W = 1.6f

        /**
         * 触点 x → 吸附后的值（纯函数，JVM 可测）。
         *
         * 与鸿蒙 `GlassSlider.valueAt` 同式：`ratio = (x - pad) / trackW`
         * 钳制 [0,1]，线性映射后按 [step] 吸附，最终夹回 [min,max]。
         */
        fun snapValue(
            x: Float,
            trackW: Float,
            pad: Float,
            min: Float,
            max: Float,
            step: Float,
        ): Float {
            val ratio = if (trackW > 0f) {
                ((x - pad) / trackW).coerceIn(0f, 1f)
            } else {
                0f
            }
            val v = min + ratio * (max - min)
            val snapped = if (step > 0f) Math.round(v / step) * step else v
            return snapped.coerceIn(min, max)
        }

        /** 值 → 触点中心 x（snapValue 的逆映射，纯函数，JVM 可测）。 */
        fun centerXOf(
            value: Float,
            trackW: Float,
            pad: Float,
            min: Float,
            max: Float,
        ): Float {
            val span = max - min
            val ratio = if (span > 0f) ((value - min) / span).coerceIn(0f, 1f) else 0f
            return pad + ratio * trackW
        }
    }

    /** 当前值（外部 set 同步 → 重绘；拖动中由触点驱动）。 */
    var value: Float = 0f
        set(v) {
            field = v
            if (!dragging) invalidate()
        }

    var minValue: Float = 0f
    var maxValue: Float = 1f

    /**
     * 拇指体直径（dp，默认 16 = 进度条档）。调节面板用 18（Flutter
     * `glassSliderTheme(thumbRadius: 9)`）。
     */
    var thumbDp: Float = THUMB_D
        set(v) {
            field = v
            invalidate()
        }

    /**
     * 拇指光晕直径（dp，默认 28 = 进度条档）。调节面板用 32（Flutter
     * `overlayRadius: 16`）。
     */
    var glowDp: Float = GLOW_D
        set(v) {
            field = v
            invalidate()
        }

    /** 吸附步长（0 = 连续；seek 用 1000ms 档，同鸿蒙 ProgressRow step）。 */
    var step: Float = 0f

    /** 拖动中回调（吸附后的值）。 */
    var onChanged: ((Float) -> Unit)? = null

    /** 抬手提交回调（seek 等一次性动作用）。 */
    var onCommit: ((Float) -> Unit)? = null

    /** 拖动中（外部进度刷新跳过用）。 */
    var dragging: Boolean = false
        private set

    /**
     * 浅色档（浅底容器内的滑杆，默认 false）。
     *
     * 深色档的白色渐变在浅底上几乎不可见（真机回归「面板滑杆看不清」）；
     * 浅色档改黑系轨道 + 纯白拇指 + accent 光晕。587 弹层改深色后
     * 面板滑杆恢复走深色档，此档保留供未来的浅底场景。
     */
    var light: Boolean = false
        set(v) {
            if (v == field) return
            field = v
            invalidate()
        }

    private val density = resources.displayMetrics.density
    private val padPx get() = glowDp / 2f * density

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val thumbPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val highlightPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = HIGHLIGHT_W * density
        strokeCap = Paint.Cap.ROUND
        color = 0xB3FFFFFF.toInt() // 白 75%（同鸿蒙 '#B3FFFFFF'）
    }

    private val trackRect = RectF()
    private val activeRect = RectF()
    private val thumbRect = RectF()
    private val highlightRect = RectF()

    init {
        minimumHeight = (GLOW_D * density).roundToInt()
        isClickable = true
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        val pad = padPx
        val trackW = max(0f, w - 2f * pad)
        val cy = h / 2f
        val trackHalf = TRACK_H / 2f * density
        val thumbR = thumbDp / 2f * density
        val glowR = glowDp / 2f * density
        val ratio = if (maxValue > minValue) {
            ((value - minValue) / (maxValue - minValue)).coerceIn(0f, 1f)
        } else {
            0f
        }

        // 层 1：未播轨（三段玻璃渐变，高光并入首档，同鸿蒙 GlassSlider）。
        trackRect.set(pad, cy - trackHalf, pad + trackW, cy + trackHalf)
        trackPaint.shader = LinearGradient(
            0f, trackRect.top, 0f, trackRect.bottom,
            if (light) {
                intArrayOf(0x2E000000, 0x1F000000, 0x14000000)
            } else {
                intArrayOf(0x58FFFFFF.toInt(), 0x29FFFFFF.toInt(), 0x22D1D1D1.toInt())
            },
            floatArrayOf(0f, 0.35f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawRoundRect(trackRect, trackHalf, trackHalf, trackPaint)

        // 层 2：已播段（accent 三段渐变 + 柔光晕 ≈ Flutter blur6 30%）。
        // 光晕用双层膨胀圆角矩形近似（BlurMaskFilter 在硬加速画布上不稳定）。
        val activeW = trackW * ratio
        if (activeW > 0f) {
            activeRect.set(pad, cy - trackHalf, pad + activeW, cy + trackHalf)
            glowPaint.color = 0x2E6366F1 // accent 18%（外层光晕）
            canvas.drawRoundRect(
                activeRect.left - 3f * density, activeRect.top - 3f * density,
                activeRect.right + 3f * density, activeRect.bottom + 3f * density,
                trackHalf + 3f * density, trackHalf + 3f * density, glowPaint,
            )
            glowPaint.color = 0x3D6366F1 // accent 24%（内层光晕）
            canvas.drawRoundRect(
                activeRect.left - 1.5f * density, activeRect.top - 1.5f * density,
                activeRect.right + 1.5f * density, activeRect.bottom + 1.5f * density,
                trackHalf + 1.5f * density, trackHalf + 1.5f * density, glowPaint,
            )
            trackPaint.shader = LinearGradient(
                0f, activeRect.top, 0f, activeRect.bottom,
                intArrayOf(0xFF9294F5.toInt(), 0xFF6366F1.toInt(), 0xFF575AD4.toInt()),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP,
            )
            canvas.drawRoundRect(activeRect, trackHalf, trackHalf, trackPaint)
        }

        // 层 3：拇指（光晕圆 + 三段渐变圆体 + 顶部高光弧）。
        val cx = pad + ratio * trackW
        thumbRect.set(cx - glowR, cy - glowR, cx + glowR, cy + glowR)
        glowPaint.color = 0x4D6366F1 // accent 30%（同鸿蒙 GLOW）
        canvas.drawOval(thumbRect, glowPaint)

        thumbRect.set(cx - thumbR, cy - thumbR, cx + thumbR, cy + thumbR)
        thumbPaint.shader = LinearGradient(
            0f, thumbRect.top, 0f, thumbRect.bottom,
            if (light) {
                intArrayOf(0xFFFFFFFF.toInt(), 0xFFF5F5F7.toInt(), 0xFFE4E4E8.toInt())
            } else {
                intArrayOf(0xFF9EA0F6.toInt(), 0xFF6366F1.toInt(), 0xFF5356CA.toInt())
            },
            floatArrayOf(0f, 0.55f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawOval(thumbRect, thumbPaint)

        // 顶部高光弧：描边圆环（中心线半径 ≈ thumbDp/2−HIGHLIGHT_W），
        // 扫角 ±75.6°（同 Flutter GlassSliderThumbShape drawArc）。
        val hr = (thumbDp / 2f - HIGHLIGHT_W) * density
        highlightRect.set(cx - hr, cy - hr, cx + hr, cy + hr)
        // 浅色档拇指是白的：白高光弧看不见 → 改用极淡暗弧表达「厚度」。
        highlightPaint.color =
            if (light) 0x33000000 else 0xB3FFFFFF.toInt()
        canvas.drawArc(highlightRect, -165.6f, 151.2f, false, highlightPaint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!isEnabled) return false
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                parent?.requestDisallowInterceptTouchEvent(true)
                dragging = true
                emit(event.x)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (dragging) emit(event.x)
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (dragging) {
                    dragging = false
                    if (maxValue > minValue) {
                        onCommit?.invoke(value)
                    }
                }
                parent?.requestDisallowInterceptTouchEvent(false)
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    /** 触点 → 值（与拇指定位同基准）→ 拖动回调 + 重绘。 */
    private fun emit(x: Float) {
        val trackW = max(0f, width - 2f * padPx)
        if (maxValue <= minValue) {
            // 范围未就绪（起播早期 duration=0）：钳到 min 但不回调
            //（无意义 seek），触摸仍响应（真机回归「进度条拖不动」）。
            value = minValue
            invalidate()
            return
        }
        value = snapValue(x, trackW, padPx, minValue, maxValue, step)
        onChanged?.invoke(value)
        invalidate()
    }
}
