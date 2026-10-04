import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';
import 'package:himi_syncwatch/widgets/tv/tv_refresh_hotkey.dart';

enum SortOption {
  dateDesc('最近添加', 'DateCreated', 'Descending'),
  nameAsc('名称 A-Z', 'SortName', 'Ascending'),
  nameDesc('名称 Z-A', 'SortName', 'Descending'),
  yearDesc('年份 ↓', 'ProductionYear', 'Descending'),
  yearAsc('年份 ↑', 'ProductionYear', 'Ascending'),
  ratingDesc('评分 ↓', 'CommunityRating', 'Descending'),
  ratingAsc('评分 ↑', 'CommunityRating', 'Ascending');

  final String label;
  final String sortBy;
  final String sortOrder;
  const SortOption(this.label, this.sortBy, this.sortOrder);
}

enum FilterOption {
  all('全部', null),
  movie('电影', 'Movie'),
  series('剧集', 'Series');

  final String label;
  final String? embyValue;
  const FilterOption(this.label, this.embyValue);
}

FilterOption _defaultFilter(String? collectionType) {
  switch (collectionType) {
    case 'movies':
      return FilterOption.movie;
    case 'tvshows':
      return FilterOption.series;
    default:
      return FilterOption.all;
  }
}

class CategoryScreen extends ConsumerStatefulWidget {
  final String libraryId;
  final String? libraryName;
  final String? collectionType;

  const CategoryScreen({
    super.key,
    required this.libraryId,
    this.libraryName,
    this.collectionType,
  });

  /// 分类页网格列数（全平台）：见设置项「分类页每行海报数」。
  ///
  /// - [columns] 指定值优先（null = 自动）；
  /// - 自动：TV 每行基准 120 逻辑px（1080p 盒子 960 宽 → 8 列），
  ///   宽屏 180（现状），窄屏固定 4（现状）；
  /// - 屏幕保护：每列不低于 80 逻辑px，指定列数放不下时压回
  ///   可显示的最大值（各分支另有上限封顶）。
  @visibleForTesting
  static int gridColumns({
    required double width,
    required bool tvMode,
    int? columns,
  }) {
    final int target;
    if (columns != null) {
      target = columns;
    } else if (tvMode) {
      target = (width / 120).floor();
    } else if (width > 600) {
      target = (width / 180).floor();
    } else {
      target = 4;
    }

    final maxFit = (width / 80).floor();
    final upper = tvMode ? 14 : (width > 600 ? 12 : 6);
    final cap = maxFit > upper ? upper : maxFit;
    return target.clamp(1, cap < 1 ? 1 : cap);
  }

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  final ScrollController _scrollController = ScrollController();
  final int _pageSize = 30;

  List<MediaItem> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  int _startIndex = 0;
  bool _hasMore = true;

  SortOption _sortOption = SortOption.dateDesc;
  late FilterOption _filterOption;

  bool get _showFilterChips =>
      widget.collectionType != 'movies' && widget.collectionType != 'tvshows';

  @override
  void initState() {
    super.initState();
    _filterOption = _defaultFilter(widget.collectionType);
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _items = [];
      _startIndex = 0;
      _hasMore = true;
    });

    try {
      final embyService = ref.read(embyServiceProvider);
      final items = await embyService.getItems(
        parentId: widget.libraryId,
        limit: _pageSize,
        startIndex: 0,
        includeItemTypes: _filterOption.embyValue,
        fields:
            'ImageTags,PrimaryImageAspectRatio,ProductionYear,CommunityRating,IndexNumber',
        sortBy: _sortOption.sortBy,
        sortOrder: _sortOption.sortOrder,
      );

      setState(() {
        _items = items;
        _startIndex = items.length;
        _hasMore = items.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final embyService = ref.read(embyServiceProvider);
      final moreItems = await embyService.getItems(
        parentId: widget.libraryId,
        limit: _pageSize,
        startIndex: _startIndex,
        includeItemTypes: _filterOption.embyValue,
        fields:
            'ImageTags,PrimaryImageAspectRatio,ProductionYear,CommunityRating,IndexNumber',
        sortBy: _sortOption.sortBy,
        sortOrder: _sortOption.sortOrder,
      );

      if (moreItems.isNotEmpty) {
        setState(() {
          _items.addAll(moreItems);
          _startIndex += moreItems.length;
          _hasMore = moreItems.length >= _pageSize;
        });
      } else {
        setState(() => _hasMore = false);
      }
    } catch (_) {}

    setState(() => _isLoadingMore = false);
  }

  void _onSortChanged(SortOption? value) {
    if (value == null || value == _sortOption) return;
    setState(() => _sortOption = value);
    _loadFirstPage();
  }

  void _onFilterChanged(FilterOption value) {
    if (value == _filterOption) return;
    setState(() => _filterOption = value);
    _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    // 主题色三段渐变背景（null 时保持应用底色，与首页/详情页一致）
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;

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
        title: Text(widget.libraryName ?? '分类'),
        actions: [
          PopupMenuButton<SortOption>(
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
        key: const Key('categoryBackground'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: PosterPalette.pageGradient(accent, base),
        ),
        child: Column(
          children: [
            // extendBodyBehindAppBar：内容从屏顶开始，先给 AppBar 留位
            SizedBox(height: GlassConfig.topInsetOf(context)),
            if (_showFilterChips) _buildFilterChips(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: FilterOption.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final opt = FilterOption.values[index];
          final selected = opt == _filterOption;
          return FilterChip(
            label: Text(opt.label),
            selected: selected,
            onSelected: (_) => _onFilterChanged(opt),
            selectedColor: Theme.of(context).colorScheme.primaryContainer,
            checkmarkColor: Theme.of(context).colorScheme.primary,
          );
        },
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
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFirstPage,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(child: Text('暂无内容'));
    }

    return TvRefreshHotkey(
      onRefresh: _loadFirstPage,
      child: RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = CategoryScreen.gridColumns(
              width: constraints.maxWidth,
              tvMode: ref.watch(settingsProvider.select((s) => s.tvMode)),
              columns:
                  ref.watch(settingsProvider.select((s) => s.categoryColumns)),
            );
            // 按列宽精确匹配 2:3 海报 + 文字区，海报完整不裁切
            final cellWidth =
                (constraints.maxWidth - 8 * 2 - 8 * (columns - 1)) / columns;
            final childAspectRatio =
                cellWidth / PosterCard.heightFor(cellWidth);

            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(8),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: childAspectRatio,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => PosterCard(
                        key: ValueKey('posterCard_${_items[index].id}'),
                        item: _items[index],
                        width: cellWidth,
                        onTap: () =>
                            context.push('/detail/${_items[index].id}'),
                      ),
                      childCount: _items.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildFooter(),
                ),
                SliverToBoxAdapter(
                  child:
                      SizedBox(height: MediaQuery.of(context).padding.bottom),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasMore && _items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            '已加载全部 ${_items.length} 项',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
