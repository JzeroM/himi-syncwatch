import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/poster_backdrop.dart';

/// 698 N46：海报底部三带取色色场 + 明暗保色派生 + 暗角聚光守卫。
Future<ui.Image> _bandImage() async {
  // 10×10 三带三色（floor 半开）：y9 黄 / y7-8 红 / y6 蓝（带外黑）。
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 10, 10), Paint()..color = const Color(0xFF000000));
  canvas.drawRect(const Rect.fromLTWH(0, 6, 10, 1), Paint()..color = const Color(0xFF1E2878));
  canvas.drawRect(const Rect.fromLTWH(0, 7, 10, 2), Paint()..color = const Color(0xFFC83C32));
  canvas.drawRect(const Rect.fromLTWH(0, 9, 10, 1), Paint()..color = const Color(0xFFDCB428));
  final picture = recorder.endRecording();
  final image = await picture.toImage(10, 10);
  picture.dispose();
  return image;
}

Widget _app({required bool isDark}) => ProviderScope(
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: const Scaffold(body: PosterBackdrop(base: Color(0xFFF4F5F7))),
      ),
    );

/// 测试内写入海报 URL（非 build 期，安全）→ 推进取色异步链。
/// toImage/toByteData 为真异步（engine 交互），须 runAsync 打通事件循环。
Future<void> _setUrl(WidgetTester tester, String url) async {
  final container =
      ProviderScope.containerOf(tester.element(find.byType(PosterBackdrop)));
  container.read(heroPosterUrlProvider.notifier).state = url;
  await tester.pump();
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
}

List<DecoratedBox> _layers(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.descendant(
      of: find.byType(PosterBackdrop),
      matching: find.byType(DecoratedBox),
    ))
    .toList();

void main() {
  setUp(() {
    PosterPalette.debugReset();
    PosterPalette.debugImageLoader = (url, {headers}) => _bandImage();
  });
  tearDown(PosterPalette.debugReset);

  testWidgets('回退态（无海报 URL）：平色基底 + 暗角聚光双层', (tester) async {
    await tester.pumpWidget(_app(isDark: true));

    final layers = _layers(tester);
    final base = layers.first.decoration! as BoxDecoration;
    expect(base.color, isNotNull, reason: '回退平色底');
    expect(base.gradient, isNull, reason: '无织物渐变（N46 已移除）');
    final gradients = layers
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<Gradient>()
        .length;
    expect(gradients, greaterThanOrEqualTo(2), reason: '暗角 + 聚光双层');
  });

  testWidgets('取色态（暗版）：三段色场 + L 钳 0.25~0.45 保色', (tester) async {
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://a/p.jpg');

    final field = _layers(tester)
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .firstOrNull;
    expect(field, isNotNull, reason: '色场渐变渲染');
    expect(field!.colors, hasLength(3), reason: '三带三段色场');
    for (final c in field.colors) {
      // ±0.006：8bit 量化容差（255 分度 round 边界）。
      final l = HSLColor.fromColor(c).lightness;
      expect(l, greaterThanOrEqualTo(0.244), reason: '暗版 L≥0.25 不压死色相');
      expect(l, lessThanOrEqualTo(0.456), reason: '暗版 L≤0.45 不刺眼');
    }
    // 顶段衔接色来自底缘黄带（黄相）——零分割关键。
    expect(HSLColor.fromColor(field.colors.first).hue, inInclusiveRange(35, 65),
        reason: '顶段 = 海报底缘色（黄带）');
  });

  testWidgets('取色态（亮版）：L 钳 0.65~0.85 保色', (tester) async {
    await tester.pumpWidget(_app(isDark: false));
    await _setUrl(tester, 'https://b/p.jpg');

    final field = _layers(tester)
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .firstOrNull;
    expect(field, isNotNull);
    for (final c in field!.colors) {
      // ±0.006：8bit 量化容差（255 分度 round 边界）。
      final l = HSLColor.fromColor(c).lightness;
      expect(l, greaterThanOrEqualTo(0.644), reason: '亮版 L≥0.65 不发灰');
      expect(l, lessThanOrEqualTo(0.856), reason: '亮版 L≤0.85 不洗白刺眼');
    }
  });

  testWidgets('轮播切换交叉淡化：AnimatedSwitcher 600ms', (tester) async {
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://c/p.jpg');
    final sw = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(sw.duration, const Duration(milliseconds: 600));
  });

  testWidgets('N48 保持旧场：新海报取色未就绪时不闪平色', (tester) async {
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://old/p.jpg');
    // 旧场就绪（黄顶衔接色）。
    LinearGradient? fieldOf() => _layers(tester)
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .firstOrNull;
    expect(fieldOf(), isNotNull, reason: '旧场已渲染');

    // 切新海报 + 挂起取色（loader 慢）——未就绪期间应保持旧场。
    PosterPalette.debugImageLoader = (url, {headers}) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return _bandImage();
    };
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PosterBackdrop)));
    container.read(heroPosterUrlProvider.notifier).state = 'https://new/p.jpg';
    await tester.pump();

    // 交叉淡化进行中（旧场淡出 + 新 field lastTrio 保持旧色）。
    final mid = fieldOf();
    expect(mid, isNotNull, reason: 'N48 取色未就绪保持旧场（不闪平色）');
    expect(HSLColor.fromColor(mid!.colors.first).hue,
        inInclusiveRange(35, 65),
        reason: '仍为旧场衔接色（黄带）');

    // drain 慢 loader 的 pending timer（fake async 200ms delayed）。
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
  });

  testWidgets('N49 模糊海报氛围层在（首页同款公式，全局统一）', (tester) async {
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://ambient/p.jpg');
    expect(find.byType(ImageFiltered), findsWidgets,
        reason: 'N49 模糊氛围层（blur σ36 首页同款公式）全局渲染');
  });

  testWidgets('暗角聚光层叠于色场之上（取色态同构）', (tester) async {
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://d/p.jpg');

    final layers = _layers(tester);
    final radial = layers
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<RadialGradient>()
        .length;
    expect(radial, greaterThanOrEqualTo(2), reason: '暗角 + 聚光均为径向渐变');
  });
}
