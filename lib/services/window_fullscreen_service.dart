import 'package:window_manager/window_manager.dart';

/// 桌面窗口全屏封装（window_manager）。
/// 所有调用静默兜底：插件不可用/未初始化时返回安全默认值，绝不抛出。
class WindowFullscreenService {
  /// 查询当前窗口是否全屏；失败返回 false。
  Future<bool> isFullScreen() async {
    try {
      return await windowManager.isFullScreen();
    } catch (_) {
      return false;
    }
  }

  /// 设置窗口全屏状态；失败静默。
  Future<void> setFullScreen(bool value) async {
    try {
      await windowManager.setFullScreen(value);
    } catch (_) {}
  }
}
