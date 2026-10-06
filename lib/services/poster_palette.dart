import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// 海报主色提取（零依赖自研）。
///
/// 图片（多已磁盘缓存）→ 解码 → 缩至 64×64 → RGBA 采样 →
/// 4-bit 量化分桶 → 严格池（防近黑/近白主导）选首色，候选按频次
/// 与色差贪心凑满 [trioCount] 色，不足用首色重复补齐——**只要图片能
/// 加载成功必返回 3 色**；仅加载失败/超时/无有效像素返回 null。
/// 对外派生：[extract] 压暗首色（页面背景）、[extractBright] 提亮首色、
/// [extractTrio] 原始三色组（详情页渐变），共享缓存与单飞，同图只解码一次。
/// 内置内存 LRU 缓存、同 URL 单飞去重、超时兜底。
class PosterPalette {
  PosterPalette._();

  /// 取色失败/无主色时的页面深色基调。
  static const Color deepFallback = Color(0xFF0F1116);

  static const Duration defaultTimeout = Duration(milliseconds: 2500);
  static const int maxCacheEntries = 128;
  static const int sampleSize = 64;
  static const int targetSamples = 4096;

  /// 每次提取的目标色数（详情页三段渐变）。
  static const int trioCount = 3;

  /// 首色严格亮度过滤：L<0.12 视为近黑、L>0.92 视为近白，不参与首色竞争
  /// （防噪点/大块近白主导）。
  static const double minLuma = 0.12;
  static const double maxLuma = 0.92;

  /// 第 2/3 色宽池过滤：暗色区/亮色区也参与（底段本来就要近黑），
  /// 仅挡纯噪点。
  static const double wideMinLuma = 0.05;
  static const double wideMaxLuma = 0.97;

  /// 入选色之间的最小 RGB 欧氏距离（平方比较，保证三色真的不同）。
  static const double colorSeparation = 48;

  /// 主色与深色底的混合比例（0=保留主色，1=完全深色）。
  static const double deepMix = 0.45;

  /// 页面渐变的分段位置（顶部主色 → 中段过渡 → 底部底色）。
  static const List<double> pageStops = [0.0, 0.4, 0.8];

  /// 详情页三色渐变的分段位置（顶亮 → 中深 → 底近黑）。
  static const List<double> detailStops = [0.0, 0.4, 0.9];

  /// 提亮版（渐变顶段）：与深色底的混合比例（轻压防止刺眼）。
  static const double brightMix = 0.15;

  /// 提亮版：亮度下限（主色太暗时提亮到此值）与上限（防刺眼）。
  static const double brightLightnessFloor = 0.5;
  static const double brightLightnessCap = 0.55;

  /// 提亮版：饱和度下限（保证彩色感）。
  static const double brightSaturationFloor = 0.25;

  /// 中段（渐变中段，保色相中深色）：混深比例、亮度区间、饱和度保底。
  static const double toneMix = 0.45;
  static const double toneLightnessFloor = 0.32;
  static const double toneLightnessCap = 0.46;
  static const double toneSaturationFloor = 0.18;

  /// 底段（渐变底段，近黑带色相）：更重混深、更低亮度上限、饱和保底。
  static const double deepMixStrong = 0.60;
  static const double deepLightnessCap = 0.35;
  static const double deepSaturationFloor = 0.12;

  /// 底段与页面底色的最终融合比例（收向底色但保留色相）。
  static const double detailBaseMix = 0.35;

  static Duration debugTimeout = defaultTimeout;
  static Future<ui.Image?> Function(String url, {Map<String, String>? headers})?
      debugImageLoader;

