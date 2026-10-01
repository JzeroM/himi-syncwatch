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
    if (scope.focusInDirection(TraversalDirection.down)) return null;
    scope.focusInDirection(TraversalDirection.up);
    return null;
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
