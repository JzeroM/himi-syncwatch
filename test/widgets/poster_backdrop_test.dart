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

/// 上亮下暗双色海报（网格光影可验证）。
Future<ui.Image> _posterImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 8, 12), Paint()..color = const Color(0xFFE8A050));
  canvas.drawRect(const Rect.fromLTWH(0, 12, 8, 12), Paint()..color = const Color(0xFF302018));
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
    // 同步注入（fake-async 兼容）：3×3 网格均色 + 基调。
    PosterPalette.debugExtractLightField = (image) async {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final rgba = data.buffer.asUint8List();
      final w = image.width;
      final h = image.height;
      final grid = <(Color, double)>[];
      for (var gy = 0; gy < 3; gy++) {
        for (var gx = 0; gx < 3; gx++) {
          final x0 = w * gx ~/ 3;
          final x1 = w * (gx + 1) ~/ 3;
          final y0 = h * gy ~/ 3;
          final y1 = h * (gy + 1) ~/ 3;
          var r = 0, g = 0, b = 0, n = 0;
          for (var y = y0; y < y1; y++) {
            for (var x = x0; x < x1; x++) {
              final o = (y * w + x) * 4;
              if (rgba[o + 3] < 128) continue;
              r += rgba[o];
              g += rgba[o + 1];
              b += rgba[o + 2];
              n++;
            }
          }
          final c =
              n == 0 ? const Color(0xFF808080) : Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
          grid.add((c, HSLColor.fromColor(c).lightness));
        }
      }
      return LightField(
        base: grid[7].$1,
        palette: [grid[0].$1, grid[7].$1],
        grid: grid,
      );
    };
  });
  tearDown(() {
    PosterPalette.debugExtractLightField = null;
    PosterPalette.debugReset();
  });

  group('extractLightField（N56 光场数据）', () {
    testWidgets('多色调色板 + 3×3 网格 + 基调（下半区）', (tester) async {
      final image = await _posterImage();
      PosterPalette.debugExtractLightField = null; // 测生产逻辑
      final field = await tester
          .runAsync(() => PosterPalette.extractLightField(image));
      expect(field, isNotNull);
      expect(field!.palette.length, greaterThanOrEqualTo(2),
          reason: '多色调色板（≥2 色）');
      expect(field.grid, hasLength(9), reason: '3×3 网格光影');
      // 基调 = 下半区暗色（上下协调）。
      final baseL = HSLColor.fromColor(field.base).lightness;
      expect(baseL, lessThan(0.5), reason: '基调偏暗（下半区暗色）');
    });

    testWidgets('光场种子稳定：同 URL 同布局（微随机可复现）', (tester) async {
      final image = await _posterImage();
      PosterPalette.debugExtractLightField = null; // 测生产逻辑
      final f1 = await tester
          .runAsync(() => PosterPalette.extractLightField(image));
      final f2 = await tester
          .runAsync(() => PosterPalette.extractLightField(image));
      // 数据层确定性（随机在渲染层按 URL 种子）。
      expect(f1!.base, f2!.base, reason: '同图基调一致');
      expect(f1.grid.length, f2.grid.length);
    });
  });

  testWidgets('N56 光场渲染：S 曲线底 + 9 光球 + 无黑幕', (tester) async {
    final image = await _posterImage();
    debugAmbientImageProvider =
        (url) => fake[url] ??= _FakeImageProvider(image);
    await tester.pumpWidget(_app(isDark: true));
    await _setUrl(tester, 'https://a/p.jpg');

    // 9 颗光球（径向渐变）。
    final radials = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(PosterBackdrop),
          matching: find.byType(DecoratedBox),
        ))
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<RadialGradient>()
        .toList();
    expect(radials.length, 9, reason: 'N56：3×3 网格 9 颗光球');

    // S 曲线底（线性渐变）。
    final linears = tester
        .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(PosterBackdrop),
          matching: find.byType(DecoratedBox),
        ))
        .map((l) => (l.decoration! as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .toList();
    expect(linears, isNotEmpty, reason: 'S 曲线基调打底');
    // 第一道压暗保持（基调 L 钳暗区）。
    for (final c in linears.first.colors) {
      expect(HSLColor.fromColor(c).lightness, lessThanOrEqualTo(0.25),
          reason: '同色调压暗（白字可读）');
    }
    debugAmbientImageProvider = null;
  });

  testWidgets('N53 保持旧场：新光场就绪前不换场', (tester) async {
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
