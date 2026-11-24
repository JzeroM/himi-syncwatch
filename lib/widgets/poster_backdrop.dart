import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';

/// 698 N44 全屏海报氛围洗背景（参考图同款，零分割感）：
/// 当前 hero 海报 → 全屏 blur(σ30) → 明暗色调处理（暗=混黑 65%+降饱和
/// 蓝灰洗 / 亮=混白 55%+降饱和粉调柔洗）；轮播图与其同源 → 交界天然
/// 连续。轮播切换交叉淡化 600ms；未就绪回退 [PosterPalette.fabricGradient]
///（中性织物微渐变）。织物微粒蒙层在 app builder 全局叠。
class PosterBackdrop extends ConsumerWidget {
  const PosterBackdrop({super.key, required this.base});

  /// 回退基底（scaffoldBackgroundColor）。
  final Color base;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(heroPosterUrlProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: PosterPalette.fabricGradient(base),
      ),
    );
    if (url == null || url.isEmpty) return fallback;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _PosterWash(key: ValueKey(url), url: url, isDark: isDark, fallback: fallback),
    );
  }
}

class _PosterWash extends StatelessWidget {
  const _PosterWash({
    super.key,
    required this.url,
    required this.isDark,
    required this.fallback,
  });

  final String url;
  final bool isDark;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    // 明暗色调矩阵（参考图配比）：
    // 暗 = 饱和×0.6 + 混黑 65%（蓝灰洗）；亮 = 饱和×0.4 + 混白 55% + 明度↑（粉调柔洗）。
    final sat = isDark ? 0.6 : 0.4;
    final mix = isDark ? 0.65 : 0.55; // 混黑/混白比
    final List<double> satMatrix = [
      // 饱和度矩阵（luma 保持）。
      0.213 + 0.787 * sat, 0.715 - 0.715 * sat, 0.072 - 0.072 * sat, 0, 0,
      0.213 - 0.213 * sat, 0.715 + 0.285 * sat, 0.072 - 0.072 * sat, 0, 0,
      0.213 - 0.213 * sat, 0.715 - 0.715 * sat, 0.072 + 0.928 * sat, 0, 0,
      0, 0, 0, 1, 0,
    ];
    final double mv = isDark ? 0.0 : 55.0 * 0.45; // 亮套轻提明
    final List<double> mixMatrix = [
      1 - mix, 0, 0, 0, (isDark ? 0 : 255 * mix) + mv,
      0, 1 - mix, 0, 0, (isDark ? 0 : 255 * mix) + mv,
      0, 0, 1 - mix, 0, (isDark ? 0 : 255 * mix) + mv,
      0, 0, 0, 1, 0,
    ];
    return SizedBox.expand(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(mixMatrix),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(satMatrix),
            child: Image(
              image: CachedNetworkImageProvider(url),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => fallback,
            ),
          ),
        ),
      ),
    );
  }
}
