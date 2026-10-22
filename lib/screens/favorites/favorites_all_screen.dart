import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/category_filter.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/favorites_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/category/category_screen.dart'
    show SortOption;
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/favorite_episode_card.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/media_context_menu.dart';
import 'package:himi_syncwatch/widgets/media_filter_panel.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';
import 'package:himi_syncwatch/widgets/tv/tv_app_bar_icon_button.dart';

/// 「查看所有」页：展示某分类（电影/电视剧/集）的全部收藏，网格铺开。
/// 顶层路由 `/favorites/all?type=...&title=...`。
///
/// 服务器模式：走当前服务器 Emby 查询（服务端筛选/排序）。
/// TMDB 聚合模式：读取全部服务器收藏，按 TMDB id 去重后在本地筛选/排序。
class FavoritesAllScreen extends ConsumerStatefulWidget {
  const FavoritesAllScreen({
    super.key,
    required this.type,
    required this.title,
  });

  final String type;
  final String title;

  @override
  ConsumerState<FavoritesAllScreen> createState() =>
      _FavoritesAllScreenState();
}

class _FavoritesAllScreenState extends ConsumerState<FavoritesAllScreen> {
  SortOption _sortOption = SortOption.nameAsc;
  CategoryFilter _mediaFilter = CategoryFilter.empty;
  MediaFilterOptions? _filterOptions;

  Future<MediaFilterOptions>? _filterOptionsFuture;
  bool _filterOpening = false;

  List<MediaItem> _items = [];
  bool _isLoading = true;
  String? _error;

  bool get isEpisode => widget.type == 'episode';

  bool get _aggregateMode => ref.read(settingsProvider).isTmdbHome;

  String? get _embyType => switch (widget.type) {
        'movie' => 'Movie',
        'series' => 'Series',
        'episode' => 'Episode',
        _ => null,
      };

  @override
  void initState() {
    super.initState();
    if (!_aggregateMode && _embyType != null) _prefetchFilterOptions();
    _load();
  }

  void _prefetchFilterOptions() {
    if (_filterOptions != null || _filterOptionsFuture != null) return;
    final future = ref.read(embyServiceProvider).getFilterOptions(
          includeItemTypes: _embyType,
        );
    _filterOptionsFuture = future;
    future.then((options) {
      if (!mounted) return;
      setState(() => _filterOptions = options);
    }).whenComplete(() {
      if (mounted) _filterOptionsFuture = null;
    });
  }

  Future<MediaFilterOptions> _fetchFilterOptions() async {
    final options = await ref.read(embyServiceProvider).getFilterOptions(
          includeItemTypes: _embyType,
        );
    if (mounted) setState(() => _filterOptions = options);
    return options;
  }

