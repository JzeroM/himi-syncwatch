package com.himi.syncwatch

import android.net.TrafficStats
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 整机累计收字节（播放页真实网速数据源）。
 *
 * `/proc/net/dev`、`/proc/self/net/dev` 在 Android 上均带 `proc_net`
 * SELinux 标签，untrusted_app 域无读权限（EACCES）→ 改走系统 API
 * `TrafficStats.getTotalRxBytes()`：无需权限、BPF/proc 由框架归一，
 * 返回整机自开机累计 RX 字节（与 /proc/net/dev 求和同口径）。
 *
 * `UNSUPPORTED(-1)` / 异常一律回传 null，上层按「本 tick 不可用」处理。
 */
class NetworkTrafficPlugin : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "himi/network_traffic"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "totalRxBytes" -> result.success(totalRxBytes())
            else -> result.notImplemented()
        }
    }

    private fun totalRxBytes(): Long? {
        return try {
            val bytes = TrafficStats.getTotalRxBytes()
            if (bytes < 0L) null else bytes
        } catch (_: Throwable) {
            null
        }
    }
}
