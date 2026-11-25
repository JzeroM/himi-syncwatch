import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';

/// 698 N53 背景 = 轮播海报 **dominant 取色渐变遮罩**（同色调暗氛围）：
/// 海报降采样解码（宽 8px）→ [PosterPalette.computeDominant]（过滤 +
/// K-means 6 簇最大占比簇）→ [PosterPalette.ambientTrio]（H 保留、
/// L 压 0.11~0.18、S ×0.75 上限 0.46、深色保底）→ **S 曲线明度渐变**
/// （顶部缓入 → 中部饱满 → 底部缓沉）+ 双色微流动 + 短色弧过渡。
///
/// 白字自适应压暗：按 dominant 原始亮度动态压暗（亮海报多压/暗海报
/// 少压，白字对比恒可读）。零分割 = 轮播底部渐隐带 alpha 溶解。
/// 保持旧场 / 预暖 / 600ms 交叉淡化 / TV 平色（无海报 URL 回退）。
class PosterBackdrop extends ConsumerStatefulWidget {
  const PosterBackdrop({super.key, required this.base});

  /// 回退基底（scaffoldBackgroundColor）。
  final Color base;

  @override
  ConsumerState<PosterBackdrop> createState() => _PosterBackdropState();
}

class _PosterBackdropState extends ConsumerState<PosterBackdrop> {
  /// 取色渐变缓存（url → (渐变带色, 邻色晕染色)）。
  static final Map<String, (List<Color>, Color?)> _fieldCache = {};

  /// 当前已就绪的海报 URL（渐变算好才切换——保持旧场）。
  String? _readyUrl;

  (List<Color>, Color?)? get _field =>
      _readyUrl == null ? null : _fieldCache[_readyUrl];

  @override
  Widget build(BuildContext context) {
    final url = ref.watch(heroPosterUrlProvider);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(color: widget.base),
      child: const SizedBox.expand(),
    );
    if (url == null || url.isEmpty) return fallback;

    // 新图就绪检测：解码 → dominant → 渐变算好才切（保持旧场）。
    if (url != _readyUrl && !_fieldCache.containsKey(url)) {
      final provider = _ambientProvider(url);
      final stream = provider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        stream.removeListener(listener);
        _extractField(info.image).then((field) {
          if (mounted && field != null) {
            setState(() {
              _fieldCache[url] = field;
              _readyUrl = url;
            });
          }
        });
      }, onError: (_, __) {
        stream.removeListener(listener);
      });
      stream.addListener(listener);
    } else if (_fieldCache.containsKey(url) && url != _readyUrl) {
      _readyUrl = url;
    }

    final field = _field;
    if (field == null) return fallback;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _FieldMask(
        key: ValueKey(_readyUrl),
        field: field.$1,
        wash: field.$2,
      ),
    );
  }

  /// dominant 提取 → 同色调派生 → S 曲线渐变带（短色弧展开）+ 邻色晕染色。
  Future<(List<Color>, Color?)?> _extractField(ui.Image image) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final rgba = data.buffer.asUint8List();
      final (dominant, secondary) =
          PosterPalette.computeDominant(rgba, image.width, image.height);
      final (top, mid, base) =
          PosterPalette.ambientTrio(dominant, secondary);

      // S 曲线明度（顶部缓入 → 中部饱满 → 底部缓沉），5 关键停点。
      final anchorColors = <Color>[top, mid, mid, base, base];

      // 短色弧展开：相邻关键停点间 HSL 短路径插 2 子点 → 11 停点。
      final out = <Color>[];
      for (var i = 0; i < anchorColors.length - 1; i++) {
        final a = HSLColor.fromColor(anchorColors[i]);
        final b = HSLColor.fromColor(anchorColors[i + 1]);
        final dh = ((b.hue - a.hue + 540) % 360) - 180;
        for (var t = 0; t < 3; t++) {
          final f = t / 3;
          out.add(HSLColor.fromAHSL(
            1,
            (a.hue + dh * f + 360) % 360,
            a.saturation + (b.saturation - a.saturation) * f,
            a.lightness + (b.lightness - a.lightness) * f,
          ).toColor());
        }
      }
      out.add(anchorColors.last);
      // 698 N54：邻色晕染色 = 辅簇同色调派生（L 提到 0.32 柔和混入）。
      final wash = secondary == null
          ? null
          : PosterPalette.ambientTrio(secondary, dominant).$1;
      return (out, wash);
    } catch (_) {
      return null;
    }
  }
}

/// 预热背景海报图（轮播切页前调——ImageCache 解码缓存命中，切换即时）。
void precacheAmbientPoster(String url) {
  _ambientProvider(url).resolve(const ImageConfiguration());
}

/// 测试注入（默认 null = 生产 CachedNetworkImageProvider）。
ImageProvider Function(String url)? debugAmbientImageProvider;

/// 降采样海报 provider（宽 8px 解码——dominant 取色源）。
ImageProvider _ambientProvider(String url) => ResizeImage(
      debugAmbientImageProvider?.call(url) ?? CachedNetworkImageProvider(url),
      width: 8,
      allowUpscaling: true,
    );

/// dominant 同色调渐变遮罩场。
class _FieldMask extends StatelessWidget {
  const _FieldMask({super.key, required this.field, this.wash});

  /// S 曲线短色弧渐变带（11 停点）。
  final List<Color> field;

  /// 698 N54：邻色晕染色（辅簇派生，右上对角小面积柔混）。
  final Color? wash;

  @override
  Widget build(BuildContext context) {
    final n = field.length;
    // 白字自适应压暗：按渐变带（=dominant 派生）亮度动态定压暗强度。
    final avgL =
        field.map((c) => HSLColor.fromColor(c).lightness).reduce((a, b) => a + b) /
            n;
    // 平均 L≈0.17（spec 压暗区）→ 压暗微弱；若偏亮（保底路径）则多压。
    final darkAlpha = (0.18 + (avgL - 0.12) * 0.9).clamp(0.08, 0.38);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: field,
          stops: [for (var i = 0; i < n; i++) i / (n - 1)],
        ),
      ),
      child: DecoratedBox(
        // 698 N54：邻色晕染（辅簇对角径向柔混，subtle 多色氛围）。
        decoration: BoxDecoration(
          gradient: wash == null
              ? null
              : RadialGradient(
                  center: const Alignment(0.95, -1.05),
                  radius: 1.15,
                  colors: [
                    wash!.withValues(alpha: 0.16),
                    wash!.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 1.0],
                ),
        ),
        child: DecoratedBox(
          // 自适应压暗（白字可读）+ 顶部微受光。
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0x0AFFFFFF), // 顶部受光微亮
                Color.fromARGB((darkAlpha * 0.55 * 255).round(), 0, 0, 0),
                Color.fromARGB((darkAlpha * 255).round(), 0, 0, 0),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
