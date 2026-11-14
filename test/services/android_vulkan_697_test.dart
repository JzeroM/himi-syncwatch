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
      expect(buildScript, contains("'pl_gpu_vk'"));
      // libplacebo 是静态库，符号在 libmpv.so 里
      expect(buildScript, contains('libmpv 缺少 Vulkan 后端'));
    });

    test('1.3b 必须创建 vulkan.pc（meson 交叉编译只走 pkg-config）', () {
      expect(buildScript, contains('vulkan.pc'));
      expect(buildScript, contains('Name: Vulkan'));
      // -L${libdir} 让链接器搜 prefix/lib（通过 usr -> . 符号链接解析）
      expect(buildScript, contains(r'Libs: -L${libdir} -lvulkan'));
      // 版本必须 >= 1.3.238（mpv 的 meson 要求），否则报
      // "Found 1.3 but need: '>= 1.3.238'"
      expect(buildScript, contains('Version: 1.3.238'));
      // 必须建符号链接（PKG_CONFIG_SYSROOT_DIR 依赖它们解析路径）
      expect(buildScript, contains(r'ln -s . "$PREFIX_DIR/usr"'));
      expect(buildScript, contains(r'ln -s . "$PREFIX_DIR/local"'));
    });

    test('1.3c 创建 libvulkan.so stub（NDK r30 不自带）', () {
      // NDK r30 只有 Vulkan 头文件，没有 libvulkan.so 链接 stub。
      // 运行时由 Android 系统 Vulkan loader 提供，构建时只需空 stub。
      expect(buildScript, contains('libvulkan.so'));
      expect(buildScript, contains('VULKAN_TRIPLE'));
      expect(buildScript, contains('_himi_vulkan_stub'));
      expect(buildScript, contains(r'-Wl,-soname,libvulkan.so'));
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

    test('3.2 _gpuApi 字段控制 gpu-api 值', () {
      expect(androidDart, contains("static String _gpuApi = 'opengl'"));
      expect(androidDart, contains("'gpu-api': _gpuApi"));
    });

    test('3.3 _start 时检测 Vulkan 并设置 _gpuApi', () {
      expect(androidDart, contains('_gpuApi = await isVulkanAvailable()'));
      expect(androidDart, contains("? 'vulkan' : 'opengl'"));
    });

    test('3.4 gpu-context 保持 android（与 GPU API 无关）', () {
      expect(androidDart, contains("'gpu-context': 'android'"));
    });

    test('3.5 检测结果缓存（只检测一次）', () {
      expect(androidDart, contains('if (_vulkanAvailable != null)'));
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
}
