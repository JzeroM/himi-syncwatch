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
  });

  factory MediaItem.fromJson(Map<String, dynamic> json, {String? serverUrl}) {
    final baseUrl = serverUrl ?? '';

    return MediaItem(
      id: json['Id'] ?? '',
      name: json['Name'] ?? '',
      overview: json['Overview'],
      posterUrl: json['ImageTags']?['Primary'] != null && baseUrl.isNotEmpty
          ? '$baseUrl/Items/${json["Id"]}/Images/Primary?maxHeight=400&tag=${json['ImageTags']['Primary']}'
          : null,
      backdropUrl: json['ImageTags']?['Backdrop'] != null && baseUrl.isNotEmpty
          ? '$baseUrl/Items/${json["Id"]}/Images/Backdrop?maxHeight=300&tag=${json['ImageTags']['Backdrop']}'
          : null,
      year: json['ProductionYear']?.toString(),
      officialRating: json['OfficialRating'],
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      type: json['Type'] ?? 'Movie',
      seriesName: json['SeriesName'],
      indexNumber: json['IndexNumber'],
      parentIndexNumber: json['ParentIndexNumber'],
    );
  }

  bool get isMovie => type == 'Movie';
  bool get isSeries => type == 'Series';
  bool get isEpisode => type == 'Episode';
}
