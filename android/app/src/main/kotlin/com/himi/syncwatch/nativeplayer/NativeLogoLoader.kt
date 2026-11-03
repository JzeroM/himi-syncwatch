package com.himi.syncwatch.nativeplayer

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import android.view.View
import android.widget.ImageView
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.PriorityBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * 原生控件窗的轻量网络图片加载器（无第三方图片库可用）。
 *
 * 588 重做（真机「选集面板封面加载太慢」）：
 * - **4 线程**（旧实现单线程串行，20 集要排队几十秒）；
 * - **磁盘 LRU**（`cacheDir/native_poster`，64MB，key = URL 的 SHA-256）：
 *   同一剧集重开面板/重进播放页时秒出，不再重复下载；
 * - **按目标宽二次采样**（旧实现固定 960px 上限：选集封面 900px 宽也按
 *   960 解，解码/内存都浪费；Logo 240px 宽也被解成 960）；
 * - **优先级队列**：当前集 0 → 邻集 1 → 其余 2（P0 先出图，对齐
 *   Flutter 选集面板「当前集立刻可见」的观感）；
 * - 面板关闭调 [cancelPending] 清空等待队列，避免关面板后仍在跑无用下载。
 *
 * 失败静默隐藏，与 Flutter `EmbyImage` 的「失败不占位」行为一致。
 * 按 `ImageView.tag` 做过期取消（快速切集/切线路时旧结果不覆盖新图）。
 */
object NativeLogoLoader {
    private const val CONNECT_TIMEOUT_MS = 5000
    private const val READ_TIMEOUT_MS = 8000

    /** 未指定目标宽时的解码上限（Logo 展示 240×44，2x 余量足够）。 */
    private const val DEFAULT_MAX_BITMAP_PX = 960

    /** 内存缓存 16MB（约 8~16 张选集封面）。 */
    private const val MEMORY_CACHE_BYTES = 16 * 1024 * 1024

    /** 磁盘缓存 64MB（约 200 张封面缩略图/原图字节）。 */
    private const val DISK_CACHE_BYTES = 64L * 1024 * 1024

    /** 并发下载/解码线程数。 */
    private const val THREADS = 4

    /** 优先级：当前集 / 邻集 / 其余。 */
    const val PRIORITY_CURRENT = 0
    const val PRIORITY_NEIGHBOR = 1
    const val PRIORITY_REST = 2

    private val mainHandler = Handler(Looper.getMainLooper())
    private val seq = AtomicLong()

    /** 取消代际：递增后队列里的旧任务直接退出（不下载、不回贴）。 */
    @Volatile
    private var generation: Long = 0L

    @Volatile
    private var diskDir: File? = null

    private val cache = object : LruCache<String, Bitmap>(MEMORY_CACHE_BYTES) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    /**
     * 优先级线程池。
     *
     * `PriorityBlockingQueue` 的 `take()` 需要元素可比较，因此任务统一包成
     * [PriorityTask]（priority 升序 + 入队序号保证同优先级 FIFO）。
     */
    private val executor = ThreadPoolExecutor(
        THREADS,
        THREADS,
        30L,
        TimeUnit.SECONDS,
        PriorityBlockingQueue<Runnable>(),
    ) { runnable ->
        Thread(runnable, "himi-image-loader").apply { isDaemon = true }
    }

    /** 加载图片到 view；url 为空或加载失败时隐藏 view。 */
    fun load(view: ImageView, url: String?) =
        load(view, url, targetWidthPx = 0, priority = PRIORITY_REST)

    /**
     * 加载图片到 view。
     *
     * @param targetWidthPx 展示目标宽（px，0 = 用 [DEFAULT_MAX_BITMAP_PX]）；
     *   按此宽做 `inSampleSize` 二次采样，避免整图解码。
     * @param priority [PRIORITY_CURRENT] / [PRIORITY_NEIGHBOR] / [PRIORITY_REST]。
     */
    fun load(
        view: ImageView,
        url: String?,
        targetWidthPx: Int,
        priority: Int = PRIORITY_REST,
    ) {
        if (url.isNullOrEmpty()) {
            view.tag = null
            view.setImageBitmap(null)
            view.visibility = View.GONE
            return
        }
        val key = cacheKey(url, targetWidthPx)
        if (view.tag == key && view.drawable != null) {
            view.visibility = View.VISIBLE
            return
        }
        view.tag = key
        cache.get(key)?.let { bitmap ->
            view.setImageBitmap(bitmap)
            view.visibility = View.VISIBLE
            return
        }
        val gen = generation
        executor.execute(
            PriorityTask(priority, seq.incrementAndGet()) {
                // 已取消（面板关闭/新一批加载）：不下载、不回贴。
                if (gen == generation) {
                    val bitmap = fetch(view.context, url, targetWidthPx, gen)
                    mainHandler.post {
                        if (view.tag != key) return@post // 已被新请求取代
                        if (bitmap != null) {
                            cache.put(key, bitmap)
                            view.setImageBitmap(bitmap)
                            view.visibility = View.VISIBLE
                        } else {
                            view.setImageBitmap(null)
                            view.visibility = View.GONE
                        }
                    }
                }
            },
        )
    }

