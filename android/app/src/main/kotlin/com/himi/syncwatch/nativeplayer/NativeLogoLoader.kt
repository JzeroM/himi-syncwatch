package com.himi.syncwatch.nativeplayer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.view.View
import android.widget.ImageView
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Logo 轻量网络图片加载器（原生控件窗无图片库可用）。
 *
 * HttpURLConnection + LruCache + 单线程解码；按 ImageView tag 做过期
 * 取消（快速切集/切线路时旧结果不覆盖新图）。加载失败静默隐藏，与
 * Flutter EmbyImage 的「失败不占位」行为一致。
 */
object NativeLogoLoader {
    private const val CONNECT_TIMEOUT_MS = 5000
    private const val READ_TIMEOUT_MS = 8000

    /** 解码上限：Logo 展示尺寸 240×44，2x 余量足够。 */
    private const val MAX_BITMAP_PX = 960

    /** 缓存上限 8MB（约十张 Logo）。 */
    private const val CACHE_BYTES = 8 * 1024 * 1024

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "himi-logo-loader")
    }
    private val cache = object : LruCache<String, Bitmap>(CACHE_BYTES) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    /** 加载 logo 到 view；url 为空或加载失败时隐藏 view。 */
    fun load(view: ImageView, url: String?) {
        if (url.isNullOrEmpty()) {
            view.tag = null
            view.setImageBitmap(null)
            view.visibility = View.GONE
            return
        }
        if (view.tag == url && view.drawable != null) {
            view.visibility = View.VISIBLE
            return
        }
        view.tag = url
        cache.get(url)?.let { bitmap ->
            view.setImageBitmap(bitmap)
            view.visibility = View.VISIBLE
            return
        }
        executor.execute {
            val bitmap = fetch(url)
            mainHandler.post {
                if (view.tag != url) return@post // 已被新请求取代
                if (bitmap != null) {
                    view.setImageBitmap(bitmap)
                    view.visibility = View.VISIBLE
                } else {
                    view.setImageBitmap(null)
                    view.visibility = View.GONE
                }
            }
        }
    }

    private fun fetch(url: String): Bitmap? = try {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = CONNECT_TIMEOUT_MS
            conn.readTimeout = READ_TIMEOUT_MS
            conn.instanceFollowRedirects = true
            if (conn.responseCode != HttpURLConnection.HTTP_OK) {
                null
            } else {
                conn.inputStream.use { input -> decodeSampled(input.readBytes()) }
            }
        } finally {
            conn.disconnect()
        }
    } catch (_: Exception) {
        null
    }

    /** 二次采样解码：大图先按 bounds 计算 inSampleSize，避免 OOM。 */
    private fun decodeSampled(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_BITMAP_PX) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
    }
}
