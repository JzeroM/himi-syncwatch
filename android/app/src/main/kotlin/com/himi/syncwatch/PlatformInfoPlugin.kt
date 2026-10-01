package com.himi.syncwatch

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 平台设备信息探测：TV 设备识别（Android TV / 盒子）。
 *
 * 判定顺序：
 * 1. UiModeManager#uiModeType == UI_MODE_TYPE_TELEVISION（系统声明的
 *    电视模式，最直接）；
 * 2. PackageManager.FEATURE_LEANBACK（电视特性，无遥控器的盒子也常带）。
 *
 * 检测失败一律返回 false——上层按「非 TV」处理，绝不静默误开 TV 模式
 * （策略 A：只有明确检测为 TV 才自动开启）。
 */
class PlatformInfoPlugin(private val context: Context?) :
    MethodChannel.MethodCallHandler {

    /** 无 Context 的构造：仅用于测试。 */
    constructor() : this(null)

    companion object {
        const val CHANNEL = "himi/platform"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isTelevision" -> result.success(isTelevision())
            else -> result.notImplemented()
        }
    }

    private fun isTelevision(): Boolean {
        val ctx = context ?: return false
        return try {
            val uiMode = ctx.getSystemService(Context.UI_MODE_SERVICE)
                as? UiModeManager
            if (uiMode?.uiModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
                return true
            }
            ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        } catch (_: Throwable) {
            false
        }
    }
}
