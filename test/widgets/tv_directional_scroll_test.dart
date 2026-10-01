import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_directional_scroll.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

import '../helpers/test_fakes.dart';

ProviderScope _wrap(
  Widget page, {
  bool remote = true,
  AppSettings settings = const AppSettings(tvMode: true),
}) {
  final Widget child = remote ? TvRemoteShortcuts(child: page) : page;
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
    ],
    child: child,
  );
}

Widget _listPage() => MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          itemCount: 50,
          itemBuilder: (context, i) => SizedBox(
            key: ValueKey('item_$i'),
            height: 60,
            child: TvFocusable(
              autofocus: i == 0,
              onTap: () {},
              child: Center(child: Text('item $i')),
            ),
          ),
        ),
      ),
    );

/// 焦点节点是否位于 [ancestor] 子树内（含自身）。
bool _isWithin(Element node, Element ancestor) {
  if (node == ancestor) return true;
  var found = false;
  node.visitAncestorElements((a) {
    if (a == ancestor) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// 当前焦点落在哪个 item 的 TvFocusable 内（0..49，找不到返回 null）。
int? _focusedIndex(WidgetTester tester) {
  final focus = FocusManager.instance.primaryFocus;
  final node = focus?.context;
  if (node is! Element) return null;
  for (var i = 0; i < 50; i++) {
    final candidates = find.descendant(
      of: find.byKey(ValueKey('item_$i')),
      matching: find.byType(Focus),
    );
    if (candidates.evaluate().any((c) => _isWithin(node, c))) return i;
  }
  return null;
}

void main() {
  testWidgets('方向键走到列表底后滚动贯通：焦点继续深入新滚入区域', (tester) async {
    await tester.pumpWidget(_wrap(_listPage()));
    await tester.pump();
    expect(_focusedIndex(tester), 0);

    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }

    // 焦点穿过视口边界（默认行为停在 ~16），贯通后深入 22+
    final idx = _focusedIndex(tester);
    expect(idx, isNotNull);
    expect(idx! >= 22, isTrue, reason: '焦点应贯通滚动到 item $idx');
  });

  testWidgets('对照：无遥控器挂载层时按框架默认行为运行（焦点移动、无异常）', (tester) async {
    await tester.pumpWidget(_wrap(_listPage(), remote: false));
    await tester.pump();

    for (var i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }

    // 默认行为（方向焦点+ensureVisible）也存在，但贯通由挂载层保证大步滚动
    expect(tester.takeException(), isNull);
    final idx = _focusedIndex(tester);
    expect(idx, isNotNull);
    expect(idx! > 0, isTrue);
  });

  testWidgets('文本编辑内方向键让位给光标移动（不被滚动贯通拦截）', (tester) async {
    final controller = TextEditingController(text: 'hello')
      ..selection = const TextSelection.collapsed(offset: 5);
    await tester.pumpWidget(_wrap(
      MaterialApp(
        home:
            Scaffold(body: TextField(controller: controller, autofocus: true)),
      ),
    ));
    await tester.pump();
    expect(controller.selection.baseOffset, 5);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection.baseOffset, 4);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.baseOffset, 5);
  });

  testWidgets('Dialog 打开后 OK 键两段式：先落焦主按钮再激活', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(_wrap(MaterialApp(home: Builder(builder: (ctx) {
      return ElevatedButton(
        onPressed: () => showDialog<void>(
          context: ctx,
          builder: (c) => AlertDialog(
            title: const Text('删除'),
            actions: [
              TextButton(
                onPressed: () {
                  confirmed = true;
                  Navigator.pop(c);
                },
                child: const Text('确认'),
              ),
            ],
          ),
        ),
        child: const Text('open'),
      );
    }))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 第一段：焦点停在 Dialog 作用域，OK 落焦到主按钮
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(confirmed, isFalse);

    // 第二段：焦点在按钮上，OK 激活
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('Dialog 打开后方向键落焦路径：下 + OK 激活', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(_wrap(MaterialApp(home: Builder(builder: (ctx) {
      return ElevatedButton(
        onPressed: () => showDialog<void>(
          context: ctx,
          builder: (c) => AlertDialog(
            title: const Text('提示'),
            actions: [
              TextButton(
                onPressed: () {
                  confirmed = true;
                  Navigator.pop(c);
                },
                child: const Text('好'),
              ),
            ],
          ),
        ),
        child: const Text('open'),
      );
    }))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('焦点滚动到列表尽头后吞键不越界（无异常）', (tester) async {
    await tester.pumpWidget(_wrap(_listPage()));
    await tester.pump();

    // 远超内容长度：滚动到 maxScrollExtent 后应停住而非抛异常
    for (var i = 0; i < 80; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(find.text('item 49'), findsOneWidget);
  });
}
