import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 窄窗口底部浮动胶囊导航的显隐状态。
///
/// 从 `MainShell` 本地状态提升为 provider：子页滑到底隐藏导航后，
/// 返回分支根路由时由 [ShellNavRouteObserver] 统一恢复（不依赖滚动通知，
/// 因为分支页被 IndexedStack 保活、返回时不会重新 attach Scrollable）。
class ShellNavVisibility extends StateNotifier<bool> {
  ShellNavVisibility() : super(true);

  void show() {
    if (!state) state = true;
  }

  void hide() {
    if (state) state = false;
  }
}

final shellNavVisibilityProvider =
    StateNotifierProvider<ShellNavVisibility, bool>(
  (ref) => ShellNavVisibility(),
);

/// 分支导航器 observer：pop 回「分支根路由」（`previousRoute.isFirst`）时
/// 恢复底部导航。只对回到根路由恢复，从子页回子页（栈未到底）不误恢复。
class ShellNavRouteObserver extends NavigatorObserver {
  ShellNavRouteObserver(this.onReturnToRoot);

  final VoidCallback onReturnToRoot;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute?.isFirst ?? false) onReturnToRoot();
  }
}