    /**
     * 清空等待队列（面板关闭时调用）。
     *
     * 只清「还没开始跑」的任务；正在跑的 4 个会因代际变化在回贴前退出。
     * 内存/磁盘缓存保留（重开面板仍然秒出）。
     */
    fun cancelPending() {
        generation += 1
        executor.queue.clear()
    }

    /** 内存 + 磁盘缓存键：同一 URL 不同目标宽分开缓存（避免小图糊大图）。 */
    private fun cacheKey(url: String, targetWidthPx: Int): String {
        val bucket = if (targetWidthPx <= 0) DEFAULT_MAX_BITMAP_PX else targetWidthPx
        return "$url@$bucket"
    }

    private fun fetch(
        context: Context,
        url: String,
        targetWidthPx: Int,
        gen: Long,
    ): Bitmap? {
        val bytes = readDisk(context, url) ?: download(url)?.also { data ->
            writeDisk(context, url, data)
        }
        if (bytes == null || gen != generation) return null
        return decodeSampled(bytes, targetWidthPx.coerceAtLeast(1))
    }

    private fun download(url: String): ByteArray? = try {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.connectTimeout = CONNECT_TIMEOUT_MS
            conn.readTimeout = READ_TIMEOUT_MS
            conn.instanceFollowRedirects = true
            if (conn.responseCode != HttpURLConnection.HTTP_OK) {
                null
            } else {
                conn.inputStream.use { it.readBytes() }
            }
        } finally {
            conn.disconnect()
        }
    } catch (_: Exception) {
        null
    }

    /**
     * 二次采样解码：按目标宽算 `inSampleSize`（保证解码宽 ≥ 目标宽），
     * 避免整图解码的内存与耗时。
     */
    internal fun decodeSampled(bytes: ByteArray, targetWidthPx: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val target = if (targetWidthPx <= 0) DEFAULT_MAX_BITMAP_PX else targetWidthPx
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= target) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
    }

    // ── 磁盘 LRU ──────────────────────────────────────────────────

    private fun dir(context: Context): File {
        diskDir?.let { return it }
        val d = File(context.cacheDir, "native_poster").apply { mkdirs() }
        diskDir = d
        return d
    }

    private fun fileFor(context: Context, url: String): File =
        File(dir(context), sha256(url) + ".img")

    private fun readDisk(context: Context, url: String): ByteArray? = try {
        val f = fileFor(context, url)
        if (f.exists() && f.length() > 0) {
            // 命中即刷新 mtime，作为 LRU 依据。
            f.setLastModified(System.currentTimeMillis())
            f.readBytes()
        } else {
            null
        }
    } catch (_: Exception) {
        null
    }

    private fun writeDisk(context: Context, url: String, bytes: ByteArray) {
        try {
            val f = fileFor(context, url)
            f.writeBytes(bytes)
            trimDisk(context)
        } catch (_: Exception) {
            // 磁盘写失败不影响本次显示（内存缓存仍生效）。
        }
    }

    /** 超出 64MB 时按 mtime 从旧到新删除，直到低于上限。 */
    private fun trimDisk(context: Context) {
        val files = dir(context).listFiles() ?: return
        var total = files.sumOf { it.length() }
        if (total <= DISK_CACHE_BYTES) return
        files.sortedBy { it.lastModified() }.forEach { f ->
            if (total <= DISK_CACHE_BYTES) return@forEach
            val len = f.length()
            if (f.delete()) total -= len
        }
    }

    private fun sha256(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray())
        val sb = StringBuilder(digest.size * 2)
        for (b in digest) sb.append(String.format("%02x", b))
        return sb.toString()
    }

    /** 可比较任务：优先级升序，同优先级按入队序号 FIFO。 */
    private class PriorityTask(
        private val priority: Int,
        private val order: Long,
        private val block: () -> Unit,
    ) : Runnable, Comparable<PriorityTask> {
        override fun run() = block()

        override fun compareTo(other: PriorityTask): Int {
            val c = priority.compareTo(other.priority)
            return if (c != 0) c else order.compareTo(other.order)
        }
    }
}
