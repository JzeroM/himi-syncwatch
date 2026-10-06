import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/widgets/glass_slider_theme.dart';

void main() {
  group('glassSliderTheme 主题构造', () {
    test('默认玻璃观：6px 轨道 + 玻璃 trackShape/thumbShape', () {
      final t = glassSliderTheme();
      expect(t.trackHeight, 6);
      expect(t.trackShape, isA<GlassSliderTrackShape>());
      expect(t.thumbShape, isA<GlassSliderThumbShape>());
      expect((t.thumbShape as GlassSliderThumbShape).radius, 8);
    });

    test('自定义 accent/尺寸透传', () {
      final t = glassSliderTheme(
        accent: const Color(0xFFFFD54F),
        trackHeight: 4,
        thumbRadius: 6,
        overlayRadius: 10,
      );
      expect(t.activeTrackColor, const Color(0xFFFFD54F));
      expect(t.trackHeight, 4);
      expect((t.thumbShape as GlassSliderThumbShape).radius, 6);
    });

    test('glassEnabled=false 回退纯色旧观（3px + RoundSliderThumbShape）', () {
      final t = glassSliderTheme(glassEnabled: false);
      expect(t.trackHeight, 3);
      expect(t.trackShape, isNot(isA<GlassSliderTrackShape>()));
      expect(t.thumbShape, isA<RoundSliderThumbShape>());
      expect(t.inactiveTrackColor, Colors.white24);
    });
  });

  group('绘制冒烟', () {
    Future<void> pumpSlider(
      WidgetTester tester, {
      required double value,
      required TextDirection textDirection,
      bool vertical = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: textDirection,
              child: Center(
                child: SizedBox(
                  width: 260,
                  height: vertical ? 160 : 40,
                  child: RotatedBox(
                    quarterTurns: vertical ? -1 : 0,
                    child: SliderTheme(
                      data: vertical
                          ? glassSliderTheme(accent: Colors.amber)
                          : glassSliderTheme(),
                      child: Slider(
                        value: value,
                        onChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('LTR 0% / 50% / 100% 三态绘制不抛异常', (tester) async {
      for (final v in [0.0, 0.5, 1.0]) {
        await pumpSlider(tester, value: v, textDirection: TextDirection.ltr);
        expect(tester.takeException(), isNull, reason: 'value=$v');
      }
    });

    testWidgets('RTL 绘制不抛异常', (tester) async {
      await pumpSlider(tester, value: 0.6, textDirection: TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('竖柱（RotatedBox -1）绘制不抛异常', (tester) async {
      await pumpSlider(
        tester,
        value: 0.4,
        textDirection: TextDirection.ltr,
        vertical: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
    });
  });
}
