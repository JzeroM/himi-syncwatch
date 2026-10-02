import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 剧集详情页分季区块集合：选季下拉 + 该季剧集横卡 + 播出季季卡横排。
///
/// 三个区块共享同一 `selectedSeason`（季号），互相联动：点季卡或用下拉
/// 切换季 → 上方剧集行跟着换。全平台一套 UI，TV 焦点由 [TvFocusable] 提供。
class SeriesSections extends StatelessWidget {
  final List<MediaItem> seasons;
  final List<MediaItem> episodes;
  final int? selectedSeason;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<MediaItem> onEpisodeTap;
  final bool tvMode;

  const SeriesSections({
    super.key,
    required this.seasons,
    required this.episodes,
    required this.selectedSeason,
    required this.onSeasonSelected,
    required this.onEpisodeTap,
    this.tvMode = false,
  });

  /// 季号：优先季自身的 `indexNumber`，缺失回退列表序号（1 起）。
  static int seasonNumber(MediaItem season, int index) =>
      season.indexNumber ?? index + 1;

  /// 该季的集（已按集号排序；调用方保证 episodes 全量）。
  List<MediaItem> get _seasonEpisodes => episodes
      .where((e) => (e.parentIndexNumber ?? 0) == (selectedSeason ?? 0))
      .toList();

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SeasonSelector(
          seasons: seasons,
          selectedSeason: selectedSeason,
          onSeasonSelected: onSeasonSelected,
          tvMode: tvMode,
        ),
        const SizedBox(height: 12),
        _SeasonEpisodeRow(
          episodes: _seasonEpisodes,
          onEpisodeTap: onEpisodeTap,
          tvMode: tvMode,
        ),
        const SizedBox(height: 20),
        const Text(
          '播出季',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _SeasonCardRow(
          seasons: seasons,
          selectedSeason: selectedSeason,
          onSeasonSelected: onSeasonSelected,
          tvMode: tvMode,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// 「第 N 季 ▼」快速选季下拉。
class _SeasonSelector extends StatelessWidget {
  final List<MediaItem> seasons;
  final int? selectedSeason;
  final ValueChanged<int> onSeasonSelected;
  final bool tvMode;

  const _SeasonSelector({
    required this.seasons,
    required this.selectedSeason,
    required this.onSeasonSelected,
    required this.tvMode,
  });

  @override
  Widget build(BuildContext context) {
    final numbers = seasons
        .asMap()
        .entries
        .map((e) => SeriesSections.seasonNumber(e.value, e.key))
        .toList();
    final current =
        numbers.contains(selectedSeason) ? selectedSeason : numbers.first;

    final dropdown = DropdownButton<int>(
      key: const Key('seriesSeasonSelector'),
      value: current,
      underline: const SizedBox.shrink(),
      isExpanded: false,
      items: [
        for (final n in numbers)
          DropdownMenuItem<int>(
            value: n,
            child: Text('第 $n 季'),
          ),
      ],
      onChanged: (v) {
        if (v != null) onSeasonSelected(v);
      },
    );

    if (!tvMode) return dropdown;
    return Align(
      alignment: Alignment.centerLeft,
      child: TvFocusable(
        radius: 8,
        onTap: () => _showMenu(context),
        child: ExcludeFocus(child: dropdown),
      ),
    );
  }

  /// TV 下 dropdown 自身的展开菜单焦点链不可靠，改为弹出 PopupMenu。
  Future<void> _showMenu(BuildContext context) async {
    final numbers = seasons
        .asMap()
        .entries
        .map((e) => SeriesSections.seasonNumber(e.value, e.key))
        .toList();
    final picked = await showMenu<int>(
      context: context,
      position: RelativeRect.fromDirectional(
        textDirection: Directionality.of(context),
        top: 120,
        start: 16,
        end: 16,
        bottom: 0,
      ),
      items: [
        for (final n in numbers)
          PopupMenuItem<int>(
            value: n,
            child: Text('第 $n 季'),
          ),
      ],
    );
    if (picked != null) onSeasonSelected(picked);
  }
}

/// 该季剧集横卡行：缩略图 + 「第N集 标题」+ 日期·时长 + 简介。
class _SeasonEpisodeRow extends StatelessWidget {
  final List<MediaItem> episodes;
  final ValueChanged<MediaItem> onEpisodeTap;
  final bool tvMode;

  const _SeasonEpisodeRow({
    required this.episodes,
    required this.onEpisodeTap,
    required this.tvMode,
  });

  static const double _cardWidth = 240;

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('暂无剧集', style: TextStyle(color: Colors.white70)),
      );
    }

    return SizedBox(
      height: 240,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: episodes.length,
        itemBuilder: (context, index) {
          final ep = episodes[index];
          final card = SizedBox(
            key: Key('episodeCard_${ep.id}'),
            width: _cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: EmbyImage(url: ep.posterUrl, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '第${ep.indexNumber ?? 0}集 ${ep.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _metaLine(ep),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  ep.overview ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            ),
          );

          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: tvMode
                ? TvFocusable(
                    radius: 12,
                    onTap: () => onEpisodeTap(ep),
                    child: card,
                  )
                : GestureDetector(
                    onTap: () => onEpisodeTap(ep),
                    child: card,
                  ),
          );
        },
      ),
    );
  }

  /// 「2022年3月31日 · 53 min」（缺字段的段自动省略）。
  String _metaLine(MediaItem ep) {
    final parts = <String>[];
    final d = ep.premiereDate;
    if (d != null) parts.add('${d.year}年${d.month}月${d.day}日');
    final runtime = ep.runtimeText;
    if (runtime != null) parts.add(runtime);
    return parts.join(' · ');
  }
}

/// 「播出季」季卡横排：季海报 + 集数徽章 + 第N季标签，选中态主色描边。
class _SeasonCardRow extends StatelessWidget {
  final List<MediaItem> seasons;
  final int? selectedSeason;
  final ValueChanged<int> onSeasonSelected;
  final bool tvMode;

  const _SeasonCardRow({
    required this.seasons,
    required this.selectedSeason,
    required this.onSeasonSelected,
    required this.tvMode,
  });

  static const double _posterWidth = 88;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: _posterWidth * 1.5 + 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: seasons.length,
        itemBuilder: (context, index) {
          final season = seasons[index];
          final number = SeriesSections.seasonNumber(season, index);
          final selected = number == selectedSeason;

          // 集数徽章：覆盖在海报右下角
          final poster = ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: _posterWidth * 1.5,
              child: season.posterUrl != null
                  ? EmbyImage(url: season.posterUrl, fit: BoxFit.cover)
                  : Container(
                      color: Colors.white10,
                      child:
                          const Icon(Icons.tv, color: Colors.white38, size: 32),
                    ),
            ),
          );

          final card = Container(
            key: Key('seasonCard_${season.id}'),
            width: _posterWidth,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    poster,
                    if (season.childCount != null)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${season.childCount}集',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '第 $number 季',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? primary : Colors.white70,
                  ),
                ),
              ],
            ),
          );

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: tvMode
                ? TvFocusable(
                    radius: 12,
                    onTap: () => onSeasonSelected(number),
                    child: card,
                  )
                : GestureDetector(
                    onTap: () => onSeasonSelected(number),
                    child: card,
                  ),
          );
        },
      ),
    );
  }
}
