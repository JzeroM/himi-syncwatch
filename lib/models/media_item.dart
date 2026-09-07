class MediaStream {
  final String type;
  final String codec;
  final String? title;
  final String? language;
  final int? width;
  final int? height;
  final int? channels;
  final bool? isDefault;

  MediaStream({
    required this.type,
    required this.codec,
    this.title,
    this.language,
    this.width,
    this.height,
    this.channels,
    this.isDefault,
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
    );
  }

  String get displayInfo {
    switch (type) {
      case 'Video':
        if (width != null && height != null) return '$codec ${width}x$height';
        return codec;
      case 'Audio':
        final ch = channels != null ? '$channels ch' : '';
        final lang =
            language != null && language != 'und' ? ' $language' : '';
        final t = title != null && title!.isNotEmpty ? ' $title' : '';
        return '$codec$lang$t $ch'.trim();
      case 'Subtitle':
        return '$codec ${language ?? ''} ${title ?? ''}'.trim();
      default:
        return codec;
    }
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
    );
  }

  bool get isMovie => type == 'Movie';
  bool get isSeries => type == 'Series';
  bool get isEpisode => type == 'Episode';

  String? get runtimeText {
    if (runTimeTicks == null || runTimeTicks! <= 0) return null;
    final h = runTimeTicks! ~/ 36000000000;
    final m = (runTimeTicks! % 36000000000) ~/ 60000000;
    if (h > 0) return '$h h ${m}m';
    return '$m min';
  }
}
