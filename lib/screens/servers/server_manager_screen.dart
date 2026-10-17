import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/server_avatar_provider.dart';
import 'package:himi_syncwatch/providers/server_stats_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tv_sync_provider.dart';
import 'package:himi_syncwatch/screens/settings/qr_config_screen.dart';
import 'package:himi_syncwatch/screens/servers/route_manager_sheet.dart';
import 'package:himi_syncwatch/screens/shell/shell_back_intercept_provider.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_visibility.dart';
import 'package:himi_syncwatch/models/server_route.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/emby_error.dart';
import 'package:himi_syncwatch/services/lan_config/emby_setup_service.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/server_card.dart';
import 'package:himi_syncwatch/widgets/resource_stats_sheet.dart';
import 'package:himi_syncwatch/widgets/server_service_settings_sheet.dart';
import 'package:himi_syncwatch/widgets/tv/tv_app_bar_icon_button.dart';
import 'package:himi_syncwatch/widgets/tv_device_sheet.dart';

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

  /// 卡片「同步到 TV」图标可见性：仅手机/桌面端、开关开启、已配对、且该
  /// TV 当前在局域网被发现（在线）时显示；已配对但离线时隐藏。
  @visibleForTesting
  static bool shouldShowSyncToTvIcon({
    required bool tvMode,
    required bool tvSyncEnabled,
    required String? pairedDeviceId,
    required Set<String> onlineDeviceIds,
  }) {
    if (tvMode || !tvSyncEnabled) return false;
    final id = pairedDeviceId;
    if (id == null || id.isEmpty) return false;
    return onlineDeviceIds.contains(id);
  }

  @override
  ConsumerState<ServerManagerScreen> createState() =>
      _ServerManagerScreenState();
}

class _ServerManagerScreenState extends ConsumerState<ServerManagerScreen> {
  bool _showAddServerForm = false;

  /// 编辑目标（非空 = 内联展开编辑表单，复用添加表单）。
  EmbyServerConfig? _editingServer;

  /// TV 布局模式：正在移动的服务器 id（null = 非布局模式）。
  String? _layoutServerId;

  /// 布局模式进入时的顺序快照（返回键取消时还原）。
  List<EmbyServerConfig>? _layoutBackup;

