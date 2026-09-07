import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/widgets/media_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _CategoryData {
  final LibraryFolder folder;
  final List<MediaItem> items;
  _CategoryData({required this.folder, required this.items});
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<_CategoryData> _categories = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final embyService = ref.read(embyServiceProvider);
      final libraries = await embyService.getLibraries();

      final categories = <_CategoryData>[];
      for (final lib in libraries) {
        final items = await embyService.getItems(
          parentId: lib.id,
          limit: 8,
        );
        if (items.isNotEmpty) {
          categories.add(_CategoryData(folder: lib, items: items));
        }
      }

      setState(() {
        _categories = categories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HimiSync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: '加入房间',
            onPressed: () => _showJoinRoomDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearch(context),
          ),
        ],
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
                        onPressed: _loadMedia,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMedia,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      return _CategoryRow(
                        category: cat,
                        onViewAll: () => context.push(
                          '/category/${cat.folder.id}?name=${Uri.encodeComponent(cat.folder.name)}',
                        ),
                        onItemTap: (item) => context.push(
                          '/detail/${item.id}',
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(
      context: context,
      delegate: _MediaSearchDelegate(ref),
    );
  }

  void _showJoinRoomDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('加入房间'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入房间号',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context);
              context.push('/room/${value.trim().toUpperCase()}');
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final roomId = controller.text.trim();
              if (roomId.isNotEmpty) {
                Navigator.pop(context);
                context.push('/room/${roomId.toUpperCase()}');
              }
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final _CategoryData category;
  final VoidCallback onViewAll;
  final void Function(MediaItem item) onItemTap;

  const _CategoryRow({
    required this.category,
    required this.onViewAll,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  category.folder.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: onViewAll,
                icon: const Icon(Icons.chevron_right, size: 20),
                label: const Text('查看更多'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: category.items.length,
            itemBuilder: (context, index) {
              final item = category.items[index];
              return SizedBox(
                width: 130,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: MediaCard(
                    item: item,
                    compact: true,
                    onTap: () => onItemTap(item),
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

class _MediaSearchDelegate extends SearchDelegate<String> {
  final WidgetRef ref;

  _MediaSearchDelegate(this.ref);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults();

  Widget _buildSearchResults() {
    if (query.length < 2) {
      return const Center(child: Text('输入至少2个字符进行搜索'));
    }

    return FutureBuilder<List<MediaItem>>(
      future: ref.read(embyServiceProvider).searchItems(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Center(child: Text('未找到结果'));
        }

        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: item.posterUrl != null
                  ? Image.network(
                      item.posterUrl!,
                      width: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.movie),
                    )
                  : const Icon(Icons.movie),
              title: Text(item.name),
              subtitle: Text(item.year ?? ''),
              onTap: () {
                close(context, '');
                context.push('/detail/${item.id}');
              },
            );
          },
        );
      },
    );
  }
}
