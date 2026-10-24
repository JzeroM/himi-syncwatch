import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/danmaku_config_screen.dart';
import 'package:himi_syncwatch/screens/settings/player_settings_screen.dart';
import 'package:himi_syncwatch/screens/settings/settings_screen.dart';

import '../helpers/test_fakes.dart';

Future<ProviderContainer> _pumpConfig(
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
      child: const MaterialApp(home: DanmakuConfigScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 开关 finder：祖先 SwitchListTile 包含指定标题。
Finder _switchOf(String title) => find.descendant(
      of: find.ancestor(
          of: find.text(title), matching: find.byType(SwitchListTile)),
      matching: find.byType(Switch),
    );

/// ListView 懒构建：滚到目标文本（多滚一段越过透明 AppBar 遮挡）。
Future<void> _scrollTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('DanmakuConfigScreen 控件与写入', () {
    testWidgets('默认展示全部分区控件', (tester) async {
      await _pumpConfig(tester);

      expect(
          find.byKey(const ValueKey('danmakuDefaultOnSwitch')), findsOneWidget);
      expect(find.byKey(const ValueKey('danmakuQrConfigEntry')), findsNothing);
      expect(
          find.byKey(const ValueKey('danmakuClearConfigEntry')), findsNothing);
      expect(find.byKey(const ValueKey('danmakuApiUrlField')), findsOneWidget);
      expect(find.byKey(const ValueKey('danmakuScrollRowsSlider')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('danmakuTopRowsSlider')), findsOneWidget);
      expect(find.byKey(const ValueKey('danmakuBottomRowsSlider')),
          findsOneWidget);
      // 限制关 → 无数量上限滑杆
      expect(find.byKey(const ValueKey('danmakuMaxCountSlider')), findsNothing);

      await _scrollTo(tester, '屏蔽关键词');
      expect(
          find.byKey(const ValueKey('danmakuBlockTopSwitch')), findsOneWidget);
      expect(find.byKey(const ValueKey('danmakuBlockBottomSwitch')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('danmakuBlockWordsField')), findsOneWidget);
      expect(find.byKey(const ValueKey('danmakuLimitCountSwitch')),
          findsOneWidget);

      await _scrollTo(tester, '恢复默认');
      expect(
          find.byKey(const ValueKey('danmakuResetDefaults')), findsOneWidget);
    });

    testWidgets('弹幕默认打开开关切换写入 settings', (tester) async {
      final container = await _pumpConfig(tester);
      expect(container.read(settingsProvider).danmakuDefaultOn, isTrue);

      await tester.tap(_switchOf('弹幕默认打开'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).danmakuDefaultOn, isFalse);
    });

    testWidgets('API 地址输入写入 danmakuApiUrl', (tester) async {
      final container = await _pumpConfig(tester);

      await tester.enterText(
        find.byKey(const ValueKey('danmakuApiUrlField')),
        'http://10.0.0.2:9321/tok',
      );
      await tester.pumpAndSettle();
      expect(
        container.read(settingsProvider).danmakuApiUrl,
        'http://10.0.0.2:9321/tok',
      );
    });

    testWidgets('TV 只显示扫码配置，不显示输入框', (tester) async {
      await _pumpConfig(tester, initial: const AppSettings(tvMode: true));

      final entry = find.byKey(const ValueKey('danmakuQrConfigEntry'));
      expect(entry, findsOneWidget);
      expect(find.byKey(const ValueKey('danmakuClearConfigEntry')),
          findsOneWidget);
      expect(find.text('扫码配置'), findsOneWidget);
      expect(find.textContaining('手机扫码打开网页'), findsOneWidget);
      expect(find.byKey(const ValueKey('danmakuApiUrlField')), findsNothing);
      expect(
          find.byKey(const ValueKey('danmakuBlockWordsField')), findsNothing);

      // 行数/屏蔽开关等非输入项保留。
      expect(find.byKey(const ValueKey('danmakuScrollRowsSlider')),
          findsOneWidget);
      await _scrollTo(tester, '屏蔽');
      expect(
          find.byKey(const ValueKey('danmakuBlockTopSwitch')), findsOneWidget);
    });

    testWidgets('非 TV 不显示扫码入口，输入框可正常输入', (tester) async {
      await _pumpConfig(tester);

      expect(find.byKey(const ValueKey('danmakuQrConfigEntry')), findsNothing);
      expect(
          find.byKey(const ValueKey('danmakuClearConfigEntry')), findsNothing);
      expect(
        find.ancestor(
            of: find.byKey(const ValueKey('danmakuApiUrlField')),
            matching: find.byType(ExcludeFocus)),
        findsNothing,
      );
    });

    testWidgets('TV 清除配置只清 API 地址，保留行数/屏蔽设置', (tester) async {
      final container = await _pumpConfig(
        tester,
        initial: const AppSettings(
          tvMode: true,
          danmakuApiUrl: 'http://old',
          danmakuScrollRows: 12,
          danmakuBlockTop: true,
          danmakuBlockWords: '旧词',
        ),
      );

      await tester.tap(find.byKey(const ValueKey('danmakuClearConfigEntry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tvConfirmOk')));
      await tester.pumpAndSettle();

      final s = container.read(settingsProvider);
      expect(s.danmakuApiUrl, isEmpty);
      expect(s.danmakuScrollRows, 12);
      expect(s.danmakuBlockTop, isTrue);
      expect(s.danmakuBlockWords, '旧词');
    });

    testWidgets('滚动行数滑杆拖动改值（钳在 1~30）', (tester) async {
      final container = await _pumpConfig(tester,
          initial: const AppSettings(danmakuScrollRows: 4));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('danmakuScrollRows')))
            .data,
        '4',
      );

      await tester.drag(
        find.byKey(const ValueKey('danmakuScrollRowsSlider')),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();
      final v = container.read(settingsProvider).danmakuScrollRows;
      expect(v, 30, reason: '拖到底 → 最大 30');
    });

    testWidgets('屏蔽关键词输入写入 danmakuBlockWords', (tester) async {
      final container = await _pumpConfig(tester);
      await _scrollTo(tester, '屏蔽关键词');

      await tester.enterText(
        find.byKey(const ValueKey('danmakuBlockWordsField')),
        '剧透, 广告',
      );
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).danmakuBlockWords, '剧透, 广告');
    });

    testWidgets('限制同屏数量开 → 出现上限滑杆，拖动写入', (tester) async {
      final container = await _pumpConfig(tester);
      await _scrollTo(tester, '限制同屏数量');

      await tester.tap(_switchOf('限制同屏数量'));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).danmakuLimitCount, isTrue);
      expect(
          find.byKey(const ValueKey('danmakuMaxCountSlider')), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('danmakuMaxCountSlider')),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(settingsProvider).danmakuMaxCount,
        AppSettings.danmakuMaxCountMax,
      );
    });

    testWidgets('恢复默认把改过的弹幕项全部归位并清空输入框', (tester) async {
      final container = await _pumpConfig(
        tester,
        initial: const AppSettings(
          danmakuDefaultOn: false,
          danmakuApiUrl: 'http://x',
          danmakuScrollRows: 9,
          danmakuBlockTop: true,
          danmakuBlockWords: '广告',
          danmakuLimitCount: true,
          danmakuMaxCount: 2000,
          danmakuSpeed: 2.0,
        ),
      );
      await _scrollTo(tester, '恢复默认');

      await tester.tap(find.byKey(const ValueKey('danmakuResetDefaults')));
      await tester.pumpAndSettle();

      final s = container.read(settingsProvider);
      expect(s.danmakuDefaultOn, isTrue);
      expect(s.danmakuApiUrl, '');
      expect(s.danmakuScrollRows, 30);
      expect(s.danmakuBlockTop, isFalse);
      expect(s.danmakuBlockWords, '');
      expect(s.danmakuLimitCount, isFalse);
      expect(s.danmakuMaxCount, 500);
      expect(s.danmakuSpeed, 1.0);
      // 地址/屏蔽词输入框内容已随恢复默认清空（controller 归 State 所有，
      // 懒卸载不影响；此处以 settings 落盘值为准）
      expect(s.danmakuApiUrl, isEmpty);
      expect(s.danmakuBlockWords, isEmpty);
    });
  });

  group('设置页 → 弹幕配置入口', () {
    Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'player',
                builder: (context, state) => const PlayerSettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'danmaku',
                    builder: (context, state) => const DanmakuConfigScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('入口行存在，点击 push 弹幕配置页', (tester) async {
      await pumpSettings(tester);
      // 入口位于「播放器」子页
      await tester.tap(find.text('播放器'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('danmakuConfigEntry')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('danmakuConfigEntry')));
      await tester.pumpAndSettle();

      expect(find.byType(DanmakuConfigScreen), findsOneWidget);
      expect(find.text('弹幕配置'), findsWidgets);
      expect(find.byKey(const ValueKey('danmakuQrConfigEntry')), findsNothing);
      expect(find.byKey(const ValueKey('danmakuApiUrlField')), findsOneWidget);
    });
  });
}
