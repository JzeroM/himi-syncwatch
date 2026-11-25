import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/palette_provider.dart';

/// 698 N51 背景 = 当前轮播图**高斯模糊氛围场**（细节全抹）：
/// 海报降采样解码（宽 24px——解码级局部像素加权平均）→ 放大铺全屏
/// （双线性再平均）+ 轻 blur σ10——细节完全抹掉、只剩大色块明暗流动
/// （afusekt 参考图云雾氛围本源）。
///
/// **梯度压暗**（零分割关键）：顶部交界带几乎不压（混黑 ~8%，与轮播
/// 底缘同明度溶解）→ 往下渐增到底部 ~30%——明暗流动光感（顶部受光/
/// 底部沉暗）+ 白字可读（中下部 L≤0.45）。
///
/// 降饱和 ×0.85（背景退后不抢戏）；同源零分割（与轮播同一张海报 +
/// 底部渐隐带溶解）；轮播切换 600ms 交叉淡化；新图就绪前保持旧场。
/// 无海报 URL 回退平色（TV 拍板不变）。
class PosterBackdrop extends ConsumerStatefulWidget {
  const PosterBackdrop({super.key, required this.base});

  /// 回退基底（scaffoldBackgroundColor）。
  final Color base;

  @override
  ConsumerState<PosterBackdrop> createState() => _PosterBackdropState();
}

class _PosterBackdropState extends ConsumerState<PosterBackdrop> {
  /// 当前已就绪的海报 URL（图片解码完成才切换——保持旧场）。
  String? _readyUrl;

  @override
  Widget build(BuildContext context) {
    final url = ref.watch(heroPosterUrlProvider);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(color: widget.base),
      child: const SizedBox.expand(),
    );
    if (url == null || url.isEmpty) return fallback;

    // 新图就绪检测：ImageStream resolve 出首帧后才切（保持旧场）。
    if (url != _readyUrl) {
      final provider = _ambientProvider(url);
      final stream = provider.resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener((_, __) {
        stream.removeListener(listener);
        if (mounted) setState(() => _readyUrl = url);
      }, onError: (_, __) {
        stream.removeListener(listener);
      });
      stream.addListener(listener);
    }

    final shown = _readyUrl;
    if (shown == null) return fallback;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _AmbientField(key: ValueKey(shown), url: shown),
    );
  }
}

/// 预热背景海报图（轮播切页前调——ImageCache 解码缓存命中，切换即时）。
void precacheAmbientPoster(String url) {
  _ambientProvider(url).resolve(const ImageConfiguration());
}

/// 测试注入（默认 null = 生产 CachedNetworkImageProvider）。
ImageProvider Function(String url)? debugAmbientImageProvider;

/// 降采样海报 provider（宽 24px 解码——局部像素加权平均抹细节）。
ImageProvider _ambientProvider(String url) => ResizeImage(
      debugAmbientImageProvider?.call(url) ?? CachedNetworkImageProvider(url),
      width: 24,
      allowUpscaling: true,
    );

class _AmbientField extends StatelessWidget {
  const _AmbientField({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 降采样海报放大 + 轻模糊（细节全抹，大色块明暗流动）。
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: ColorFiltered(
            // 降饱和 ×0.85（背景退后不抢戏）——饱和度矩阵。
            colorFilter: const ui.ColorFilter.matrix(<double>[
              0.9275, 0.0725, 0, 0, 0,
              0.01075, 0.98925, 0, 0, 0,
              0, 0.0725, 0.9275, 0, 0,
              0, 0, 0, 1, 0,
            ]),
            child: Image(
              image: _ambientProvider(url),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
        // 梯度压暗（零分割 + 明暗流动 + 白字可读）：
        // 顶部受光微亮 → 中部渐暗 → 底部沉暗（~30%）。
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x0FFFFFFF), // 顶部受光微亮（白 α0.06）
                Color(0x00000000),
                Color(0x24000000), // 中部暗 α0.14
                Color(0x4D000000), // 底部沉暗 α0.30
              ],
              stops: [0.0, 0.18, 0.55, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}
