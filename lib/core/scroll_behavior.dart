import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:himi_syncwatch/core/himi_platform.dart';

/// 687：全局滚动行为（统一各平台手感）。
///
/// ## 为什么需要
///
/// 旧实现 `MaterialApp.router` 没设 `scrollBehavior`，全平台走 Flutter
/// 默认值：
///   - **Android** 用 `ClampingScrollPhysics`——滑到边界「硬撞墙」，
///     没有回弹，观感生硬（用户反馈「滑动不自然」）
///   - **桌面**默认 `dragDevices` **不含 mouse**——鼠标按住拖动列表
///     完全不动，只有滚轮能用（长列表很难受）
///   - 长列表没有任何滚动条，缺少位置反馈
///
/// ## 现在
///
/// | 平台 | 物理 | 滚动条 |
/// |---|---|---|
/// | Android / iOS / **鸿蒙** | `BouncingScrollPhysics`（iOS 式回弹） | 不显示（触屏无意义） |
/// | Windows / macOS / Linux | `ClampingScrollPhysics`（滚轮精确，不甩） | 细滚动条，可拖动 |
///
/// 所有平台都放开鼠标拖动。
///
/// 【697 修复】此前判定写的是 `platform == android || platform == iOS`，
/// **鸿蒙（`TargetPlatform.ohos`）落在桌面分支**，滑到边界硬撞墙、没有
/// 回弹。现改为按 `name` 判定鸿蒙（stock SDK 没有该枚举值，不能直接比）。
class HimiScrollBehavior extends MaterialScrollBehavior {
  const HimiScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // 手机端（含鸿蒙）：iOS 式回弹（用户明确要求）
    if (_isTouchFirst(getPlatform(context))) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    // 桌面：Clamping 更精确（滚轮不会「甩」过头）
    return const ClampingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  /// 是否触屏手机形态（Android / iOS / 鸿蒙）。
  ///
  /// 不能只比枚举：stock Flutter 没有 `TargetPlatform.ohos`，故鸿蒙按
  /// `name` 判定（见 [HimiPlatform.isOhos]）。
  static bool _isTouchFirst(TargetPlatform platform) =>
      HimiPlatform.isOhos ||
      platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS;

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        // 桌面鼠标按住可拖动列表（默认不含，长列表很难操作）
        PointerDeviceKind.mouse,
      };

  // 688：**不覆写 buildScrollbar**——桌面细滚动条观感差（用户明确否掉），
  // 回归 Flutter 默认（桌面自带系统滚动条，触屏不显示）。
}
