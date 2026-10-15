import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/server_route.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/settings/qr_config_screen.dart';
import 'package:himi_syncwatch/services/server_route_service.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 打开线路管理底部弹层（玻璃，跟随液态玻璃 UI 开关）。
Future<void> showRouteManagerSheet(
  BuildContext context,
  WidgetRef ref,
  EmbyServerConfig server,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => RouteManagerSheet(
      serverId: server.id,
      // TV 下输入框屏蔽焦点（添加线路走遥控器不可用；保留查看/切换/测速）
      tvMode: ref.read(settingsProvider.select((s) => s.tvMode)),
    ),
  );
}

/// 线路管理 sheet：自动故障转移开关 + 测速/重试/添加 + 可拖拽线路列表。
class RouteManagerSheet extends ConsumerStatefulWidget {
  const RouteManagerSheet({super.key, required this.serverId, this.tvMode = false});

  final String serverId;
  final bool tvMode;

  @override
  ConsumerState<RouteManagerSheet> createState() => _RouteManagerSheetState();
}

class _RouteManagerSheetState extends ConsumerState<RouteManagerSheet> {
  /// 每条线路（含主线路，url→latency）最近一次测速结果。
  final Map<String, int?> _latencies = {};
  bool _measuring = false;

  EmbyServerConfig? get _server {
    final list = ref.watch(embyServerListProvider);
    for (final s in list) {
      if (s.id == widget.serverId) return s;
    }
    return ref.watch(embyConfigProvider);
  }

  Future<void> _measureAll(EmbyServerConfig server) async {
    if (_measuring) return;
    setState(() => _measuring = true);
    final svc = ref.read(serverRouteServiceProvider);
    final probe = await svc.measureAll(server);
    if (!mounted) return;
    setState(() {
      _latencies
        ..clear()
        ..[probe.main.url] = probe.main.latencyMs;
      for (final r in probe.routes) {
        _latencies[r.url] = r.latencyMs;
      }
      _measuring = false;
    });
  }

  Future<void> _measureOne(String url) async {
    final svc = ref.read(serverRouteServiceProvider);
    final latency = await svc.measureUrl(url);
    if (!mounted) return;
    setState(() => _latencies[url] = latency);
  }

  Future<void> _retry(EmbyServerConfig server) async {
    await _measureAll(server);
    if (server.autoFailover && mounted) {
      final svc = ref.read(serverRouteServiceProvider);
      final switched = await svc.failoverIfNeeded(server);
      if (!mounted) return;
      if (switched != null) {
        showAppToast(context, '当前线路不可达，已自动切换');
      }
    }
  }

  Future<void> _openAddRoute(EmbyServerConfig server) async {
    // TV：遥控器无输入法 → 手机扫码添加（v1.1.243）
    if (widget.tvMode) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QrConfigScreen(mode: 'route', serverId: server.id),
        ),
      );
      return;
    }
    final result = await showModalBottomSheet<ServerRoute>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => AddRouteSheet(
        server: server,
        tvMode: widget.tvMode,
      ),
    );
    if (result != null && mounted) {
      showAppToast(context, '已添加「${result.name}」');
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    if (server == null) return const SizedBox.shrink();
    final activeUrl = server.effectiveUrl;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          tint: GlassConfig.popupTint,
          fallbackColor: GlassConfig.popupFallback,
          showShadow: false,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 拖拽把手
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 头部：头像 + 名称/副标题 + 关闭
              Row(
                children: [
                  _SheetAvatar(label: server.label),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          '线路管理',
                          style: TextStyle(fontSize: 13, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('routeSheetClose'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 自动故障转移
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('自动故障转移',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500)),
                    ),
                    Switch(
                      key: const Key('autoFailoverSwitch'),
                      value: server.autoFailover,
                      onChanged: (v) => ref
                          .read(serverRouteServiceProvider)
                          .setAutoFailover(server, v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 操作行：测速 / 重试 / + 添加线路
              Row(
                children: [
                  _ActionButton(
                    key: const Key('measureAllButton'),
                    icon: Icons.speed,
                    label: '测速',
                    onTap: _measuring ? null : () => _measureAll(server),
                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    key: const Key('retryButton'),
                    icon: Icons.refresh,
                    label: '重试',
                    onTap: _measuring ? null : () => _retry(server),
                  ),
                  const Spacer(),
                  _ActionButton(
                    key: const Key('addRouteButton'),
                    icon: Icons.add,
                    label: '添加线路',
                    // TV 走扫码添加（v1.1.243），非 TV 展开表单
                    onTap: () => _openAddRoute(server),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 线路列表（主线路固定首位 + 备用可拖拽）
              Flexible(
                child: ReorderableListView(
                  key: const Key('routeList'),
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) =>
                      ref.read(serverRouteServiceProvider).reorderRoutes(
                            oldIndex - 1,
                            newIndex - 1,
                          ),
                  children: [
                    // 主线路（不可拖、不可删），占 index 0
                    _RouteTile(
                      key: const Key('routeTile_main'),
                      index: 0,
                      draggable: false,
                      selected: activeUrl == server.serverUrl,
                      title: '主线路',
                      subtitle: '${server.serverUrl}',
                      latencyMs: _latencies[server.serverUrl],
                      measuring: _measuring,
                      onTap: () => ref
                          .read(serverRouteServiceProvider)
                          .switchRoute(server, null),
                      onMeasure: () => _measureOne(server.serverUrl),
                    ),
                    for (var i = 0; i < server.routes.length; i++)
                      _buildRouteTile(server, i, activeUrl),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteTile(
    EmbyServerConfig server,
    int index,
    String activeUrl,
  ) {
    final route = server.routes[index];
    return _RouteTile(
      key: ValueKey('routeTile_${route.id}'),
      index: index + 1,
      draggable: !widget.tvMode,
      selected: activeUrl == route.url,
      title: route.name,
      subtitle: '${route.isReverseProxy ? '反代' : '直连'} · ${route.url}',
      latencyMs: _latencies[route.url],
      measuring: _measuring,
      onTap: () =>
          ref.read(serverRouteServiceProvider).switchRoute(server, route.url),
      onMeasure: () => _measureOne(route.url),
      onRemove: widget.tvMode
          ? null
          : () => _removeRoute(server, index),
    );
  }

  Future<void> _removeRoute(EmbyServerConfig server, int index) async {
    final route = server.routes[index];
    final routes = [...server.routes]..removeAt(index);
    final clearsActive = server.activeRouteUrl == route.url;
    await ref.read(serverRouteServiceProvider).persist(
          server.copyWith(
            routes: routes,
            clearActiveRoute: clearsActive,
          ),
        );
    if (mounted) showAppToast(context, '已删除「${route.name}」');
  }
}

/// 线路列表项：拖拽手柄 + 选中点 + 名称/副标题 + 延迟 + 测速/删除。
class _RouteTile extends StatelessWidget {
  const _RouteTile({
    super.key,
    required this.index,
    required this.draggable,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.latencyMs,
    required this.measuring,
    required this.onTap,
    required this.onMeasure,
    this.onRemove,
  });

  /// 在 ReorderableListView 中的位置（主线路 0，备用从 1 起）。
  final int index;

  final bool draggable;
  final bool selected;
  final String title;
  final String subtitle;
  final int? latencyMs;
  final bool measuring;
  final VoidCallback onTap;
  final VoidCallback onMeasure;
  final VoidCallback? onRemove;

  Color? get _latencyColor {
    final ms = latencyMs;
    if (ms == null) return null;
    if (ms < 300) return Colors.greenAccent;
    if (ms < 800) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: selected ? 0.10 : 0.05),
        borderRadius: BorderRadius.circular(14),
        border: selected
            ? Border.all(color: Colors.greenAccent.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          if (draggable)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.drag_indicator, size: 18, color: Colors.white38),
            ),
          Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: selected ? Colors.greenAccent : Colors.white38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          if (latencyMs != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '$latencyMs ms',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _latencyColor,
                ),
              ),
            ),
          IconButton(
            onPressed: measuring ? null : onMeasure,
            icon: const Icon(Icons.speed, size: 18, color: Colors.white54),
            tooltip: '测速',
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Colors.white38),
              tooltip: '删除',
            ),
        ],
      ),
    );

    final content = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: tile,
      ),
    );

    if (!draggable) return content;
    return ReorderableDelayedDragStartListener(
      index: index,
      child: content,
    );
  }
}

