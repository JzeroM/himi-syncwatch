import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';
import 'package:himi_syncwatch/services/hero_ratings_service.dart';

void main() {
  group('parseOmdb（698 OMDb 一枚 key 三枚徽章）', () {
    test('imdbRating + Ratings[] 解析出 IMDb/烂番茄影评/Metacritic', () {
      final body = jsonEncode({
        'Response': 'True',
        'imdbRating': '7.6',
        'Ratings': [
          {'Source': 'Internet Movie Database', 'Value': '7.6/10'},
          {'Source': 'Rotten Tomatoes', 'Value': '69%'},
          {'Source': 'Metacritic', 'Value': '67/100'},
        ],
      });
      final badges = HeroRatingsService.parseOmdb(body);
      expect(badges, [
        const HeroRatingBadge(RatingPlatform.imdb, '7.6'),
        const HeroRatingBadge(RatingPlatform.rottenTomatoesCritic, '69%'),
        const HeroRatingBadge(RatingPlatform.metacritic, '67'),
      ]);
    });

    test('Response: False 静默返回空（不抛）', () {
      final body = jsonEncode({
        'Response': 'False',
        'Error': 'Incorrect IMDb ID.',
      });
      expect(HeroRatingsService.parseOmdb(body), isEmpty);
    });

    test('缺 Ratings 或部分源缺失时只出已有徽章', () {
      final body = jsonEncode({
        'Response': 'True',
        'imdbRating': '8.0',
        'Ratings': [
          {'Source': 'Rotten Tomatoes', 'Value': '91%'},
        ],
      });
      final badges = HeroRatingsService.parseOmdb(body);
      expect(badges.map((b) => b.platform), [
        RatingPlatform.imdb,
        RatingPlatform.rottenTomatoesCritic,
      ]);
    });

    test('N/A 分数与零分不产出徽章', () {
      final body = jsonEncode({
        'Response': 'True',
        'imdbRating': 'N/A',
        'Ratings': [
          {'Source': 'Rotten Tomatoes', 'Value': 'N/A'},
          {'Source': 'Metacritic', 'Value': '0/100'},
        ],
      });
      expect(HeroRatingsService.parseOmdb(body), isEmpty);
    });
  });

  group('parseSimkl（698 Simkl 徽章）', () {
    test('ratings.simkl.rating 解析（对象形态）', () {
      final body = jsonEncode({
        'type': 'movie',
        'ratings': {
          'simkl': {'rating': 6.4, 'votes': 100},
        },
      });
      expect(HeroRatingsService.parseSimkl(body), [
        const HeroRatingBadge(RatingPlatform.simkl, '6.4'),
      ]);
    });

    test('单元素数组形态兼容', () {
      final body = jsonEncode([
        {
          'ratings': {
            'simkl': {'rating': 8.25, 'votes': 10},
          },
        },
      ]);
      expect(HeroRatingsService.parseSimkl(body), [
        const HeroRatingBadge(RatingPlatform.simkl, '8.3'),
      ]);
    });

    test('无 simkl 评分 / 零分 → 空；畸形响应抛出（语义=源失败可重试）', () {
      expect(HeroRatingsService.parseSimkl('{}'), isEmpty);
      expect(
        HeroRatingsService.parseSimkl(jsonEncode({
          'ratings': {
            'simkl': {'rating': 0},
          },
        })),
        isEmpty,
      );
      expect(
        () => HeroRatingsService.parseSimkl('not-json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HeroRatingsService.fetch（缓存与降级）', () {
    const query = HeroRatingQuery(imdbId: 'tt0133093', tmdbScore: 7.4);

    test('未配 key 的源跳过：仅种子徽章，零 HTTP', () async {
      var httpCalls = 0;
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          httpCalls++;
          return '{}';
        },
      );
      final badges = await service.fetch(query);
      expect(badges, [
        const HeroRatingBadge(RatingPlatform.tmdb, '7.4'),
      ]);
      expect(httpCalls, 0);
    });

    test('同条目二次 fetch 命中缓存（HTTP 只打一次）', () async {
      var httpCalls = 0;
      final service = HeroRatingsService(
        omdbApiKey: 'k',
        httpGet: (url, {headers = const {}}) async {
          httpCalls++;
          return jsonEncode({
            'Response': 'True',
            'imdbRating': '7.6',
          });
        },
      );
      final first = await service.fetch(query);
      final second = await service.fetch(query);
      expect(httpCalls, 1);
      expect(first, second);
      expect(first.map((b) => b.display), contains('7.6'));
    });

    test('全源失败不缓存（下次重试）；部分成功即缓存', () async {
      var httpCalls = 0;
      var fail = true;
      final service = HeroRatingsService(
        omdbApiKey: 'k',
        simklApiKey: 's',
        // Trakt 桥恒抛 = 该源失败（三源全配，失败可判「全败」）。
        traktRating: ({String? imdbId, String? tmdbId, required bool isMovie}) {
          throw StateError('trakt down');
        },
        httpGet: (url, {headers = const {}}) async {
          httpCalls++;
          if (fail) throw StateError('net down');
          return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
        },
      );
      // 双 id 齐全：omdb + simkl 两源都会打 HTTP。
      const fullQuery = HeroRatingQuery(
        imdbId: 'tt0133093',
        tmdbId: '603',
        tmdbScore: 7.4,
      );
      // 第一次全败：只有种子，且不缓存（HTTP 打了 omdb+simkl 两次）。
      final first = await service.fetch(fullQuery);
      expect(first.single.platform, RatingPlatform.tmdb);
      expect(httpCalls, 2);
      // 第二次重试成功（缓存若在就不会发请求）。
      fail = false;
      final second = await service.fetch(fullQuery);
      expect(httpCalls, 4);
      expect(
        second.map((b) => b.platform),
        containsAll([RatingPlatform.tmdb, RatingPlatform.imdb]),
      );
      // 第三次命中缓存。
      await service.fetch(fullQuery);
      expect(httpCalls, 4);
    });

    test('双 id 皆缺：不发网络，仅种子徽章', () async {
      var httpCalls = 0;
      final service = HeroRatingsService(
        omdbApiKey: 'k',
        httpGet: (url, {headers = const {}}) async {
          httpCalls++;
          return '{}';
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(tmdbScore: 8.0),
      );
      expect(httpCalls, 0);
      expect(badges.single.platform, RatingPlatform.tmdb);
    });

    test('Trakt 评分桥：有分出 Trakt 徽章（百分比），无分跳过', () async {
      final withTrakt = HeroRatingsService(
        traktRating: ({String? imdbId, String? tmdbId, required bool isMovie}) {
          expect(imdbId, 'tt0133093');
          expect(isMovie, isTrue);
          return Future<double?>.value(7.5);
        },
      );
      final badges = await withTrakt.fetch(query);
      expect(badges, contains(
        const HeroRatingBadge(RatingPlatform.trakt, '75%'),
      ));

      final noTrakt = HeroRatingsService(
        traktRating: ({String? imdbId, String? tmdbId, required bool isMovie}) {
          return Future<double?>.value();
        },
      );
      final empty = await noTrakt.fetch(query);
      expect(empty.map((b) => b.platform), [RatingPlatform.tmdb]);
    });

    test('Trakt 桥异常按该源失败处理，不影响种子徽章', () async {
      final service = HeroRatingsService(
        traktRating: ({String? imdbId, String? tmdbId, required bool isMovie}) {
          throw StateError('trakt down');
        },
      );
      final badges = await service.fetch(query);
      expect(badges.single.platform, RatingPlatform.tmdb);
    });
  });
}
