import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/appearance_settings_screen.dart';
import 'package:himi_syncwatch/services/app_icon_service.dart';

import '../helpers/test_fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required TargetPlatform platform,
  bool tvMode = false,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  // 高视口：让外观页所有分节都被布局（ListView 懒构建，矮视口下方分节不 attach）。
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
      'appIcon_artistic',
      'appIcon_glass',
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

  testWidgets('点 Artistic：Android 传别名全限定名 + 黑名单并写回设置', (tester) async {
    const channel = MethodChannel('flutter_dynamic_icon_plus');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    // 注入设备标识替身，避免依赖 device_info 平台通道。
    final original = AppIconService.deviceBlacklistLoader;
    AppIconService.deviceBlacklistLoader = () async => (
          brands: const ['Xiaomi'],
          manufactures: const ['Xiaomi'],
          models: const ['23127PN0CC'],
        );
    addTearDown(() => AppIconService.deviceBlacklistLoader = original);

    final container = await _pump(tester, platform: TargetPlatform.android);
    final tile = find.byKey(const ValueKey('appIcon_artistic'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(calls, isNotEmpty, reason: '应调用插件 setAlternateIconName');
    expect(calls.last.method, 'setAlternateIconName');
    expect(
        calls.last.arguments['iconName'], 'com.himi.syncwatch.icon_artistic');
    // Android 需带黑名单（设备自身命中）走立即分支。
    expect(calls.last.arguments['manufactures'], contains('Xiaomi'));
    expect(calls.last.arguments['models'], contains('23127PN0CC'));
    expect(container.read(settingsProvider).appIcon, 'artistic');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('外观页顺序：应用图标→主题色，分类页每行海报数在玻璃参数之后', (tester) async {
    await _pump(tester, platform: TargetPlatform.android);

    double y(String t) {
      final f = find.text(t);
      return tester.getTopLeft(f.first).dy;
    }

    // 应用图标 在 主题色 之上
    expect(y('应用图标'), lessThan(y('主题色')));
    // 分类页每行海报数 在 玻璃参数 之下
    expect(y('分类页每行海报数'), greaterThan(y('玻璃参数')));
    debugDefaultTargetPlatformOverride = null;
  });
}
