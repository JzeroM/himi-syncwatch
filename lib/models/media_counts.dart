/// 媒体库计数统计（电影 / 电视剧 / 集）。
class MediaCounts {
  const MediaCounts({
    required this.movies,
    required this.series,
    required this.episodes,
  });

  final int movies;
  final int series;
  final int episodes;

  @override
  String toString() =>
      'MediaCounts(movies: $movies, series: $series, episodes: $episodes)';
}
