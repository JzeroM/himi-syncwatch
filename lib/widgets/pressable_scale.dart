import 'package:flutter/material.dart';
import 'package:himi_syncwatch/utils/motion.dart';

/// 687：通用按压反馈——按下缩到 0.97，松开弹回。
///
/// ## 为什么需要
///
/// 旧实现非 TV 模式下 `TvFocusable` 直接返回 `GestureDetector`，
/// **手机端点卡片毫无视觉反馈**——用户不确定是否点中（真机体感
/// 「点了没反应」）。
///
/// TV 模式本来有焦点缩放，但那是遥控器场景；触屏需要的是「按下即
/// 反馈、松开即回弹」。
///
/// ## 行为
///
/// - 按下：`scale 1.0 → 0.97`（90ms，`easeOut`）
/// - 松开/取消：`0.97 → 1.0`（140ms，`easeOut` 带回弹感）
/// - 系统开启「减少动画」：不缩放（直接无过渡）
///
/// ## 用法
///
/// ```dart
/// PressableScale(
///   onTap: () => ...,
///   child: PosterCard(...),
/// )
/// ```
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.pressedScale = 0.97,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 桌面右键（上下文菜单）。
  final VoidCallback? onSecondaryTap;

  /// 按下时的缩放比例（默认 0.97）。
  final double pressedScale;

  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (!widget.enabled) return;
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    // 系统要求减少动画时不缩放（保留点击功能）
    final scale = _pressed && !Motion.reduced(context)
        ? widget.pressedScale
        : 1.0;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onSecondaryTap: widget.onSecondaryTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onLongPressEnd: (_) => _setPressed(false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        // 按下快、回弹慢（更自然）
        duration: Motion.of(
          context,
          Duration(milliseconds: _pressed ? 90 : 140),
        ),
        curve: Curves.easeOut,
        scale: scale,
        child: widget.child,
      ),
    );
  }
}
