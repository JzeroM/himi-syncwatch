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
 * 液态玻璃背景（方案 A）：真采样 + 边缘折射带 + 光学层。
 *
 * - **采样**：PixelCopy 按面板屏幕矩形（`Rect` 重载）截取视频帧——只拷面板
 *   那一块的像素，数据量比整帧小 ~30 倍，不阻塞 SurfaceFlinger 合成；
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
     *
     * 【性能优化】只采面板矩形（`PixelCopy.request(SurfaceView, Rect, ...)`），
     * 而非整帧（`PixelCopy.request(SurfaceView, Bitmap, ...)`）。整帧 = GPU→CPU
     * 同步拷贝约 10MB/次（每秒 4 次），阻塞 SurfaceFlinger 合成队列 → 视频
     * 呈现卡顿；只采面板矩形（约 320×600dp）降 ~30 倍数据量。
     */
    fun sampleAsync() {
        if (sampling) return
        val surface = try {
            surfaceProvider()
        } catch (_: Throwable) {
            null
        } ?: return
        if (surface.width <= 0 || surface.height <= 0) return
        // 面板矩形未喂入时降级 tint（不清屏、绝不影响出画）。
        if (panelRect.width() <= 2 || panelRect.height() <= 2) return
        // 采样位图 = 面板矩形的逐像素副本（PixelCopy 目标必须与源矩形同尺寸；
        // 模糊由 draw 时的 FILTER_BITMAP_FLAG + 折射带放大近似，不再靠降采样）。
        ensureSampleSize(panelRect.width(), panelRect.height())
        val bmp = sample ?: return
        sampling = true
        try {
            // 只采面板矩形（panelRect），大幅降低 GPU→CPU 拷贝量。
            // 注意：这里是 surface 窗坐标，panelRect 已由宿主按窗坐标喂入。
            PixelCopy.request(
                surface,
                panelRect,
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
     * 面板在屏幕上的矩形（像素）。由宿主在每次绘制前喂入——PixelCopy 只
     * 拷贝这一块，绘制时直接铺满面板 bounds（1:1，不做整窗换算）。
     */
    fun setPanelScreenRect(left: Int, top: Int, right: Int, bottom: Int) {
        panelRect.set(left, top, right, bottom)
    }

    /** 采样位图对应的 surface 窗尺寸（映射比例基准）。 */
    fun setSurfaceSize(width: Int, height: Int) {
        surfaceW = width
        surfaceH = height
    }

    /** 采样位图按面板尺寸（重）建；面板尺寸变化时重建。 */
    private fun ensureSampleSize(panelW: Int, panelH: Int) {
        val w = panelW.coerceAtLeast(2)
        val h = panelH.coerceAtLeast(2)
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
     * 采样帧绘制：把面板采样铺满面板 bounds。
     *
     * 采样位图**就是**面板矩形本身（PixelCopy 只拷 panelRect），因此源矩形
     * 恒为整张位图（1:1）。若把位图当成「整窗的一块」去换算，
     * 会取到面板之外的内容（采样图里根本没有）→ 玻璃错位/空白。
     */
    private fun drawRefractedSample(canvas: Canvas, bmp: Bitmap, rect: RectF) {
        if (bmp.width < 2 || bmp.height < 2) return
        val src = android.graphics.Rect(0, 0, bmp.width, bmp.height)
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
     * PixelCopy 只拷贝面板矩形，位图恒等于面板；这里只做数据校验。
     * 数据缺失或结果过小返回 null（降级 tint）。
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

    /**
     * 预留（宿主布局完成后调用）。采样位图尺寸现由面板矩形决定，故只按
     * 当前已知面板矩形建一次；面板未定位时是空操作。
     */
    fun prepare() {
        if (panelRect.width() <= 2 || panelRect.height() <= 2) return
        ensureSampleSize(panelRect.width(), panelRect.height())
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
        /** 采样节拍（ms）：面板打开期间 ~1.7fps，足够覆盖玻璃慢变化。
         *  旧值 250ms（4fps）导致每秒 4 次 GPU→CPU 同步拷贝，阻塞
         *  SurfaceFlinger 合成 → 视频呈现卡顿（真机回归）。 */
        const val SAMPLE_INTERVAL_MS = 600L

        /**
         * 面板屏幕矩形 → 采样位图源矩形（纯函数，JVM 可单测）。
         *
         * 【契约】PixelCopy 只拷贝面板矩形，因此**位图恒等于面板**：源矩形
         * 就是整张位图 `(0, 0, bmpW, bmpH)`。旧实现把位图当「整窗的一块」按
         * `bmpW/surfaceW` 换算，在面板矩形采样下会取到面板之外的内容（玻璃
         * 错位 / 空白）。数据缺失或结果过小返回 null（降级 tint），绝不画错
         * （黑屏红线：面板失败不能影响出画）。
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
            // 采样源是 surface 窗；面板矩形必须落在窗内（越界 = 脏数据，降级）。
            if (panelLeft < 0 || panelTop < 0) return null
            if (panelRight > surfaceW || panelBottom > surfaceH) return null
            if (bmpW < 2 || bmpH < 2) return null
            // 位图 = 面板的逐像素副本 → 源矩形即整张位图。
            return android.graphics.Rect(0, 0, bmpW, bmpH)
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
