import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/providers/settings_provider.dart';

/// TV 模式下的可聚焦交互项。
///
/// - TV 模式关闭：透传为普通 GestureDetector，行为与原样一致（零影响）
/// - TV 模式开启：获得 D-pad 焦点（方向键由框架全局遍历）、聚焦高亮
///   （主题色描边 + 微放大）、遥控器 OK 键（Enter/Select）触发 onTap
class TvFocusable extends ConsumerWidget {
  const TvFocusable({
    super.key,
    required this.onTap,
    required this.child,
    this.autofocus = false,
    this.focusNode,
    this.radius = 8,
    this.enabled = true,
  });

  final VoidCallback? onTap;
  final Widget child;
  final bool autofocus;
  final FocusNode? focusNode;
  final double radius;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvMode = ref.watch(settingsProvider).tvMode;
    if (!tvMode || !enabled) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: child,
      );
    }

    final highlightColor = Theme.of(context).colorScheme.primary;

    return _TvFocusableActive(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      radius: radius,
      highlightColor: highlightColor,
      child: child,
    );
  }
}

class _TvFocusableActive extends StatefulWidget {
  const _TvFocusableActive({
    required this.onTap,
    required this.autofocus,
    this.focusNode,
    required this.radius,
    required this.highlightColor,
    required this.child,
  });

  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final double radius;
  final Color highlightColor;
  final Widget child;

  @override
  State<_TvFocusableActive> createState() => _TvFocusableActiveState();
}

class _TvFocusableActiveState extends State<_TvFocusableActive> {
  late final FocusNode _node =
      widget.focusNode ?? FocusNode(debugLabel: 'TvFocusable');

  @override
  void dispose() {
    // 仅释放内部创建的节点，外部传入的由持有者管理
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      if (widget.onTap != null) {
        widget.onTap!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // 方向键放行：交给框架全局 Shortcuts 做焦点遍历
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: AnimatedBuilder(
        animation: _node,
        builder: (context, _) {
          final focused = _node.hasFocus;
          return GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              decoration: focused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.radius),
                      border:
                          Border.all(color: widget.highlightColor, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: widget.highlightColor.withValues(alpha: 0.55),
                          blurRadius: 14,
                          spreadRadius: 1.5,
                        ),
                      ],
                    )
                  : null,
              child: AnimatedScale(
                scale: focused ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}
