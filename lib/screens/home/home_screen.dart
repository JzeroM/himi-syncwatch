import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

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

      final futures = libraries.map((lib) async {
        final items = await embyService.getItems(
          parentId: lib.id,
          limit: 20,
          includeItemTypes: 'Movie,Series',
          fields: 'ImageTags,PrimaryImageAspectRatio,ProductionYear',
        );
        return _CategoryData(folder: lib, items: items);
      }).toList();

      final results = await Future.wait(futures);
      final categories = results.where((c) => c.items.isNotEmpty).toList();

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
      drawer: _ServerDrawer(onRefresh: _loadMedia),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
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
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      return _CategorySection(
                        category: cat,
                        onViewAll: () => context.push(
                          '/category/${cat.folder.id}?name=${Uri.encodeComponent(cat.folder.name)}',
                        ),
                        onItemTap: (item) =>
                            context.push('/detail/${item.id}'),
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

class _CategorySection extends StatelessWidget {
  final _CategoryData category;
  final VoidCallback onViewAll;
  final void Function(MediaItem item) onItemTap;

  const _CategorySection({
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
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: GestureDetector(
            onTap: onViewAll,
            child: Row(
              children: [
                Text(
                  category.folder.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 22),
              ],
            ),
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
                  child: _PosterCard(
                    item: item,
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

class _PosterCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  const _PosterCard({required this.item, this.onTap});

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

class _ServerDrawer extends ConsumerWidget {
  final VoidCallback onRefresh;
  const _ServerDrawer({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(embyServerListProvider);
    final currentConfig = ref.watch(embyConfigProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '服务器',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: '添加服务器',
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/login');
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: servers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '暂无服务器\n点击右上角 + 添加',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: servers.length,
                      itemBuilder: (context, index) {
                        final server = servers[index];
                        final isActive = currentConfig?.id == server.id;
                        return ListTile(
                          leading: Icon(
                            Icons.dns,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: Text(
                            server.label,
                            style: TextStyle(
                              fontWeight:
                                  isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            '${server.username} · ${server.serverUrl}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isActive)
                                const Icon(Icons.check_circle,
                                    color: Colors.green, size: 20),
                              PopupMenuButton<String>(
                                itemBuilder: (context) => [
                                  if (!isActive)
                                    const PopupMenuItem(
                                      value: 'switch',
                                      child: Text('切换'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除',
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                                onSelected: (value) async {
                                  if (value == 'switch') {
                                    await ref
                                        .read(embyConfigProvider.notifier)
                                        .saveConfig(server);
                                    onRefresh();
                                    if (context.mounted) Navigator.pop(context);
                                  } else if (value == 'delete') {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('删除服务器'),
                                        content: Text(
                                            '确定删除 "${server.label}" 吗？'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('删除',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed == true) {
                                      await ref
                                          .read(embyServerListProvider.notifier)
                                          .removeServer(server.id);
                                      if (isActive) {
                                        final remaining =
                                            ref.read(embyServerListProvider);
                                        if (remaining.isNotEmpty) {
                                          await ref
                                              .read(embyConfigProvider.notifier)
                                              .saveConfig(remaining.first);
                                        } else {
                                          await ref
                                              .read(embyConfigProvider.notifier)
                                              .clearConfig();
                                        }
                                        onRefresh();
                                      }
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('退出登录'),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('退出登录'),
                    content: const Text('确定退出当前登录吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('退出',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(embyConfigProvider.notifier).clearConfig();
                  if (context.mounted) context.go('/login');
                }
              },
            ),
          ],
        ),
      ),
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
        if (items.isEmpty) return const Center(child: Text('未找到结果'));
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              leading: SizedBox(
                width: 50,
                height: 70,
                child: EmbyImage(url: item.posterUrl, fit: BoxFit.cover),
              ),
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
