import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

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
            'ImageTags,PrimaryImageAspectRatio,ProductionYear,CommunityRating',
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
            'ImageTags,PrimaryImageAspectRatio,ProductionYear,CommunityRating',
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
    return Scaffold(
      appBar: AppBar(
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
      body: Column(
        children: [
          if (_showFilterChips) _buildFilterChips(),
          Expanded(child: _buildBody()),
        ],
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

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isPC = constraints.maxWidth > 600;
          final columns = isPC
              ? (constraints.maxWidth / 180).floor().clamp(2, 12)
              : 3;

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(8),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: 0.56,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _GridCard(
                      item: _items[index],
                      onTap: () => context.push('/detail/${_items[index].id}'),
                    ),
                    childCount: _items.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildFooter(),
              ),
            ],
          );
        },
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

class _GridCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  const _GridCard({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: EmbyImage(url: item.posterUrl, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (item.year != null)
                    Text(
                      item.year!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
