import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// 海报主色提取（零依赖自研）。
///
/// 图片（多已磁盘缓存）→ 解码 → 缩至 64×64 → RGBA 采样 →
/// 过滤过暗/过亮像素 → 4-bit 量化取高频色 → 原始主色入缓存。
/// 对外按需派生压暗主色（[extract]，页面背景）或提亮主色
/// （[extractBright]，详情页背景），两者共享缓存、同图只解码一次。
/// 内置内存 LRU 缓存、同 URL 单飞去重、超时兜底（失败返回 null）。
class PosterPalette {
  PosterPalette._();

  /// 取色失败/无主色时的页面深色基调。
  static const Color deepFallback = Color(0xFF0F1116);

  static const Duration defaultTimeout = Duration(milliseconds: 2500);
  static const int maxCacheEntries = 128;
  static const int sampleSize = 64;
  static const int targetSamples = 4096;

  /// 亮度过滤阈值：L<0.12 视为近黑、L>0.92 视为近白，均不参与取色。
  static const double minLuma = 0.12;
  static const double maxLuma = 0.92;

  /// 主色与深色底的混合比例（0=保留主色，1=完全深色）。
  static const double deepMix = 0.45;

  /// 页面渐变的分段位置（顶部主色 → 中段过渡 → 底部底色）。
  static const List<double> pageStops = [0.0, 0.4, 0.8];

  /// 详情页亮色渐变的分段位置（顶部亮主色 → 中段 → 底部收深）。
  static const List<double> detailStops = [0.0, 0.4, 0.9];

  /// 提亮版：与深色底的混合比例（轻压防止刺眼）。
  static const double brightMix = 0.15;

  /// 提亮版：亮度下限（主色太暗时提亮到此值）与上限（防刺眼）。
  static const double brightLightnessFloor = 0.5;
  static const double brightLightnessCap = 0.55;

  /// 提亮版：饱和度下限（保证彩色感）。
  static const double brightSaturationFloor = 0.25;

  static Duration debugTimeout = defaultTimeout;
  static Future<ui.Image?> Function(String url, {Map<String, String>? headers})?
      debugImageLoader;

  static final Map<String, Color> _cache = <String, Color>{};
  static final Map<String, Future<Color?>> _inflight =
      <String, Future<Color?>>{};

  /// 清空缓存与调试注入（测试用）。
  static void debugReset() {
    _cache.clear();
    _inflight.clear();
    debugTimeout = defaultTimeout;
    debugImageLoader = null;
  }

  static int debugCacheLength() => _cache.length;

  /// 提取 [url] 图片的压暗主色（页面背景用）；空 URL、超时、解码失败均返回 null。
  static Future<Color?> extract(String url,
      {Map<String, String>? headers}) async {
    final raw = await _raw(url, headers: headers);
    return raw == null ? null : darkenForPage(raw);
  }

  /// 提取 [url] 图片的提亮主色（详情页背景用）；与 [extract] 共享缓存与
  /// 单飞，同一 URL 不会重复解码。失败返回 null。
  static Future<Color?> extractBright(String url,
      {Map<String, String>? headers}) async {
    final raw = await _raw(url, headers: headers);
    return raw == null ? null : brightenForPage(raw);
  }