  Future<void> _load() async {
    if (_aggregateMode) {
      if (_isLoading && mounted) setState(() => _isLoading = false);
      return;
    }
    final embyType = _embyType;
    if (embyType == null) {
      setState(() {
        _items = [];
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await ref.read(embyServiceProvider).getFavoriteItems(
            includeItemTypes: embyType,
            sortBy: _sortOption.sortBy,
            sortOrder: _sortOption.sortOrder,
            filters: _mediaFilter.watchStatusParam,
            genres: _mediaFilter.genresParam,
            years: _mediaFilter.yearsParam,
            officialRatings: _mediaFilter.ratingsParam,
          );
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSortChanged(SortOption? value) {
    if (value == null || value == _sortOption) return;
    setState(() => _sortOption = value);
    if (!_aggregateMode) _load();
  }

  List<FavoriteEntry> _entriesOf(FavoriteGroups groups) {
    return switch (widget.type) {
      'movie' => groups.movies,
      'series' => groups.series,
      'episode' => groups.episodes,
      _ => const <FavoriteEntry>[],
    };
  }

  static int _yearOf(FavoriteEntry entry) =>
      int.tryParse(entry.item.year ?? '') ?? 0;

  bool _matchesFilter(FavoriteEntry entry) {
    final item = entry.item;
    switch (_mediaFilter.watchStatus) {
      case WatchStatusFilter.watched:
        if (!item.isWatched) return false;
        break;
      case WatchStatusFilter.unwatched:
        if (item.isWatched) return false;
        break;
      case WatchStatusFilter.resumable:
        if (item.isWatched || item.playbackPositionMs <= 0) return false;
        break;
      case WatchStatusFilter.any:
        break;
    }
    if (_mediaFilter.genres.isNotEmpty &&
        !item.genres.any(_mediaFilter.genres.contains)) {
      return false;
    }
    if (_mediaFilter.years.isNotEmpty && !_mediaFilter.years.contains(_yearOf(entry))) {
      return false;
    }
    if (_mediaFilter.ratings.isNotEmpty &&
        !_mediaFilter.ratings.contains(item.officialRating)) {
      return false;
    }
    return true;
  }

  int _compare(FavoriteEntry a, FavoriteEntry b) {
    int byText(String? x, String? y) =>
        (x ?? '').toLowerCase().compareTo((y ?? '').toLowerCase());
    switch (_sortOption) {
      case SortOption.nameAsc:
        return byText(a.name, b.name);
      case SortOption.nameDesc:
        return byText(b.name, a.name);
      case SortOption.yearAsc:
        return _yearOf(a).compareTo(_yearOf(b));
      case SortOption.yearDesc:
        return _yearOf(b).compareTo(_yearOf(a));
      case SortOption.ratingAsc:
        return (a.item.communityRating ?? 0)
            .compareTo(b.item.communityRating ?? 0);
      case SortOption.ratingDesc:
        return (b.item.communityRating ?? 0)
            .compareTo(a.item.communityRating ?? 0);
      case SortOption.dateDesc:
        final at = a.item.dateLastContentAdded ?? a.item.dateCreated;
        final bt = b.item.dateLastContentAdded ?? b.item.dateCreated;
        return (bt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(at ?? DateTime.fromMillisecondsSinceEpoch(0));
    }
  }

  MediaFilterOptions _optionsFromEntries(List<FavoriteEntry> entries) {
    final genres = <String>{};
    final years = <int>{};
    final ratings = <String>{};
    for (final entry in entries) {
      genres.addAll(entry.item.genres);
      final year = _yearOf(entry);
      if (year > 0) years.add(year);
      final rating = entry.item.officialRating;
      if (rating != null && rating.isNotEmpty) ratings.add(rating);
    }
    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    final sortedGenres = genres.toList()..sort();
    final sortedRatings = ratings.toList()..sort();
    return MediaFilterOptions(
      genres: sortedGenres,
      years: sortedYears,
      ratings: sortedRatings,
    );
  }

  Future<void> _openFilterPanel() async {
    if (_filterOpening) return;
    final aggregate = _aggregateMode;
    setState(() => _filterOpening = true);
    try {
      final cached = aggregate
          ? _optionsFromEntries(
              _entriesOf(
                  ref.read(aggregateFavoriteItemsProvider).valueOrNull ??
                      const FavoriteGroups()),
            )
          : _filterOptions;
      final result = await showMediaFilterPanel(
        context,
        current: _mediaFilter,
        options: cached,
        optionsFuture: aggregate || cached != null
            ? null
            : (_filterOptionsFuture ??= _fetchFilterOptions()),
        tvMode: ref.read(settingsProvider.select((s) => s.tvMode)),
      );
      if (result == null || !mounted || result == _mediaFilter) return;
      setState(() => _mediaFilter = result);
      if (!aggregate) _load();
    } finally {
      if (mounted) setState(() => _filterOpening = false);
    }
  }

  void _openEntry(FavoriteEntry entry, bool aggregate) {
    final item = entry.item;
    final params = <String, String>{
      if (entry.serverId != null) 'server': entry.serverId!,
      if (aggregate) 'aggregate': 'true',
    };
    String query([MapEntry<String, String>? extra]) {
      final all = [...params.entries, if (extra != null) extra];
      if (all.isEmpty) return '';
      return '?${all.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
    }

    if (item.isEpisode && item.seriesId != null) {
      context
          .push('/detail/${item.seriesId}${query(MapEntry('episode', item.id))}');
    } else {
      context.push('/detail/${item.id}${query()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final aggregateMode =
        ref.watch(settingsProvider.select((s) => s.isTmdbHome));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;

    ref.listen(favoritesRevisionProvider, (_, __) {
      if (!ref.read(settingsProvider).isTmdbHome) _load();
    });
    ref.listen(embyConfigProvider, (_, __) {
      if (!ref.read(settingsProvider).isTmdbHome) _load();
    });

    final aggregate = aggregateMode
        ? ref.watch(aggregateFavoriteItemsProvider)
        : null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const TvBackButton(),
        title: Text(widget.title),
        actions: [
          TvAppBarIconButton(
            key: const Key('favoritesFilterButton'),
            icon: Icons.filter_list,
            color: _mediaFilter.isNotEmpty
                ? Theme.of(context).colorScheme.primary
                : null,
            tooltip: '筛选',
            onPressed: _filterOpening ? null : _openFilterPanel,
          ),
          TvMenuIconButton<SortOption>(
            key: const Key('favoritesSortMenu'),
            icon: Icons.sort,
            tooltip: '排序',
            onSelected: _onSortChanged,
            itemsBuilder: (context) => SortOption.values.map((opt) {
              return PopupMenuItem(
                value: opt,
                child: Row(
                  children: [
                    if (opt == _sortOption)
                      const Icon(Icons.check, size: 18, color: Colors.green)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(opt.label),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
      body: AnimatedContainer(
        key: const Key('favoritesAllBackground'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: PosterPalette.pageGradient(accent, base),
        ),
        child: _buildBody(aggregateMode, aggregate),
      ),
    );
  }

  Widget _buildBody(
    bool aggregateMode,
    AsyncValue<FavoriteGroups>? aggregate,
  ) {
    if (aggregateMode) {
      return aggregate!.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _errorView(e.toString()),
        data: (groups) {
          final all = _entriesOf(groups);
          if (all.isEmpty) return _emptyView(false);
          final filtered = all.where(_matchesFilter).toList()..sort(_compare);
          if (filtered.isEmpty) return _emptyView(true);
          return _grid(filtered, aggregateMode: true);
        },
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _errorView(_error!);
    if (_items.isEmpty) return _emptyView(_mediaFilter.isNotEmpty);

    final entries = [
      for (final item in _items) FavoriteEntry(item: item),
    ];
    return _grid(entries, aggregateMode: false);
  }

  Widget _grid(List<FavoriteEntry> entries, {required bool aggregateMode}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = isEpisode ? 210.0 : 120.0;
        return ListView(
          padding: EdgeInsets.only(
            top: GlassConfig.topInsetOf(context),
            bottom: GlassConfig.bottomReserveOf(context),
            left: 16,
            right: 16,
          ),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 16,
              children: [
                for (final entry in entries)
                  SizedBox(
                    width: cardWidth,
                    child: isEpisode
                        ? FavoriteEpisodeCard(
                            item: entry.item,
                            width: cardWidth,
                            onTap: () => _openEntry(entry, aggregateMode),
                          )
                        : PosterCard(
                            key: ValueKey('posterCard_${entry.id}'),
                            item: entry.item,
                            width: cardWidth,
                            serverBadge:
                                aggregateMode ? entry.server?.label : null,
                            onTap: () => _openEntry(entry, aggregateMode),
                            onLongPress: aggregateMode
                                ? null
                                : (rect) => showPosterCardMenu(
                                    context, ref, entry.item, rect),
                          ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _emptyView(bool filtered) {
    return Center(
      child: Text(
        filtered ? '筛选无匹配项' : '暂无收藏',
        key: const Key('favoritesAllEmptyText'),
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _errorView(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '加载失败：$error',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (ref.read(settingsProvider).isTmdbHome) {
                ref.invalidate(aggregateFavoriteItemsProvider);
              } else {
                _load();
              }
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
