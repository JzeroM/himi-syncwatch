import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 「可用版本」行的 TV 方向键确定性导航。
///
/// 版本行原先完全依赖框架方向键遍历（DirectionalFocusTraversalPolicy +
/// `Scrollable.ensureVisible`）：详情页是折叠 SliverAppBar + 单列内容，
/// ↓ 的落点与滚动量受 ensureVisible/策略历史影响，真机实测「下移一个版本
/// 后再按 ↓ 焦点环反而上移」；到底后还会落入 TvDirectionalAction 的空
/// 滚动重试，整页乱滚。这里按行序显式接管 ↑/↓：
/// - ↓/↑：焦点移到相邻版本行并确保可见；
/// - 末行 ↓ 且下方**没有任何可聚焦节点**：吞键（不滚动、不乱跳）；
///   下方有节点则放行（去剧集横卡/播出季/相似推荐）；
/// - 首行 ↑ 放行（回到播放操作行）。
class VersionRowNav {
  final Map<String, FocusNode> _nodes = <String, FocusNode>{};
  List<String> _order = const <String>[];

  /// 构建时同步当前生效的行 id 顺序；销毁已消失版本的节点。
  void sync(List<String> orderedIds) {
    _order = List<String>.unmodifiable(orderedIds);
    final active = orderedIds.toSet();
    final stale = _nodes.keys.where((id) => !active.contains(id)).toList();
    for (final id in stale) {
      _nodes.remove(id)!.dispose();
    }
  }

  /// 取该版本行对应的焦点节点（按 id 复用：跨重建稳定，焦点不丢）。
  FocusNode nodeFor(String id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'versionRow_$id'));

  /// 行按键处理：↑/↓ 已消费返回 handled，其余原样返回 ignored
  /// （OK 长按等默认逻辑不受影响）。
  KeyEventResult handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.arrowDown;
    final up = key == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;

    final index = _indexOf(node);
    if (index < 0) return KeyEventResult.ignored;

    final nextIndex = down ? index + 1 : index - 1;
    if (nextIndex >= 0 && nextIndex < _order.length) {
      final target = _nodes[_order[nextIndex]];
      if (target != null && target.canRequestFocus && target.context != null) {
        _focusAndReveal(target, down: down);
        return KeyEventResult.handled;
      }
    }

    // 末行 ↓：下方无任何可聚焦节点时吞键，避免框架/滚动兜底把整页滚走
    //（用户感知为「焦点环反而上移」）。
    if (down && !hasFocusableBelow(node)) return KeyEventResult.handled;
    // 首行 ↑（或末行下方仍有节点）：交给默认遍历。
    return KeyEventResult.ignored;
  }

  int _indexOf(FocusNode node) {
    for (var i = 0; i < _order.length; i++) {
      if (identical(_nodes[_order[i]], node)) return i;
    }
    return -1;
  }

  void _focusAndReveal(FocusNode target, {required bool down}) {
    // 与框架 defaultTraversalRequestFocusCallback 同语义：先落焦再确保可见
    target.requestFocus();
    final ctx = target.context;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignmentPolicy: down
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  /// [node] 所在作用域内、几何上位于其下方的可聚焦节点是否存在。
  /// 复刻框架方向带判据（中心点越过当前节点下沿）。
  @visibleForTesting
  static bool hasFocusableBelow(FocusNode node) {
    final scope = node.nearestScope;
    if (scope == null || node.context == null) return false;
    final target = node.rect;
    for (final n in scope.traversalDescendants) {
      if (identical(n, node)) continue;
      if (!n.canRequestFocus || n.context == null) continue;
      if (n.rect.center.dy >= target.bottom) return true;
    }
    return false;
  }

  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
    _order = const <String>[];
  }
}
