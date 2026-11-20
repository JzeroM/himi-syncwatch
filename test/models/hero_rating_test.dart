import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';
import 'package:himi_syncwatch/models/media_item.dart';

void main() {
  group('formatRatingScore：平台格式（698）', () {
    test('百分比平台（烂番茄影评/观众、Trakt）→ 整数百分比', () {
      expect(formatRatingScore(RatingPlatform.rottenTomatoesCritic, 69), '69%');
      expect(formatRatingScore(RatingPlatform.rottenTomatoesAudience, 85), '85%');
      expect(formatRatingScore(RatingPlatform.trakt, 75), '75%');
      expect(formatRatingScore(RatingPlatform.trakt, 75.4), '75%');
    });

    test('Metacritic → 整数（0–100）', () {
      expect(formatRatingScore(RatingPlatform.metacritic, 67), '67');
      expect(formatRatingScore(RatingPlatform.metacritic, 67.6), '68');
    });

    test('十分制平台（TMDB/IMDb/豆瓣/Letterboxd）→ 1 位小数', () {
      expect(formatRatingScore(RatingPlatform.tmdb, 7.4), '7.4');
      expect(formatRatingScore(RatingPlatform.imdb, 7.6), '7.6');
      expect(formatRatingScore(RatingPlatform.douban, 8.9), '8.9');
      expect(formatRatingScore(RatingPlatform.letterboxd, 7.6), '7.6');
      expect(formatRatingScore(RatingPlatform.tmdb, 8), '8.0');
    });
  });

  group('HeroRatingQuery（698）', () {
    test('fromMediaItem 抽取 imdb/tmdb id、型别与 TMDB 分', () {
      final item = MediaItem(
        id: 'm1',
        name: '影片',
        type: 'Movie',
        communityRating: 7.4,
        providerIds: const {'Imdb': 'tt0133093', 'Tmdb': '603'},
      );
      final query = HeroRatingQuery.fromMediaItem(item);
      expect(query.imdbId, 'tt0133093');
      expect(query.tmdbId, '603');
      expect(query.isMovie, isTrue);
      expect(query.tmdbScore, 7.4);
    });

    test('seedBadges：有 TMDB 分出 1 枚种子徽章，无分为空', () {
      const withScore = HeroRatingQuery(tmdbScore: 7.4);
      expect(withScore.seedBadges.length, 1);
      expect(withScore.seedBadges.single.platform, RatingPlatform.tmdb);
      expect(withScore.seedBadges.single.display, '7.4');

      const noScore = HeroRatingQuery();
      expect(noScore.seedBadges, isEmpty);
      // 非正分也不出徽章（Emby 脏数据防御）。
      const zeroScore = HeroRatingQuery(tmdbScore: 0);
      expect(zeroScore.seedBadges, isEmpty);
    });

    test('cacheKey：IMDb id 优先，其次 TMDB id，双缺为 null', () {
      const both = HeroRatingQuery(imdbId: 'tt1', tmdbId: '2');
      expect(both.cacheKey, 'imdb:tt1');
      const tmdbOnly = HeroRatingQuery(tmdbId: '2');
      expect(tmdbOnly.cacheKey, 'tmdb:2');
      const none = HeroRatingQuery();
      expect(none.cacheKey, isNull);
      // 空白 id 视同缺失。
      const blank = HeroRatingQuery(imdbId: '  ');
      expect(blank.cacheKey, isNull);
    });
  });

  group('HeroRatingBadge 相等性', () {
    test('同平台同分相等，便于测试断言', () {
      expect(
        const HeroRatingBadge(RatingPlatform.imdb, '7.6'),
        const HeroRatingBadge(RatingPlatform.imdb, '7.6'),
      );
      expect(
        const HeroRatingBadge(RatingPlatform.imdb, '7.6') ==
            const HeroRatingBadge(RatingPlatform.tmdb, '7.6'),
        isFalse,
      );
    });
  });
}
