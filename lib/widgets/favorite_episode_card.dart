import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 收藏页「集」分区横版卡：16:9 剧照 + 标题（+ 剧名/N 集）在下方。
class FavoriteEpisodeCard extends StatelessWidget {
  const FavoriteEpisodeCard({
    super.key,
    required this.item,
    required this.width,
    this.onTap,
  });

  final MediaItem item;
  final double width;
  final VoidCallback? onTap;

  /// 图片下方文字区预留高（标题 + 副标题 + 间距）。
  static const double textReservedHeight = 40;

  static double heightFor(double width) => width * 9 / 16 + textReservedHeight;

  @override
  Widget build(BuildContext context) {
    final title =
        item.name.trim().isEmpty ? '第 ${item.indexNumber ?? 1} 集' : item.name;
    final subtitle = item.seriesName?.trim();
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
              height: width * 9 / 16,
              child: EmbyImage(
                url: item.posterUrl,
                fit: BoxFit.cover,
                cacheWidth:
                    (width * MediaQuery.devicePixelRatioOf(context)).round(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
        ],
      ),
    );
  }
}
