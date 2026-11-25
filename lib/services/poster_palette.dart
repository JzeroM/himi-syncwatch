import 'dart:async';

import 'package:color_thief_dart/color_thief_dart.dart' as thief;
import 'package:palette_generator/palette_generator.dart';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// 海报主色提取（零依赖内置实现）。
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

  /// 698 N53：dominant 取色结果（占比最大簇 + 辅簇）。
  ///
  /// 过滤：剔除近白（L>0.88）、近黑（L<0.07）、近灰（S<0.04）像素；
  /// K-means 6 簇取占比最大簇为 dominant、次大为 secondary。
  static (Color, Color?) computeDominant(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return (const Color(0xFF808080), null);
    }
    // ① 过滤 + 收集（698 N54：y 加权——像素权重 1+0.8×y/h，越靠下
    // 权重越高 → 主导色偏向海报下半部，与轮播底缘渐隐带天然协调，
    // 根治「主色和海报色上下不搭」）。
    final pts = <(HSLColor, double)>[];
    final total = width * height;
    var stride = (total / targetSamples).ceil();
    if (stride < 1) stride = 1;
    for (var i = 0; i < total; i += stride) {
      final o = i * 4;
      if (rgba[o + 3] < 128) continue;
      final hsl = HSLColor.fromColor(
          Color.fromARGB(255, rgba[o], rgba[o + 1], rgba[o + 2]));
      if (hsl.lightness > 0.88) continue; // 近白剔除
      if (hsl.lightness < 0.07) continue; // 近黑剔除
      if (hsl.saturation < 0.04) continue; // 近灰剔除
      final y = i ~/ width;
      pts.add((hsl, 1.0 + 0.8 * y / height));
    }
    if (pts.isEmpty) return (const Color(0xFF808080), null);

    // ② K-means 6 簇（轻量迭代——像素量小，8 轮收敛足够）。
    const k = 6;
    final centers = <HSLColor>[];
    for (var i = 0; i < k; i++) {
      centers.add(pts[(i * pts.length) ~/ k].$1);
    }
    var assigns = List<int>.filled(pts.length, 0);
    for (var iter = 0; iter < 8; iter++) {
      for (var i = 0; i < pts.length; i++) {
        var best = 0;
        var bestD = double.infinity;
        for (var c = 0; c < k; c++) {
          final d = _hslDist(pts[i].$1, centers[c]);
          if (d < bestD) {
            bestD = d;
            best = c;
          }
        }
        assigns[i] = best;
      }
      // 簇均值更新（H 圆均值；**y 加权**——下半像素权重高）。
      final sums = List.generate(k, (_) => <double>[0, 0, 0, 0]);
      for (var i = 0; i < pts.length; i++) {
        final c = assigns[i];
        final w = pts[i].$2;
        final hRad = pts[i].$1.hue * 3.1415926535 / 180;
        sums[c][0] += _cos(hRad) * w;
        sums[c][1] += _sin(hRad) * w;
        sums[c][2] += pts[i].$1.lightness * w;
        sums[c][3] += w;
      }
      for (var c = 0; c < k; c++) {
        if (sums[c][3] <= 0) continue;
        final hue = (_atan2(sums[c][1], sums[c][0]) * 180 / 3.1415926535 + 360) % 360;
        centers[c] = HSLColor.fromAHSL(
            1, hue, centers[c].saturation, sums[c][2] / sums[c][3]);
      }
    }

    // ③ 加权占比排序 → top2。
    final counts = List<double>.filled(k, 0);
    for (var i = 0; i < pts.length; i++) {
      counts[assigns[i]] += pts[i].$2;
    }
    final order = [for (var c = 0; c < k; c++) c]
      ..sort((a, b) => counts[b].compareTo(counts[a]));
    final dom = centers[order[0]].toColor();
    final sec = counts[order[1]] > 0 ? centers[order[1]].toColor() : null;
    return (dom, sec);
  }

  static double _cos(double x) {
    // 8 阶泰勒（x∈[-π,π] 足够准）。
    final x2 = x * x;
    return 1 - x2 / 2 * (1 - x2 / 12 * (1 - x2 / 30 * (1 - x2 / 56 * (1 - x2 / 90))));
  }

  static double _sin(double x) {
    final x2 = x * x;
    return x * (1 - x2 / 6 * (1 - x2 / 20 * (1 - x2 / 42 * (1 - x2 / 72))));
  }

  static double _atan2(double y, double x) {
    if (x.abs() > y.abs()) {
      final t = y / x;
      final a = t * (0.97239411 - 0.19194795 * t * t);
      return x > 0 ? a : (y >= 0 ? a + 3.14159265 : a - 3.14159265);
    }
    final t = x / y;
    final a = 1.57079633 - t * (0.97239411 - 0.19194795 * t * t);
    return y > 0 ? a : -a;
  }

  /// K-means 距离（H 色相圆距 + L/S 加权）。
  static double _hslDist(HSLColor a, HSLColor b) {
    final dh = ((a.hue - b.hue + 540) % 360) - 180;
    final dl = a.lightness - b.lightness;
    final ds = a.saturation - b.saturation;
    return dh * dh * 0.5 + dl * dl * 2.0 + ds * ds;
  }

  /// 698 N53：同色调暗氛围派生（spec）——H 保留、L 压 0.11~0.18、
  /// S ×0.75 上限 0.46；深色保底（dominant L<0.12 → 提 0.16 防丢色相）。
  /// 返回 `(top(保底/主调), mid(L0.20), base(L0.14))`；双色流动：色相
  /// 向辅簇微移（top 15% / mid 8% / base 5%）。
  static (Color, Color, Color) ambientTrio(Color dominant, Color? secondary) {
    final src = HSLColor.fromColor(dominant);
    var s = src.saturation * 0.75;
    if (s > 0.46) s = 0.46;
    var l = src.lightness.clamp(0.11, 0.18);
    if (src.lightness < 0.12) l = 0.16; // 深色保底

    double flowHue(double t) {
      if (secondary == null) return src.hue;
      final sh = HSLColor.fromColor(secondary).hue;
      final dh = ((sh - src.hue + 540) % 360) - 180;
      return (src.hue + dh * t + 360) % 360;
    }

    Color at(double t, double lightness) =>
        HSLColor.fromAHSL(1, flowHue(t), s, lightness).toColor();
    return (at(0.15, l), at(0.08, 0.20), at(0.05, 0.14));
  }

  /// 698 N55：设计调色板——**palette_generator（Vibrant.js 同源六 swatch
  /// 目标法）+ color_thief（MMCQ）交叉验证**，替代自研 K-means。
  ///
  /// - 基调（背景底色）= **下半区** darkMuted ?? muted ?? darkVibrant
  ///   ——下半区取色与轮播底缘渐隐带天然协调（根治上下不搭）；
  /// - 晕染（邻色）= 全图 vibrant ?? lightVibrant（鲜色 subtle 混入）；
  /// - color_thief 交叉验证：MMCQ top 色与基调色相接近（≤60°）则采用
  ///   thief 色（两边都认 = 可靠）；差太远信 palette（目标法更设计导向）；
  ///   palette 全空时 thief 顶色兜底。
  /// 测试注入（PaletteGenerator 真异步在 fake-async 测试环境不推进
  /// ——测试注入同步实现；生产走六 swatch + thief 交叉验证）。
  static Future<(Color, Color?)> Function(ui.Image image)? debugExtractPalette;

  static Future<(Color, Color?)> extractDesignPalette(ui.Image image) async {
    if (debugExtractPalette != null) return debugExtractPalette!(image);
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    PaletteGenerator? full;
    PaletteGenerator? lower;
    // spec 过滤（近白/近黑/近灰剔除）——替代默认 avoidRedBlackWhite
    //（默认会避开红色系，红色海报主色丢失的元凶）。
    // PaletteFilter 语义：true = 保留（include）——spec 三剔除的反面。
    bool specFilter(HSLColor hsl) =>
        hsl.lightness <= 0.88 &&
        hsl.lightness >= 0.07 &&
        hsl.saturation >= 0.04;
    try {
      // fromByteData（纯字节，不碰 dart:ui——比 fromImage 稳）。
      final bytes =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes != null) {
        final encoded =
            EncodedImage(bytes, width: image.width, height: image.height);
        full = await PaletteGenerator.fromByteData(encoded,
            maximumColorCount: 16, filters: [specFilter]);
        lower = await PaletteGenerator.fromByteData(
          encoded,
          region: Rect.fromLTWH(0, h / 2, w, h / 2),
          maximumColorCount: 16,
          filters: [specFilter],
        );
      }
    } catch (_) {
      // palette 失败走 thief 兜底。
    }

    final baseSwatch = lower?.darkMutedColor ??
        lower?.mutedColor ??
        lower?.darkVibrantColor ??
        lower?.dominantColor ?? // 下半区主导色兜底（上下协调关键）
        full?.darkMutedColor ??
        full?.mutedColor ??
        full?.darkVibrantColor ??
        full?.dominantColor;
    final washSwatch = full?.vibrantColor ?? full?.lightVibrantColor;

    Color? base = baseSwatch?.color;
    Color? wash = washSwatch?.color;

    // color_thief 交叉验证（RGBA 像素）。
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data != null) {
        final rgba = data.buffer.asUint8List();
        final top = await thief.getPaletteFromBytes(
            rgba, image.width, image.height, 5, 10);
        if (top != null && top.isNotEmpty) {
          final topColor = Color.fromARGB(255, top[0][0], top[0][1], top[0][2]);
          if (base == null) {
            base = topColor; // 兜底
          } else {
            final dh = ((HSLColor.fromColor(topColor).hue -
                        HSLColor.fromColor(base).hue +
                        540) %
                    360) -
                180;
            if (dh.abs() <= 60) {
              base = topColor; // 两边都认 → 采用 thief 顶色
            }
          }
        }
      }
    } catch (_) {
      // thief 失败保持 palette 结果。
    }

    if (base == null) return (const Color(0xFF3A3A3A), wash);
    return (base, wash);
  }

  /// 测试注入（真异步解码在 fake-async 测试环境不推进）。
  static Future<LightField?> Function(ui.Image image)? debugExtractLightField;

  /// 698 N56：海报光场数据（多色调色板 + 3×3 网格光影 + 基调）。
  static Future<LightField?> extractLightField(ui.Image image) async {
    if (debugExtractLightField != null) return debugExtractLightField!(image);
    // ① 多色调色板：thief 6 色 + palette 六 swatch 合并去重（4~6 色）。
    final swatchColors = <Color>[];
    Color? base;
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      final rgba = bytes.buffer.asUint8List();
      final w = image.width;
      final h = image.height;

      // palette 六 swatch。
      bool specFilter(HSLColor hsl) =>
          hsl.lightness <= 0.88 &&
          hsl.lightness >= 0.07 &&
          hsl.saturation >= 0.04;
      try {
        final encoded = EncodedImage(bytes, width: w, height: h);
        final full = await PaletteGenerator.fromByteData(encoded,
            maximumColorCount: 16, filters: [specFilter]);
        final lower = await PaletteGenerator.fromByteData(encoded,
            region: Rect.fromLTWH(0, h / 2, w.toDouble(), h / 2),
            maximumColorCount: 16,
            filters: [specFilter]);
        for (final sc in [
          full.vibrantColor,
          full.lightVibrantColor,
          full.darkVibrantColor,
          full.mutedColor,
          full.lightMutedColor,
          full.darkMutedColor,
        ]) {
          if (sc != null) swatchColors.add(sc.color);
        }
        base = lower.darkMutedColor?.color ??
            lower.mutedColor?.color ??
            lower.darkVibrantColor?.color ??
            lower.dominantColor?.color ??
            full.darkMutedColor?.color ??
            full.mutedColor?.color ??
            full.darkVibrantColor?.color ??
            full.dominantColor?.color;
      } catch (_) {
        // palette 失败走 thief。
      }

      // thief 6 色并入。
      try {
        final top = await thief.getPaletteFromBytes(rgba, w, h, 6, 10);
        if (top != null) {
          for (final c in top) {
            swatchColors.add(Color.fromARGB(255, c[0], c[1], c[2]));
          }
        }
      } catch (_) {
        // thief 失败忽略。
      }

      // 去重（色相+明度近似 12°/0.08 内视为同色）→ 上限 6 色。
      final palette = <Color>[];
      for (final c in swatchColors) {
        final ch = HSLColor.fromColor(c);
        final dup = palette.any((p) {
          final ph = HSLColor.fromColor(p);
          final dh = ((ch.hue - ph.hue + 540) % 360) - 180;
          return dh.abs() < 12 && (ch.lightness - ph.lightness).abs() < 0.08;
        });
        if (!dup && palette.length < 6) palette.add(c);
      }

      // ② 3×3 网格光影：每格像素均色 + 亮度。
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
          if (n == 0) {
            grid.add((base ?? const Color(0xFF808080), 0.2));
            continue;
          }
          final c = Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
          grid.add((c, HSLColor.fromColor(c).lightness));
        }
      }

      if (palette.isEmpty && base != null) palette.add(base);
      return LightField(
        base: base ?? palette.first,
        palette: palette.isEmpty ? [const Color(0xFF808080)] : palette,
        grid: grid,
      );
    } catch (_) {
      return null;
    }
  }

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

  /// 698 N46：**底部垂直三带取色**（背景色场专用）——返回
  /// `[顶衔接色, 中主色, 底深调色]`，分别取自海报底部三带：
  /// y 0.90~1.0（底缘，衔接轮播零分割）/ 0.75~0.90 / 0.60~0.75。
  /// 每带 4-bit 量化取高频桶均色；空带向邻带借（保 3 色恒定）。
  /// 缓存 key `url#bottom3` 与全图 trio 共存；失败返回 null。
  static Future<List<Color>?> extractTrioBottom(String url,
      {Map<String, String>? headers}) {
    return _raw(url, headers: headers, bottom: true);
  }

  /// 读取原始三色组（缓存存 raw，压暗/提亮/中深在各入口按需派生）。
  static Future<List<Color>?> _raw(String url,
      {Map<String, String>? headers, bool bottom = false}) async {
    if (url.isEmpty) return null;
    final key = bottom ? '$url#bottom3' : url;
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _load(url, headers: headers, bottom: bottom);
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(url);
    }
  }

  static Future<List<Color>?> _load(String url,
      {Map<String, String>? headers, bool bottom = false}) async {
    try {
      final source =
          await (debugImageLoader ?? _loadImage)(url, headers: headers)
              .timeout(debugTimeout);
      if (source == null) return null;
      final small = await _downscale(source, sampleSize);
      try {
        final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        final colors = bottom
            ? computeBottom(data.buffer.asUint8List(), small.width, small.height)
            : compute(data.buffer.asUint8List(), small.width, small.height);
        if (colors.isEmpty) return null;
        _putCache(bottom ? '$url#bottom3' : url, colors);
        return colors;
      } finally {
        small.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// 698 N46：底部垂直三带取色——`[顶衔接色, 中主色, 底深调色]`。
  /// 三带：y ∈ [0.90, 1.0] / [0.75, 0.90] / [0.60, 0.75]；每带 4-bit
  /// 量化分桶取最高频桶均色（带内近黑/近白不滤——底段本就深）；
  /// 空带（全透明/噪点）向下方邻带借、仍空则整体失败返回空表。
  static List<Color> computeBottom(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0) return const [];
    if (rgba.length < width * height * 4) return const [];
    const bands = <(double, double)>[
      (0.90, 1.0), // 底缘衔接带（顶段渐变起点）
      (0.75, 0.90), // 中主色带
      (0.60, 0.75), // 深调色带
    ];
    final result = <Color>[];
    for (final (y0, y1) in bands) {
      final counts = <int, int>{};
      final sums = <int, List<int>>{};
      // floor 半开区间 [y0h, y1h)：三带不重叠；极小图保底至少 1 行。
      var rowStart = (height * y0).floor();
      var rowEnd = (height * y1).floor();
      if (rowEnd <= rowStart) rowEnd = rowStart + 1;
      if (rowEnd > height) rowEnd = height;
      if (rowStart < 0) rowStart = 0;
      for (var y = rowStart; y < rowEnd; y++) {
        for (var x = 0; x < width; x++) {
          final offset = (y * width + x) * 4;
          if (rgba[offset + 3] < 128) continue;
          final r = rgba[offset];
          final g = rgba[offset + 1];
          final b = rgba[offset + 2];
          final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
          counts[key] = (counts[key] ?? 0) + 1;
          final sum = sums[key] ??= <int>[0, 0, 0];
          sum[0] += r;
          sum[1] += g;
          sum[2] += b;
        }
      }
      if (counts.isEmpty) {
        // 空带向下方邻带借（result 顺序顶→底，已收的是更靠顶的带）。
        if (result.isNotEmpty) result.add(result.last);
        continue;
      }
      var bestKey = 0;
      var bestCount = -1;
      counts.forEach((key, count) {
        if (count > bestCount) {
          bestCount = count;
          bestKey = key;
        }
      });
      final sum = sums[bestKey]!;
      result.add(Color.fromARGB(
        255,
        sum[0] ~/ bestCount,
        sum[1] ~/ bestCount,
        sum[2] ~/ bestCount,
      ));
    }
    return result;
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

  /// 698 N41 页面背景**纯平色**（主题色退出背景）：深 #0F1116 / 浅
  /// #F4F5F7（由 scaffoldBackgroundColor 传入）。[glow] 非空时顶部叠
  /// 主题色氛围光带（α6%、向下渐隐，首页不传）。
  static Gradient pageFlat(Color base, {Color? glow}) {
    if (glow == null) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [base, base, base],
      );
    }
    final glowMix = Color.lerp(base, glow, 0.06)!;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [glowMix, base, base],
      stops: const [0.0, 0.18, 1.0], // 顶部 ~150px 渐隐到平色
    );
  }

  /// 页面背景垂直渐变：顶部 [accent] 主色 → 底部 [base] 页面底色。
  /// [accent] 为 null 时整页保持 [base]（与取色前视觉一致）。
  /// 【N41 起弃用：主题色退出背景——改用 [pageFlat]。】
  @Deprecated('698 N41: 主题色退出背景，改用 pageFlat')
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

/// 织物微粒噪点层（698 N43）：确定性种子细点阵——微亮/微暗交替 3~5%
/// 亮度差，静态一次绘制（随背景铺满），玻璃折射穿出细腻织纹。
/// 织物微粒噪点蒙层（698 N43）：确定性种子细点阵（微亮/微暗 α 低），
/// 全局叠一层出胶片颗粒/织物细粒感——玻璃折射穿出细腻微纹理。

/// 698 N56：海报光场数据——多色调色板 + 3×3 网格光影 + 基调。
class LightField {
  const LightField({
    required this.base,
    required this.palette,
    required this.grid,
  });

  /// 基调（下半区 darkMuted——S 曲线打底源）。
  final Color base;

  /// 多色调色板（4~6 色，thief + palette 合并去重）。
  final List<Color> palette;

  /// 3×3 网格（9 格：格均色 + 亮度 0~1）。
  final List<(Color, double)> grid;
}
