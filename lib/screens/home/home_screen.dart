import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/utils/room_code.dart';
import 'package:himi_syncwatch/screens/room/qr_scanner_screen.dart';
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
          if (activeConfig == null) activeConfig = config;
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
    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasServer = ref.watch(embyConfigProvider)?.isAuthenticated == true;

    return Scaffold(
      drawer: _ServerDrawer(onRefresh: _loadMedia),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text('HIMI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '开房间',
            onPressed: hasServer ? () => _createEmptyRoom(context) : null,
          ),
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: '加入房间',
            onPressed: () => _showJoinRoomDialog(context),
          ),
          if (hasServer)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _showSearch(context),
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
                        padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).padding.bottom),
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
          const SnackBar(content: Text('请先在侧边栏配置声网 App ID 和 App Certificate')),
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
            '点击左上角 ☰ 添加 Emby 服务器',
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

class _ServerDrawer extends ConsumerStatefulWidget {
  final VoidCallback onRefresh;
  const _ServerDrawer({required this.onRefresh});

  @override
  ConsumerState<_ServerDrawer> createState() => _ServerDrawerState();
}

class _ServerDrawerState extends ConsumerState<_ServerDrawer> {
  bool _showAddServerForm = false;

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(embyServerListProvider);
    final currentConfig = ref.watch(embyConfigProvider);
    final agoraConfig = ref.watch(agoraConfigProvider);

