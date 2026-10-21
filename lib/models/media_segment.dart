/// 播放片段类型（与 Jellyfin MediaSegments / Emby ChapterMarkerType 对齐）。
enum MediaSegmentType {
  intro,
  outro,
  recap,
  preview,
  commercial,
  unknown,
}

/// 片段来源：手动标记优先级高于服务端章节。
enum MediaSegmentSource {
  manual,
  embyChapter,
}

/// Emby `Chapters[]` 的轻量模型。
class MediaChapter {
  const MediaChapter({
    required this.startMs,
    this.name = '',
    this.markerType = '',
  });

  final int startMs;
  final String name;
  final String markerType;

  factory MediaChapter.fromJson(Map<String, dynamic> json) {
    final startTicks = json['StartPositionTicks'];
    final startMs = startTicks is num ? startTicks.toInt() ~/ 10000 : 0;
    return MediaChapter(
      startMs: startMs < 0 ? 0 : startMs,
      name: json['Name'] as String? ?? '',
      markerType: json['MarkerType']?.toString() ?? '',
    );
  }
}

/// 一段可跳过的播放区间。
class MediaSegment {
  const MediaSegment({
    required this.type,
    required this.startMs,
    required this.endMs,
    required this.source,
  });

  final MediaSegmentType type;
  final int startMs;
  final int endMs;
  final MediaSegmentSource source;

  String get key => '${type.name}:$startMs:$endMs:${source.name}';

  bool contains(int positionMs) => positionMs >= startMs && positionMs < endMs;

  bool isValid(int durationMs) =>
      startMs >= 0 &&
      endMs > startMs &&
      (durationMs <= 0 || startMs < durationMs);

  MediaSegment clampTo(int durationMs) {
    if (durationMs <= 0) return this;
    return MediaSegment(
      type: type,
      startMs: startMs.clamp(0, durationMs),
      endMs: endMs.clamp(0, durationMs),
      source: source,
    );
  }
}

/// 手动标记的本地记录。剧集按 seriesId 共享，电影按 itemId。
class ManualSegmentRecord {
  const ManualSegmentRecord({
    required this.serverId,
    required this.providerIds,
    this.seriesId,
    this.itemId,
    this.introEndMs,
    this.creditsStartMs,
    required this.updatedAtMs,
  });

  final String serverId;
  final String? seriesId;
  final String? itemId;
  final Map<String, String> providerIds;

  /// 片头结束/正片开始位置；null = 未手动设置。
  final int? introEndMs;

  /// 片尾开始位置；null = 未手动设置。
  final int? creditsStartMs;

  final int updatedAtMs;

  String get key => '$serverId|${seriesId ?? itemId ?? ''}';

  bool get hasMarkers => introEndMs != null || creditsStartMs != null;

  static const Object _unset = Object();

  ManualSegmentRecord copyWith({
    Object? introEndMs = _unset,
    Object? creditsStartMs = _unset,
    int? updatedAtMs,
    String? seriesId,
    String? itemId,
    Map<String, String>? providerIds,
  }) {
    return ManualSegmentRecord(
      serverId: this.serverId,
      seriesId: seriesId ?? this.seriesId,
      itemId: itemId ?? this.itemId,
      providerIds: providerIds ?? this.providerIds,
      introEndMs:
          identical(introEndMs, _unset) ? this.introEndMs : introEndMs as int?,
      creditsStartMs: identical(creditsStartMs, _unset)
          ? this.creditsStartMs
          : creditsStartMs as int?,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'serverId': serverId,
        if (seriesId != null) 'seriesId': seriesId,
        if (itemId != null) 'itemId': itemId,
        'providerIds': providerIds,
        if (introEndMs != null) 'introEndMs': introEndMs,
        if (creditsStartMs != null) 'creditsStartMs': creditsStartMs,
        'updatedAtMs': updatedAtMs,
      };

  factory ManualSegmentRecord.fromJson(Map<String, dynamic> json) {
    return ManualSegmentRecord(
      serverId: json['serverId'] as String? ?? '',
      seriesId: json['seriesId'] as String?,
      itemId: json['itemId'] as String?,
      providerIds: (json['providerIds'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) ??
          const {},
      introEndMs: (json['introEndMs'] as num?)?.toInt(),
      creditsStartMs: (json['creditsStartMs'] as num?)?.toInt(),
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}
