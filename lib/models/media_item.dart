class MediaStream {
  final String type;
  final String codec;
  final String? title;
  final String? language;
  final int? width;
  final int? height;
  final int? channels;
  final bool? isDefault;
  final int index;
  final bool isForced;
  final bool isExternal;
  final String? displayTitle;
  final String? displayLanguage;
  final String? subtitleLocationType;
  final String? channelLayout;
  final int? bitRate;
  final int? sampleRate;
  final String? videoRange;
  final String? extendedVideoType;
  final String?
      extendedVideoSubType; // DV Profile: DoviProfile50/DoviProfile81 等

  /// Emby `VideoRangeType`（SDR/HDR10/HLG/DOVI）：比 `VideoRange`
  /// 可靠——strm/部分重封装项 `VideoRange` 常错标 SDR（1.1.187）。
  final String? videoRangeType;

  /// 色彩元数据（Emby 流字段）：bt2020+smpte2084 = HDR10，
  /// arib-std-b67 = HLG。VideoRange 缺失时兜底推断。
  final String? colorPrimaries;
  final String? colorSpace;
  final String? transferCharacteristics;

  // ---- 详情页「媒体信息」展示用（Emby 流字段）----
  final String? profile;
  final int? level;
  final int? bitDepth;
  final String? pixelFormat;
  final int? refFrames;
  final double? frameRate;
  final bool? isInterlaced;

  MediaStream({
    required this.type,
    required this.codec,
    this.title,
    this.language,
    this.width,
    this.height,
    this.channels,
    this.isDefault,
    this.index = 0,
    this.isForced = false,
    this.isExternal = false,
    this.displayTitle,
    this.displayLanguage,
    this.subtitleLocationType,
    this.channelLayout,
    this.bitRate,
    this.sampleRate,
    this.videoRange,
    this.extendedVideoType,
    this.extendedVideoSubType,
    this.videoRangeType,
    this.colorPrimaries,
    this.colorSpace,
    this.transferCharacteristics,
    this.profile,
    this.level,
    this.bitDepth,
    this.pixelFormat,
    this.refFrames,
    this.frameRate,
    this.isInterlaced,
  });

  factory MediaStream.fromJson(Map<String, dynamic> json) {
    return MediaStream(
      type: json['Type'] ?? '',
      codec: json['Codec'] ?? '',
      title: json['Title'],
      language: json['Language'],
      width: json['Width'],
      height: json['Height'],
      channels: json['Channels'],
      isDefault: json['IsDefault'],
      index: json['Index'] ?? 0,
      isForced: json['IsForced'] ?? false,
      isExternal: json['IsExternal'] ?? false,
      displayTitle: json['DisplayTitle'],
      displayLanguage: json['DisplayLanguage'],
      subtitleLocationType: json['SubtitleLocationType'],
      channelLayout: json['ChannelLayout'],
      bitRate: json['BitRate'] as int?,
      sampleRate: json['SampleRate'] as int?,
      videoRange: json['VideoRange'],
      extendedVideoType: json['ExtendedVideoType'],
      extendedVideoSubType: json['ExtendedVideoSubType'],
      videoRangeType: json['VideoRangeType'],
      colorPrimaries: json['ColorPrimaries'],
      colorSpace: json['ColorSpace'],
      transferCharacteristics: json['TransferCharacteristics'],
      profile: json['Profile'],
      level: json['Level'] as int?,
      bitDepth: json['BitDepth'] as int?,
      pixelFormat: json['PixelFormat'],
      refFrames: json['RefFrames'] as int?,
      frameRate: ((json['RealFrameRate'] ?? json['AverageFrameRate']) as num?)
          ?.toDouble(),
      isInterlaced: json['IsInterlaced'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Type': type,
      'Codec': codec,
      if (title != null) 'Title': title,
      if (language != null) 'Language': language,
      if (width != null) 'Width': width,
      if (height != null) 'Height': height,
      if (channels != null) 'Channels': channels,
      if (isDefault != null) 'IsDefault': isDefault,
      'Index': index,
      'IsForced': isForced,
      'IsExternal': isExternal,
      if (displayTitle != null) 'DisplayTitle': displayTitle,
      if (displayLanguage != null) 'DisplayLanguage': displayLanguage,
      if (subtitleLocationType != null)
        'SubtitleLocationType': subtitleLocationType,
      if (channelLayout != null) 'ChannelLayout': channelLayout,
      if (bitRate != null) 'BitRate': bitRate,
      if (sampleRate != null) 'SampleRate': sampleRate,
      if (videoRange != null) 'VideoRange': videoRange,
      if (extendedVideoType != null) 'ExtendedVideoType': extendedVideoType,
      if (extendedVideoSubType != null)
        'ExtendedVideoSubType': extendedVideoSubType,
      if (videoRangeType != null) 'VideoRangeType': videoRangeType,
      if (colorPrimaries != null) 'ColorPrimaries': colorPrimaries,
      if (colorSpace != null) 'ColorSpace': colorSpace,
      if (transferCharacteristics != null)
        'TransferCharacteristics': transferCharacteristics,
    };
  }

  bool get isTextSubtitle => type == 'Subtitle';
  bool get isInternalStream => subtitleLocationType == 'InternalStream';

  /// 杜比视界检测（ExtendedVideoType 或 VideoRangeType=DOVI）
  bool get isDolbyVision =>
      extendedVideoType == 'DolbyVision' ||
      (videoRangeType?.toUpperCase() == 'DOVI');

  /// 传输特性是否 PQ（HDR10 信号）：smpte2084/st2084。
  bool get _transferIsPQ {
    final t = (transferCharacteristics ?? '').toLowerCase();
    return t.contains('smpte2084') || t.contains('st2084');
  }

  /// 传输特性是否 HLG：arib-std-b67。
  bool get _transferIsHLG =>
      (transferCharacteristics ?? '').toLowerCase().contains('arib-std-b67');

  /// HDR 类型检测（HDR10/Dolby Vision）。
  ///
  /// 分层判定（1.1.187）：DV → VideoRangeType → VideoRange → 传输特性。
  /// strm/部分重封装项 `VideoRange` 常错标 SDR，`VideoRangeType` 与
  /// `TransferCharacteristics`（smpte2084=HDR10）更可靠。
  /// HLG 不计入（历史语义，路由决策只针对 HDR10/DV 直写 wedge）。
  bool get isHDR =>
      isDolbyVision ||
      const {'HDR10', 'HDR10PLUS', 'PQ'}
          .contains(videoRangeType?.toUpperCase()) ||
      videoRange == 'HDR' ||
      videoRange == 'PQ' ||
      _transferIsPQ;

  /// HDR 类型标签（含 HLG 展示）。
  String get hdrLabel {
    if (isDolbyVision) {
      if (extendedVideoSubType == 'DoviProfile50') return 'Dolby Vision P5';
      if (extendedVideoSubType == 'DoviProfile76') return 'Dolby Vision P7';
      if (extendedVideoSubType == 'DoviProfile81') return 'Dolby Vision P8';
      if (extendedVideoSubType == 'DoviProfile84') return 'Dolby Vision P8.4';
      return 'Dolby Vision';
    }
    final vrt = videoRangeType?.toUpperCase();
    if (vrt == 'HDR10PLUS') return 'HDR10+';
    if (vrt == 'HDR10' || vrt == 'PQ') return 'HDR10';
    if (videoRange == 'HDR' || videoRange == 'PQ') return 'HDR10';
    if (_transferIsPQ) return 'HDR10';
    if (vrt == 'HLG' || videoRange == 'HLG' || _transferIsHLG) return 'HLG';
    return 'SDR';
  }

  /// DV Profile 5 检测（单层，IPT-PQ 色彩空间，需要特殊处理）
  bool get isDolbyVisionProfile5 =>
      isDolbyVision && extendedVideoSubType?.contains('Profile50') == true;

  String get displayInfo {
    if (displayTitle != null && displayTitle!.isNotEmpty) {
      return displayTitle!;
    }
    switch (type) {
      case 'Video':
        if (width != null && height != null) return '$codec ${width}x$height';
        return codec;
      case 'Audio':
        final ch = channelLayout ?? (channels != null ? '$channels ch' : '');
        final lang = language != null && language != 'und' ? ' $language' : '';
        final t = title != null && title!.isNotEmpty ? ' $title' : '';
        return '$codec$lang$t $ch'.trim();
      case 'Subtitle':
        final lang = displayLanguage ?? language ?? '';
        final forced = isForced ? ' (forced)' : '';
        return '$lang (${codec.toUpperCase()})$forced'.trim();
      default:
        return codec;
    }
  }

  String get label {
    final lang = displayLanguage ?? language ?? '';
    if (lang.isEmpty || lang == 'und') return codec.toUpperCase();
    return lang;
  }
}

class MediaSource {
  final String id;
  final String name;
  final String? path;
  final int? width;
  final int? height;
  final String? container;
  final int? size;
  final List<MediaStream> mediaStreams;
  final int? defaultAudioStreamIndex;
  final int? defaultSubtitleStreamIndex;

  MediaSource({
    required this.id,
    required this.name,
    this.path,
    this.width,
    this.height,
    this.container,
    this.size,
    this.mediaStreams = const [],
    this.defaultAudioStreamIndex,
    this.defaultSubtitleStreamIndex,
  });

  factory MediaSource.fromJson(Map<String, dynamic> json) {
    return MediaSource(
      id: json['Id'] ?? '',
      name: json['Name'] ?? '',
      path: json['Path'],
      width: json['Width'],
      height: json['Height'],
      container: json['Container'],
      size: json['Size'] as int?,
      mediaStreams: (json['MediaStreams'] as List<dynamic>?)
              ?.map((s) => MediaStream.fromJson(s))
              .toList() ??
          [],
      defaultAudioStreamIndex: json['DefaultAudioStreamIndex'] as int?,
      defaultSubtitleStreamIndex: json['DefaultSubtitleStreamIndex'] as int?,
    );
  }

  List<MediaStream> get audioStreams =>
      mediaStreams.where((s) => s.type == 'Audio').toList();

  List<MediaStream> get subtitleStreams =>
      mediaStreams.where((s) => s.type == 'Subtitle').toList();

  MediaStream? get videoStream =>
      mediaStreams.where((s) => s.type == 'Video').firstOrNull;

  MediaStream? get defaultAudioStream {
    if (defaultAudioStreamIndex == null) return audioStreams.firstOrNull;
    return audioStreams
        .where((s) => s.index == defaultAudioStreamIndex)
        .firstOrNull;
  }

  MediaStream? get defaultSubtitleStream {
    if (defaultSubtitleStreamIndex == null) return null;
    return subtitleStreams
        .where((s) => s.index == defaultSubtitleStreamIndex)
        .firstOrNull;
  }

  String get displayLabel {
    final parts = <String>[name];
    if (width != null) {
      if (width! >= 3840) {
        parts.add('4K');
      } else if (width! >= 1920) {
        parts.add('1080p');
      } else if (width! >= 1280) {
        parts.add('720p');
      } else {
        parts.add('${width}p');
      }
    }
    if (container != null) parts.add(container!);
    if (size != null) {
      final gb = size! / (1024 * 1024 * 1024);
      parts.add('${gb.toStringAsFixed(1)} GB');
    }
    return parts.join(' · ');
  }
}

/// 外部链接（IMDb/TMDb/TVDB…）。
class ExternalUrl {
  const ExternalUrl({required this.name, required this.url});

  final String name;
  final String url;
}

class MediaItem {
  final String id;
  final String name;
  final String? overview;
  final String? posterUrl;
  final String? backdropUrl;

  /// 标题艺术字图（`ImageTags.Logo`，透明宽幅 PNG）；无 Logo 资源为 null。
  final String? logoUrl;
  final String? year;
  final String? officialRating;
  final double? communityRating;
  final String type;
  final String? seriesName;
  final int? indexNumber;
  final int? parentIndexNumber;
  final List<String> genres;
  final int? runTimeTicks;
  final List<MediaStream> mediaStreams;
  final int? childCount;
  final double? primaryImageAspectRatio;
  final List<MediaSource> mediaSources;

  /// 首播/上映日期（`PremiereDate` ISO 字符串），剧集卡展示「2022年3月31日」用。
  final DateTime? premiereDate;

  /// 当前用户是否已收藏（Emby `UserData.IsFavorite`；收藏功能用）。
  final bool isFavorite;

  /// 当前用户是否已观看（Emby `UserData.Played`；标记已观看功能用）。
  final bool isWatched;

  /// 续播位置（毫秒；`UserData.PlaybackPositionTicks ÷ 10000`，缺省 0）。
  final int playbackPositionMs;

  /// 已观看百分比（0~100；`UserData.PlayedPercentage`，缺省 0）。
  final double playedPercentage;

  /// 外部链接（Emby `ExternalUrls`：Name/Url，如 IMDb/TMDb/TVDB）。
  final List<ExternalUrl> externalUrls;

  /// 外部 id（Emby `ProviderIds`：Imdb/Tmdb/Tvdb…）。
  final Map<String, String> providerIds;

  /// 工作室（Emby `Studios[].Name`）。
  final List<String> studios;

  /// 文件路径（Emby `Path`；详情页媒体信息展示）。
  final String? path;

  /// 入库时间（Emby `DateCreated`）。
  final DateTime? dateCreated;

  MediaItem({
    required this.id,
    required this.name,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.year,
    this.officialRating,
    this.communityRating,
    required this.type,
    this.seriesName,
    this.indexNumber,
    this.parentIndexNumber,
    this.genres = const [],
    this.runTimeTicks,
    this.mediaStreams = const [],
    this.childCount,
    this.primaryImageAspectRatio,
    this.mediaSources = const [],
    this.premiereDate,
    this.isFavorite = false,
    this.isWatched = false,
    this.playbackPositionMs = 0,
    this.playedPercentage = 0,
    this.externalUrls = const [],
    this.providerIds = const {},
    this.studios = const [],
    this.path,
    this.dateCreated,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json, {String? serverUrl}) {
    final baseUrl = serverUrl ?? '';

    String? buildUrl(String path) {
      if (baseUrl.isEmpty) return null;
      return '$baseUrl$path';
    }

    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    final backdropTags = json['BackdropImageTags'] as List<dynamic>?;

    final userData = json['UserData'] as Map<String, dynamic>?;
    return MediaItem(
      id: json['Id'] ?? '',
      name: json['Name'] ?? '',
      overview: json['Overview'],
      posterUrl: imageTags?['Primary'] != null
          ? buildUrl(
              '/Items/${json["Id"]}/Images/Primary?maxHeight=400&tag=${imageTags!['Primary']}')
          : null,
      backdropUrl: backdropTags != null && backdropTags.isNotEmpty
          ? buildUrl(
              '/Items/${json["Id"]}/Images/Backdrop?maxHeight=400&tag=${backdropTags[0]}')
          : null,
      logoUrl: imageTags?['Logo'] != null
          ? buildUrl(
              '/Items/${json["Id"]}/Images/Logo?tag=${imageTags!['Logo']}')
          : null,
      year: json['ProductionYear']?.toString(),
      officialRating: json['OfficialRating'],
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      type: json['Type'] ?? 'Movie',
      seriesName: json['SeriesName'],
      indexNumber: json['IndexNumber'],
      parentIndexNumber: json['ParentIndexNumber'],
      genres: (json['Genres'] as List<dynamic>?)?.cast<String>() ?? [],
      runTimeTicks: json['RunTimeTicks'] as int?,
      mediaStreams: (json['MediaStreams'] as List<dynamic>?)
              ?.map((s) => MediaStream.fromJson(s))
              .toList() ??
          [],
      childCount: json['ChildCount'] as int?,
      primaryImageAspectRatio:
          (json['PrimaryImageAspectRatio'] as num?)?.toDouble(),
      mediaSources: (json['MediaSources'] as List<dynamic>?)
              ?.map((s) => MediaSource.fromJson(s))
              .toList() ??
          [],
      premiereDate: DateTime.tryParse(json['PremiereDate'] as String? ?? ''),
      isFavorite: userData?['IsFavorite'] == true,
      isWatched: userData?['Played'] == true,
      playbackPositionMs:
          ((userData?['PlaybackPositionTicks'] as num?)?.toInt() ?? 0) ~/ 10000,
      playedPercentage:
          (userData?['PlayedPercentage'] as num?)?.toDouble() ?? 0,
      externalUrls: (json['ExternalUrls'] as List<dynamic>?)
              ?.map((e) => ExternalUrl(
                    name: (e as Map)['Name'] as String? ?? '',
                    url: e['Url'] as String? ?? '',
                  ))
              .where((e) => e.url.isNotEmpty)
              .toList() ??
          const [],
      providerIds: (json['ProviderIds'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v?.toString() ?? ''),
          ) ??
          const {},
      studios: (json['Studios'] as List<dynamic>?)
              ?.map((e) => (e as Map)['Name'] as String? ?? '')
              .where((n) => n.isNotEmpty)
              .toList() ??
          const [],
      path: json['Path'] as String?,
      dateCreated: DateTime.tryParse(json['DateCreated'] as String? ?? ''),
    );
  }

  bool get isMovie => type == 'Movie';
  bool get isSeries => type == 'Series';
  bool get isEpisode => type == 'Episode';
  bool get hasMultipleVersions => mediaSources.length > 1;

  String? get runtimeText {
    if (runTimeTicks == null || runTimeTicks! <= 0) return null;
    final h = runTimeTicks! ~/ 36000000000;
    final m = (runTimeTicks! % 36000000000) ~/ 60000000;
    if (h > 0) return '$h h ${m}m';
    return '$m min';
  }
}
