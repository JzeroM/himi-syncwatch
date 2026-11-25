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
    // 同步注入（fake-async 兼容）：按像素主导色直读。
    PosterPalette.debugExtractPalette = (image) async {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return (const Color(0xFF808080), null);
      final rgba = data.buffer.asUint8List();
      final w = image.width;
      final h = image.height;
      // 上下半区均色（基调=下半、晕染=上半——测试双色链路）。
      List<int> avg(int y0, int y1) {
        var r = 0, g = 0, b = 0, n = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = 0; x < w; x++) {
            final o = (y * w + x) * 4;
            if (rgba[o + 3] < 128) continue;
            r += rgba[o];
            g += rgba[o + 1];
            b += rgba[o + 2];
            n++;
          }
        }
        return n == 0 ? [128, 128, 128] : [r ~/ n, g ~/ n, b ~/ n];
      }

      final lo = avg(h ~/ 2, h);
      final up = avg(0, h ~/ 2);
      return (
        Color.fromARGB(255, lo[0], lo[1], lo[2]),
        Color.fromARGB(255, up[0], up[1], up[2]),
      );
    };
  });
  tearDown(() {
    PosterPalette.debugExtractPalette = null;
    PosterPalette.debugReset();
  });

  group('extractDesignPalette（N55 设计调色板）', () {
    testWidgets('palette_generator 六 swatch + thief 交叉验证出基调', (tester) async {
      // 红主导海报 → 基调为红系暗色（darkMuted/dominant 派生）、保底可用。
      final image = await _posterImage();
      PosterPalette.debugExtractPalette = null; // 测生产逻辑
      final result = await tester
          .runAsync(() => PosterPalette.extractDesignPalette(image));
      final (base, _) = result!;
      final hsl = HSLColor.fromColor(base);
      // 深色保底：结果 L≥0.11（ambientTrio 前的原色；调色板色可亮可暗，
      // 但不能是近黑丢色相——L<0.07 的极端值由 swatch 目标法天然避开）。
      expect(hsl.lightness, greaterThan(0.05), reason: '基调非死黑');
      // 红主导图 → 基调色相红系（thief/palette 交叉一致）。
      expect(hsl.hue, inInclusiveRange(0, 40), reason: '红主导色相保留');
    });

    testWidgets('下半区取色（上下协调）：底缘色彩胜出', (tester) async {
      // 上蓝下红图 → 基调应偏红（下半区 darkMuted）。
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 12), Paint()..color = const Color(0xFF2244CC));
      canvas.drawRect(const Rect.fromLTWH(0, 12, 8, 12), Paint()..color = const Color(0xFFCC4422));
      final picture = recorder.endRecording();
      final image = await picture.toImage(8, 24);
      picture.dispose();
      PosterPalette.debugExtractPalette = null; // 测生产逻辑
      final result = await tester
          .runAsync(() => PosterPalette.extractDesignPalette(image));
      final (base, _) = result!;
      final hue = HSLColor.fromColor(base).hue;
      expect(hue < 30 || hue > 330, isTrue,
          reason: '下半（海报底缘侧）色彩胜出（上下协调）');
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

  test('N54 y 加权取色：下半像素权重高（上下协调根治）', () {
    // 构造：上 5 行蓝、下 5 行红（像素 1:1）——不加权难分胜负，
    // y 加权（下半权重高）后红（海报底缘侧）必胜出。
    final rgba = Uint8List(10 * 10 * 4);
    for (var y = 0; y < 10; y++) {
      for (var x = 0; x < 10; x++) {
        final o = (y * 10 + x) * 4;
        final lower = y >= 5;
        rgba[o] = lower ? 200 : 40;
        rgba[o + 1] = lower ? 60 : 60;
        rgba[o + 2] = lower ? 50 : 180;
        rgba[o + 3] = 255;
      }
    }
    final (dom, _) = PosterPalette.computeDominant(rgba, 10, 10);
    // 下半红像素少但权重高（1+0.8y/h）→ 主导色向红偏移（或至少非纯蓝）。
    final hue = HSLColor.fromColor(dom).hue;
    final redWins = hue < 30 || hue > 330;
    expect(redWins, isTrue,
        reason: 'y 加权：下半（海报底缘侧）色彩胜出（上下协调）');
  });

  testWidgets('N54 邻色晕染层：辅簇对角径向柔混', (tester) async {
    // 双色海报（上红下蓝）→ 辅簇存在 → 晕染层渲染。
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 12), Paint()..color = const Color(0xFFCC4422));
    canvas.drawRect(const Rect.fromLTWH(0, 12, 8, 12), Paint()..color = const Color(0xFF2244CC));
    final picture = recorder.endRecording();
    final image = await picture.toImage(8, 24);
    picture.dispose();
    debugAmbientImageProvider =
        (url) => fake[url] ??= _FakeImageProvider(image);
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://wash/p.jpg');

    final radials = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(PosterBackdrop),
          matching: find.byType(DecoratedBox),
        ))
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<RadialGradient>()
        .toList();
    expect(radials, isNotEmpty, reason: 'N54 邻色晕染层（对角径向）');
    debugAmbientImageProvider = null;
  });

  test('预热函数：precacheAmbientPoster 可用', () {
    precacheAmbientPoster('https://warm/p.jpg');
  });
}
