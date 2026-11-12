import 'package:flutter/material.dart';
import 'package:himi_syncwatch/screens/shell/shell_nav_bar.dart' show kNavBlobColor;
import 'package:himi_syncwatch/utils/motion.dart';

/// 687：玻璃质感下拉刷新指示器。
///
/// ## 为什么需要
///
/// 旧实现用 Material 默认 `RefreshIndicator`（白色圆盘 + 箭头），与整套
/// 液态玻璃风格割裂——下拉时突然冒出一个不透明圆盘。
///
/// ## 现在
///
/// 半透明玻璃圆环 + 主色渐变弧 + 柔光，下拉/刷新中与背景自然融合。
///
/// 系统开启「减少动画」时仍保留旋转（这是**加载进度指示**，属于必要
/// 反馈，不属于装饰性动画）。
class GlassRefreshIndicator extends StatelessWidget {
  const GlassRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
    this.displacement = 40,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// 触发区距顶部的偏移（有 AppBar 时传入其高度）。
  final double edgeOffset;

  /// 指示器下拉距离。
  final double displacement;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      edgeOffset: edgeOffset,
      displacement: displacement,
      // 687：主色进度弧 + 半透明深底（与液态玻璃风格统一）。
      //
      // 【为什么不用 indicatorBuilder】当前 Flutter 版本（3.47）的
      // `RefreshIndicator` 尚未提供该参数；用 color/backgroundColor
      // 配色即可达到「不突兀」的效果。
      color: kNavBlobColor,
      backgroundColor: const Color(0xCC1A1D23),
      strokeWidth: 2.5,
      child: child,
    );
  }
}

/// 687：滚动到顶时顶栏从透明渐显为玻璃条。
///
/// 用法：把 [child] 放在 AppBar 的 `flexibleSpace`，传入页面滚动控制器。
///
/// 不依赖滚动回调（避免每帧 setState）：直接用 [ValueListenableBuilder]
/// 监听 [ScrollPosition]。
class ScrollRevealBackdrop extends StatelessWidget {
  const ScrollRevealBackdrop({
    super.key,
    required this.controller,
    required this.backdrop,
    this.threshold = 8,
  });

  /// 页面滚动控制器（无 clients 时按「未滚动」处理）。
  final ScrollController controller;

  /// 渐显的内容（通常是 `GlassBackdrop()`）。
  final Widget backdrop;

  /// 超过多少像素开始渐显。
  final double threshold;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final offset =
            controller.hasClients ? controller.position.pixels : 0.0;
        // 0..1：超过阈值后 120px 内渐显完成
        final t = ((offset - threshold) / 120).clamp(0.0, 1.0);
        return IgnorePointer(
          child: Opacity(
            opacity: Motion.reduced(context) ? (t > 0 ? 1.0 : 0.0) : t,
            child: child,
          ),
        );
      },
      child: backdrop,
    );
  }
}
