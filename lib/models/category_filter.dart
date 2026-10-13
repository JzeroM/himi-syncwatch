/// 播放状态筛选（Emby `/Items` 的 `Filters` 参数子集）。
enum WatchStatusFilter {
  any('任意', null),
  watched('已播放', 'IsPlayed'),
  unwatched('未播放', 'IsUnplayed'),
  resumable('继续观看', 'IsResumable');

  final String label;
  final String? embyValue;
  const WatchStatusFilter(this.label, this.embyValue);
}

/// 筛选面板可选项（来自 Emby `GET /Items/Filters`）。
/// 某组为空时面板隐藏该行（服务端无该维度数据）。
class MediaFilterOptions {
  const MediaFilterOptions({
    this.genres = const [],
    this.years = const [],
    this.ratings = const [],
  });

  final List<String> genres;
  final List<int> years;
  final List<String> ratings;

  bool get hasGenres => genres.isNotEmpty;
  bool get hasYears => years.isNotEmpty;
  bool get hasRatings => ratings.isNotEmpty;
  bool get isEmpty => !hasGenres && !hasYears && !hasRatings;
}

/// 分类页 / 收藏页的服务端筛选条件（播放状态单选 + 类型/年份/分级多选）。
/// 多选维度为「或」语义，一次查询即可，无需多次合并。
class CategoryFilter {
  const CategoryFilter({
    this.watchStatus = WatchStatusFilter.any,
    this.genres = const {},
    this.years = const {},
    this.ratings = const {},
  });

  static const CategoryFilter empty = CategoryFilter();

  final WatchStatusFilter watchStatus;
  final Set<String> genres;
  final Set<int> years;
  final Set<String> ratings;

  bool get isEmpty =>
      watchStatus == WatchStatusFilter.any &&
      genres.isEmpty &&
      years.isEmpty &&
      ratings.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// `Filters` 参数增量（仅播放状态；收藏页会与 `IsFavorite` 合并）。
  String? get watchStatusParam => watchStatus.embyValue;

  /// `Genres` 参数：管道符分隔（Emby 约定）。
  String? get genresParam =>
      genres.isEmpty ? null : genres.join('|');

  /// `Years` 参数：逗号分隔（Emby 约定）。
  String? get yearsParam =>
      years.isEmpty ? null : years.join(',');

  /// `OfficialRatings` 参数：管道符分隔（Emby 约定）。
  String? get ratingsParam =>
      ratings.isEmpty ? null : ratings.join('|');

  CategoryFilter copyWith({
    WatchStatusFilter? watchStatus,
    Set<String>? genres,
    Set<int>? years,
    Set<String>? ratings,
  }) {
    return CategoryFilter(
      watchStatus: watchStatus ?? this.watchStatus,
      genres: genres ?? this.genres,
      years: years ?? this.years,
      ratings: ratings ?? this.ratings,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CategoryFilter &&
      other.watchStatus == watchStatus &&
      other.genres.length == genres.length &&
      other.genres.containsAll(genres) &&
      other.years.length == years.length &&
      other.years.containsAll(years) &&
      other.ratings.length == ratings.length &&
      other.ratings.containsAll(ratings);

  @override
  int get hashCode =>
      Object.hash(watchStatusHash, genresHash, yearsHash, ratingsHash);

  int get watchStatusHash => watchStatus.index;
  int get genresHash => Object.hashAllUnordered(genres);
  int get yearsHash => Object.hashAllUnordered(years);
  int get ratingsHash => Object.hashAllUnordered(ratings);
}
