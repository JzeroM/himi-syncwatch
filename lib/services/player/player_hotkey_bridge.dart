import 'package:flutter/foundation.dart';

/// 695：Windows 全局键盘桥——让 Space/ESC 在**播放页之外**（详情页、
/// 房间面板等）也生效。播放页（player_screen）注册回调，app 根部的
/// `WindowsGlobalHotkeys` 消费。
///
/// 【为什么用注册制】Space 的暂停/播放含锁屏/观众权限与房间同步
/// （`_handleHotkeyTogglePlayPause`），语义只应有一份实现——全局层
/// 不重复实现，直接复用播放页回调（与播放页热键同链路）。
class PlayerHotkeyBridge {
  PlayerHotkeyBridge._();

  /// 暂停/播放（回调内部含锁屏/观众权限门禁 + 房间同步）。
  static VoidCallback? togglePlayPause;

  /// Flutter 窗当前是否全屏。
  static bool Function()? isWindowFullscreen;

  /// 退出 Flutter 窗全屏。
  static VoidCallback? exitWindowFullscreen;

  /// 测试注入复位。
  @visibleForTesting
  static void debugReset() {
    togglePlayPause = null;
    isWindowFullscreen = null;
    exitWindowFullscreen = null;
  }
}
