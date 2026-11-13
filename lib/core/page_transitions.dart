// 鸿蒙 SDK 把 `CupertinoPageTransitionsBuilder` 放在 `material.dart`，
// stock Flutter 把它放在 `cupertino.dart`——两个都 import，两套 SDK 才能
// 各自解析到同一个类名。
//
// 两套 SDK 会各报一个不同的「冗余导入」提示（stock 说 cupertino 没被用到，
// 鸿蒙说 material 已包含），都属于跨 SDK 兼容的必然产物，一并忽略。
// ignore: unused_import, unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 687：页面转场（697 补鸿蒙）。
///
/// ## 分档
///
/// | 平台 | 转场 | 理由 |
/// |---|---|---|
/// | Android / iOS / **鸿蒙** | `CupertinoPageTransitionsBuilder` | 从右侧滑入，比 Android 默认 Zoom 自然 |
/// | Windows / macOS / Linux | `FadeUpwardsPageTransitionsBuilder` | 淡入上移，不抢眼 |
///
/// ## 为什么不能写成常量 map（697 修复点）
///
/// 项目用两套 SDK 构建：
/// - 鸿蒙用 `flutter_ohos`，`TargetPlatform` 里有 `ohos`；
/// - 其它平台用 stock Flutter，**枚举里没有 `ohos`**。
///
/// 因此 `const PageTransitionsTheme(builders: {TargetPlatform.ohos: ...})`
/// 会让 stock SDK 直接编译失败。687 当时只列了 5 个平台，鸿蒙于是走框架
/// 兜底 `ZoomPageTransitionsBuilder`（缩放），不是设计的横滑。
///
/// 这里改为**运行时按 `TargetPlatform.values` 构建**：遇到 `name == 'ohos'`
/// 就按手机档处理，两套 SDK 都能编译。
PageTransitionsTheme buildHimiPageTransitions() {
  final builders = <TargetPlatform, PageTransitionsBuilder>{};
  for (final platform in TargetPlatform.values) {
    builders[platform] = _isTouchFirst(platform)
        ? const CupertinoPageTransitionsBuilder()
        : const FadeUpwardsPageTransitionsBuilder();
  }
  return PageTransitionsTheme(builders: builders);
}

/// 是否触屏手机形态（Android / iOS / 鸿蒙）。
///
/// 鸿蒙按 `name` 判定——stock Flutter 没有 `TargetPlatform.ohos`。
bool _isTouchFirst(TargetPlatform platform) {
  if (platform.name == 'ohos') return true;
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}
