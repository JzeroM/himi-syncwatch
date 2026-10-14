import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/providers/server_stats_provider.dart';
import 'package:himi_syncwatch/widgets/app_toast.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 服务器头像渐变调色板（按 serverId hash 取色，同服务器恒定色）。
const List<List<Color>> _avatarGradients = [
  [Color(0xFF43E97B), Color(0xFF38F9D7)],
  [Color(0xFF4FACFE), Color(0xFF00F2FE)],
  [Color(0xFFFA709A), Color(0xFFFEE140)],
  [Color(0xFFA18CD1), Color(0xFFB8E4FF)],
  [Color(0xFFF6D365), Color(0xFFFDA085)],
  [Color(0xFF89F7FE), Color(0xFF66A6FF)],
];

Color serverAvatarStartColor(String seed) =>
    _avatarGradients[(seed.hashCode & 0x7fffffff) % _avatarGradients.length][0];

Color serverAvatarEndColor(String seed) =>
    _avatarGradients[(seed.hashCode & 0x7fffffff) % _avatarGradients.length][1];

/// 渐变圆形头像（取服务器名首字符）。
class ServerAvatar extends StatelessWidget {
  const ServerAvatar({super.key, required this.label, this.size = 44});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final seed = label.isEmpty ? 'himi' : label;
    final letter = label.isEmpty ? 'H' : label.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [serverAvatarStartColor(seed), serverAvatarEndColor(seed)],
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 延迟徽标：<100ms 绿 / <300ms 橙 / 其余红；null 不渲染。
class LatencyBadge extends StatelessWidget {
  const LatencyBadge({super.key, required this.latencyMs});

  final int? latencyMs;

  @override
  Widget build(BuildContext context) {
    final ms = latencyMs;
    if (ms == null) return const SizedBox.shrink();
    final color = ms < 100
        ? Colors.greenAccent
        : (ms < 300 ? Colors.orangeAccent : Colors.redAccent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.speed, size: 13, color: color),
        const SizedBox(width: 2),
        Text(
          '${ms}ms',
          style:
              TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// 电影 / 剧集计数（无数据不渲染）。
class MovieSeriesCounts extends StatelessWidget {
  const MovieSeriesCounts({super.key, required this.counts});

  final MediaCounts? counts;

  @override
  Widget build(BuildContext context) {
    final c = counts;
    if (c == null) return const SizedBox.shrink();
    const style = TextStyle(fontSize: 12, color: Colors.white70);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.movie_outlined, size: 14, color: Colors.white70),
        const SizedBox(width: 2),
        Text('${c.movies}', style: style),
        const SizedBox(width: 8),
        const Icon(Icons.tv, size: 14, color: Colors.white70),
        const SizedBox(width: 2),
        Text('${c.series}', style: style),
      ],
    );
  }
}

/// 当前展开的操作面板（全局单例：同一时刻只开一个）。
///
/// 卡片重建/删除时通过 [ServerMoreButton.dispose] 关闭，避免悬挂。
OverlayEntry? _activePanelEntry;
VoidCallback? _activePanelClose;

/// 关闭当前展开的服务器操作面板（页面级重排/删除前调用防悬挂）。
void closeServerActionPanel() {
  _activePanelClose?.call();
}

/// 卡片右上角「···」：点击在按钮下方展开不透明操作面板。
class ServerMoreButton extends ConsumerStatefulWidget {
  const ServerMoreButton({
    super.key,
    required this.menuKey,
    required this.onDelete,
    this.onEdit,
  });

  final String menuKey;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  ConsumerState<ServerMoreButton> createState() => _ServerMoreButtonState();
}

class _ServerMoreButtonState extends ConsumerState<ServerMoreButton> {
  OverlayEntry? _entry;

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    closeServerActionPanel();
    _open();
  }

  void _open() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    final onClose = _close;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ServerActionPanel(
        anchorOffset: offset,
        anchorSize: size,
        onEdit: widget.onEdit,
        onDelete: () {
          onClose();
          widget.onDelete();
        },
        onClose: onClose,
      ),
    );
    _entry = entry;
    _activePanelEntry = entry;
    _activePanelClose = onClose;
    overlay.insert(entry);
  }

  void _close() {
    _entry?.remove();
    if (identical(_activePanelEntry, _entry)) {
      _activePanelEntry = null;
      _activePanelClose = null;
    }
    _entry = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TV 模式：D-pad 可聚焦，OK 键展开/收起面板
    return TvFocusable(
      onTap: _toggle,
      scale: 1.0,
      radius: 8,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(Icons.more_vert, size: 20, key: ValueKey(widget.menuKey)),
      ),
    );
  }
}

/// 面板动作：label + 危险标记 + 点击回调。
class _PanelAction {
  const _PanelAction({
    required this.icon,
    required this.label,
    required this.value,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool danger;
}

/// 按钮下方展开的不透明操作面板（实色底 + 淡入下滑动画）。
class _ServerActionPanel extends StatefulWidget {
  const _ServerActionPanel({
    required this.anchorOffset,
    required this.anchorSize,
    required this.onDelete,
    required this.onClose,
    this.onEdit,
  });

  final Offset anchorOffset;
  final Size anchorSize;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  State<_ServerActionPanel> createState() => _ServerActionPanelState();
}

class _ServerActionPanelState extends State<_ServerActionPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    reverseDuration: const Duration(milliseconds: 120),
  );

