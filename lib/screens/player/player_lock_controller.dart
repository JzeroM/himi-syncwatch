import 'package:flutter/foundation.dart';

/// 播放页屏幕锁定状态机（会话态，不入设置）。
///
/// - [lock]：锁定（调用方随后收起控制栏，仅保留左缘锁钮）；
/// - [unlock]：解锁（调用方随后恢复控制栏）。
///
/// 抽成独立类是为了脱离 `mdk.Player`/路由环境单测状态转移。
class PlayerLockController extends ChangeNotifier {
  bool _locked = false;

  bool get locked => _locked;

  void lock() {
    if (_locked) return;
    _locked = true;
    notifyListeners();
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
  }
}
