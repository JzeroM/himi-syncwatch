import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/poster_backdrop.dart';

/// 698 N50：纯三带色场（7 段氛围编排、原色、无模糊/无暗角）守卫。
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

List<DecoratedBox> _layers(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.descendant(
      of: find.byType(PosterBackdrop),
      matching: find.byType(DecoratedBox),
    ))
    .toList();

/// 测试内写入海报 URL → 推进取色异步链（toImage 真异步须 runAsync）。
Future<void> _setUrl(WidgetTester tester, String url) async {
  final container =
      ProviderScope.containerOf(tester.element(find.byType(PosterBackdrop)));
  container.read(heroPosterUrlProvider.notifier).state = url;
  await tester.pump();
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
}

void main() {
  setUp(() {
    PosterPalette.debugReset();
    PosterPalette.debugImageLoader = (url, {headers}) => _bandImage();
  });
  tearDown(PosterPalette.debugReset);

  testWidgets('回退态（无海报 URL）：纯平色基底（N50 极简，无暗角聚光）',
      (tester) async {
    await tester.pumpWidget(_app(isDark: true));

    final layers = _layers(tester);
    expect(layers, hasLength(1), reason: 'N50 极简：仅平色单层');
    final base = layers.first.decoration! as BoxDecoration;
    expect(base.color, isNotNull);
    expect(base.gradient, isNull);
  });

  testWidgets('取色态：7 段氛围色场 + 顶段=底缘原色（零分割）', (tester) async {
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://a/p.jpg');

    final field = _layers(tester)
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .firstOrNull;
    expect(field, isNotNull, reason: '色场渲染');
    expect(field!.colors, hasLength(7), reason: 'N50 七段氛围编排');
    expect(field.stops, orderedEquals(<double>[0.0, 0.08, 0.28, 0.48, 0.70, 0.88, 1.0]),
        reason: '氛围节奏锁');

    // 零分割：顶段 = 底缘带（黄）原色（无派生、无混色）。
    final top = field.colors.first;
    expect(HSLColor.fromColor(top).hue, inInclusiveRange(35, 65),
        reason: '顶段 = 底缘黄带（同源）');
    // 原色保真：无混黑/混白（饱和与原带一致量级）。
    expect(HSLColor.fromColor(top).saturation, greaterThan(0.5),
        reason: 'N50 原色鲜活（无派生压暗）');
  });

  testWidgets('N50 极简：无模糊层无暗角层（ImageFiltered/径向渐变为零）',
      (tester) async {
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://d/p.jpg');

    expect(find.byType(ImageFiltered), findsNothing, reason: '无模糊氛围层');
    final radial = _layers(tester)
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<RadialGradient>()
        .length;
    expect(radial, 0, reason: '无暗角聚光');
  });

  testWidgets('N48 保持旧场：新海报取色未就绪时不闪平色', (tester) async {
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://old/p.jpg');
    LinearGradient? fieldOf() => _layers(tester)
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .firstOrNull;
    expect(fieldOf(), isNotNull, reason: '旧场已渲染');

    PosterPalette.debugImageLoader = (url, {headers}) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return _bandImage();
    };
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PosterBackdrop)));
    container.read(heroPosterUrlProvider.notifier).state = 'https://new/p.jpg';
    await tester.pump();

    final mid = fieldOf();
    expect(mid, isNotNull, reason: 'N48 取色未就绪保持旧场（不闪平色）');
    expect(HSLColor.fromColor(mid!.colors.first).hue, inInclusiveRange(35, 65),
        reason: '仍为旧场衔接色（黄带）');

    // drain 慢 loader 的 pending timer（fake async 200ms delayed）。
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
  });

  testWidgets('轮播切换交叉淡化：AnimatedSwitcher 600ms', (tester) async {
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://c/p.jpg');
    final sw = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(sw.duration, const Duration(milliseconds: 600));
  });
}
