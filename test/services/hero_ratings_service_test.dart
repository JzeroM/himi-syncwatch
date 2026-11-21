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

  group('OMDb 内置 key（698 N3）', () {
    test('用户 key 为空 → 用内置 key 发请求', () async {
      final urls = <String>[];
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          urls.add(url.toString());
          return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
        },
      );
      await service.fetch(const HeroRatingQuery(imdbId: 'tt1'));
      expect(urls.any((u) => u.contains(HeroRatingsService.builtInOmdbKey)),
          isTrue);
    });

    test('用户 key 非空 → 覆盖内置 key', () async {
      final urls = <String>[];
      final service = HeroRatingsService(
        omdbApiKey: 'my-own-key',
        httpGet: (url, {headers = const {}}) async {
          urls.add(url.toString());
          return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
        },
      );
      await service.fetch(const HeroRatingQuery(imdbId: 'tt1'));
      expect(urls.any((u) => u.contains('my-own-key')), isTrue);
      expect(
        urls.any((u) => u.contains(HeroRatingsService.builtInOmdbKey)),
        isFalse,
      );
    });
  });

  group('豆瓣爬页（698 ② 免 key）', () {
    test('subject 页 JSON-LD 抽豆瓣分', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          expect(url.toString(), contains('movie.douban.com/subject/3541415'));
          return '<script type="application/ld+json">'
              '{"aggregateRating":{"ratingValue":"9.4"}}</script>';
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(doubanId: '3541415', tmdbScore: 8.0),
      );
      expect(badges, contains(
        const HeroRatingBadge(RatingPlatform.douban, '9.4'),
      ));
    });

    test('meta 降级：v:average 取分', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          return '<meta property="v:average" content="8.9">';
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(doubanId: '3541415', tmdbScore: 8.0),
      );
      expect(badges, contains(
        const HeroRatingBadge(RatingPlatform.douban, '8.9'),
      ));
    });

    test('搜索兜底：subject 候选 + 相似度匹配（宁缺勿错）', () async {
      final urls = <String>[];
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          urls.add(url.toString());
          if (url.host == 'search.douban.com') {
            return '<a href="https://movie.douban.com/subject/111/">搏击俱乐部</a>'
                '<a href="https://movie.douban.com/subject/222/">搏击俱乐部2</a>';
          }
          // subject 页。
          return '<script type="application/ld+json">'
              '{"aggregateRating":{"ratingValue":"8.8"}}</script>';
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(title: '搏击俱乐部', tmdbId: '603'),
      );
      expect(urls.first, contains('search.douban.com'));
      expect(urls.last, contains('subject/111'));
      expect(badges, contains(
        const HeroRatingBadge(RatingPlatform.douban, '8.8'),
      ));
    });

    test('搜索匹配不确定（相似度低）→ 不上徽章', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          return '<a href="https://movie.douban.com/subject/111/">完全不相干的片子</a>';
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(title: '搏击俱乐部', tmdbId: '603'),
      );
      expect(badges, isEmpty);
    });

    test('已有服务端刮削种子分 → 不爬页（省流量）', () async {
      var httpCalls = 0;
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          httpCalls++;
          return '';
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(doubanId: '3541415', doubanScore: 8.9),
      );
      expect(httpCalls, 0);
      expect(badges, contains(
        const HeroRatingBadge(RatingPlatform.douban, '8.9'),
      ));
    });
  });

  group('豆瓣反爬挑战流（698 N5-C）', () {
    const challengeHtml = '<html><body><form id="sec" method="POST" action="/c">'
        '<input type="hidden" id="tok" name="tok" value="TOK" />'
        '<input type="hidden" id="cha" name="cha" value="test-cha-130197" />'
        '<input type="hidden" id="sol" name="sol" value="" />'
        '<input type="hidden" id="red" name="red" value="https://movie.douban.com/subject/3541415/" />'
        '</form></body></html>';
    const ratingHtml = '<meta property="v:average" content="9.4">';

    test('挑战页 → 挖矿 POST /c → 携通行 cookie 重试取分', () async {
      var subjectCalls = 0;
      final getHeaders = <Map<String, String>>[];
      Uri? postUrl;
      Map<String, String>? postForm;
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          if (url.host == 'movie.douban.com') {
            subjectCalls++;
            getHeaders.add(headers);
            return subjectCalls == 1 ? challengeHtml : ratingHtml;
          }
          return '{}';
        },
        httpPost: (url, {headers = const {}, required form}) async {
          postUrl = url;
          postForm = form;
          return const RatingsHttpPostResult(
              setCookie: 'dbcl2="pass123"; Path=/; Domain=.douban.com');
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(doubanId: '3541415', tmdbScore: 8.0),
      );
      expect(
        badges,
        contains(const HeroRatingBadge(RatingPlatform.douban, '9.4')),
      );
      // POST /c 表单：tok/cha/red 透传，sol = 挖出的 nonce（秒解向量 = 1）。
      expect(postUrl.toString(), 'https://movie.douban.com/c');
      expect(postForm!['tok'], 'TOK');
      expect(postForm!['cha'], 'test-cha-130197');
      expect(postForm!['sol'], '1');
      expect(postForm!['red'], contains('/subject/3541415/'));
      // 重试 GET 携通行 cookie（只回 name=value 段）+ Referer + bid。
      final retryHeaders = getHeaders.last;
      expect(retryHeaders['Cookie'], contains('dbcl2="pass123"'));
      expect(retryHeaders['Cookie'], contains('bid='));
      expect(retryHeaders['Cookie'], isNot(contains('Domain=')),
          reason: 'Cookie 只回传 name=value 段');
      expect(retryHeaders['Referer'], 'https://movie.douban.com/');
    });

    test('豆瓣请求头：完整浏览器头组（UA/语言/Referer/bid Cookie）', () async {
      final headersSeen = <Map<String, String>>[];
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          headersSeen.add(headers);
          return ratingHtml;
        },
      );
      await service.fetch(const HeroRatingQuery(doubanId: '3541415'));
      final h = headersSeen.firstWhere((h) => h.containsKey('Referer'));
      expect(h['User-Agent'], contains('Mozilla/5.0'));
      expect(h['User-Agent'], contains('Chrome'));
      expect(h['Accept-Language'], contains('zh-CN'));
      expect(h['Referer'], 'https://movie.douban.com/');
      expect(h['Cookie'], startsWith('bid='));
    });

    test('重试仍被拦 → 源失败不缓存（下次 fetch 自动重试）', () async {
      var subjectCalls = 0;
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          if (url.host == 'movie.douban.com') {
            subjectCalls++;
            return challengeHtml; // 永远挑战页
          }
          return '{}';
        },
        httpPost: (url, {headers = const {}, required form}) async =>
            const RatingsHttpPostResult(setCookie: 'a=b'),
      );
      const query = HeroRatingQuery(doubanId: '3541415', tmdbScore: 8.0);
      final first = await service.fetch(query);
      expect(first.map((b) => b.platform), [RatingPlatform.tmdb],
          reason: '豆瓣源失败不产出徽章');
      final before = subjectCalls;
      await service.fetch(query);
      expect(subjectCalls, greaterThan(before),
          reason: '挑战失败不缓存，下次 fetch 自动重试');
    });

    test('挑战未回 Set-Cookie → 源失败（没换到通行凭证不算过）', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          return url.host == 'movie.douban.com' ? challengeHtml : '{}';
        },
        httpPost: (url, {headers = const {}, required form}) async =>
            const RatingsHttpPostResult(),
      );
      final badges = await service.fetch(
        const HeroRatingQuery(doubanId: '3541415', tmdbScore: 8.0),
      );
      expect(badges.map((b) => b.platform), [RatingPlatform.tmdb]);
    });

    test('selfCheck：豆瓣被拦 → doubanBlocked 如实报', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          if (url.host == 'movie.douban.com') return challengeHtml;
          if (url.host.contains('omdbapi')) {
            return jsonEncode({'Response': 'True', 'imdbRating': '8.8'});
          }
          return '<script type="application/ld+json">'
              '{"aggregateRating":{"ratingValue":"4.4"}}</script>';
        },
        httpPost: (url, {headers = const {}, required form}) async =>
            const RatingsHttpPostResult(setCookie: 'a=b'),
      );
      final result = await service.selfCheck();
      expect(result.doubanBlocked, isTrue);
      expect(result.bridgeError, isNull,
          reason: 'Letterboxd 正常取到，不算全挂');
      expect(result.bridgeBadges.map((b) => b.platform), [
        RatingPlatform.letterboxd,
      ]);
    });

    test('首请求即正常页 → 不打 POST（无挑战不挖矿）', () async {
      var postCalls = 0;
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          return url.host == 'movie.douban.com' ? ratingHtml : '{}';
        },
        httpPost: (url, {headers = const {}, required form}) async {
          postCalls++;
          return const RatingsHttpPostResult(setCookie: 'a=b');
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(doubanId: '3541415', tmdbScore: 8.0),
      );
      expect(postCalls, 0);
      expect(badges, contains(const HeroRatingBadge(RatingPlatform.douban, '9.4')));
    });
  });

  group('Letterboxd 爬页（698 ② 免 key）', () {
    test('/imdb/{tt}/ 路由取分，5 分制 ×2', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          if (url.host.contains('letterboxd')) {
            expect(url.toString(), contains('letterboxd.com/imdb/tt0133093'));
            return '<script type="application/ld+json">'
                '{"aggregateRating":{"ratingValue":"4.2"}}</script>';
          }
          return '{}'; // OMDb 等其他源空响应。
        },
      );
      final badges = await service
          .fetch(const HeroRatingQuery(imdbId: 'tt0133093'));
      expect(badges, contains(
        const HeroRatingBadge(RatingPlatform.letterboxd, '8.4'),
      ));
    });

    test('无 tt id 时走 /tmdb/{id}/ 路由', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          if (url.host.contains('letterboxd')) {
            expect(url.toString(), contains('letterboxd.com/tmdb/603'));
            return '<meta name="twitter:data2" content="4.4 average">';
          }
          return '{}';
        },
      );
      final badges = await service.fetch(const HeroRatingQuery(tmdbId: '603'));
      expect(badges, contains(
        const HeroRatingBadge(RatingPlatform.letterboxd, '8.8'),
      ));
    });

    test('缺 id / 解析不出 → 静默空', () async {
      var httpCalls = 0;
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          httpCalls++;
          return '<html>no rating</html>';
        },
      );
      expect(await service.fetch(const HeroRatingQuery()), isEmpty);
      expect(httpCalls, 0);
      expect(
        await service.fetch(const HeroRatingQuery(imdbId: 'tt1')),
        isEmpty,
      );
    });
  });

  group('HeroRatingsService.fetch（按源缓存与降级）', () {
    const query = HeroRatingQuery(imdbId: 'tt0133093', tmdbScore: 7.4);

    test('同条目二次 fetch 命中缓存（每源 HTTP 只打一次）', () async {
      final calls = <String, int>{};
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          calls[url.host] = (calls[url.host] ?? 0) + 1;
          return jsonEncode({
            'Response': 'True',
            'imdbRating': '7.6',
          });
        },
      );
      final first = await service.fetch(query);
      final second = await service.fetch(query);
      expect(calls['www.omdbapi.com'], 1);
      expect(calls['letterboxd.com'], 1);
      expect(first, second);
      expect(first.map((b) => b.display), contains('7.6'));
    });

    test('源失败不缓存该源（下次重试）；成功源缓存不重复打（698 修复）', () async {
      var omdbCalls = 0;
      var failOmdb = true;
      final service = HeroRatingsService(
        traktRating: ({String? imdbId, String? tmdbId, required bool isMovie}) {
          throw StateError('trakt down');
        },
        httpGet: (url, {headers = const {}}) async {
          if (url.host.contains('omdbapi')) {
            omdbCalls++;
            if (failOmdb) throw StateError('net down');
            return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
          }
          return '<html>no rating</html>';
        },
      );
      // 第一次：omdb+trakt 失败 → 只剩种子，失败源不缓存。
      final first = await service.fetch(query);
      expect(first.single.platform, RatingPlatform.tmdb);
      // 第二次：omdb 重试成功，IMDb 补位。
      failOmdb = false;
      final second = await service.fetch(query);
      expect(omdbCalls, 2);
      expect(
        second.map((b) => b.platform),
        containsAll([RatingPlatform.tmdb, RatingPlatform.imdb]),
      );
      // 第三次：omdb 成功已缓存。
      await service.fetch(query);
      expect(omdbCalls, 2);
    });

    test('部分失败只重试失败源（按源缓存）', () async {
      var omdbCalls = 0;
      var doubanCalls = 0;
      var failDouban = true;
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          if (url.host.contains('omdbapi')) {
            omdbCalls++;
            return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
          }
          if (url.host == 'movie.douban.com') {
            doubanCalls++;
            if (failDouban) throw StateError('douban down');
            return '<meta property="v:average" content="8.9">';
          }
          return '<html>no rating</html>';
        },
      );
      const fullQuery = HeroRatingQuery(
        imdbId: 'tt0133093',
        doubanId: '3541415',
        tmdbScore: 7.4,
      );
      // 第一次：omdb 成功、douban 失败。
      final first = await service.fetch(fullQuery);
      expect(omdbCalls, 1);
      expect(doubanCalls, 1);
      expect(first.map((b) => b.platform), isNot(contains(RatingPlatform.douban)));
      // 第二次：只重试 douban（omdb 已缓存）。
      failDouban = false;
      final second = await service.fetch(fullQuery);
      expect(omdbCalls, 1, reason: '成功源不重复打');
      expect(doubanCalls, 2, reason: '失败源自动重试');
      expect(second.map((b) => b.platform), contains(RatingPlatform.douban));
    });

    test('串行队列（698）：并发 fetch 不并发打 HTTP', () async {
      var inFlight = 0;
      var maxInFlight = 0;
      final service = HeroRatingsService(
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
      expect(maxInFlight, 1, reason: 'HTTP 请求服务内串行（防限速/爬站过密）');
    });

    test('双 id 皆缺：不发网络，仅种子徽章', () async {
      var httpCalls = 0;
      final service = HeroRatingsService(
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
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async => '{}',
        traktRating: ({String? imdbId, String? tmdbId, required bool isMovie}) {
          expect(imdbId, 'tt0133093');
          expect(isMovie, isTrue);
          return Future<double?>.value(7.5);
        },
      );
      final badges = await service.fetch(query);
      expect(badges, contains(
        const HeroRatingBadge(RatingPlatform.trakt, '75%'),
      ));

      final noTrakt = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async => '{}',
        traktRating: ({String? imdbId, String? tmdbId, required bool isMovie}) {
          return Future<double?>.value();
        },
      );
      final empty = await noTrakt.fetch(const HeroRatingQuery(imdbId: 'tt2', tmdbScore: 7.4));
      expect(empty.map((b) => b.platform), [RatingPlatform.tmdb]);
    });

    test('Trakt 桥异常按该源失败处理，不影响种子徽章', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async => '{}',
        traktRating: ({String? imdbId, String? tmdbId, required bool isMovie}) {
          throw StateError('trakt down');
        },
      );
      final badges = await service.fetch(query);
      expect(badges, contains(
        const HeroRatingBadge(RatingPlatform.tmdb, '7.4'),
      ));
    });
  });

  group('HeroRatingsService.selfCheck（设置页测试按钮）', () {
    test('标准片自检：OMDb 三枚 + 爬页双枚', () async {
      final service = HeroRatingsService(
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
          if (url.host == 'movie.douban.com') {
            return '<meta property="v:average" content="9.4">';
          }
          return '<script type="application/ld+json">'
              '{"aggregateRating":{"ratingValue":"4.4"}}</script>';
        },
      );
      final result = await service.selfCheck();
      expect(result.omdbError, isNull);
      expect(result.omdbBadges.map((b) => b.platform), [
        RatingPlatform.imdb,
        RatingPlatform.rottenTomatoesCritic,
        RatingPlatform.metacritic,
      ]);
      expect(result.bridgeError, isNull);
      expect(result.bridgeBadges.map((b) => b.platform), [
        RatingPlatform.douban,
        RatingPlatform.letterboxd,
      ]);
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
    });

    test('爬页全挂 → bridgeError 提示反爬/改版', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          throw StateError('blocked');
        },
      );
      final result = await service.selfCheck();
      expect(result.omdbError, '网络错误');
      expect(result.bridgeError, contains('反爬'));
    });
  });
}
