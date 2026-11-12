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
    this.onLongPress,
    this.serverBadge,
    this.heroTag,
  });

  /// 资源数据。
  final MediaItem item;

  /// 卡片宽（海报高 = width * 1.5）。
  final double width;

  final VoidCallback? onTap;

  /// 长按（触屏长按 / TV 长按 OK）：回调携带卡片全局矩形作菜单锚点。
  final void Function(Rect anchor)? onLongPress;

  /// 左上服务器名角标（聚合搜索「全部」视图区分来源）；设置后
  /// 集数角标让位（同为左上角，来源归属优先）。
  final String? serverBadge;

  /// 687：Hero 共享元素 tag（可选）。
  ///
  /// 【只在主列表传值】首页/分类/搜索/收藏 → 详情页这条链路启用。
  /// 「相似推荐」等可能同页出现相同影片的位置**不传**，否则同页多个
  /// 同 tag 的 Hero 会抛异常。
  ///
  /// 详情页侧落点见 `detail_screen.dart` 的隐藏 Hero。
  final Object? heroTag;

  /// 海报下方文字区预留高度（标题 + 年份 + 间距，含少量余量）。
  static const double textReservedHeight = 46;

  /// 给定卡片宽时的完整卡片高（海报 2:3 + 文字区）。
  static double heightFor(double width) => width * 1.5 + textReservedHeight;

  /// 海报图区（2:3）高度：供横栏箭头垂直居中对齐使用。
  static double mediaHeightFor(double width) => width * 1.5;

  /// 687：传了 [heroTag] 才包 Hero（主列表 → 详情页共享元素）。
  ///
  /// 【为什么要去重】同一个影片可能在同一页出现多次（首页的「继续观看」
  /// 与「分类区」、搜索的多个来源等）。Flutter 要求**同一路由子树内
  /// Hero tag 唯一**，重复会直接抛
  /// `There are multiple heroes that share the same tag`。
  ///
  /// 这里用「本帧已用过的 tag 集合」做运行时去重：先出现的包 Hero，
  /// 后出现的自动降级为普通卡片（视觉上无差别，只是不参与飞行动画）。
  static final Set<Object> _heroTagsInFrame = {};
  static int _heroFrameStamp = -1;

  Widget _maybeHero(Widget child) {
    final tag = heroTag;
    if (tag == null) return child;
    // 每帧重置集合（用帧号判断，避免 addPostFrameCallback 的时序问题）
    final frame = WidgetsBinding.instance.currentSystemFrameTimeStamp;
    final stamp = frame.inMicroseconds;
    if (_heroFrameStamp != stamp) {
      _heroFrameStamp = stamp;
      _heroTagsInFrame.clear();
    }
    if (!_heroTagsInFrame.add(tag)) {
      // 本帧已有同 tag → 本次不参与 Hero（避免断言崩溃）
      return child;
    }
    return Hero(
      tag: tag,
      // 飞行中保持 2:3 竖版 + 圆角收敛（详情页落点是极小占位，
      // 主视觉由 backdrop 接管，不做横竖比拉伸）。
      flightShuttleBuilder: (_, animation, __, ___, ____) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final t = Curves.easeOut.transform(animation.value);
            return ClipRRect(
              borderRadius: BorderRadius.circular(12 * (1 - t)),
              child: Material(
                color: Colors.transparent,
                child: child,
              ),
            );
          },
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
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
          // 687：Hero 共享元素（仅传了 heroTag 的主列表卡片启用）。
          //
          // 【flightShuttleBuilder】列表是竖版 2:3 海报，详情页落点是
          // 极小占位（详情页主视觉是横版 backdrop）——默认 Hero 会把
          // 竖版硬拉到横版变形。这里让飞行中保持 2:3 + 圆角随进度
          // 收敛，落地瞬间由详情页 backdrop 接管。
          _maybeHero(
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
