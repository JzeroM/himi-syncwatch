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
    );
  }

  bool get isTextSubtitle => type == 'Subtitle';
  bool get isInternalStream => subtitleLocationType == 'InternalStream';

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
        final lang =
            language != null && language != 'und' ? ' $language' : '';
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

class MediaItem {
  final String id;
  final String name;
  final String? overview;
  final String? posterUrl;
  final String? backdropUrl;
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

  MediaItem({
    required this.id,
    required this.name,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
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
  });

  factory MediaItem.fromJson(Map<String, dynamic> json, {String? serverUrl}) {
    final baseUrl = serverUrl ?? '';

    String? buildUrl(String path) {
      if (baseUrl.isEmpty) return null;
      return '$baseUrl$path';
    }

    final imageTags = json['ImageTags'] as Map<String, dynamic>?;
    final backdropTags = json['BackdropImageTags'] as List<dynamic>?;

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
