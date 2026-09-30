import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';
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
  List<LibraryFolder> _libraries = [];
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
      final libs = await embyService.getLibraries();

      final futures = libs.map((lib) async {
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

      // 媒体库栏：剔除空库，其余严格保持服务端排序
      final nonEmptyIds = {for (final c in categories) c.folder.id};
      final libraries = [
        for (final lib in libs)
          if (nonEmptyIds.contains(lib.id)) lib
      ];

      setState(() {
        _categories = categories;
        _libraries = libraries;
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

    // 主题色三段渐变背景（null 时保持应用底色）
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
                    icon: const Icon(Icons.meeting_room_outlined),
                    tooltip: '房间',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 44, minHeight: 44),
                    onPressed: () => _showRoomCard(context,
                        hasServer: hasServer),
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
      body: AnimatedContainer(
        key: const Key('homeBackground'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: PosterPalette.pageGradient(accent, base),
        ),
        child: !hasServer
            ? const _EmptyState()
            : _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
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
                          itemCount: _categories.length +
                              (_libraries.isNotEmpty ? 1 : 0),
                          itemBuilder: (context, index) {
                            final headerCount =
                                _libraries.isNotEmpty ? 1 : 0;
                            if (index < headerCount) {
                              return _LibraryBar(
                                libraries: _libraries,
                                onOpen: (lib) => context.push(
                                  '/category/${lib.id}?name=${Uri.encodeComponent(lib.name)}&type=${lib.collectionType}',
                                ),
                              );
                            }
                            final cat = _categories[index - headerCount];
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

    return Builder(
      builder: (titleContext) => GlassContainer(
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        padding: const EdgeInsets.only(left: 12, right: 2),
        child: Tooltip(
          message: '切换服务器',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showServerMenu(
              titleContext,
              current: current,
              servers: dedupedServers,
            ),
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
        ),
      ),
    );
  }

  /// 标题下方锚定的液态玻璃服务器下拉层（替代 Material PopupMenu）。
  void _showServerMenu(
    BuildContext titleContext, {
    required EmbyServerConfig? current,
    required List<EmbyServerConfig> servers,
  }) {
    final box = titleContext.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final screenW = MediaQuery.sizeOf(titleContext).width;

    showGeneralDialog<void>(
      context: titleContext,
      barrierDismissible: true,
      barrierLabel: '关闭服务器列表',
      barrierColor: Colors.black.withValues(alpha: 0.30),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, __) {
        var left = rect.left < 12 ? 12.0 : rect.left;
        var width =
            math.min(math.max(rect.width, 220.0), screenW - left - 12);
        if (left + width > screenW - 12) {
          left = math.max(12.0, screenW - 12 - width);
        }
        return Stack(
          children: [
            Positioned(
              left: left,
              top: rect.bottom + 8,
              width: width,
              child: Material(
                type: MaterialType.transparency,
                child: GlassContainer(
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final s in servers)
                            _buildServerRow(
                              dialogContext,
                              s,
                              active: current?.id == s.id,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildServerRow(
    BuildContext dialogContext,
    EmbyServerConfig server, {
    required bool active,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pop(dialogContext);
        _selectServer(server);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            if (active)
              const Icon(Icons.check_circle, size: 18, color: Colors.green)
            else
              const Icon(Icons.dns_outlined, size: 18, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                server.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 房间入口玻璃卡片：创建房间 / 加入房间二选一。
  void _showRoomCard(BuildContext context, {required bool hasServer}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        child: Material(
          type: MaterialType.transparency,
          child: GlassContainer(
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    '房间',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                _roomOption(
                  dialogContext: dialogContext,
                  icon: Icons.add_circle_outline,
                  title: '创建房间',
                  subtitle: '开一局同步观影',
                  enabled: hasServer,
                  run: () => _createEmptyRoom(context),
                ),
                _roomOption(
                  dialogContext: dialogContext,
                  icon: Icons.group_add,
                  title: '加入房间',
                  subtitle: '粘贴或扫码加入',
                  enabled: true,
                  run: () => _showJoinRoomDialog(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roomOption({
    required BuildContext dialogContext,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback run,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled
            ? () {
                Navigator.pop(dialogContext);
                run();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 24, color: Colors.white70),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.white38),
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

/// 首页「媒体库」横向栏：库封面卡片按服务端排序排列，
/// 点击进入对应分类海报墙。
class _LibraryBar extends StatelessWidget {
  const _LibraryBar({required this.libraries, required this.onOpen});

  final List<LibraryFolder> libraries;
  final void Function(LibraryFolder library) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '媒体库',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: libraries.length,
            itemBuilder: (context, index) {
              final lib = libraries[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  key: ValueKey('libraryCard_${lib.id}'),
                  onTap: () => onOpen(lib),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 160,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          EmbyImage(url: lib.posterUrl, fit: BoxFit.cover),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.0),
                                  Colors.black.withValues(alpha: 0.62),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 8,
                            child: Text(
                              lib.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

  Future<List<GlobalSearchResult>>? _cachedFuture;
  String? _cachedQuery;

  /// 聚合搜索全部已认证服务器；缓存避免 rebuild 重复触发。
  Future<List<GlobalSearchResult>> _search() {
    final q = query.trim();
    if (_cachedQuery != q || _cachedFuture == null) {
      _cachedQuery = q;
      _cachedFuture = ref
          .read(globalSearchProvider)
          .search(q, ref.read(embyServerListProvider));
    }
    return _cachedFuture!;
  }

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
    if (query.trim().isEmpty) {
      return const Center(child: Text('输入关键词搜索全部服务器'));
    }
    return FutureBuilder<List<GlobalSearchResult>>(
      future: _search(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? [];
        if (results.isEmpty) return const Center(child: Text('未找到结果'));
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final r = results[index];
            final item = r.item;
            final meta = item.year != null
                ? '${r.server.serverName} · ${item.year}'
                : r.server.serverName;
            return ListTile(
              leading: SizedBox(
                width: 50,
                height: 70,
                child: EmbyImage(url: item.posterUrl, fit: BoxFit.cover),
              ),
              title: Text(item.name),
              subtitle: Text(meta),
              onTap: () {
                close(context, '');
                context.push(
                  '/detail/${item.id}?server=${Uri.encodeComponent(r.server.id)}',
                );
              },
            );
          },
        );
      },
    );
  }
}