    final seenServerIds = <String>{};
    final dedupedServers = <EmbyServerConfig>[];
    for (final s in servers) {
      if (seenServerIds.add(s.serverId)) {
        dedupedServers.add(s);
      }
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 设置入口 ──
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('设置'),
              onTap: () {
                Navigator.pop(context);
                context.push('/settings');
              },
            ),
            const Divider(height: 1),
            // ── Emby 服务器区域 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Emby 服务器',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: Icon(_showAddServerForm ? Icons.close : Icons.add),
                    tooltip: _showAddServerForm ? '取消添加' : '添加服务器',
                    onPressed: () =>
                        setState(() => _showAddServerForm = !_showAddServerForm),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_showAddServerForm)
              _AddServerForm(
                onSuccess: () {
                  setState(() => _showAddServerForm = false);
                  widget.onRefresh();
                },
              )
            else
              Expanded(
                child: dedupedServers.isEmpty
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
                        itemCount: dedupedServers.length,
                        itemBuilder: (context, index) {
                          final server = dedupedServers[index];
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
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              '${server.username} · ${server.serverUrl}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onTap: isActive
                                ? null
                                : () {
                                    ref
                                        .read(embyConfigProvider.notifier)
                                        .setConfig(server);
                                    widget.onRefresh();
                                    Navigator.pop(context);
                                  },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isActive)
                                  const Icon(Icons.check_circle,
                                      color: Colors.green, size: 20),
                                PopupMenuButton<String>(
                                  itemBuilder: (context) => [
                                    if (isActive)
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('编辑'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除',
                                          style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      _showEditServerDialog(context, server);
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
                                        final authService = ref.read(
                                            embyAuthServiceProvider);
                                        await authService.deleteSession(
                                            server.serverId);
                                        ref
                                            .read(embyServerListProvider
                                                .notifier)
                                            .removeServer(server.id);
                                        if (isActive) {
                                          final remaining = ref.read(
                                              embyServerListProvider);
                                          if (remaining.isNotEmpty) {
                                            ref
                                                .read(embyConfigProvider
                                                    .notifier)
                                                .setConfig(remaining.first);
                                          } else {
                                            ref
                                                .read(embyConfigProvider
                                                    .notifier)
                                                .clear();
                                          }
                                          widget.onRefresh();
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

            // ── Agora 配置区域 ──
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.key),
              title: const Text('声网配置'),
              subtitle: Text(
                agoraConfig?.isConfigured == true
                    ? 'App ID: ${agoraConfig!.appId.substring(0, 8)}...'
                    : '未配置',
                style: TextStyle(
                  fontSize: 12,
                  color: agoraConfig?.isConfigured == true
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
              trailing: const Icon(Icons.edit),
              onTap: () => _showAgoraConfigSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showAgoraConfigSheet(BuildContext context) {
    final agoraConfig = ref.read(agoraConfigProvider);
    final appIdController = TextEditingController(text: agoraConfig?.appId ?? '');
    final certController = TextEditingController(text: agoraConfig?.appCertificate ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.key, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '声网配置',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.help_outline, size: 20),
                      tooltip: '配置说明',
                      onPressed: () => _showAgoraGuide(context),
                    ),
                    if (agoraConfig?.isConfigured == true)
                      TextButton(
                        onPressed: () async {
                          await ref.read(agoraConfigProvider.notifier).clear();
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('声网配置已清空')),
                            );
                          }
                        },
                        child: const Text('清空', style: TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: appIdController,
                  decoration: const InputDecoration(
                    labelText: 'App ID',
                    hintText: '声网 App ID',
                    prefixIcon: Icon(Icons.vpn_key),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: certController,
                  decoration: const InputDecoration(
                    labelText: 'App Certificate',
                    hintText: '声网 App Certificate',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final appId = appIdController.text.trim();
                      final cert = certController.text.trim();
                      if (appId.isEmpty) return;

                      final config = AgoraConfigModel(
                        appId: appId,
                        appCertificate: cert,
                      );
                      await ref.read(agoraConfigProvider.notifier).save(config);
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('声网配置已保存')),
                        );
                      }
                    },
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      appIdController.dispose();
      certController.dispose();
    });
  }

  void _showAgoraGuide(BuildContext context) {
    final pageController = PageController();
    var currentPage = 0;

    final steps = [
      _AgoraGuideStep(
        title: '注册登录并创建通用项目',
        image: 'assets/images/agora_step1.png',
        description: '访问 shengwang.cn 注册并登录\n'
            '创建项目时选择「通用项目」',
      ),
      _AgoraGuideStep(
        title: '开通体验版套餐包',
        image: 'assets/images/agora_step2.png',
        description: '套餐包 → RTM\n'
            '选择「体验版」（免费）',
      ),
      _AgoraGuideStep(
        title: '开启 Presence 和 Storage',
        image: 'assets/images/agora_step3.png',
        description: '全部产品 → 实时消息 RTM → 基础配置\n'
            '启用「出席通知 (Presence)」\n'
            '启用「状态同步 (Storage)」\n'
            '数据存储区域选「中国」',
      ),
      _AgoraGuideStep(
        title: '获取 APP ID 和证书',
        image: 'assets/images/agora_step4.png',
        description: '项目总览页 → 复制 APP ID\n'
            '展开查看主要证书 → 复制 APP Certificate\n'
            '填入下方输入框 → 点击保存',
      ),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          content: SizedBox(
            width: 360,
            height: 420,
            child: Column(
              children: [
                // 页码指示器
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(steps.length, (i) {
                    return Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == currentPage
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[300],
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                // 页面内容
                Expanded(
                  child: PageView.builder(
                    controller: pageController,
                    itemCount: steps.length,
                    onPageChanged: (i) {
                      currentPage = i;
                      setDialogState(() {});
                    },
                    itemBuilder: (ctx, i) {
                      final step = steps[i];
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            Text(
                              '步骤 ${i + 1}: ${step.title}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () => _showFullImage(context, step.image),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  step.image,
                                  fit: BoxFit.contain,
                                  height: 220,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 220,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '请将截图放到:\n${step.image}',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '点击放大',
                              style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              step.description,
                              style: const TextStyle(fontSize: 13, height: 1.5),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                // 底部按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('关闭'),
                    ),
                    FilledButton(
                      onPressed: currentPage < steps.length - 1
                          ? () {
                              pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          : () => Navigator.pop(ctx),
                      child: Text(
                          currentPage < steps.length - 1 ? '下一步' : '完成'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, String imagePath) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.black,
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Text('图片加载失败', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditServerDialog(BuildContext context, EmbyServerConfig server) {
    final nameController = TextEditingController(text: server.serverName);
    final urlController = TextEditingController(text: server.serverUrl);
    final usernameController = TextEditingController(text: server.username);
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑服务器'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '服务器名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://emby.example.com:8920',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新密码（留空保持不变）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              final username = usernameController.text.trim();
              final password = passwordController.text;

              if (url.isEmpty || username.isEmpty) return;

              final authService = ref.read(embyAuthServiceProvider);

              if (password.isNotEmpty) {
                try {
                  final embyService = EmbyService();
                  final authResult = await embyService.authenticate(
                    serverUrl: url,
                    username: username,
                    password: password,
                    deviceId: server.id,
                  );
                  final newServerId = authResult['ServerId'] ?? server.serverId;
                  final newConfig = server.copyWith(
                    serverUrl: url,
                    serverName: name,
                    username: username,
                    accessToken: authResult['AccessToken'],
                    userId: authResult['User']['Id'],
                    serverId: newServerId,
                  );

                  final existingServers = ref.read(embyServerListProvider);
                  for (final other in existingServers) {
                    if (other.id != server.id && other.serverId == newServerId) {
                      await authService.deleteSession(other.serverId);
                      ref.read(embyServerListProvider.notifier).removeServer(other.id);
                    }
                  }

                  ref.read(embyServerListProvider.notifier).updateServer(newConfig);
                  ref.read(embyConfigProvider.notifier).setConfig(newConfig);
                  await authService.deleteSession(server.serverId);
                  await authService.saveSession(
                    serverId: newConfig.serverId,
                    serverUrl: url,
                    serverName: name,
                    userId: newConfig.userId!,
                    username: username,
                    accessToken: newConfig.accessToken!,
                    id: newConfig.id,
                  );
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('编辑失败: $e')),
                    );
                  }
                  return;
                }
              } else {
                final newConfig = server.copyWith(
                  serverUrl: url,
                  serverName: name,
                  username: username,
                );
                ref.read(embyServerListProvider.notifier).updateServer(newConfig);
                if (ref.read(embyConfigProvider)?.id == server.id) {
                  ref.read(embyConfigProvider.notifier).setConfig(newConfig);
                }
                await authService.deleteSession(server.serverId);
                await authService.saveSession(
                  serverId: newConfig.serverId,
                  serverUrl: url,
                  serverName: name,
                  userId: newConfig.userId ?? '',
                  username: username,
                  accessToken: newConfig.accessToken ?? '',
                  id: newConfig.id,
                );
              }

              if (ctx.mounted) Navigator.pop(ctx);
              widget.onRefresh();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class _AddServerForm extends ConsumerStatefulWidget {
  final VoidCallback onSuccess;
  const _AddServerForm({required this.onSuccess});

  @override
  ConsumerState<_AddServerForm> createState() => _AddServerFormState();
}

class _AddServerFormState extends ConsumerState<_AddServerForm> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _serverName;

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pingAndLogin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = ref.read(embyAuthServiceProvider);
      final url = _urlController.text.trim();

      final info = await EmbyService().pingServer(url);
      final serverName = info['ServerName'] ?? url;
      final serverId = info['Id'] ?? '';

      setState(() => _serverName = serverName);

      final authResult = await EmbyService().authenticate(
        serverUrl: url,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        deviceId: authService.deviceId,
      );

      final user = authResult['User'] as Map<String, dynamic>?;
      final userId = user?['Id'] as String? ?? '';
      final accessToken = authResult['AccessToken'] as String? ?? '';
      final returnedServerId = authResult['ServerId'] as String? ?? serverId;

      if (userId.isEmpty || accessToken.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登录失败：服务端返回数据异常')),
          );
        }
        return;
      }

      final configId = 'srv_${const Uuid().v4().substring(0, 8)}';

      final existingServers = ref.read(embyServerListProvider);
      final duplicate = existingServers.where((s) => s.serverId == returnedServerId).toList();
      for (final old in duplicate) {
        await authService.deleteSession(old.serverId);
        ref.read(embyServerListProvider.notifier).removeServer(old.id);
      }

      final config = EmbyServerConfig(
        id: configId,
        serverUrl: url,
        serverName: serverName,
        serverId: returnedServerId,
        username: _usernameController.text.trim(),
        accessToken: accessToken,
        userId: userId,
      );

      await authService.saveSession(
        serverId: returnedServerId,
        serverUrl: url,
        serverName: serverName,
        userId: userId,
        username: _usernameController.text.trim(),
        accessToken: accessToken,
                  id: config.id,
                );

      ref.read(embyServerListProvider.notifier).addServer(config);
      ref.read(embyConfigProvider.notifier).setConfig(config);

      widget.onSuccess();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_serverName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '已连接: $_serverName',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://emby.example.com:8096',
              prefixIcon: Icon(Icons.dns),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '备注名称（可选）',
              hintText: '如：家里NAS',
              prefixIcon: Icon(Icons.label),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _pingAndLogin,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('连接并登录'),
            ),
          ),
        ],
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

class _AgoraGuideStep {
  final String title;
  final String image;
  final String description;
  const _AgoraGuideStep({
    required this.title,
    required this.image,
    required this.description,
  });
}
