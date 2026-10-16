import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:himi_syncwatch/providers/settings_provider.dart';

/// TV 模式下的可聚焦交互项。
///
/// - TV 模式关闭：透传为普通 GestureDetector，行为与原样一致（零影响）
/// - TV 模式开启：获得 D-pad 焦点（方向键由框架全局遍历）、聚焦高亮
///   （主题色描边 + 微放大）、遥控器 OK 键（Enter/Select）触发 onTap
/// - 可选 [onLongPress]：触屏长按；TV 端为「长按 OK」（按住 ≥ 阈值）。仅
///   在提供 [onLongPress] 时才启用延迟判定，未提供者保持 OK 立即 onTap。
class TvFocusable extends ConsumerWidget {
  const TvFocusable({
    super.key,
    required this.onTap,
    required this.child,
    this.autofocus = false,
    this.focusNode,
    this.radius = 8,
    this.enabled = true,
    this.scale = 1.06,
    this.onLongPress,
    this.onKeyEvent,
  });

  final VoidCallback? onTap;
  final Widget child;
  final bool autofocus;
  final FocusNode? focusNode;
  final double radius;
  final bool enabled;

  /// 自定义按键处理（在默认 OK/长按处理之前调用）。返回 handled 可拦截
  /// 该事件（如让 ⋮ 按左键把焦点交回卡片主体），返回 ignored 则继续默认
  /// 逻辑与框架方向键遍历。
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  /// 聚焦微放大倍率。满宽行（如设置页整行）传 1.0 关闭缩放，
  /// 避免超宽内容按中心放大后两端文字被推出屏幕裁切。
  final double scale;

  /// 长按回调（触屏长按 / TV 长按 OK）。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只订阅 tvMode：整对象 watch 会让设置页任何写入导致屏上全部
    // TvFocusable 同帧重建（详情页多卡片时焦点移动掉帧体感来源之一）。
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    // 桌面鼠标端：上下文菜单改用右键（左键长按禁用，避免与拖动冲突）。
    final desktopMouse = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final effectiveLongPress = desktopMouse ? null : onLongPress;
    final secondaryTap =
        desktopMouse && onLongPress != null ? onLongPress : null;
    if (!tvMode || !enabled) {
      return GestureDetector(
        onTap: onTap,
        onLongPress: effectiveLongPress,
        onSecondaryTap: secondaryTap,
        behavior: HitTestBehavior.opaque,
        child: child,
      );
    }

    final highlightColor = Theme.of(context).colorScheme.primary;

    return _TvFocusableActive(
      onTap: onTap,
      onLongPress: effectiveLongPress,
      onSecondaryTap: secondaryTap,
      autofocus: autofocus,
      focusNode: focusNode,
      radius: radius,
      scale: scale,
      highlightColor: highlightColor,
      onKeyEvent: onKeyEvent,
      child: child,
    );
  }
}

class _TvFocusableActive extends StatefulWidget {
  const _TvFocusableActive({
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    required this.autofocus,
    this.focusNode,
    required this.radius,
    required this.scale,
    required this.highlightColor,
    required this.child,
    this.onKeyEvent,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 桌面鼠标右键触发（取代左键长按，用于上下文菜单）。
  final VoidCallback? onSecondaryTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final double radius;
  final double scale;
  final Color highlightColor;
  final Widget child;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  @override
  State<_TvFocusableActive> createState() => _TvFocusableActiveState();
}

class _TvFocusableActiveState extends State<_TvFocusableActive> {
  /// TV 长按 OK 判定阈值。
  static const Duration _longPressThreshold = Duration(milliseconds: 500);

  late final FocusNode _node =
      widget.focusNode ?? FocusNode(debugLabel: 'TvFocusable');

  Timer? _longPressTimer;
  bool _longPressFired = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    // 仅释放内部创建的节点，外部传入的由持有者管理
    if (widget.focusNode == null) _node.dispose();
    super.dispose();
  }

  bool _isConfirm(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.select;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final custom = widget.onKeyEvent?.call(node, event);
    if (custom == KeyEventResult.handled) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (!_isConfirm(key)) return KeyEventResult.ignored;

    // 无长按：保持原行为（KeyDown 立即 onTap）
    if (widget.onLongPress == null) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (widget.onTap != null) {
        widget.onTap!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
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
    if (event is KeyUpEvent) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
      if (_longPressFired) {
        _longPressFired = false;
        return KeyEventResult.handled; // 长按已处理，不再触发 onTap
      }
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    // KeyRepeatEvent 等：忽略（定时器已在跑）
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
          // 聚焦 120ms 淡入；失焦零时长瞬时移除——否则旧环的 120ms 淡出
          // 与新焦点高亮淡入交叉，同屏出现"两个焦点框"。
          final duration =
              focused ? const Duration(milliseconds: 120) : Duration.zero;
          return GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onSecondaryTap: widget.onSecondaryTap,
            behavior: HitTestBehavior.opaque,
            // AnimatedScale 在最外层：描边与内容一起缩放，环始终完整
            // 包住放大后的内容（环在缩放内层时内容会溢出环外 3%/侧）。
            child: AnimatedScale(
              scale: focused ? widget.scale : 1.0,
              duration: duration,
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                // foregroundDecoration：描边画在 child 之上且不参与布局。
                // 若用 decoration，border 会按 Container 规则挤占 child 约束，
                // 聚焦时高内容子项（如媒体库卡片）被压缩而触发布局溢出。
                foregroundDecoration: focused
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.radius),
                        border:
                            Border.all(color: widget.highlightColor, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color:
                                widget.highlightColor.withValues(alpha: 0.55),
                            blurRadius: 14,
                            spreadRadius: 1.5,
                          ),
                        ],
                      )
                    : null,
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}
