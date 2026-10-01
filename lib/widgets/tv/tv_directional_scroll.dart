import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV 遥控器方向键意图：焦点移动 + 滚动贯通。
///
/// 默认框架行为中方向键只做焦点移动（[DirectionalFocusAction]），而
/// `ListView.builder` 等懒构建列表视口外没有焦点节点，焦点走到边缘后
/// 方向键失效、无法继续翻屏。本意图在焦点移动失败时滚动最近的同轴
/// [Scrollable]（视口 60%），再重试焦点移动，直到焦点落位或到达边界。
class TvDirectionalIntent extends Intent {
  const TvDirectionalIntent(this.direction);

  final TraversalDirection direction;
}

/// 作用域落焦意图：焦点停在 [FocusScopeNode]（冷启动无焦点 / Dialog 刚
/// 打开未落焦）时按 OK（Enter/Select）把焦点落进该作用域第一个可聚焦项。
///
/// 仅在焦点为作用域节点时启用；焦点在普通控件上时返回禁用，事件继续
/// 沿默认链处理（按钮激活等行为不受影响）。
class TvScopeEnterIntent extends Intent {
  const TvScopeEnterIntent();
}

class TvDirectionalAction extends ContextAction<TvDirectionalIntent> {
  TvDirectionalAction();

  /// 单次滚动步长：视口的 60%。
  static const double _stepFactor = 0.6;

  /// 至多「滚→移」循环次数（跨多屏未构建区域时连续滚几段）。
  static const int _maxAttempts = 4;

  static bool _isTextInput(BuildContext context) =>
      context.findAncestorWidgetOfExactType<EditableText>() != null;

  @override
  bool isEnabled(TvDirectionalIntent intent, [BuildContext? context]) {
    if (context == null) return false;
    // 文本编辑中：方向键让位给光标/选择移动（DefaultTextEditingShortcuts）
    if (_isTextInput(context)) return false;
    return true;
  }

  @override
  Object? invoke(TvDirectionalIntent intent, [BuildContext? context]) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return null;

    if (node.focusInDirection(intent.direction)) return null;

    // 跨祖先 scope 兜底：Flutter inDirection 只在 nearestScope 内找候选，
    // 而 GoRouter 嵌套 Navigator 的页面 ModalScope 不含壳层顶栏——内容区
    // 到达 scope 边界（首/末项）时上/下键找不到顶栏 → 失败 → 落到滚动
    // 边界吞键，焦点再也回不到顶栏。仅纵向（问题场景），横向保持原滚动。
    if (intent.direction == TraversalDirection.up ||
        intent.direction == TraversalDirection.down) {
      final cross = _findCrossScope(node, intent.direction);
      if (cross != null) {
        cross.requestFocus();
        return null;
      }
    }

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      if (node.focusInDirection(intent.direction)) return null;
      if (node.context == null) return null;
      final scrollable = _matchingScrollable(node.context, intent.direction);
      if (scrollable == null) return null;
      final pos = scrollable.position;
      final delta = _stepFor(intent.direction, pos.viewportDimension);
      final target =
          (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (target == pos.pixels) return null; // 已到边界：吞键
      pos.jumpTo(target);
    }
    return null;
  }

  /// 沿 nearestScope 的祖先 scope 链收集候选，复刻 Flutter 方向带算法挑
  /// 最近节点（跨页面 ModalScope 与壳层之间的查找）。
  static FocusNode? _findCrossScope(
    FocusNode node,
    TraversalDirection direction,
  ) {
    final target = node.rect;
    final seen = <FocusNode>{node};
    final candidates = <FocusNode>[];
    FocusNode? scope = node.nearestScope;
    while (scope != null) {
      if (scope is FocusScopeNode) {
        for (final n in scope.traversalDescendants) {
          if (seen.add(n) && n.canRequestFocus && n.context != null) {
            candidates.add(n);
          }
        }
      }
      scope = scope.parent;
    }

    bool inDirection(FocusNode n) {
      if (n.rect == target) return false;
      switch (direction) {
        case TraversalDirection.up:
          return n.rect.center.dy <= target.top;
        case TraversalDirection.down:
          return n.rect.center.dy >= target.bottom;
        case TraversalDirection.left:
          return n.rect.center.dx <= target.left;
        case TraversalDirection.right:
          return n.rect.center.dx >= target.right;
      }
    }

    final eligible = candidates.where(inDirection).toList();
    if (eligible.isEmpty) return null;

    final vertical = direction == TraversalDirection.up ||
        direction == TraversalDirection.down;
    // 方向带：与源在垂直（up/down）或水平（left/right）投影重叠
    final band = vertical
        ? Rect.fromLTRB(
            target.left, double.negativeInfinity, target.right, double.infinity)
        : Rect.fromLTRB(double.negativeInfinity, target.top, double.infinity,
            target.bottom);
    final inBand =
        eligible.where((n) => !n.rect.intersect(band).isEmpty).toList();

    double mainDistance(FocusNode n) => vertical
        ? (n.rect.center.dy - target.center.dy).abs()
        : (n.rect.center.dx - target.center.dx).abs();
    double edgeDistance(FocusNode n) => vertical
        ? (direction == TraversalDirection.up
                ? target.top - n.rect.bottom
                : n.rect.top - target.bottom)
            .abs()
        : (direction == TraversalDirection.left
                ? target.left - n.rect.right
                : n.rect.left - target.right)
            .abs();
    int crossDistance(FocusNode a, FocusNode b) => vertical
        ? (a.rect.center.dx - target.center.dx)
            .abs()
            .compareTo((b.rect.center.dx - target.center.dx).abs())
        : (a.rect.center.dy - target.center.dy)
            .abs()
            .compareTo((b.rect.center.dy - target.center.dy).abs());

    if (inBand.isNotEmpty) {
      inBand.sort((a, b) {
        final c = mainDistance(a).compareTo(mainDistance(b));
        return c != 0 ? c : crossDistance(a, b);
      });
      return inBand.first;
    }
    eligible.sort((a, b) {
      final c = edgeDistance(a).compareTo(edgeDistance(b));
      return c != 0 ? c : crossDistance(a, b);
    });
    return eligible.first;
  }

  /// 从焦点节点向上找**轴匹配**的最近祖先滚动容器。
  ///
  /// 横滑区（horizontal）按上下键时跳过横滑、继续向上找外层竖列表；
  /// 找遍祖先仍无匹配则返回 null（交由默认焦点行为）。
  static ScrollableState? _matchingScrollable(
    BuildContext? context,
    TraversalDirection direction,
  ) {
    final wantVertical = direction == TraversalDirection.up ||
        direction == TraversalDirection.down;
    var ctx = context;
    while (ctx != null) {
      final scrollable = Scrollable.maybeOf(ctx);
      if (scrollable == null) return null;
      if ((scrollable.position.axis == Axis.vertical) == wantVertical) {
        return scrollable;
      }
      // 从该 Scrollable 继续向上（findAncestorStateOfType 不含自身）
      ctx = scrollable.context;
    }
    return null;
  }

  static double _stepFor(TraversalDirection direction, double viewport) {
    final step = viewport * _stepFactor;
    switch (direction) {
      case TraversalDirection.down:
      case TraversalDirection.right:
        return step;
      case TraversalDirection.up:
      case TraversalDirection.left:
        return -step;
    }
  }
}

