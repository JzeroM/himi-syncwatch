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

    /** 面板在屏幕上的矩形（像素；未喂入时为零 → 降级 tint）。 */
    private val panelRect = android.graphics.Rect()
    /** 采样位图对应的 surface 窗尺寸（映射比例基准）。 */
    private var surfaceW = 0
    private var surfaceH = 0

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

    /**
     * 面板在屏幕上的矩形（像素）。由宿主在每次绘制前喂入——采样位图是
     * **整个 surface 窗**，绘制时必须把它映射到面板所占的那一块，否则
     * 会把整帧视频缩到面板里（真机截图回归「面板显示缩小版全视频」）。
     */
    fun setPanelScreenRect(left: Int, top: Int, right: Int, bottom: Int) {
        panelRect.set(left, top, right, bottom)
    }

    /** 采样位图对应的 surface 窗尺寸（映射比例基准）。 */
    fun setSurfaceSize(width: Int, height: Int) {
        surfaceW = width
        surfaceH = height
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

    /**
     * 采样帧绘制：把**面板所占的那一块**从整帧采样里取出来铺满面板。
     *
     * 采样位图是整个 surface 窗（视频区）。旧实现 `drawBitmap(bmp, null, rect)`
     * 把整帧拉伸铺满面板矩形 → 面板里显示「缩小版全视频」（真机截图回归）。
     * 正确做法：面板屏幕矩形 → 位图源矩形（按采样比例缩放），再画到面板 bounds。
     */
    private fun drawRefractedSample(canvas: Canvas, bmp: Bitmap, rect: RectF) {
        val src = panelSourceRect(bmp) ?: return
        canvas.drawBitmap(bmp, src, rect, paint)

        // 折射带：边缘 band 用放大 zoom 倍的同源区（凸透镜观感）。
        val band = NPTheme.GLASS_REFRACTION_BAND * resourcesDensity()
        if (band <= 0f || rect.width() <= 0f || rect.height() <= 0f) return
        val zoom = NPTheme.GLASS_REFRACTION_ZOOM
        // band 在源矩形里占的像素宽/高（等比换算）。
        val bandSrcX = band / rect.width() * src.width()
        val bandSrcY = band / rect.height() * src.height()
        // 放大倍率对应的源区收缩（中心不变、边缘放大 = 内容沿边缘被推移）。
        val insetSrcX = src.width() * (zoom - 1f) * 0.5f
        val insetSrcY = src.height() * (zoom - 1f) * 0.5f
        val sl = src.left.toFloat()
        val st = src.top.toFloat()
        val sr = src.right.toFloat()
        val sb = src.bottom.toFloat()
        val insetL = sl + insetSrcX
        val insetT = st + insetSrcY
        val insetR = sr - insetSrcX
        val insetB = sb - insetSrcY
        // 上带
        canvas.drawBitmap(
            bmp,
            android.graphics.Rect(
                insetL.toInt(), insetT.toInt(),
                insetR.toInt(), (insetT + bandSrcY).toInt(),
            ),
            android.graphics.RectF(rect.left, rect.top, rect.right, rect.top + band),
            paint,
        )
        // 下带
        canvas.drawBitmap(
            bmp,
            android.graphics.Rect(
                insetL.toInt(), (insetB - bandSrcY).toInt(),
                insetR.toInt(), insetB.toInt(),
            ),
            android.graphics.RectF(rect.left, rect.bottom - band, rect.right, rect.bottom),
            paint,
        )
        // 左带
        canvas.drawBitmap(
            bmp,
            android.graphics.Rect(
                insetL.toInt(), insetT.toInt(),
                (insetL + bandSrcX).toInt(), insetB.toInt(),
            ),
            android.graphics.RectF(rect.left, rect.top, rect.left + band, rect.bottom),
            paint,
        )
        // 右带
        canvas.drawBitmap(
            bmp,
            android.graphics.Rect(
                (insetR - bandSrcX).toInt(), insetT.toInt(),
                insetR.toInt(), insetB.toInt(),
            ),
            android.graphics.RectF(rect.right - band, rect.top, rect.right, rect.bottom),
            paint,
        )
    }

    /**
     * 面板屏幕矩形 → 采样位图源矩形（纯映射，JVM 可单测）。
     *
     * 位图覆盖整个 surface 窗，面板是其中一块，按 `bmp/surface` 比例缩放
     * 并夹到位图范围内。数据缺失或结果过小返回 null（降级 tint）。
     */
    private fun panelSourceRect(bmp: Bitmap): android.graphics.Rect? =
        mapPanelToSource(
            panelLeft = panelRect.left,
            panelTop = panelRect.top,
            panelRight = panelRect.right,
            panelBottom = panelRect.bottom,
            surfaceW = surfaceW,
            surfaceH = surfaceH,
            bmpW = bmp.width,
            bmpH = bmp.height,
        )

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

        /**
         * 面板屏幕矩形 → 采样位图源矩形（纯函数，JVM 可单测）。
         *
         * 位图覆盖整个 surface 窗，面板是其中一块，按 `bmp/surface` 比例
         * 缩放并夹到位图范围内。数据缺失或结果过小返回 null（降级 tint），
         * 绝不画错（黑屏红线：面板失败不能影响出画）。
         */
        fun mapPanelToSource(
            panelLeft: Int,
            panelTop: Int,
            panelRight: Int,
            panelBottom: Int,
            surfaceW: Int,
            surfaceH: Int,
            bmpW: Int,
            bmpH: Int,
        ): android.graphics.Rect? {
            if (panelRight <= panelLeft || panelBottom <= panelTop) return null
            if (surfaceW <= 0 || surfaceH <= 0 || bmpW <= 0 || bmpH <= 0) return null
            val kx = bmpW.toDouble() / surfaceW
            val ky = bmpH.toDouble() / surfaceH
            val left = (panelLeft * kx).toInt().coerceIn(0, bmpW)
            val top = (panelTop * ky).toInt().coerceIn(0, bmpH)
            val right = (panelRight * kx).toInt().coerceIn(0, bmpW)
            val bottom = (panelBottom * ky).toInt().coerceIn(0, bmpH)
            if (right - left < 2 || bottom - top < 2) return null
            return android.graphics.Rect(left, top, right, bottom)
        }

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
