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
      'appIcon_mint',
      'appIcon_glass',
    ]) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    for (final entry in const {
      'appIcon_default': '默认',
      'appIcon_artistic': '艺术字',
      'appIcon_mint': '薄荷绿',
      'appIcon_glass': '玻璃紫',
    }.entries) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(entry.key)),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
        reason: entry.value,
      );
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

  testWidgets('点艺术字：先保存设置再走 himi/app_icon，不二次回查', (tester) async {
    final calls = <MethodCall>[];
    String? settingAtNative;
    late ProviderContainer container;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AppIconService.androidChannel, (call) async {
      calls.add(call);
      if (call.method == 'setIcon') {
        settingAtNative = container.read(settingsProvider).appIcon;
        return true;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AppIconService.androidChannel, null));

    container = await _pump(tester, platform: TargetPlatform.android);
    final tile = find.byKey(const ValueKey('appIcon_artistic'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(settingAtNative, 'artistic', reason: '原生切换前设置已落盘');
    expect(calls.map((c) => c.method), ['setIcon']);
    expect(calls.first.arguments, {'id': 'artistic'});
    expect(container.read(settingsProvider).appIcon, 'artistic');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android 切换失败 → 回滚设置', (tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AppIconService.androidChannel, (call) async {
      if (call.method == 'setIcon') {
        throw PlatformException(code: 'ICON_SWITCH_FAILED', message: '失败');
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(AppIconService.androidChannel, null));

    final container = await _pump(tester, platform: TargetPlatform.android);
    final tile = find.byKey(const ValueKey('appIcon_mint'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(settingsProvider).appIcon, isNull, reason: '失败回滚默认');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('点 Artistic（iOS）：公开 API 单次调用成功 → 写回设置', (tester) async {
    const channel = MethodChannel('flutter_dynamic_icon_plus');
    final calls = <MethodCall>[];
    String? current;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      if (call.method == 'setAlternateIconName') {
        // 只走公开 API：完整回传，无静默双打。
        current = (call.arguments as Map)['iconName'] as String?;
        return null;
      }
      if (call.method == 'getAlternateIconName') return current;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    final container =
        await _pump(tester, platform: TargetPlatform.iOS, tvMode: false);
    final tile = find.byKey(const ValueKey('appIcon_artistic'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final sets = calls
        .where((c) => c.method == 'setAlternateIconName')
        .toList(growable: false);
    expect(sets, hasLength(1), reason: '单次公开调用（修复前静默分支挂起/双打）');
    expect(sets.single.arguments['isSilent'], isFalse);
    expect(sets.single.arguments['iconName'], 'artistic');
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

  testWidgets('外观页含「首页轮播」开关，切换写回设置', (tester) async {
    final container = await _pump(tester, platform: TargetPlatform.android);

    expect(find.text('首页轮播'), findsOneWidget);
    final toggle = find.byKey(const ValueKey('homeCarouselToggle'));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue,
        reason: '首页轮播默认开');

    await tester.tap(toggle);
    await tester.pump();
    expect(container.read(settingsProvider).homeCarousel, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('TV 模式隐藏「首页轮播」开关', (tester) async {
    await _pump(tester, platform: TargetPlatform.android, tvMode: true);

    expect(find.byKey(const ValueKey('homeCarouselToggle')), findsNothing);
    expect(find.text('首页轮播'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
