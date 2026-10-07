import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 首页「继续观看」横卡：16:9 剧照 + 底部观看进度条 + 标题/副标题。
/// 电影：标题=片名、副标题=年份；集：标题=剧名、副标题=`S1:E10 - 集名`。
class ContinueWatchingCard extends StatelessWidget {
  const ContinueWatchingCard({
    super.key,
    required this.item,
    required this.width,
    this.onTap,
    this.onLongPress,
  });

  final MediaItem item;
  final double width;
  final VoidCallback? onTap;

  /// 长按（触屏长按 / TV 长按 OK）：回调携带卡片全局矩形作菜单锚点。
  final void Function(Rect anchor)? onLongPress;

  static const double textReservedHeight = 46;

  static double heightFor(double width) => width * 9 / 16 + textReservedHeight;

  String get _title {
    if (item.isEpisode && (item.seriesName?.isNotEmpty ?? false)) {
      return item.seriesName!;
    }
    return item.name;
  }

  String? get _subtitle {
    if (item.isEpisode) {
      final s = item.parentIndexNumber ?? 0;
      final e = item.indexNumber ?? 0;
      return 'S$s:E$e - ${item.name}';
    }
    return item.year;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final pct = item.playedPercentage.clamp(0.0, 100.0);
    final subtitle = _subtitle;
    return TvFocusable(
      radius: 12,
      onTap: onTap,
      onLongPress: onLongPress == null
          ? null
          : () {
              final box = context.findRenderObject();
              if (box is RenderBox && box.attached) {
                onLongPress!(box.localToGlobal(Offset.zero) & box.size);
              }
            },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: width * 9 / 16,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EmbyImage(
                    url: item.posterUrl ?? item.backdropUrl,
                    fit: BoxFit.cover,
                    cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                  ),
                  // 底部观看进度条
                  if (pct > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SizedBox(
                        height: 4,
                        child: Stack(
                          children: [
                            const ColoredBox(color: Colors.white24),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: pct / 100,
                              child: ColoredBox(color: primary),
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
            _title,
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
