import 'package:flutter/foundation.dart';

/// 679：房间模式的「退出请求」全局通道。
///
/// 【链路真相】`window_manager` 的 `WM_CLOSE` 处理是
/// **先发 `close` 事件、再检查 `IsPreventClose()`**（插件源码
/// `window_manager_plugin.cpp`）：
///
/// ```cpp
/// } else if (message == WM_CLOSE) {
///     _EmitEvent("close");                    // ← 先发事件
///     if (window_manager->IsPreventClose()) {
///       return -1;                            // ← 再拦截
///     }
/// }
/// ```
///
/// 所以 `onWindowClose` 在**拦截态也会被调用**（早期实现误以为它不会
/// 触发，导致「点 X 直接关掉 Qt 播放窗、房间悬空」——真机回归）。
///
/// 【正确分工】
/// - `main.dart` 的 `onWindowClose`：若 [hasRoomListener]（房间播放中）
///   → 只发退出请求，**不关 Qt**；否则（单人播放）→ 直接关 Qt
/// - 播放页：`attach()` 注册监听 → 弹确认框 → 确认后关 Qt + 退页；
///   `detach()` 在 dispose 里调用
/// - `setPreventClose(true)` 仍需要：它负责「别让窗口真的关掉」，
///   与事件分发是两件独立的事
class RoomExitRequest {
  const RoomExitRequest._();

  /// 请求序号（每次点关闭 +1）。播放页监听变化即弹确认框。
  static final ValueNotifier<int> seq = ValueNotifier<int>(0);

  /// 当前是否有房间播放页在监听（决定 `main.dart` 是「弹确认」还是「直接关」）。
  static bool _hasRoomListener = false;
  static bool get hasRoomListener => _hasRoomListener;

  /// 房间播放页注册（进入房间时调用）。
  static void attach() => _hasRoomListener = true;

  /// 房间播放页注销（dispose 时调用）。
  static void detach() => _hasRoomListener = false;

  /// 发起一次退出请求（由 `main.dart` 的窗口关闭监听调用）。
  static void request() => seq.value = seq.value + 1;

  /// 测试用：重置全部状态。
  @visibleForTesting
  static void reset() {
    seq.value = 0;
    _hasRoomListener = false;
  }
}
