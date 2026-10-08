import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/appearance_settings_screen.dart';

import '../helpers/test_fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required TargetPlatform platform,
  bool tvMode = false,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(AppSettings(tvMode: tvMode))),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppearanceSettingsScreen()),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('Android 非 TV：显示应用图标分组与 4 个选项', (tester) async {
    await _pump(tester, platform: TargetPlatform.android);

    expect(find.text('应用图标'), findsOneWidget);
    for (final k in const [
      'appIcon_default',
      'appIcon_aurora',
      'appIcon_metal',
      'appIcon_neon',
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows：不显示应用图标分组', (tester) async {
    await _pump(tester, platform: TargetPlatform.windows);
    expect(find.text('应用图标'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android + TV：不显示应用图标分组', (tester) async {
    await _pump(tester, platform: TargetPlatform.android, tvMode: true);
    expect(find.text('应用图标'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('点 Aurora：Android 传别名全限定名并写回设置', (tester) async {
    const channel = MethodChannel('flutter_dynamic_icon_plus');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    final container = await _pump(tester, platform: TargetPlatform.android);
    final tile = find.byKey(const ValueKey('appIcon_aurora'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    await tester.pump();

    expect(calls, isNotEmpty, reason: '应调用插件 setAlternateIconName');
    expect(calls.last.method, 'setAlternateIconName');
    expect(calls.last.arguments['iconName'], 'com.himi.syncwatch.icon_aurora');
    expect(container.read(settingsProvider).appIcon, 'aurora');
    debugDefaultTargetPlatformOverride = null;
  });
}
