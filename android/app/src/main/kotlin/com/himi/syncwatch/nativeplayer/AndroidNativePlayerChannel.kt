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

    /**
     * Dart 订阅前的命令队列。
     *
     * 原生控件窗可能在 Dart 侧 `commandStream` 订阅**之前**就建好并产生
     * 点击事件；`eventSink?.success(...)` 在 sink 为空时静默丢弃 → 真机
     * 表现为「点了没反应」。这里缓存，onListen 时按序补发。
     */
    private val pendingCommands = mutableListOf<Map<String, Any?>>()

    /** 视图交互 → EventChannel → Dart。 */
    private val host = AndroidNativePlayerHost(activity) { command ->
        val sink = eventSink
        if (sink == null) {
            synchronized(pendingCommands) { pendingCommands.add(command) }
        } else {
            sink.success(command)
        }
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
        // 补发订阅前积压的命令（按序）。
        val queued = synchronized(pendingCommands) {
            val copy = pendingCommands.toList()
            pendingCommands.clear()
            copy
        }
        queued.forEach { events?.success(it) }
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
