import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/widgets/continue_watching_card.dart';
import 'package:himi_syncwatch/widgets/hover_scroll_row.dart';

/// TMDB 聚合首页「继续观看」横栏（跨服务器）。
class TmdbResumeBar extends StatelessWidget {
  const TmdbResumeBar({
    super.key,
    required this.entries,
    required this.onOpen,
    this.onLongPress,
  });

  final List<TmdbResumeEntry> entries;
  final void Function(TmdbResumeEntry entry) onOpen;

  /// 长按（触屏长按 / TV 长按 OK）：回调携带来源服务器与菜单锚点。
  final void Function(TmdbResumeEntry entry, Rect anchor)? onLongPress;

  static const double _cardWidth = 200;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final height = ContinueWatchingCard.heightFor(_cardWidth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '继续观看',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: height,
          child: HoverScrollRow(
            height: height,
            arrowAnchorHeight: ContinueWatchingCard.mediaHeightFor(_cardWidth),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: _cardWidth,
                  child: ContinueWatchingCard(
                    key: ValueKey(
                        'tmdbResume_${entry.server.id}_${entry.item.id}'),
                    item: entry.item,
                    width: _cardWidth,
                    serverBadge: entry.server.label,
                    accessToken: entry.server.accessToken,
                    onTap: () => onOpen(entry),
                    onLongPress: onLongPress == null
                        ? null
                        : (anchor) => onLongPress!(entry, anchor),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
