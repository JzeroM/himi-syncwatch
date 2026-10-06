import 'package:flutter/material.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
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
  final ValueChanged<MediaItem> onEpisodeSelect;
  final bool tvMode;

  /// 倒序排列（横卡行与选集网格共用，见详情页排序切换）。
  final bool sortDescending;

  /// 切换正序/倒序（由详情页持有状态并 setState）。
  final VoidCallback onToggleSort;

  /// 打开数字网格选集器（由详情页持有选中集状态）。
  final VoidCallback onOpenEpisodePicker;

  /// 选中集 id：横卡主色描边高亮（null = 无描边）。
  final String? highlightEpisodeId;

  /// 横卡行挂点：详情页选集后对其 `Scrollable.ensureVisible` 垂直定位。
  final GlobalKey? episodeRowKey;

  /// 横卡行水平滚动控制器（详情页选集后 jumpTo 定位高亮卡）。
  final ScrollController? episodeRowController;

  /// 已收藏的集 id（横卡右上角爱心实心/空心）。
  final Set<String> favoriteIds;

  /// 点击某集爱心（收藏/取消）；null = 不显示爱心。
  final ValueChanged<String>? onToggleFavorite;

  /// 已观看的集 id（横卡右下角对勾实心/线框）。
  final Set<String> watchedIds;

  /// 点击某集对勾（标记/取消已观看）；null = 不显示对勾。
  final ValueChanged<String>? onToggleWatched;

  const SeriesSections({
    super.key,
    required this.seasons,
    required this.episodes,
    required this.selectedSeason,
    required this.onSeasonSelected,
    required this.onEpisodeSelect,
    required this.onToggleSort,
    required this.onOpenEpisodePicker,
    this.sortDescending = false,
    this.tvMode = false,
    this.highlightEpisodeId,
    this.episodeRowKey,
    this.episodeRowController,
    this.favoriteIds = const {},
    this.onToggleFavorite,
    this.watchedIds = const {},
    this.onToggleWatched,
  });

  /// 横卡水平步长：卡宽 240 + 右侧间距 12。
  static const double episodeCardStride =
      _SeasonEpisodeRow._cardWidth + _SeasonEpisodeRow._cardGap;

  /// 季号：优先季自身的 `indexNumber`，缺失回退列表序号（1 起）。
  static int seasonNumber(MediaItem season, int index) =>
      season.indexNumber ?? index + 1;

  /// 季显示名：优先 Emby 自带季名（`Name`，如「特别篇」/自定义名），
  /// 空名回退「第 N 季」。
  static String seasonTitle(MediaItem season, int index) {
    final name = season.name.trim();
    return name.isEmpty ? '第 ${seasonNumber(season, index)} 季' : name;
  }

  /// 该季的集：按集号排序后按 [sortDescending] 决定正/倒序。
  List<MediaItem> get _seasonEpisodes {
    final list = episodes
        .where((e) => (e.parentIndexNumber ?? 0) == (selectedSeason ?? 0))
        .toList()
      ..sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
    return sortDescending ? list.reversed.toList() : list;
  }

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
          onToggleSort: onToggleSort,
          onOpenEpisodePicker: onOpenEpisodePicker,
          tvMode: tvMode,
        ),
        const SizedBox(height: 12),
        _SeasonEpisodeRow(
          rowKey: episodeRowKey,
          episodes: _seasonEpisodes,
          onEpisodeSelect: onEpisodeSelect,
          tvMode: tvMode,
          highlightEpisodeId: highlightEpisodeId,
          controller: episodeRowController,
          favoriteIds: favoriteIds,
          onToggleFavorite: onToggleFavorite,
          watchedIds: watchedIds,
          onToggleWatched: onToggleWatched,
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

/// 「第 N 季 ▼」快速选季下拉 + 右侧排序/选集入口。
class _SeasonSelector extends StatelessWidget {
  final List<MediaItem> seasons;
  final int? selectedSeason;
  final ValueChanged<int> onSeasonSelected;
  final VoidCallback onToggleSort;
  final VoidCallback onOpenEpisodePicker;
  final bool tvMode;

  const _SeasonSelector({
    required this.seasons,
    required this.selectedSeason,
    required this.onSeasonSelected,
    required this.onToggleSort,
    required this.onOpenEpisodePicker,
    required this.tvMode,
  });

  @override
  Widget build(BuildContext context) {
    final entries = seasons.asMap().entries.toList();
    final numbers = entries
        .map((e) => SeriesSections.seasonNumber(e.value, e.key))
        .toList();
    final current =
        numbers.contains(selectedSeason) ? selectedSeason! : numbers.first;
    final currentIndex = numbers.indexOf(current);
    final currentTitle = SeriesSections.seasonTitle(
        seasons[currentIndex], entries[currentIndex].key);

    // 触发按钮：玻璃胶囊（当前季名 + 下拉箭头）。点开玻璃面板选季。
    final trigger = GlassContainer(
      key: const Key('seriesSeasonSelector'),
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currentTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 22),
        ],
      ),
    );

    Widget iconBtn({
      required Key key,
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
    }) {
      final btn = IconButton(
        key: key,
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onTap,
      );
      if (!tvMode) return btn;
      return TvFocusable(
        radius: 10,
        onTap: onTap,
        child: ExcludeFocus(child: btn),
      );
    }

    return Row(
      children: [
        if (tvMode)
          TvFocusable(
            radius: 14,
            onTap: () => _showMenu(context),
            child: ExcludeFocus(child: trigger),
          )
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showMenu(context),
            child: trigger,
          ),
        const Spacer(),
        iconBtn(
          key: const Key('episodeSortToggle'),
          icon: Icons.swap_vert,
          tooltip: '切换正序/倒序',
          onTap: onToggleSort,
        ),
        iconBtn(
          key: const Key('episodePickerButton'),
          icon: Icons.grid_view,
          tooltip: '选集',
          onTap: onOpenEpisodePicker,
        ),
      ],
    );
  }

  /// 打开玻璃选季面板（透明 Material + GlassContainer 承底），
  /// 触摸与 TV 遥控统一走此菜单。
  Future<void> _showMenu(BuildContext context) async {
    final entries = seasons.asMap().entries.toList();
    final numbers = entries
        .map((e) => SeriesSections.seasonNumber(e.value, e.key))
        .toList();
    final current =
        numbers.contains(selectedSeason) ? selectedSeason : numbers.first;

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    final position = (overlay != null && box != null)
        ? RelativeRect.fromLTRB(
            box.localToGlobal(Offset.zero, ancestor: overlay).dx,
            box
                    .localToGlobal(box.size.bottomLeft(Offset.zero),
                        ancestor: overlay)
                    .dy +
                4,
            overlay.size.width -
                box
                    .localToGlobal(box.size.bottomLeft(Offset.zero),
                        ancestor: overlay)
                    .dx,
            0,
          )
        : const RelativeRect.fromLTRB(16, 120, 16, 0);

    final picked = await showMenu<int>(
      context: context,
      color: Colors.transparent,
      elevation: 0,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
      position: position,
      items: [
        PopupMenuItem<int>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Builder(
            builder: (menuCtx) => GlassContainer(
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in entries)
                    _seasonRow(
                      menuCtx,
                      SeriesSections.seasonTitle(e.value, e.key),
                      SeriesSections.seasonNumber(e.value, e.key) == current,
                      SeriesSections.seasonNumber(e.value, e.key),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    if (picked != null) onSeasonSelected(picked);
  }

  /// 玻璃面板中的单个季选项（当前季主色高亮）。
  Widget _seasonRow(
      BuildContext menuCtx, String title, bool selected, int value) {
    return InkWell(
      onTap: () => Navigator.pop(menuCtx, value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: selected
            ? Theme.of(menuCtx).colorScheme.primary.withValues(alpha: 0.35)
            : Colors.transparent,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// 该季剧集横卡行：缩略图 + 「第N集 标题」+ 日期·时长 + 简介。
/// 选中集（[highlightEpisodeId]）主色描边高亮。
class _SeasonEpisodeRow extends StatelessWidget {
  final List<MediaItem> episodes;
  final ValueChanged<MediaItem> onEpisodeSelect;
  final bool tvMode;
  final String? highlightEpisodeId;
  final ScrollController? controller;

  /// 行挂点（只挂到内部 SizedBox，勿同时作 widget key）。
  final GlobalKey? rowKey;

  const _SeasonEpisodeRow({
    required this.episodes,
    required this.onEpisodeSelect,
    required this.tvMode,
    this.highlightEpisodeId,
    this.controller,
    this.rowKey,
    this.favoriteIds = const {},
    this.onToggleFavorite,
    this.watchedIds = const {},
    this.onToggleWatched,
  });

  final Set<String> favoriteIds;
  final ValueChanged<String>? onToggleFavorite;
  final Set<String> watchedIds;
  final ValueChanged<String>? onToggleWatched;

  static const double _cardWidth = 240;
  static const double _cardGap = 12;

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('暂无剧集', style: TextStyle(color: Colors.white70)),
      );
    }

    final primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      key: rowKey,
      height: 240,
      child: ListView.builder(
        // TV 焦点框放大溢出内容盒，默认 clip 会裁边
        clipBehavior: Clip.none,
        controller: controller,
        scrollDirection: Axis.horizontal,
        itemCount: episodes.length,
        itemBuilder: (context, index) {
          final ep = episodes[index];
          final selected = ep.id == highlightEpisodeId;
          final favorited = favoriteIds.contains(ep.id);
          final watched = watchedIds.contains(ep.id);
          final card = Container(
            key: Key('episodeCard_${ep.id}'),
            width: _cardWidth,
            padding: const EdgeInsets.all(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 选中描边仅包图片，不包文字/简介区
                Container(
                  key: Key('episodeCardImage_${ep.id}'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          EmbyImage(
                            url: ep.posterUrl,
                            fit: BoxFit.cover,
                            cacheWidth: (_cardWidth *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                          ),
                          // 每集收藏爱心（图片右上角；触摸操作）
                          if (onToggleFavorite != null)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                key: Key('episodeFavorite_${ep.id}'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => onToggleFavorite!(ep.id),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    favorited
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 16,
                                    color: favorited ? primary : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          // 每集已观看对勾（图片右下角；触摸操作）
                          if (onToggleWatched != null)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: GestureDetector(
                                key: Key('episodeWatched_${ep.id}'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => onToggleWatched!(ep.id),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    watched
                                        ? Icons.check_circle
                                        : Icons.check_circle_outline,
                                    size: 16,
                                    color: watched ? primary : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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
            padding: const EdgeInsets.only(right: _cardGap),
            child: tvMode
                ? TvFocusable(
                    radius: 12,
                    onTap: () => onEpisodeSelect(ep),
                    child: card,
                  )
                : GestureDetector(
                    // opaque：占位图窄/未加载时卡片中心也命中
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onEpisodeSelect(ep),
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

  static const double _posterWidth = 104;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: _posterWidth * 1.5 + 44,
      child: ListView.builder(
        // TV 焦点框放大溢出内容盒，默认 clip 会裁边
        clipBehavior: Clip.none,
        scrollDirection: Axis.horizontal,
        itemCount: seasons.length,
        itemBuilder: (context, index) {
          final season = seasons[index];
          final number = SeriesSections.seasonNumber(season, index);
          final selected = number == selectedSeason;

          // 集数徽章：覆盖在海报右下角；选中描边仅包海报图
          final poster = Container(
            key: Key('seasonCardImage_${season.id}'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: _posterWidth * 1.5,
                child: season.posterUrl != null
                    ? EmbyImage(
                        url: season.posterUrl,
                        fit: BoxFit.cover,
                        cacheWidth: (_posterWidth *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                      )
                    : Container(
                        color: Colors.white10,
                        child: const Icon(Icons.tv,
                            color: Colors.white38, size: 32),
                      ),
              ),
            ),
          );

          final card = Container(
            key: Key('seasonCard_${season.id}'),
            width: _posterWidth,
            padding: const EdgeInsets.all(3),
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
                // 季标签优先用 Emby 自带季名（如「特别篇」），不随选中
                // 高亮：仅图片描边表达选中态
                Text(
                  SeriesSections.seasonTitle(season, index),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
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
                    // opaque：占位图窄/未加载时卡片中心也命中
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSeasonSelected(number),
                    child: card,
                  ),
          );
        },
      ),
    );
  }
}
