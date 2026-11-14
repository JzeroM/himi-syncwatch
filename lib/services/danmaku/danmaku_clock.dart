/// 弹幕播放时钟（四端同构的纯逻辑实现）。
///
/// ## 为什么需要它
///
/// 弹幕的横坐标是「播放位置的函数」。如果直接用播放器上报的位置，弹幕会
/// 跟着上报节奏**一段一段往前蹦**；如果每次上报都硬重锚，IPC 延迟抖动又会
/// 让弹幕**前后弹一下**。两种都是真机上肉眼可见的"跳跃抖动"。
///
/// 正确做法（参考 NeoPlayer 的 `PlaybackClock` 思路）：
///
/// - **锚点 + 单调时钟投影**：两次上报之间按播放速率线性外推；
/// - **误差死区**（[deadbandMs]）：小于人眼可辨阈值的误差不修正，避免来回抖；
/// - **缓慢收敛**（[convergeMs]）：中等误差不改锚点，只微调速率让它自己追上；
/// - **硬对齐**（[hardResyncMs]）：只有 seek / 卡顿恢复这种大跳才允许瞬移。
///
/// ## 为什么用单调时钟
///
/// `DateTime.now()` / `System.currentTimeMillis()` 会被 NTP 校时拨动，
/// 一拨动整屏弹幕就跳。四端各自用各自平台的单调时钟：
///
/// | 平台 | 单调时钟 |
/// |---|---|
/// | Flutter | `Ticker.elapsed` |
/// | 安卓 | `SystemClock.elapsedRealtimeNanos()` |
/// | 鸿蒙 | `systemDateTime.getUptime(STARTUP)` |
/// | Windows | `QElapsedTimer`（C++ 侧） |
///
/// 本类是唯一权威实现，另外三端按同样的规则各自实现（有结构测试锁定同构）。
library;

class DanmakuClock {
  DanmakuClock({
    Duration position = Duration.zero,
    int monoUs = 0,
    bool paused = true,
    double baseRate = 1.0,
  })  : _anchorPos = position,
        _anchorMonoUs = monoUs,
        _baseRate = baseRate > 0 ? baseRate : 1.0,
        _rate = paused ? 0.0 : (baseRate > 0 ? baseRate : 1.0),
        _paused = paused;

  /// 误差死区：小于该值不修正（毫秒）。
  static const int deadbandMs = 40;

  /// 硬对齐阈值：超过该值视为 seek/卡顿恢复（毫秒）。
  static const int hardResyncMs = 400;

  /// 收敛窗口：把中等误差在约该时长内消化掉（毫秒）。
  static const int convergeMs = 600;

  /// 速率修正上限：±5%，避免弹幕忽快忽慢。
  static const double maxRateAdjust = 0.05;

  Duration _anchorPos;
  int _anchorMonoUs;
  double _baseRate;
  double _rate;
  bool _paused;
  Duration _duration = Duration.zero;

  int _lastErrorMs = 0;
  int _hardResyncCount = 0;

  /// 最近一次上报与投影的误差（毫秒）——面板统计用。
  int get lastErrorMs => _lastErrorMs;

  /// 硬对齐次数（seek / 卡顿恢复）——面板统计用。
  int get hardResyncCount => _hardResyncCount;

  /// 是否处于暂停冻结。
  bool get paused => _paused;

  /// 当前生效速率（含收敛修正）。
  double get rate => _rate;

  /// 单调时钟时刻 [monoUs] 对应的播放位置。
  Duration positionAt(int monoUs) {
    if (_paused || _rate <= 0) return _anchorPos;
    final elapsedUs = monoUs - _anchorMonoUs;
    if (elapsedUs <= 0) return _anchorPos;
    final projected = _anchorPos + Duration(microseconds: (elapsedUs * _rate).round());
    if (projected < Duration.zero) return Duration.zero;
    if (_duration > Duration.zero && projected > _duration) return _duration;
    return projected;
  }

  /// 收到一份权威位置（播放器上报）。
  ///
  /// [monoUs] 必须是**单调时钟**（与 [positionAt] 同一时间基准）。
  /// [duration] 为 0 表示时长未知（起播早期）——此时不钳上限。
  void onAuthoritative({
    required Duration position,
    required int monoUs,
    required bool paused,
    double baseRate = 1.0,
    Duration duration = Duration.zero,
  }) {
    final rate = baseRate > 0 ? baseRate : 1.0;
    if (duration > Duration.zero) _duration = duration;

    // 暂停/恢复、播放速率变化：直接重锚（语义变化，不是误差）。
    if (paused != _paused || (paused == false && rate != _baseRate)) {
      _hardResync(position, monoUs, paused, rate);
      return;
    }
    if (paused) {
      // 暂停期间位置本就该冻结，只在偏差明显时才挪锚点。
      if ((position - _anchorPos).inMilliseconds.abs() > hardResyncMs) {
        _hardResync(position, monoUs, true, rate);
      }
      return;
    }

    _baseRate = rate;
    final errMs = (position - positionAt(monoUs)).inMilliseconds;
    _lastErrorMs = errMs;

    if (errMs.abs() > hardResyncMs) {
      _hardResync(position, monoUs, false, rate);
      return;
    }
    // 【关键】换速率前必须先把锚点挪到「当前投影位置」。
    // 投影是 `anchorPos + (now - anchorMono) * rate`，速率一改，
    // 整段 elapsed 会被重新缩放 → 位置瞬间回退/前跳（真机表现为抽搐）。
    // 先重锚保证位置连续，再只改变斜率。
    _rebase(monoUs);

    if (errMs.abs() > deadbandMs) {
      // 只调整速率，让误差在 convergeMs 内自行消化。
      final adjust = (errMs / convergeMs).clamp(-maxRateAdjust, maxRateAdjust);
      _rate = rate + adjust;
      return;
    }
    // 死区内：速率回到基准（斜率变化，位置仍连续）。
    _rate = rate;
  }

  /// 把锚点挪到「当前投影位置」，保持位置连续（只改后续斜率）。
  void _rebase(int monoUs) {
    _anchorPos = positionAt(monoUs);
    _anchorMonoUs = monoUs;
  }

  /// 立即对齐到权威位置（seek / 卡顿恢复 / 暂停恢复）。
  void _hardResync(Duration position, int monoUs, bool paused, double rate) {
    _anchorPos = position < Duration.zero ? Duration.zero : position;
    _anchorMonoUs = monoUs;
    _paused = paused;
    _baseRate = rate;
    _rate = paused ? 0.0 : rate;
    _lastErrorMs = 0;
    _hardResyncCount++;
  }
}
