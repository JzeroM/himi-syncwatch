import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 698 N75/N76：Windows 单人模式「主窗可操作」守卫。
///
/// 背景：单人播放时 Qt 播放窗 `forceForeground()` 在最前，播放页 pop 回
/// 详情页后主窗一直压在 Qt 后面 → 用户无法浏览/换资源。
///
/// 修法：`_safePopPlayerPage` 在 pop 后（仅 Windows 单人）把主窗抬回前台；
/// Qt 继续在后台播放（任务栏可切回）。
///
/// 注意：房间并排走 `_raisePanelWithQt`（Qt 联动信号），与单人这条链无关。
void main() {
  final src = File('lib/screens/player/player_screen.dart').readAsStringSync();

  String safePopBody() {
    final start = src.indexOf('Future<void> _safePopPlayerPage');
    expect(start, greaterThan(0), reason: '_safePopPlayerPage 必须存在');
    // 取函数体一段足够覆盖 pop 之后的恢复逻辑
    return src.substring(start, (start + 3200).clamp(0, src.length));
  }

  test('单人 pop 后把主窗抬回前台（Windows only，roomCode==null）', () {
    final body = safePopBody();
    expect(
      body,
      contains('widget.roomCode == null'),
      reason: '只对单人模式生效；房间并排不能乱抬（会破坏面板摆位）',
    );
    expect(
      body,
      contains('defaultTargetPlatform == TargetPlatform.windows'),
      reason: '仅 Windows 双窗形态需要',
    );
    expect(
      body,
      contains('windowManager.show()'),
      reason: '抬主窗回前台（Qt 后台继续播放）',
    );
  });

  test('房间联动抬升仍保留，且不误伤单人（Qt 侧信号仅房间开启）', () {
    expect(src, contains('_raisePanelWithQt'));
    // N76 注释钉死事实：window_manager 0.5.2 的 Show 忽略 inactive
    expect(src, contains('忽略'));
    expect(src, contains('inactive'));
  });
}