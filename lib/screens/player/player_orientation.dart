import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// 播放器横屏方向侧。
enum PlayerLandscapeSide { left, right }

/// 播放器横屏方向映射（纯逻辑，便于单测）。
class PlayerOrientation {
  const PlayerOrientation._();

  /// 引擎侧 `DeviceOrientation.landscapeLeft/Right` 在 iOS 与 Android 的
  /// 视觉方向相反：安卓「左」= iOS「右」。这里对 iOS 做 left/right 互换，
  /// 使两端横屏观感一致（修复 iOS 横屏反/倒）。
  static PlayerLandscapeSide effectiveSide(
    PlayerLandscapeSide side, {
    required bool isIOS,
  }) {
    if (!isIOS) return side;
    return side == PlayerLandscapeSide.left
        ? PlayerLandscapeSide.right
        : PlayerLandscapeSide.left;
  }
}

/// 横屏方向请求（按目标侧**单方向**强制）。
///
/// 引擎 `PlatformChannel.decodeOrientations` 把 `[landscapeLeft,
/// landscapeRight]` 双方向列表解码为 `SCREEN_ORIENTATION_USER_LANDSCAPE`
/// ——USER 系尊重系统旋转锁：系统关闭自动旋转时请求不生效，摇一摇 180°
/// 翻转与播放器按钮横屏全部失效。单方向列表解码为固定值
/// （`0x02 LANDSCAPE` / `0x08 REVERSE_LANDSCAPE`），旋转锁开启时也能
/// 强制旋转。
Future<void> requestPlayerLandscape(PlayerLandscapeSide side) {
  final effective = PlayerOrientation.effectiveSide(side, isIOS: Platform.isIOS);
  return SystemChrome.setPreferredOrientations([
    switch (effective) {
      PlayerLandscapeSide.left => DeviceOrientation.landscapeLeft,
      PlayerLandscapeSide.right => DeviceOrientation.landscapeRight,
    },
  ]);
}
