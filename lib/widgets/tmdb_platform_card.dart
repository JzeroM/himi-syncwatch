import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';
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
  });

  final TmdbPlatformShowcase showcase;
  final String imageBase;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final local = showcase.local;
    final highlight = showcase.highlight;
    final logoUrl = TmdbService.imageUrl(
      imageBase,
      showcase.logoPath,
      size: 'w300',
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return SizedBox(
      width: width,
      height: height,
      child: TvFocusable(
        radius: 18,
        onTap: onTap,
        child: GlassContainer(
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.all(8),
          showShadow: false,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 58,
                  height: height - 16,
                  child: KeyedSubtree(
                    key: ValueKey(
                      'tmdbPlatformPoster_${showcase.platform.providerId}',
                    ),
                    child: local != null
                        ? TmdbAvailabilityImage(
                            entry: local,
                            imageBase: imageBase,
                            cacheWidth: (58 * dpr).round(),
                          )
                        : highlight?.posterPath != null
                            ? TmdbImage(
                                url: highlight!.posterUrl(imageBase),
                                cacheWidth: (58 * dpr).round(),
                                placeholder: const SizedBox.shrink(),
                              )
                            : const _PosterFallback(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Center(
                    child: logoUrl == null
                        ? _PlatformName(name: showcase.platform.name)
                        : KeyedSubtree(
                            key: ValueKey(
                              'tmdbPlatformLogo_${showcase.platform.providerId}',
                            ),
                            child: SizedBox.expand(
                              child: TmdbImage(
                                url: logoUrl,
                                fit: BoxFit.contain,
                                cacheWidth: (width * dpr).round(),
                                placeholder: const SizedBox.shrink(),
                                errorWidget: Center(
                                  child: _PlatformName(
                                    name: showcase.platform.name,
                                  ),
                                ),
                              ),
                            ),
                          ),
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

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF24262D),
      child: Center(
        child: Icon(Icons.movie_outlined, color: Colors.white38, size: 24),
      ),
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
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
