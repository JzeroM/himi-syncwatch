import 'package:flutter/foundation.dart';

/// 679：房间模式的「退出请求」全局通道。
///
/// 【为什么需要全局通道】Flutter 主窗的关闭按钮由 `window_manager` 拦截
/// （`setPreventClose(true)`），但**拦截回调拿不到播放页的 BuildContext**——
/// 它在 `main.dart` 的 `WindowListener` 里。所以：
///
/// ```
/// 用户点关闭 → window_manager 拦截 → main.dart 发通知 → 播放页监听 → 弹确认框
/// ```
///
/// 【为什么用 ValueNotifier 而不是 StreamController】不需要背压、不需要
/// 多订阅者，一个「第 N 次请求」的计数即可驱动播放页响应；且 `ValueNotifier`
/// 在 widget 层可以直接 `addListener`，不需要管理订阅生命周期。
class RoomExitRequest {
  const RoomExitRequest._();

  /// 请求序号（每次点关闭 +1）。播放页监听变化即弹确认框。
  static final ValueNotifier<int> seq = ValueNotifier<int>(0);

  /// 发起一次退出请求（由 `main.dart` 的窗口关闭监听调用）。
  static void request() => seq.value = seq.value + 1;

  /// 测试用：重置计数。
  @visibleForTesting
  static void reset() => seq.value = 0;
}
