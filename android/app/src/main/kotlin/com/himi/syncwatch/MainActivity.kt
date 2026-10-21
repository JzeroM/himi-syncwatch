package com.himi.syncwatch

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /**
     * 必须持有引用以便 cleanUp 时解绑；为 null 表示尚未绑定。
     *
     * 注意：不能在字段初始化器里创建 channel。
     * FlutterActivity.flutterEngine 在 `onCreate` → `configureFlutterEngine`
     * 之前为 null，此处用 `!!` 拿到的 messenger 与随后真正驱动 Dart 的
     * engine 不是同一个，handler 实际从未注册上，Dart 侧只会收到
     * MissingPluginException（表现为 DV 能力探测静默失败、被误判为不支持
     * 而强制软件解码）。
     */
    private var dvChannel: MethodChannel? = null
    private var piChannel: MethodChannel? = null
    private var ntChannel: MethodChannel? = null
    private var ndChannel: MethodChannel? = null
    private var dcChannel: MethodChannel? = null
    private var aiChannel: MethodChannel? = null
    private var appIconChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dvChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DolbyVisionPlugin.CHANNEL
        ).apply {
            // applicationContext 供 getAppVersion 读 PackageManager
            setMethodCallHandler(DolbyVisionPlugin(applicationContext))
        }
        piChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PlatformInfoPlugin.CHANNEL
        ).apply {
            // TV 设备识别（自动开启 TV 模式的判定来源）
            setMethodCallHandler(PlatformInfoPlugin(applicationContext))
        }
        ntChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NetworkTrafficPlugin.CHANNEL
        ).apply {
            // 真实网速：TrafficStats 整机累计收字节（/proc 受 SELinux 限制）
            setMethodCallHandler(NetworkTrafficPlugin())
        }
        ndChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NetworkDiscoveryPlugin.CHANNEL
        ).apply {
            // 局域网发现组播锁（WiFi 省电时保持接收广播/组播）
            setMethodCallHandler(NetworkDiscoveryPlugin(applicationContext))
        }
        dcChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DeviceCapabilityPlugin.CHANNEL
        ).apply {
            // 启动设备能力评估（显示 HDR / GL-EGL / Vulkan / HEVC HDR10）
            setMethodCallHandler(DeviceCapabilityPlugin(applicationContext))
        }
        aiChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ApkInstallerPlugin.CHANNEL
        ).apply {
            // 应用内更新：安装未知来源授权 + 调起 APK 安装器
            setMethodCallHandler(ApkInstallerPlugin(applicationContext))
        }
        appIconChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AppIconPlugin.CHANNEL
        ).apply {
            // 应用图标切换：归一化 activity-alias，避免旧别名残留
            setMethodCallHandler(AppIconPlugin(applicationContext))
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        dvChannel?.setMethodCallHandler(null)
        dvChannel = null
        piChannel?.setMethodCallHandler(null)
        piChannel = null
        ntChannel?.setMethodCallHandler(null)
        ntChannel = null
        ndChannel?.setMethodCallHandler(null)
        ndChannel = null
        dcChannel?.setMethodCallHandler(null)
        dcChannel = null
        aiChannel?.setMethodCallHandler(null)
        aiChannel = null
        appIconChannel?.setMethodCallHandler(null)
        appIconChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
