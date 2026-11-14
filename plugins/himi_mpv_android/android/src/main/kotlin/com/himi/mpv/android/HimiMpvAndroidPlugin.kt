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
            "releaseSurface" -> {
                currentSurface?.releaseSurface()
                result.success(null)
            }
            "isVulkanAvailable" -> {
                result.success(isVulkanAvailable())
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
     * 697：检测 Vulkan 是否可用。
     *
     * 【为什么需要】libplacebo 的 DV 处理（`bt.2390` tone-mapping +
     * compute shader）需要 Vulkan。启用后 `gpu-api=vulkan` 让 libplacebo
     * 走 Vulkan 后端；不支持 Vulkan 的设备自动回退 OpenGL。
     *
     * 检测策略：
     * 1. API 24+ 保证 Vulkan 1.0（我们的 minSdk 26，所以恒真）
     * 2. dlopen `libvulkan.so` 验证 Vulkan loader 可加载
     *
     * 这比「只看 API 级别」可靠——个别设备虽有 Vulkan API 但 loader
     * 损坏或 GPU 驱动缺失。
     */
    private fun isVulkanAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        return try {
            System.loadLibrary("vulkan")
            true
        } catch (_: Throwable) {
            false
        }
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
