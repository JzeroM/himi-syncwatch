import 'package:flutter/foundation.dart';

/// 播放器平台差异开关（纯函数，测试用 debugDefaultTargetPlatformOverride 覆盖）。
class PlayerPlatform {
  PlayerPlatform._();

  /// Windows 取消音量/亮度垂直手势（改用控制条滑杆）。
  static bool get verticalVolumeBrightnessGesture =>
      defaultTargetPlatform != TargetPlatform.windows;

  /// 控制条音量/亮度滑杆（仅 Windows）。
  static bool get volumeBrightnessSliders =>
      defaultTargetPlatform == TargetPlatform.windows;

  /// 空格键播放/暂停（仅 Windows）。
  static bool get spaceKeyPlayPause =>
      defaultTargetPlatform == TargetPlatform.windows;

  /// 窗口全屏按钮（桌面三端）。
  static bool get windowFullscreenButton =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// 进入播放器时亮度跟随系统（仅 Windows，不强制覆盖系统亮度）。
  static bool get brightnessFollowsSystem =>
      defaultTargetPlatform == TargetPlatform.windows;

  /// 进入播放器时的初始亮度。
  /// [current] 为当前实际亮度；[followSystem] 为真时采用当前值，否则采用 [fallback]。
  static double initialBrightness({
    required double current,
    required bool followSystem,
    double fallback = 0.8,
  }) {
    if (followSystem) {
      if (current.isNaN) return fallback;
      return current.clamp(0.0, 1.0);
    }
    return fallback;
  }
}
