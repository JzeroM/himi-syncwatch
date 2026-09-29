import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/settings_screen.dart';

import '../helpers/test_fakes.dart';

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  AppSettings initial = const AppSettings(),
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(initial)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _glassSwitch(WidgetTester tester) {
  return find.descendant(
    of: find.ancestor(
      of: find.text('液态玻璃'),
      matching: find.byType(SwitchListTile),
    ),
    matching: find.byType(Switch),
  );
}

void main() {
  testWidgets('设置页展示液态玻璃开关（默认开）', (tester) async {
    final container = await _pumpScreen(tester);

    expect(find.text('液态玻璃'), findsOneWidget);
    expect(
      find.text('毛玻璃模糊与高光效果，低端设备可关闭以提升流畅度'),
      findsOneWidget,
    );
    expect(container.read(settingsProvider).glassUi, isTrue);
    expect(tester.widget<Switch>(_glassSwitch(tester)).value, isTrue);
  });

  testWidgets('切换开关后 glassUi 变为 false', (tester) async {
    final container = await _pumpScreen(tester);

    await tester.ensureVisible(find.text('液态玻璃'));
    await tester.pumpAndSettle();
    await tester.tap(_glassSwitch(tester));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).glassUi, isFalse);
  });

  testWidgets('再次切换恢复开启', (tester) async {
    final container =
        await _pumpScreen(tester, initial: const AppSettings(glassUi: false));

    expect(tester.widget<Switch>(_glassSwitch(tester)).value, isFalse);

    await tester.ensureVisible(find.text('液态玻璃'));
    await tester.pumpAndSettle();
    await tester.tap(_glassSwitch(tester));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).glassUi, isTrue);
  });
}
