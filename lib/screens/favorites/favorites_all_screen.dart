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

/// 「查看所有」页：展示某分类（电影/电视剧/集）的全部收藏，网格铺开。
/// 顶层路由 `/favorites/all?type=...&title=...`。
/// 筛选与排序作用于全部收藏（跨库，跟随路由 [type] 限定电影/剧集/单集），
/// 恒带 `IsFavorite` 服务端过滤；排序复用分类页 [SortOption]。
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
  /// 默认排序与服务端原行为一致（SortName 升序）。
  SortOption _sortOption = SortOption.nameAsc;
  CategoryFilter _mediaFilter = CategoryFilter.empty;
  MediaFilterOptions? _filterOptions;

  List<MediaItem> _items = [];
  bool _isLoading = true;
  String? _error;

  bool get isEpisode => widget.type == 'episode';

  /// 路由 type → Emby IncludeItemTypes；未知 type 不加载（与旧版空列表一致）。
  String? get _embyType => switch (widget.type) {
        'movie' => 'Movie',
        'series' => 'Series',
        'episode' => 'Episode',
        _ => null,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
    _load();
  }

  /// 打开筛选面板；确认后应用新筛选并重载。
  Future<void> _openFilterPanel() async {
    var options = _filterOptions;
    if (options == null) {
      options = await ref.read(embyServiceProvider).getFilterOptions(
            includeItemTypes: _embyType,
          );
      if (!mounted) return;
      _filterOptions = options;
    }

    final result = await showMediaFilterPanel(
      context,
      current: _mediaFilter,
      options: options,
      tvMode: ref.read(settingsProvider.select((s) => s.tvMode)),
    );
    if (result == null || !mounted || result == _mediaFilter) return;
    setState(() => _mediaFilter = result);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;

    // 收藏状态变化 / 切换服务器后重取（与 favoriteItemsProvider 同源语义）
    ref.listen(favoritesRevisionProvider, (_, __) => _load());
    ref.listen(embyConfigProvider, (_, __) => _load());

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title),
        actions: [
          IconButton(
            key: const Key('favoritesFilterButton'),
            icon: Icon(
              Icons.filter_list,
              color: _mediaFilter.isNotEmpty
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: '筛选',
            onPressed: _openFilterPanel,
          ),
          PopupMenuButton<SortOption>(
            key: const Key('favoritesSortMenu'),
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            onSelected: _onSortChanged,
            itemBuilder: (context) => SortOption.values.map((opt) {
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
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '加载失败：$_error',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          _mediaFilter.isNotEmpty ? '筛选无匹配项' : '暂无收藏',
          key: const Key('favoritesAllEmptyText'),
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

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
                for (final item in _items)
                  SizedBox(
                    width: cardWidth,
                    child: isEpisode
                        ? FavoriteEpisodeCard(
                            item: item,
                            width: cardWidth,
                            onTap: () {
                              // 集条目 → 剧详情页 + 定位到该集
                              if (item.isEpisode && item.seriesId != null) {
                                context.push(
                                    '/detail/${item.seriesId}?episode=${item.id}');
                              } else {
                                context.push('/detail/${item.id}');
                              }
                            },
                          )
                        : PosterCard(
                            key: ValueKey('posterCard_${item.id}'),
                            item: item,
                            width: cardWidth,
                            onTap: () =>
                                context.push('/detail/${item.id}'),
                            onLongPress: (rect) =>
                                showPosterCardMenu(context, ref, item, rect),
                          ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
