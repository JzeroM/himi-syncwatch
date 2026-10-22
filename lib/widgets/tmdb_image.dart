import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// TMDB 图片（无 Emby 鉴权头），统一占位/失败样式。
class TmdbImage extends StatelessWidget {
  const TmdbImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.placeholder,
    this.errorWidget,
  });

  final String? url;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    final value = url;
    if (value == null || value.isEmpty) {
      return errorWidget ?? const _Fallback();
    }
    return CachedNetworkImage(
      imageUrl: value,
      fit: fit,
      memCacheWidth: cacheWidth,
      placeholder: (_, __) =>
          placeholder ?? const ColoredBox(color: Color(0xFF23252A)),
      errorWidget: (_, __, ___) => errorWidget ?? const _Fallback(),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF2A2D33),
      child: Center(
        child: Icon(Icons.movie_outlined, color: Colors.white38, size: 34),
      ),
    );
  }
}
