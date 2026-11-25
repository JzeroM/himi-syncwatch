import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/poster_backdrop.dart';

/// 测试用图片 provider（可控就绪时机）。
class _FakeImageProvider extends ImageProvider<_FakeImageProvider> {
  _FakeImageProvider(this.image, {this.completer});

  final ui.Image image;
  final Completer<ImageInfo>? completer;

  @override
  Future<_FakeImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_FakeImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      _FakeImageProvider key, ImageDecoderCallback decode) {
    if (completer != null) {
      return OneFrameImageStreamCompleter(completer!.future);
    }
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
    );
  }
}

/// 红色主导海报图（含近白/近黑/近灰干扰像素）。
Future<ui.Image> _posterImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 24), Paint()..color = const Color(0xFFCC4422));
  // 干扰像素：近白/近黑/近灰（须被过滤）。
  canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawRect(const Rect.fromLTWH(1, 0, 1, 1), Paint()..color = const Color(0xFF030303));
  canvas.drawRect(const Rect.fromLTWH(2, 0, 1, 1), Paint()..color = const Color(0xFF808080));
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 24);
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
  final fake = <String, _FakeImageProvider>{};

  setUp(() {
    PosterPalette.debugReset();
    fake.clear();
  });
  tearDown(PosterPalette.debugReset);

  group('computeDominant（N53 spec）', () {
    test('过滤：近白/近黑/近灰剔除，红主导簇胜出', () {
      final rgba = Uint8List(10 * 10 * 4);
      for (var i = 0; i < 100; i++) {
        final o = i * 4;
        // 70% 红主导 + 30% 干扰（近白/近黑/近灰各 10%）。
        final r = (i % 10 < 7) ? 200 : 128;
        final g = (i % 10 < 7) ? 60 : 128;
        final b = (i % 10 < 7) ? 50 : 128;
        rgba[o] = (i % 10 >= 7 && i % 10 < 8) ? 250 : r;
        rgba[o + 1] = (i % 10 >= 8 && i % 10 < 9) ? 2 : g;
        rgba[o + 2] = b;
        rgba[o + 3] = 255;
      }
      final (dom, _) = PosterPalette.computeDominant(rgba, 10, 10);
      final hsl = HSLColor.fromColor(dom);
      expect(hsl.hue, inInclusiveRange(0, 30), reason: '红主导簇（干扰剔除）');
    });

    test('ambientTrio（spec 派生）：L 压区/S 收敛/深色保底', () {
      final (top, mid, base) = PosterPalette.ambientTrio(
          const Color(0xFFCC4422), null);
      final t = HSLColor.fromColor(top);
      // ±0.006 8bit 量化容差
      expect(t.lightness, inInclusiveRange(0.104, 0.186), reason: 'L 压 0.11~0.18');
      expect(t.saturation, lessThanOrEqualTo(0.46), reason: 'S 上限 0.46');
      expect(HSLColor.fromColor(mid).lightness, closeTo(0.20, 0.006));
      expect(HSLColor.fromColor(base).lightness, closeTo(0.14, 0.006));
      // 深色保底：L<0.12 的 dominant → 提 0.16。
      final (darkTop, _, _) = PosterPalette.ambientTrio(
          const Color(0xFF141010), null);
      expect(HSLColor.fromColor(darkTop).lightness, closeTo(0.16, 0.006),
          reason: '深色保底提 0.16（防丢色相）');
    });
  });

  testWidgets('N53 渐变遮罩场：短色弧 S 曲线 + 自适应压暗 + 无模糊', (tester) async {
    final image = await _posterImage();
    debugAmbientImageProvider =
        (url) => fake[url] ??= _FakeImageProvider(image);
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://a/p.jpg');

    expect(find.byType(ImageFiltered), findsNothing, reason: '无模糊（纯取色渐变）');
    final gradients = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(PosterBackdrop),
          matching: find.byType(DecoratedBox),
        ))
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .toList();
    expect(gradients.length, greaterThanOrEqualTo(2), reason: '渐变场 + 压暗层');

    final field = gradients.first;
    expect(field.colors.length, greaterThanOrEqualTo(9),
        reason: '短色弧展开（S 曲线多停点）');
    // 同色调暗氛围：整场 L 压暗区（≤0.25）。
    for (final c in field.colors) {
      expect(HSLColor.fromColor(c).lightness, lessThanOrEqualTo(0.25),
          reason: 'spec 压暗（同色调暗氛围）');
    }
    // 色相保留（红主导）。
    expect(HSLColor.fromColor(field.colors.first).hue, inInclusiveRange(0, 40),
        reason: 'H 保留（红主导色相）');
    debugAmbientImageProvider = null;
  });

  testWidgets('N53 保持旧场：新渐变就绪前不换场', (tester) async {
    final image = await _posterImage();
    debugAmbientImageProvider =
        (url) => fake[url] ??= _FakeImageProvider(image);
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://old/p.jpg');
    expect(find.byType(AnimatedSwitcher), findsOneWidget);

    final slow = Completer<ImageInfo>();
    fake['https://new/p.jpg'] = _FakeImageProvider(image, completer: slow);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PosterBackdrop)));
    container.read(heroPosterUrlProvider.notifier).state = 'https://new/p.jpg';
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();

    final sw = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(sw.child, isNotNull, reason: '保持旧场（不闪空白）');

    slow.complete(ImageInfo(image: image));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 650));
    debugAmbientImageProvider = null;
  });

  test('预热函数：precacheAmbientPoster 可用', () {
    precacheAmbientPoster('https://warm/p.jpg');
  });
}
