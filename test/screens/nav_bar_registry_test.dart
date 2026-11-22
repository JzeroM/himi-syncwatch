import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/shell/fluid_glass_nav_bar.dart';
import 'package:himi_syncwatch/screens/shell/nav_bar_registry.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart';
import 'package:himi_syncwatch/widgets/glass/blob_lens.dart';

import '../helpers/test_fakes.dart';

/// 698 N15 导航栏样式注册表守卫：注册表分发 / 流体款双玻璃形态 / 弹性参数。
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
            height: 200,
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

  group('流体液态款（698 N15-F/G）', () {
    testWidgets('双玻璃形态：开=液镜折射（LiquidBlobLens），关=轻量磨砂（零折射）',
        (tester) async {
      // 开：真折射液镜。
      await tester.pumpWidget(host(
        settings: const AppSettings(glassUi: true),
        nav: const FluidGlassNavBar(currentIndex: 0, onSelect: _noop),
      ));
      expect(find.byType(LiquidBlobLens), findsOneWidget,
          reason: '玻璃开 = 液镜折射（LiquidBlobLens）');
      expect(find.byType(BackdropFilter), findsNothing,
          reason: '折射形态不做磨砂兜底');

      // 关：轻量磨砂（模糊 + 半透明 + 描边 + 微光圈，零折射）。
      await tester.pumpWidget(host(
        settings: const AppSettings(glassUi: false),
        nav: const FluidGlassNavBar(currentIndex: 0, onSelect: _noop),
      ));
      expect(find.byType(LiquidBlobLens), findsNothing,
          reason: '玻璃关 = 零折射（性能优先）');
      expect(find.byKey(const ValueKey('fluidNavBlob')), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget,
          reason: '轻量磨砂：模糊质感（玻璃乙形态）');
      final blob = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('fluidNavBlob')),
      );
      expect(blob.decoration, isA<ShapeDecoration>());
      expect((blob.decoration as ShapeDecoration).shape, isA<OvalBorder>(),
          reason: '698 N15-C：液滴正椭圆');
    });

    test('弹性参数在位（bouncy 过冲 + 拉伸增益 + 图标弹跳）', () {
      expect(FluidGlassNavBar.stretchGain, greaterThan(1.0),
          reason: '速度拉伸比水滴款夸张（液态感）');
      expect(FluidGlassNavBar.iconBounce, greaterThan(1.0),
          reason: '选中图标弹跳放大');
    });
  });
}

void _noop(int _) {}
