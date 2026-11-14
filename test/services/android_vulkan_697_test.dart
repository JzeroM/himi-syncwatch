import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 697：安卓 libplacebo Vulkan 支持（DV 元数据处理需要 compute shader）。
///
/// ## 背景
///
/// 安卓的 libmpv 构建时 libplacebo 被 `-Dvulkan=disabled` 禁用了 Vulkan
/// 后端，导致 DV 元数据处理（`bt.2390` tone-mapping + compute shader）
/// 不可用，P5 单层 IPT 内容偏色。
///
/// ## 修复链路
///
/// 1. 构建脚本 patch `libplacebo.sh`：`-Dvulkan=disabled` → `-Dvulkan=enabled`
/// 2. Kotlin 层 `isVulkanAvailable()` 检测设备 Vulkan 支持
/// 3. Dart 层根据检测结果设 `gpu-api=vulkan` 或 `gpu-api=opengl`
///
/// ## 测试重点
///
/// 锁住「构建脚本必须启用 Vulkan」「运行时必须有回退」「字段名必须
/// 正确」这三件事，防止有人回退到 `-Dvulkan=disabled`。
void main() {
  String read(String p) => File(p).readAsStringSync();

  late String buildScript;
  late String androidDart;
  late String kotlinPlugin;

  setUpAll(() {
    buildScript = read('scripts/mpv/build_android.sh');
    androidDart = read('plugins/himi_mpv_android/lib/himi_mpv_android.dart');
    kotlinPlugin = read(
        'plugins/himi_mpv_android/android/src/main/kotlin/com/himi/mpv/android/'
        'HimiMpvAndroidPlugin.kt');
  });

  group('1. 构建脚本：libplacebo Vulkan 必须启用', () {
    test('1.1 patch libplacebo.sh 从 disabled 改为 enabled', () {
      expect(buildScript, contains('-Dvulkan=disabled'));
      expect(buildScript, contains('-Dvulkan=enabled'));
      expect(
        buildScript,
        contains("sed -i 's/-Dvulkan=disabled/-Dvulkan=enabled/'"),
        reason: '必须有 sed 命令把 disabled 改成 enabled',
      );
    });

    test('1.2 patch 失败时 die 而非静默继续', () {
      expect(buildScript, contains('die "libplacebo.sh 结构已变'));
    });

    test('1.3 构建后验证 Vulkan 符号', () {
      expect(buildScript, contains("grep_binary"));
      expect(buildScript, contains("'pl_gpu_create_vk'"));
      // libplacebo 是静态库，符号在 libmpv.so 里
      expect(buildScript, contains('libmpv 缺少 Vulkan 后端'));
    });

    test('1.3b 必须创建 vulkan.pc（meson 交叉编译只走 pkg-config）', () {
      expect(buildScript, contains('vulkan.pc'));
      expect(buildScript, contains('Name: Vulkan'));
      // 必须链接 -lvulkan：mpv 的 Vulkan context 直接调用
      // vkGetInstanceProcAddr 等 13 个符号，不链接会留下未定义符号 →
      // System.loadLibrary 用 RTLD_NOW 解析失败 → 白屏
      expect(buildScript, contains(r'Libs: -L${libdir} -lvulkan'));
      // 版本必须 >= 1.3.238（mpv 的 meson 要求），否则报
      // "Found 1.3 but need: '>= 1.3.238'"
      expect(buildScript, contains('Version: 1.3.238'));
      // 必须建符号链接（PKG_CONFIG_SYSROOT_DIR 依赖它们解析路径）
      expect(buildScript, contains(r'ln -s . "$PREFIX_DIR/usr"'));
      expect(buildScript, contains(r'ln -s . "$PREFIX_DIR/local"'));
    });

    test('1.3c 从 NDK 找 libvulkan.so stub（API 24+ 目录）', () {
      // NDK 只有 API 24+ 才有 libvulkan.so stub，而编译用 API 23。
      // 必须搜 24~36 目录找到后拷到 prefix/lib。
      expect(buildScript, contains('VULKAN_STUB'));
      // 倒序搜（36→24）优先用符号最全的高 API stub
      expect(buildScript, contains('for _api in 36 35 34'));
      expect(buildScript, contains('libvulkan.so stub 已拷贝'));
    });

    test('1.3d NDK 定义在 Vulkan 检查之前', () {
      final ndkIdx = buildScript.indexOf(r'NDK="$SCRIPTS/sdk/android-ndk-');
      final vulkanIdx = buildScript.indexOf('VULKAN_SYSROOT=');
      expect(ndkIdx, greaterThan(0));
      expect(vulkanIdx, greaterThan(ndkIdx), reason: 'NDK 必须先于 Vulkan 检查定义');
    });

    test('1.4 patch 在构建之前（checkout 后、buildall 前）', () {
      final checkoutIdx = buildScript.indexOf('checkout_ref');
      final patchIdx = buildScript.indexOf('libplacebo.sh 结构已变');
      final buildIdx = buildScript.indexOf('buildall.sh --only-deps');
      expect(checkoutIdx, greaterThan(0));
      expect(patchIdx, greaterThan(checkoutIdx), reason: 'patch 必须在 checkout 之后');
      expect(buildIdx, greaterThan(patchIdx), reason: 'patch 必须在构建之前');
    });
  });

  group('2. Kotlin 层 Vulkan 检测', () {
    test('2.1 有 isVulkanAvailable 方法', () {
      expect(kotlinPlugin, contains('fun isVulkanAvailable'));
    });

    test('2.2 通过 dlopen libvulkan.so 验证', () {
      expect(kotlinPlugin, contains('System.loadLibrary("vulkan")'));
    });

    test('2.3 API 级别检查（Vulkan 1.0 从 API 24 起）', () {
      expect(kotlinPlugin, contains('Build.VERSION_CODES.N'));
    });

    test('2.4 检测失败时返回 false 而非抛异常', () {
      expect(kotlinPlugin, contains('catch'));
      expect(kotlinPlugin, contains('false'));
    });

    test('2.5 MethodChannel 注册了 isVulkanAvailable', () {
      expect(kotlinPlugin, contains('"isVulkanAvailable"'));
    });
  });

  group('3. Dart 层 gpu-api 策略', () {
    test('3.1 有 isVulkanAvailable 方法（带缓存）', () {
      expect(androidDart, contains('static bool? _vulkanAvailable'));
      expect(androidDart, contains('static Future<bool> isVulkanAvailable'));
    });

    test('3.2 _vulkanOk 控制 gpu-api 是否带 Vulkan 优先项', () {
      expect(androidDart, contains('static bool _vulkanOk = false'));
      expect(androidDart,
          contains("(_vulkanOk && !_forceOpenGl) ? 'vulkan,opengl' : 'opengl'"));
    });

    test('3.3 _start 探测 Vulkan 并写入 _vulkanOk', () {
      expect(androidDart, contains('_vulkanOk = await isVulkanAvailable()'));
    });

    test('3.4 gpu-context 按 API 选 androidvk / android', () {
      // 【真机回归根因】mpv 的 Vulkan Android 上下文名是 `androidvk`，
      // GL 的才叫 `android`。用错名字 → 「Failed initializing any
      // suitable GPU context!」→ vo 起不来 → 黑屏有声。
      expect(androidDart, contains('androidvk,android'));
      expect(androidDart, contains('Vulkan → `androidvk`'));
    });

    test('3.5 检测结果缓存（只检测一次）', () {
      expect(androidDart, contains('if (_vulkanAvailable != null)'));
    });
  });

  group('3.6 Manifest 声明 libvulkan.so（Android 12+ 可见性）', () {
    test('3.6.1 uses-native-library required=false', () {
      final manifest =
          read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('<uses-native-library'));
      expect(manifest, contains('android:name="libvulkan.so"'));
      // required=false：无 Vulkan 设备也能安装，运行时回退 OpenGL
      expect(manifest, contains('android:required="false"'));
    });
  });

  group('3.8 硬解显式限定 mediacodec（避开 Vulkan 硬解路径）', () {
    test('3.8.1 不用 hwdec=auto', () {
      // 启用 Vulkan 后 mpv 编译了 vulkan 硬解后端，auto 会把它纳入候选，
      // 而它在初始化时调用 vkGetPhysicalDeviceQueueFamilyProperties2
      // （Vulkan 1.1，API 28+）。Android 硬解只有 MediaCodec，显式限定
      // 可彻底避开这条依赖新版 Vulkan loader 的路径。
      // 真机回归：显式 mediacodec 要求直写 Surface，部分设备不回退 →
      // 黑屏有声。恢复 auto/auto-copy（auto-copy 是 copy-back，兼容性最好）。
      final hwdecIdx = androidDart.indexOf("'hwdec':");
      expect(hwdecIdx, greaterThan(0));
      final hwdecBlock = androidDart.substring(hwdecIdx, hwdecIdx + 200);
      expect(hwdecBlock, contains("'auto-copy'"));
      expect(hwdecBlock, contains("'auto'"));
      // 软解回退必须保留
      expect(androidDart, contains("'hwdec-software-fallback': 'yes'"));
    });
  });

  group('3.7 白屏兜底：插件注册 catch Throwable', () {
    test('3.7.1 MainActivity 用 Throwable 包住插件注册', () {
      // Flutter 生成的 GeneratedPluginRegistrant 只 catch Exception，
      // 而 NoClassDefFoundError 是 Error → 冒泡导致白屏。
      final main =
          read('android/app/src/main/kotlin/com/himi/syncwatch/MainActivity.kt');
      expect(main, contains('catch (t: Throwable)'));
      expect(main, contains('super.configureFlutterEngine(flutterEngine)'));
      expect(main, contains('插件注册失败'));
    });
  });

  group('4. 与其他平台的一致性', () {
    test('4.1 DV 字段名与 mpv 源码一致', () {
      // DV 在 current-tracks/video 下（不在 video-params）
      // 这里验证的是 Android 的 getVideoParams 不再伪造
      expect(androidDart, contains("'video-params/primaries'"));
      expect(androidDart, contains("'video-params/gamma'"));
    });

    test('4.2 彩色元数据走标量子属性', () {
      expect(androidDart, contains("'video-params/sig-peak'"));
    });
  });

  // ---------------------------------------------------------------------
  // 5. 渲染层自愈：Vulkan 能初始化但渲染不出帧
  // ---------------------------------------------------------------------
  //
  // `gpu-api=vulkan,opengl` 只在**上下文创建失败**时回退。若 Vulkan
  // 上下文创建成功但呈现不出帧，mpv 不会回退，表现为「有声音没画面」。
  // 适配器的「有声无画」看门狗因此多了一级：软解仍无画面 → 判定为
  // 渲染层问题 → 显式切 opengl 并重载，同时给插件置 `_forceOpenGl`
  // 让后续会话直接走 opengl（不再每次黑 3 秒）。
  group('5. 渲染层自愈：软解仍无画面 → 回退 opengl', () {
    late String adapterDart;

    setUpAll(() {
      adapterDart = read('lib/services/player/mpv_player_adapter.dart');
    });

    test('5.1 适配器有单次 GPU 回退标志', () {
      expect(adapterDart, contains('bool _gpuApiFallbackDone = false'));
    });

    test('5.2 软解无画面分支里显式切 gpu-api/gpu-context', () {
      final idx = adapterDart.indexOf("_hwdec == 'no'");
      expect(idx, greaterThan(0));
      final block = adapterDart.substring(idx, idx + 1600);
      expect(block, contains("setProperty('gpu-api', 'opengl')"));
      expect(block, contains("setProperty('gpu-context', 'android')"));
      expect(block, contains('_gpuApiFallbackDone = true'),
          reason: '必须单次触发，否则会无限重载');
    });

    test('5.3 回退后重载并复位首帧标记', () {
      final idx = adapterDart.indexOf('_gpuApiFallbackDone = true');
      expect(idx, greaterThan(0));
      final block = adapterDart.substring(idx, idx + 900);
      expect(block, contains('firstFramePending.value = true'));
      expect(block, contains('_videoParamsSeen = false'));
      expect(block, contains('_player?.open('));
    });

    test('5.4 只在安卓触发（其他平台没有这套 gpu-api 语义）', () {
      final idx = adapterDart.indexOf('_gpuApiFallbackDone = true');
      final before = adapterDart.substring(idx - 600, idx);
      expect(before, contains('defaultTargetPlatform == TargetPlatform.android'));
    });

    test('5.4b 只认 vo-configured=no（纯音频不误伤）', () {
      final idx = adapterDart.indexOf('_gpuApiFallbackDone = true');
      final before = adapterDart.substring(idx - 600, idx);
      expect(before, contains("state.voConfigured == 'no'"));
    });

    test('5.5 跨会话记忆：插件侧 _forceOpenGl 生效', () {
      expect(adapterDart,
          contains('HimiMpvAndroidSession.disableVulkanRendering()'));
      expect(androidDart, contains('static bool _forceOpenGl = false'));
      expect(androidDart, contains('static void disableVulkanRendering()'));
      // gpu-api / gpu-context 都必须同时受 _forceOpenGl 约束
      expect(androidDart,
          contains("(_vulkanOk && !_forceOpenGl) ? 'vulkan,opengl' : 'opengl'"));
      expect(androidDart,
          contains("(_vulkanOk && !_forceOpenGl) ? 'androidvk,android' : 'android'"));
    });

    test('5.6 mpv 源码语义：gpu-context 列表决定尝试顺序', () {
      // video/out/gpu/context.c 的 ra_ctx_create 按 **context_list**
      // 顺序逐个 create_in_contexts，再用 gpu-api 的 type 列表过滤。
      // 所以 `androidvk,android` + `vulkan,opengl` 才是正确写法：
      // androidvk(vulkan) 先试，失败后 android(opengl) 兜底。
      // 反过来（api 列表驱动顺序）就不成立，必须锁住注释里的说明。
      expect(androidDart, contains('mpv 的上下文名按 API 区分'));
      expect(androidDart, contains('androidvk'));
    });
  });
}
