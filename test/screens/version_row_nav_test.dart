import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/detail/version_row_nav.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

import '../helpers/test_fakes.dart';

/// 「可用版本」行 TV 方向键确定性导航（v1.2.24）。
///
/// 真机症状：下移一个版本后再按 ↓ 焦点环反而上移；到底后整页乱滚。
/// 这里验证 [VersionRowNav] 的行序接管、末行吞键与首行放行。

const double _rowHeight = 60;

KeyEvent _arrowDown() => const KeyDownEvent(
      timeStamp: Duration.zero,
      logicalKey: LogicalKeyboardKey.arrowDown,
      physicalKey: PhysicalKeyboardKey.arrowDown,
    );

KeyEvent _arrowUp() => const KeyDownEvent(
      timeStamp: Duration.zero,
      logicalKey: LogicalKeyboardKey.arrowUp,
      physicalKey: PhysicalKeyboardKey.arrowUp,
    );

Future<void> _pumpRows(
  WidgetTester tester,
  VersionRowNav nav, {
  List<String> ids = const ['a', 'b', 'c'],
  FocusNode? belowNode,
}) async {
  nav.sync(ids);
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(const AppSettings(tvMode: true))),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              for (final id in ids)
                SizedBox(
                  height: _rowHeight,
                  child: TvFocusable(
                    onTap: () {},
                    focusNode: nav.nodeFor(id),
                    onKeyEvent: nav.handleKeyEvent,
                    child: Center(child: Text('row-$id')),
                  ),
                ),
              if (belowNode != null)
                TvFocusable(
                  onTap: () {},
                  focusNode: belowNode,
                  child: const SizedBox(
                    height: _rowHeight,
                    child: Center(child: Text('below')),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('↓ 按行序下移、↑ 按行序回退（不再跳回上一行）', (tester) async {
    final nav = VersionRowNav();
    addTearDown(nav.dispose);
    await _pumpRows(tester, nav);

    nav.nodeFor('a').requestFocus();
    await tester.pump();
    expect(nav.nodeFor('a').hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(nav.nodeFor('b').hasPrimaryFocus, isTrue, reason: '↓ 落到下一个版本行');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(nav.nodeFor('c').hasPrimaryFocus, isTrue,
        reason: '再按 ↓ 继续下移（真机症状：此处曾往上回）');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(nav.nodeFor('b').hasPrimaryFocus, isTrue, reason: '↑ 回退一行');
  });

  testWidgets('末行 ↓：下方无可聚焦节点 → 吞键不滚动、焦点不动', (tester) async {
    final nav = VersionRowNav();
    addTearDown(nav.dispose);
    await _pumpRows(tester, nav);

    nav.nodeFor('c').requestFocus();
    await tester.pump();
    expect(nav.nodeFor('c').hasPrimaryFocus, isTrue);

    expect(nav.handleKeyEvent(nav.nodeFor('c'), _arrowDown()),
        KeyEventResult.handled, reason: '无下方候选时消费按键，防整页乱滚');
    await tester.pump();
    expect(nav.nodeFor('c').hasPrimaryFocus, isTrue, reason: '焦点保持在末行');
  });

  testWidgets('末行 ↓：下方有可聚焦节点 → 放行给默认遍历（去剧集/推荐行）',
      (tester) async {
    final nav = VersionRowNav();
    addTearDown(nav.dispose);
    final belowNode = FocusNode(debugLabel: 'below');
    addTearDown(belowNode.dispose);
    await _pumpRows(tester, nav, belowNode: belowNode);

    nav.nodeFor('c').requestFocus();
    await tester.pump();

    expect(nav.handleKeyEvent(nav.nodeFor('c'), _arrowDown()),
        KeyEventResult.ignored, reason: '下方有候选，交给框架继续下移');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(belowNode.hasPrimaryFocus, isTrue, reason: '焦点落到下方节点');
  });

  testWidgets('首行 ↑：放行给默认遍历（回播放操作行）', (tester) async {
    final nav = VersionRowNav();
    addTearDown(nav.dispose);
    await _pumpRows(tester, nav);

    nav.nodeFor('a').requestFocus();
    await tester.pump();
    expect(nav.handleKeyEvent(nav.nodeFor('a'), _arrowUp()),
        KeyEventResult.ignored, reason: '首行上方无版本行，交还框架');
  });

  testWidgets('非方向键与松开键不消费（OK 等默认逻辑不受影响）', (tester) async {
    final nav = VersionRowNav();
    addTearDown(nav.dispose);
    await _pumpRows(tester, nav);

    expect(
        nav.handleKeyEvent(
          nav.nodeFor('b'),
          const KeyDownEvent(
            timeStamp: Duration.zero,
            logicalKey: LogicalKeyboardKey.enter,
            physicalKey: PhysicalKeyboardKey.enter,
          ),
        ),
        KeyEventResult.ignored);
    expect(
        nav.handleKeyEvent(
          nav.nodeFor('b'),
          const KeyUpEvent(
            timeStamp: Duration.zero,
            logicalKey: LogicalKeyboardKey.arrowDown,
            physicalKey: PhysicalKeyboardKey.arrowDown,
          ),
        ),
        KeyEventResult.ignored);
  });

  testWidgets('sync 清理消失版本的节点（新节点为新实例）', (tester) async {
    final nav = VersionRowNav();
    addTearDown(nav.dispose);
    await _pumpRows(tester, nav);

    final staleA = nav.nodeFor('a');
    nav.sync(const ['b', 'c']);
    expect(nav.handleKeyEvent(staleA, _arrowDown()), KeyEventResult.ignored,
        reason: '已移除的行不再参与导航');
    expect(identical(nav.nodeFor('a'), staleA), isFalse,
        reason: '旧节点已销毁，重新取为新实例');
  });

  test('hasFocusableBelow：无作用域/未挂树时安全返回 false', () {
    final node = FocusNode();
    addTearDown(node.dispose);
    expect(VersionRowNav.hasFocusableBelow(node), isFalse);
  });
}
