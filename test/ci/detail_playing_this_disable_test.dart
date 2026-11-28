import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 698 N77：详情页「同资源播放中 → 播放/建房按钮视觉禁用」守卫。
///
/// 约束（N72 起）：Windows 单人双窗口下，当前正在播放的资源的详情页，
/// 「播放」与「建房」控件禁用；**其他资源不受限制**（可点播放切换当前
/// 播放内容）。
///
/// N77 补上「视觉禁用」：此前只在点击处理器里 return + toast，按钮仍
/// 可点、看着能点。现在按钮在 `playingThis` 时传 null → 灰化。
void main() {
  final src =
      File('lib/screens/detail/detail_screen.dart').readAsStringSync();

  test('响应式判定用 ref.watch（播放中资源变化实时重建）', () {
    expect(src, contains('_qtPlayingThisWatch'));
    expect(src, contains('ref.watch(currentPlayingItemIdProvider)'),
        reason: 'watch 订阅，回详情页时按钮实时变灰/恢复');
  });

  test('glassButton 支持禁用态（onPressed 可空 + 灰化 0.35）', () {
    expect(src, contains('Future<void> Function()? onPressed'),
        reason: 'onPressed 可空，null 即禁用');
    expect(src, contains('alpha: 0.35'),
        reason: '禁用态图标/文字灰化');
    expect(src, contains('final disabled = onPressed == null;'));
  });

  test('播放/建房按钮：playingThis 时传 null', () {
    expect(src, contains('onPressed: playingThis ? null : play'));
    expect(src, contains('onPressed: playingThis ? null : _createRoom'));
  });

  test('点击处理器守卫保留（兜底，防止状态竞态）', () {
    expect(src, contains('if (_qtPlayingThis)'),
        reason: '处理器层仍拦截并提示，防视觉禁用被绕过的竞态');
  });
}