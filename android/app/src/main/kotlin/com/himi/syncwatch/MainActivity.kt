package com.himi.syncwatch

import com.himi.syncwatch.nativeplayer.AndroidNativePlayerChannel
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
    private var gallerySaverChannel: MethodChannel? = null
    private var nativePlayerChannel: AndroidNativePlayerChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // 697：插件注册兜底。
        //
        // Flutter 生成的 GeneratedPluginRegistrant 对每个插件只 catch
        // `Exception`，但 **`NoClassDefFoundError` 是 Error 而非 Exception**
        // ——一旦某个插件的静态初始化块抛错（例如 media_kit 的
        // `System.loadLibrary("mpv")` 因 RTLD_NOW 解析到未定义符号而失败），
        // 后续对该类的引用抛 NoClassDefFoundError，直接冒泡出
        // configureFlutterEngine → Flutter 首帧永远不出 → **白屏**。
        //
        // 这里用 Throwable 兜住：即使个别插件不可用，界面仍能正常启动，
        // 用户至少能看到错误提示而不是纯白屏。
        try {
            super.configureFlutterEngine(flutterEngine)
        } catch (t: Throwable) {
            android.util.Log.e(
                "MainActivity",
                "插件注册失败（界面继续启动）: ${t.javaClass.simpleName}: ${t.message}",
                t,
            )
        }
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
            // 应用图标切换：归一化 activity-alias，并 recreate/重启刷新桌面
            setMethodCallHandler(AppIconPlugin(this@MainActivity))
        }
        gallerySaverChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GallerySaverPlugin.CHANNEL
        ).apply {
            // 图片保存到相册：API 29+ 走 MediaStore（无需存储权限）
            setMethodCallHandler(GallerySaverPlugin(applicationContext))
        }
        // 原生播放器 UI（全屏 Dialog + SurfaceView，计划书 §6）
        nativePlayerChannel = AndroidNativePlayerChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )
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
        gallerySaverChannel?.setMethodCallHandler(null)
        gallerySaverChannel = null
        // 原生播放器：关闭 Dialog 并释放 surface，避免引擎重建后残留
        nativePlayerChannel?.dispose()
        nativePlayerChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
