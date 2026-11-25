import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';

/// 698 N46 全屏背景 = 轮播海报**底部垂直三带取色**纯渐变色场：
/// `[顶衔接色, 中主色, 底深调色]`（[PosterPalette.extractTrioBottom]），
/// 顶段起点 = 海报底缘色 → 与轮播交界天然零分割。
///
/// 明暗派生**保色**（体现背景色，不太亮不太暗）：
/// 暗版混黑 35% + 饱和×0.7、L 钳 0.25~0.45；亮版混白 30% + 饱和×0.75、
/// L 钳 0.65~0.85。叠加**暗角聚光**（边缘暗角 + 顶部中心柔光斑，
/// N46 起替代织物微粒）。轮播切换交叉淡化 600ms；取色未就绪/失败回退
/// 平色基底（同样叠暗角聚光）。首页与非首页共用（main_shell 一处渲染）。
class PosterBackdrop extends ConsumerStatefulWidget {
  const PosterBackdrop({super.key, required this.base});

  /// 回退基底（scaffoldBackgroundColor）。
  final Color base;

  @override
  ConsumerState<PosterBackdrop> createState() => _PosterBackdropState();
}

class _PosterBackdropState extends ConsumerState<PosterBackdrop> {
  /// 698 N48：最近一次成功的三带取色——新海报取色未就绪时保持旧场
  ///（不闪平色），就绪后交叉淡化（消除「下方背景是上一张」的跳变面）。
  List<Color>? _lastTrio;

  @override
  Widget build(BuildContext context) {
    final url = ref.watch(heroPosterUrlProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(color: _derived(widget.base, isDark)),
      child: _vignetteAndSpotlight(),
    );
    if (url == null || url.isEmpty) return fallback;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _PosterField(
        key: ValueKey(url),
        url: url,
        isDark: isDark,
        fallback: fallback,
        lastTrio: _lastTrio,
        onTrio: (trio) => _lastTrio = trio,
      ),
    );
  }
}

/// 单张海报的取色色场（stateful：取色异步一次，缓存命中即返回）。
class _PosterField extends StatefulWidget {
  const _PosterField({
    super.key,
    required this.url,
    required this.isDark,
    required this.fallback,
    this.lastTrio,
    this.onTrio,
  });

  final String url;
  final bool isDark;
  final Widget fallback;

  /// 上一张海报的三带色（取色未就绪时保持旧场）。
  final List<Color>? lastTrio;

  /// 取色成功回报（供外层保存 lastTrio）。
  final ValueChanged<List<Color>>? onTrio;

  @override
  State<_PosterField> createState() => _PosterFieldState();
}

class _PosterFieldState extends State<_PosterField> {
  List<Color>? _trio;

  @override
  void initState() {
    super.initState();
    PosterPalette.extractTrioBottom(widget.url).then((trio) {
      if (mounted && trio != null && trio.length == 3) {
        widget.onTrio?.call(trio);
        setState(() => _trio = trio);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 698 N48：取色未就绪 → 保持旧场（无跳变）；旧场也无 → 回退平色。
    final trio = _trio ?? widget.lastTrio;
    if (trio == null) return widget.fallback;
    // 顶段 = 底缘衔接色（与轮播交界同色）→ 中主色 → 底深调色。
    final colors = [
      _derived(trio[0], widget.isDark),
      _derived(trio[1], widget.isDark),
      _derived(trio[2], widget.isDark),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 698 N49：首页同款模糊海报氛围层（blur σ36 + 黑渐变压暗 +
          // 垂直渐隐）——所有页背景观感 = 首页（浮块折射观感自然一致）。
          _AmbientWash(url: widget.url),
          _vignetteAndSpotlight(),
        ],
      ),
    );
  }
}

/// 首页同款模糊海报氛围层（与 HomeHeroBackground 同公式：同源 hero 海报
/// blur σ36、scale 1.35、黑渐变 0.30→0.42→渐隐透明）。
class _AmbientWash extends StatelessWidget {
  const _AmbientWash({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
            child: Transform.scale(
              scale: 1.35,
              child: Image(
                image: CachedNetworkImageProvider(url),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x4D000000), // 黑 α0.30
                  Color(0x6B000000), // 黑 α0.42
                  Colors.transparent,
                  Colors.transparent,
                ],
                stops: [0.0, 0.5, 0.85, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 暗角聚光双层（色场/回退共用）：暗角（边缘压暗）+ 聚光（顶部柔光斑）。
Widget _vignetteAndSpotlight() => DecoratedBox(
      decoration: BoxDecoration(gradient: _vignetteGradient()),
      child: const DecoratedBox(
        decoration: BoxDecoration(gradient: _spotlightGradient),
        child: SizedBox.expand(),
      ),
    );

/// 明暗派生（保色原则：背景色清晰可辨，不太亮不太暗）：
/// 暗版混黑 35% + 饱和×0.7 + L∈[0.25, 0.45]；
/// 亮版混白 30% + 饱和×0.75 + L∈[0.65, 0.85]。
Color _derived(Color source, bool isDark) {
  final mixed = Color.lerp(source, isDark ? Colors.black : Colors.white,
      isDark ? 0.35 : 0.30)!;
  var hsl = HSLColor.fromColor(mixed);
  hsl = hsl.withSaturation(hsl.saturation * (isDark ? 0.7 : 0.75));
  final l = hsl.lightness;
  if (isDark) {
    if (l < 0.25) hsl = hsl.withLightness(0.25);
    if (l > 0.45) hsl = hsl.withLightness(0.45);
  } else {
    if (l < 0.65) hsl = hsl.withLightness(0.65);
    if (l > 0.85) hsl = hsl.withLightness(0.85);
  }
  return hsl.toColor();
}

/// 暗角聚光 · 暗角层（边缘压暗四角，中心透）。
Gradient _vignetteGradient() => const RadialGradient(
      center: Alignment(0, -0.15),
      radius: 1.25,
      colors: [
        Colors.transparent,
        Colors.transparent,
        Color(0x40000000),
      ],
      stops: [0.0, 0.62, 1.0],
    );

/// 暗角聚光 · 聚光层（顶部中心柔光斑，白 α0.08 渐隐）。
const Gradient _spotlightGradient = RadialGradient(
  center: Alignment(0, -1.1),
  radius: 1.6,
  colors: [
    Color(0x14FFFFFF),
    Colors.transparent,
  ],
  stops: [0.0, 1.0],
);
