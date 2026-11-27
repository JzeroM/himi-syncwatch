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
    // 698 N58 零分割回归：顶带 = 海报底缘带**原色**（轻混基调 15%）——
    // 与轮播底缘渐隐终点机械同色，根治首页分割感。
    final edgeTop = Color.lerp(field.edge, top, 0.15)!;
    // S 曲线三明度档 → 5 停点渐变（顶=衔接原色 → 饱满 → 缓沉）。
    final n = 5;
    final curve = <Color>[edgeTop, mid, mid, base, base];

    // 698 N58 光场质感：5 颗**超大光域**（大块柔和明暗流动，afusekt
    // 质感——替代 N56 的 9 碎球）；种子=URL hash 同海报稳定。
    final rand = math.Random(seedKey.hashCode);
    // 取明暗最分明的 5 格（3 亮 2 暗——光域明暗交错）。
    final cells = [...field.grid];
    cells.sort((a, b) => b.$2.compareTo(a.$2));
    final brightCells = cells.take(3).toList();
    final darkCells = cells.reversed.take(2).toList();
    final balls = <Widget>[];
    for (var i = 0; i < 5; i++) {
      final bright = i < 3;
      // 698 N71：首球色贴海报底缘色（hero 渐隐终点连续——过渡分割感）。
      final (rawColor, _) = bright ? brightCells[i] : darkCells[i - 3];
      // 698 N71：顶光域色向 hero 底缘色靠（溶解终点连续）。
      final cellColor =
          i == 0 ? Color.lerp(field.edge, rawColor, 0.5)! : rawColor;
      // 位置：全屏散布（微随机避开死板对称）。
      final cx = 0.12 + (i * 0.19) % 0.76 + (rand.nextDouble() - 0.5) * 0.18;
      final cy = 0.12 + (i * 0.31) % 0.76 + (rand.nextDouble() - 0.5) * 0.18;
      // 698 N70：超大光域云雾（afusekt 氛围）——1.5~2.2 屏宽超大柔边。
      final radius = 1.5 + rand.nextDouble() * 0.7;
      Color ballColor;
      double alpha;
      if (bright) {
        var hsl = HSLColor.fromColor(cellColor);
        // 698 N70 云雾：饱和加深 S×1.2、受光更亮（钳 0.42 保白字）。
        final l = (hsl.lightness * 0.55 + 0.20).clamp(0.0, 0.42);
        ballColor = hsl
            .withLightness(l)
            .withSaturation((hsl.saturation * 1.2).clamp(0.0, 0.85))
            .toColor();
        alpha = 0.22 + rand.nextDouble() * 0.10; // 明暗对比加强
      } else {
        var hsl = HSLColor.fromColor(base);
        ballColor = hsl
            .withLightness((hsl.lightness * 0.62).clamp(0.0, 0.20))
            .withSaturation((hsl.saturation * 1.1).clamp(0.0, 0.75))
            .toColor();
        alpha = 0.24 + rand.nextDouble() * 0.08; // 阴影更深
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

/// 698 N74b：全局背景层 GlobalKey——玻璃折射（水滴/浮块/标签）采样此
/// 边界 → 透视显示真实背景色（非黑）。
final GlobalKey posterBackdropKey = GlobalKey(debugLabel: 'posterBackdrop');
