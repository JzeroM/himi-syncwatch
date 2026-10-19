import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/about_settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
      child: const MaterialApp(home: AboutSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'HIMI',
      packageName: 'com.himi.syncwatch',
      version: '1.2.30',
      buildNumber: '456',
      buildSignature: '',
    );
  });

  testWidgets('渲染版本信息与三个功能行', (tester) async {
    await _pumpScreen(tester);

    expect(find.byKey(const ValueKey('aboutSettingsPage')), findsOneWidget);
    expect(find.text('HIMI 私密同步观影'), findsOneWidget);
    expect(find.text('版本 1.2.30+456'), findsOneWidget);
    expect(find.text('当前 v1.2.30+456'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('新版本提醒'), findsOneWidget);
    expect(find.text('上次检查'), findsOneWidget);
    expect(find.text('尚未检查过'), findsOneWidget);
  });

  testWidgets('上次检查时间按本地时区格式化', (tester) async {
    final t = DateTime(2026, 3, 8, 9, 5);
    await _pumpScreen(
      tester,
      initial: AppSettings(lastUpdateCheckAt: t.millisecondsSinceEpoch),
    );

    expect(find.text('2026-03-08 09:05'), findsOneWidget);
    expect(find.text('尚未检查过'), findsNothing);
  });

  testWidgets('新版本提醒开关可关闭并落盘', (tester) async {
    final container = await _pumpScreen(tester);
    final notifier =
        container.read(settingsProvider.notifier) as FakeSettingsNotifier;

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).updatePromptEnabled, isFalse);
    expect(notifier.persistCount, 1);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).updatePromptEnabled, isTrue);
  });

  testWidgets('当前平台不支持应用内更新时给出提示（主机测试环境为 Linux）',
      (tester) async {
    await _pumpScreen(tester);

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(find.text('当前平台暂不支持应用内更新'), findsOneWidget);
  });
}
