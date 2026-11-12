import 'dart:async';

import 'package:flutter/material.dart';

/// 687：滚动状态广播——滚动中把列表内玻璃降级为纯色，停止后恢复。
///
/// ## 为什么需要
///
/// 液态玻璃（`liquid_glass_widgets`）的真折射管线每帧都要**重新采样
/// 背景纹理**并做折射计算。列表滚动时每个玻璃项每帧都在重采样 →
/// 中低端设备明显掉帧、拖动发涩（用户反馈「滑动中感觉有抖动」）。
///
/// 但滚动过程中用户**看不清**折射细节（内容在动），此时用纯色降级
/// 视觉上几乎无差，却能省掉绝大部分 GPU 开销。
///
/// ## 用法
///
/// ```dart
/// ScrollGlassScope(
///   child: ListView.builder(
///     itemBuilder: (_, i) => GlassContainer(
///       degradeWhileScrolling: true,   // ← 列表内玻璃项打开
///       child: ...,
///     ),
///   ),
/// )
/// ```
///
/// 滚动开始立刻降级；停止 120ms 后恢复（留一点缓冲，避免惯性滚动
/// 结束时反复切换造成闪烁）。
class ScrollGlassScope extends StatefulWidget {
  const ScrollGlassScope({super.key, required this.child});

  final Widget child;

  /// 停止滚动后多久恢复真折射（毫秒）。
  ///
  /// 【为什么不是 0】惯性滚动（fling）结束后系统还会补几帧；
  /// 立刻恢复会看到「停下→闪一下变玻璃」。
  static const int restoreDelayMs = 120;

  /// 取最近的祖先 [ScrollGlassScope] 状态（无则返回 null）。
  static ScrollGlassScopeState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<ScrollGlassScopeState>();

  @override
  State<ScrollGlassScope> createState() => ScrollGlassScopeState();
}

class ScrollGlassScopeState extends State<ScrollGlassScope> {
  bool _scrolling = false;
  Timer? _restoreTimer;

  /// 当前是否正在滚动（供子级玻璃项查询）。
  bool get scrolling => _scrolling;

  @override
  void dispose() {
    _restoreTimer?.cancel();
    super.dispose();
  }

  bool _onNotification(ScrollNotification notification) {
    // 只在滚动位移时降级（深度 0 = 最外层列表，避免内层横栏误触发）
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _markScrolling();
      _scheduleRestore();
    } else if (notification is ScrollEndNotification) {
      _scheduleRestore();
    }
    return false;
  }

  void _markScrolling() {
    if (_scrolling) return;
    setState(() => _scrolling = true);
  }

  void _scheduleRestore() {
    _restoreTimer?.cancel();
    _restoreTimer = Timer(
      const Duration(milliseconds: ScrollGlassScope.restoreDelayMs),
      () {
        if (!mounted || !_scrolling) return;
        setState(() => _scrolling = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      // 用 InheritedWidget 广播（子级 `GlassContainer` 走 O(1) 查表，
      // 不需要每个 item 都做 ancestor 查找）。
      child: ScrollGlassIndicator(
        scrolling: _scrolling,
        child: widget.child,
      ),
    );
  }
}

/// 687：把「是否滚动中」传给子树（`InheritedWidget`，避免每项都
/// `findAncestorStateOfType` 造成 O(n) 查找）。
class ScrollGlassIndicator extends InheritedWidget {
  const ScrollGlassIndicator({
    super.key,
    required this.scrolling,
    required super.child,
  });

  final bool scrolling;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ScrollGlassIndicator>()
          ?.scrolling ??
      false;

  @override
  bool updateShouldNotify(ScrollGlassIndicator oldWidget) =>
      oldWidget.scrolling != scrolling;
}
