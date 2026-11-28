import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 698 N77：Android 渲染后端守卫。
///
/// 需求：三端（安卓/iOS/鸿蒙）玻璃统一回 standard 着色器（v1.6.17 架构），
/// 安卓引擎关闭 Impeller（Skia）。
///
/// 落地：Manifest meta-data 是**单一事实源**——
/// - 引擎 `FlutterLoader` 读到 `false` → Skia；
/// - fvp 插件 `FvpPlugin` 读同一 meta-data → `SurfaceTexture`（Skia）。
/// 两边同源，杜绝「引擎 Impeller + 插件 SurfaceTexture」的黑屏错配
/// （v1.1.61 RK3528 盒子回归的根因）。
void main() {
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const fvpPluginPath = 'third_party/fvp/android/src/main/java/'
      'com/mediadevkit/fvp/FvpPlugin.java';

  group('AndroidManifest Impeller 配置（单一事实源）', () {
    test('EnableImpeller meta-data 显式声明且为 true（全端 Impeller）', () {
      final xml = File(manifestPath).readAsStringSync();
      final match = RegExp(
        '<meta-data\\s+'
        'android:name="io\\.flutter\\.embedding\\.android\\.EnableImpeller"\\s+'
        'android:value="([^"]+)"',
        multiLine: true,
      ).firstMatch(xml);

      expect(
        match,
        isNotNull,
        reason: '必须显式声明：它是引擎与 fvp 的共同事实源，'
            '删除后插件按 false 注册 SurfaceTexture，会与引擎错配黑屏',
      );
      expect(
        match!.group(1),
        'false',
        reason: '698 N77：回到 v1.6.17——安卓关闭 Impeller（Skia），'
            '三端玻璃统一 standard；fvp 读同一键走 SurfaceTexture，成对',
      );
    });

    test('fvp 插件从 meta-data 读取 Impeller（与引擎同源）', () {
      final java = File(fvpPluginPath).readAsStringSync();
      expect(
        java,
        contains(
            'io.flutter.embedding.android.EnableImpeller'),
        reason: '插件必须读同一 meta-data key',
      );
      expect(
        java,
        contains('createSurfaceProducer'),
        reason: 'Impeller 下必须用 SurfaceProducer',
      );
      expect(
        java,
        isNot(contains('impeller = true;')),
        reason: '不能硬编码：硬编码会与引擎来源脱钩，回退时可能错配',
      );
    });
  });

  /// 698 N76 实战教训：注释里写 `--enable-impeller` 会让
  /// `ManifestMerger2` 解析失败（XML 注释禁止连续 `--`），CI build-android
  /// 直接挂。文件仍是合法文本，普通字符串断言抓不到，必须专门守卫。
  test('XML 注释不含连续 "--"（Manifest 合并解析守卫）', () {
    final xml = File(manifestPath).readAsStringSync();
    final comments = RegExp(r'<!--([\s\S]*?)-->').allMatches(xml);
    expect(comments, isNotEmpty);
    for (final c in comments) {
      expect(
        c.group(1)!.contains('--'),
        isFalse,
        reason: 'XML 注释禁止连续 --（如 --enable-impeller= 写法）',
      );
    }
  });
}