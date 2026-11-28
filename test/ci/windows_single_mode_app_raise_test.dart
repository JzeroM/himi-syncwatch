import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 698 N75/N76/N77：Windows 单人模式「主窗可操作」守卫。
///
/// 背景：单人播放时 Qt 播放窗 `forceForeground()` 在最前，且其**透明控件层
/// （Overlay.qml 的 Qt::Tool 透明窗）没有 click-through**，会叠在 Flutter 主窗
/// 上吞掉鼠标（真机：看得见、点不动，点击还触发系统 beep）。
///
/// 修法（两层）：
/// 1. Dart：`_safePopPlayerPage` pop 后用 `windowManager.focus()` 真正
///    `SetWindowPos(HWND_TOP)` 抬主窗（`show()` 对已可见窗不抬 z-order）；
/// 2. Qt：控件层在「宿主+控件层双窗都失活」时隐藏，杜绝透明窗吞点击。
///
/// 注意：房间并排两窗相邻不重叠，走 `_raisePanelWithQt` 联动，与单人这条链无关。
void main() {
  final src = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final cpp = File('native/windows_qt_player/src/main.cpp').readAsStringSync();

  String safePopBody() {
    final start = src.indexOf('Future<void> _safePopPlayerPage');
    expect(start, greaterThan(0), reason: '_safePopPlayerPage 必须存在');
    return src.substring(start, (start + 3400).clamp(0, src.length));
  }

  test('单人 pop 后用 focus() 抬主窗（Windows only，roomCode==null）', () {
    final body = safePopBody();
    expect(body, contains('widget.roomCode == null'),
        reason: '只对单人模式生效；房间并排不能乱抬');
    expect(body, contains('defaultTargetPlatform == TargetPlatform.windows'),
        reason: '仅 Windows 双窗形态需要');
    expect(body, contains('windowManager.show()'),
        reason: '兜底恢复隐藏/最小化');
    expect(body, contains('windowManager.focus()'),
        reason: 'N77：show() 不抬已可见窗，必须 focus()（SetWindowPos HWND_TOP）');
  });

  test('Qt 控件层在双窗失活时隐藏（根治透明层吞点击/beep）', () {
    expect(cpp, contains('activeChanged'),
        reason: '必须监听宿主与控件层的激活态');
    expect(cpp, contains('overlay->hide()'),
        reason: '双窗失活时隐藏透明控件层');
    expect(cpp, contains('overlay->show()'),
        reason: '任一激活时恢复显示');
    expect(cpp, contains('host->isActive() || overlay->isActive()'),
        reason: '双窗任一激活即显示（只看宿主失活会把点控件的瞬间误藏）');
  });

  test('房间联动抬升仍保留', () {
    expect(src, contains('_raisePanelWithQt'));
  });
}