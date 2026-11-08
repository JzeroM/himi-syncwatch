package com.himi.mpv.android

import android.hardware.display.DisplayManager
import android.os.Build
import android.view.Display
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec

/**
 * Android surface host for HIMI MPV.
 *
 * libmpv itself is driven from Dart through media_kit; this plugin only owns
 * the SurfaceView and hands a Java Surface global reference to Dart. Keeping
 * the MPV control interface in Dart lets Android share the exact same session
 * contract as HarmonyOS and Windows.
 */
class HimiMpvAndroidPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val METHOD_CHANNEL = "himi_mpv_android"
        const val SURFACE_CHANNEL = "himi_mpv_android/surface"
        const val VIEW_TYPE = "himi_mpv_android_surface"

        @Volatile
        var eventSink: EventChannel.EventSink? = null

        @Volatile
        var currentSurface: HimiMpvSurfaceView? = null
    }

    private var appContext: android.content.Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, SURFACE_CHANNEL)
        eventChannel?.setStreamHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE,
            HimiMpvSurfaceFactory(StandardMessageCodec.INSTANCE),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        currentSurface?.releaseSurface()
        currentSurface = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCurrentSurface" -> {
                val view = currentSurface
                result.success(view?.surfaceInfo())
            }
            "queryHdrCapabilities" -> {
                result.success(queryHdrCapabilities())
            }
            // 639：查询 OpenGL ES 版本——`vo=gpu-next` 要求 ES 3.1+，
            // 老 GPU（Mali-450 等只有 3.0）用它必然黑屏，需降级 `vo=gpu`。
            "queryGlEsVersion" -> {
                result.success(queryGlEsVersion())
            }
            "releaseSurface" -> {
                currentSurface?.releaseSurface()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun queryHdrCapabilities(): Map<String, Any> {
        val formats = mutableListOf<String>()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            return mapOf("formats" to formats)
        }
        try {
            val dm = currentContext()?.getSystemService(android.content.Context.DISPLAY_SERVICE) as? DisplayManager
            val display = dm?.getDisplay(Display.DEFAULT_DISPLAY)
            val types = display?.hdrCapabilities?.supportedHdrTypes ?: intArrayOf()
            if (types.contains(Display.HdrCapabilities.HDR_TYPE_HDR10)) formats.add("hdr10")
            if (types.contains(Display.HdrCapabilities.HDR_TYPE_HLG)) formats.add("hlg")
            if (types.contains(Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION)) formats.add("dolbyVision")
        } catch (_: Throwable) {
        }
        return mapOf("formats" to formats)
    }

    /**
     * 639：通过 EGL 查询当前设备的 OpenGL ES 版本。
     *
     * 为什么需要：Android 的 surface 路径用 `vo=gpu-next`，而 mpv 官方手册
     * 明确它需要 OpenGL ES 3.1+；老 GPU（如 Mali-450 MP，仅 ES 3.0）用它
     * 会渲染初始化失败 → 黑屏（真机：H96 Max RK3528 / Android 13）。
     *
     * 实现要点：创建一个**无 surface** 的 EGL 上下文（pbuffer 都不需要），
     * 读 `GL_VERSION` 后立即销毁，不影响后续 mpv 自己的 EGL 初始化。
     * 全程 try-catch：任何失败都返回 0.0，调用方据此保持乐观默认。
     */
    private fun queryGlEsVersion(): Map<String, Any> {
        val out = mutableMapOf<String, Any>("major" to 0, "minor" to 0, "renderer" to "")
        var display = android.opengl.EGL14.EGL_NO_DISPLAY
        var context = android.opengl.EGL14.EGL_NO_CONTEXT
        var surface = android.opengl.EGL14.EGL_NO_SURFACE
        try {
            display = android.opengl.EGL14.eglGetDisplay(android.opengl.EGL14.EGL_DEFAULT_DISPLAY)
            if (display == android.opengl.EGL14.EGL_NO_DISPLAY) return out
            val version = IntArray(2)
            if (!android.opengl.EGL14.eglInitialize(display, version, 0, version, 1)) return out

            // 尝试 ES 3.x；若失败再退 ES 2.0（老设备）。
            for (clientVersion in intArrayOf(3, 2)) {
                val configAttribs = intArrayOf(
                    android.opengl.EGL14.EGL_RENDERABLE_TYPE,
                    if (clientVersion >= 3) 0x40 /* EGL_OPENGL_ES3_BIT_KHR */
                    else android.opengl.EGL14.EGL_OPENGL_ES2_BIT,
                    android.opengl.EGL14.EGL_NONE
                )
                val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
                val numConfigs = IntArray(1)
                if (!android.opengl.EGL14.eglChooseConfig(
                        display, configAttribs, 0, configs, 0, 1, numConfigs, 0
                    ) || numConfigs[0] <= 0 || configs[0] == null
                ) {
                    continue
                }
                val ctxAttribs = intArrayOf(
                    android.opengl.EGL14.EGL_CONTEXT_CLIENT_VERSION, clientVersion,
                    android.opengl.EGL14.EGL_NONE
                )
                context = android.opengl.EGL14.eglCreateContext(
                    display, configs[0], android.opengl.EGL14.EGL_NO_CONTEXT, ctxAttribs, 0
                )
                if (context == android.opengl.EGL14.EGL_NO_CONTEXT) continue

                // 用 1x1 pbuffer 让上下文可 current（部分驱动要求有 draw surface）。
                val pbAttribs = intArrayOf(
                    android.opengl.EGL14.EGL_WIDTH, 1,
                    android.opengl.EGL14.EGL_HEIGHT, 1,
                    android.opengl.EGL14.EGL_NONE
                )
                surface = android.opengl.EGL14.eglCreatePbufferSurface(
                    display, configs[0], pbAttribs, 0
                )
                if (surface == android.opengl.EGL14.EGL_NO_SURFACE) {
                    android.opengl.EGL14.eglDestroyContext(display, context)
                    context = android.opengl.EGL14.EGL_NO_CONTEXT
                    continue
                }
                if (!android.opengl.EGL14.eglMakeCurrent(display, surface, surface, context)) {
                    android.opengl.EGL14.eglDestroySurface(display, surface)
                    surface = android.opengl.EGL14.EGL_NO_SURFACE
                    android.opengl.EGL14.eglDestroyContext(display, context)
                    context = android.opengl.EGL14.EGL_NO_CONTEXT
                    continue
                }

                val glVersion = android.opengl.GLES20.glGetString(android.opengl.GLES20.GL_VERSION) ?: ""
                val renderer = android.opengl.GLES20.glGetString(android.opengl.GLES20.GL_RENDERER) ?: ""
                // 形如 "OpenGL ES 3.0 v1.r0p0-01rel0" / "OpenGL ES 3.2 v1.r32..."
                val match = Regex("OpenGL ES (\\d+)\\.(\\d+)").find(glVersion)
                if (match != null) {
                    out["major"] = match.groupValues[1].toIntOrNull() ?: 0
                    out["minor"] = match.groupValues[2].toIntOrNull() ?: 0
                }
                out["renderer"] = renderer
                break
            }
        } catch (_: Throwable) {
            // 忽略：查询失败时返回 0.0，调用方保持乐观默认（gpu-next）。
        } finally {
            try {
                if (display != android.opengl.EGL14.EGL_NO_DISPLAY) {
                    android.opengl.EGL14.eglMakeCurrent(
                        display,
                        android.opengl.EGL14.EGL_NO_SURFACE,
                        android.opengl.EGL14.EGL_NO_SURFACE,
                        android.opengl.EGL14.EGL_NO_CONTEXT
                    )
                    if (surface != android.opengl.EGL14.EGL_NO_SURFACE) {
                        android.opengl.EGL14.eglDestroySurface(display, surface)
                    }
                    if (context != android.opengl.EGL14.EGL_NO_CONTEXT) {
                        android.opengl.EGL14.eglDestroyContext(display, context)
                    }
                    android.opengl.EGL14.eglTerminate(display)
                }
            } catch (_: Throwable) {
            }
        }
        return out
    }

    private fun currentContext(): android.content.Context? = appContext

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        currentSurface?.surfaceInfo()?.let { events?.success(it) }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
