import 'package:himi_syncwatch/models/media_segment.dart';

/// 片段跳过判定（纯状态机，不依赖播放器）。
///
/// 规则对齐主流客户端：
/// - 仅在播放中、位置自然越过片段起点时触发；
/// - 手动 seek 进入片段不触发；
/// - 同一片段本次播放只提示一次；
/// - 短于 1 秒的片段不处理；短于 3 秒不弹询问；
/// - 手动片头 `[0, end]` 允许起播时已位于片段内立即提示。
class SegmentSkipController {
  static const int minSegmentMs = 1000;
  static const int minAskMs = 3000;
  static const int startToleranceMs = 1500;

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
  }) {
    _lastPositionMs = positionMs;
    for (final segment in segments) {
      if (segment.contains(positionMs)) _handled.add(segment.key);
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
      final last = _lastPositionMs;
      final crossedStart = last == null
          ? positionMs <= segment.startMs + startToleranceMs
          : last < segment.startMs && positionMs >= segment.startMs;
      final manualIntroInProgress = last == null &&
          segment.source == MediaSegmentSource.manual &&
          segment.type == MediaSegmentType.intro &&
          positionMs < segment.endMs;

      if (length < minSegmentMs || length < minAskMs) {
        _handled.add(segment.key);
        continue;
      }
      if (crossedStart || manualIntroInProgress) {
        _handled.add(segment.key);
        _lastPositionMs = positionMs;
        return segment;
      }
    }

    _lastPositionMs = positionMs;
    return null;
  }
}
