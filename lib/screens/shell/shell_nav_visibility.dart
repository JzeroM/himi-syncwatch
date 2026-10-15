import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 窄窗口底部浮动胶囊导航的显隐状态（多来源）。
///
/// 导航只在各 tab「首页」（分支根路由）显示；隐藏来源分三类：
/// - `scroll`：页面滑到底（滚动通知驱动）；
/// - `route`：分支内 push 了非根路由（子页/底部弹层/对话框/扫码页）；
/// - `form`：分支首页上内联展开了添加/编辑表单。
///
/// 任一来源存在即隐藏；全部解除才恢复。[reset] 清空所有来源
/// （切 tab / 回分支根路由时统一调用）。
class ShellNavVisibility extends StateNotifier<bool> {
  ShellNavVisibility() : super(true);

  final Set<String> _reasons = {};

  /// 按来源隐藏（幂等；重复 hide 不影响计数语义）。
  void hideFor(String reason) {
    if (_reasons.add(reason)) state = false;
  }

  /// 解除某来源；全部解除后恢复显示。
  void showFor(String reason) {
    if (_reasons.remove(reason) && _reasons.isEmpty) state = true;
  }

  /// 清空全部隐藏来源并恢复显示。
  void reset() {
    _reasons.clear();
    if (!state) state = true;
  }

  /// 兼容旧调用：滚动来源。
  void hide() => hideFor('scroll');

  void show() => showFor('scroll');
}

/// 滚动来源（main_shell 滚动通知）。
const kShellNavHideScroll = 'scroll';

/// 分支子路由来源（RouteObserver push 非根路由）。
const kShellNavHideRoute = 'route';

/// 内联表单来源（Emby 添加/编辑表单展开）。
const kShellNavHideForm = 'form';

final shellNavVisibilityProvider =
    StateNotifierProvider<ShellNavVisibility, bool>(
  (ref) => ShellNavVisibility(),
);

/// 每分支「切走重置」代数：MainShell 切 tab 时对源分支 bump，
/// 分支首页据此丢弃未保存操作（表单收起、输入还原）。
class ShellBranchEpoch extends StateNotifier<Map<int, int>> {
  ShellBranchEpoch() : super(const {});

  /// 源分支被切走：代数 +1（触发该分支页面重置）。
  void bump(int branch) =>
      state = {...state, branch: (state[branch] ?? 0) + 1};

  /// 当前分支代数（未 bump 过为 0）。
  int of(int branch) => state[branch] ?? 0;
}

final shellBranchEpochProvider =
    StateNotifierProvider<ShellBranchEpoch, Map<int, int>>(
  (ref) => ShellBranchEpoch(),
);

/// 分支导航器 observer：
/// - push 非根路由 → 隐藏底部导航（子页/弹层不与导航重叠）；
/// - pop 回「分支根路由」（`previousRoute.isFirst`）→ 恢复导航。
/// 只对回到根路由恢复，从子页回子页（栈未到底）不误恢复。
class ShellNavRouteObserver extends NavigatorObserver {
  ShellNavRouteObserver(this.onReturnToRoot, {this.onPushSubPage});

  final VoidCallback onReturnToRoot;
  final VoidCallback? onPushSubPage;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    // 路由可能在 widget build 期间 push（如 go_router 首次构建分支栈），
    // 直接改 provider 会触发 "modify while building"；延迟到微任务。
    if (!route.isFirst) {
      scheduleMicrotask(() => onPushSubPage?.call());
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute?.isFirst ?? false) {
      scheduleMicrotask(onReturnToRoot);
    }
  }
}
