package com.himi.syncwatch.nativeplayer

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.SurfaceView

/**
 * 液态玻璃背景（方案 A）：真采样 + 软模糊 + 边缘折射带 + 光学层。
 *
 * - **采样**：PixelCopy 从 surface 窗（视频）截取帧，1/[GLASS_BLUR_DOWNSAMPLE]
 *   降采样——既是压缩又是**软模糊**（缩小再拉大 = 高斯近似，全版本可用）；
 * - **折射带**：面板边缘 [GLASS_REFRACTION_BAND]dp 带用
 *   [GLASS_REFRACTION_ZOOM] 倍放大帧（凸透镜边缘放大 = 液态玻璃典型折射观感）；
 * - **光学层**：tint 渐变（panelTint）+ rim 描边 + 顶部高光（菲涅尔近似）+
 *   内缘暗描边；
 * - **降级链**：采样失败/未开启玻璃 → 纯 tint 静默兜底。全程 try/catch
 *   隔离，绝不抛出（黑屏红线：控件窗失败必须不影响 surface 窗出画）。
 */
class GlassBackdropDrawable(
    private val surfaceProvider: () -> SurfaceView?,
    private val cornerRadiusPx: Float,
) : Drawable() {

    /** 采样帧（降采样；null = 尚未采到，走 tint 兜底）。 */
    private var sample: Bitmap? = null
    private var sampling = false
    private val mainHandler = Handler(Looper.getMainLooper())

    private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val tintPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1f
        color = NPTheme.RIM
    }
    private val innerRimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1f
        color = NPTheme.GLASS_INNER_RIM
    }

    /** 是否已采到有效帧（决定折射/模糊是否生效）。 */
    val hasSample: Boolean get() = sample != null && !(sample?.isRecycled ?: true)

    /**
     * 触发一次采样（异步）。成功后自动重绘。面板打开期间由宿主按节拍调用；
     * 失败静默（下次再试），不回调异常。
     *
     * 关键：采样源必须是 **SurfaceView**（视频所在的 z-on-top 图层）。
     * 对 Window 重载只会截到控件窗自己的透明层 → 黑底（真机回归）。
     */
    fun sampleAsync() {
        if (sampling) return
        val surface = try {
            surfaceProvider()
        } catch (_: Throwable) {
            null
        } ?: return
        // 按 surfaceView 尺寸（重）建采样位图；尺寸未知时跳过本轮。
        if (surface.width <= 0 || surface.height <= 0) return
        ensureSampleSize(surface.width, surface.height)
        val bmp = sample ?: return
        sampling = true
        try {
            PixelCopy.request(
                surface,
                bmp,
                { result ->
                    sampling = false
                    if (result == PixelCopy.SUCCESS) {
                        invalidateSelf()
                    }
                },
                mainHandler,
            )
        } catch (_: Throwable) {
            sampling = false
        }
    }

    /** 采样位图按目标尺寸（重）建；窗尺寸变化时重建。 */
    private fun ensureSampleSize(windowW: Int, windowH: Int) {
        val w = (windowW / NPTheme.GLASS_BLUR_DOWNSAMPLE).coerceAtLeast(2)
        val h = (windowH / NPTheme.GLASS_BLUR_DOWNSAMPLE).coerceAtLeast(2)
        val cur = sample
        if (cur == null || cur.width != w || cur.height != h) {
            try {
                cur?.recycle()
                sample = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            } catch (_: Throwable) {
                sample = null
            }
        }
    }

    override fun draw(canvas: Canvas) {
        val b = bounds
        if (b.isEmpty) return
        val path = Path()
        val rect = RectF(b)
        path.addRoundRect(rect, cornerRadiusPx, cornerRadiusPx, Path.Direction.CW)
        val save = canvas.save()
        canvas.clipPath(path)

        val bmp = sample
        if (bmp != null && !bmp.isRecycled) {
            try {
                drawRefractedSample(canvas, bmp, rect)
            } catch (_: Throwable) {
                // 采样绘制失败：落入 tint 兜底，不影响其它绘制。
            }
        }

        // tint 渐变（Flutter GlassConfig：tint → tint → tint×0.72）。
        val ta = (NPTheme.PANEL_TINT ushr 24) and 0xFF
        tintPaint.shader = LinearGradient(
            0f, rect.top, 0f, rect.bottom,
            intArrayOf(
                Color.argb(((ta * 1.15).toInt()).coerceAtMost(255), 0x24, 0x27, 0x2D),
                NPTheme.PANEL_TINT,
                Color.argb((ta * 0.72).toInt(), 0x1A, 0x1D, 0x23),
            ),
            null as FloatArray?,
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(rect, tintPaint)

        // 顶部高光带（菲涅尔近似，上亮下隐）。
        val hiH = rect.height() * 0.18f
        tintPaint.shader = LinearGradient(
            0f, rect.top, 0f, rect.top + hiH,
            NPTheme.GLASS_HIGHLIGHT_TOP,
            NPTheme.GLASS_HIGHLIGHT_BOTTOM,
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(rect.left, rect.top, rect.right, rect.top + hiH, tintPaint)
        tintPaint.shader = null

        // rim + 内缘暗描边。
        canvas.drawRoundRect(rect, cornerRadiusPx, cornerRadiusPx, rimPaint)
        val inner = RectF(
            rect.left + 1f, rect.top + 1f, rect.right - 1f, rect.bottom - 1f,
        )
        canvas.drawRoundRect(inner, cornerRadiusPx, cornerRadiusPx, innerRimPaint)
        canvas.restoreToCount(save)
    }

    /** 采样帧绘制：主体模糊底 + 边缘折射带（放大裁边 = 凸透镜观感）。 */
    private fun drawRefractedSample(canvas: Canvas, bmp: Bitmap, rect: RectF) {
        // 主体：全铺（降采样帧拉大 = 软模糊背景）。
        canvas.drawBitmap(bmp, null, rect, paint)

        // 折射带：边缘 band 用 zoom 倍放大帧的对应区（中心不变、边缘放大）。
        val band = NPTheme.GLASS_REFRACTION_BAND * resourcesDensity()
        if (band <= 0f) return
        val zoom = NPTheme.GLASS_REFRACTION_ZOOM
        val srcW = bmp.width.toFloat()
        val srcH = bmp.height.toFloat()
        // 映射 rect→src 坐标。
        val sx = { x: Float -> (x - rect.left) / rect.width() * srcW }
        val sy = { y: Float -> (y - rect.top) / rect.height() * srcH }
        // 四条边带：从放大帧取比原位更「靠里」的窄带，画到边缘 →
        // 视觉上内容沿边缘被推移放大（折射位移近似）。
        val z = (zoom - 1f) * 0.5f
        val insetL = rect.width() * z
        val insetT = rect.height() * z
        // 上带
        canvas.drawBitmap(
            bmp,
            android.graphics.Rect(
                sx(rect.left + insetL).toInt(), sy(rect.top + insetT).toInt(),
                sx(rect.right - insetL).toInt(), sy(rect.top + band + insetT).toInt(),
            ),
            android.graphics.RectF(rect.left, rect.top, rect.right, rect.top + band),
            paint,
        )
        // 下带
        canvas.drawBitmap(
            bmp,
            android.graphics.Rect(
                sx(rect.left + insetL).toInt(), sy(rect.bottom - band - insetT).toInt(),
                sx(rect.right - insetL).toInt(), sy(rect.bottom - insetT).toInt(),
            ),
            android.graphics.RectF(rect.left, rect.bottom - band, rect.right, rect.bottom),
            paint,
        )
        // 左带
        canvas.drawBitmap(
            bmp,
            android.graphics.Rect(
                sx(rect.left + insetL).toInt(), sy(rect.top + insetT).toInt(),
                sx(rect.left + band + insetL).toInt(), sy(rect.bottom - insetT).toInt(),
            ),
            android.graphics.RectF(rect.left, rect.top, rect.left + band, rect.bottom),
            paint,
        )
        // 右带
        canvas.drawBitmap(
            bmp,
            android.graphics.Rect(
                sx(rect.right - band - insetL).toInt(), sy(rect.top + insetT).toInt(),
                sx(rect.right - insetL).toInt(), sy(rect.bottom - insetT).toInt(),
            ),
            android.graphics.RectF(rect.right - band, rect.top, rect.right, rect.bottom),
            paint,
        )
    }

    private fun resourcesDensity(): Float = try {
        android.content.res.Resources.getSystem().displayMetrics.density
    } catch (_: Throwable) {
        1f
    }

    /** 宿主在 surface 窗尺寸已知时调用，按需（重）建采样位图。 */
    fun prepare(windowW: Int, windowH: Int) {
        ensureSampleSize(windowW, windowH)
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {
        paint.colorFilter = colorFilter
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = android.graphics.PixelFormat.TRANSLUCENT

    /** 释放采样位图（宿主 close 时调用）。 */
    fun release() {
        try {
            sample?.recycle()
        } catch (_: Throwable) {
        }
        sample = null
    }

    companion object {
        /** 采样节拍（ms）：面板打开期间 4fps，足以覆盖玻璃慢变化。 */
        const val SAMPLE_INTERVAL_MS = 250L

        /** 安全工厂：任何异常返回 null（调用方降级 tint），绝不抛出。 */
        fun createOrNull(
            surfaceProvider: () -> SurfaceView?,
            cornerRadiusPx: Float,
        ): GlassBackdropDrawable? = try {
            GlassBackdropDrawable(surfaceProvider, cornerRadiusPx)
        } catch (_: Throwable) {
            null
        }
    }
}
