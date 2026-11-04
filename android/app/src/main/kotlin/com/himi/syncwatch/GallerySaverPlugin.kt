package com.himi.syncwatch

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * 图片保存到系统相册（590）。
 *
 * 【为什么需要原生实现】旧 Dart 代码直写
 * `/storage/emulated/0/DCIM/Himi`，在 Android 10+（分区存储）直接抛
 * `PathAccessException: errno = 13`——真机「保存二维码失败」。
 *
 * 正确做法按 SDK 分档：
 * - **API 29+**：走 `MediaStore`，由系统在相册目录分配文件，
 *   `RELATIVE_PATH = DCIM/<subDir>` + `IS_PENDING` 两阶段提交。
 *   **不需要任何存储权限**。
 * - **API ≤28**：`MediaStore` 的 `RELATIVE_PATH` 不可用，退回直接写
 *   `DCIM/<subDir>`，此时才需要 `WRITE_EXTERNAL_STORAGE`
 *   （manifest 里限定 `maxSdkVersion=28`）。
 *
 * 统一在后台线程执行 IO，结果 post 回主线程返回（避免阻塞 UI）。
 */
class GallerySaverPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "himi/gallery_saver"
        private const val TAG = "GallerySaver"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveImage" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName") ?: "image"
                val subDir = call.argument<String>("subDir") ?: "Himi"
                if (bytes == null || bytes.isEmpty()) {
                    result.error("INVALID_ARG", "bytes 为空", null)
                    return
                }
                Thread {
                    val ok = try {
                        saveImage(bytes, fileName, subDir)
                    } catch (e: Exception) {
                        android.util.Log.w(TAG, "saveImage 失败", e)
                        false
                    }
                    mainHandler.post { result.success(ok) }
                }.start()
            }
            "supports" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    /** 保存 PNG 到相册；返回是否成功。 */
    private fun saveImage(bytes: ByteArray, fileName: String, subDir: String): Boolean {
        val name = if (fileName.endsWith(".png")) fileName else "$fileName.png"
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(bytes, name, subDir)
        } else {
            saveViaFile(bytes, name, subDir)
        }
    }

    /**
     * API 29+：MediaStore 两阶段写入。
     *
     * `IS_PENDING=1` 期间文件对其它应用不可见，写完再置 0——避免相册
     * 扫描到半张图。
     */
    private fun saveViaMediaStore(bytes: ByteArray, name: String, subDir: String): Boolean {
        val resolver = context.contentResolver
        val relativePath = "${Environment.DIRECTORY_DCIM}/$subDir"
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return false
        return try {
            resolver.openOutputStream(uri)?.use { out ->
                out.write(bytes)
                out.flush()
            } ?: return false
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } catch (e: Exception) {
            android.util.Log.w(TAG, "MediaStore 写入失败", e)
            // 失败要删掉半成品，否则相册里留一条坏记录。
            runCatching { resolver.delete(uri, null, null) }
            false
        }
    }

    /** API ≤28：直接写 DCIM（需要 WRITE_EXTERNAL_STORAGE，manifest 已限 maxSdk=28）。 */
    @Suppress("DEPRECATION")
    private fun saveViaFile(bytes: ByteArray, name: String, subDir: String): Boolean {
        val dcim = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM),
            subDir,
        )
        if (!dcim.exists() && !dcim.mkdirs()) return false
        val target = File(dcim, name)
        return try {
            FileOutputStream(target).use { out ->
                out.write(bytes)
                out.flush()
            }
            true
        } catch (e: Exception) {
            android.util.Log.w(TAG, "直写 DCIM 失败", e)
            false
        }
    }
}
