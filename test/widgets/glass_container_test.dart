import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';

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
    testWidgets('开启玻璃时渲染 BackdropFilter 与子组件', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassContainer(child: Text('面板内容')),
          const AppSettings(glassUi: true),
        ),
      );

      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('面板内容'), findsOneWidget);
      expect(find.byType(ClipRRect), findsOneWidget);
    });

    testWidgets('关闭玻璃时降级为纯色，不产生 BackdropFilter', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassContainer(child: Text('面板内容')),
          const AppSettings(glassUi: false),
        ),
      );

      expect(find.byType(BackdropFilter), findsNothing);
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

    testWidgets('开启玻璃时面板带悬浮投影', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassContainer(child: Text('面板内容')),
          const AppSettings(glassUi: true),
        ),
      );

      final decorations = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(GlassContainer),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        decorations.any((d) {
          final box = d.decoration as BoxDecoration;
          return box.boxShadow != null && box.boxShadow!.isNotEmpty;
        }),
        isTrue,
      );
    });

    testWidgets('玻璃着色为三段渐变（上亮、中主体、下透）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassContainer(child: Text('面板内容')),
          const AppSettings(glassUi: true),
        ),
      );

      final decoration = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(ClipRRect),
          matching: find.byType(DecoratedBox),
        ),
      );
      final box = decoration.decoration as BoxDecoration;
      expect(box.gradient, isA<LinearGradient>());
      expect((box.gradient! as LinearGradient).colors.length, 3);
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
      expect(painter.shouldRepaint(const GlassRimPainter(
          BorderRadius.all(Radius.circular(12)))), isFalse);
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

    test('玻璃着色透明度约 25%，背景尽量透出', () {
      expect(GlassConfig.panelTint.a, closeTo(0x40 / 255, 0.001));
      expect(GlassConfig.barTint.a, closeTo(0x40 / 255, 0.001));
      expect(GlassConfig.barTintSoft.a, closeTo(0x26 / 255, 0.001));
      expect(GlassConfig.panelTint.a, lessThan(0.3));
      expect(GlassConfig.barTint.a, lessThan(0.3));
    });
  });
}