  static const double _panelWidth = 212;
  static const double _itemHeight = 48;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSelected(_PanelAction action) {
    widget.onClose();
    switch (action.value) {
      case 'edit':
        widget.onEdit?.call();
      case 'delete':
        widget.onDelete();
      default:
        // 占位功能：具体交互后续设计
        showAppToast(context, '功能开发中');
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (widget.onEdit != null)
        const _PanelAction(
            icon: Icons.edit_outlined, label: '编辑', value: 'edit'),
      const _PanelAction(
          icon: Icons.alt_route, label: '切换线路', value: 'switchLine'),
      const _PanelAction(
          icon: Icons.image_outlined, label: '更换图标', value: 'changeIcon'),
      const _PanelAction(
          icon: Icons.bar_chart_outlined, label: '资源统计', value: 'stats'),
      const _PanelAction(
          icon: Icons.tune, label: '资源设置', value: 'resourceSettings'),
      const _PanelAction(
        icon: Icons.delete_outline,
        label: '删除',
        value: 'delete',
        danger: true,
      ),
    ];

    final panelHeight = actions.length * _itemHeight + 12;
    final screen = MediaQuery.sizeOf(context);

    // 右对齐锚点（按钮在卡片右侧），屏幕边缘钳制
    var left = widget.anchorOffset.dx + widget.anchorSize.width - _panelWidth;
    if (left < 8) left = 8;
    if (left + _panelWidth > screen.width - 8) {
      left = screen.width - _panelWidth - 8;
    }
    var top = widget.anchorOffset.dy + widget.anchorSize.height + 4;
    if (top + panelHeight > screen.height - 8) {
      top = widget.anchorOffset.dy - panelHeight - 4;
      if (top < 8) top = 8;
    }

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    return Stack(
      children: [
        // 透明 barrier：点击面板外关闭
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onClose,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.06),
                end: Offset.zero,
              ).animate(curved),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: _panelWidth,
                  decoration: BoxDecoration(
                    // 实色不透明底（区别于玻璃面板）
                    color: const Color(0xFF252830),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x22FFFFFF)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i == actions.length - 1)
                          const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: Color(0x1AFFFFFF),
                          ),
                        _PanelItem(
                          action: actions[i],
                          onTap: () => _onSelected(actions[i]),
                        ),
                      ],
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelItem extends StatelessWidget {
  const _PanelItem({required this.action, required this.onTap});

  final _PanelAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = action.danger ? Colors.redAccent : Colors.white;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(action.icon, size: 20, color: color),
              const SizedBox(width: 12),
              Text(
                action.label,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表视图服务器卡（横向玻璃卡）：头像 + 名称/副标题 + 计数/延迟 + 把手。
class ServerListCard extends StatelessWidget {
  const ServerListCard({
    super.key,
    required this.server,
    required this.isActive,
    required this.stats,
    required this.onTap,
    required this.onDelete,
    this.onEdit,
    this.dragHandle,
  });

  final EmbyServerConfig server;
  final bool isActive;
  final ServerStats? stats;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  /// 拖拽把手（由外层 ReorderableDragStartListener 包装后传入；TV 传 null）。
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    final start = serverAvatarStartColor(server.serverId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(18),
        tint:
            isActive ? start.withValues(alpha: 0.28) : GlassConfig.panelTintOf(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  ServerAvatar(label: server.label),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                server.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.check_circle,
                                  color: Colors.greenAccent, size: 16),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${server.username} · ${server.serverUrl}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 10,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            MovieSeriesCounts(counts: stats?.counts),
                            LatencyBadge(latencyMs: stats?.latencyMs),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ServerMoreButton(
                        menuKey: 'serverMore_${server.id}',
                        onEdit: onEdit,
                        onDelete: onDelete,
                      ),
                      if (dragHandle != null) dragHandle!,
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 网格视图服务器卡（近方形玻璃卡）：
/// 第 1 行 = 头像 + 用户名 + ···；第 2 行 = 服务器名称；底部 = 延迟/计数。
class ServerGridCard extends StatelessWidget {
  const ServerGridCard({
    super.key,
    required this.server,
    required this.isActive,
    required this.stats,
    required this.onTap,
    required this.onDelete,
    this.onEdit,
  });

  final EmbyServerConfig server;
  final bool isActive;
  final ServerStats? stats;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final start = serverAvatarStartColor(server.serverId);
    final end = serverAvatarEndColor(server.serverId);
    return GlassContainer(
      borderRadius: BorderRadius.circular(18),
      tint:
          isActive ? start.withValues(alpha: 0.28) : GlassConfig.panelTintOf(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Stack(
            children: [
              // 背景斜向渐变氛围（激活态更明显）
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        start.withValues(alpha: isActive ? 0.22 : 0.10),
                        end.withValues(alpha: isActive ? 0.10 : 0.03),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 第 1 行：头像 + 用户名 + ···
                    Row(
                      children: [
                        ServerAvatar(label: server.label, size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            server.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        ServerMoreButton(
                          menuKey: 'serverMore_${server.id}',
                          onEdit: onEdit,
                          onDelete: onDelete,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 第 2 行：服务器名称/备注名（激活加粗 + 勾）
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            server.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight:
                                  isActive ? FontWeight.bold : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.check_circle,
                              color: Colors.greenAccent, size: 14),
                        ],
                      ],
                    ),
                    const Spacer(),
                    LatencyBadge(latencyMs: stats?.latencyMs),
                    const SizedBox(height: 6),
                    MovieSeriesCounts(counts: stats?.counts),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
