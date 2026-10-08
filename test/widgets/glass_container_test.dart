import 'dart:io';

import 'package:flutter/foundation.dart';
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

      // 只认 GlassConfig.panelShadowOf() 精确样式（包玻璃内部装饰不计）
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

    testWidgets('玻璃开启时不再叠本层白描边（v1.1.85 弱化）', (tester) async {
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
      expect(boxes.any((b) => b.border != null), isFalse,
          reason: '包折射自带菲涅尔边缘，本层白描边压灰观感');
    });

    testWidgets('纯色降级态保留 rim 边线定界', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassContainer(child: Text('面板内容')),
          const AppSettings(glassUi: false),
        ),
      );

      final boxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .toList();
      expect(
        boxes.any((b) => b.border?.top.color == GlassConfig.rimColor),
        isTrue,
        reason: '关闭玻璃后不透明纯色需要边线与背景区分',
      );
    });
  });

  group('GlassBackdrop', () {
    testWidgets('开启玻璃时渲染包真折射玻璃条', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassBackdrop(),
          const AppSettings(glassUi: true),
        ),
      );
      expect(find.byType(lg.GlassContainer), findsOneWidget);
      expect(find.byType(ClipRect), findsOneWidget);
      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: 'v1.1.85 起顶栏由包折射管线取代 BackdropFilter',
      );
    });

    testWidgets('关闭玻璃时降级为纯色条', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GlassBackdrop(),
          const AppSettings(glassUi: false),
        ),
      );
      expect(find.byType(lg.GlassContainer), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('玻璃着色按平台（iOS 更淡，尽量透）', () {
    Color midTint(WidgetTester tester) {
      final boxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>();
      final g = boxes
          .map((b) => b.gradient)
          .whereType<LinearGradient>()
          .firstWhere((g) => g.colors.length == 3);
      return g.colors[1];
    }

    testWidgets('iOS 用更淡默认 tint（约 5%，低于 12%）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(_wrap(
        const GlassContainer(child: Text('面板内容')),
        const AppSettings(glassUi: true),
      ));
      expect(midTint(tester), GlassConfig.panelTintIos);
      expect(GlassConfig.panelTintIos.a, lessThan(GlassConfig.panelTint.a));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Android 沿用原 tint（约 12%）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(_wrap(
        const GlassContainer(child: Text('面板内容')),
        const AppSettings(glassUi: true),
      ));
      expect(midTint(tester), GlassConfig.panelTint);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('调用方自定义 tint 不被平台默认覆盖', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const custom = Color(0x55ABCDEF);
      await tester.pumpWidget(_wrap(
        const GlassContainer(tint: custom, child: Text('面板内容')),
        const AppSettings(glassUi: true),
      ));
      expect(midTint(tester), custom);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('GlassRimPainter / GlassConfig 旧滤镜死代码已移除', () {
    test('GlassRimPainter、filter()、saturationMatrix() 无残留（观感清理）', () {
      final container = File('lib/widgets/glass/glass_container.dart')
          .readAsStringSync();
      expect(container.contains('GlassRimPainter'), isFalse,
          reason: 'GlassRimPainter 仅测试引用，已为死代码');
      final config =
          File('lib/widgets/glass/glass_config.dart').readAsStringSync();
      expect(config.contains('static List<double> saturationMatrix'), isFalse,
          reason: '旧 BackdropFilter 饱和矩阵已被包折射管线取代');
      expect(config.contains('static ImageFilter filter('), isFalse,
          reason: '旧模糊+饱和合成滤镜已无调用方');
      expect(config.contains('static const double blurSigma'), isFalse,
          reason: '旧滤镜的模糊半径常量一并移除');
      expect(config.contains('innerRimColor'), isFalse,
          reason: '内圈暗线随 GlassRimPainter 一并移除');
    });
  });

  group('GlassConfig', () {
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

    test('[PATCH himi] iOS 投影更轻、顶栏描边更淡（降「脏/边框感」）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(GlassConfig.panelShadowOf(), GlassConfig.panelShadowIos);
      expect(GlassConfig.panelShadowIos.first.color.a,
          lessThan(GlassConfig.panelShadow.first.color.a),
          reason: 'iOS 29% → 16% 黑投影');
      expect(GlassConfig.rimColorOf(), GlassConfig.rimColorIos);
      expect(GlassConfig.rimColorIos.a, lessThan(GlassConfig.rimColor.a),
          reason: 'iOS 顶栏底边白线 30% → 16%');
    });

    test('Android 沿用原投影与描边（观感不变）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(GlassConfig.panelShadowOf(), GlassConfig.panelShadow);
      expect(GlassConfig.rimColorOf(), GlassConfig.rimColor);
    });
  });
}

/// 本层悬浮投影（GlassConfig.panelShadowOf()）是否存在——按样式精确匹配，
/// 避免把包玻璃内部装饰误判为投影。
bool _hasOwnPanelShadow(WidgetTester tester) {
  final panels = GlassConfig.panelShadowOf();
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
