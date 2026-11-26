import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';

/// 698 N56 背景 = **多色海报光场**（与原海报光影一致 + 微随机）：
///
/// - 底：下半区 darkMuted 同色调派生 **S 曲线明度渐变**（L 压 0.11~0.18
///   第一道压暗保留；**第二道自适应黑幕已删**——零分割更纯、白字由
///   派生 L 钳 + 受光球上限保证）
/// - 光场：3×3 网格光影（每格色+亮度）→ **9 颗大半径径向光球**——
///   亮格→鲜色受光球（L≤0.26 保白字）、暗格→基调压暗球；位置/半径
///   微随机抖动（种子=URL hash——同海报稳定、换海报换光场）
/// - 观感 = 海报光影构图的放大抽象（afusekt 氛围感），每张海报不同
///
/// 保持旧场 / 预暖 / 600ms 交叉淡化 / TV 平色（无海报 URL 回退）。
class PosterBackdrop extends ConsumerStatefulWidget {
  const PosterBackdrop({super.key, required this.base});

  /// 回退基底（scaffoldBackgroundColor）。
  final Color base;

  @override
  ConsumerState<PosterBackdrop> createState() => _PosterBackdropState();
}

class _PosterBackdropState extends ConsumerState<PosterBackdrop> {
  /// 光场缓存（url → LightField）。
  static final Map<String, LightField> _fieldCache = {};

  /// 当前已就绪的海报 URL（光场算好才切换——保持旧场）。
  String? _readyUrl;

  LightField? get _field => _readyUrl == null ? null : _fieldCache[_readyUrl];

  @override
  Widget build(BuildContext context) {
    final url = ref.watch(heroPosterUrlProvider);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(color: widget.base),
      child: const SizedBox.expand(),
    );
    if (url == null || url.isEmpty) return fallback;

    // 新图就绪检测：解码 → 光场算好才切（保持旧场）。
    if (url != _readyUrl && !_fieldCache.containsKey(url)) {
      final provider = _ambientProvider(url);
      final stream = provider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        stream.removeListener(listener);
        PosterPalette.extractLightField(info.image).then((field) {
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
      child: _LightFieldMask(
        key: ValueKey(_readyUrl),
        field: field,
        seedKey: _readyUrl!,
      ),
    );
  }
}

/// 预热背景海报图（轮播切页前调——ImageCache 解码缓存命中，切换即时）。
void precacheAmbientPoster(String url) {
  _ambientProvider(url).resolve(const ImageConfiguration());
}

/// 测试注入（默认 null = 生产 CachedNetworkImageProvider）。
ImageProvider Function(String url)? debugAmbientImageProvider;

/// 降采样海报 provider（宽 8px 解码——光场取色源）。
ImageProvider _ambientProvider(String url) => ResizeImage(
      debugAmbientImageProvider?.call(url) ?? CachedNetworkImageProvider(url),
      width: 8,
      allowUpscaling: true,
    );

/// 多色海报光场渲染：S 曲线底 + 9 颗随机光球。
class _LightFieldMask extends StatelessWidget {
  const _LightFieldMask({
    super.key,
    required this.field,
    required this.seedKey,
  });

  final LightField field;
  final String seedKey;

  @override
  Widget build(BuildContext context) {
    final (top, mid, base) = PosterPalette.ambientTrio(field.base, null);
    // S 曲线三明度档 → 5 停点渐变（缓入/饱满/缓沉）。
    final n = 5;
    final curve = <Color>[top, mid, mid, base, base];

    // 随机光球（种子=URL hash——同海报稳定）。
    final rand = math.Random(seedKey.hashCode);
    final avgL = field.grid.map((g) => g.$2).reduce((a, b) => a + b) /
        field.grid.length;
    final balls = <Widget>[];
    for (var i = 0; i < field.grid.length; i++) {
      final (cellColor, luma) = field.grid[i];
      final gx = i % 3;
      final gy = i ~/ 3;
      // 位置：格中心 + 微随机抖动（±12% 屏）。
      final cx = (gx + 0.5) / 3 + (rand.nextDouble() - 0.5) * 0.24;
      final cy = (gy + 0.5) / 3 + (rand.nextDouble() - 0.5) * 0.24;
      // 半径：0.6~1.4 屏宽大柔边（随机）。
      final radius = 0.6 + rand.nextDouble() * 0.8;
      final bright = luma > avgL;
      // 受光球：鲜色派生提明（上限 L≤0.26 保白字）；阴影球：基调压暗。
      Color ballColor;
      double alpha;
      if (bright) {
        var hsl = HSLColor.fromColor(cellColor);
        // 698 N57 提亮：受光球上限 L≤0.38（白字对比仍安全）。
        final l = (hsl.lightness * 0.45 + 0.18).clamp(0.0, 0.38);
        ballColor = hsl.withLightness(l).withSaturation(hsl.saturation * 0.8).toColor();
        alpha = 0.10 + rand.nextDouble() * 0.08;
      } else {
        var hsl = HSLColor.fromColor(base);
        ballColor =
            hsl.withLightness((hsl.lightness * 0.8).clamp(0.0, 0.22)).toColor();
        alpha = 0.12 + rand.nextDouble() * 0.08;
      }
      balls.add(
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(cx * 2 - 1, cy * 2 - 1),
                radius: radius,
                colors: [
                  ballColor.withValues(alpha: alpha),
                  ballColor.withValues(alpha: 0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 底：S 曲线同色调暗渐变（第一道压暗）。
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: curve,
              stops: [for (var i = 0; i < n; i++) i / (n - 1)],
            ),
          ),
        ),
        // 光场：9 颗随机光球（明暗交错，海报光影抽象）。
        ...balls,
      ],
    );
  }
}
