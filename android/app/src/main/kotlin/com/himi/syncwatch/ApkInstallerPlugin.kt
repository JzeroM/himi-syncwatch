package com.himi.syncwatch

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用内更新安装（Android）：
 *
 * - `canInstall`：`PackageManager.canRequestPackageInstalls()`（API 26+，
 *   应用内安装 APK 的前提；未授权时上层引导去系统设置页）；
 * - `openInstallSettings`：跳「安装未知应用」授权页（带 package 参数直达本应用）；
 * - `install`：用 FileProvider 生成 content:// 后 ACTION_VIEW 调起系统安装器
 *   （Android 7.0+ 禁止 file:// 直传，必须走 FileProvider；APK 位于
 *   应用缓存目录 updates/ 下，见 res/xml/apk_installer_paths.xml）。
 *
 * 所有失败一律返回 false（不抛异常），上层按「拉起失败」提示重试。
 */
class ApkInstallerPlugin(private val context: Context?) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "himi/apk_installer"

        /** FileProvider authority（AndroidManifest.xml 中 ${applicationId}.apk_installer）。 */
        private const val AUTHORITY_SUFFIX = ".apk_installer"

        private const val APK_MIME = "application/vnd.android.package-archive"
    }

    /** 无 Context 的构造：仅用于测试。 */
    constructor() : this(null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context
        if (ctx == null) {
            result.success(false)
            return
        }
        when (call.method) {
            "canInstall" -> result.success(canInstall(ctx))
            "openInstallSettings" -> result.success(openInstallSettings(ctx))
            "install" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.success(false)
                } else {
                    result.success(install(ctx, path))
                }
            }
            else -> result.notImplemented()
        }
    }

    /** 是否已允许安装未知来源应用（minSdk=26，无需版本分支）。 */
    private fun canInstall(ctx: Context): Boolean {
        return try {
            ctx.packageManager.canRequestPackageInstalls()
        } catch (_: Throwable) {
            false
        }
    }

    /** 打开本应用的「安装未知应用」授权页。 */
    private fun openInstallSettings(ctx: Context): Boolean {
        return try {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${ctx.packageName}")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** 调起系统安装器（用户仍可取消安装）。 */
    private fun install(ctx: Context, path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = FileProvider.getUriForFile(
                ctx,
                ctx.packageName + AUTHORITY_SUFFIX,
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }
}
