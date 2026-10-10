package com.himi.syncwatch

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Point
import android.hardware.display.DisplayManager
import android.os.Build
import android.view.Display
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 平台设备信息探测：TV 设备识别（Android TV / 盒子）。
 *
 * 判定顺序：
 * 1. Configuration#uiMode 的设备类型段 == UI_MODE_TYPE_TELEVISION
 *    （系统声明的电视模式，最直接；UiModeManager#getUiModeType 是
 *    隐藏 API 不可用，故读公开字段）；
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
            "displaySize" -> result.success(displaySize())
            else -> result.notImplemented()
        }
    }

    /**
     * 显示器的「真实输出分辨率」（物理像素）。
     *
     * 用于渲染尺寸夹紧：TV/盒子的 Flutter 视图常只有 1080p（UI 层），
     * 但输出模式可能是 4K；用 Display 的真实尺寸做夹紧目标，才能保住
     * 4K 全分辨率扫描输出，而不是误降到 1080p。
     *
     * 优先 `getMode().getPhysicalWidth/Height`（API 23+，返回面板物理
     * 分辨率，不受 UI 缩放影响）；回退 `getRealSize`（已废弃，兼容旧
     * 设备）。异常/无 Context → null（上层按自身显示尺寸兜底）。
     */
    private fun displaySize(): Map<String, Int>? {
        val ctx = context ?: return null
        return try {
            val dm = ctx.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
                ?: return null
            val display: Display = dm.getDisplay(Display.DEFAULT_DISPLAY) ?: return null

            // 优先 getMode().getPhysicalWidth/Height（API 23+）
            // 返回面板物理分辨率，不受 UI 缩放影响
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val mode = display.mode
                val w = mode.physicalWidth
                val h = mode.physicalHeight
                if (w > 0 && h > 0) {
                    return mapOf(
                        "width" to w,
                        "height" to h,
                        "refreshRate" to mode.refreshRate.toInt(),
                    )
                }
            }

            // 回退：getRealSize（已废弃，兼容旧设备）
            val point = Point()
            @Suppress("DEPRECATION")
            display.getRealSize(point)
            if (point.x > 0 && point.y > 0) {
                mapOf("width" to point.x, "height" to point.y)
            } else null
        } catch (_: Throwable) {
            null
        }
    }

    private fun isTelevision(): Boolean {
        val ctx = context ?: return false
        return try {
            // UiModeManager#getUiModeType 是隐藏 API，改读公开的
            // Configuration#uiMode（UI_MODE_TYPE_MASK 段即设备类型）
            val uiMode = ctx.resources.configuration.uiMode
            if ((uiMode and Configuration.UI_MODE_TYPE_MASK) ==
                Configuration.UI_MODE_TYPE_TELEVISION
            ) {
                return true
            }
            ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        } catch (_: Throwable) {
            false
        }
    }
}
