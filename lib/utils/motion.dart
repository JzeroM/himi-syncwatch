import 'package:flutter/material.dart';

/// 687：统一动效入口——遵守系统「减少动画」无障碍设置。
///
/// ## 为什么需要
///
/// 系统无障碍里有「移除动画」（Android）/「减弱动态效果」（iOS）/
/// 「显示动画」（Windows）。开启后系统会通过
/// `MediaQuery.disableAnimations` 告知应用，但**应用必须自己遵守**——
/// Flutter 只对部分内置转场生效，自定义的 `AnimatedContainer` /
/// `AnimatedOpacity` / 入场动画仍会照常播放。
///
/// 对前庭功能敏感的用户，持续的缩放/位移动画会引起眩晕。
///
/// ## 用法
///
/// ```dart
/// AnimatedContainer(
///   duration: Motion.of(context, const Duration(milliseconds: 200)),
///   ...
/// )
/// ```
///
/// 减少动画时 `Motion.of` 返回 [Duration.zero]，动画瞬间完成（保留
/// 最终视觉状态，只是没有过渡过程）。
class Motion {
  const Motion._();

  /// 系统是否要求减少动画。
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// 该用多长时长——减少动画时返回 [Duration.zero]。
  static Duration of(BuildContext context, Duration base) =>
      reduced(context) ? Duration.zero : base;

  /// 该用多大缩放——减少动画时返回 1.0（不缩放）。
  static double scale(BuildContext context, double base) =>
      reduced(context) ? 1.0 : base;
}
