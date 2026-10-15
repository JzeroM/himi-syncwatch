import 'dart:async';

/// 视频流同线路自动重载的退避调度。
///
/// 网络波动导致流中断（invalid / 取流失败 / 缓冲超时）时，按固定退避序列
/// （2s/5s/10s，共 3 次）调度同线路重载；重试耗尽后 [exhausted] 为 true，
/// 不再调度。播放稳定 / 换集 / 手动加载成功时调用 [reset] 恢复预算。
///
/// 与 [CountRetryScheduler] 的区别：本类是「单发 + 耗尽」语义（一次错误
/// 调度一次重载，失败后再调度下一次），而非固定间隔连续 tick。
class StreamReloadScheduler {
  StreamReloadScheduler({List<int>? delaysSec})
      : _delaysSec = List<int>.unmodifiable(delaysSec ?? defaultDelaysSec);

  /// 默认退避序列（秒）：共 3 次重载机会。
  static const List<int> defaultDelaysSec = [2, 5, 10];

  /// 缓冲持续超过该时长视为流中断，触发重载（watchdog 用）。
  static const Duration stallTimeout = Duration(seconds: 10);

  final List<int> _delaysSec;

  int _attempt = 0;
  Timer? _timer;
  bool _inFlight = false;

  /// 是否已耗尽重试预算（不再调度）。
  bool get exhausted => _attempt >= _delaysSec.length;

  /// 是否有待触发的重载定时器。
  bool get hasPending => _timer?.isActive ?? false;

  /// 重载是否进行中（防并发重入）。
  bool get inFlight => _inFlight;

  /// 是否还能调度（未耗尽、无 pending、非 inFlight）。
  bool get canSchedule => !exhausted && !hasPending && !_inFlight;

  /// 调度一次重载；已调度 / 进行中 / 耗尽则 no-op。
  ///
  /// [onFire] 在退避时间到达后执行（调用方负责真正的重载）。
  void schedule(void Function() onFire) {
    if (!canSchedule) return;
    final delay = Duration(seconds: _delaysSec[_attempt]);
    _attempt++;
    _timer = Timer(delay, () {
      _timer = null;
      onFire();
    });
  }

  /// 标记重载开始；已在进行中返回 false（调用方应跳过本次重载）。
  bool beginFlight() {
    if (_inFlight) return false;
    _inFlight = true;
    return true;
  }

  /// 标记重载结束（须在 beginFlight 成功后调用，建议 finally 中调用）。
  void endFlight() {
    _inFlight = false;
  }

  /// 重试预算完整复位：attempt 清零 + 取消 pending 定时器。
  ///
  /// 播放稳定 / 换集 / 手动加载成功时调用。
  void reset() {
    _attempt = 0;
    cancelPending();
  }

  /// 仅取消 pending 定时器，保留已消耗的重试预算。
  ///
  /// dispose / 换集时调用（防定时器泄漏；是否连预算一起清由调用方决定）。
  void cancelPending() {
    _timer?.cancel();
    _timer = null;
  }
}
