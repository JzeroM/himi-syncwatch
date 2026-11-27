import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 698 N50：liquid_glass_widgets 水滴 shader 定制守卫（vendored 版）。
///
/// 包是 vendored（path: third_party/liquid_glass_widgets），himi 定制
/// （N39 凸透镜剖面 / N42 轮廓色散环 / ×4.0 色散 / 双纹理复合）直接提交
/// 在 third_party（git 持久）。本测试锁定制在位 + 透镜强度。
void main() {
  final frag = File(
      'third_party/liquid_glass_widgets/shaders/interactive_indicator.frag');

  test('vendored 定制在位（uLensZoom/轮廓色散环/双纹理复合）', () {
    expect(frag.existsSync(), isTrue);
    final s = frag.readAsStringSync();
    expect(s, contains('uLensZoom'), reason: 'N39 凸透镜剖面');
    expect(s, contains('ringWeight'), reason: 'N42 轮廓色散环');
    expect(s, contains('compositeFetch'), reason: 'N40 双纹理复合');
  });

  test('守卫脚本通过（vendored 定制全部在位）', () {
    final r = Process.runSync('bash', ['scripts/patch_glass_shader.sh']);
    expect(r.exitCode, 0);
    expect(r.stdout, contains('全部在位'));
  });

  test('N51 透镜替换式合成（baseAlpha/edgeAlpha 1.0 不透底）', () {
    final s = frag.readAsStringSync();
    expect(s, contains('float baseAlpha = (uHasBackground > 0.5) ? 1.0 :'),
        reason: 'N51：滴内纯折射替换（消重影/原线直穿）');
    expect(s, contains('float edgeAlpha = (uHasBackground > 0.5) ? 1.0 :'),
        reason: 'N51：边缘同为折射替换');
  });

  test('N73 透镜纯弯折（lensZoom=0，1:1 不缩放）', () {
    final lens = File('lib/widgets/glass/blob_lens.dart').readAsStringSync();
    expect(lens, contains('lensZoom: 0'),
        reason: 'N73：1:1 纯弯折（图2 对齐）');
  });
}
