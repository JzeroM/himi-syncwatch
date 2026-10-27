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

    private fun currentContext(): android.content.Context? = appContext

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        currentSurface?.surfaceInfo()?.let { events?.success(it) }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
