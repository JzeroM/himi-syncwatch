import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/fluid_glass_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/nav_bar_registry.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:liquid_glass_widgets/widgets/shared/glass_effect.dart';

import '../helpers/test_fakes.dart';

/// 698 N15/N17 导航栏样式注册表守卫：注册表分发 / 悬浮凹口款双玻璃形态 /
/// 凹口形状 / 动作语义。
void main() {
  Widget host({required AppSettings settings, required Widget nav}) {
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
            child: Align(alignment: Alignment.bottomCenter, child: nav),
          ),
        ),
      ),
    );
  }

  group('样式注册表（698 N15-E）', () {
    test('解析容错：未知/空值回默认玻璃水滴款', () {
      expect(NavBarStyle.parse(null), NavBarStyle.glassCapsule);
      expect(NavBarStyle.parse('nonsense'), NavBarStyle.glassCapsule);
      expect(NavBarStyle.parse('fluidGlass'), NavBarStyle.fluidGlass);
    });

    testWidgets('按设置分发：glassCapsule→ShellNavBar、fluidGlass→FluidGlassNavBar',
        (tester) async {
      await tester.pumpWidget(host(
        settings: const AppSettings(navBarStyle: 'glassCapsule'),
        nav: const NavBarStyleHost(currentIndex: 0, onSelect: _noop),
      ));
      expect(find.byType(ShellNavBar), findsOneWidget);

      await tester.pumpWidget(host(
        settings: const AppSettings(navBarStyle: 'fluidGlass'),
        nav: const NavBarStyleHost(currentIndex: 0, onSelect: _noop),
      ));
      expect(find.byType(FluidGlassNavBar), findsOneWidget);
    });
  });

  group('悬浮凹口款（698 N17）', () {
    testWidgets('双玻璃形态（N22 回归）：开=折射条+玻璃球滴，关=磨砂条+平涂滴',
        (tester) async {
      // 开：液态玻璃（GlassContainer 折射胶囊 + GlassEffect 真折射水滴）。
      await tester.pumpWidget(host(
        settings: const AppSettings(glassUi: true),
        nav: const FluidGlassNavBar(currentIndex: 0, onSelect: _noop),
      ));
      expect(find.byKey(FluidGlassNavBar.glassBallsKey), findsOneWidget,
          reason: '玻璃开 = GlassEffect 真折射水滴层');
      expect(find.byType(GlassEffect), findsWidgets,
          reason: '真折射（透亮 + 色散），非磨砂');
      expect(find.byKey(FluidGlassNavBar.flatDropsKey), findsNothing);
      expect(find.byKey(FluidGlassNavBar.dropMotherKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(FluidGlassNavBar.barKey),
          matching: find.byType(GlassContainer),
        ),
        findsOneWidget,
        reason: '玻璃开 = 折射胶囊（N19 下缘修复保留）',
      );

      // 关：轻量磨砂（磨砂白 30% 条 + 平涂滴，零折射/球内 blur）。
      await tester.pumpWidget(host(
        settings: const AppSettings(glassUi: false),
        nav: const FluidGlassNavBar(currentIndex: 0, onSelect: _noop),
      ));
      expect(find.byKey(FluidGlassNavBar.flatDropsKey), findsOneWidget,
          reason: '玻璃关 = 平涂磨砂滴层（零 blur 省性能）');
      expect(find.byKey(FluidGlassNavBar.glassBallsKey), findsNothing);
      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsOneWidget,
          reason: '玻璃关 = 条体轻量磨砂（球内无 blur）');
    });

    test('凹口弧与母滴同心、恒距 4dp（正好包裹下半部分）', () {
      expect(
        FluidGlassNavBar.notchRadius - FluidGlassNavBar.motherSize / 2,
        FluidGlassNavBar.notchGap,
        reason: '凹口弧半径 = 母滴 R + 恒定间距（严格同心）',
      );
      const cx = 400.0;
      const mcy = FluidGlassNavBar.motherCenterY;
      const nr = FluidGlassNavBar.notchRadius;
      final path = FluidGlassNavBar.notchBarPath(size: const Size(800, 54));
      // 弧内外 3dp：恒距 4dp 缝隙语义（弧内凹口空腔、弧外条体）。
      expect(path.contains(const Offset(cx, mcy + nr - 3)), isFalse,
          reason: '弧内 3dp 在凹口空腔（母滴嵌入处）');
      expect(path.contains(const Offset(cx, mcy + nr + 3)), isTrue,
          reason: '弧外 3dp 在条体内（4dp 呼吸缝）');
      // 侧向包裹到母滴水平中心线（下半圆范围）。
      expect(path.contains(Offset(cx - nr + 3, mcy)), isFalse,
          reason: '凹口包裹到母滴水平中心线（左）');
      expect(path.contains(Offset(cx + nr - 3, mcy)), isFalse,
          reason: '凹口包裹到母滴水平中心线（右）');
    });

    test('透镜叶形轮廓：顶缘八字拱（中央高两端低）+ 底缘微下拱', () {
      final path = FluidGlassNavBar.notchBarPath(size: const Size(800, 54));
      const cx = 400.0;
      // 顶缘中央峰：y≈0 有料、y=-2 无料。
      expect(path.contains(const Offset(cx + 60, 3)), isTrue,
          reason: '中央顶缘高（峰下有料）');
      expect(path.contains(const Offset(cx + 60, -2)), isFalse,
          reason: '中央顶缘高（峰上无料）');
      // 顶缘端部低（topArch=4）：y=2 无料、y=6 有料。
      const rightEndX = 800.0 - (54 - FluidGlassNavBar.topArch) / 2;
      expect(path.contains(const Offset(rightEndX - 1, 2)), isFalse,
          reason: '端部顶缘低（八字拱落下）');
      expect(path.contains(const Offset(rightEndX - 1, 6)), isTrue);
      // 底缘下拱：中央垂（54+3.5）、端部高（54）。
      expect(path.contains(const Offset(cx, 56)), isTrue,
          reason: '底缘中央微下拱');
      expect(path.contains(const Offset(cx, 58.5)), isFalse,
          reason: '中央底缘 ≤ 57.5');
      expect(path.contains(const Offset(26, 55)), isFalse,
          reason: '端部底缘 54（拱回）');
    });

    test('几何常量：子滴 ≈ 母滴 1.35×、扇形落位中心略高（视频像素实测）', () {
      expect(FluidGlassNavBar.childScaleRatio, closeTo(1.35, 0.1),
          reason: '视频实测 74/54 ≈ 1.37');
      final l = FluidGlassNavBar.childTarget(0, totalWidth: 800);
      final c = FluidGlassNavBar.childTarget(1, totalWidth: 800);
      final r = FluidGlassNavBar.childTarget(2, totalWidth: 800);
      expect(c.dy, lessThan(l.dy), reason: '中心子滴略高（上浮弧线）');
      expect((l.dx - 400).abs(), closeTo((r.dx - 400).abs(), 0.01),
          reason: '左右对称');
      expect(l.dx, lessThan(400));
      expect(r.dx, greaterThan(400));
    });

    test('动作语义：左→右 = Emby(2) / 声网(3) / 设置(4)', () {
      expect(FluidGlassNavBar.actionBranch(0), 2);
      expect(FluidGlassNavBar.actionBranch(1), 3);
      expect(FluidGlassNavBar.actionBranch(2), 4);
    });

    test('三动作钮语义 = ShellNavBar.tab 组 2..4（Emby/声网/设置）', () {
      expect(ShellNavBar.tabLabels.sublist(2, 5), ['Emby', '声网', '设置']);
      expect(FluidGlassNavBar.actionKeys.length, 3);
    });
  });
}

void _noop(int _) {}
