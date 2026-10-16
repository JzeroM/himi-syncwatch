/// 跨设备时钟偏移估计（NTP-lite 往返握手）。
///
/// 观众发出 ping（本机时刻 `t1`），房主收到后回 pong（回显 `t1` + 房主
/// 发送时刻 `t2`），观众在 `t4` 收到。单程网络对称时：
///   offset = t2 - (t1 + t4) / 2   // hostClock - viewerClock（毫秒）
///   rtt    = t4 - t1
///
/// 用途：房主心跳里的 `ts` 用的是**房主系统时钟**，观众若直接用本机时钟
/// 相减，两台设备时钟差 `S` 秒会让纠偏目标恒偏 `S×rate`（表现为「房主与
/// 观众进度稳定差好几秒」）。校准后观众用 `本地时刻 + offset` 还原房主
/// 时钟，再算流逝时间，即可消除该恒定偏差。
///
/// 估计策略：对有效样本做 EMA 平滑（抑制网络抖动），同时记录最小 RTT
/// 供诊断。RTT 越小越接近真实偏移（往返不对称误差 ≤ rtt/2）。
class ClockOffsetEstimator {
  ClockOffsetEstimator({this.smoothing = 0.3});

  /// EMA 平滑系数（0..1，越大越跟随最新样本）。
  final double smoothing;

  double? _offsetMs;
  int? _bestRttMs;
  int _samples = 0;

  /// 是否已完成至少一次校准。
  bool get isCalibrated => _offsetMs != null;

  /// hostClock - viewerClock（毫秒）；未校准时为 null。
  double? get offsetMs => _offsetMs;

  /// 观测到的最小 RTT（毫秒）；未校准时为 null。
  int? get bestRttMs => _bestRttMs;

  /// 已采纳样本数。
  int get sampleCount => _samples;

  /// 提交一次往返样本。`t1`/`t4` 为观众本机毫秒，`t2` 为房主毫秒。
  /// 返回该样本是否被采纳（RTT 为负等异常值会被丢弃）。
  bool addSample({required int t1, required int t2, required int t4}) {
    final rtt = t4 - t1;
    if (rtt < 0) return false;

    final offset = t2 - (t1 + t4) / 2.0;
    if (_offsetMs == null) {
      _offsetMs = offset;
    } else {
      _offsetMs = _offsetMs! + smoothing * (offset - _offsetMs!);
    }
    if (_bestRttMs == null || rtt < _bestRttMs!) {
      _bestRttMs = rtt;
    }
    _samples++;
    return true;
  }

  /// 把本机时刻换算为房主时刻（毫秒）。
  int toHostClockMs(int localMs) =>
      _offsetMs == null ? localMs : (localMs + _offsetMs!).round();

  /// 重置（重新进房时调用）。
  void reset() {
    _offsetMs = null;
    _bestRttMs = null;
    _samples = 0;
  }
}
