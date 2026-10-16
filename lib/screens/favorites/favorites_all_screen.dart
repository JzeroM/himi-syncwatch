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

  /// 在途的可选项请求（预取与打开面板共享，去重避免重复网络往返）。
  Future<MediaFilterOptions>? _filterOptionsFuture;

  /// 筛选面板打开中（防重入：连点只会弹出一个面板）。
  bool _filterOpening = false;

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
    // 进页即后台预取筛选可选项（v1.1.235）：让首次打开筛选面板连选项都瞬时。
    // 未知 type（_embyType == null）不加载，跳过预取。
    if (_embyType != null) _prefetchFilterOptions();
    _load();
  }

  /// 后台预取筛选面板可选项（进页调用一次）。
  ///
  /// 复用在途 future 去重：预取与打开面板共享同一请求，避免重复网络往返。
  /// 失败/未完成不影响主列表，面板侧仍可走 optionsFuture 先弹后填。
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

  /// 拉取可选项并写回缓存（供 _openFilterPanel 在无缓存且无预取时兜底）。
  Future<MediaFilterOptions> _fetchFilterOptions() async {
    final options = await ref.read(embyServiceProvider).getFilterOptions(
          includeItemTypes: _embyType,
        );
    if (mounted) setState(() => _filterOptions = options);
    return options;
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
  ///
  /// 防重入（v1.1.234）：面板 await 期间再次点击会被忽略，否则会弹出两个
  /// 叠加的筛选面板。
  ///
  /// 先弹后填（v1.1.235）：不再 await 可选项请求——命中缓存直接传 options，
  /// 未命中则把预取的 future 传给面板（面板立即弹出，选项就绪后补上）。
  Future<void> _openFilterPanel() async {
    if (_filterOpening) return;
    setState(() => _filterOpening = true);
    try {
      final cached = _filterOptions;
      final result = await showMediaFilterPanel(
        context,
        current: _mediaFilter,
        options: cached,
        optionsFuture:
            cached == null ? (_filterOptionsFuture ??= _fetchFilterOptions()) : null,
        tvMode: ref.read(settingsProvider.select((s) => s.tvMode)),
      );
      if (result == null || !mounted || result == _mediaFilter) return;
      setState(() => _mediaFilter = result);
      _load();
    } finally {
      if (mounted) setState(() => _filterOpening = false);
    }
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
            // 打开期间置灰：配合防重入守卫，杜绝连点弹出两个面板
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
