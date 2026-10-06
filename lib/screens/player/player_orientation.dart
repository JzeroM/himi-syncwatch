import 'package:flutter/services.dart';

/// 播放器横屏方向侧。
enum PlayerLandscapeSide { left, right }

/// 横屏方向请求（按目标侧**单方向**强制）。
///
/// 引擎 `PlatformChannel.decodeOrientations` 把 `[landscapeLeft,
/// landscapeRight]` 双方向列表解码为 `SCREEN_ORIENTATION_USER_LANDSCAPE`
/// ——USER 系尊重系统旋转锁：系统关闭自动旋转时请求不生效，摇一摇 180°
/// 翻转与播放器按钮横屏全部失效。单方向列表解码为固定值
/// （`0x02 LANDSCAPE` / `0x08 REVERSE_LANDSCAPE`），旋转锁开启时也能
/// 强制旋转。
Future<void> requestPlayerLandscape(PlayerLandscapeSide side) {
  return SystemChrome.setPreferredOrientations([
    switch (side) {
      PlayerLandscapeSide.left => DeviceOrientation.landscapeLeft,
      PlayerLandscapeSide.right => DeviceOrientation.landscapeRight,
    },
  ]);
}
