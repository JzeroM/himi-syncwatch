import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// vendored liquid_glass_widgets 本地补丁回归测试。
///
/// third_party/liquid_glass_widgets 是 pub.dev 1.8.1 的 vendored 副本，
/// 带多处 [PATCH himi] 补丁（interactive_indicator.frag：色散 ×4.0 物理
/// 彩虹、中性 rim、折射增强 ×1.79、边框弱化；无任何自发光色环）。本测试
/// 防止包更新/误还原导致补丁悄悄丢失：
/// - pubspec 必须是 path 依赖（hosted 包拿不到补丁）；
/// - frag 必须保留全部补丁标记，且不得回退人造光谱色环/自发光光晕；
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

  test('vendored frag 保留第一轮补丁（真色散 ×4.0 + 中性 rim）', () {
    final frag = File(fragPath).readAsStringSync();

    expect(
      frag.contains('[PATCH himi] 0.12 → 4.0'),
      isTrue,
      reason: '真色散补丁被移除：upstream ×0.12 为亚像素（0.06px）不可见',
    );
    expect(
      frag.contains('chromaticShift = distort * 4.0'),
      isTrue,
      reason: '色散系数必须为 4.0（0.5 输入 → 边缘 ~2px/侧物理彩虹）',
    );
    expect(
      frag.contains('vec3 rimSpectrum'),
      isFalse,
      reason: '人造光谱色环已撤销（设备反馈：要物理光晕不要发光色晕）',
    );
    expect(
      frag.contains('float haloBand'),
      isFalse,
      reason: '自发光宽软光晕带已撤销，彩虹必须来自捕获内容的真色散',
    );
    expect(
      frag.contains('vec3 rimColor = vec3(1.0) * modifiedRimBrightness'),
      isTrue,
      reason: 'rim 必须是中性白微光（非光谱色）',
    );
  });

  test('vendored frag 保留第二轮补丁（折射增强+边框弱化）', () {
    final frag = File(fragPath).readAsStringSync();

    expect(frag.contains('bendStrength = 1.25 *'), isTrue,
        reason: '折射强度 1.25（upstream 0.9 → 设备反馈需更强折射）');
    expect(frag.contains('edgeZone = 28.0'), isTrue,
        reason: '光学边带 28px（upstream 14 → round-5 折射范围加大）');
    expect(
        frag.contains('edgeInfluence = edgeInfluence * edgeInfluence'), isTrue,
        reason: '平方衰减必须保留：round-5 撤销后 28px 线性中带把内容撕成彩色碎片（设备反馈 round-6）');
    expect(frag.contains('uSize.y * 0.45'), isTrue,
        reason: '弯折高度比 0.45（upstream 0.35，配合 1.25 → ×1.79 折射）');
    expect(frag.contains('rimColor * borderMask * 1.2'), isTrue,
        reason: 'rim 只合成 hairline 核心（1.5 → 1.2，无 haloBand 扩散）');
    expect(frag.contains('(keyHighlight + kickHighlight) * 0.4'), isTrue,
        reason: '白色镜面瓣 ×0.4 → 边缘是柔和微光不是白框');
    expect(frag.contains('0.88 : standardEdgeAlpha'), isTrue,
        reason: '边缘 alpha 0.95 → 0.88，不再近乎实心');
    expect(
      frag.contains('borderMask * 0.5 * clamp(uAmbientRim * 3.0'),
      isTrue,
      reason: 'ringOpacity 实心环 0.9/×10 → 0.5/×3，边框感主因被削弱',
    );

    final markers = RegExp(r'\[PATCH himi\]').allMatches(frag).length;
    expect(markers, greaterThanOrEqualTo(10), reason: '全部 [PATCH himi] 补丁标记齐全');
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
