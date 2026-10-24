import 'package:himi_syncwatch/models/emby_playback_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';

/// 依据 Emby 服务器阈值统一判定「已看完 / 可续播」的纯函数集合。
///
/// 「继续观看」栏本身信任服务器 `/Items/Resume`（服务器已按阈值计算），
/// 本类只用于 **客户端自行判断** 的场景：详情页目标集选择、续播按钮、
/// 自动连播前置判定等，保证与服务器口径一致。
class PlaybackRules {
  const PlaybackRules._();

  /// Emby ticks（100ns/单位）→ 秒。
  static int durationSeconds(MediaItem item) =>
      (item.runTimeTicks ?? 0) ~/ 10000000;

  /// 是否「已看完」：显式已观看标记，或进度百分比达到阈值上限。
  static bool isFinished(MediaItem item, EmbyPlaybackSettings s) {
    if (item.isWatched) return true;
    return resumePercentage(item) >= s.maxResumePct;
  }

  /// 续播百分比。服务器没返回 `PlayedPercentage` 时按位置/时长补算，
  /// 避免有 `PlaybackPositionTicks` 却完全不显示续播。
  static double resumePercentage(MediaItem item) {
    if (item.playedPercentage > 0) return item.playedPercentage;
    final positionMs = item.playbackPositionMs;
    final ticks = item.runTimeTicks;
    if (positionMs <= 0 || ticks == null || ticks <= 0) {
      return item.playedPercentage;
    }
    final durationMs = ticks ~/ 10000;
    if (durationMs <= 0) return item.playedPercentage;
    return (positionMs / durationMs * 100).clamp(0.0, 100.0);
  }

  /// 是否「可续播」：未标记已观看、有进度、未达上限、不低于下限、且时长够长。
  static bool isResumable(MediaItem item, EmbyPlaybackSettings s) {
    if (item.isWatched) return false;
    if (item.playbackPositionMs <= 0) return false;
    final pct = resumePercentage(item);
    if (pct >= s.maxResumePct) return false;
    if (pct < s.minResumePct) return false;
    // 时长未知时不据此拦截（服务器已按此时长过滤 Resume）。
    final ticks = item.runTimeTicks;
    if (ticks != null &&
        ticks > 0 &&
        ticks ~/ 10000000 < s.minResumeDurationSeconds) {
      return false;
    }
    return true;
  }
}
