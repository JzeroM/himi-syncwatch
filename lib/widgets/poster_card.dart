import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 资源海报卡片：完整 2:3 圆角海报（右下评分角标、左上集数角标），
/// 标题与年份显示在海报正下方，直接落在页面背景上，不套黑底卡片。
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.width,
    this.onTap,
    this.serverBadge,
  });

  /// 资源数据。
  final MediaItem item;

  /// 卡片宽（海报高 = width * 1.5）。
  final double width;

  final VoidCallback? onTap;

  /// 左上服务器名角标（聚合搜索「全部」视图区分来源）；设置后
  /// 集数角标让位（同为左上角，来源归属优先）。
  final String? serverBadge;

  /// 海报下方文字区预留高度（标题 + 年份 + 间距，含少量余量）。
  static const double textReservedHeight = 46;

  /// 给定卡片宽时的完整卡片高（海报 2:3 + 文字区）。
  static double heightFor(double width) => width * 1.5 + textReservedHeight;

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
                  EmbyImage(
                    url: item.posterUrl,
                    fit: BoxFit.cover,
                    // 按显示宽×dpr 解码，避免原图全尺寸解码卡顿
                    cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                  ),
                  if (serverBadge != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: (width * 0.66).clamp(56, 180),
                        ),
                        child: _PosterBadge(
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
                    )
                  else if (item.indexNumber != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _PosterBadge(
                        child: Text(
                          '${item.indexNumber}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (item.communityRating != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: _PosterBadge(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                size: 12, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              item.communityRating!.toStringAsFixed(1),
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
            item.name,
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

/// 海报角标（半透明黑底小胶囊）。
class _PosterBadge extends StatelessWidget {
  const _PosterBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }
}
