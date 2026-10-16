import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/providers/server_stats_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
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

/// 操作面板展开状态（全局单例）。服务器页监听它注册壳层返回拦截，
/// 使返回键优先关闭面板而非弹回首页。
final ValueNotifier<bool> serverActionPanelOpen = ValueNotifier<bool>(false);

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
    this.onSwitchLine,
    this.onStats,
    this.focusNode,
    this.onBack,
    this.onForward,
  });

  final String menuKey;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  /// 切换线路：打开线路管理弹层。
  final VoidCallback? onSwitchLine;

  /// 资源统计：打开资源统计底部面板。
  final VoidCallback? onStats;

  /// TV 模式下由页面注入的焦点节点（用于「主体 → ⋮」方向键连线与
  /// 面板关闭回焦）；为空时按钮自建节点。
  final FocusNode? focusNode;

  /// ⋮ 聚焦时按左方向键：把焦点交回卡片主体。
  final VoidCallback? onBack;

  /// ⋮ 聚焦时按右方向键：把焦点交到相邻卡片主体（⋮ 是卡内最深节点，
  /// 框架遍历无法从 ⋮ 跨出到相邻卡，故显式连线）。
  final VoidCallback? onForward;

  @override
  ConsumerState<ServerMoreButton> createState() => _ServerMoreButtonState();
}

class _ServerMoreButtonState extends ConsumerState<ServerMoreButton> {
  OverlayEntry? _entry;

  /// TV 面板当前选中项索引。箭头键只改这个值让面板高亮移动，
  /// **不移动焦点**——焦点一旦离开卡片子树，卡片会被框架重建，
  /// ⋮ 的 State 被销毁 → 面板随即被关（v1.1.246 实测陷阱）。
  final ValueNotifier<int> _panelIndex = ValueNotifier<int>(0);

  /// 持有按钮焦点节点：面板关闭后回焦，TV 遥控器不丢焦点位置。
  /// 页面注入时用注入节点（用于「主体 → ⋮」连线），不重复创建。
  late final FocusNode _buttonNode =
      widget.focusNode ?? FocusNode(debugLabel: 'serverMoreBtn');

  /// 面板动作项数（编辑项视是否可编辑而定）。
  int get _actionCount => widget.onEdit != null ? 6 : 5;

  /// 面板动作表（与 [_ServerActionPanel] 渲染顺序一致）。
  List<_PanelAction> _buildActions() => [
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

  bool _isConfirm(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.select;

  /// 激活面板第 [index] 项（OK 键 / 指针点击共用）。
  void _activate(int index) {
    final actions = _buildActions();
    if (index < 0 || index >= actions.length) return;
    final action = actions[index];
    _close();
    switch (action.value) {
      case 'edit':
        widget.onEdit?.call();
      case 'switchLine':
        if (widget.onSwitchLine != null) {
          widget.onSwitchLine!();
        } else {
          showAppToast(context, '功能开发中');
        }
      case 'stats':
        if (widget.onStats != null) {
          widget.onStats!();
        } else {
          showAppToast(context, '功能开发中');
        }
      case 'delete':
        widget.onDelete();
      default:
        // 占位功能：具体交互后续设计
        showAppToast(context, '功能开发中');
    }
  }

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

    _panelIndex.value = 0;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ServerActionPanel(
        anchorOffset: offset,
        anchorSize: size,
        actions: _buildActions(),
        selection: _panelIndex,
        onActivate: _activate,
        onClose: onClose,
        tvMode: ref.read(settingsProvider.select((s) => s.tvMode)),
      ),
    );
    _entry = entry;
    _activePanelEntry = entry;
    _activePanelClose = onClose;
    serverActionPanelOpen.value = true;
    overlay.insert(entry);
  }