class TvScopeEnterAction extends ContextAction<TvScopeEnterIntent> {
  TvScopeEnterAction();

  @override
  bool isEnabled(TvScopeEnterIntent intent, [BuildContext? context]) =>
      FocusManager.instance.primaryFocus is FocusScopeNode;

  @override
  Object? invoke(TvScopeEnterIntent intent, [BuildContext? context]) {
    final scope = FocusManager.instance.primaryFocus;
    if (scope is! FocusScopeNode) return null;
    // 壳层优先：GoRouter 嵌套 Navigator 下页面 ModalScope 不含壳层顶栏，
    // 冷启动 OK 若走原生 findFirst 只会落页面第一项——先在祖先 route scope
    // （壳层）里取 topmost 落焦。Dialog 无祖先 route scope → 候选为空，
    // 自动回退原生两段式（Dialog 内先落主按钮）。
    final shell = _findShellTopmost(scope);
    if (shell != null) {
      shell.requestFocus();
      return null;
    }
    if (scope.focusInDirection(TraversalDirection.down)) return null;
    scope.focusInDirection(TraversalDirection.up);
    return null;
  }

  /// 取严格祖先 route scope 内、topmost 的可聚焦节点（如顶栏）。
  static FocusNode? _findShellTopmost(FocusScopeNode scope) {
    final ancestorRoutes = <ModalRoute>{};
    FocusNode? p = scope.parent;
    while (p != null) {
      if (p is FocusScopeNode) {
        final r = _routeOf(p);
        if (r != null) ancestorRoutes.add(r);
      }
      p = p.parent;
    }
    if (ancestorRoutes.isEmpty) return null;

    FocusNode? parent = scope.parent;
    while (parent != null && parent is! FocusScopeNode) {
      parent = parent.parent;
    }
    if (parent is! FocusScopeNode) return null;

    final candidates = <FocusNode>[];
    for (final n in parent.traversalDescendants) {
      if (n.context == null || !n.canRequestFocus) continue;
      final r = _nearestRoute(n);
      if (r != null && ancestorRoutes.contains(r)) candidates.add(n);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final c = a.rect.top.compareTo(b.rect.top);
      return c != 0 ? c : a.rect.left.compareTo(b.rect.left);
    });
    return candidates.first;
  }

  /// 节点所属的最近 ModalRoute（无则 null）。
  static ModalRoute? _nearestRoute(FocusNode n) {
    FocusNode? p = n is FocusScopeNode ? n : n.parent;
    while (p != null) {
      if (p is FocusScopeNode) {
        final r = _routeOf(p);
        if (r != null) return r;
      }
      p = p.parent;
    }
    return null;
  }

  static ModalRoute? _routeOf(FocusScopeNode s) {
    final ctx = s.context;
    return ctx == null ? null : ModalRoute.of(ctx);
  }
}

/// TV 遥控器按键挂载层：覆盖方向键映射（焦点移动+滚动贯通）与
/// 作用域落焦（OK 键）。应包在 Navigator 之上，使所有页面与 Dialog
/// 的焦点事件先经过本层；未匹配或禁用时事件继续沿默认链处理。
class TvRemoteShortcuts extends StatelessWidget {
  const TvRemoteShortcuts({super.key, required this.child});

  final Widget child;

  static final Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const TvDirectionalIntent(TraversalDirection.up),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const TvDirectionalIntent(TraversalDirection.down),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const TvDirectionalIntent(TraversalDirection.left),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const TvDirectionalIntent(TraversalDirection.right),
    const SingleActivator(LogicalKeyboardKey.enter): const TvScopeEnterIntent(),
    const SingleActivator(LogicalKeyboardKey.numpadEnter):
        const TvScopeEnterIntent(),
    const SingleActivator(LogicalKeyboardKey.select):
        const TvScopeEnterIntent(),
  };

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        TvDirectionalIntent: TvDirectionalAction(),
        TvScopeEnterIntent: TvScopeEnterAction(),
      },
      child: Shortcuts(
        shortcuts: _shortcuts,
        child: child,
      ),
    );
  }
}
