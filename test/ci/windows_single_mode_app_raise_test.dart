import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 698 N77：Windows 单人模式「主窗可操作」守卫。
///
/// 设计：起播后 **Qt 保持在前**；用户需要换资源时**主动选主窗**（任务栏/
/// 点主窗）才让主窗到前。主窗在前时 Qt 宿主失活 → 透明控件层（overlay）
/// 必须隐藏，否则它叠在主窗上吞点击、触发系统 beep（真机：看得见、点不动）。
///
/// 修法：
/// - Qt：50ms 定时器里控件层显隐条件 = `宿主可见 &&（宿主或控件层任一激活）`，
///   失活即隐藏；
/// - Dart：`_safePopPlayerPage`（仅退出/会话顶替路径）用 `windowManager.focus()`
///   抬主窗；正常单人「隐身存活」不 pop、不自动抬窗。
void main() {
  final src = File('lib/screens/player/player_screen.dart').readAsStringSync();
  final cpp = File('native/windows_qt_player/src/main.cpp').readAsStringSync();

  String safePopBody() {
    final start = src.indexOf('Future<void> _safePopPlayerPage');
    expect(start, greaterThan(0), reason: '_safePopPlayerPage 必须存在');
    return src.substring(start, (start + 3400).clamp(0, src.length));
  }

  test('Qt 控件层显隐同时看可见性与激活态（失活即隐藏，不被定时器拉回）', () {
    expect(cpp, contains('hostVisible && active'),
        reason: '显示条件必须同时看宿主可见 + 任一激活');
    expect(cpp, contains('host->isActive() || overlay->isActive()'),
        reason: '双窗任一激活才显示（只看宿主失活会把点控件的瞬间误藏）');
    expect(cpp, contains('overlay->setVisible(show)'),
        reason: '用统一的 show 裁决显隐，杜绝透明层在宿主失活时仍显示');
    // N77 曾加的 activeChanged 防抖块会与定时器打架，必须已删除
    expect(cpp, isNot(contains('overlayVisTimer')),
        reason: '不要单独用 activeChanged 防抖，统一由 50ms 定时器裁决');
  });

  test('单人退出/会话顶替路径用 focus() 抬主窗（不自动抬）', () {
    final body = safePopBody();
    expect(body, contains('windowManager.focus()'),
        reason: 'focus() 才 SetWindowPos(HWND_TOP)，show() 不抬已可见窗');
    // 正常单人「隐身存活」不 pop——本方法只在退出/顶替时触发
    expect(src, contains('隐身存活'),
        reason: '单人正常回详情页不 pop、不自动抬主窗（Qt 保持在前）');
  });
}