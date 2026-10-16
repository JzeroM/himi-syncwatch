import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/providers/settings_provider.dart';

/// TV 模式下的顶栏图标按钮：聚焦时显示与 [TvFocusable] 一致的主色焦点环
/// （3px 描边 + 光晕）。
///
/// - TV 模式关闭：透传为普通 [IconButton]，行为与视觉完全不变（零影响）
/// - TV 模式开启：自带 [FocusNode]，方向键可聚焦；遥控器 OK（Enter/Select）
///   触发 [onPressed]；焦点环为圆形（图标按钮 48×48），不做缩放避免顶栏裁切
class TvAppBarIconButton extends ConsumerWidget {
  const TvAppBarIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.iconSize = 24,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double iconSize;

  /// 覆盖图标颜色（如筛选激活时用主色）。为空时用默认/禁用色。
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    if (!tvMode) {
      return IconButton(
        icon: Icon(icon, size: iconSize, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
      );
    }
    return _TvAppBarIconButtonActive(
      icon: icon,
      iconSize: iconSize,
      tooltip: tooltip,
      onPressed: onPressed,
      color: color,
      highlightColor: Theme.of(context).colorScheme.primary,
    );
  }
}

class _TvAppBarIconButtonActive extends StatefulWidget {
  const _TvAppBarIconButtonActive({
    required this.icon,
    required this.iconSize,
    required this.tooltip,
    required this.onPressed,
    required this.color,
    required this.highlightColor,
  });

  final IconData icon;
  final double iconSize;
  final String? tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final Color highlightColor;

  @override
  State<_TvAppBarIconButtonActive> createState() =>
      _TvAppBarIconButtonActiveState();
}

class _TvAppBarIconButtonActiveState extends State<_TvAppBarIconButtonActive> {
  late final FocusNode _node =
      FocusNode(debugLabel: 'TvAppBarIconButton');

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  bool _isConfirm(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.select;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_isConfirm(event.logicalKey)) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (widget.onPressed != null) {
      widget.onPressed!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Focus(
      focusNode: _node,
      onKeyEvent: _onKey,
      child: AnimatedBuilder(
        animation: _node,
        builder: (context, _) {
          final focused = _node.hasFocus;
          // 聚焦 120ms 淡入；失焦零时长瞬时移除（避免新旧焦点框交叉）
          final duration =
              focused ? const Duration(milliseconds: 120) : Duration.zero;
          return Tooltip(
            message: widget.tooltip ?? '',
            child: GestureDetector(
              onTap: widget.onPressed,
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                width: 48,
                height: 48,
                // foregroundDecoration：环画在图标之上且不参与布局
                foregroundDecoration: focused
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.highlightColor,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.highlightColor
                                .withValues(alpha: 0.55),
                            blurRadius: 14,
                            spreadRadius: 1.5,
                          ),
                        ],
                      )
                    : null,
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: widget.iconSize,
                    color: widget.color ?? (enabled ? null : Colors.white38),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 统一的顶栏返回按钮：TV 模式下带焦点环。
class TvBackButton extends StatelessWidget {
  const TvBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TvAppBarIconButton(
      icon: Icons.arrow_back,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
    );
  }
}

/// 顶栏菜单图标按钮：TV 模式下带焦点环；点按在按钮下方弹出菜单。
///
/// 用于替换 AppBar 上的 `PopupMenuButton`，保留原有 key 与菜单行为。
class TvMenuIconButton<T> extends StatefulWidget {
  const TvMenuIconButton({
    super.key,
    required this.icon,
    required this.itemsBuilder,
    required this.onSelected,
    this.tooltip,
    this.iconSize = 24,
  });

  final IconData icon;
  final String? tooltip;
  final double iconSize;
  final List<PopupMenuEntry<T>> Function(BuildContext context) itemsBuilder;
  final ValueChanged<T> onSelected;

  @override
  State<TvMenuIconButton<T>> createState() => _TvMenuIconButtonState<T>();
}

class _TvMenuIconButtonState<T> extends State<TvMenuIconButton<T>> {
  final _anchorKey = GlobalKey();

  Future<void> _open() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight =
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    final selected = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy,
        overlay.size.width - bottomRight.dx,
        overlay.size.height - bottomRight.dy,
      ),
      items: widget.itemsBuilder(context),
    );
    if (selected != null) widget.onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _anchorKey,
      child: TvAppBarIconButton(
        icon: widget.icon,
        tooltip: widget.tooltip,
        iconSize: widget.iconSize,
        onPressed: _open,
      ),
    );
  }
}
