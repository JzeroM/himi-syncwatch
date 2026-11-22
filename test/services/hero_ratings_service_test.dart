import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';
import 'package:himi_syncwatch/services/hero_ratings_service.dart';
import 'package:himi_syncwatch/services/ratings_cache_store.dart';

void main() {
  /// API 全挂假件：_fetchDouban 的 API 层抛错 → 回落爬页（爬页组语义保持）。
  RatingsHttpPost _apiDown = (url, {headers = const {}, required form}) async {
    throw StateError('api down');
  };

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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
        httpGet: (url, {headers = const {}}) async {
          if (!url.host.endsWith('douban.com')) return '{}';
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
          if (url.host == 'api.douban.com') throw StateError('api down');
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
      // 698 N7-E：POST 目标 = 挑战宿主 sec.douban.com（真机实录——POST 到
      // movie 域 = 未解决挑战循环，永不发通行 cookie）。
      expect(postUrl.toString(), 'https://sec.douban.com/c');
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
        httpPost: _apiDown,
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
          if (url.host == 'api.douban.com') throw StateError('api down');
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

    test('表单 action 绝对 URL → 原样 POST（不硬编宿主）', () async {
      Uri? postUrl;
      var subjectCalls = 0;
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          if (url.host == 'movie.douban.com') {
            subjectCalls++;
            return subjectCalls == 1
                ? challengeHtml.replaceFirst(
                    'action="/c"', 'action="https://verify.douban.com/x"')
                : ratingHtml;
          }
          return '{}';
        },
        httpPost: (url, {headers = const {}, required form}) async {
          if (url.host == 'api.douban.com') throw StateError('api down');
          postUrl = url;
          return const RatingsHttpPostResult(setCookie: 'a=b');
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(doubanId: '3541415', tmdbScore: 8.0),
      );
      expect(badges, contains(const HeroRatingBadge(RatingPlatform.douban, '9.4')));
      expect(postUrl.toString(), 'https://verify.douban.com/x');
    });

    test('sec 轮未解掉 → 换请求宿主兜底再解一轮（698 N7-E）', () async {
      final postUrls = <String>[];
      var subjectCalls = 0;
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          if (url.host == 'movie.douban.com') {
            subjectCalls++;
            // 前两次都回挑战页：sec 轮后仍拦 → 触发宿主兜底轮。
            return subjectCalls <= 2 ? challengeHtml : ratingHtml;
          }
          return '{}';
        },
        httpPost: (url, {headers = const {}, required form}) async {
          if (url.host == 'api.douban.com') throw StateError('api down');
          postUrls.add(url.toString());
          return const RatingsHttpPostResult(setCookie: 'a=b');
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(doubanId: '3541415', tmdbScore: 8.0),
      );
      expect(badges, contains(const HeroRatingBadge(RatingPlatform.douban, '9.4')));
      expect(postUrls, [
        'https://sec.douban.com/c',
        'https://movie.douban.com/c',
      ], reason: 'sec 轮无效 → action 按请求宿主兜底再解');
    });

    test('搜索反爬空壳 → 源失败不缓存（自动重试，698 N7-E）', () async {
      var searchCalls = 0;
      final service = HeroRatingsService(
        httpPost: _apiDown,
        httpGet: (url, {headers = const {}}) async {
          if (url.host == 'search.douban.com') {
            searchCalls++;
            return '<html>empty shell</html>'; // 无 __DATA__/subject/「没有找到」
          }
          return '{}';
        },
      );
      const query = HeroRatingQuery(title: '盗梦空间', tmdbId: '603');
      final first = await service.fetch(query);
      expect(first, isEmpty, reason: '空壳不出徽章');
      final before = searchCalls;
      await service.fetch(query);
      expect(searchCalls, greaterThan(before),
          reason: '空壳 = 源失败，绝不缓存（下次自动重试）');
    });

    test('搜索真无匹配 → 缓存空（不再重查）', () async {
      var searchCalls = 0;
      final service = HeroRatingsService(
        httpPost: _apiDown,
        httpGet: (url, {headers = const {}}) async {
          if (url.host == 'search.douban.com') {
            searchCalls++;
            return '<script>window.__DATA__ = {"items":[]};</script>没有找到相关结果';
          }
          return '{}';
        },
      );
      const query = HeroRatingQuery(title: '不存在的片子xyz', tmdbId: '603');
      final first = await service.fetch(query);
      expect(first, isEmpty);
      await service.fetch(query);
      expect(searchCalls, 1, reason: '真无匹配缓存空（短 TTL），不重复搜索');
    });
  });

  group('Letterboxd 爬页（698 ② 免 key）', () {
    test('/imdb/{tt}/ 路由取分，5 分制 ×2', () async {
      final service = HeroRatingsService(
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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

    test('OMDb 串行限速（698 N7-F 队列分组：仅 key 源过队列）', () async {
      var omdbInFlight = 0;
      var omdbMaxInFlight = 0;
      final service = HeroRatingsService(
        httpPost: _apiDown,
        httpGet: (url, {headers = const {}}) async {
          if (!url.host.contains('omdbapi')) return '{}';
          omdbInFlight++;
          if (omdbInFlight > omdbMaxInFlight) omdbMaxInFlight = omdbInFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          omdbInFlight--;
          return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
        },
      );
      await Future.wait([
        service.fetch(const HeroRatingQuery(imdbId: 'tt1')),
        service.fetch(const HeroRatingQuery(imdbId: 'tt2')),
        service.fetch(const HeroRatingQuery(imdbId: 'tt3')),
      ]);
      expect(omdbMaxInFlight, 1, reason: 'OMDb 免费 key 串行限速');
    });

    test('双 id 皆缺：不发网络，仅种子徽章', () async {
      var httpCalls = 0;
      final service = HeroRatingsService(
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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

  group('评分行流式渐进（698 N7-F）', () {
    const query = HeroRatingQuery(imdbId: 'tt1', tmdbScore: 7.4);

    test('watch：种子首帧先出，逐源补位（帧单调递增）', () async {
      final service = HeroRatingsService(
        httpPost: _apiDown,
        httpGet: (url, {headers = const {}}) async {
          if (url.host.contains('omdbapi')) {
            return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
          }
          return '{}';
        },
      );
      final emissions = await service.watch(query).toList();
      expect(emissions.first.map((b) => b.platform), [RatingPlatform.tmdb],
          reason: '首帧 = 种子（不等网络）');
      expect(emissions.length, greaterThan(1), reason: '逐源补位多帧');
      expect(emissions.last.map((b) => b.platform), contains(RatingPlatform.imdb));
      for (var i = 1; i < emissions.length; i++) {
        expect(emissions[i].length, greaterThanOrEqualTo(emissions[i - 1].length),
            reason: '徽章只增不减');
      }
    });

    test('watch：慢源不挡快源（IMDb 先上，豆瓣落地再补）', () async {
      final doubanGate = Completer<String>();
      final service = HeroRatingsService(
        httpPost: _apiDown,
        httpGet: (url, {headers = const {}}) {
          if (url.host == 'movie.douban.com') return doubanGate.future;
          return Future.value(
              jsonEncode({'Response': 'True', 'imdbRating': '7.6'}));
        },
      );
      const slowQuery =
          HeroRatingQuery(imdbId: 'tt1', doubanId: '3541415', tmdbScore: 7.4);
      final emissions = <List<HeroRatingBadge>>[];
      final sub = service.watch(slowQuery).listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        emissions.expand((e) => e).map((b) => b.platform),
        contains(RatingPlatform.imdb),
        reason: '快源已上',
      );
      expect(
        emissions.last.map((b) => b.platform),
        isNot(contains(RatingPlatform.douban)),
        reason: '慢源（豆瓣）未落地前不陪等',
      );
      doubanGate.complete('<meta property="v:average" content="8.9">');
      await sub.asFuture<void>();
      expect(
        emissions.last.map((b) => b.platform),
        contains(RatingPlatform.douban),
      );
    });

    test('watch：会话缓存命中首帧即全量（零网络）', () async {
      var httpCalls = 0;
      final service = HeroRatingsService(
        httpPost: _apiDown,
        httpGet: (url, {headers = const {}}) async {
          httpCalls++;
          return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
        },
      );
      await service.fetch(query); // 全量并缓存
      final callsAfterFetch = httpCalls;
      final emissions = await service.watch(query).toList();
      expect(
        emissions.first.map((b) => b.platform),
        containsAll([RatingPlatform.tmdb, RatingPlatform.imdb]),
        reason: '缓存命中首帧即全量',
      );
      expect(httpCalls, callsAfterFetch, reason: 'watch 不重复打 HTTP');
    });
  });

  group('评分徽章缓存（698 N7-I：重复获取归零）', () {
    const query = HeroRatingQuery(imdbId: 'tt1', tmdbScore: 7.4);

    test('跨服务重建命中持久缓存（settings/trakt 变更不再重复获取）', () async {
      var httpCalls = 0;
      final store = MemoryRatingsCacheStore();
      String body() {
        httpCalls++;
        return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
      }

      final service1 = HeroRatingsService(
        httpPost: _apiDown,
        cacheStore: store,
        httpGet: (url, {headers = const {}}) async => body(),
      );
      final first = await service1.fetch(query);
      expect(first.map((b) => b.platform), contains(RatingPlatform.imdb));
      final callsAfterFirst = httpCalls;

      // 新服务实例（provider 重建语义）+ 同一 store：零网络出全量。
      final service2 = HeroRatingsService(
        httpPost: _apiDown,
        cacheStore: store,
        httpGet: (url, {headers = const {}}) async => body(),
      );
      final second = await service2.fetch(query);
      expect(httpCalls, callsAfterFirst, reason: '缓存命中零网络');
      expect(second.map((b) => b.platform), contains(RatingPlatform.imdb));
    });

    test('失败不缓存可重试（重建后同样重试）', () async {
      var httpCalls = 0;
      var fail = true;
      final store = MemoryRatingsCacheStore();
      final service = HeroRatingsService(
        httpPost: _apiDown,
        cacheStore: store,
        httpGet: (url, {headers = const {}}) async {
          httpCalls++;
          if (fail) throw StateError('net down');
          return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
        },
      );
      await service.fetch(query);
      fail = false;
      await service.fetch(query);
      expect(httpCalls, greaterThan(1), reason: '失败源自动重试');
      // 成功后进缓存：第三次零网络。
      final before = httpCalls;
      await service.fetch(query);
      expect(httpCalls, before);
    });

    test('TTL：有分 7 天有效，空结果 24h 重查', () async {
      var omdbCalls = 0;
      final store = MemoryRatingsCacheStore();
      final service = HeroRatingsService(
        httpPost: _apiDown,
        cacheStore: store,
        httpGet: (url, {headers = const {}}) async {
          if (url.host.contains('omdbapi')) omdbCalls++;
          return jsonEncode({'Response': 'True', 'imdbRating': '7.6'});
        },
      );
      // 有分 2 天前 → 未过期（7d）→ 命中。
      await store.write(
        'omdb:imdb:tt1',
        RatingsCacheEntry(
          badges: const [HeroRatingBadge(RatingPlatform.imdb, '7.6')],
          at: DateTime.now().subtract(const Duration(days: 2)),
          hasData: true,
        ),
      );
      await service.fetch(query);
      expect(omdbCalls, 0, reason: '有分 TTL 7 天内命中');

      // 空结果 2 天前 → 已过期（24h）→ 重查。
      await store.write(
        'omdb:imdb:tt2',
        RatingsCacheEntry(
          badges: const [],
          at: DateTime.now().subtract(const Duration(days: 2)),
          hasData: false,
        ),
      );
      await service.fetch(const HeroRatingQuery(imdbId: 'tt2'));
      expect(omdbCalls, 1, reason: '空结果 TTL 24h 后自动重查');
    });
  });

  group('HeroRatingsService.selfCheck（设置页测试按钮）', () {
    test('标准片自检：OMDb 三枚 + 爬页双枚', () async {
      final service = HeroRatingsService(
        httpPost: _apiDown,
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
        httpPost: _apiDown,
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
        httpPost: _apiDown,
        httpGet: (url, {headers = const {}}) async {
          throw StateError('blocked');
        },
      );
      final result = await service.selfCheck();
      expect(result.omdbError, '网络错误');
      expect(result.bridgeError, contains('反爬'));
    });
  });

  group('豆瓣 API（698 N14：api.douban.com v2 + Frodo 兜底）', () {
    RatingsHttpPost apiReply(String body) =>
        (url, {headers = const {}, required form}) async {
          if (url.host == 'api.douban.com') {
            return RatingsHttpPostResult(body: body);
          }
          throw StateError('unexpected post ${url.host}');
        };

    test('key 常量在位（用户拍板内置）+ Frodo 微信头', () {
      expect(HeroRatingsService.builtInDoubanAppKey, isNotEmpty);
      expect(HeroRatingsService.builtInFrodoKey, isNotEmpty);
      expect(HeroRatingsService.frodoHeaders['User-Agent'], 'MicroMessenger/',
          reason: '缺微信头 Frodo 报 997（真机实测）');
    });

    test('subject id 直查解析 rating.average（免反爬毫秒级）', () async {
      final posts = <String>[];
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          throw StateError('不应打 GET（API 直查命中）');
        },
        httpPost: (url, {headers = const {}, required form}) async {
          posts.add(url.toString());
          return RatingsHttpPostResult(
              body: jsonEncode({'rating': {'average': 9.4}}));
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(doubanId: '3541415'),
      );
      expect(posts.single, 'https://api.douban.com/v2/movie/subject/3541415');
      expect(badges, [const HeroRatingBadge(RatingPlatform.douban, '9.4')]);
    });

    test('imdb id 直查（average 字符串兼容）', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async => '{}',
        httpPost: apiReply(
            jsonEncode({'rating': {'average': '8.8'}})),
      );
      final badges =
          await service.fetch(const HeroRatingQuery(imdbId: 'tt1'));
      expect(badges, [const HeroRatingBadge(RatingPlatform.douban, '8.8')]);
    });

    test('搜索匹配：标题+年份命中出分；不相似宁缺勿错', () async {
      String searchBody(List<Map<String, Object?>> subjects) =>
          jsonEncode({'subjects': subjects});
      // 命中。
      var service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async => '{}',
        httpPost: apiReply(searchBody([
          {
            'title': '盗梦空间',
            'year': '2010',
            'rating': {'average': 9.4},
          },
          {
            'title': '完全不相干',
            'year': '1999',
            'rating': {'average': 1.0},
          },
        ])),
      );
      var badges = await service.fetch(
        const HeroRatingQuery(title: '盗梦空间', year: '2010', tmdbId: '603'),
      );
      expect(badges, [const HeroRatingBadge(RatingPlatform.douban, '9.4')]);

      // 不相似（低分候选也不认）。
      service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async => '{}',
        httpPost: apiReply(searchBody([
          {'title': '完全不相干', 'year': '1999', 'rating': {'average': 1.0}},
        ])),
      );
      badges = await service
          .fetch(const HeroRatingQuery(title: '盗梦空间', tmdbId: '603'));
      expect(badges, isEmpty);
    });

    test('v2 搜索无匹配 → Frodo 兜底（微信头 + rating.value）', () async {
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          expect(url.host, 'frodo.douban.com');
          expect(headers['User-Agent'], 'MicroMessenger/');
          return jsonEncode({
            'items': [
              {
                'target': {
                  'title': '盗梦空间',
                  'year': 2010,
                  'rating': {'value': 9.4},
                },
              },
            ],
          });
        },
        httpPost: apiReply(jsonEncode({'subjects': []})),
      );
      final badges = await service.fetch(
        const HeroRatingQuery(title: '盗梦空间', tmdbId: '603'),
      );
      expect(badges, [const HeroRatingBadge(RatingPlatform.douban, '9.4')]);
    });

    test('API 抛错回落爬页（PoW 挑战流保底）', () async {
      var posts = 0;
      final service = HeroRatingsService(
        httpGet: (url, {headers = const {}}) async {
          // 仅豆瓣宿主回爬页响应；其余源（Letterboxd 等）回空。
          if (url.host.endsWith('douban.com')) {
            return '<meta property="v:average" content="8.9">'; // 爬页直取
          }
          return '{}';
        },
        httpPost: (url, {headers = const {}, required form}) async {
          posts++;
          throw StateError('api down');
        },
      );
      final badges = await service.fetch(
        const HeroRatingQuery(doubanId: '3541415', tmdbId: '603'),
      );
      expect(posts, greaterThan(0), reason: 'API 先试');
      expect(badges, [const HeroRatingBadge(RatingPlatform.douban, '8.9')],
          reason: 'API 挂了爬页兜底出分');
    });

    test('评分边界：0 / 超 10 不出徽章', () async {
      for (final raw in [0, 11.0]) {
        final service = HeroRatingsService(
          httpGet: (url, {headers = const {}}) async => '{}',
          httpPost: apiReply(jsonEncode({'rating': {'average': raw}})),
        );
        final badges =
            await service.fetch(const HeroRatingQuery(doubanId: '3541415'));
        expect(badges, isEmpty, reason: 'average=$raw 非法不出分');
      }
    });
  });
}
