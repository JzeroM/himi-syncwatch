import 'package:himi_syncwatch/models/media_item.dart';

/// 多平台评分徽章（首页轮播 / 详情页评分行）。
///
/// 显示顺序 = 枚举声明顺序（与参考截图一致：豆瓣 → TMDB → IMDb → 烂番茄
/// 影评/观众 → Letterboxd → Trakt，Metacritic 收尾）。
/// 豆瓣数据源待接入，接入前 [RatingPlatform.douban] 永不产出徽章。
enum RatingPlatform {
  douban('豆瓣'),
  tmdb('TMDB'),
  imdb('IMDb'),
  rottenTomatoesCritic('烂番茄影评'),
  rottenTomatoesAudience('烂番茄观众'),
  letterboxd('Letterboxd'),
  trakt('Trakt'),
  metacritic('Metacritic');

  const RatingPlatform(this.label);

  /// 中文名（无障碍语义 / 调试）。
  final String label;
}

/// 单枚评分徽章：平台 + 已格式化分数文本。
class HeroRatingBadge {
  const HeroRatingBadge(this.platform, this.display);

  final RatingPlatform platform;
  final String display;

  @override
  bool operator ==(Object other) =>
      other is HeroRatingBadge &&
      other.platform == platform &&
      other.display == display;

  @override
  int get hashCode => Object.hash(platform, display);

  @override
  String toString() => 'HeroRatingBadge(${platform.name}, $display)';
}

/// 分数 → 显示文本。
///
/// [score] 语义按平台不同：烂番茄影评/观众、Trakt、Metacritic 传 0–100；
/// 其余（豆瓣 / IMDb / TMDB / Letterboxd）传 0–10。
String formatRatingScore(RatingPlatform platform, double score) {
  switch (platform) {
    case RatingPlatform.rottenTomatoesCritic:
    case RatingPlatform.rottenTomatoesAudience:
    case RatingPlatform.trakt:
      return '${score.round()}%';
    case RatingPlatform.metacritic:
      return '${score.round()}';
    default:
      return score.toStringAsFixed(1);
  }
}

/// 评分查询参数（由 [MediaItem] 抽取，轮播/详情页共用）。
class HeroRatingQuery {
  const HeroRatingQuery({
    this.imdbId,
    this.tmdbId,
    this.isMovie = true,
    this.tmdbScore,
  });

  final String? imdbId;
  final String? tmdbId;
  final bool isMovie;

  /// TMDB 分（Emby `CommunityRating`），本地即得——首帧种子徽章用。
  final double? tmdbScore;

  factory HeroRatingQuery.fromMediaItem(MediaItem item) => HeroRatingQuery(
        imdbId: item.providerId('imdb'),
        tmdbId: item.tmdbId,
        isMovie: item.isMovie,
        tmdbScore: item.communityRating,
      );

  /// 首帧种子徽章（纯本地数据，不等网络）：TMDB 分来自 CommunityRating。
  List<HeroRatingBadge> get seedBadges => [
        if (tmdbScore != null && tmdbScore! > 0)
          HeroRatingBadge(
            RatingPlatform.tmdb,
            formatRatingScore(RatingPlatform.tmdb, tmdbScore!),
          ),
      ];

  /// 服务端缓存键（优先 IMDb id）；双 id 皆缺返回 null（不发网络请求）。
  String? get cacheKey {
    final imdb = imdbId?.trim();
    if (imdb != null && imdb.isNotEmpty) return 'imdb:$imdb';
    final tmdb = tmdbId?.trim();
    if (tmdb != null && tmdb.isNotEmpty) return 'tmdb:$tmdb';
    return null;
  }
}
