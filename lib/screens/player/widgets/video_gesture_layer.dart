import 'package:flutter/material.dart';

/// 视频层手势容器：点屏显隐控制条、双击播放暂停、横拖 seek、纵拖音量/亮度。
///
/// 只包视频内容本身（作为 Stack 底层），**不包**控制条与字幕/音轨/倍速
/// 浮层面板——若放到 Scaffold body 层成为这些浮层的祖先，拖动起点在
/// 浮层内时祖先的 drag recognizer 会先进手势竞技场抢走拖动，浮层
/// ListView 滚不动（且误触音量/亮度）。
///
/// 纯参数 widget（不依赖 provider/状态），便于脱离 `mdk.Player` 单测
/// 「视频区拖动触发回调 / 上层浮层拖动不触发且回调隔离」。
class VideoGestureLayer extends StatelessWidget {
  const VideoGestureLayer({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  final Widget child;

  /// 点视频区（点屏显隐控制条 / 关菜单）。
  final VoidCallback? onTap;

  /// 双击播放暂停；null = 锁定中解除绑定。
  final VoidCallback? onDoubleTap;

  /// 横拖 seek；null = 锁定中解除绑定。
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;

  /// 纵拖音量/亮度；null = Windows/锁定中不启用。
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onHorizontalDragUpdate: onHorizontalDragUpdate,
      onHorizontalDragEnd: onHorizontalDragEnd,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}
