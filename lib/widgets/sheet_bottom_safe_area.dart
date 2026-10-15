import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 底部弹层统一底部安全区（v1.1.244）。
///
/// 把弹层内容抬离虚拟导航键/手势条区域，避免保存/确认按钮被系统导航
/// 遮挡。底部取值为 `max(viewPadding.bottom, padding.bottom)`：
/// - `viewPadding`：不受键盘（viewInsets）影响的系统 insets；
/// - `padding`：`viewPadding - viewInsets`，祖先 SafeArea 消费后仅它保留。
///
/// [avoidSides] 为 true 时同时用 `SafeArea(top:false, bottom:false)`
/// 避开横屏左右安全区（替代弹层内裸 SafeArea，并顺带消除其把状态栏
/// 高度垫到弹层顶部的副作用）。
class SheetBottomSafeArea extends StatelessWidget {
  const SheetBottomSafeArea({
    super.key,
    required this.child,
    this.avoidSides = false,
  });

  final Widget child;
  final bool avoidSides;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottom = math.max(
      mediaQuery.viewPadding.bottom,
      mediaQuery.padding.bottom,
    );
    Widget result = Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: child,
    );
    if (avoidSides) {
      result = SafeArea(
        top: false,
        bottom: false,
        child: result,
      );
    }
    return result;
  }
}
