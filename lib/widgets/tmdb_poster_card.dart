import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// TMDB 海报卡：2:3 海报 + 标题/年份 + 可选服务器角标。
class TmdbPosterCard extends StatelessWidget {
  const TmdbPosterCard({
    super.key,
    required this.item,
    required this.imageBase,
    required this.width,
    this.onTap,
    this.serverBadge,
  });

  final TmdbItem item;
  final String imageBase;
  final double width;
  final VoidCallback? onTap;
  final String? serverBadge;

  static const double textReservedHeight = 46;

  static double heightFor(double width) => width * 1.5 + textReservedHeight;

  static double mediaHeightFor(double width) => width * 1.5;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      radius: 12,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: width * 1.5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TmdbImage(
                    url: item.posterUrl(imageBase),
                    cacheWidth:
                        (width * MediaQuery.devicePixelRatioOf(context)).round(),
                  ),
                  if (serverBadge != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: (width * 0.66).clamp(56, 180),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          serverBadge!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (item.voteAverage != null && item.voteAverage! > 0)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                size: 12, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              item.voteAverage!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (item.year != null)
            Text(
              item.year!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
        ],
      ),
    );
  }
}
