import 'dart:async';

/// 成员变化后的在线人数重查序列调度。
///
/// presence 服务端列表有同步延迟，单次立即查询必拿到旧值；
/// 本类按固定间隔序列（如 1s/2s/3s/5s）触发 [onTick] 兜底重查，
/// 新的成员变化事件调用 [restart] 重排整个序列。
class CountRetryScheduler {
  CountRetryScheduler({
    required List<int> delaysSec,
    required this.onTick,
  }) : _delaysSec = List<int>.unmodifiable(delaysSec);

  final List<int> _delaysSec;

  /// 每次到达序列时间点时回调（调用方负责真正的查询）。
  final void Function() onTick;

  Timer? _timer;
  int _tick = 0;

  /// 序列是否仍在进行（有待触发的重查）。
  bool get isActive => _timer != null;

  /// 取消当前序列（如房间退出时）。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _tick = 0;
  }

  /// （重）启动序列：先清掉旧序列，再按 delaysSec 依次触发。
  void restart() {
    cancel();
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_tick >= _delaysSec.length) return;
    final delay = Duration(seconds: _delaysSec[_tick]);
    _tick++;
    _timer = Timer(delay, () {
      _timer = null;
      onTick();
      _scheduleNext();
    });
  }
}
