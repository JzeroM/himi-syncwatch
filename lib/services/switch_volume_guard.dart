/// 换源音量守卫（切集静音回归修复）。
///
/// 回归链路：渐出把 `player.volume` 压到 0 后、渐入开始前的换源窗口内，
/// `onStateChanged` 把 `player.volume`（此时为 0）回写进 UI 音量 `_volume`，
/// 渐入目标读到 0 → 短路 → 永久静音且音量条归零（实测音量条显示 0、
/// 手动拖动可恢复，正是该污染的特征）。
///
/// 双保险：
/// 1. [canWriteBack]——渐变进行中或换源窗口内拒绝音量回写（污染源头）；
/// 2. [markFadeOutStart]/[fadeInTarget]——渐出前记录用户目标音量，
///    渐入与失败恢复一律以记录值为准，即使 `_volume` 已被历史数据
///    污染也能正确收敛。
///
/// 纯 Dart、无插件依赖，便于单测。
class SwitchVolumeGuard {
  double? _fadeTarget;

  /// 是否有未消费的目标音量记录（测试/取证用）。
  bool get hasPendingTarget => _fadeTarget != null;

  /// 渐出前记录用户目标音量（UI 音量的 0-1 形式）。
  void markFadeOutStart(double uiVolume) {
    _fadeTarget = uiVolume.clamp(0.0, 1.0);
  }

  /// 渐入/失败恢复的目标：记录值优先，未记录回退当前 UI 音量。
  double fadeInTarget(double uiVolume) =>
      _fadeTarget ?? uiVolume.clamp(0.0, 1.0);

  /// 换源窗口内是否允许把 `player.volume` 回写进 UI 音量。
  ///
  /// - [fading]：音量渐变进行中（`AudioFader.active`）；
  /// - [switching]：换源流程进行中（渐出完成→渐入完成，含 prepare/
  ///   texture 同步等无渐变覆盖的时段）。
  bool canWriteBack({required bool fading, required bool switching}) =>
      !fading && !switching;

  /// 换源流程结束（渐入完成 / 失败恢复 / 被新请求抢占），清除记录。
  void endSwitch() {
    _fadeTarget = null;
  }
}
