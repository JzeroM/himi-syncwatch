import 'package:himi_syncwatch/models/media_segment.dart';

/// 将 Emby 章节标记与手动标记合并为可跳过片段。
///
/// 优先级：手动标记按类型完全覆盖章节（手动片头覆盖 Intro，手动片尾覆盖
/// Credits）。未被手动覆盖的类型继续使用章节。手动片头语义为
/// `[0, introEndMs]`（片头结束/正片开始），手动片尾为
/// `[creditsStartMs, durationMs]`。
class MediaSegmentResolver {
  MediaSegmentResolver._();

  static List<MediaSegment> resolve({
    required List<MediaChapter> chapters,
    required ManualSegmentRecord? manual,
    required int durationMs,
  }) {
    final segments = <MediaSegment>[];

    final manualIntro = manual?.introEndMs;
    if (manualIntro != null &&
        manualIntro > 0 &&
        (durationMs <= 0 || manualIntro < durationMs)) {
      final segment = MediaSegment(
        type: MediaSegmentType.intro,
        startMs: 0,
        endMs: manualIntro,
        source: MediaSegmentSource.manual,
      );
      if (segment.isValid(durationMs)) {
        segments.add(_clamp(segment, durationMs));
      }
    } else {
      segments.addAll(
          _fromChapters(chapters, durationMs, type: MediaSegmentType.intro));
    }

    final manualCredits = manual?.creditsStartMs;
    var manualCreditsUsed = false;
    if (manualCredits != null &&
        manualCredits > 0 &&
        durationMs > 0 &&
        manualCredits < durationMs) {
      final segment = MediaSegment(
        type: MediaSegmentType.outro,
        startMs: manualCredits,
        endMs: durationMs,
        source: MediaSegmentSource.manual,
      );
      if (segment.isValid(durationMs)) {
        segments.add(segment);
        manualCreditsUsed = true;
      }
    }
    if (!manualCreditsUsed) {
      segments.addAll(
          _fromChapters(chapters, durationMs, type: MediaSegmentType.outro));
    }

    segments.sort((a, b) => a.startMs.compareTo(b.startMs));
    return segments;
  }

  static MediaSegment _clamp(MediaSegment segment, int durationMs) {
    if (durationMs <= 0) return segment;
    return segment.clampTo(durationMs);
  }

  static List<MediaSegment> _fromChapters(
    List<MediaChapter> chapters,
    int durationMs, {
    required MediaSegmentType type,
  }) {
    if (chapters.isEmpty) return const [];
    final sorted = [...chapters]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (type == MediaSegmentType.intro) {
      return _introFromChapters(sorted, durationMs);
    }
    return _outroFromChapters(sorted, durationMs);
  }

  static List<MediaSegment> _introFromChapters(
    List<MediaChapter> sorted,
    int durationMs,
  ) {
    final result = <MediaSegment>[];
    int? startMs;
    for (final chapter in sorted) {
      final marker = _normalize(chapter.markerType);
      if (marker == 'introstart') {
        startMs = chapter.startMs;
      } else if (marker == 'introend') {
        final start = startMs;
        if (start != null && chapter.startMs > start) {
          final segment = MediaSegment(
            type: MediaSegmentType.intro,
            startMs: start,
            endMs: chapter.startMs,
            source: MediaSegmentSource.embyChapter,
          );
          if (segment.isValid(durationMs)) {
            result.add(_clamp(segment, durationMs));
          }
        }
        startMs = null;
      }
    }
    return result;
  }

  static List<MediaSegment> _outroFromChapters(
    List<MediaChapter> sorted,
    int durationMs,
  ) {
    final start = sorted
        .where((c) => _normalize(c.markerType) == 'creditsstart')
        .firstOrNull;
    if (start == null) return const [];
    final explicitEnd = sorted
        .where((c) =>
            _normalize(c.markerType) == 'creditsend' &&
            c.startMs > start.startMs)
        .firstOrNull;
    final endMs = explicitEnd?.startMs ?? durationMs;
    if (endMs <= start.startMs) return const [];
    final segment = MediaSegment(
      type: MediaSegmentType.outro,
      startMs: start.startMs,
      endMs: endMs,
      source: MediaSegmentSource.embyChapter,
    );
    if (!segment.isValid(durationMs)) return const [];
    return [_clamp(segment, durationMs)];
  }

  static String _normalize(String markerType) =>
      markerType.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
}
