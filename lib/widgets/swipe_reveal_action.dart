import 'package:flutter/material.dart';

/// 左滑露出尾部操作控件（如「取消配对」）。
///
/// 从左向右滑动卡片 → 右侧露出红色操作区；松手按 40% 阈值吸附开/合，
/// 点操作区触发 [onAction]，点前景或拖回关闭。无第三方依赖，纯手写，
/// 用于触屏/鼠标端（手机、桌面）。
class SwipeRevealAction extends StatefulWidget {
  const SwipeRevealAction({
    super.key,
    required this.child,
    required this.actionLabel,
    required this.onAction,
    this.actionIcon = Icons.link_off,
    this.actionColor,
    this.actionWidth = 96,
    this.borderRadius = 14,
    this.enabled = true,
  });

  final Widget child;
  final String actionLabel;
  final VoidCallback onAction;
  final IconData actionIcon;
  final Color? actionColor;
  final double actionWidth;
  final double borderRadius;
  final bool enabled;

  @override
  State<SwipeRevealAction> createState() => _SwipeRevealActionState();
}

class _SwipeRevealActionState extends State<SwipeRevealAction>
    with SingleTickerProviderStateMixin {
  static const Duration _snapDuration = Duration(milliseconds: 200);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _snapDuration,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final extents = _controller.value * widget.actionWidth;
    final next = (extents - details.delta.dx).clamp(0.0, widget.actionWidth);
    _controller.value = next / widget.actionWidth;
  }

  void _onDragEnd(DragEndDetails details) {
    _controller.animateTo(
      _controller.value >= 0.4 ? 1.0 : 0.0,
      duration: _snapDuration,
      curve: Curves.easeOut,
    );
  }

  void _close() => _controller.animateTo(
        0.0,
        duration: _snapDuration,
        curve: Curves.easeOut,
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final radius = BorderRadius.circular(widget.borderRadius);
    final actionColor = widget.actionColor ?? Colors.red.shade600;

    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: widget.actionWidth,
            child: Semantics(
              button: true,
              label: widget.actionLabel,
              child: Tooltip(
                message: widget.actionLabel,
                child: GestureDetector(
                  onTap: widget.onAction,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    color: actionColor,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.actionIcon,
                            color: Colors.white, size: 20),
                        const SizedBox(height: 2),
                        Text(
                          widget.actionLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            // builder 内联 GestureDetector：随动画值重建，保证「开启态点前景
            // 关闭、关闭态放行内层按钮」的 onTap 判定始终最新（不能用 build
            // 期一次性捕获的 open 快照，否则拖动后 onTap 仍是关闭态的空值）。
            builder: (context, child) => Transform.translate(
              offset: Offset(-_controller.value * widget.actionWidth, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _controller.value > 0 ? _close : null,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: child,
              ),
            ),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
