import 'package:flutter/foundation.dart';

/// 全局平台判定（687 交互优化 / 697 鸿蒙修正）。
///
/// ## 为什么需要这个文件
///
/// 项目同时用两套 Flutter SDK 构建：
/// - **鸿蒙**：`flutter_ohos`，`TargetPlatform` 枚举里有 `ohos`；
/// - **其它平台**：stock Flutter，枚举里**没有** `ohos`。
///
/// 因此**任何地方都不能写 `TargetPlatform.ohos`**——那会让 stock SDK 下
/// 的 `flutter analyze` / `flutter test` 直接编译失败（枚举值不存在）。
/// 只能用 `defaultTargetPlatform.name == 'ohos'` 这种运行时字符串比较。
///
/// ## 687 遗留 bug（697 修复）
///
/// 687 的滚动物理与页面转场都按 `TargetPlatform` 分档，但两处都只列了
/// android / iOS / windows / macOS / linux——**鸿蒙落在桌面分支**：
/// - `HimiScrollBehavior` 给鸿蒙返回 `ClampingScrollPhysics`
///   → 滑到边界「硬撞墙」，没有 iOS 式回弹（鸿蒙是触屏设备，明显不符）
/// - `pageTransitionsTheme.builders` 未含 ohos
///   → 走框架兜底 `ZoomPageTransitionsBuilder`，不是设计的横滑
class HimiPlatform {
  const HimiPlatform._();

  /// 测试用鸿蒙覆盖。
  ///
  /// stock Flutter 的 `TargetPlatform` 没有 `ohos`，
  /// `debugDefaultTargetPlatformOverride` 无法模拟，只能单独留钩子
  /// （与 `PlayerPlatform.debugIsOhosOverride` 同一套做法）。
  @visibleForTesting
  static bool? debugIsOhosOverride;

  /// 是否鸿蒙。
  static bool get isOhos =>
      debugIsOhosOverride ??
      (!kIsWeb && defaultTargetPlatform.name == 'ohos');

  /// 是否触屏手机形态（Android / iOS / 鸿蒙）。
  ///
  /// 用于「该用触屏手感还是桌面手感」的判定：滚动物理、滚动条、
  /// 页面转场都以此为准。
  static bool get isTouchFirst =>
      isOhos ||
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));
}
