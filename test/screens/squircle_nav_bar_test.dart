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

    test('凹口恒距几何（N33）：入口宽 = 半宽 + 7、凹深 = 半高 + 7', () {
      expect(SquircleNavBar.notchGap, 7, reason: '浮块/标签与凹槽恒距 7dp');
      expect(SquircleNavBar.blockNotchRadius, 22 + 7,
          reason: '顶凹口半径 = 浮块半宽 + 间距');
      expect(SquircleNavBar.barRadius, lessThan(SquircleNavBar.navHeight / 2),
          reason: '圆角矩形（r18 < 半高 27，不是半圆胶囊）');
    });

    testWidgets('条体路径（N33）：圆角矩形 + 顶凹口托浮块 + 底凹口托标签，'
        '凹口随跳槽移动', (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      final w = 800.0;
      final slot0 = w / 5 * 0.5;
      final p0 = SquircleNavBar.barPath(
        size: Size(w, SquircleNavBar.navHeight),
        blockCx: slot0,
        labelCx: slot0,
        labelHalfWidth: SquircleNavBar.labelWidthOf('首页') / 2,
      );
      final b0 = p0.getBounds();
      expect(b0.width, closeTo(w, 1), reason: '条体满宽');
      expect(b0.height, closeTo(SquircleNavBar.navHeight, 1),
          reason: '条体高 = navHeight（圆角矩形）');
      final topNotchY = SquircleNavBar.blockCenterY +
          SquircleNavBar.block / 2 +
          SquircleNavBar.notchGap;
      expect(topNotchY, closeTo(37, 0.5),
          reason: '顶凹口底 = 浮块底 + 7dp 间距');
      // 凹口跟随：p0 在槽 0 → (80, 30) 处是凹口空腔（不在条内）；
      // p4 在槽 4 → 凹口移到 720，(80, 30) 变实心条体。
      expect(p0.contains(const Offset(80, 30)), isFalse,
          reason: '槽 0 凹口空腔（浮块正下方被挖空）');
      expect(p0.contains(const Offset(720, 30)), isTrue,
          reason: '非凹口区实心');
      final p4 = SquircleNavBar.barPath(
        size: Size(w, SquircleNavBar.navHeight),
        blockCx: w / 5 * 4.5,
        labelCx: w / 5 * 4.5,
        labelHalfWidth: SquircleNavBar.labelWidthOf('设置') / 2,
      );
      expect(p4.contains(const Offset(80, 30)), isTrue,
          reason: '凹口随跳槽移到槽 4 → 原位置变实心');
      expect(p4.contains(const Offset(720, 30)), isFalse,
          reason: '槽 4 凹口空腔');
      // 底凹口：标签正上方被挖空（条下缘 y=54，凹深 17 → 空腔到 y=37）。
      expect(p0.contains(const Offset(80, 50)), isFalse,
          reason: '底凹口空腔（标签正上方）');
    });

    testWidgets('浮块/标签骑跨条缘（N33）：块悬条上叠入顶凹口、标签骑条下缘',
        (tester) async {
      await tester.pumpWidget(host(onSelect: (_) {}));
      await tester.pump();
      // 全局坐标 → 盒内相对（宿主 400 高、盒 80 贴底 → 盒顶 = 320）。
      final boxTop = 400 - SquircleNavBar.boxHeight;
      final blockRect = tester.getRect(find.byKey(SquircleNavBar.blockKey));
      final bTop = blockRect.top - boxTop;
      final bBottom = blockRect.bottom - boxTop;
      expect(bTop, closeTo(14 + 8 - 22, 1), reason: '块心在条上缘附近');
      expect(bBottom, greaterThan(14),
          reason: '块底部叠入条体（顶凹口托住）');
      expect(bBottom, lessThan(14 + 54),
          reason: '块不穿出条下缘');
      final labelRect = tester.getRect(find.text('首页'));
      final lTop = labelRect.top - boxTop;
      final lBottom = labelRect.bottom - boxTop;
      expect(lTop, lessThan(14 + 54),
          reason: '标签顶部在条内（骑跨下缘）');
      expect(lBottom, greaterThan(14 + 54),
          reason: '标签底部露出条外（骑跨下缘）');
      expect(lBottom, lessThanOrEqualTo(SquircleNavBar.boxHeight + 1),
          reason: '标签不出盒底（N33 防屏幕裁切）');
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