  /// 挂载时捕获的容器（dispose 中 ref.read 非法，用它清壳层拦截器）。
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    // ⋮ 操作面板开合 → 同步壳层返回拦截（面板优先于表单/布局消费返回）
    serverActionPanelOpen.addListener(_syncBackIntercept);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStats();
      _syncTvDiscovery();
    });
  }

  /// 按当前设置启停局域网 TV 发现：仅手机/桌面端且「同步到 TV」开启时运行，
  /// 用于判定已配对 TV 是否在线（在线才显示卡片电视图标）。
  void _syncTvDiscovery() {
    if (!mounted) return;
    final tvMode = ref.read(settingsProvider.select((s) => s.tvMode));
    final enabled = ref.read(settingsProvider.select((s) => s.tvSyncEnabled));
    final notifier = ref.read(tvDiscoveryProvider.notifier);
    final shouldRun = !tvMode && enabled;
    if (shouldRun) {
      if (!notifier.isRunning) unawaited(notifier.start());
    } else {
      if (notifier.isRunning) unawaited(notifier.stop());
    }
  }

  @override
  void dispose() {
    serverActionPanelOpen.removeListener(_syncBackIntercept);
    _container.read(shellBackInterceptProvider.notifier).clear();
    super.dispose();
  }

  /// 表单/布局/⋮ 面板变化后同步壳层返回拦截：任一激活则注册，否则清空。
  ///
  /// 用 initState 捕获的 [_container]（而非 `ref`）读写 provider：本方法可能
  /// 被全局 [serverActionPanelOpen] 通知在卡片 dispose 期间同步回调，此时
  /// 本 State 的 Element 已 deactivate，`ref.read` 会抛「deactivated widget's
  /// ancestor」。
  void _syncBackIntercept() {
    if (!mounted) return;
    final notifier = _container.read(shellBackInterceptProvider.notifier);
    final active = _layoutServerId != null ||
        _showAddServerForm ||
        _editingServer != null ||
        serverActionPanelOpen.value;
    if (active) {
      notifier.register(_onBackIntercept);
    } else {
      notifier.clear();
    }
  }

  /// 壳层返回拦截：优先关 ⋮ 操作面板，其次关布局模式，再次关表单；均不活跃时放行。
  bool _onBackIntercept() {
    if (serverActionPanelOpen.value) {
      closeServerActionPanel();
      return true;
    }
    if (_layoutServerId != null) {
      _exitLayoutMode(save: false);
      return true;
    }
    if (_showAddServerForm || _editingServer != null) {
      setState(() {
        _showAddServerForm = false;
        _editingServer = null;
      });
      _setFormVisible(false);
      return true;
    }
    return false;
  }

  /// 展开/收起表单时同步底部导航显隐（表单展开算"非首页"状态）。
  void _setFormVisible(bool visible) {
    final nav = ref.read(shellNavVisibilityProvider.notifier);
    if (visible) {
      nav.hideFor(kShellNavHideForm);
    } else {
      nav.showFor(kShellNavHideForm);
    }
  }

  /// 编辑入口（v1.1.243）：非 TV 内联编辑表单；TV 走手机扫码配置。
  void _onEditServer(EmbyServerConfig server) {
    final tvMode = ref.read(settingsProvider.select((s) => s.tvMode));
    if (tvMode) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const QrConfigScreen(mode: 'emby'),
        ),
      );
      return;
    }
    setState(() {
      _editingServer = server;
      _showAddServerForm = false;
    });
    _setFormVisible(true);
    _syncBackIntercept();
  }

  /// 关闭添加/编辑表单（Windows 表头关闭按钮）：丢弃未保存内容回列表。
  void _closeServerForm() {
    if (_editingServer == null && !_showAddServerForm) return;
    setState(() {
      _showAddServerForm = false;
      _editingServer = null;
    });
    _setFormVisible(false);
    _syncBackIntercept();
  }

  /// 切 tab 离开本页（epoch bump）：丢弃未保存的添加/编辑表单与布局模式。
  void _resetUnsavedOperations() {
    final hadForm = _showAddServerForm || _editingServer != null;
    final hadLayout = _layoutServerId != null;
    if (hadForm || hadLayout) {
      setState(() {
        _showAddServerForm = false;
        _editingServer = null;
        _layoutServerId = null;
        _layoutBackup = null;
      });
      if (hadForm) _setFormVisible(false);
    }
    _syncBackIntercept();
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
    // 同步到 TV 开关（设置-通用）：关闭时隐藏电视机控件
    final tvSyncEnabled =
        ref.watch(settingsProvider.select((s) => s.tvSyncEnabled));
    // 在线 TV 判定：发现服务实时维护（仅手机/桌面且开关开启时运行）
    final onlineTvIds = ref.watch(tvDiscoveryProvider).keys.toSet();

    // 设置变化 → 启停发现服务（在线判定依赖它）
    ref.listen(
      settingsProvider.select((s) => !s.tvMode && s.tvSyncEnabled),
      (previous, next) => _syncTvDiscovery(),
    );

    // 切 tab 离开本页 → 丢弃未保存的添加/编辑表单（v1.1.243）
    ref.listen(
      shellBranchEpochProvider.select((m) => m[2] ?? 0),
      (previous, next) {
        if (previous != next) _resetUnsavedOperations();
      },
    );

    final dedupedServers = _dedupServers(servers);
    final layoutId = _layoutServerId;
    final editing = _editingServer;

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
          // 布局模式下第二行按钮不参与焦点：避免方向键移动卡片时焦点逃逸到顶栏
          actions: <Widget>[
            TvAppBarIconButton(
              key: const ValueKey('serverViewToggle'),
              icon: viewMode == 'list' ? Icons.view_module : Icons.view_list,
              tooltip: viewMode == 'list' ? '网格视图' : '列表视图',
              onPressed: () => ref.read(settingsProvider.notifier).update(
                    serverViewMode: viewMode == 'list' ? 'grid' : 'list',
                  ),
            ),
            TvAppBarIconButton(
              key: const ValueKey('serverStatsRefresh'),
              icon: Icons.refresh,
              tooltip: '刷新延迟与计数',
              onPressed: _loadStats,
            ),
            // TV 设备（局域网发现/配对/推送服务器配置；仅手机/桌面端，
            // 且设置-通用「同步到 TV」开启时显示）
            if (!tvMode && tvSyncEnabled)
              TvAppBarIconButton(
                key: const ValueKey('tvDeviceButton'),
                icon: Icons.tv,
                tooltip: 'TV 设备',
                onPressed: () => showTvDeviceSheet(context),
              ),
            if (tvMode)
              TvAppBarIconButton(
                icon: Icons.qr_code_scanner,
                tooltip: '手机扫码配置',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const QrConfigScreen(mode: 'emby'),
                  ),
                ),
              ),
            // TV 不提供手动添加表单（遥控器无输入法）：走上方扫码入口
            if (!tvMode)
              TvAppBarIconButton(
                icon: _showAddServerForm ? Icons.close : Icons.add,
                tooltip: _showAddServerForm ? '取消添加' : '添加服务器',
                onPressed: () {
                  final next = !_showAddServerForm;
                  setState(() {
                    _showAddServerForm = next;
                    if (next) _editingServer = null;
                  });
                  _setFormVisible(next);
                  _syncBackIntercept();
                },
              ),
          ]
              .map((w) => _layoutServerId != null ? ExcludeFocus(child: w) : w)
              .toList(),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: GlassConfig.topInsetOf(context)),
            if ((editing != null || _showAddServerForm) && !tvMode)
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                      bottom: GlassConfig.bottomReserveOf(context)),
                  child: _AddServerForm(
                    key: ValueKey('serverForm_${editing?.id ?? 'add'}'),
                    editServer: editing,
                    onCancel: _closeServerForm,
                    onSuccess: () {
                      if (!mounted) return;
                      final isEdit = editing != null;
                      setState(() {
                        _showAddServerForm = false;
                        _editingServer = null;
                      });
                      _setFormVisible(false);
                      _syncBackIntercept();
                      showAppToast(context, isEdit ? '服务器已更新' : '服务器已添加');
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
                        ? _buildGrid(
                            dedupedServers, currentConfig, statsMap, onlineTvIds)
                        : _buildList(
                            dedupedServers, currentConfig, statsMap, onlineTvIds),
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
    Set<String> onlineTvIds,
  ) {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    final tvSyncEnabled =
        ref.watch(settingsProvider.select((s) => s.tvSyncEnabled));
    final pairedTv = ref.watch(pairedTvProvider);
    final avatarVersions = ref.watch(serverAvatarVersionProvider);
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
            isFirst: index == 0,
            cardBuilder:
                (moreButtonNode, onMoreButtonBack, onMoreButtonForward) =>
                    ServerListCard(
              server: server,
              isActive: isActive,
              stats: statsMap[server.id],
              onTap: () => _openServer(server),
              onEdit: () => _onEditServer(server),
              onSwitchLine: () => showRouteManagerSheet(context, ref, server),
              onStats: () => showResourceStatsSheet(context, server),
              onServiceSettings: () => showServiceSettingsSheet(context, server),
              onDelete: () => _deleteServer(server, isActive),
              // 已配对且该 TV 在线时显示「同步到 TV」图标（离线则隐藏）
              onSyncToTv: ServerManagerScreen.shouldShowSyncToTvIcon(
                tvMode: tvMode,
                tvSyncEnabled: tvSyncEnabled,
                pairedDeviceId: pairedTv?.deviceId,
                onlineDeviceIds: onlineTvIds,
              )
                  ? () => pushServerToTv(context, ref, server)
                  : null,
              // TV 模式：隐藏拖拽把手（布局模式用方向键移动）
              dragHandle: tvMode
                  ? null
                  : ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle, size: 20),
                    ),
              tvMode: tvMode,
              moreButtonNode: moreButtonNode,
              onMoreButtonBack: onMoreButtonBack,
              onMoreButtonForward: onMoreButtonForward,
              avatarVersion: avatarVersions[server.id],
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
    Set<String> onlineTvIds,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = (width / 220).floor().clamp(2, 4);
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    final tvSyncEnabled =
        ref.watch(settingsProvider.select((s) => s.tvSyncEnabled));
    final pairedTv = ref.watch(pairedTvProvider);
    final avatarVersions = ref.watch(serverAvatarVersionProvider);
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
        childAspectRatio: 1.25,
      ),
      itemCount: dedupedServers.length,
      // TV 布局移动重排时按 key 搬运元素（而非按新下标重建），保留卡片
      // 的 State/FocusNode，焦点不回落外层 scope 被抢到顶栏。
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        const prefix = 'serverGridTile_';
        if (!key.value.startsWith(prefix)) return null;
        final id = key.value.substring(prefix.length);
        final idx = dedupedServers.indexWhere((s) => s.id == id);
        return idx < 0 ? null : idx;
      },
      itemBuilder: (context, index) {
        final server = dedupedServers[index];
        final isActive = currentConfig?.id == server.id;
        final card = KeyedSubtree(
          key: ValueKey('serverGridTile_${server.id}'),
          child: _wrapCard(
            server: server,
            isGrid: true,
            crossAxisCount: crossAxisCount,
            isFirst: index == 0,
            cardBuilder:
                (moreButtonNode, onMoreButtonBack, onMoreButtonForward) =>
                    ServerGridCard(
              server: server,
              isActive: isActive,
              stats: statsMap[server.id],
              onTap: () => _openServer(server),
              onEdit: () => _onEditServer(server),
              onSwitchLine: () => showRouteManagerSheet(context, ref, server),
              onStats: () => showResourceStatsSheet(context, server),
              onServiceSettings: () => showServiceSettingsSheet(context, server),
              onDelete: () => _deleteServer(server, isActive),
              // 已配对且该 TV 在线时显示「同步到 TV」图标（离线则隐藏）
              onSyncToTv: ServerManagerScreen.shouldShowSyncToTvIcon(
                tvMode: tvMode,
                tvSyncEnabled: tvSyncEnabled,
                pairedDeviceId: pairedTv?.deviceId,
                onlineDeviceIds: onlineTvIds,
              )
                  ? () => pushServerToTv(context, ref, server)
                  : null,
              tvMode: tvMode,
              moreButtonNode: moreButtonNode,
              onMoreButtonBack: onMoreButtonBack,
              onMoreButtonForward: onMoreButtonForward,
              avatarVersion: avatarVersions[server.id],
            ),
          ),
        );
        // TV 模式：禁用长按拖拽（用布局模式方向键移动）
        if (tvMode) return card;
        // 拖拽反馈尺寸必须与网格单元一致（aspect 1.25），否则拖拽中
        // 卡片会变回旧版高瘦形状（v1.1.247 修复反馈硬编码 180×200）
        final cellWidth =
            (width - 12 - 12 - (crossAxisCount - 1) * 10) / crossAxisCount;
        final cellHeight = cellWidth / 1.25;
        return LongPressDraggable<int>(
          data: index,
          maxSimultaneousDrags: 1,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child:
                  SizedBox(width: cellWidth, height: cellHeight, child: card),
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
  /// - 常规态：_TvCardFocus 焦点节点覆盖整卡（OK 打开、长按进布局、整卡
  ///   焦点环）；右侧 ⋮ 为卡内独立焦点节点，页面显式连线「主体 → ⋮」
  ///   （→ 方向键）/「⋮ → 主体」（← 方向键），其余方向键走框架遍历。
  /// - 布局模式选中卡：Focus 拦截方向键移动 + OK 保存退出，外加高亮描边
  /// - 布局模式其他卡：忽略指针 + 降透明 + 排除焦点
  /// 非 TV 模式原样返回（[cardBuilder] 收到两个 null）。
  Widget _wrapCard({
    required EmbyServerConfig server,
    required bool isGrid,
    required int crossAxisCount,
    required Widget Function(FocusNode? moreButtonNode,
            VoidCallback? onMoreButtonBack, VoidCallback? onMoreButtonForward)
        cardBuilder,
    bool isFirst = false,
  }) {
    if (!ref.watch(settingsProvider.select((s) => s.tvMode))) {
      return cardBuilder(null, null, null);
    }

    final layoutId = _layoutServerId;
    if (layoutId == server.id) {
      // 复用 _TvCardFocus（同类型 widget → 焦点节点跨模式切换保留），
      // 避免裸 Focus 替换时旧节点被销毁、焦点瞬时回落到外层 scope，
      // 进而被全局 TvScopeEnterIntent 抢到顶栏（v1.1.251 修复）。
      // 布局键处理走 onLayoutKey；描边由 _layoutDecorate 画，关焦点环。
      return _TvCardFocus(
        showFocusRing: false,
        onTap: () {},
        onLayoutKey: (event) => _handleLayoutKey(
          event,
          isGrid: isGrid,
          crossAxisCount: crossAxisCount,
        ),
        childBuilder: (_, __, ___) => _layoutDecorate(
          ExcludeFocus(child: cardBuilder(null, null, null)),
        ),
      );
    }
    if (layoutId != null) {
      return ExcludeFocus(
        child: IgnorePointer(
          child: Opacity(opacity: 0.4, child: cardBuilder(null, null, null)),
        ),
      );
    }
    return _TvCardFocus(
      autofocus: isFirst,
      onTap: () => _openServer(server),
      onLongPress: () => _enterLayoutMode(server),
      childBuilder: (moreButtonNode, onMoreButtonBack, onMoreButtonForward) =>
          cardBuilder(moreButtonNode, onMoreButtonBack, onMoreButtonForward),
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
      // 仅 KeyDown 短按退出；长按进布局模式时用户仍按住 OK，后续
      // KeyRepeat 若也退出会立刻又退出，且焦点回落期间顶栏视图切换
      // 按钮被反复激活导致网格/列表闪切（v1.1.247 修复）。
      if (event is KeyDownEvent) {
        _exitLayoutMode(save: true);
      }
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
    _syncBackIntercept();
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
    _syncBackIntercept();
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

  /// 点击任意卡片（含激活）：未激活先切换服务器。
  /// TV 模式切换后留在本页（遥控器管理服务器，跳首页用返回键）；
  /// 手机/桌面切换后跳回首页 tab。
  Future<void> _openServer(EmbyServerConfig server) async {
    final current = ref.read(embyConfigProvider);
    if (current?.id != server.id) {
      ref.read(embyConfigProvider.notifier).setConfig(server);
      await ref.read(embyAuthServiceProvider).saveSelectedServerId(server.id);
      if (mounted) showAppToast(context, '已切换到「${server.label}」');
    }
    if (!mounted) return;
    final tvMode = ref.read(settingsProvider.select((s) => s.tvMode));
    if (tvMode) return;
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

/// TV 卡片焦点包装：纯 Focus（OK 键 + 焦点环），无 GestureDetector。
///
/// 触摸交给卡内 InkWell 处理；OK 键（Enter/Select）短按 = onTap、
/// 长按 ≥500ms = onLongPress。不用 TvFocusable 是因为它自带
/// GestureDetector，与卡内 ⋮ 按钮的 GestureDetector 在手势竞技场
/// 竞争时，聚焦态下外层会吞掉手势导致 ⋮ 失效（v1.1.246）。
class _TvCardFocus extends StatefulWidget {
  const _TvCardFocus({
    required this.childBuilder,
    required this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.onLayoutKey,
    this.showFocusRing = true,
  });

  /// 构建卡片，并把「⋮ 焦点节点」与「⋮ 回焦主体 / 前进相邻卡回调」交给
  /// 卡片，用于显式连线「主体 → ⋮」。焦点节点覆盖整卡，环画在整卡外围。
  final Widget Function(FocusNode moreButtonNode, VoidCallback onMoreButtonBack,
      VoidCallback onMoreButtonForward) childBuilder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;

  /// 布局模式键处理器（非空 = 该卡处于布局模式，按键全权委托它，
  /// 不再触发 tap/长按）。复用同一 State 以保留焦点节点。
  final KeyEventResult Function(KeyEvent event)? onLayoutKey;

  /// 是否绘制焦点环（布局模式由琥珀描边代替，置 false 避免叠加）。
  final bool showFocusRing;

  @override
  State<_TvCardFocus> createState() => _TvCardFocusState();
}

class _TvCardFocusState extends State<_TvCardFocus> {
  static const Duration _longPressThreshold = Duration(milliseconds: 500);

  final FocusNode _node = FocusNode(debugLabel: 'TvCardFocus');

  /// ⋮ 的焦点节点：由本 State 持有并注入卡内，实现「主体 → ⋮」方向键连线。
  final FocusNode _moreNode = FocusNode(debugLabel: 'serverMoreBtn');
  Timer? _longPressTimer;
  bool _longPressFired = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _node.dispose();
    _moreNode.dispose();
    super.dispose();
  }

  bool _isConfirm(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.select;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // 布局模式：按键全权交给布局处理器，绝不触发 tap/长按。焦点节点
    // 跨进入/退出布局模式保留，故长按 OK 的 KeyRepeat 始终落在此节点，
    // 不会冒泡到全局 TvScopeEnterIntent 被抢到顶栏。
    final layoutHandler = widget.onLayoutKey;
    if (layoutHandler != null) return layoutHandler(event);

    // 主体 → ⋮：⋮ 与主体为独立焦点节点（无几何包含关系），框架遍历不会
    // 从主体进入 ⋮，故显式连线。仅拦截右方向键 KeyDown，其余方向键仍走
    // 框架遍历（如网格中左右切换卡片、上下移动）。
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowRight &&
        _moreNode.canRequestFocus) {
      _moreNode.requestFocus();
      return KeyEventResult.handled;
    }

    final key = event.logicalKey;
    if (!_isConfirm(key)) return KeyEventResult.ignored;

    if (widget.onLongPress == null) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      widget.onTap();
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent) {
      _longPressFired = false;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(_longPressThreshold, () {
        if (!mounted) return;
        _longPressFired = true;
        widget.onLongPress?.call();
      });
      return KeyEventResult.handled;
    }
    // 长按中（或松开前）的 KeyRepeat 必须吞掉：冒泡会触发全局
    // TvScopeEnterIntent 把焦点抢到壳层顶栏，顶栏视图切换按钮被
    // 反复激活导致网格/列表视图不停闪切（v1.1.247 修复）。
    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _longPressTimer?.cancel();
      // 仅在本节点见过对应 KeyDown 时才算完整一次点击；焦点中途
      // 转移后落进来的孤立 KeyUp 直接吞掉，避免误触发 onTap 打开
      // 服务器（v1.1.247）。
      final hadDown = _longPressTimer != null;
      _longPressTimer = null;
      if (_longPressFired) {
        _longPressFired = false;
        return KeyEventResult.handled;
      }
      if (hadDown) widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// ⋮ 回焦主体：⋮ 与主体为独立节点，框架遍历无法从 ⋮ 回到主体，故显式。
  void _focusBody() => _node.requestFocus();

  /// ⋮ 前进相邻卡：以整卡几何为基准做方向遍历，落到右侧相邻卡主体。
  void _focusNext() => _node.focusInDirection(TraversalDirection.right);

  @override
  Widget build(BuildContext context) {
    final highlightColor = Theme.of(context).colorScheme.primary;
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: AnimatedBuilder(
        animation: _node,
        builder: (context, _) {
          // hasPrimaryFocus：焦点落入卡内 ⋮ 时卡环必须熄灭，否则与 ⋮ 的
          // 焦点环同屏出现两个环。
          final focused = _node.hasPrimaryFocus;
          final duration =
              focused ? const Duration(milliseconds: 120) : Duration.zero;
          return AnimatedScale(
            scale: focused ? 1.03 : 1.0,
            duration: duration,
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              foregroundDecoration: (focused && widget.showFocusRing)
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: highlightColor, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: highlightColor.withValues(alpha: 0.55),
                          blurRadius: 14,
                          spreadRadius: 1.5,
                        ),
                      ],
                    )
                  : null,
              child: widget.childBuilder(_moreNode, _focusBody, _focusNext),
            ),
          );
        },
      ),
    );
  }
}

