import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';

class TmdbAvailabilityImage extends StatelessWidget {
  const TmdbAvailabilityImage({
    super.key,
    required this.entry,
    required this.imageBase,
    this.backdrop = false,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.transparent = false,
    this.posterSize = 'w500',
    this.backdropSize = 'w1280',
    this.serverMaxHeight,
    this.serverMaxWidth,
    this.showTmdbWhileLoading = false,
    this.fadeInDuration = const Duration(milliseconds: 250),
  });

  final TmdbAvailability entry;
  final String imageBase;
  final bool backdrop;
  final BoxFit fit;
  final int? cacheWidth;
  final bool transparent;

  /// TMDB 海报尺寸；小卡片传 `w154` 可显著减少下载与解码开销。
  final String posterSize;

  /// TMDB 背景尺寸；Hero 主图用 `w780`，虚化背景用 `w300`。
  final String backdropSize;

  /// 服务器图片最大高度（写入 Emby URL）；为空时保留原始 URL。
  final int? serverMaxHeight;

  /// 服务器图片最大宽度（写入 Emby URL）；为空时保留原始 URL。
  final int? serverMaxWidth;

  /// 服务器图加载期间先铺 TMDB 图，避免服务器较慢时整块空白。
  final bool showTmdbWhileLoading;

  final Duration fadeInDuration;

  @override
  Widget build(BuildContext context) {
    final tmdbUrl = backdrop
        ? (entry.tmdb.backdropUrl(imageBase, size: backdropSize) ??
            entry.tmdb.posterUrl(imageBase))
        : entry.tmdb.posterUrl(imageBase, size: posterSize);
    final fallback = TmdbImage(
      url: tmdbUrl,
      fit: fit,
      cacheWidth: cacheWidth,
      fadeInDuration: fadeInDuration,
      placeholder: transparent ? const SizedBox.shrink() : null,
      errorWidget: transparent ? const SizedBox.shrink() : null,
    );
    final serverUrl = backdrop
        ? (entry.item.backdropWideUrl ??
            entry.item.backdropUrl ??
            entry.item.posterUrl)
        : entry.item.posterUrl;
    if (serverUrl == null || serverUrl.isEmpty) return fallback;

    final imageUrl = _withMaxDimensions(
      serverUrl,
      maxHeight: serverMaxHeight,
      maxWidth: serverMaxWidth,
    );
    if (showTmdbWhileLoading) {
      return Stack(
        fit: StackFit.expand,
        children: [
          fallback,
          EmbyImage(
            url: imageUrl,
            fit: fit,
            cacheWidth: cacheWidth,
            accessToken: entry.server.accessToken,
            fadeInDuration: fadeInDuration,
            placeholder: const SizedBox.shrink(),
            errorWidget: const SizedBox.shrink(),
          ),
        ],
      );
    }
    return EmbyImage(
      url: imageUrl,
      fit: fit,
      cacheWidth: cacheWidth,
      accessToken: entry.server.accessToken,
      fadeInDuration: fadeInDuration,
      placeholder: transparent ? const SizedBox.shrink() : null,
      errorWidget: fallback,
    );
  }

  String _withMaxDimensions(
    String url, {
    int? maxHeight,
    int? maxWidth,
  }) {
    if ((maxHeight == null || maxHeight <= 0) &&
        (maxWidth == null || maxWidth <= 0)) {
      return url;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    final query = Map<String, String>.from(uri.queryParameters);
    if (maxHeight != null && maxHeight > 0) {
      query['maxHeight'] = '$maxHeight';
    }
    if (maxWidth != null && maxWidth > 0) {
      query['maxWidth'] = '$maxWidth';
    }
    return uri.replace(queryParameters: query).toString();
  }
}
