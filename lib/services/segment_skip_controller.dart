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
