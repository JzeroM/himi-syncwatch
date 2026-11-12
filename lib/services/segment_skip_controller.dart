import 'package:himi_syncwatch/models/media_segment.dart';

/// 片段跳过判定（纯状态机，不依赖播放器）。
///
/// 规则对齐主流客户端：
/// - 仅在播放中、位置自然越过片段起点时触发；
/// - 手动 seek 进入片段不触发；
/// - 同一片段本次播放只提示一次；
/// - 短于 1 秒的片段不处理；短于 3 秒不弹询问；
/// - 片头需播放位置达到 3 秒后才提示（从片头中段续播也不例外）；
/// - 手动/章节片头 `[0, end]` 在跨过 3 秒门槛时补触发一次。
class SegmentSkipController {
  static const int minSegmentMs = 1000;
  static const int minAskMs = 3000;
  static const int startToleranceMs = 1500;

  /// 片头提示门槛，同时用于“前 3 秒不可设置片头”。
  static const int introGateMs = 3000;

  int? _lastPositionMs;
  final Set<String> _handled = {};

  void reset() {
    _lastPositionMs = null;
    _handled.clear();
  }

  /// seek 完成后重置越过基线；seek 落点所在片段视为已处理，避免弹提示。
  void onSeek({
    required int positionMs,
    required List<MediaSegment> segments,
    bool markOutroHandled = true,
  }) {
    _lastPositionMs = positionMs;
    for (final segment in segments) {
      if (markOutroHandled || segment.type != MediaSegmentType.outro) {
        if (segment.contains(positionMs)) _handled.add(segment.key);
      }
    }
  }

  /// 690：**切集/换源后重置基线**——片尾一律视为已处理。
  ///
  /// 【为什么需要】`reset()` 把 `_lastPositionMs` 清成 null，而
  /// `evaluate` 的 `outroInProgress` 分支只要「当前位置在片尾区间内」就
  /// 命中（不要求跨过起点）——切集后若落点恰好在片尾附近，会**立刻**冒出
  /// 「跳过片尾」（真机反馈：安卓/鸿蒙不会，切集后不该出现片尾提示）。
  ///
  /// 与 [onSeek] 的区别：那里只标记「落点所在」的片段；这里把**所有片尾
  /// 段**都标记为已处理，因为切集后用户本来就不在片尾（是新一集的片尾）。
  void beginEpisode({
    required int positionMs,
    required List<MediaSegment> segments,
  }) {
    _lastPositionMs = positionMs;
    for (final segment in segments) {
      // 690：**只标记片尾**。
      //
      // 【为什么不能连片头一起按 contains 标记】片头起点通常是 0，
      // 切集/首播的 startMs 也是 0 → `contains(0)` 恒真 → 片头被误标
      // 为「已处理」→ 跳过片头提示永不出现（真机回归）。
      //
      // 片头靠 3 秒门禁（`introGateMs`）自然延后，不需要在这里压制。
      if (segment.type == MediaSegmentType.outro) {
        _handled.add(segment.key);
      }
    }
  }

  /// 返回本次需要展示“跳过”提示的片段；null = 不触发。
  MediaSegment? evaluate({
    required int positionMs,
    required int durationMs,
    required bool playing,
    required bool enabled,
    required List<MediaSegment> segments,
  }) {
    if (!enabled || !playing || durationMs <= 0 || segments.isEmpty) {
      _lastPositionMs = positionMs;
      return null;
    }

    for (final segment in segments) {
      if (!segment.contains(positionMs) || _handled.contains(segment.key)) {
        continue;
      }
      final length = segment.endMs - segment.startMs;
      if (length < minSegmentMs || length < minAskMs) {
        _handled.add(segment.key);
        continue;
      }

      final last = _lastPositionMs;
      final introTooEarly =
          segment.type == MediaSegmentType.intro && positionMs < introGateMs;
      if (introTooEarly) continue;

      final crossedStart = last == null
          ? positionMs <= segment.startMs + startToleranceMs
          : last < segment.startMs && positionMs >= segment.startMs;
      // 片头起点多为 0：首次判定可能已越过起点，或在起播/续播时直接位于
      // 片头内。只要尚未跨过 3 秒门槛，就在达到门槛时补触发一次。
      final introInProgress = segment.type == MediaSegmentType.intro &&
          positionMs >= introGateMs &&
          positionMs < segment.endMs &&
          (last == null || last < introGateMs);
      final outroInProgress = segment.type == MediaSegmentType.outro &&
          positionMs >= segment.startMs &&
          positionMs < segment.endMs;

      if (crossedStart || introInProgress || outroInProgress) {
        _handled.add(segment.key);
        _lastPositionMs = positionMs;
        return segment;
      }
    }

    _lastPositionMs = positionMs;
    return null;
  }
}
