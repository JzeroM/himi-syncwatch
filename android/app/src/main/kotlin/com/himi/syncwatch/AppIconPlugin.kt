package com.himi.syncwatch

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android 应用图标切换（activity-alias 组件启停）。
 *
 * 关键机制（对齐已验证的动态图标实现）：
 * - 首次从 `.DEFAULT` 切走：先启用目标别名，再显式禁用 `.DEFAULT`，并重启
 *   应用一次。禁用当前别名时系统可能直接杀进程，因此目标必须先启用。
 * - 后续切换：旧别名用 COMPONENT_ENABLED_STATE_DEFAULT 回到清单默认的
 *   禁用态，不触发杀进程；随后 Activity.recreate() 强制刷新组件状态，
 *   否则可能残留多个启用别名，桌面继续显示旧图标。
 * - 切回默认使用 `.icon_default` 克隆别名，避免重新启用 manifest 默认
 *   enabled 的 `.DEFAULT`。
 */
class AppIconPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "himi/app_icon"

        private const val TAG = "AppIconPlugin"
        private const val INITIAL_ALIAS = "com.himi.syncwatch.DEFAULT"
        private const val DEFAULT_CLONE_ALIAS = "com.himi.syncwatch.icon_default"

        /** id → 全限定 activity-alias（默认单独映射到克隆别名）。 */
        private val ALIASES = mapOf(
            "artistic" to "com.himi.syncwatch.icon_artistic",
            "mint" to "com.himi.syncwatch.icon_mint",
            "glass" to "com.himi.syncwatch.icon_glass",
        )

        private val ALL_ALIASES = listOf(
            INITIAL_ALIAS,
            DEFAULT_CLONE_ALIAS,
        ) + ALIASES.values
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "supports" -> result.success(true)
            "getIcon" -> result.success(currentIconId())
            "setIcon" -> {
                val id = call.argument<String?>("id") ?: "default"
                try {
                    val restart = applyIcon(id)
                    result.success(true)
                    // result 先回传，避免 recreate/restart 中断 Dart Future。
                    if (restart) {
                        postDelayed(150) { restartApp() }
                    } else {
                        postDelayed(150) { activity.recreate() }
                    }
                } catch (t: Throwable) {
                    Log.e(TAG, "setIcon($id) failed", t)
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

    /** @return true 表示首次激活，需要重启应用；false 表示仅 recreate。 */
    private fun applyIcon(id: String): Boolean {
        val target = if (id == "default") {
            DEFAULT_CLONE_ALIAS
        } else {
            ALIASES[id] ?: throw IllegalArgumentException("未知应用图标: $id")
        }
        val current = currentAliasName()
        Log.d(TAG, "setIcon id=$id current=$current target=$target")
        if (current == target) return false

        // 目标必须先启用：下一步禁用当前别名可能直接杀掉进程。
        setState(target, PackageManager.COMPONENT_ENABLED_STATE_ENABLED)

        // `.DEFAULT` 只在首次安装时启用；一旦切走永久禁用，由克隆别名承担默认。
        setState(INITIAL_ALIAS, PackageManager.COMPONENT_ENABLED_STATE_DISABLED)

        // 其余非目标别名回到清单默认禁用态（不会触发杀进程）。
        ALL_ALIASES.forEach { alias ->
            if (alias != target && alias != INITIAL_ALIAS) {
                setState(alias, PackageManager.COMPONENT_ENABLED_STATE_DEFAULT)
            }
        }

        // 当前状态不唯一（0 个或多个）时也走重启，强制 PackageManager 重新
        // 评估组件集合；普通切换只需 recreate 即可刷新桌面。
        return current == null || current == INITIAL_ALIAS
    }

    private fun currentIconId(): String {
        val current = currentAliasName() ?: return "invalid"
        if (current == INITIAL_ALIAS || current == DEFAULT_CLONE_ALIAS) {
            return "default"
        }
        return ALIASES.entries.firstOrNull { it.value == current }?.key
            ?: "invalid"
    }

    private fun currentAliasName(): String? {
        val enabled = ALL_ALIASES.filter { isEnabled(it) }
        return if (enabled.size == 1) enabled.first() else null
    }

    private fun setState(alias: String, state: Int) {
        activity.packageManager.setComponentEnabledSetting(
            ComponentName(activity.packageName, alias),
            state,
            PackageManager.DONT_KILL_APP,
        )
    }

    private fun isEnabled(alias: String): Boolean {
        val pm = activity.packageManager
        val component = ComponentName(activity.packageName, alias)
        return when (pm.getComponentEnabledSetting(component)) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            else -> manifestEnabled(alias)
        }
    }

    private fun manifestEnabled(alias: String): Boolean {
        val pm = activity.packageManager
        val flags =
            PackageManager.GET_ACTIVITIES or PackageManager.GET_DISABLED_COMPONENTS
        val info =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(
                    activity.packageName,
                    PackageManager.PackageInfoFlags.of(flags.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(activity.packageName, flags)
            }
        return info.activities?.firstOrNull { it.name == alias }?.enabled == true
    }

    private fun restartApp() {
        val pm = activity.packageManager
        val intent = pm.getLaunchIntentForPackage(activity.packageName) ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        activity.finish()
        activity.applicationContext.startActivity(intent)
    }

    private fun postDelayed(delayMs: Long, action: () -> Unit) {
        Handler(Looper.getMainLooper()).postDelayed(action, delayMs)
    }
}
