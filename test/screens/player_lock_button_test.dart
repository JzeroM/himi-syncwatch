import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_lock_button.dart';

import '../helpers/test_fakes.dart';

Widget _host(
  Widget child, {
  AppSettings settings = const AppSettings(),
}) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
    ],
  );
  addTearDown(container.dispose);
  // TvFocusable 是 ConsumerWidget（读 tvMode provider）
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('PlayerScreen.showLockButton（TV 无锁）', () {
    test('非 TV 显示锁按钮', () {
      expect(PlayerScreen.showLockButton(tvMode: false), isTrue);
    });

    test('TV 模式隐藏锁按钮', () {
      expect(PlayerScreen.showLockButton(tvMode: true), isFalse);
    });
  });

  group('PlayerLockButton（左缘两形态）', () {
    testWidgets('未锁：lock_open 图标，点击回调上锁', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(PlayerLockButton(
        locked: false,
        onToggle: () => calls++,
      )));
      final icon =
          tester.widget<Icon>(find.byKey(const ValueKey('playerLockButton')));
      expect(icon.icon, Icons.lock_open);
      await tester.tap(find.byKey(const ValueKey('playerLockButton')));
      expect(calls, 1);
    });

    testWidgets('已锁：lock 图标，点击回调解锁', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(PlayerLockButton(
        locked: true,
        onToggle: () => calls++,
      )));
      final icon =
          tester.widget<Icon>(find.byKey(const ValueKey('playerLockButton')));
      expect(icon.icon, Icons.lock);
      await tester.tap(find.byKey(const ValueKey('playerLockButton')));
      expect(calls, 1);
    });
  });
}
