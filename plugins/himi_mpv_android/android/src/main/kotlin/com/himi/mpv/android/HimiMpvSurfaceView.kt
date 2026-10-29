package com.himi.mpv.android

import android.content.Context
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.platform.PlatformView

/**
 * SurfaceView owned by HIMI MPV direct output.
 *
 * The Java Surface is converted to a JNI global reference, which is what
 * libmpv's Android `wid` option expects. HDR metadata/format is configured by
 * libmpv on the ANativeWindow created from this Surface.
 *
 * 【为什么每个事件都带 src + handle】
 * App 同时存在两个实例：Flutter 平台视图（src=platform）与原生播放器
 * Dialog 的顶层 surface（src=native），两者共用同一个 EventChannel。
 * Dart 侧（SurfaceRebindPolicy）靠 src 过滤过期事件、靠 handle 仲裁销毁；
 * 缺任何一个都会出现「重绑回垂死 surface → 硬解失败 → 黑屏」。
 */
class HimiMpvSurfaceView(
    context: Context,
    private val viewId: Int,
    /**
     * true（默认）：Flutter hybrid composition 下需 `setZOrderMediaOverlay`
     * 才能压在 PlatformViewWrapper 之上。
     * false：作为全屏 Dialog 的顶层内容（Android 原生播放器 UI）时，
     * media overlay 会让 Flutter 窗口表面盖住本 SurfaceView。
     */
    private val useMediaOverlay: Boolean = true,
    /**
     * 事件来源标识：`platform` = Flutter 平台视图；`native` = 原生播放器
     * UI 的 SurfaceView。Dart 只接受当前激活来源的事件。
     */
    private val source: String = "platform",
) : SurfaceView(context), PlatformView, SurfaceHolder.Callback {

    private var surfaceHandle: Long = 0L
    private var width = 0
    private var height = 0

    init {
        holder.addCallback(this)
        // SurfaceView 在 Flutter hybrid composition 的 PlatformViewWrapper
        // 下方时会被窗口表面遮住。MediaOverlay 让它位于其它 SurfaceView
        // 之上，但仍低于 Flutter 控件窗口。
        if (useMediaOverlay) setZOrderMediaOverlay(true)
        setBackgroundColor(android.graphics.Color.BLACK)
    }

    override fun getView(): View = this

    override fun dispose() {
        // Flutter 卸载平台视图走这里：必须在释放 handle **之前**把销毁
        // 事件发出去（surfaceDestroyed 回调随后不会再触发——callback
        // 已移除），否则 Dart 永远不知道 surface 死了，mpv 搁浅在死
        // surface 上 → 黑屏。
        val destroyedHandle = surfaceHandle
        Log.i(TAG, "dispose[$source#$viewId] handle=$destroyedHandle")
        if (destroyedHandle != 0L) {
            emitDestroyed(destroyedHandle)
        }
        releaseSurface()
        holder.removeCallback(this)
        if (HimiMpvAndroidPlugin.currentSurface === this) {
            HimiMpvAndroidPlugin.currentSurface = null
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        Log.i(TAG, "surfaceCreated[$source#$viewId] valid=${holder.surface?.isValid}")
        attachSurface(holder.surface)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        this.width = width
        this.height = height
        Log.d(TAG, "surfaceChanged[$source#$viewId] handle=$surfaceHandle ${width}x$height")
        emitSurface()
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        // 带上被销毁的 handle：原生 UI（Dialog）与 Flutter 平台视图各有
        // 自己的 SurfaceView，Dart 侧要靠它判断销毁的是不是当前绑定的
        // surface（发 0 会让 Dart 误拆掉新 surface 上的播放器 → 黑屏）。
        val destroyedHandle = surfaceHandle
        Log.i(TAG, "surfaceDestroyed[$source#$viewId] handle=$destroyedHandle")
        releaseSurface()
        if (HimiMpvAndroidPlugin.currentSurface === this) {
            HimiMpvAndroidPlugin.currentSurface = null
        }
        if (destroyedHandle != 0L) {
            emitDestroyed(destroyedHandle)
        }
    }

    private fun emitDestroyed(handle: Long) {
        HimiMpvAndroidPlugin.eventSink?.success(
            mapOf(
                "type" to "surfaceDestroyed",
                "handle" to handle,
                "src" to source,
            ),
        )
    }

    private fun attachSurface(surface: android.view.Surface?) {
        if (surface == null || !surface.isValid) {
            // 静默失败曾让 Dart 永远等不到事件（黑屏盲区之一）：必须留痕。
            Log.w(TAG, "attachSurface[$source#$viewId] 跳过：surface=${surface != null} valid=${surface?.isValid}")
            return
        }
        releaseSurface()
        surfaceHandle = nativeCreateGlobalRef(surface)
        HimiMpvAndroidPlugin.currentSurface = this
        Log.i(TAG, "attachSurface[$source#$viewId] -> handle=$surfaceHandle")
        emitSurface()
    }

    private fun emitSurface() {
        if (surfaceHandle == 0L) return
        HimiMpvAndroidPlugin.eventSink?.success(surfaceInfo())
    }

    fun surfaceInfo(): Map<String, Any>? {
        if (surfaceHandle == 0L) return null
        return mapOf(
            "type" to "surface",
            "handle" to surfaceHandle,
            "width" to width,
            "height" to height,
            "src" to source,
        )
    }

    fun releaseSurface() {
        val ref = surfaceHandle
        surfaceHandle = 0L
        if (ref != 0L) {
            nativeDeleteGlobalRef(ref)
            Log.i(TAG, "releaseSurface[$source#$viewId] handle=$ref")
        }
    }

    private external fun nativeCreateGlobalRef(surface: android.view.Surface): Long
    private external fun nativeDeleteGlobalRef(ref: Long)

    companion object {
        private const val TAG = "HimiMpvSurface"

        init {
            System.loadLibrary("himi_mpv_android")
        }
    }
}
