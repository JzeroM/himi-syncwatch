import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// vendored liquid_glass_widgets 本地补丁回归测试。
///
/// third_party/liquid_glass_widgets 是 pub.dev 1.8.1 的 vendored 副本，
/// 带多处 [PATCH himi] 补丁（interactive_indicator.frag：色散 ×2.0、
/// 光谱边光、折射增强 ×1.79、边框弱化、宽软彩虹光晕）。本测试防止包
/// 更新/误还原导致补丁悄悄丢失：
/// - pubspec 必须是 path 依赖（hosted 包拿不到补丁）；
/// - frag 必须保留全部补丁标记；
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
  });

  test('vendored frag 保留第二轮补丁（折射增强+边框弱化+宽软彩虹光晕）', () {
    final frag = File(fragPath).readAsStringSync();

    expect(frag.contains('bendStrength = 1.25 *'), isTrue,
        reason: '折射强度 1.25（upstream 0.9 → 设备反馈需更强折射）');
    expect(frag.contains('edgeZone = 18.0'), isTrue,
        reason: '光学边带 18px（upstream 14 → 宽软折射/光晕带）');
    expect(frag.contains('uSize.y * 0.45'), isTrue,
        reason: '弯折高度比 0.45（upstream 0.35，配合 1.25 → ×1.79 折射）');
    expect(frag.contains('haloBand'), isTrue,
        reason: '宽软彩虹光晕带（upstream 仅发丝 borderMask → 边框感）');
    expect(frag.contains('* max(borderMask, haloBand) * 1.2'), isTrue,
        reason: '光晕合成走 haloBand 且系数 1.2（防过曝白框）');
    expect(frag.contains('(keyHighlight + kickHighlight) * 0.4'), isTrue,
        reason: '白色镜面瓣 ×0.4 → 边缘是彩色光晕不是白框');
    expect(frag.contains('0.88 : standardEdgeAlpha'), isTrue,
        reason: '边缘 alpha 0.95 → 0.88，不再近乎实心');
    expect(
      frag.contains('borderMask * 0.5 * clamp(uAmbientRim * 3.0'),
      isTrue,
      reason: 'ringOpacity 实心环 0.9/×10 → 0.5/×3，边框感主因被削弱',
    );

    final markers = RegExp(r'\[PATCH himi\]').allMatches(frag).length;
    expect(markers, greaterThanOrEqualTo(9), reason: '全部 [PATCH himi] 补丁标记齐全');
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
