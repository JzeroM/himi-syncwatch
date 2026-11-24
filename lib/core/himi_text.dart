import 'package:flutter/material.dart';

/// 698 N46：文字语义色**单点映射**——明暗暂统一白系（亮版文字与暗版
/// 一致，后续做明亮版文字适配时**只改本文件方法体**，不再逐文件反转）。
///
/// 语义分档（承接 N45 灰阶平移档位）：
/// [primary] 主文字/图标 · [secondary] 次文字(α0.70) · [t75] 淡标(α0.75)
/// · [t62](α0.62) · [t54](α0.54) · [t38](α0.38) · [t30](α0.30) ·
/// [t24](α0.24 弱化态/禁用)。
abstract final class HimiText {
  /// 主文字/图标。
  static Color primary(BuildContext _) => Colors.white;

  /// 次文字（α0.70）。
  static Color secondary(BuildContext _) =>
      Colors.white.withValues(alpha: 0.70);

  /// 淡标（α0.75）。
  static Color t75(BuildContext _) => Colors.white.withValues(alpha: 0.75);

  /// 三级文字（α0.62）。
  static Color t62(BuildContext _) => Colors.white.withValues(alpha: 0.62);

  /// 弱文字（α0.54）。
  static Color t54(BuildContext _) => Colors.white.withValues(alpha: 0.54);

  /// 更弱（α0.38）。
  static Color t38(BuildContext _) => Colors.white.withValues(alpha: 0.38);

  /// 极弱（α0.30）。
  static Color t30(BuildContext _) => Colors.white.withValues(alpha: 0.30);

  /// 弱化/禁用态（α0.24）。
  static Color t24(BuildContext _) => Colors.white.withValues(alpha: 0.24);
}