class _AddServerForm extends ConsumerStatefulWidget {
  final VoidCallback onSuccess;

  /// 关闭/取消表单（Windows 端表头关闭按钮）。为空则不显示关闭按钮。
  final VoidCallback? onCancel;

  /// 非空 = 编辑模式：预填该服务器字段，保存走编辑逻辑（保留线路）。
  final EmbyServerConfig? editServer;

  const _AddServerForm({
    super.key,
    required this.onSuccess,
    this.onCancel,
    this.editServer,
  });

  @override
  ConsumerState<_AddServerForm> createState() => _AddServerFormState();
}

class _AddServerFormState extends ConsumerState<_AddServerForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _pathController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  final _remarkController = TextEditingController();
  late bool _useHttps;
  bool _isLoading = false;
  String? _error;
  String? _serverName;

  bool get _isEdit => widget.editServer != null;

  @override
  void initState() {
    super.initState();
    final server = widget.editServer;
    _nameController = TextEditingController(text: server?.serverName ?? '');
    _usernameController = TextEditingController(text: server?.username ?? '');
    if (server != null) {
      final parsed = parseServerUrl(server.serverUrl);
      _hostController =
          TextEditingController(text: parsed?.host ?? server.serverUrl);
      _pathController = TextEditingController(text: parsed?.path ?? '');
      _portController = TextEditingController(
          text: (parsed?.port.isNotEmpty ?? false) ? parsed!.port : '8096');
      _useHttps =
          parsed?.useHttps ?? server.serverUrl.trim().startsWith('https://');
    } else {
      _hostController = TextEditingController();
      _pathController = TextEditingController();
      _portController = TextEditingController(text: '8096');
      _useHttps = false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _pathController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = buildServerUrl(
      host: _hostController.text,
      port: _portController.text,
      path: _pathController.text,
      useHttps: _useHttps,
    );
    if (url == null) {
      setState(() => _error = '请输入有效的服务器地址（ip 或域名）');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isEdit) {
        await _saveEdit(url);
      } else {
        // 备注名优先，其次备注信息（备注字段）
        final name = _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : _remarkController.text.trim();
        await ref.read(embySetupServiceProvider).addAndActivate(
              serverUrl: url,
              username: _usernameController.text,
              password: _passwordController.text,
              serverName: name.isEmpty ? null : name,
              onServerInfo: (srvName) {
                if (mounted) setState(() => _serverName = srvName);
              },
            );
      }

      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyEmbyError(e);
        _isLoading = false;
      });
    }
  }

  /// 编辑保存（复用原 _saveEdit 流程）：仅填新密码时重新 authenticate；
  /// 修复原实现 saveSession 不传 routes 导致备用线路被清空的问题。
  Future<void> _saveEdit(String url) async {
    final server = widget.editServer!;
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty) throw EmbySetupException('用户名不能为空');

    final authService = ref.read(embyAuthServiceProvider);
    final wasActive = ref.read(embyConfigProvider)?.id == server.id;

    EmbyServerConfig newConfig;
    if (password.isNotEmpty) {
      final authResult = await EmbyService().authenticate(
        serverUrl: url,
        username: username,
        password: password,
        deviceId: server.id,
      );
      final newServerId = authResult['ServerId'] ?? server.serverId;
      newConfig = server.copyWith(
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
    } else {
      newConfig = server.copyWith(
        serverUrl: url,
        serverName: name,
        username: username,
      );
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
      userId: newConfig.userId ?? '',
      username: username,
      accessToken: newConfig.accessToken ?? '',
      id: newConfig.id,
      // 保留备用线路（v1.1.243：原实现丢线路的 bug 回归）
      routes: newConfig.routes.map((r) => r.toJson()).toList(),
      activeRouteUrl: newConfig.activeRouteUrl,
      autoFailover: newConfig.autoFailover,
      strmDirectPlay: newConfig.strmDirectPlay,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Windows 端：编辑/新增表单是整页内联替换（非路由），无返回按钮，
    // 故在表头补一个关闭按钮；其他平台保持原样（手机走系统返回）。
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    final showHeader = _isEdit || (isWindows && widget.onCancel != null);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(
                      _isEdit ? '编辑服务器' : '添加服务器',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    if (isWindows && widget.onCancel != null)
                      IconButton(
                        key: const Key('serverFormClose'),
                        icon: const Icon(Icons.close),
                        tooltip: '关闭',
                        onPressed: widget.onCancel,
                      ),
                  ],
                ),
              ),
            if (_serverName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '已连接: $_serverName',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            _formField(
              label: '资源名称',
              controller: _nameController,
              hintText: _isEdit ? '资源名称' : '请输入资源名称（可选）',
            ),
            _formField(
              label: '服务器地址',
              controller: _hostController,
              hintText: '例如：192.168.1.100',
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _formField(
                    label: '路径（可选）',
                    controller: _pathController,
                    hintText: 'Path（可选）',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _formField(
                    label: '端口',
                    controller: _portController,
                  ),
                ),
              ],
            ),
            _switchRow(
              label: '使用 HTTPS',
              value: _useHttps,
              onChanged: (v) => setState(() => _useHttps = v),
            ),
            _formField(
              label: '用户名',
              controller: _usernameController,
              hintText: '输入用户名',
            ),
            _formField(
              label: _isEdit ? '新密码（留空保持不变）' : '密码（可选）',
              controller: _passwordController,
              hintText: _isEdit ? '输入新密码（可选）' : '输入密码（可选）',
              obscure: true,
            ),
            if (!_isEdit)
              _formField(
                label: '备注',
                controller: _remarkController,
                hintText: '输入备注信息（可选）',
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
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEdit ? '保存' : '连接并登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: obscure,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: hintText,
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
