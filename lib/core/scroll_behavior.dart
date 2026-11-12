import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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
/// | Android / iOS | `BouncingScrollPhysics`（iOS 式回弹） | 不显示（触屏无意义） |
/// | Windows / macOS / Linux | `ClampingScrollPhysics`（滚轮精确，不甩） | 细滚动条，可拖动 |
///
/// 所有平台都放开鼠标拖动。
class HimiScrollBehavior extends MaterialScrollBehavior {
  const HimiScrollBehavior();

  /// 是否触屏平台（不显示滚动条）。
  static bool _isTouchPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    // 手机端：iOS 式回弹（用户明确要求）
    if (_isTouchPlatform(getPlatform(context))) {
      return const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      );
    }
    // 桌面：Clamping 更精确（滚轮不会「甩」过头）
    return const ClampingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        // 桌面鼠标按住可拖动列表（默认不含，长列表很难操作）
        PointerDeviceKind.mouse,
      };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // 触屏不显示滚动条（手指本来就能滑，滚动条只会挡内容）
    if (_isTouchPlatform(getPlatform(context))) return child;
    // 桌面：细滚动条，可拖动定位
    return Scrollbar(
      thickness: 3,
      radius: const Radius.circular(2),
      interactive: true,
      child: child,
    );
  }
}
