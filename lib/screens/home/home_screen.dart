import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/utils/room_code.dart';
import 'package:himi_syncwatch/screens/room/qr_scanner_screen.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';

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
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final authService = ref.read(embyAuthServiceProvider);
    final serverIds = await authService.listServerIds();

    if (serverIds.isNotEmpty) {
      final configs = <EmbyServerConfig>[];
      final seenServerIds = <String>{};
      EmbyServerConfig? activeConfig;

      final savedId = await authService.loadSelectedServerId();

      for (final sid in serverIds) {
        final session = await authService.loadSession(sid);
        if (session != null) {
          final config = EmbyServerConfig.fromJson(session);
          if (seenServerIds.contains(config.serverId)) {
            await authService.deleteSession(sid);
            continue;
          }
          seenServerIds.add(config.serverId);
          configs.add(config);
          if (activeConfig == null || config.id == savedId) {
            activeConfig = config;
          }
        }
      }

      ref.read(embyServerListProvider.notifier).setList(configs);

      if (activeConfig != null) {
        ref.read(embyConfigProvider.notifier).setConfig(activeConfig);
        await _loadMedia();
      } else {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }

    setState(() => _initialized = true);
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
          sortBy: 'DateCreated',
          sortOrder: 'Descending',
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
    // 服务器在「Emby服务器」标签页切换 / 增删后，重新加载首页媒体
    ref.listen<EmbyServerConfig?>(embyConfigProvider, (prev, next) {
      if (!_initialized || next == null || identical(prev, next)) return;
      _loadMedia();
    });

    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasServer = ref.watch(embyConfigProvider)?.isAuthenticated == true;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Align(
          alignment: Alignment.centerLeft,
          child: _buildTitle(ref.watch(embyConfigProvider)),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GlassContainer(
              borderRadius: const BorderRadius.all(Radius.circular(24)),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: '开房间',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 44, minHeight: 44),
                    onPressed: hasServer ? () => _createEmptyRoom(context) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.group_add),
                    tooltip: '加入房间',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 44, minHeight: 44),
                    onPressed: () => _showJoinRoomDialog(context),
                  ),
                  if (hasServer)
                    IconButton(
                      icon: const Icon(Icons.search),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 44, minHeight: 44),
                      onPressed: () => _showSearch(context),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: !hasServer
          ? const _EmptyState()
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_error!,
                              style: const TextStyle(color: Colors.red)),
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
                        padding: EdgeInsets.only(
                          top: GlassConfig.topInsetOf(context),
                          bottom: GlassConfig.bottomReserveOf(context),
                        ),
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          final cat = _categories[index];
                          return _CategorySection(
                            category: cat,
                            onViewAll: () => context.push(
                              '/category/${cat.folder.id}?name=${Uri.encodeComponent(cat.folder.name)}&type=${cat.folder.collectionType}',
                            ),
                            onItemTap: (item) =>
                                context.push('/detail/${item.id}'),
                          );
                        },
                      ),
                    ),
    );
  }

  /// 标题显示当前服务器名，椭圆玻璃包裹，点击下拉切换 Emby 服务器。
  Widget _buildTitle(EmbyServerConfig? current) {
    final servers = ref.watch(embyServerListProvider);
    final seenServerIds = <String>{};
    final dedupedServers = <EmbyServerConfig>[];
    for (final s in servers) {
      if (seenServerIds.add(s.serverId)) {
        dedupedServers.add(s);
      }
    }

    final label = current?.label ?? 'HIMI';
    if (dedupedServers.isEmpty) {
      return GlassContainer(
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
    }

    return GlassContainer(
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      padding: const EdgeInsets.only(left: 12, right: 2),
      child: PopupMenuButton<String>(
        tooltip: '切换服务器',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        onSelected: (id) {
          for (final s in dedupedServers) {
            if (s.id == id) {
              _selectServer(s);
              break;
            }
          }
        },
        itemBuilder: (context) => dedupedServers.map((s) {
          final active = current?.id == s.id;
          return PopupMenuItem(
            value: s.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active)
                  const Icon(Icons.check_circle, size: 18, color: Colors.green)
                else
                  const Icon(Icons.dns_outlined, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    s.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.dns_outlined, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label, overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectServer(EmbyServerConfig server) async {
    final current = ref.read(embyConfigProvider);
    if (current?.id == server.id) return;
    ref.read(embyConfigProvider.notifier).setConfig(server);
    await ref.read(embyAuthServiceProvider).saveSelectedServerId(server.id);
  }

  void _showSearch(BuildContext context) {
    showSearch(context: context, delegate: _MediaSearchDelegate(ref));
  }

  void _showJoinRoomDialog(BuildContext context) {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('加入房间'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                hintText: '粘贴房间码',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              minLines: 1,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                hintText: '你的昵称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final result = await navigator.push<String>(
                    MaterialPageRoute(
                      builder: (_) => const QrScannerScreen(),
                    ),
                  );
                  if (result != null && context.mounted) {
                    final roomData = RoomCode.decode(result);
                    if (roomData == null) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('扫码结果无效')),
                      );
                      return;
                    }
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      _showJoinRoomDialog(context);
                      return;
                    }
                    context.push(
                      '/player/_?roomCode=${Uri.encodeComponent(result)}&isHost=false&name=${Uri.encodeComponent(name)}',
                    );
                  }
                },
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('扫码加入'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final code = codeController.text.trim();
              final name = nameController.text.trim();
              if (code.isNotEmpty && name.isNotEmpty) {
                Navigator.pop(dialogContext);
                final roomData = RoomCode.decode(code);
                if (roomData == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('房间码无效')),
                  );
                  return;
                }
                context.push(
                  '/player/_?roomCode=${Uri.encodeComponent(code)}&isHost=false&name=${Uri.encodeComponent(name)}',
                );
              }
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }

  Future<void> _createEmptyRoom(BuildContext context) async {
    final agoraConfig = ref.read(agoraConfigProvider);
    if (agoraConfig == null || !agoraConfig.isConfigured) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('请先在「声网配置」页填写 App ID 和 App Certificate')),
        );
      }
      return;
    }

    final tokenCount = await _showTokenCountDialog(context);
    if (tokenCount == null) return;

    final channel = RoomCode.generateChannelId();
    final roomCode = RoomCode.encode(
      appId: agoraConfig.appId,
      appCertificate: agoraConfig.appCertificate,
      channel: channel,
      tokenCount: tokenCount,
    );

    if (context.mounted) {
      context.push(
        '/player/_?roomCode=${Uri.encodeComponent(roomCode)}&isHost=true',
      );
    }
  }

  Future<int?> _showTokenCountDialog(BuildContext context) {
    final controller = TextEditingController(text: '2');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开房间'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('房间最大人数', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              if (n != null && n > 0 && n <= 100) {
                Navigator.pop(ctx, n);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns, size: 64, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text(
            '暂无服务器',
            style: TextStyle(fontSize: 18, color: Colors.grey[400]),
          ),
          const SizedBox(height: 8),
          Text(
            '请到「Emby服务器」标签添加 Emby 服务器',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
    if (query.length < 1) {
      return const Center(child: Text('输入关键词进行搜索'));
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
