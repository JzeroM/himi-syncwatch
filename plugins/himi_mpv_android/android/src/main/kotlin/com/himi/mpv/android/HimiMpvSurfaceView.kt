package com.himi.mpv.android

import android.content.Context
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
 */
class HimiMpvSurfaceView(context: Context, private val viewId: Int) :
    SurfaceView(context), PlatformView, SurfaceHolder.Callback {

    private var surfaceHandle: Long = 0L
    private var width = 0
    private var height = 0

    init {
        holder.addCallback(this)
        // SurfaceView 在 Flutter hybrid composition 的 PlatformViewWrapper
        // 下方时会被窗口表面遮住。MediaOverlay 让它位于其它 SurfaceView
        // 之上，但仍低于 Flutter 控件窗口。
        setZOrderMediaOverlay(true)
        setBackgroundColor(android.graphics.Color.BLACK)
    }

    override fun getView(): View = this

    override fun dispose() {
        releaseSurface()
        holder.removeCallback(this)
        if (HimiMpvAndroidPlugin.currentSurface === this) {
            HimiMpvAndroidPlugin.currentSurface = null
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        attachSurface(holder.surface)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        this.width = width
        this.height = height
        emitSurface()
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        releaseSurface()
        HimiMpvAndroidPlugin.eventSink?.success(
            mapOf("type" to "surfaceDestroyed", "handle" to 0),
        )
    }

    private fun attachSurface(surface: android.view.Surface?) {
        if (surface == null || !surface.isValid) return
        releaseSurface()
        surfaceHandle = nativeCreateGlobalRef(surface)
        HimiMpvAndroidPlugin.currentSurface = this
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
        )
    }

    fun releaseSurface() {
        val ref = surfaceHandle
        surfaceHandle = 0L
        if (ref != 0L) {
            nativeDeleteGlobalRef(ref)
        }
    }

    private external fun nativeCreateGlobalRef(surface: android.view.Surface): Long
    private external fun nativeDeleteGlobalRef(ref: Long)

    companion object {
        init {
            System.loadLibrary("himi_mpv_android")
        }
    }
}
