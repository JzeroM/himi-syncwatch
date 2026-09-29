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
    test('纯色图提取主色并压暗混合', () {
      final color = PosterPalette.compute(_solidBuffer(100, 100, 200, 60, 40),
          100, 100)!;

      // mixed = lerp(原色, deepFallback, 0.45)
      expect(_red(color), closeTo(200 * 0.55 + 15 * 0.45, 2));
      expect(_green(color), closeTo(60 * 0.55 + 17 * 0.45, 2));
      expect(_blue(color), closeTo(40 * 0.55 + 22 * 0.45, 2));
      expect(_red(color) > _green(color), isTrue);
      expect(_red(color) > _blue(color), isTrue);
    });

    test('近黑像素全部被过滤', () {
      expect(
        PosterPalette.compute(_solidBuffer(64, 64, 5, 5, 5), 64, 64),
        isNull,
      );
    });

    test('近白像素全部被过滤', () {
      expect(
        PosterPalette.compute(_solidBuffer(64, 64, 250, 250, 250), 64, 64),
        isNull,
      );
    });

    test('透明像素被忽略', () {
      expect(
        PosterPalette.compute(_solidBuffer(64, 64, 200, 60, 40, a: 0), 64, 64),
        isNull,
      );
    });

    test('buffer 长度不足返回 null', () {
      expect(PosterPalette.compute(Uint8List(10), 100, 100), isNull);
      expect(PosterPalette.compute(Uint8List(400), 0, 100), isNull);
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

      final color = PosterPalette.compute(buffer, width, height)!;
      expect(_red(color) > _blue(color), isTrue);
      expect(_green(color) < _red(color), isTrue);
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
}
