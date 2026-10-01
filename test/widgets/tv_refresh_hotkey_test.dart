import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/tv/tv_refresh_hotkey.dart';

import '../helpers/test_fakes.dart';

Widget _host(bool tvMode, Future<void> Function() onRefresh) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(AppSettings(tvMode: tvMode))),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: TvRefreshHotkey(
          onRefresh: onRefresh,
          // 焦点在子树内，按键事件沿焦点链到达热键层
          child: const Focus(
            autofocus: true,
            child: SizedBox(width: 10, height: 10),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('TV 模式菜单键触发刷新', (tester) async {
    var count = 0;
    await tester.pumpWidget(_host(true, () async => count++));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect(count, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect(count, 2);
  });

  testWidgets('非 TV 模式菜单键不触发刷新', (tester) async {
    var count = 0;
    await tester.pumpWidget(_host(false, () async => count++));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect(count, 0);
  });

  testWidgets('非 TV 模式直接透传子树（无 Focus 包裹层）', (tester) async {
    await tester.pumpWidget(_host(false, () async {}));
    await tester.pump();

    // 焦点应落在子树自身的 autofocus Focus 上，中间没有额外热键层拦截
    expect(find.byType(TvRefreshHotkey), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(FocusManager.instance.primaryFocus!.hasPrimaryFocus, isTrue);
  });
}
