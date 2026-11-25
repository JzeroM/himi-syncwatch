import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';

/// 698 N50 纯三带色场背景（极简）：
/// 海报底部垂直三带取色（[PosterPalette.extractTrioBottom]）→ **7 段
/// 氛围编排**渐变（顶部呼吸 → 中部饱满 → 底部沉稳）。
///
/// 零分割：顶段 0.00 = 底缘带取色**原色**（与轮播底部渐隐终点完全一致）。
/// 无明暗派生（原色鲜活）、无模糊层、无暗角聚光（极简，GPU≈0）。
/// 轮播切换交叉淡化 600ms；取色未就绪保持旧场（不闪平色）。
/// 首页与非首页共用（main_shell/app builder 全局层一处渲染）。
class PosterBackdrop extends ConsumerStatefulWidget {
  const PosterBackdrop({super.key, required this.base});

  /// 回退基底（scaffoldBackgroundColor）。
  final Color base;

  @override
  ConsumerState<PosterBackdrop> createState() => _PosterBackdropState();
}

class _PosterBackdropState extends ConsumerState<PosterBackdrop> {
  /// 最近一次成功的三带取色——新海报取色未就绪时保持旧场。
  List<Color>? _lastTrio;

  @override
  Widget build(BuildContext context) {
    final url = ref.watch(heroPosterUrlProvider);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(color: widget.base),
      child: const SizedBox.expand(),
    );
    if (url == null || url.isEmpty) return fallback;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _PosterField(
        key: ValueKey(url),
        url: url,
        fallback: fallback,
        lastTrio: _lastTrio,
        onTrio: (trio) => _lastTrio = trio,
      ),
    );
  }
}

class _PosterField extends StatefulWidget {
  const _PosterField({
    super.key,
    required this.url,
    required this.fallback,
    this.lastTrio,
    this.onTrio,
  });

  final String url;
  final Widget fallback;

  /// 上一张海报的三带色（取色未就绪时保持旧场）。
  final List<Color>? lastTrio;

  /// 取色成功回报。
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
    final trio = _trio ?? widget.lastTrio;
    if (trio == null) return widget.fallback;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: ambientFieldGradient(trio[0], trio[1], trio[2]),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// 698 N50 三带色场 7 段氛围编排（纯渐变，无派生）：
/// `[顶衔接原色, 呼吸提明, 色彩升腾, 主色最饱满, 主色微沉, 深调, 深调收边]`。
///
/// 零分割关键：**0.00 段 = [edge] 原色**（与轮播底部渐隐终点同源同值）；
/// 提亮/升腾都从 0.08 之后开始。
Gradient ambientFieldGradient(Color edge, Color mid, Color deep) {
  Color lift(Color c, double delta) {
    var hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness + delta).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }

  Color saturateUp(Color c, double delta) {
    var hsl = HSLColor.fromColor(c);
    final s = (hsl.saturation + delta).clamp(0.0, 1.0);
    return hsl.withSaturation(s).toColor();
  }

  final rise = Color.lerp(edge, mid, 0.5)!;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      edge, // 0.00 底缘原色（零分割）
      lift(edge, 0.06), // 顶部呼吸
      saturateUp(rise, 0.08), // 色彩升腾
      mid, // 主色最饱满
      lift(mid, -0.08), // 主色微沉
      deep, // 深调
      lift(deep, -0.06), // 深调收边
    ],
    stops: const [0.0, 0.08, 0.28, 0.48, 0.70, 0.88, 1.0],
  );
}
