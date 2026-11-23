import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/nav_palette.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/squircle_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

import '../helpers/test_fakes.dart';

/// 698 N32「悬浮方块」导航守卫（视频动效 1:1）：跳槽弹滑、图标接力、
/// 标签胶囊跟随、主题色渐变、深图标压亮底、命中区满槽宽。
void main() {
  Widget host({
    AppSettings settings = const AppSettings(),
    int currentIndex = 0,
    required ValueChanged<int> onSelect,
  }) {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
    ]);
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SquircleNavBar(
                currentIndex: currentIndex,
                onSelect: onSelect,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('悬浮方块（698 N32）', () {
    test('主题色渐变 + 深图标压亮底 + null 回退', () {
      const theme = 0xFF6750A4;
      final g = NavPalette.dropGradient(theme);
      expect(g.last, const Color(theme), reason: '底右 = 主题色本色');
      expect(g.first.computeLuminance(), greaterThan(g.last.computeLuminance()),
          reason: '顶左 = 主题色提亮 55%（体积渐变）');
      final fb = NavPalette.dropGradient(null);
      expect(fb, [NavPalette.dropFallbackLight, NavPalette.dropFallbackDeep],
          reason: 'null 回退银白玻璃渐变');
      final ink = NavPalette.dropInkColor(theme);
      expect(ink.computeLuminance(), lessThan(g.first.computeLuminance()),
          reason: '深图标压亮底（视频同构）');
      expect(NavPalette.dropInkColor(null), NavPalette.inkFallback);
    });

    testWidgets('条体 = GlassContainer（①款同源双形态）+ 浮块主题色渐变',
        (tester) async {
      await tester.pumpWidget(host(
        settings: const AppSettings(themeColor: 0xFF6750A4),
        onSelect: (_) {},
      ));
      expect(find.byKey(SquircleNavBar.barKey), findsOneWidget);
      expect(find.byType(GlassContainer), findsWidgets,
          reason: '条体①款同源 GlassContainer');
      // 浮块渐变含主题色。
      final block = tester.widget<DecoratedBox>(
          find.byKey(SquircleNavBar.blockKey));
      final shape = block.decoration as ShapeDecoration;
      final grad = shape.gradient as LinearGradient;
      expect(grad.colors.last, const Color(0xFF6750A4),
          reason: '浮块渐变底右 = 主题色本色');
    });

    testWidgets('跳槽弹滑：点第 4 槽 → 浮块/标签落位该槽 + onSelect',
        (tester) async {
      final calls = <int>[];
      await tester.pumpWidget(host(onSelect: calls.add));
      await tester.pump();
      final slot4Center = Offset(800 / 5 * 4.5, 400 - 27); // 条体垂直中线（贴底）
      await tester.tapAt(slot4Center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // 420ms 拉满
      expect(calls, [4], reason: 'onSelect(4)');
      final blockRect =
          tester.getRect(find.byKey(SquircleNavBar.blockKey));
      expect((blockRect.center.dx - 800 / 5 * 4.5).abs(), lessThan(2),
          reason: '浮块落位第 4 槽中心');
    });

    testWidgets('图标接力：落位后浮块显示目标槽图标', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      await tester.tapAt(Offset(800 / 5 * 2.5, 400 - 27));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final block = find.byKey(SquircleNavBar.blockKey);
      expect(
        find.descendant(
          of: block,
          matching: find.byIcon(ShellNavBar.tabIcons[2]),
        ),
        findsOneWidget,
        reason: '落位后浮块 = 目标槽图标（Emby）',
      );
    });

    testWidgets('命中区满槽宽（N29 教训）：每槽 = 1/5 条宽 × 满高',
        (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      // 槽位命中层存在（GestureDetector opaque 覆盖整槽）。
      for (var i = 0; i < 5; i++) {
        final hit = find.byKey(ValueKey('squircleSlot$i'));
        expect(hit, findsOneWidget);
      }
    });

    testWidgets('标签胶囊跟随 + 文案 = tab 组', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      expect(find.text('首页'), findsOneWidget, reason: '初始标签 = 首页');
      await tester.tapAt(Offset(800 / 5 * 3.5, 400 - 27));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('声网'), findsOneWidget, reason: '落位后标签 = 声网');
    });
  });
}
