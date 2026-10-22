import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';

/// TMDB 媒体类型（与 Emby 的 Movie/Series 一一对应）。
enum TmdbMediaType {
  movie('movie', '电影', 'Movie'),
  tv('tv', '剧集', 'Series');

  const TmdbMediaType(this.apiValue, this.label, this.embyType);

  final String apiValue;
  final String label;
  final String embyType;

  static TmdbMediaType? fromApi(String? value) {
    for (final type in values) {
      if (type.apiValue == value) return type;
    }
    return null;
  }
}

/// TMDB 条目（电影/剧集共用的最小字段集）。
class TmdbItem {
  const TmdbItem({
    required this.id,
    required this.type,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage,
    this.voteCount,
    this.popularity,
    this.genreIds = const [],
  });

  final int id;
  final TmdbMediaType type;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double? voteAverage;
  final int? voteCount;
  final double? popularity;
  final List<int> genreIds;

  String? get year {
    final date = releaseDate;
    if (date == null || date.length < 4) return null;
    return date.substring(0, 4);
  }

  String? posterUrl(String imageBase, {String size = 'w500'}) {
    final path = posterPath;
    if (path == null || path.isEmpty) return null;
    return '$imageBase/$size$path';
  }

  String? backdropUrl(String imageBase, {String size = 'w1280'}) {
    final path = backdropPath;
    if (path == null || path.isEmpty) return null;
    return '$imageBase/$size$path';
  }

  String get key => '${type.apiValue}:$id';

  factory TmdbItem.fromJson(
    Map<String, dynamic> json, {
    TmdbMediaType? fallbackType,
  }) {
    final rawType = json['media_type'] as String?;
    final type = TmdbMediaType.fromApi(rawType) ?? fallbackType;
    if (type == null) {
      throw const FormatException('TMDB 条目缺少 media_type');
    }
    return TmdbItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: type,
      title: (json['title'] ?? json['name'] ?? '').toString(),
      originalTitle:
          (json['original_title'] ?? json['original_name'])?.toString(),
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: (json['release_date'] ?? json['first_air_date'])?.toString(),
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      voteCount: (json['vote_count'] as num?)?.toInt(),
      popularity: (json['popularity'] as num?)?.toDouble(),
      genreIds: (json['genre_ids'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'media_type': type.apiValue,
        'title': title,
        'original_title': originalTitle,
        'overview': overview,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'release_date': releaseDate,
        'vote_average': voteAverage,
        'vote_count': voteCount,
        'popularity': popularity,
        'genre_ids': genreIds,
      };
}

/// TMDB 分页结果。
class TmdbPagedResult {
  const TmdbPagedResult({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalResults,
  });

  final List<TmdbItem> items;
  final int page;
  final int totalPages;
  final int totalResults;

  bool get hasMore => page < totalPages;

  factory TmdbPagedResult.fromJson(
    Map<String, dynamic> json, {
    TmdbMediaType? fallbackType,
  }) {
    final results = json['results'] as List<dynamic>? ?? const [];
    final items = <TmdbItem>[];
    for (final raw in results.whereType<Map>()) {
      try {
        final item = TmdbItem.fromJson(
          Map<String, dynamic>.from(raw),
          fallbackType: fallbackType,
        );
        if (item.id > 0) items.add(item);
      } on FormatException {
        // 趋势接口可能混入 person 等不支持的类型，跳过而不是整页失败。
      }
    }
    return TmdbPagedResult(
      items: items,
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      totalResults: (json['total_results'] as num?)?.toInt() ?? 0,
    );
  }
}

/// TMDB 条目在 Emby 中的落点（本地条目 + 来源服务器）。
class TmdbAvailability {
  const TmdbAvailability({
    required this.tmdb,
    required this.item,
    required this.server,
  });

  final TmdbItem tmdb;
  final MediaItem item;
  final EmbyServerConfig server;
}

/// 跨服务器继续观看条目。
class TmdbResumeEntry {
  const TmdbResumeEntry({required this.item, required this.server});

  final MediaItem item;
  final EmbyServerConfig server;

  String get dedupeKey {
    final tmdb = item.tmdbId;
    if (item.isEpisode) {
      if (tmdb != null) return 'e:$tmdb';
      return 'e:${item.seriesName ?? item.name}|'
          '${item.parentIndexNumber ?? 0}|${item.indexNumber ?? 0}';
    }
    if (tmdb != null) return '${item.type}:$tmdb';
    return '${item.type}:${item.name.trim().toLowerCase()}|${item.year ?? ''}';
  }

  DateTime? get playedAt => item.lastPlayedDate;
}

class TmdbResumeResult {
  const TmdbResumeResult({
    required this.entries,
    this.failedServerIds = const {},
  });

  final List<TmdbResumeEntry> entries;
  final Set<String> failedServerIds;
}

/// 首页 TMDB 栏目。
class TmdbSectionData {
  const TmdbSectionData({
    required this.key,
    required this.title,
    required this.items,
  });

  final String key;
  final String title;
  final List<TmdbAvailability> items;

  bool get isEmpty => items.isEmpty;
}

/// TMDB 首页聚合数据。
class TmdbHomeData {
  const TmdbHomeData({
    required this.configured,
    this.resume = const [],
    this.sections = const [],
    this.failedServerCount = 0,
    this.sectionsLoading = false,
  });

  const TmdbHomeData.unconfigured()
      : configured = false,
        resume = const [],
        sections = const [],
        failedServerCount = 0,
        sectionsLoading = false;

  final bool configured;
  final List<TmdbResumeEntry> resume;
  final List<TmdbSectionData> sections;
  final int failedServerCount;

  /// 栏目仍在渐进加载；此时不应把首页判定为「暂无内容」。
  final bool sectionsLoading;

  bool get isEmpty =>
      !sectionsLoading &&
      resume.isEmpty &&
      sections.every((s) => s.items.isEmpty);
}
