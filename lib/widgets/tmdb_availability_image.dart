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
  });

  final TmdbAvailability entry;
  final String imageBase;
  final bool backdrop;
  final BoxFit fit;
  final int? cacheWidth;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final tmdbUrl = backdrop
        ? (entry.tmdb.backdropUrl(imageBase) ?? entry.tmdb.posterUrl(imageBase))
        : entry.tmdb.posterUrl(imageBase);
    final fallback = TmdbImage(
      url: tmdbUrl,
      fit: fit,
      cacheWidth: cacheWidth,
      placeholder: transparent ? const SizedBox.shrink() : null,
      errorWidget: transparent ? const SizedBox.shrink() : null,
    );
    final serverUrl = backdrop
        ? (entry.item.backdropWideUrl ??
            entry.item.backdropUrl ??
            entry.item.posterUrl)
        : entry.item.posterUrl;
    if (serverUrl == null || serverUrl.isEmpty) return fallback;
    return EmbyImage(
      url: serverUrl,
      fit: fit,
      cacheWidth: cacheWidth,
      accessToken: entry.server.accessToken,
      placeholder: transparent ? const SizedBox.shrink() : null,
      errorWidget: fallback,
    );
  }
}
