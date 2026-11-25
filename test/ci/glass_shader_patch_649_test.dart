import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 698 N49：liquid_glass_widgets 水滴 shader 物理修正 patch 守卫。
///
/// pub get 会重置 pub cache → patch 由 [scripts/patch_glass_shader.sh]
/// 在每次 pub get 后打回（CI/本地构建已集成）。本测试锁 patch 状态，
/// 丢失即红（提示重跑 patch 脚本）。
void main() {
  final frag = Directory(
          Platform.environment['PUB_CACHE'] ??
              '${Platform.environment['HOME']}/.pub-cache')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('shaders/interactive_indicator.frag'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('shader patch 在位（PATCH himi N49 标记 + 真实色散系数）', () {
    expect(frag, isNotEmpty, reason: 'liquid_glass_widgets shader 存在');
    final s = frag.last.readAsStringSync();
    expect(s, contains('PATCH himi N49'), reason: 'patch 标记在位');
    expect(s, contains('float dispersion = uChromaticAberration * 0.35;'),
        reason: '真实棱镜色散（柯西模型）系数锁');
    expect(s, contains('uSize.y * 0.5;'), reason: '放大弯折倍率锁');
    expect(s, contains('// edgeInfluence = edgeInfluence * edgeInfluence;'),
        reason: '形变一次方衰减（平方衰减已注释）');
  });

  test('patch 脚本幂等（重跑不破坏）', () {
    final r = Process.runSync('bash', ['scripts/patch_glass_shader.sh']);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('已 patch，跳过'));
  });
}
