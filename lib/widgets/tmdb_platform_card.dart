import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tmdb_availability_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

class TmdbPlatformCard extends StatelessWidget {
  const TmdbPlatformCard({
    super.key,
    required this.showcase,
    required this.imageBase,
    required this.onTap,
    this.width = 170,
    this.height = 84,
    this.serverLookupComplete = true,
  });

  final TmdbPlatformShowcase showcase;
  final String imageBase;
  final VoidCallback onTap;
  final double width;
  final double height;

  /// 服务器海报是否已全部反查完成；false 时缺失海报使用中性骨架，
  /// 不提前加载 TMDB 图。
  final bool serverLookupComplete;

  @override
  Widget build(BuildContext context) {
    final platform = showcase.platform;
    final posters = showcase.posters.take(2).toList(growable: false);
    return SizedBox(
      width: width,
      height: height,
      child: TvFocusable(
        radius: 18,
        onTap: onTap,
        child: GlassContainer(
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          showShadow: false,
          child: Row(
            children: [
              SizedBox(
                width: 58,
                height: height - 16,
                child: _PosterStack(
                  platformId: platform.providerId,
                  posters: posters,
                  imageBase: imageBase,
                  serverLookupComplete: serverLookupComplete,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Center(
                  child: Image.asset(
                    platform.logoAsset,
                    key: ValueKey('tmdbPlatformLogo_${platform.providerId}'),
                    height: 20,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (context, error, stackTrace) {
                      return _PlatformName(name: platform.name);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterStack extends StatelessWidget {
  const _PosterStack({
    required this.platformId,
    required this.posters,
    required this.imageBase,
    required this.serverLookupComplete,
  });

  static const double _posterWidth = 38;
  static const double _posterHeight = 54;

  final int platformId;
  final List<TmdbPlatformPoster> posters;
  final String imageBase;
  final bool serverLookupComplete;

  @override
  Widget build(BuildContext context) {
    final empty = posters.isEmpty;
    final hasBack = posters.length > 1;
    return Center(
      child: SizedBox(
        width: 58,
        height: 60,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (empty)
              Positioned(
                left: 16,
                top: 0,
                child: Transform.rotate(
                  angle: 0.06,
                  child: _PosterTile(
                    key: ValueKey('tmdbPlatformPoster_${platformId}_1'),
                    poster: null,
                    imageBase: imageBase,
                    width: _posterWidth,
                    height: _posterHeight,
                    serverLookupComplete: serverLookupComplete,
                  ),
                ),
              )
            else if (hasBack)
              Positioned(
                left: 16,
                top: 0,
                child: Transform.rotate(
                  angle: 0.06,
                  child: _PosterTile(
                    key: ValueKey('tmdbPlatformPoster_${platformId}_1'),
                    poster: posters[1],
                    imageBase: imageBase,
                    width: _posterWidth,
                    height: _posterHeight,
                    serverLookupComplete: serverLookupComplete,
                  ),
                ),
              ),
            Positioned(
              left: empty ? 0 : (hasBack ? 0 : 8),
              top: empty ? 6 : (hasBack ? 6 : 3),
              child: Transform.rotate(
                angle: empty ? -0.05 : (hasBack ? -0.05 : 0),
                child: _PosterTile(
                  key: ValueKey('tmdbPlatformPoster_${platformId}_0'),
                  poster: posters.isEmpty ? null : posters[0],
                  imageBase: imageBase,
                  width: _posterWidth,
                  height: _posterHeight,
                  serverLookupComplete: serverLookupComplete,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({
    super.key,
    required this.poster,
    required this.imageBase,
    required this.width,
    required this.height,
    required this.serverLookupComplete,
  });

  final TmdbPlatformPoster? poster;
  final String imageBase;
  final double width;
  final double height;
  final bool serverLookupComplete;

  @override
  Widget build(BuildContext context) {
    final value = poster;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: value == null
            ? const ColoredBox(
                color: Color(0xFF2A2D33),
                child: Center(
                  child: Icon(
                    Icons.movie_outlined,
                    color: Colors.white24,
                    size: 16,
                  ),
                ),
              )
            : _PosterImage(
                poster: value,
                imageBase: imageBase,
                serverLookupComplete: serverLookupComplete,
              ),
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({
    required this.poster,
    required this.imageBase,
    required this.serverLookupComplete,
  });

  final TmdbPlatformPoster poster;
  final String imageBase;
  final bool serverLookupComplete;

  @override
  Widget build(BuildContext context) {
    final availability = poster.availability;
    if (availability != null) {
      return TmdbAvailabilityImage(
        entry: availability,
        imageBase: imageBase,
        cacheWidth: 120,
        posterSize: 'w154',
        serverMaxHeight: 240,
        fadeInDuration: const Duration(milliseconds: 120),
      );
    }
    if (!serverLookupComplete) {
      return const ColoredBox(color: Color(0xFF23252A));
    }
    final url = poster.tmdb.posterUrl(imageBase, size: 'w154');
    return TmdbImage(
      url: url,
      cacheWidth: 120,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: const ColoredBox(color: Color(0xFF23252A)),
      errorWidget: const ColoredBox(color: Color(0xFF2A2D33)),
    );
  }
}

class _PlatformName extends StatelessWidget {
  const _PlatformName({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
