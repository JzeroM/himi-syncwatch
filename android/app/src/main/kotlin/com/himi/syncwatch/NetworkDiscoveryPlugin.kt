package com.himi.syncwatch

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 局域网发现组播锁（WifiManager.MulticastLock）。
 *
 * 背景：Android WiFi 省电时射频会过滤广播/组播包，导致手机端 UDP 广播发现
 * 收不到 TV 的「我在」包（表现为永远搜索不到设备）。持有组播锁可让 WiFi
 * 保持接收。需在 manifest 声明 CHANGE_WIFI_MULTICAST_STATE（普通权限）。
 *
 * 方法：
 * - acquireMulticastLock → 获取（幂等，重复调用不重复 acquire）
 * - releaseMulticastLock → 释放
 *
 * 失败一律返回 false，绝不抛异常——发现失败应降级为「未持锁」而非崩溃。
 */
class NetworkDiscoveryPlugin(private val context: Context?) :
    MethodChannel.MethodCallHandler {

    /** 无 Context 的构造：仅用于测试。 */
    constructor() : this(null)

    companion object {
        const val CHANNEL = "himi/network_discovery"
    }

    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquireMulticastLock" -> result.success(acquire())
            "releaseMulticastLock" -> result.success(release())
            else -> result.notImplemented()
        }
    }

    private fun acquire(): Boolean {
        val ctx = context ?: return false
        return try {
            if (multicastLock?.isHeld == true) return true
            val wifi = ctx.applicationContext
                .getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ?: return false
            val lock = wifi.createMulticastLock("himi_tv_discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
            multicastLock = lock
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun release(): Boolean {
        return try {
            multicastLock?.let { if (it.isHeld) it.release() }
            multicastLock = null
            true
        } catch (_: Throwable) {
            false
        }
    }
}
