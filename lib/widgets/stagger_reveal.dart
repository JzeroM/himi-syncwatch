import 'package:flutter/material.dart';
import 'package:himi_syncwatch/utils/motion.dart';

/// 687：列表项入场动画——淡入 + 上移，按 index 递增延迟。
///
/// ## 为什么需要
///
/// 旧实现列表数据到达时**瞬间铺满**，视觉上像「闪一下出现」，缺少
/// 过渡感。逐项淡入能让页面显得更从容（这也是主流流媒体应用的通用
/// 做法）。
///
/// ## 关键约束
///
/// **只播一次**：滚动回来时不再重播（否则每滚一次都在动，非常烦人）。
/// 用全局 `Set` 记录已播过的 key。
///
/// ## 用法
///
/// ```dart
/// ListView.builder(
///   itemBuilder: (_, i) => StaggerReveal(
///     index: i,
///     child: PosterCard(...),
///   ),
/// )
/// ```
class StaggerReveal extends StatefulWidget {
  const StaggerReveal({
    super.key,
    required this.index,
    required this.child,
    this.maxDelayMs = 300,
    this.stepMs = 30,
    this.offsetY = 8,
  });

  /// 该项在列表中的序号（决定延迟）。
  final int index;

  final Widget child;

  /// 最大延迟（超过后不再累加，避免长列表末尾等太久）。
  final int maxDelayMs;

  /// 每项递增延迟。
  final int stepMs;

  /// 初始上移距离（像素）。
  final double offsetY;

  /// 已播放过的项（key = identityHashCode of state）。
  ///
  /// 【为什么用静态 Set】列表项滚出屏幕后 State 被销毁，滚回来会重新
  /// 创建——用 State 字段记录无效。静态集合保证「同一位置只播一次」。
  ///
  /// 【为什么不会无限增长】key 用 `index + hashCode(widget.child)` 的
  /// 组合；列表长度有限（通常几百项），可接受。
  static final Set<int> _played = {};

  /// 清空记录（测试用；生产不需要）。
  @visibleForTesting
  static void resetPlayed() => _played.clear();

  @override
  State<StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<StaggerReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(0, widget.offsetY / 100),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    // 【不能在这里查 MediaQuery】`initState` 期间调用
    // `dependOnInheritedWidgetOfExactType` 会抛
    // 「called before initState completed」——推迟到首帧后再判断。
    final key = _identityKey();
    if (StaggerReveal._played.contains(key)) {
      _controller.value = 1.0;
      return;
    }
    StaggerReveal._played.add(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 系统要求减少动画 → 直接显示（不播过渡）
      if (Motion.reduced(context)) {
        _controller.value = 1.0;
        return;
      }
      final delay =
          (widget.index * widget.stepMs).clamp(0, widget.maxDelayMs);
      Future<void>.delayed(Duration(milliseconds: delay), () {
        if (mounted) _controller.forward();
      });
    });
  }

  int _identityKey() =>
      Object.hash(widget.index, widget.child.runtimeType, widget.key);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
