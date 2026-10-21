package com.himi.syncwatch

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android 应用图标切换（activity-alias 组件启停）。
 *
 * 不使用 flutter_dynamic_icon_plus 的 Android 分支：它只禁用「检测到的
 * 一个」旧别名，历史脏状态下可能同时启用 DEFAULT 与备用别名，桌面会
 * 一直显示旧图标。这里每次切换都启用目标并禁用其余全部别名，保证最终
 * 状态唯一；切换后回查，异常直接返回给 Dart 层。
 */
class AppIconPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "himi/app_icon"

        /** id → 全限定 activity-alias。 */
        private val ALIASES = mapOf(
            "default" to "com.himi.syncwatch.DEFAULT",
            "artistic" to "com.himi.syncwatch.icon_artistic",
            "mint" to "com.himi.syncwatch.icon_mint",
            "glass" to "com.himi.syncwatch.icon_glass",
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "supports" -> result.success(true)
            "getIcon" -> result.success(currentIcon())
            "setIcon" -> {
                val id = call.argument<String?>("id") ?: "default"
                try {
                    applyIcon(id)
                    val current = currentIcon()
                    if (current != id) {
                        result.error(
                            "ICON_NOT_APPLIED",
                            "期望图标 $id，实际生效 $current",
                            null,
                        )
                    } else {
                        result.success(true)
                    }
                } catch (t: Throwable) {
                    result.error(
                        "ICON_SWITCH_FAILED",
                        t.message ?: t.javaClass.simpleName,
                        null,
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun applyIcon(id: String) {
        val target = ALIASES[id]
            ?: throw IllegalArgumentException("未知应用图标: $id")
        setEnabled(target, true)
        ALIASES.values.forEach { alias ->
            if (alias != target) setEnabled(alias, false)
        }
    }

    private fun setEnabled(alias: String, enabled: Boolean) {
        context.packageManager.setComponentEnabledSetting(
            ComponentName(context.packageName, alias),
            if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            },
            PackageManager.DONT_KILL_APP,
        )
    }

    /** 唯一启用的图标 id；0 个或多个启用时返回 null，交由启动自愈归一化。 */
    private fun currentIcon(): String? {
        val enabled = ALIASES.filterValues { isEnabled(it) }.keys
        return if (enabled.size == 1) enabled.first() else null
    }

    private fun isEnabled(alias: String): Boolean {
        val pm = context.packageManager
        val component = ComponentName(context.packageName, alias)
        return when (pm.getComponentEnabledSetting(component)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            else -> manifestEnabled(alias)
        }
    }

    private fun manifestEnabled(alias: String): Boolean {
        val pm = context.packageManager
        val flags =
            PackageManager.GET_ACTIVITIES or PackageManager.GET_DISABLED_COMPONENTS
        val info =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(
                    context.packageName,
                    PackageManager.PackageInfoFlags.of(flags.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(context.packageName, flags)
            }
        return info.activities?.firstOrNull { it.name == alias }?.enabled == true
    }
}
