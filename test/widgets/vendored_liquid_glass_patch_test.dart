import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// vendored liquid_glass_widgets 本地补丁回归测试。
///
/// third_party/liquid_glass_widgets 是 pub.dev 1.8.1 的 vendored 副本，
/// 带两处 [PATCH himi] 补丁（interactive_indicator.frag 色散 ×2.0 与
/// 光谱边光）。本测试防止包更新/误还原导致补丁悄悄丢失：
/// - pubspec 必须是 path 依赖（hosted 包拿不到补丁）；
/// - frag 必须保留两处补丁标记；
/// - LICENSE 必须随包保留（MIT 再分发要求）。
void main() {
  const fragPath =
      'third_party/liquid_glass_widgets/shaders/interactive_indicator.frag';

  test('pubspec 使用 path 依赖 vendored 包（补丁才能生效）', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec.contains('path: third_party/liquid_glass_widgets'),
      isTrue,
      reason: 'liquid_glass_widgets 必须指向 third_party 本地副本',
    );
    expect(
      pubspec.contains('liquid_glass_widgets: ^1.8.1'),
      isFalse,
      reason: '不得回退到 hosted 依赖（会丢掉 [PATCH himi] 补丁）',
    );
  });

  test('vendored frag 保留两处 [PATCH himi] 补丁', () {
    final frag = File(fragPath).readAsStringSync();

    expect(
      frag.contains('[PATCH himi] 0.12 → 2.0'),
      isTrue,
      reason: '真色散补丁被移除：upstream ×0.12 为亚像素（0.06px）不可见',
    );
    expect(
      frag.contains('chromaticShift = distort * 2.0'),
      isTrue,
      reason: '色散系数必须为 2.0（0.5 输入 → 边缘 ~1px/侧彩边）',
    );
    expect(
      frag.contains('rimSpectrum'),
      isTrue,
      reason: '光谱边光补丁被移除：rim 恢复纯白 → 彩虹圈消失',
    );
    expect(
      frag.contains('mix(vec3(1.0), rimSpectrum, 0.85)'),
      isTrue,
      reason: '光谱边光着色系数保持 0.85',
    );

    final markers = RegExp(r'\[PATCH himi\]').allMatches(frag).length;
    expect(markers, greaterThanOrEqualTo(2), reason: '两处补丁标记齐全');
  });

  test('vendored 包带 LICENSE 且包名未变', () {
    expect(
      File('third_party/liquid_glass_widgets/LICENSE').existsSync(),
      isTrue,
      reason: 'MIT LICENSE 必须随 vendored 副本保留',
    );
    final pkg = File('third_party/liquid_glass_widgets/pubspec.yaml')
        .readAsStringSync();
    expect(pkg.contains('name: liquid_glass_widgets'), isTrue,
        reason: '包名不变 → package:liquid_glass_widgets 导入全部照旧');
    expect(pkg.contains('version: 1.8.1'), isTrue, reason: '基线版本 1.8.1');
  });
}
