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

    test('容错（698）：Source 大小写/空格不敏感，数值格式宽松', () {
      final body = jsonEncode({
        'Response': 'True',
        'imdbRating': '7.6',
        'Ratings': [
          {'Source': ' rotten tomatoes ', 'Value': '69'},
          {'Source': 'METACRITIC', 'Value': '67'},
        ],
      });
      final badges = HeroRatingsService.parseOmdb(body);
      expect(badges, [
        const HeroRatingBadge(RatingPlatform.imdb, '7.6'),
        const HeroRatingBadge(RatingPlatform.rottenTomatoesCritic, '69%'),
        const HeroRatingBadge(RatingPlatform.metacritic, '67'),
      ]);
    });
  });

  group('parseMdblistAudience（698 爆米花指数 🍿）', () {
    test('ratings 对象形态：tomatoesaudience 数值', () {
      final body = jsonEncode({
        'ratings': {'tomatoesaudience': 91},
      });
      expect(HeroRatingsService.parseMdblistAudience(body), [
        const HeroRatingBadge(RatingPlatform.rottenTomatoesAudience, '91%'),
      ]);
    });

    test('ratings 对象形态：嵌套 {score: 91} 与 0–10 制换算', () {
      final body = jsonEncode({
        'ratings': {
          'tomatoesaudience': {'score': 91, 'votes': 100},
          'imdb': 8.8,
        },
      });
      expect(HeroRatingsService.parseMdblistAudience(body), [
        const HeroRatingBadge(RatingPlatform.rottenTomatoesAudience, '91%'),
      ]);

      // 0–10 制（9.1）→ 91%。
      final tenScale = jsonEncode({
        'ratings': {'tomatoesaudience': 9.1},
      });
      expect(HeroRatingsService.parseMdblistAudience(tenScale), [
        const HeroRatingBadge(RatingPlatform.rottenTomatoesAudience, '91%'),
      ]);
    });

    test('ratings 数组形态：source+type=audience（大小写/空格容错）', () {
      final body = jsonEncode([
        {'source': 'imdb', 'value': 8.8, 'score': 88},
        {
          'source': 'Rotten Tomatoes',
          'type': 'audience',
          'value': 9.1,
          'score': 91,
        },
        {
          'source': 'Rotten Tomatoes',
          'type': 'critic',
          'value': 8.7,
          'score': 87,
        },
      ]);
      // 优先 score（91%）；critic 行不混入。
      expect(HeroRatingsService.parseMdblistAudience(body), [
        const HeroRatingBadge(RatingPlatform.rottenTomatoesAudience, '91%'),
      ]);
    });

    test('数组形态：popcornmeter / audience 键名变体', () {
      final body = jsonEncode([
        {'source': 'popcornmeter', 'value': 85},
        {'name': 'audience_score', 'value': 88},
      ]);
      // 第一条命中即返回（85%）。
      expect(HeroRatingsService.parseMdblistAudience(body), [
        const HeroRatingBadge(RatingPlatform.rottenTomatoesAudience, '85%'),
      ]);
    });

    test('百分号文本值 / 无观众分 / 脏数据', () {
      final withPercent = jsonEncode({
        'ratings': {'tomatoesaudience': '84%'},
      });
      expect(HeroRatingsService.parseMdblistAudience(withPercent), [
        const HeroRatingBadge(RatingPlatform.rottenTomatoesAudience, '84%'),
      ]);

      expect(
        HeroRatingsService.parseMdblistAudience(jsonEncode({'ratings': {}})),
        isEmpty,
      );
      expect(
        () => HeroRatingsService.parseMdblistAudience('not-json'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('HeroRatingsService.fetch（按源缓存与降级）', () {
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

    test('源失败不缓存该源（下次重试）；成功源缓存不重复打（698 修复）', () async {
      var omdbCalls = 0;
      var failOmdb = true;
      final service = HeroRatingsService(
        omdbApiKey: 'k',
        traktRating: ({String? imdbId, String? tmdbId, required bool isMovie}) {
          throw StateError('trakt down');
        },
        httpGet: (url, {headers = const {}}) async {
          omdbCalls++;
          if (failOmdb) throw StateError('net down');
          return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
        },
      );
      // 第一次：omdb+trakt 失败 → 只剩种子，失败源不缓存。
      final first = await service.fetch(query);
      expect(first.single.platform, RatingPlatform.tmdb);
      expect(omdbCalls, 1);
      // 第二次：omdb 重试成功（trakt 仍抛但不阻塞），IMDb 补位。
      failOmdb = false;
      final second = await service.fetch(query);
      expect(omdbCalls, 2);
      expect(
        second.map((b) => b.platform),
        containsAll([RatingPlatform.tmdb, RatingPlatform.imdb]),
      );
      // 第三次：omdb 成功已缓存（trakt 桥非 HTTP，不计数）。
      await service.fetch(query);
      expect(omdbCalls, 2);
    });

    test('部分失败只重试失败源，成功源不重复打（按源缓存）', () async {
      var omdbCalls = 0;
      var mdblistCalls = 0;
      var failMdblist = true;
      final service = HeroRatingsService(
        omdbApiKey: 'k',
        mdblistApiKey: 'm',
        httpGet: (url, {headers = const {}}) async {
          if (url.host.contains('omdbapi')) {
            omdbCalls++;
            return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
          }
          mdblistCalls++;
          if (failMdblist) throw StateError('mdb down');
          return jsonEncode({
            'ratings': {'tomatoesaudience': 91},
          });
        },
      );
      const fullQuery = HeroRatingQuery(
        imdbId: 'tt0133093',
        tmdbId: '603',
        tmdbScore: 7.4,
      );
      // 第一次：omdb 成功、mdblist 失败。
      final first = await service.fetch(fullQuery);
      expect(omdbCalls, 1);
      expect(mdblistCalls, 1);
      expect(
        first.map((b) => b.platform),
        isNot(contains(RatingPlatform.rottenTomatoesAudience)),
      );
      // 第二次：只重试 mdblist（omdb 已缓存）。
      failMdblist = false;
      final second = await service.fetch(fullQuery);
      expect(omdbCalls, 1, reason: '成功源不重复打');
      expect(mdblistCalls, 2, reason: '失败源自动重试');
      expect(
        second.map((b) => b.platform),
        contains(RatingPlatform.rottenTomatoesAudience),
      );
    });

    test('串行队列（698）：并发 fetch 不并发打 HTTP', () async {
      var inFlight = 0;
      var maxInFlight = 0;
      final service = HeroRatingsService(
        omdbApiKey: 'k',
        httpGet: (url, {headers = const {}}) async {
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
        },
      );
      await Future.wait([
        service.fetch(const HeroRatingQuery(imdbId: 'tt1')),
        service.fetch(const HeroRatingQuery(imdbId: 'tt2')),
        service.fetch(const HeroRatingQuery(imdbId: 'tt3')),
      ]);
      expect(maxInFlight, 1, reason: 'HTTP 请求服务内串行（防免费 key 并发限速）');
    });

    test('双 id 皆缺：不发网络，仅种子徽章', () async {
      var httpCalls = 0;
      final service = HeroRatingsService(
        omdbApiKey: 'k',
        mdblistApiKey: 'm',
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

    test('MDBList 只认 tt id（裸数字/缺 id 不发请求防串条目）', () async {
      var urls = <String>[];
      final service = HeroRatingsService(
        mdblistApiKey: 'm',
        httpGet: (url, {headers = const {}}) async {
          urls.add(url.toString());
          return jsonEncode({
            'ratings': {'tomatoesaudience': 80},
          });
        },
      );
      // 只有 TMDB id：不发 MDBList。
      await service.fetch(const HeroRatingQuery(tmdbId: '603'));
      expect(urls, isEmpty);
      // tt id：发 mdblist movie 面。
      await service.fetch(const HeroRatingQuery(imdbId: 'tt1'));
      expect(urls.single, contains('api.mdblist.com/movie/tt1/ratings'));
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

  group('HeroRatingsService.selfCheck（设置页测试按钮）', () {
    test('三源齐备的标准片自检 → 三枚徽章无错误', () async {
      final service = HeroRatingsService(
        omdbApiKey: 'k',
        mdblistApiKey: 'm',
        httpGet: (url, {headers = const {}}) async {
          if (url.host.contains('omdbapi')) {
            return jsonEncode({
              'Response': 'True',
              'imdbRating': '8.8',
              'Ratings': [
                {'Source': 'Rotten Tomatoes', 'Value': '79%'},
                {'Source': 'Metacritic', 'Value': '66/100'},
              ],
            });
          }
          return jsonEncode({
            'ratings': {'tomatoesaudience': 96},
          });
        },
      );
      final result = await service.selfCheck();
      expect(result.omdbError, isNull);
      expect(result.omdbBadges.map((b) => b.platform), [
        RatingPlatform.imdb,
        RatingPlatform.rottenTomatoesCritic,
        RatingPlatform.metacritic,
      ]);
      expect(result.mdblistError, isNull);
      expect(result.mdblistBadges, isNotEmpty);
    });

    test('key 错误透出 Response: False 的 Error 文案', () async {
      final service = HeroRatingsService(
        omdbApiKey: 'bad',
        httpGet: (url, {headers = const {}}) async {
          return jsonEncode({
            'Response': 'False',
            'Error': 'Invalid API key!',
          });
        },
      );
      final result = await service.selfCheck();
      expect(result.omdbError, 'Invalid API key!');
      expect(result.mdblistError, '未配置 MDBList Key');
    });

    test('未配 key 明示提示', () async {
      final service = HeroRatingsService();
      final result = await service.selfCheck();
      expect(result.omdbError, '未配置 OMDb Key');
      expect(result.mdblistError, '未配置 MDBList Key');
    });
  });
}
