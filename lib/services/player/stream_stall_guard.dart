/// 缓冲 watchdog 的「真卡死 vs 慢但在播」判定（纯函数，便于单测）。
///
/// 高码率内容 + 弱网下 mdk 会长期置位 `buffering`，但播放位置仍在推进
/// （降速播放）。此时若按状态位重载会清空缓冲、反复 seek，反而加剧卡顿
/// 并形成无界重载环。故以「播放位置是否推进」区分：
/// 推进幅度超过 [progressThresholdMs] 即视为仍在播放，不重载。
class StreamStallGuard {
  StreamStallGuard._();

  /// watchdog 武装后位置推进超过该值（ms）即判定为「仍在播放」。
  static const int progressThresholdMs = 500;

  /// [startPosMs] 为 watchdog 武装时的位置，[currentPosMs] 为当前采样位置。
  static bool progressed(int startPosMs, int currentPosMs) =>
      currentPosMs - startPosMs > progressThresholdMs;
}