  static final Map<String, List<Color>> _cache = <String, List<Color>>{};
  static final Map<String, Future<List<Color>?>> _inflight =
      <String, Future<List<Color>?>>{};

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
    final trio = await _raw(url, headers: headers);
    return trio == null ? null : darkenForPage(trio.first);
  }

  /// 提取 [url] 图片的提亮主色；与 [extract] 共享缓存与单飞，
  /// 同一 URL 不会重复解码。失败返回 null。
  static Future<Color?> extractBright(String url,
      {Map<String, String>? headers}) async {
    final trio = await _raw(url, headers: headers);
    return trio == null ? null : brightenForPage(trio.first);
  }

  /// 提取 [url] 图片的原始三色组（频次降序，保证 [trioCount] 色，
  /// 见 [compute]）；失败（图加载不了/无有效像素）返回 null。
  static Future<List<Color>?> extractTrio(String url,
      {Map<String, String>? headers}) {
    return _raw(url, headers: headers);
  }

  /// 读取原始三色组（缓存存 raw，压暗/提亮/中深在各入口按需派生）。
  static Future<List<Color>?> _raw(String url,
      {Map<String, String>? headers}) async {
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

  static Future<List<Color>?> _load(String url,
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
        final colors =
            compute(data.buffer.asUint8List(), small.width, small.height);
        if (colors.isEmpty) return null;
        _putCache(url, colors);
        return colors;
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

  /// 对 RGBA 像素做采样取原始三色组（频次降序，保证 [trioCount] 色）：
  /// 1. 宽池过滤（[wideMinLuma]~[wideMaxLuma]）分桶求平均色
  /// 2. 首色取严格池（[minLuma]~[maxLuma]）最高频桶（严格池空则全池最高频）
  /// 3. 候选按「严格池频次序 → 宽池其余频次序」贪心选入，与已选色
  ///    RGB 距离 ≥ [colorSeparation] 才入选（保证三色互异）
  /// 4. 不足 [trioCount] 用首色重复补齐（纯色图 → 同色系明度渐变）
  ///
  /// 无有效像素（全透明/全噪点）返回空表（调用方视为提取失败）。
  static List<Color> compute(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0) return const [];
    final total = width * height;
    if (rgba.length < total * 4) return const [];

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
      if (luma < wideMinLuma || luma > wideMaxLuma) continue;
      final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
      counts[key] = (counts[key] ?? 0) + 1;
      final sum = sums[key] ??= <int>[0, 0, 0];
      sum[0] += r;
      sum[1] += g;
      sum[2] += b;
    }
    if (counts.isEmpty) return const [];

    final strict = <_Bucket>[];
    final byCount = <_Bucket>[];
    counts.forEach((key, count) {
      final sum = sums[key]!;
      final r = sum[0] ~/ count;
      final g = sum[1] ~/ count;
      final b = sum[2] ~/ count;
      final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
      final bucket = _Bucket(Color.fromARGB(255, r, g, b), luma, count);
      byCount.add(bucket);
      if (luma >= minLuma && luma <= maxLuma) strict.add(bucket);
    });
    byCount.sort((a, b) => b.count.compareTo(a.count));
    strict.sort((a, b) => b.count.compareTo(a.count));

    final selected = <Color>[];
    // 首色：优先严格池最高频；严格池空（整图近黑/近白）则全池最高频
    selected.add((strict.isNotEmpty ? strict : byCount).first.color);

    // 候选序：严格池频次序 → 宽池其余频次序；色差达标才入选
    final candidates = <Color>[
      ...strict.map((e) => e.color),
      for (final e in byCount)
        if (e.luma < minLuma || e.luma > maxLuma) e.color,
    ];
    final minSepSq = colorSeparation * colorSeparation;
    for (final candidate in candidates) {
      if (selected.length >= trioCount) break;
      var ok = true;
      for (final chosen in selected) {
        if (_distanceSq(candidate, chosen) < minSepSq) {
          ok = false;
          break;
        }
      }
      if (ok) selected.add(candidate);
    }

    // 补齐：不足三色用首色重复（detailGradient 对三段做不同明度派生）
    while (selected.length < trioCount) {
      selected.add(selected.first);
    }
    return selected;
  }

  /// RGB 欧氏距离平方（0~195075）。
  static double _distanceSq(Color a, Color b) {
    final dr = (a.r - b.r) * 255;
    final dg = (a.g - b.g) * 255;
    final db = (a.b - b.b) * 255;
    return dr * dr + dg * dg + db * db;
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

  /// 将任意主色提亮为适合做详情页渐变顶段的色调：
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

  /// 将任意主色处理为详情页渐变中段的保色相中深色：
  /// 混深 → 亮度夹在 [toneLightnessFloor, toneLightnessCap] → 饱和保底。
  static Color toneForPage(Color color) {
    final mixed = Color.lerp(color, deepFallback, toneMix)!;
    var hsl = HSLColor.fromColor(mixed);
    if (hsl.saturation < toneSaturationFloor) {
      hsl = hsl.withSaturation(toneSaturationFloor);
    }
    var lightness = hsl.lightness;
    if (lightness < toneLightnessFloor) {
      lightness = toneLightnessFloor;
    } else if (lightness > toneLightnessCap) {
      lightness = toneLightnessCap;
    }
    return hsl.withLightness(lightness).toColor();
  }

  /// 将任意主色处理为详情页渐变底段的近黑色（带色相）：
  /// 重混深 → 亮度封顶 [deepLightnessCap] → 饱和保底防灰化。
  static Color deepenForPage(Color color) {
    final mixed = Color.lerp(color, deepFallback, deepMixStrong)!;
    var hsl = HSLColor.fromColor(mixed);
    if (hsl.saturation < deepSaturationFloor) {
      hsl = hsl.withSaturation(deepSaturationFloor);
    }
    if (hsl.lightness > deepLightnessCap) {
      return hsl.withLightness(deepLightnessCap).toColor();
    }
    return hsl.toColor();
  }

  /// 页面背景垂直渐变：顶部 [accent] 主色 → 底部 [base] 页面底色。
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

  /// 详情页背景三段异色渐变（[detailStops]）：
  /// 顶 = [brightenForPage] 亮色段（三色至少一亮）、
  /// 中 = [toneForPage] 保色相中深、
  /// 底 = [deepenForPage] 再混底色（[detailBaseMix]）近黑收深。
  /// [trio] 为 null/空（图提取失败）时整页保持 [base]；
  /// 非空时按 [compute] 保证的三色直接派生，无逐段回退。
  static LinearGradient detailGradient(List<Color>? trio, Color base) {
    if (trio == null || trio.isEmpty) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [base, base, base],
        stops: detailStops,
      );
    }
    final top = brightenForPage(trio[0]);
    final mid = toneForPage(trio.length > 1 ? trio[1] : trio[0]);
    final low = Color.lerp(deepenForPage(trio.length > 2 ? trio[2] : trio[0]),
        base, detailBaseMix)!;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, mid, low],
      stops: detailStops,
    );
  }

  static void _putCache(String url, List<Color> colors) {
    _cache.remove(url);
    _cache[url] = colors;
    while (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}

/// 采样分桶的候选色：桶平均色 + 平均亮度 + 像素频次。
class _Bucket {
  const _Bucket(this.color, this.luma, this.count);
  final Color color;
  final double luma;
  final int count;
}