  /// 关闭面板。[refocus] 为 true 时把焦点交回 ⋮ 按钮（避免焦点悬空）；
  /// dispose 路径必须传 false——此时节点可能已被上层重新挂载，若仍请求
  /// 聚焦会把焦点错误地拉到 ⋮（表现为进入页面即聚焦 ⋮）。
  void _close({bool refocus = true}) {
    _entry?.remove();
    if (identical(_activePanelEntry, _entry)) {
      _activePanelEntry = null;
      _activePanelClose = null;
      serverActionPanelOpen.value = false;
    }
    _entry = null;
    // TV：面板关闭后回焦 ⋮ 按钮，避免焦点悬空
    if (refocus && mounted) _buttonNode.requestFocus();
  }

  @override
  void dispose() {
    _close(refocus: false);
    _panelIndex.dispose();
    // 仅释放自建节点，注入的由页面持有
    if (widget.focusNode == null) _buttonNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    final icon = SizedBox(
      width: 40,
      height: 40,
      child: Icon(Icons.more_vert, size: 20, key: ValueKey(widget.menuKey)),
    );
    if (!tvMode) {
      // 非 TV：原 GestureDetector 行为
      return TvFocusable(
        onTap: _toggle,
        scale: 1.0,
        radius: 8,
        child: icon,
      );
    }
    // TV：TvFocusable 提供 OK 键 + 焦点环。
    // 卡片外层已改用 _TvCardFocus（无 GestureDetector），⋮ 的
    // GestureDetector 在手势竞技场中应胜过卡内 InkWell（v1.1.246）。
    return TvFocusable(
      focusNode: _buttonNode,
      onTap: _toggle,
      scale: 1.0,
      radius: 8,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        // 面板已展开：方向键闭环移动面板高亮（焦点留在 ⋮，不逃逸、不重建卡片）。
        if (_entry != null) {
          if (key == LogicalKeyboardKey.arrowDown) {
            if (_panelIndex.value < _actionCount - 1) _panelIndex.value++;
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            if (_panelIndex.value > 0) _panelIndex.value--;
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft) {
            _close();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            _close();
            widget.onForward?.call();
            return KeyEventResult.handled;
          }
          if (_isConfirm(key)) {
            _activate(_panelIndex.value);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        // 面板未展开：
        // 左方向键：交回卡片主体焦点（⋮ 与主体为独立节点，无几何包含关系，
        // 框架遍历无法从 ⋮ 回到主体，故显式连线）。
        if (key == LogicalKeyboardKey.arrowLeft) {
          if (widget.onBack == null) return KeyEventResult.ignored;
          widget.onBack!();
          return KeyEventResult.handled;
        }
        // 右方向键：交到相邻卡片主体（同上，显式连线）。
        if (key == LogicalKeyboardKey.arrowRight) {
          if (widget.onForward == null) return KeyEventResult.ignored;
          widget.onForward!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ExcludeFocus(child: icon),
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

/// 按钮下方展开的玻璃操作面板（94% 不透明着色膜 + 淡入下滑动画）。
///
/// TV 焦点策略：面板项**不自持焦点**。焦点始终留在触发它的 ⋮ 按钮上，
/// 由按钮用 [selection] 驱动面板项高亮，OK 键经 [onActivate] 激活当前项。
/// 原因：把焦点移出卡片子树会导致卡片被框架重建、⋮ State 销毁、面板被关
/// （v1.1.246 实测陷阱）。故此方案方向键闭环且不触碰焦点。
class _ServerActionPanel extends StatefulWidget {
  const _ServerActionPanel({
    required this.anchorOffset,
    required this.anchorSize,
    required this.actions,
    required this.selection,
    required this.onActivate,
    required this.onClose,
    this.tvMode = false,
  });

  final Offset anchorOffset;
  final Size anchorSize;
  final List<_PanelAction> actions;

  /// 当前选中项索引（TV 高亮来源；由 ⋮ 按钮持有）。
  final ValueListenable<int> selection;

  /// 指针点击某项时激活该索引。
  final ValueChanged<int> onActivate;

  final VoidCallback onClose;
  final bool tvMode;

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

  @override
  Widget build(BuildContext context) {
    final actions = widget.actions;
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

    final panel = SizedBox(
      width: _panelWidth,
      child: GlassContainer(
        borderRadius: BorderRadius.circular(16),
        tint: GlassConfig.popupTint,
        fallbackColor: GlassConfig.popupFallback,
        showShadow: false,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          type: MaterialType.transparency,
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
                ValueListenableBuilder<int>(
                  valueListenable: widget.selection,
                  builder: (_, selectedIndex, __) => _PanelItem(
                    action: actions[i],
                    selected: widget.tvMode && selectedIndex == i,
                    onTap: () => widget.onActivate(i),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
              child: panel,
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelItem extends StatelessWidget {
  const _PanelItem({
    required this.action,
    required this.onTap,
    this.selected = false,
  });

  final _PanelAction action;
  final VoidCallback onTap;

  /// TV 选中态：左侧主题色竖条 + 淡背景高亮。
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = action.danger ? Colors.redAccent : Colors.white;
    final primary = Theme.of(context).colorScheme.primary;
    final row = SizedBox(
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
    );
    // 面板项不参与焦点遍历（焦点留在 ⋮ 按钮，由按钮驱动高亮/激活）。
    return ExcludeFocus(
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: selected
              ? BoxDecoration(
                  color: primary.withValues(alpha: 0.16),
                  border: Border(
                    left: BorderSide(color: primary, width: 3),
                  ),
                )
              : const BoxDecoration(
                  border: Border(left: BorderSide(color: Colors.transparent, width: 3)),
                ),
          child: row,
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
    this.onSwitchLine,
    this.onStats,
    this.onSyncToTv,
    this.dragHandle,
    this.tvMode = false,
    this.moreButtonNode,
    this.onMoreButtonBack,
    this.onMoreButtonForward,
  });

  final EmbyServerConfig server;
  final bool isActive;
  final ServerStats? stats;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSwitchLine;
  final VoidCallback? onStats;

  /// 同步本服务器到已配对 TV（null=未配对，不显示电视图标）。
  final VoidCallback? onSyncToTv;

  /// 拖拽把手（由外层 ReorderableDragStartListener 包装后传入；TV 传 null）。
  final Widget? dragHandle;

  /// TV 模式：外层 InkWell 不再请求焦点，⋮ 为唯一内层可聚焦节点，
  /// 由页面显式连线「主体 → ⋮」。
  final bool tvMode;

  /// TV 模式注入给 ⋮ 的焦点节点（用于「主体 → ⋮」连线与面板回焦）。
  final FocusNode? moreButtonNode;

  /// ⋮ 按左键时回调（交回卡片主体焦点）。
  final VoidCallback? onMoreButtonBack;

  /// ⋮ 按右键时回调（交到相邻卡片主体）。
  final VoidCallback? onMoreButtonForward;

  @override
  Widget build(BuildContext context) {
    final content = Row(
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
                        fontWeight:
                            isActive ? FontWeight.bold : FontWeight.w600,
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
                style: const TextStyle(fontSize: 12, color: Colors.white54),
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
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(18),
        // 激活态不着色（v1.1.246）：仅靠绿勾 + 加粗标识，玻璃保持中性
        tint: GlassConfig.panelTintOf(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            canRequestFocus: !tvMode,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // 主体区域（TV 下外层 _TvCardFocus 持有焦点节点；⋮ 为
                  // 独立焦点节点，方向键右可移入、左可移回）。
                  Expanded(child: content),
                  const SizedBox(width: 6),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 同步到已配对 TV（配对后显示，点击推本服务器配置）
                      if (onSyncToTv != null)
                        InkWell(
                          key: const ValueKey('syncToTvButton'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: onSyncToTv,
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(Icons.cast_connected,
                                size: 20, color: Colors.white54),
                          ),
                        ),
                      ServerMoreButton(
                        menuKey: 'serverMore_${server.id}',
                        onEdit: onEdit,
                        onSwitchLine: onSwitchLine,
                        onStats: onStats,
                        onDelete: onDelete,
                        focusNode: moreButtonNode,
                        onBack: onMoreButtonBack,
                        onForward: onMoreButtonForward,
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
///
/// TV 模式下 ··· 从第 1 行移到卡片右侧垂直居中，成为与主体同级、矩形互不
/// 包含的独立焦点项，方向键可自然在「主体 ↔ ···」间移动（手机端布局不变）。
class ServerGridCard extends StatelessWidget {
  const ServerGridCard({
    super.key,
    required this.server,
    required this.isActive,
    required this.stats,
    required this.onTap,
    required this.onDelete,
    this.onEdit,
    this.onSwitchLine,
    this.onStats,
    this.onSyncToTv,
    this.tvMode = false,
    this.moreButtonNode,
    this.onMoreButtonBack,
    this.onMoreButtonForward,
  });

  final EmbyServerConfig server;
  final bool isActive;
  final ServerStats? stats;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSwitchLine;
  final VoidCallback? onStats;

  /// 同步本服务器到已配对 TV（null=未配对，不显示电视图标）。
  final VoidCallback? onSyncToTv;

  /// TV 模式：··· 移到右侧居中，成为独立焦点项，由页面显式连线。
  final bool tvMode;

  /// TV 模式注入给 ⋮ 的焦点节点。
  final FocusNode? moreButtonNode;

  /// ⋮ 按左键时回调（交回卡片主体焦点）。
  final VoidCallback? onMoreButtonBack;

  /// ⋮ 按右键时回调（交到相邻卡片主体）。
  final VoidCallback? onMoreButtonForward;

  Widget _gradient(Color start, Color end) => Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                start.withValues(alpha: 0.10),
                end.withValues(alpha: 0.03),
              ],
            ),
          ),
        ),
      );

  Widget _syncIcon() => InkWell(
        key: const ValueKey('syncToTvButton'),
        borderRadius: BorderRadius.circular(8),
        onTap: onSyncToTv,
        child: const SizedBox(
          width: 40,
          height: 40,
          child:
              Icon(Icons.cast_connected, size: 18, color: Colors.white54),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final start = serverAvatarStartColor(server.serverId);
    final end = serverAvatarEndColor(server.serverId);

    final moreButton = ServerMoreButton(
      menuKey: 'serverMore_${server.id}',
      onEdit: onEdit,
      onSwitchLine: onSwitchLine,
      onStats: onStats,
      onDelete: onDelete,
      focusNode: moreButtonNode,
      onBack: onMoreButtonBack,
      onForward: onMoreButtonForward,
    );

    Widget bodyColumn({required bool moreInTopRow}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第 1 行：头像 + 用户名 (+ 同步图标 / ···，手机端)
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
                if (moreInTopRow && onSyncToTv != null) _syncIcon(),
                if (moreInTopRow) moreButton,
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
        );

    if (tvMode) {
      // TV：主体（左，注入焦点）+ 右侧垂直居中的 ···（独立焦点）
      final body = bodyColumn(moreInTopRow: false);
      return GlassContainer(
        borderRadius: BorderRadius.circular(18),
        tint: GlassConfig.panelTintOf(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            canRequestFocus: false,
            onTap: onTap,
            child: Stack(
              children: [
                _gradient(start, end),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: body),
                      const SizedBox(width: 4),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [moreButton],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 手机端：原布局（··· 在第 1 行右上角）
    return GlassContainer(
      borderRadius: BorderRadius.circular(18),
      // 激活态不着色（v1.1.246）：仅靠绿勾 + 加粗标识，玻璃保持中性
      tint: GlassConfig.panelTintOf(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Stack(
            children: [
              // 背景斜向渐变氛围（激活/未激活同强度，不再放大激活态）
              _gradient(start, end),
              Padding(
                padding: const EdgeInsets.all(14),
                child: bodyColumn(moreInTopRow: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
