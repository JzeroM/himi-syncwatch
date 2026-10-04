import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import '../helpers/test_fakes.dart';

Widget _wrap(Widget child, AppSettings settings) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
    ],
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('GlassContainer', () {
    testWidgets('开启玻璃时渲染包折射玻璃底与子组件', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassContainer(child: Text('面板内容')),
          const AppSettings(glassUi: true),
        ),
      );

      // 真折射由 liquid_glass_widgets 承担（v1.1.84 起取代 BackdropFilter）
      expect(find.byType(lg.GlassContainer), findsOneWidget);
      expect(find.text('面板内容'), findsOneWidget);
      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('关闭玻璃时降级为纯色，不渲染任何玻璃层', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassContainer(child: Text('面板内容')),
          const AppSettings(glassUi: false),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(lg.GlassContainer), findsNothing);
      expect(find.text('面板内容'), findsOneWidget);

      final decoration = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(ClipRRect),
          matching: find.byType(DecoratedBox),
        ),
      );
      final box = decoration.decoration as BoxDecoration;
      expect(box.color, GlassConfig.fallbackColor);
      expect(box.gradient, isNull);
    });

    testWidgets('开启玻璃时面板带本层悬浮投影', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassContainer(child: Text('面板内容')),
          const AppSettings(glassUi: true),
        ),
      );

      expect(_hasOwnPanelShadow(tester), isTrue);
    });

    testWidgets('showShadow 为 false 时不绘制本层悬浮投影', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassContainer(
            showShadow: false,
            child: Text('面板内容'),
          ),
          const AppSettings(glassUi: true),
        ),
      );

      // 只认 GlassConfig.panelShadow 精确样式（包玻璃内部装饰不计）
      expect(_hasOwnPanelShadow(tester), isFalse);
      expect(find.text('面板内容'), findsOneWidget);
    });

    testWidgets('玻璃着色为三段渐变（上亮、中主体、下透）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassContainer(child: Text('面板内容')),
          const AppSettings(glassUi: true),
        ),
      );

      final boxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .toList();
      expect(
        boxes.any((b) {
          final g = b.gradient;
          return g is LinearGradient && g.colors.length == 3;
        }),
        isTrue,
        reason: '本层着色为三段渐变（上亮、中主体、下透）',
      );
    });
  });

  group('GlassBackdrop', () {
    testWidgets('开启玻璃时渲染 BackdropFilter', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassBackdrop(),
          const AppSettings(glassUi: true),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.byType(ClipRect), findsOneWidget);
    });

    testWidgets('关闭玻璃时降级为纯色条', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassBackdrop(),
          const AppSettings(glassUi: false),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('GlassRimPainter', () {
    test('尺寸为空时不抛异常', () {
      const painter = GlassRimPainter(BorderRadius.all(Radius.circular(12)));
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, Size.zero);
      expect(
          painter.shouldRepaint(
              const GlassRimPainter(BorderRadius.all(Radius.circular(12)))),
          isFalse);
      expect(
        painter.shouldRepaint(
            const GlassRimPainter(BorderRadius.all(Radius.circular(20)))),
        isTrue,
      );
    });
  });

  group('GlassConfig', () {
    test('饱和度矩阵为 4x5 结构且中性色不偏移', () {
      final m = GlassConfig.saturationMatrix(1.0);
      expect(m.length, 20);
      // s=1 时为单位阵
      expect(m[0], closeTo(1.0, 1e-9));
      expect(m[6], closeTo(1.0, 1e-9));
      expect(m[12], closeTo(1.0, 1e-9));
      expect(m[18], 1);
      expect(m[19], 0);
    });

    test('blur 与饱和增强可合成滤镜', () {
      expect(GlassConfig.filter(), isA<ImageFilter>());
      expect(GlassConfig.blurSigma, 20);
      expect(GlassConfig.saturation, 1.6);
    });

    test('底部预留高度为常量', () {
      expect(GlassConfig.shellBottomReserve, 96);
    });

    test('玻璃着色透明度约 12%，背景尽量透出', () {
      expect(GlassConfig.panelTint.a, closeTo(0x1F / 255, 0.001));
      expect(GlassConfig.barTint.a, closeTo(0x1F / 255, 0.001));
      expect(GlassConfig.barTintSoft.a, closeTo(0x12 / 255, 0.001));
      expect(GlassConfig.panelTint.a, lessThan(0.3));
      expect(GlassConfig.barTint.a, lessThan(0.3));
    });
  });
}

/// 本层悬浮投影（GlassConfig.panelShadow）是否存在——按样式精确匹配，
/// 避免把包玻璃内部装饰误判为投影。
bool _hasOwnPanelShadow(WidgetTester tester) {
  final panels = GlassConfig.panelShadow;
  return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((d) {
    final box = d.decoration;
    if (box is! BoxDecoration) return false;
    final shadow = box.boxShadow;
    if (shadow == null || shadow.length != panels.length) return false;
    for (var i = 0; i < shadow.length; i++) {
      if (shadow[i].color != panels[i].color ||
          shadow[i].blurRadius != panels[i].blurRadius ||
          shadow[i].offset != panels[i].offset) {
        return false;
      }
    }
    return true;
  });
}
