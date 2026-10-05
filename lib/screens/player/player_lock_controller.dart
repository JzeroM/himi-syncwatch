import 'package:flutter/foundation.dart';

/// 播放页屏幕锁定状态机（会话态，不入设置）。
///
/// - [lock]：锁定并收起解锁钮（调用方随后隐藏控制栏）；
/// - [onVideoTap]：锁定中点击画面 → 浮现解锁钮；未锁定 → 返回
///   `toggleControls` 语义交由调用方切换控制栏；
/// - [unlock]：解锁并隐藏解锁钮（调用方随后恢复控制栏）。
///
/// 抽成独立类是为了脱离 `mdk.Player`/路由环境单测状态转移。
class PlayerLockController extends ChangeNotifier {
  bool _locked = false;
  bool _unlockButtonVisible = false;

  bool get locked => _locked;
  bool get unlockButtonVisible => _unlockButtonVisible;

  void lock() {
    if (_locked) return;
    _locked = true;
    _unlockButtonVisible = false;
    notifyListeners();
  }

  void unlock() {
    if (!_locked && !_unlockButtonVisible) return;
    _locked = false;
    _unlockButtonVisible = false;
    notifyListeners();
  }

  /// 视频区点击：锁定中浮现解锁钮（重复点击仅刷新可见态），未锁定返回
  /// false 表示"应当切换控制栏"。
  bool onVideoTap() {
    if (!_locked) return false;
    if (!_unlockButtonVisible) {
      _unlockButtonVisible = true;
      notifyListeners();
    }
    return true;
  }

  /// 解锁钮自动隐藏（浮现超时）。
  void hideUnlockButton() {
    if (!_unlockButtonVisible) return;
    _unlockButtonVisible = false;
    notifyListeners();
  }
}