  /// 读取原始主色（缓存存 raw，压暗/提亮在各入口按需派生）。
  static Future<Color?> _raw(String url, {Map<String, String>? headers}) async {
    if (url.isEmpty) return null;
    final hit = _cache.remove(url);
    if (hit != null) {
      _cache[url] = hit;
      return hit;
    }
    final pending = _inflight[url];
    if (pending != null) return pending;
    final future = _load(url, headers: headers);
    _inflight[url] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(url);
    }
  }

  static Future<Color?> _load(String url,
      {Map<String, String>? headers}) async {
    try {
      final source =
          await (debugImageLoader ?? _loadImage)(url, headers: headers)
              .timeout(debugTimeout);
      if (source == null) return null;
      final small = await _downscale(source, sampleSize);
      try {
        final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        final color =
            compute(data.buffer.asUint8List(), small.width, small.height);
        if (color != null) _putCache(url, color);
        return color;
      } finally {
        small.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image?> _loadImage(String url,
      {Map<String, String>? headers}) {
    final provider = CachedNetworkImageProvider(url, headers: headers);
    final completer = Completer<ui.Image?>();
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  static Future<ui.Image> _downscale(ui.Image source, int size) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    return image;
  }

  /// 对 RGBA 像素做采样取原始主色；无有效像素返回 null。
  /// （压暗/提亮由 [darkenForPage]/[brightenForPage] 派生。）
  static Color? compute(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0) return null;
    final total = width * height;
    if (rgba.length < total * 4) return null;

    var stride = (total / targetSamples).ceil();
    if (stride < 1) stride = 1;

    final counts = <int, int>{};
    final sums = <int, List<int>>{};
    for (var i = 0; i < total; i += stride) {
      final offset = i * 4;
      if (rgba[offset + 3] < 128) continue;
      final r = rgba[offset];
      final g = rgba[offset + 1];
      final b = rgba[offset + 2];
      final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
      if (luma < minLuma || luma > maxLuma) continue;
      final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
      counts[key] = (counts[key] ?? 0) + 1;
      final sum = sums[key] ??= <int>[0, 0, 0];
      sum[0] += r;
      sum[1] += g;
      sum[2] += b;
    }
    if (counts.isEmpty) return null;

    var bestKey = 0;
    var bestCount = -1;
    counts.forEach((key, count) {
      if (count > bestCount) {
        bestCount = count;
        bestKey = key;
      }
    });

    final sum = sums[bestKey]!;
    return Color.fromARGB(
        255, sum[0] ~/ bestCount, sum[1] ~/ bestCount, sum[2] ~/ bestCount);
  }

  /// 将任意主色压暗为适合做页面背景的色调。
  static Color darkenForPage(Color color) {
    final mixed = Color.lerp(color, deepFallback, deepMix)!;
    final hsl = HSLColor.fromColor(mixed);
    if (hsl.lightness > 0.5) {
      return hsl.withLightness(0.5).toColor();
    }
    return mixed;
  }

  /// 将任意主色提亮为适合做详情页背景的色调：
  /// 轻混深色（防刺眼）→ 亮度夹在 [brightLightnessFloor, brightLightnessCap]
  /// → 饱和度保底 [brightSaturationFloor]（保证彩色感）。
  static Color brightenForPage(Color color) {
    final mixed = Color.lerp(color, deepFallback, brightMix)!;
    var hsl = HSLColor.fromColor(mixed);
    if (hsl.saturation < brightSaturationFloor) {
      hsl = hsl.withSaturation(brightSaturationFloor);
    }
    var lightness = hsl.lightness;
    if (lightness < brightLightnessFloor) {
      lightness = brightLightnessFloor;
    } else if (lightness > brightLightnessCap) {
      lightness = brightLightnessCap;
    }
    return hsl.withLightness(lightness).toColor();
  }

  /// 详情页背景垂直渐变：顶部 [accent] 主色 → 底部 [base] 页面底色。
  /// [accent] 为 null 时整页保持 [base]（与取色前视觉一致）。
  static LinearGradient pageGradient(Color? accent, Color base) {
    if (accent == null) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [base, base, base],
        stops: pageStops,
      );
    }
    final mid = Color.lerp(accent, base, 0.65)!;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [accent, mid, base],
      stops: pageStops,
    );
  }

  /// 详情页背景垂直渐变（亮色版，1=A 方案）：顶部 [bright] 亮主色 →
  /// 中段轻混底色 → 底部收深（约 62% 底色），分段见 [detailStops]。
  /// [bright] 为 null 时整页保持 [base]（与取色前视觉一致）。
  static LinearGradient detailGradient(Color? bright, Color base) {
    if (bright == null) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [base, base, base],
        stops: detailStops,
      );
    }
    final mid = Color.lerp(bright, base, 0.30)!;
    final low = Color.lerp(bright, base, 0.62)!;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [bright, mid, low],
      stops: detailStops,
    );
  }

  static void _putCache(String url, Color color) {
    _cache.remove(url);
    _cache[url] = color;
    while (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}