/// 头部圆形头像（取名首字符）。
class _SheetAvatar extends StatelessWidget {
  const _SheetAvatar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFF43E97B), Color(0xFF38F9D7)],
        ),
      ),
      child: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }
}

/// 操作行小按钮（测速/重试/添加线路）。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap ?? () {},
      scale: 1.0,
      radius: 10,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: onTap == null ? Colors.white24 : Colors.white70),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: onTap == null ? Colors.white24 : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 添加线路弹层（图5）：名称/地址/端口/路径 + HTTPS/反代开关 + 保存。
class AddRouteSheet extends ConsumerStatefulWidget {
  const AddRouteSheet({super.key, required this.server, this.tvMode = false});

  final EmbyServerConfig server;
  final bool tvMode;

  @override
  ConsumerState<AddRouteSheet> createState() => _AddRouteSheetState();
}

class _AddRouteSheetState extends ConsumerState<AddRouteSheet> {
  late final TextEditingController _nameController;
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '8096');
  final _pathController = TextEditingController();
  bool _useHttps = true;
  bool _isReverseProxy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: ServerRoute.defaultName(widget.server.routes),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入资源名称');
      return;
    }
    final route = await ref.read(serverRouteServiceProvider).addRoute(
          widget.server,
          name: name,
          url: url,
          isReverseProxy: _isReverseProxy,
        );
    if (!mounted) return;
    Navigator.pop(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          tint: GlassConfig.popupTint,
          fallbackColor: GlassConfig.popupFallback,
          showShadow: false,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SheetAvatar(label: widget.server.label),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '添加线路',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.server.label,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sheetField(
                  label: '资源名称',
                  controller: _nameController,
                ),
                _sheetField(
                  label: '服务器地址',
                  controller: _hostController,
                  hintText: 'ip 或域名，如 192.168.1.100',
                ),
                _sheetField(
                  label: '端口',
                  controller: _portController,
                ),
                _sheetField(
                  label: '路径（可选）',
                  controller: _pathController,
                ),
                const SizedBox(height: 8),
                const Text('配置',
                    style: TextStyle(fontSize: 13, color: Colors.white54)),
                const SizedBox(height: 4),
                _switchRow(
                  label: '使用 HTTPS',
                  value: _useHttps,
                  onChanged: (v) => setState(() => _useHttps = v),
                ),
                _switchRow(
                  label: '作为反代使用',
                  subtitle: '将此线路作为主线路的反向代理',
                  value: _isReverseProxy,
                  onChanged: (v) => setState(() => _isReverseProxy = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    key: const Key('saveRouteButton'),
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetField({
    required String label,
    required TextEditingController controller,
    String? hintText,
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
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white38)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
