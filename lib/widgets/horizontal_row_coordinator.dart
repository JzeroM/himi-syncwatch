import 'package:flutter/material.dart';
import 'package:himi_syncwatch/utils/motion.dart';

/// 688：横向栏互斥回正协调器。
///
/// ## 需求
///
/// 首页有多条横向海报栏。用户横向滚动了 A 栏后，再去滚 B 栏时，A 栏
/// 自动滑回开头——观感上「同时只有一栏是错位的」，避免整页看起来
/// 到处都是半截内容。
///
/// ## 行为
///
/// - 某一栏**开始被用户滚动** → 其余所有已注册的栏 260ms 平滑回正
/// - 只在 `isScrollingNotifier.value == true`（用户主动滚动/拖动）时
///   激活——程序性 `jumpTo`（如详情页选集定位）不会误触发
/// - 系统开启「减少动画」→ 直接 `jumpTo(0)`（无过渡）
///
/// ## 作用域
///
/// 只在**首页**挂 [HorizontalRowCoordinatorScope]（用户明确要求分类页 /
/// 详情页不做互斥回正——详情页选集行还有自动定位逻辑，回正会打断它）。
class HorizontalRowCoordinator {
  HorizontalRowCoordinator();

  final Set<ScrollController> _controllers = <ScrollController>{};

  /// 当前「活跃」的栏（最近被用户滚动的那一栏）。
  ScrollController? _active;

  /// 回正动画时长（与页面展开动画一致）。
  static const Duration restoreDuration = Duration(milliseconds: 260);

  @visibleForTesting
  int get registeredCount => _controllers.length;

  @visibleForTesting
  ScrollController? get active => _active;

  void register(ScrollController controller) {
    _controllers.add(controller);
  }

  void unregister(ScrollController controller) {
    _controllers.remove(controller);
    if (identical(_active, controller)) _active = null;
  }

  /// 某栏开始滚动 → 其余栏平滑回正。
  ///
  /// [reduced] 为 true 时直接跳回（无过渡动画）。
  void activate(ScrollController controller, {bool reduced = false}) {
    if (identical(_active, controller)) return;
    _active = controller;
    for (final other in _controllers) {
      if (identical(other, controller)) continue;
      if (!other.hasClients) continue;
      if (other.offset <= 0.5) continue;  // 已在开头，不用动
      if (reduced) {
        other.jumpTo(0);
      } else {
        other.animateTo(
          0,
          duration: restoreDuration,
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  /// 清空（测试用）。
  @visibleForTesting
  void clear() {
    _controllers.clear();
    _active = null;
  }
}

/// 688：协调器作用域（首页外层包一次即可）。
class HorizontalRowCoordinatorScope extends InheritedWidget {
  const HorizontalRowCoordinatorScope({
    super.key,
    required this.coordinator,
    required super.child,
  });

  final HorizontalRowCoordinator coordinator;

  static HorizontalRowCoordinator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<HorizontalRowCoordinatorScope>()
      ?.coordinator;

  @override
  bool updateShouldNotify(HorizontalRowCoordinatorScope oldWidget) =>
      oldWidget.coordinator != coordinator;
}

/// 688：把 [HoverScrollRow] 这类横向栏接入互斥回正的 mixin。
///
/// 用法（在 `State` 上混入）：
///
/// ```dart
/// class _MyRowState extends State<MyRow> with HorizontalRowRestore {
///   late final ScrollController _controller = ScrollController();
///
///   @override
///   ScrollController get rowController => _controller;
///
///   @override
///   void initState() {
///     super.initState();
///     initRowRestore();
///   }
/// }
/// ```
mixin HorizontalRowRestore<T extends StatefulWidget> on State<T> {
  /// 子类提供自己的滚动控制器。
  ScrollController get rowController;

  HorizontalRowCoordinator? _coordinator;

  /// 在 `initState` 里调用（此时可以安全查 InheritedWidget）。
  void initRowRestore() {
    _coordinator = HorizontalRowCoordinatorScope.maybeOf(context);
    _coordinator?.register(rowController);
    rowController.addListener(_onRowScroll);
  }

  void _onRowScroll() {
    final c = rowController;
    if (!c.hasClients) return;
    // 只在用户主动滚动时激活（程序性 jumpTo 不触发互斥回正）
    if (!c.position.isScrollingNotifier.value) return;
    _coordinator?.activate(c, reduced: Motion.reduced(context));
  }

  /// 在 `dispose` 里调用。
  void disposeRowRestore() {
    rowController.removeListener(_onRowScroll);
    _coordinator?.unregister(rowController);
    _coordinator = null;
  }
}
