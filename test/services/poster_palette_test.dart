import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';

Future<ui.Image> _solidImage(Color color, [int size = 8]) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

Uint8List _solidBuffer(int width, int height, int r, int g, int b,
    {int a = 255}) {
  final buffer = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    buffer[i * 4] = r;
    buffer[i * 4 + 1] = g;
    buffer[i * 4 + 2] = b;
    buffer[i * 4 + 3] = a;
  }
  return buffer;
}

int _red(Color c) => (c.r * 255).round();
int _green(Color c) => (c.g * 255).round();
int _blue(Color c) => (c.b * 255).round();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(PosterPalette.debugReset);

  group('compute', () {
    test('纯色图返回三色组：首色为原始主色（不足用首色补齐）', () {
      final trio =
          PosterPalette.compute(_solidBuffer(100, 100, 200, 60, 40), 100, 100);

      // 首色 = raw（压暗/提亮/中深由各入口派生）
      expect(trio, hasLength(PosterPalette.trioCount));
      expect(_red(trio[0]), 200);
      expect(_green(trio[0]), 60);
      expect(_blue(trio[0]), 40);
      expect(_red(trio[0]) > _green(trio[0]), isTrue);
      expect(_red(trio[0]) > _blue(trio[0]), isTrue);
      // 纯色图无第二主色：三色全部为首色（同色系明度渐变）
      expect(trio[1], trio[0]);
      expect(trio[2], trio[0]);
    });

    test('多色区域图返回互异三色（频次降序、色差达标）', () {
      const width = 120, height = 90;
      final buffer = Uint8List(width * height * 4);
      // 三竖条：红 60%、绿 25%、蓝 15%（均在严格亮度池内）
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          final Color c;
          if (x < 72) {
            c = const Color(0xFFCC4422);
          } else if (x < 102) {
            c = const Color(0xFF44BB55);
          } else {
            c = const Color(0xFF3366CC);
          }
          buffer[i] = (c.r * 255).round();
          buffer[i + 1] = (c.g * 255).round();
          buffer[i + 2] = (c.b * 255).round();
          buffer[i + 3] = 255;
        }
      }

      final trio = PosterPalette.compute(buffer, width, height);
      expect(trio, hasLength(3));
      // 频次最高（红条最宽）为首色
      expect(_red(trio[0]), greaterThan(_green(trio[0])));
      expect(_red(trio[0]), greaterThan(_blue(trio[0])));
      // 三色互异（色差 ≥ colorSeparation）
      for (var i = 0; i < 3; i++) {
        for (var j = i + 1; j < 3; j++) {
          final dr = (_red(trio[i]) - _red(trio[j])).toDouble();
          final dg = (_green(trio[i]) - _green(trio[j])).toDouble();
          final db = (_blue(trio[i]) - _blue(trio[j])).toDouble();
          final dist = dr * dr + dg * dg + db * db;
          expect(
              dist,
              greaterThanOrEqualTo(PosterPalette.colorSeparation *
                  PosterPalette.colorSeparation),
              reason: '色 $i 与色 $j 应达到最小色差');
        }
      }
      // 含绿/蓝色相（候选按频次入齐）
      expect(trio.any((c) => _green(c) > _red(c)), isTrue);
      expect(trio.any((c) => _blue(c) > _green(c)), isTrue);
    });

    test('严格池不足时宽池参与补色（近白区域入第二色）', () {
      const width = 100, height = 100;
      final buffer = Uint8List(width * height * 4);
      for (var i = 0; i < width * height; i++) {
        // 70% 中灰（严格池内）、30% 近白（L≈0.96，仅宽池）
        final nearWhite = i % 10 >= 7;
        final v = nearWhite ? 245 : 128;
        buffer[i * 4] = v;
        buffer[i * 4 + 1] = v;
        buffer[i * 4 + 2] = v;
        buffer[i * 4 + 3] = 255;
      }

      final trio = PosterPalette.compute(buffer, width, height);
      expect(trio, hasLength(3));
      // 首色 = 严格池最高频（中灰），第二色 = 宽池近白
      expect(_red(trio[0]), 128);
      expect(_red(trio[1]), 245);
    });

    test('近黑像素全部被过滤', () {
      expect(
        PosterPalette.compute(_solidBuffer(64, 64, 5, 5, 5), 64, 64),
        isEmpty,
      );
    });

    test('近白像素全部被过滤', () {
      expect(
        PosterPalette.compute(_solidBuffer(64, 64, 250, 250, 250), 64, 64),
        isEmpty,
      );
    });

    test('透明像素被忽略', () {
      expect(
        PosterPalette.compute(_solidBuffer(64, 64, 200, 60, 40, a: 0), 64, 64),
        isEmpty,
      );
    });

    test('buffer 长度不足返回空表', () {
      expect(PosterPalette.compute(Uint8List(10), 100, 100), isEmpty);
      expect(PosterPalette.compute(Uint8List(400), 0, 100), isEmpty);
    });

    test('少量异色像素不干扰主导色', () {
      const width = 100, height = 100;
      final buffer = _solidBuffer(width, height, 200, 60, 40);
      // 末尾 10% 像素涂成亮蓝（luma 通过过滤，但数量不敌红色）
      for (var i = width * height * 9 ~/ 10; i < width * height; i++) {
        buffer[i * 4] = 60;
        buffer[i * 4 + 1] = 120;
        buffer[i * 4 + 2] = 255;
      }

      final trio = PosterPalette.compute(buffer, width, height);
      expect(_red(trio[0]) > _blue(trio[0]), isTrue);
      expect(_green(trio[0]) < _red(trio[0]), isTrue);
    });
  });

  group('darkenForPage', () {
    test('过亮颜色的亮度被限制在 0.5 以内', () {
      final color = PosterPalette.darkenForPage(const Color(0xFFFFFFFF));
      expect(HSLColor.fromColor(color).lightness, lessThanOrEqualTo(0.5));
    });

    test('鲜艳颜色被压暗且保留色相', () {
      final color = PosterPalette.darkenForPage(const Color(0xFFCC4422));
      expect(_red(color), greaterThan(_green(color)));
      expect(_red(color), greaterThan(_blue(color)));
      expect(HSLColor.fromColor(color).lightness, lessThan(0.5));
    });
  });

  group('brightenForPage', () {
    test('亮度被夹在 0.5~0.55 区间', () {
      final color = PosterPalette.brightenForPage(const Color(0xFF3366AA));
      final lightness = HSLColor.fromColor(color).lightness;
      expect(lightness, greaterThanOrEqualTo(0.5));
      expect(lightness, lessThanOrEqualTo(0.55));
    });

    test('太暗的颜色被提亮到亮度下限', () {
      final color = PosterPalette.brightenForPage(const Color(0xFF1A1A1A));
      expect(HSLColor.fromColor(color).lightness, closeTo(0.5, 0.01));
    });

    test('过亮的颜色被压到亮度上限', () {
      final color = PosterPalette.brightenForPage(const Color(0xFFF0F0F0));
      expect(HSLColor.fromColor(color).lightness, closeTo(0.55, 0.01));
    });

    test('灰色提亮后饱和度保底', () {
      final color = PosterPalette.brightenForPage(const Color(0xFF808080));
      final hsl = HSLColor.fromColor(color);
      expect(hsl.saturation, closeTo(0.25, 0.015));
    });

    test('饱和颜色提亮后色相保留', () {
      final color = PosterPalette.brightenForPage(const Color(0xFFCC4422));
      expect(_red(color), greaterThan(_green(color)));
      expect(_red(color), greaterThan(_blue(color)));
    });
  });

  group('pageGradient', () {
    const base = Color(0xFF121212);

    test('无主色时整页保持页面底色', () {
      final gradient = PosterPalette.pageGradient(null, base);
      expect(gradient.colors, [base, base, base]);
      expect(gradient.stops, PosterPalette.pageStops);
    });

    test('有主色时三段渐变：顶部主色、底部底色', () {
      const accent = Color(0xFF3366AA);
      final gradient = PosterPalette.pageGradient(accent, base);
      expect(gradient.colors.length, 3);
      expect(gradient.colors.first, accent);
      expect(gradient.colors.last, base);
      expect(gradient.stops, PosterPalette.pageStops);
    });
  });

  group('detailGradient', () {
    const base = Color(0xFF121212);

    test('无色组时整页保持页面底色', () {
      final gradient = PosterPalette.detailGradient(null, base);
      expect(gradient.colors, [base, base, base]);
      expect(gradient.stops, PosterPalette.detailStops);
    });

    test('空色组时整页保持页面底色', () {
      final gradient = PosterPalette.detailGradient(const [], base);
      expect(gradient.colors, [base, base, base]);
      expect(gradient.stops, PosterPalette.detailStops);
    });

    test('三色组时三段异色：顶亮、中深、底收深', () {
      const top1 = Color(0xFFCC4422);
      const top2 = Color(0xFF44BB55);
      const top3 = Color(0xFF3366CC);
      final gradient =
          PosterPalette.detailGradient(const [top1, top2, top3], base);

      expect(gradient.colors.length, 3);
      expect(gradient.stops, PosterPalette.detailStops);
      // 顶段 = 亮色派生，且为至少一个亮色
      expect(gradient.colors.first, PosterPalette.brightenForPage(top1));
      expect(HSLColor.fromColor(gradient.colors.first).lightness,
          greaterThanOrEqualTo(PosterPalette.brightLightnessFloor));
      // 中段 = 第二主色中深保色相
      expect(gradient.colors[1], PosterPalette.toneForPage(top2));
      // 底段 = 第三主色压深后混底色（detailBaseMix）
      expect(
          gradient.colors.last,
          Color.lerp(PosterPalette.deepenForPage(top3), base,
              PosterPalette.detailBaseMix));
      // 三段互不相同
      expect(gradient.colors.toSet(), hasLength(3));
    });

    test('色组不足三色时用首色补齐派生', () {
      const top1 = Color(0xFFCC4422);
      final gradient = PosterPalette.detailGradient(const [top1], base);

      expect(gradient.colors.length, 3);
      expect(gradient.colors.first, PosterPalette.brightenForPage(top1));
      expect(gradient.colors[1], PosterPalette.toneForPage(top1));
      expect(
          gradient.colors.last,
          Color.lerp(PosterPalette.deepenForPage(top1), base,
              PosterPalette.detailBaseMix));
    });
  });

  group('extract', () {
    test('空 URL 返回 null 且不触发加载', () async {
      var calls = 0;
      PosterPalette.debugImageLoader = (url, {headers}) async {
        calls++;
        return _solidImage(const Color(0xFFCC4422));
      };

      expect(await PosterPalette.extract(''), isNull);
      expect(calls, 0);
    });

    test('相同 URL 二次取色命中缓存', () async {
      var calls = 0;
      PosterPalette.debugImageLoader = (url, {headers}) async {
        calls++;
        return _solidImage(const Color(0xFFCC4422));
      };

      final first = await PosterPalette.extract('http://x/1.jpg');
      final second = await PosterPalette.extract('http://x/1.jpg');

      expect(first, isNotNull);
      expect(calls, 1);
      expect(first, second);
      expect(PosterPalette.debugCacheLength(), 1);
    });

    test('并发同 URL 单飞去重', () async {
      var calls = 0;
      PosterPalette.debugImageLoader = (url, {headers}) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return _solidImage(const Color(0xFF336699));
      };

      final results = await Future.wait([
        PosterPalette.extract('http://x/a.jpg'),
        PosterPalette.extract('http://x/a.jpg'),
      ]);

      expect(calls, 1);
      expect(results[0], isNotNull);
      expect(results[0], results[1]);
    });

    test('超时返回 null', () async {
      PosterPalette.debugTimeout = const Duration(milliseconds: 20);
      PosterPalette.debugImageLoader =
          (url, {headers}) => Completer<ui.Image?>().future;

      expect(await PosterPalette.extract('http://x/timeout.jpg'), isNull);
    });

    test('加载抛错返回 null 且不缓存', () async {
      PosterPalette.debugImageLoader =
          (url, {headers}) async => throw Exception('boom');

      expect(await PosterPalette.extract('http://x/err.jpg'), isNull);
      expect(PosterPalette.debugCacheLength(), 0);
    });

    test('缓存超上限淘汰最旧条目', () async {
      var calls = 0;
      PosterPalette.debugImageLoader = (url, {headers}) async {
        calls++;
        return _solidImage(const Color(0xFFCC4422));
      };

      final total = PosterPalette.maxCacheEntries + 5;
      for (var i = 0; i < total; i++) {
        await PosterPalette.extract('http://x/$i.jpg');
      }
      expect(PosterPalette.debugCacheLength(), PosterPalette.maxCacheEntries);

      final before = calls;
      await PosterPalette.extract('http://x/0.jpg'); // 最旧，已淘汰
      expect(calls, before + 1);

      await PosterPalette.extract('http://x/${total - 1}.jpg'); // 最新，命中
      expect(calls, before + 1);
    });

    test('debugReset 清空缓存与调试注入', () async {
      PosterPalette.debugImageLoader =
          (url, {headers}) async => _solidImage(const Color(0xFFCC4422));
      await PosterPalette.extract('http://x/r.jpg');
      expect(PosterPalette.debugCacheLength(), 1);

      PosterPalette.debugReset();
      expect(PosterPalette.debugCacheLength(), 0);
      expect(PosterPalette.debugImageLoader, isNull);
      expect(PosterPalette.debugTimeout, PosterPalette.defaultTimeout);
    });
  });

  group('extractBright', () {
    test('空 URL 返回 null 且不触发加载', () async {
      var calls = 0;
      PosterPalette.debugImageLoader = (url, {headers}) async {
        calls++;
        return _solidImage(const Color(0xFFCC4422));
      };

      expect(await PosterPalette.extractBright(''), isNull);
      expect(calls, 0);
    });

    test('与 extract 共享缓存：同图只解码一次、各自派生明暗', () async {
      var calls = 0;
      PosterPalette.debugImageLoader = (url, {headers}) async {
        calls++;
        return _solidImage(const Color(0xFFCC4422));
      };

      final dark = await PosterPalette.extract('http://x/1.jpg');
      final bright = await PosterPalette.extractBright('http://x/1.jpg');

      expect(calls, 1);
      expect(PosterPalette.debugCacheLength(), 1);
      // 缓存存 raw，两者均为对同一 raw 的派生
      expect(dark, PosterPalette.darkenForPage(const Color(0xFFCC4422)));
      expect(bright, PosterPalette.brightenForPage(const Color(0xFFCC4422)));
      // 提亮版比压暗版亮
      expect(HSLColor.fromColor(bright!).lightness,
          greaterThan(HSLColor.fromColor(dark!).lightness));
    });

    test('与 extract 并发同 URL 单飞去重', () async {
      var calls = 0;
      PosterPalette.debugImageLoader = (url, {headers}) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return _solidImage(const Color(0xFF336699));
      };

      final results = await Future.wait([
        PosterPalette.extract('http://x/a.jpg'),
        PosterPalette.extractBright('http://x/a.jpg'),
      ]);

      expect(calls, 1);
      expect(results[0], isNotNull);
      expect(results[1], isNotNull);
      expect(results[0], isNot(results[1]));
    });

    test('加载失败返回 null', () async {
      PosterPalette.debugImageLoader =
          (url, {headers}) async => throw Exception('boom');
      expect(await PosterPalette.extractBright('http://x/err.jpg'), isNull);
      expect(PosterPalette.debugCacheLength(), 0);
    });
  });

  group('extractTrio', () {
    test('空 URL 返回 null 且不触发加载', () async {
      var calls = 0;
      PosterPalette.debugImageLoader = (url, {headers}) async {
        calls++;
        return _solidImage(const Color(0xFFCC4422));
      };

      expect(await PosterPalette.extractTrio(''), isNull);
      expect(calls, 0);
    });

    test('图片可加载时保证返回 3 色（图能加载→必有色组）', () async {
      PosterPalette.debugImageLoader =
          (url, {headers}) async => _solidImage(const Color(0xFFCC4422));

      final trio = await PosterPalette.extractTrio('http://x/1.jpg');
      expect(trio, isNotNull);
      expect(trio, hasLength(PosterPalette.trioCount));
    });

    test('与 extract/extractBright 共享缓存：同图只解码一次', () async {
      var calls = 0;
      PosterPalette.debugImageLoader = (url, {headers}) async {
        calls++;
        return _solidImage(const Color(0xFFCC4422));
      };

      await PosterPalette.extract('http://x/1.jpg');
      await PosterPalette.extractBright('http://x/1.jpg');
      await PosterPalette.extractTrio('http://x/1.jpg');

      expect(calls, 1);
      expect(PosterPalette.debugCacheLength(), 1);
    });

    test('加载抛错返回 null 且不缓存', () async {
      PosterPalette.debugImageLoader =
          (url, {headers}) async => throw Exception('boom');

      expect(await PosterPalette.extractTrio('http://x/err.jpg'), isNull);
      expect(PosterPalette.debugCacheLength(), 0);
    });

    test('超时返回 null', () async {
      PosterPalette.debugTimeout = const Duration(milliseconds: 20);
      PosterPalette.debugImageLoader =
          (url, {headers}) => Completer<ui.Image?>().future;

      expect(await PosterPalette.extractTrio('http://x/timeout.jpg'), isNull);
    });
  });
}
