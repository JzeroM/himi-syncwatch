import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/server_stats_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/qr_config_screen.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/lan_config/emby_setup_service.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/server_card.dart';
import 'package:himi_syncwatch/widgets/tv/tv_exclude_editable.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 按 serverId 去重（同服务器多 session 只展示第一个）。
List<EmbyServerConfig> _dedupServers(List<EmbyServerConfig> servers) {
  final seen = <String>{};
  final result = <EmbyServerConfig>[];
  for (final s in servers) {
    if (seen.add(s.serverId)) result.add(s);
  }
  return result;
}

/// Emby 服务器管理页（网格/列表双视图 + 拖拽排序 + 真延迟/计数）。
class ServerManagerScreen extends ConsumerStatefulWidget {
  const ServerManagerScreen({super.key});

  @override
  ConsumerState<ServerManagerScreen> createState() =>
      _ServerManagerScreenState();
}

class _ServerManagerScreenState extends ConsumerState<ServerManagerScreen> {
  bool _showAddServerForm = false;

  /// TV 布局模式：正在移动的服务器 id（null = 非布局模式）。
  String? _layoutServerId;

  /// 布局模式进入时的顺序快照（返回键取消时还原）。
  List<EmbyServerConfig>? _layoutBackup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  Future<void> _loadStats() async {
    final servers = _dedupServers(ref.read(embyServerListProvider));
    if (servers.isEmpty) return;
    await ref.read(serverStatsProvider.notifier).loadAll(servers);
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(embyServerListProvider);
    final currentConfig = ref.watch(embyConfigProvider);
    final statsMap = ref.watch(serverStatsProvider);
    final viewMode =
        ref.watch(settingsProvider.select((s) => s.serverViewMode));
    // 扫码配置入口仅 TV 模式（遥控器无输入法）：手机/桌面走手动输入
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));

    final dedupedServers = _dedupServers(servers);
    final layoutId = _layoutServerId;

    // 布局模式：拦截返回键取消还原（正常态放行路由返回）
    return PopScope(
      canPop: layoutId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _layoutServerId != null) {
          _exitLayoutMode(save: false);
        }
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Emby 服务器'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const GlassBackdrop(),
        actions: [
          IconButton(
            key: const ValueKey('serverViewToggle'),
            icon: Icon(
                viewMode == 'list' ? Icons.view_module : Icons.view_list),
            tooltip: viewMode == 'list' ? '网格视图' : '列表视图',
            onPressed: () => ref.read(settingsProvider.notifier).update(
                  serverViewMode: viewMode == 'list' ? 'grid' : 'list',
                ),
          ),
          IconButton(
            key: const ValueKey('serverStatsRefresh'),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新延迟与计数',
            onPressed: _loadStats,
          ),
          if (tvMode)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: '手机扫码配置',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const QrConfigScreen(mode: 'emby'),
                ),
              ),
            ),
          // TV 不提供手动添加表单（遥控器无输入法）：走上方扫码入口
          if (!tvMode)
            IconButton(
              icon: Icon(_showAddServerForm ? Icons.close : Icons.add),
              tooltip: _showAddServerForm ? '取消添加' : '添加服务器',
              onPressed: () =>
                  setState(() => _showAddServerForm = !_showAddServerForm),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: GlassConfig.topInsetOf(context)),
          if (_showAddServerForm && !tvMode)
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                    bottom: GlassConfig.bottomReserveOf(context)),
                child: _AddServerForm(
                  onSuccess: () {
                    if (!mounted) return;
                    setState(() => _showAddServerForm = false);
                    showAppToast(context, '服务器已添加');
                    // 新服务器自动排末尾（home _init 把不在序里的排尾部），
                    // 进页统计补上它
                    _loadStats();
                  },
                ),
              ),
            )
          else
            Expanded(
              child: dedupedServers.isEmpty
                  ? const _EmptyServerHint()
                  : viewMode == 'grid'
                      ? _buildGrid(dedupedServers, currentConfig, statsMap)
                      : _buildList(dedupedServers, currentConfig, statsMap),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildList(
    List<EmbyServerConfig> dedupedServers,
    EmbyServerConfig? currentConfig,
    Map<String, ServerStats> statsMap,
  ) {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: EdgeInsets.only(
        top: 8,
        bottom: GlassConfig.bottomReserveOf(context),
      ),
      itemCount: dedupedServers.length,
      onReorderItem: (oldIndex, newIndex) =>
          _reorderVisible(oldIndex, newIndex),
      itemBuilder: (context, index) {
        final server = dedupedServers[index];
        final isActive = currentConfig?.id == server.id;
        // itemBuilder 返回值的 key 必须在最外层（重排后 Focus/元素才不丢）
        return KeyedSubtree(
          key: ValueKey('serverTile_${server.id}'),
          child: _wrapCard(
            server: server,
            isGrid: false,
            crossAxisCount: 1,
            card: ServerListCard(
              server: server,
              isActive: isActive,
              stats: statsMap[server.id],
              onTap: () => _openServer(server),
              onEdit: () => _showEditServerDialog(server),
              onDelete: () => _deleteServer(server, isActive),
              // TV 模式：隐藏拖拽把手（布局模式用方向键移动）
              dragHandle: tvMode
                  ? null
                  : ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle, size: 20),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid(
    List<EmbyServerConfig> dedupedServers,
    EmbyServerConfig? currentConfig,
    Map<String, ServerStats> statsMap,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = (width / 220).floor().clamp(2, 4);
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        GlassConfig.bottomReserveOf(context),
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.92,
      ),
      itemCount: dedupedServers.length,
      itemBuilder: (context, index) {
        final server = dedupedServers[index];
        final isActive = currentConfig?.id == server.id;
        final card = KeyedSubtree(
          key: ValueKey('serverGridTile_${server.id}'),
          child: _wrapCard(
            server: server,
            isGrid: true,
            crossAxisCount: crossAxisCount,
            card: ServerGridCard(
              server: server,
              isActive: isActive,
              stats: statsMap[server.id],
              onTap: () => _openServer(server),
              onEdit: () => _showEditServerDialog(server),
              onDelete: () => _deleteServer(server, isActive),
            ),
          ),
        );
        // TV 模式：禁用长按拖拽（用布局模式方向键移动）
        if (tvMode) return card;
        return LongPressDraggable<int>(
          data: index,
          maxSimultaneousDrags: 1,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: SizedBox(width: 180, height: 200, child: card),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: card),
          child: DragTarget<int>(
            onAcceptWithDetails: (details) =>
                _reorderVisible(details.data, index),
            builder: (context, candidateData, rejectedData) => card,
          ),
        );
      },
    );
  }

  /// TV 模式卡片包装：
  /// - 常规态：TvFocusable（短按 OK 打开 / 长按 OK 进布局模式）
  /// - 布局模式选中卡：Focus 拦截方向键移动 + OK 保存退出，外加高亮描边
  /// - 布局模式其他卡：忽略指针 + 降透明 + 排除焦点
  /// 非 TV 模式原样返回。
  Widget _wrapCard({
    required EmbyServerConfig server,
    required bool isGrid,
    required int crossAxisCount,
    required Widget card,
  }) {
    if (!ref.watch(settingsProvider.select((s) => s.tvMode))) return card;

    final layoutId = _layoutServerId;
    if (layoutId == server.id) {
      return Focus(
        autofocus: true,
        onKeyEvent: (node, event) =>
            _handleLayoutKey(event, isGrid: isGrid, crossAxisCount: crossAxisCount),
        child: _layoutDecorate(card),
      );
    }
    if (layoutId != null) {
      return ExcludeFocus(
        child: IgnorePointer(
          child: Opacity(opacity: 0.4, child: card),
        ),
      );
    }
    return TvFocusable(
      autofocus: true,
      scale: 1.03,
      radius: 18,
      onTap: () => _openServer(server),
      onLongPress: () => _enterLayoutMode(server),
      child: card,
    );
  }

  /// 布局模式选中卡：琥珀色描边 + 「移动中」角标。
  Widget _layoutDecorate(Widget child) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.amber, width: 3),
              ),
            ),
          ),
        ),
        Positioned(
          top: 6,
          left: 6,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '移动中',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 布局模式按键：上下左右移动 + 短按 OK 保存退出。
  KeyEventResult _handleLayoutKey(
    KeyEvent event, {
    required bool isGrid,
    required int crossAxisCount,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      _exitLayoutMode(save: true);
      return KeyEventResult.handled;
    }
    int? delta;
    if (key == LogicalKeyboardKey.arrowUp) {
      delta = isGrid ? -crossAxisCount : -1;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      delta = isGrid ? crossAxisCount : 1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      delta = isGrid ? -1 : null; // 列表无左右移动
    } else if (key == LogicalKeyboardKey.arrowRight) {
      delta = isGrid ? 1 : null;
    }
    if (delta != null) {
      _layoutMoveBy(delta);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _enterLayoutMode(EmbyServerConfig server) {
    closeServerActionPanel();
    setState(() {
      _layoutServerId = server.id;
      _layoutBackup = List.of(ref.read(embyServerListProvider));
    });
  }

  void _layoutMoveBy(int delta) {
    final id = _layoutServerId;
    if (id == null) return;
    final deduped = _dedupServers(ref.read(embyServerListProvider));
    final from = deduped.indexWhere((s) => s.id == id);
    if (from < 0) return;
    final to = from + delta;
    if (to < 0 || to >= deduped.length) return;
    _reorderVisible(from, to);
  }

  /// 退出布局模式：save=true 仅清状态（顺序已随移动持久化）；
  /// save=false（返回键取消）还原进入前的内存与存储顺序。
  void _exitLayoutMode({required bool save}) {
    final backup = _layoutBackup;
    setState(() {
      _layoutServerId = null;
      _layoutBackup = null;
    });
    if (save) {
      if (mounted) showAppToast(context, '位置已保存');
      return;
    }
    if (backup == null) return;
    ref.read(embyServerListProvider.notifier).setList(backup);
    unawaited(
      ref
          .read(embyAuthServiceProvider)
          .saveServerOrder(backup.map((s) => s.id).toList()),
    );
    if (mounted) showAppToast(context, '已取消移动');
  }

  /// 重排可见列表（from → to，to 为目标下标）：更新内存 + 持久化顺序。
  Future<void> _reorderVisible(int from, int to) async {
    closeServerActionPanel();
    final current = ref.read(embyServerListProvider);
    final deduped = _dedupServers(current);
    if (from == to ||
        from < 0 ||
        from >= deduped.length ||
        to < 0 ||
        to >= deduped.length) {
      return;
    }
    final reordered = [...deduped];
    final item = reordered.removeAt(from);
    reordered.insert(to, item);
    // 去重副本（不可见）挪到尾部，不丢内存数据
    final movedIds = reordered.map((s) => s.id).toSet();
    final rest = current.where((s) => !movedIds.contains(s.id)).toList();
    ref.read(embyServerListProvider.notifier).setList([...reordered, ...rest]);
    await ref
        .read(embyAuthServiceProvider)
        .saveServerOrder(reordered.map((s) => s.id).toList());
  }

  /// 点击任意卡片（含激活）：未激活先切换服务器，再跳回首页 tab。
  Future<void> _openServer(EmbyServerConfig server) async {
    final current = ref.read(embyConfigProvider);
    if (current?.id != server.id) {
      ref.read(embyConfigProvider.notifier).setConfig(server);
      await ref.read(embyAuthServiceProvider).saveSelectedServerId(server.id);
      if (mounted) showAppToast(context, '已切换到「${server.label}」');
    }
    if (!mounted) return;
    context.go('/');
  }

  Future<void> _deleteServer(EmbyServerConfig server, bool isActive) async {
    closeServerActionPanel();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定删除 "${server.label}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            // TV 模式：打开即聚焦确认键，遥控器 OK 一步完成删除
            autofocus: ref.read(settingsProvider.select((s) => s.tvMode)),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final authService = ref.read(embyAuthServiceProvider);
    await authService.deleteSession(server.serverId);
    ref.read(embyServerListProvider.notifier).removeServer(server.id);

    if (isActive) {
      final remaining = ref.read(embyServerListProvider);
      if (remaining.isNotEmpty) {
        ref.read(embyConfigProvider.notifier).setConfig(remaining.first);
        await authService.saveSelectedServerId(remaining.first.id);
      } else {
        ref.read(embyConfigProvider.notifier).clear();
        await authService.saveSelectedServerId('');
      }
    }

    if (!mounted) return;
    showAppToast(context, '已删除「${server.label}」');
  }

  void _showEditServerDialog(EmbyServerConfig server) {
    final nameController = TextEditingController(text: server.serverName);
    final urlController = TextEditingController(text: server.serverUrl);
    final usernameController = TextEditingController(text: server.username);
    final passwordController = TextEditingController();
    final tvMode = ref.read(settingsProvider.select((s) => s.tvMode));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑服务器'),
        content: SingleChildScrollView(
          // TV 下输入框整体屏蔽焦点（遥控器无输入法；添加走扫码入口）
          child: tvExcludeEditable(
            tvMode: tvMode,
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => _saveEdit(
              ctx,
              server,
              name: nameController.text.trim(),
              url: urlController.text.trim(),
              username: usernameController.text.trim(),
              password: passwordController.text,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveEdit(
    BuildContext ctx,
    EmbyServerConfig server, {
    required String name,
    required String url,
    required String username,
    required String password,
  }) async {
    if (url.isEmpty || username.isEmpty) return;

    final authService = ref.read(embyAuthServiceProvider);
    final wasActive = ref.read(embyConfigProvider)?.id == server.id;

    try {
      if (password.isNotEmpty) {
        final authResult = await EmbyService().authenticate(
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
        // 非激活服务器编辑后不误切激活
        if (wasActive) {
          ref.read(embyConfigProvider.notifier).setConfig(newConfig);
          await authService.saveSelectedServerId(newConfig.id);
        }
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
      } else {
        final newConfig = server.copyWith(
          serverUrl: url,
          serverName: name,
          username: username,
        );
        ref.read(embyServerListProvider.notifier).updateServer(newConfig);
        if (ref.read(embyConfigProvider)?.id == server.id) {
          ref.read(embyConfigProvider.notifier).setConfig(newConfig);
          await authService.saveSelectedServerId(newConfig.id);
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
    } catch (e) {
      if (ctx.mounted) {
        showAppToast(ctx, '编辑失败: $e');
      }
      return;
    }

    if (ctx.mounted) Navigator.pop(ctx);
  }
}

class _EmptyServerHint extends StatelessWidget {
  const _EmptyServerHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '暂无服务器\n点击右上角 + 添加',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
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
      await ref.read(embySetupServiceProvider).addAndActivate(
            serverUrl: _urlController.text,
            username: _usernameController.text,
            password: _passwordController.text,
            serverName: _nameController.text,
            onServerInfo: (name) {
              if (mounted) setState(() => _serverName = name);
            },
          );

      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
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
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
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
