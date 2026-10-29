package com.himi.syncwatch.nativeplayer

import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `himi_native_player` 通道（计划书 §6.1）：
 * - MethodChannel：`open` / `close` / `pushNativeState`；
 * - EventChannel：`himi_native_player/commands`，视图交互回传 Dart，
 *   结构与 `NativePlayerCommand.fromMap` 一一对应。
 *
 * 生命周期由宿主 Activity 持有：`configureFlutterEngine` 创建，
 * `cleanUpFlutterEngine` 调 [dispose]（必须释放 Dialog 与其 surface）。
 */
class AndroidNativePlayerChannel(
    messenger: BinaryMessenger,
    activity: Activity,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "himi_native_player"
        const val COMMAND_CHANNEL = "himi_native_player/commands"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val commandChannel = EventChannel(messenger, COMMAND_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null

    /** 视图交互 → EventChannel → Dart。 */
    private val host = AndroidNativePlayerHost(activity) { command ->
        eventSink?.success(command)
    }

    init {
        methodChannel.setMethodCallHandler(this)
        commandChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> {
                host.open()
                result.success(null)
            }

            "close" -> {
                host.close()
                result.success(null)
            }

            "pushNativeState" -> {
                val json = call.argument<String>("state")
                when {
                    json == null -> result.error("BAD_ARGS", "missing state", null)
                    host.pushState(json) -> result.success(null)
                    else -> result.error("BAD_STATE", "state json parse failed", null)
                }
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /** 解绑：注销通道并释放 Dialog（内含 surface JNI 引用）。 */
    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        commandChannel.setStreamHandler(null)
        eventSink = null
        host.release()
    }
}
