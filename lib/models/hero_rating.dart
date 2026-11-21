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
    this.doubanId,
    this.title,
    this.year,
    this.isMovie = true,
    this.tmdbScore,
    this.criticScore,
    this.doubanScore,
  });

  final String? imdbId;
  final String? tmdbId;

  /// 豆瓣 id（`ProviderIds.Douban`，中文刮削插件常写；爬页直查用）。
  final String? doubanId;

  /// 片名/年份（豆瓣搜索兜底的相似度匹配用，698 桥接）。
  final String? title;
  final String? year;
  final bool isMovie;

  /// TMDB 分（Emby `CommunityRating`），本地即得——首帧种子徽章用。
  final double? tmdbScore;

  /// 烂番茄影评分（Emby `CriticRating`，0–100），本地即得（698 字段挖掘）。
  final double? criticScore;

  /// 豆瓣分（Emby `CustomRating` 解析，0–10），本地即得（698 字段挖掘）。
  final double? doubanScore;

  factory HeroRatingQuery.fromMediaItem(MediaItem item) => HeroRatingQuery(
        imdbId: item.providerId('imdb'),
        tmdbId: item.tmdbId,
        doubanId: item.doubanId,
        title: item.name,
        year: item.year,
        isMovie: item.isMovie,
        tmdbScore: item.communityRating,
        criticScore: item.criticRating,
        doubanScore: item.doubanRating,
      );

  /// 首帧种子徽章（纯本地数据，不等网络）：TMDB 分（CommunityRating）、
  /// 烂番茄影评（CriticRating）、豆瓣（CustomRating 解析）——服务端刮削
  /// 字段挖掘（698），有哪枚出哪枚。
  List<HeroRatingBadge> get seedBadges => [
        if (tmdbScore != null && tmdbScore! > 0)
          HeroRatingBadge(
            RatingPlatform.tmdb,
            formatRatingScore(RatingPlatform.tmdb, tmdbScore!),
          ),
        if (criticScore != null && criticScore! > 0)
          HeroRatingBadge(
            RatingPlatform.rottenTomatoesCritic,
            formatRatingScore(RatingPlatform.rottenTomatoesCritic, criticScore!),
          ),
        if (doubanScore != null && doubanScore! > 0)
          HeroRatingBadge(
            RatingPlatform.douban,
            formatRatingScore(RatingPlatform.douban, doubanScore!),
          ),
      ];

  /// 服务端缓存键（IMDb → TMDB → 豆瓣 id 三级）；三级皆缺返回 null
  /// （不发网络请求）。豆瓣 id 兜底让「仅豆瓣刮削」条目也能爬页补分/反补
  /// tt id（698 ②）。
  String? get cacheKey {
    final imdb = imdbId?.trim();
    if (imdb != null && imdb.isNotEmpty) return 'imdb:$imdb';
    final tmdb = tmdbId?.trim();
    if (tmdb != null && tmdb.isNotEmpty) return 'tmdb:$tmdb';
    final douban = doubanId?.trim();
    if (douban != null && douban.isNotEmpty) return 'douban:$douban';
    return null;
  }
}
