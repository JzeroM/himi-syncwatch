import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/squircle_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';

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
    test('玻璃水滴镜片参数（N34）：无色中性（不跟随主题色）', () {
      final settings = SquircleNavBar.lensSettings();
      expect(settings.glassColor.opacity, lessThan(0.12),
          reason: '无色中性白纱（α~0.08，折射透亮）');
      expect(settings.blur, greaterThan(0),
          reason: 'Skia 捕获钥匙（GlassEffect 门槛）');
    });

    testWidgets('条体 = GlassContainer（①款同源双形态）+ 浮块玻璃水滴'
        '（GlassEffect + 白图标，不跟主题色）', (tester) async {
      await tester.pumpWidget(host(
        settings: const AppSettings(
            glassUi: true, themeColor: 0xFF6750A4),
        onSelect: (_) {},
      ));
      expect(find.byKey(SquircleNavBar.barKey), findsOneWidget);
      expect(find.byType(GlassContainer), findsWidgets,
          reason: '条体①款同源 GlassContainer');
      // 浮块 = ①款同源 GlassEffect 玻璃水滴（真折射镜片）。
      expect(find.byType(GlassEffect), findsWidgets,
          reason: '浮块/标签 = ①款 LiquidBlobLens 同管线真折射镜片');
      // 图标白色（N34：不跟主题色）。
      final icons = tester
          .widgetList<Icon>(find.descendant(
            of: find.byKey(SquircleNavBar.blockKey),
            matching: find.byType(Icon),
          ))
          .toList();
      expect(icons, isNotEmpty);
      for (final icon in icons) {
        expect(icon.color, Colors.white, reason: '浮块内图标白色（①款风格）');
      }
    });

    testWidgets('玻璃关 = 平涂磨砂近似（零 GlassEffect）', (tester) async {
      await tester.pumpWidget(host(
        settings: const AppSettings(glassUi: false),
        onSelect: (_) {},
      ));
      expect(find.byType(GlassEffect), findsNothing,
          reason: '玻璃关零 shader');
      expect(find.byKey(SquircleNavBar.blockKey), findsOneWidget,
          reason: '平涂磨砂浮块保持');
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
      // N34：凹口 = 形体外扩轮廓（缘距 7dp 平行）——块侧缘 x±22 处
      // 凹口在 x±29（平行 7dp），点测验证。
      expect(p0.contains(Offset(slot0 - 25, 10)), isFalse,
          reason: '块左缘外 3dp 在凹口空腔内（外扩轮廓内侧）');
      expect(p0.contains(Offset(slot0 - 33, 10)), isTrue,
          reason: '块左缘外 11dp 已出凹口（外扩轮廓外侧实心）');
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
      expect(bBottom, lessThan(14 + SquircleNavBar.navHeight),
          reason: '块不穿出条下缘');
      final labelRect = tester.getRect(find.text('首页'));
      final lTop = labelRect.top - boxTop;
      final lBottom = labelRect.bottom - boxTop;
      expect(lTop, lessThan(14 + SquircleNavBar.navHeight),
          reason: '标签顶部在条内（骑跨下缘）');
      expect(lBottom, greaterThan(14 + SquircleNavBar.navHeight),
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
