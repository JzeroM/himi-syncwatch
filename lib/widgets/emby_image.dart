import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';

class EmbyImage extends ConsumerWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? errorWidget;
  final Widget? placeholder;

  /// 解码目标宽（像素，已含 dpr）：非空时按此宽度解码，
  /// 避免原图全尺寸解码的主线程开销（网格/列表海报按显示宽传入）。
  final int? cacheWidth;

  /// 显式图片 Token：跨服务器聚合条目必须传来源服务器 Token。
  final String? accessToken;

  /// 图片加载完成后的淡入时长；小尺寸海报可缩短以减少迟滞感。
  final Duration fadeInDuration;

  const EmbyImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorWidget,
    this.placeholder,
    this.cacheWidth,
    this.accessToken,
    this.fadeInDuration = const Duration(milliseconds: 250),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (url == null || url!.isEmpty) {
      return errorWidget ?? _defaultError();
    }

    final config = ref.watch(embyConfigProvider);
    final token = accessToken ?? config?.accessToken;

    final headers = <String, String>{
      if (token != null) 'X-Emby-Token': token,
    };

    return CachedNetworkImage(
      imageUrl: url!,
      httpHeaders: headers,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheWidth,
      fadeInDuration: fadeInDuration,
      // 默认占位用静态灰块（698）：转圈 spinner 是永动动画——图片未落定
      // 期间每张海报一个持续 ticker（列表滚动 N 张 = N 个永动源，拖累帧率），
      // 测试环境 pumpAndSettle 也因此永不收敛。静态占位 + 加载完成淡入
      // （[fadeInDuration]）为标准做法；需要转圈的调用方可经 [placeholder]
      // 显式传入。
      placeholder: (_, __) => placeholder ?? Container(color: Colors.grey[850]),
      errorWidget: (_, __, ___) => errorWidget ?? _defaultError(),
    );
  }

  Widget _defaultError() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Icon(Icons.movie, size: 48, color: Colors.grey),
      ),
    );
  }
}
