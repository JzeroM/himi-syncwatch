import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/widgets/media_card.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  final String libraryId;
  final String? libraryName;

  const CategoryScreen({
    super.key,
    required this.libraryId,
    this.libraryName,
  });

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  List<MediaItem> _items = [];
  bool _isLoading = true;
  String? _error;
  int _currentBatch = 0;
  static const int _batchSize = 30;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final embyService = ref.read(embyServiceProvider);
      final items = await embyService.getItems(
        parentId: widget.libraryId,
        limit: _batchSize,
        startIndex: 0,
      );
      setState(() {
        _items = items;
        _currentBatch = 1;
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
    if (_loadingMore) return;
    setState(() => _loadingMore = true);

    try {
      final embyService = ref.read(embyServiceProvider);
      final moreItems = await embyService.getItems(
        parentId: widget.libraryId,
        limit: _batchSize,
        startIndex: _currentBatch * _batchSize,
      );
      if (moreItems.isNotEmpty) {
        setState(() {
          _items.addAll(moreItems);
          _currentBatch++;
        });
      }
    } catch (_) {}

    setState(() => _loadingMore = false);
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadItems,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadItems,
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(8),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.7,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => MediaCard(
                              item: _items[index],
                              onTap: () => context.push(
                                '/detail/${_items[index].id}',
                              ),
                            ),
                            childCount: _items.length,
                          ),
                        ),
                      ),
                      if (_loadingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      if (!_loadingMore && _items.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: OutlinedButton(
                                onPressed: _loadMore,
                                child: const Text('加载更多'),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
