import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';
import 'package:himi_syncwatch/services/bridge_parsers.dart';

/// 拉取原始响应体（可注入便于测试；默认走 Dio）。
typedef RatingsHttpGet = Future<String> Function(
  Uri url, {
  Map<String, String> headers,
});

/// 评分源最小接口（[HeroRatingsService] 实现；测试可注入假实现）。
abstract class HeroRatingsSource {
  /// 取该条目的全部徽章（含种子分）；无数据返回空列表。
  Future<List<HeroRatingBadge>> fetch(HeroRatingQuery query);
}

/// Trakt 评分查询桥（由 TraktClient 适配；未登录/未命中返回 null）。
typedef TraktRatingLookup = Future<double?> Function({
  String? imdbId,
  String? tmdbId,
  required bool isMovie,
});

/// 自检结果（设置页「测试评分数据源」用；透出 key 错误文案）。
class HeroRatingsSelfCheck {
  const HeroRatingsSelfCheck({
    this.omdbBadges = const [],
    this.omdbError,
    this.bridgeBadges = const [],
    this.bridgeError,
  });

  final List<HeroRatingBadge> omdbBadges;
  final String? omdbError;
  final List<HeroRatingBadge> bridgeBadges;
  final String? bridgeError;
}

/// 多平台评分拼盘服务（698）：一次查询聚合各源徽章。
///
/// 数据源（缺哪枚隐藏哪枚，绝无空徽章）：
/// - **OMDb**（按 IMDb id）→ IMDb + 烂番茄影评 + Metacritic 三枚；
///   key 未配置时使用**内置免费 key**（698 N3），可被 `omdbApiKey` 覆盖；
/// - **Trakt**（`traktRating` 桥，连账号即亮）→ Trakt 一枚；
/// - **豆瓣爬页**（subject 页 / 搜索兜底，免 key）→ 豆瓣一枚
///   （已有服务端刮削种子分时不再爬，省流量）；
/// - **Letterboxd 爬页**（`/imdb/{tt}/`、`/tmdb/{id}/` 302→film 页，免 key）
///   → Letterboxd 一枚；
/// - 种子徽章（TMDB/🍅/豆瓣，见 [HeroRatingQuery.seedBadges]）本地即得、
///   平台去重时优先（服务端刮削 > 爬页补分）。
///
/// 预留（数据源待接入，接入即亮）：烂番茄观众（🍿）。
///
/// 可靠性（698 修复）：
/// - **按源缓存**：某源失败不缓存该源（下次 fetch 自动重试），成功源缓存
///   不重复打；
/// - **串行队列**：全部 HTTP 请求服务内排队（带抖动），防免费 key 并发
///   限速与爬站请求过密；
/// - 爬页失败静默（返回空成功），绝不影响其他徽章。
class HeroRatingsService implements HeroRatingsSource {
  HeroRatingsService({
    this.omdbApiKey = '',
    this.traktRating,
    RatingsHttpGet? httpGet,
    this.queueGap = Duration.zero,
  }) : _httpGet = httpGet ?? _dioGet;

  /// 内置 OMDb 免费 key（698 N3）：零配置即亮 IMDb/烂番茄/Metacritic 三枚。
  /// 用户配置的 `omdbApiKey` 非空时覆盖；被限流/吊销时换自己的 key。
  static const String builtInOmdbKey = 'bed542e5';

  /// 爬页 UA（豆瓣/Letterboxd 对非浏览器 UA 有风控，伪装浏览器）。
  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// 用户 key 为空时回退内置 key。
  String get _omdbKey =>
      omdbApiKey.trim().isEmpty ? builtInOmdbKey : omdbApiKey.trim();

  final String omdbApiKey;
  final TraktRatingLookup? traktRating;

  /// 串行队列相邻请求的最小间隔（生产传 ~150ms；测试传零）。
  final Duration queueGap;

  final RatingsHttpGet _httpGet;
  final Random _random = Random();

  /// 按源缓存：key = `${源}:${[HeroRatingQuery.cacheKey]}`。
  /// null 结果 = 该源失败（不缓存，下次重试）。
  final Map<String, Future<List<HeroRatingBadge>?>> _cache = {};

  /// 串行队列尾（HTTP 请求依次执行，防限速/爬站过密）。
  Future<void> _queue = Future<void>.value();

  /// 自检标准片：《盗梦空间》（IMDb/烂番茄/Metacritic 三源齐备；
  /// 豆瓣 subject 3541415、Letterboxd inception——film-bridge README 同款）。
  static const String selfCheckImdbId = 'tt1375666';
  static const String selfCheckDoubanId = '3541415';

  Future<T> _serialize<T>(Future<T> Function() job) {
    final result = _queue.then((_) => job());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// 队列内执行一次 HTTP 拉取（带请求间隔抖动）。
  Future<String> _get(Uri url, {Map<String, String> headers = const {}}) {
    return _serialize(() async {
      if (queueGap > Duration.zero) {
        await Future<void>.delayed(
          queueGap + Duration(milliseconds: _random.nextInt(120)),
        );
      }
      return _httpGet(url, headers: headers);
    });
  }

  static Future<String> _dioGet(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ));
    final response = await dio.getUri<String>(
      url,
      options: Options(headers: headers),
    );
    final code = response.statusCode ?? 0;
    if (code < 200 || code >= 300) {
      throw StateError('ratings http $code');
    }
    return response.data ?? '';
  }

  /// 取该条目的全部徽章：种子分 + 各远端源（按源缓存）。
  @override
  Future<List<HeroRatingBadge>> fetch(HeroRatingQuery query) async {
    final seed = query.seedBadges;
    final key = query.cacheKey;
    if (key == null) return seed;
    final results = await Future.wait([
      _cached('omdb', key, () => _fetchOmdb(query)),
      _cached('trakt', key, () => _fetchTrakt(query)),
      _cached('douban', key, () => _fetchDouban(query)),
      _cached('letterboxd', key, () => _fetchLetterboxd(query)),
    ]);
    return [...seed, for (final r in results) ...r];
  }

  /// 按源缓存取数：失败（null）不缓存 → 下次重试；成功（含空）缓存。
  Future<List<HeroRatingBadge>> _cached(
    String source,
    String key,
    Future<List<HeroRatingBadge>?> Function() run,
  ) async {
    final cacheKey = '$source:$key';
    var future = _cache[cacheKey];
    if (future == null) {
      future = run();
      _cache[cacheKey] = future;
    }
    final result = await future;
    if (result == null) {
      _cache.remove(cacheKey);
      return const [];
    }
    return result;
  }

  /// OMDb 一枚 key 拿三枚：IMDb + 烂番茄影评 + Metacritic。
  /// 网络/解析异常 → null（失败）；`Response: False` → 空。
  Future<List<HeroRatingBadge>?> _fetchOmdb(HeroRatingQuery query) async {
    final imdbId = query.imdbId?.trim();
    if (imdbId == null || imdbId.isEmpty) return const [];
    try {
      final body = await _get(
        Uri.parse('https://www.omdbapi.com/?apikey=$_omdbKey&i=$imdbId'),
      );
      return parseOmdb(body);
    } catch (_) {
      return null;
    }
  }

  /// Trakt 评分（0–10 → 百分比）。
  Future<List<HeroRatingBadge>?> _fetchTrakt(HeroRatingQuery query) async {
    final lookup = traktRating;
    if (lookup == null) return const [];
    try {
      final rating = await lookup(
        imdbId: query.imdbId,
        tmdbId: query.tmdbId,
        isMovie: query.isMovie,
      );
      if (rating == null || rating <= 0) return const [];
      return [
        HeroRatingBadge(
          RatingPlatform.trakt,
          formatRatingScore(RatingPlatform.trakt, rating * 10),
        ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// 豆瓣爬页（免 key）：subject 页直查 → 搜索兜底。
  ///
  /// 已有服务端刮削种子分（[HeroRatingQuery.doubanScore]）时不爬（种子优先，
  /// 省流量）。爬取失败静默返回空。
  Future<List<HeroRatingBadge>?> _fetchDouban(HeroRatingQuery query) async {
    if (query.doubanScore != null && query.doubanScore! > 0) return const [];
    try {
      String? subjectId = query.doubanId?.trim();
      subjectId = (subjectId == null || subjectId.isEmpty) ? null : subjectId;
      final title = query.title?.trim();

      if (subjectId == null && title != null && title.isNotEmpty) {
        subjectId = await _searchDouban(query);
      }
      if (subjectId == null) return const [];

      final html = await _get(
        Uri.parse('https://movie.douban.com/subject/$subjectId/'),
        headers: _browserHeaders,
      );
      final rating = BridgeParsers.extractRating(html);
      if (rating == null || rating <= 0 || rating > 10) return const [];
      return [
        HeroRatingBadge(
          RatingPlatform.douban,
          formatRatingScore(RatingPlatform.douban, rating),
        ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// 豆瓣搜索兜底：`subject_search` 候选 + film-bridge 相似度匹配（698 ②）。
  Future<String?> _searchDouban(HeroRatingQuery query) async {
    final title = query.title?.trim();
    if (title == null || title.isEmpty) return null;
    final year = BridgeParsers.parseYear(query.year);
    final searchUrl = Uri.parse(
      'https://search.douban.com/movie/subject_search'
      '?search_text=${Uri.encodeComponent(title)}&cat=1002',
    );
    final html = await _get(searchUrl, headers: _browserHeaders);
    final candidates = BridgeParsers.extractDoubanSubjects(html);
    String? bestId;
    var bestScore = 0.0;
    for (final c in candidates) {
      var score = BridgeParsers.titleSimilarity(title, c['title'] ?? '');
      // 年份一致小幅加权（标题相似但年份不同的重名条目防误配）。
      final cYear = BridgeParsers.parseYear(c['title']);
      if (year != null && cYear == year) score += 0.15;
      if (score > bestScore) {
        bestScore = score;
        bestId = c['id'];
      }
    }
    // 阈值 0.6：宁缺勿错（匹配不确定就不上徽章）。
    return bestScore >= 0.6 ? bestId : null;
  }

  /// Letterboxd 爬页（免 key）：`/imdb/{tt}/` 或 `/tmdb/{id}/` 302 → film 页，
  /// JSON-LD 抽评分（0–5 → ×2 得 0–10）。
  Future<List<HeroRatingBadge>?> _fetchLetterboxd(HeroRatingQuery query) async {
    try {
      final imdbId = query.imdbId?.trim();
      final tmdbId = query.tmdbId?.trim();
      final Uri route;
      if (imdbId != null && imdbId.isNotEmpty) {
        route = Uri.parse('https://letterboxd.com/imdb/$imdbId/');
      } else if (tmdbId != null && tmdbId.isNotEmpty) {
        route = Uri.parse('https://letterboxd.com/tmdb/$tmdbId/');
      } else {
        return const [];
      }
      final html = await _get(route, headers: _browserHeaders);
      final rating = BridgeParsers.extractRating(html);
      if (rating == null || rating <= 0) return const [];
      // Letterboxd 5 分制 → 0–10。
      final scaled = rating > 5 ? rating : rating * 2;
      if (scaled > 10) return const [];
      return [
        HeroRatingBadge(
          RatingPlatform.letterboxd,
          formatRatingScore(RatingPlatform.letterboxd, scaled),
        ),
      ];
    } catch (_) {
      return null;
    }
  }

  /// 自检（设置页「测试评分数据源」）：标准片实打一次网络，**不读缓存**。
  ///
  /// 三源齐备的标准片查不出 → 解析/响应形态问题；查得出而条目上没有 →
  /// 该条目数据稀疏（正常）。key 错误文案透出到 [HeroRatingsSelfCheck]。
  Future<HeroRatingsSelfCheck> selfCheck() async {
    String? omdbError;
    List<HeroRatingBadge> omdbBadges = const [];
    try {
      final body = await _get(Uri.parse(
        'https://www.omdbapi.com/?apikey=$_omdbKey&i=$selfCheckImdbId',
      ));
      final json = jsonDecode(body);
      if (json is Map && json['Response'] == 'False') {
        omdbError = '${json['Error'] ?? 'OMDb 拒绝请求'}';
      } else {
        omdbBadges = parseOmdb(body);
      }
    } catch (_) {
      omdbError = '网络错误';
    }

    String? bridgeError;
    List<HeroRatingBadge> bridgeBadges = const [];
    try {
      final badges = <HeroRatingBadge>[];
      // 豆瓣标准片直查（subject 3541415）。
      final doubanHtml = await _get(
        Uri.parse('https://movie.douban.com/subject/$selfCheckDoubanId/'),
        headers: _browserHeaders,
      );
      final doubanRating = BridgeParsers.extractRating(doubanHtml);
      if (doubanRating != null && doubanRating > 0) {
        badges.add(HeroRatingBadge(
          RatingPlatform.douban,
          formatRatingScore(RatingPlatform.douban, doubanRating),
        ));
      }
      // Letterboxd 标准片（/imdb/{tt}/ 路由）。
      final lbHtml = await _get(
        Uri.parse('https://letterboxd.com/imdb/$selfCheckImdbId/'),
        headers: _browserHeaders,
      );
      final lbRating = BridgeParsers.extractRating(lbHtml);
      if (lbRating != null && lbRating > 0) {
        final scaled = lbRating > 5 ? lbRating : lbRating * 2;
        badges.add(HeroRatingBadge(
          RatingPlatform.letterboxd,
          formatRatingScore(RatingPlatform.letterboxd, scaled),
        ));
      }
      bridgeBadges = badges;
      if (badges.isEmpty) {
        bridgeError = '豆瓣/Letterboxd 均未取到（反爬或站点改版）';
      }
    } catch (_) {
      bridgeError = '爬页网络错误（反爬或站点改版）';
    }

    return HeroRatingsSelfCheck(
      omdbBadges: omdbBadges,
      omdbError: omdbError,
      bridgeBadges: bridgeBadges,
      bridgeError: bridgeError,
    );
  }

  /// 解析 OMDb 响应 → IMDb / 烂番茄影评 / Metacritic 徽章。
  ///
  /// 容错（698）：Source 匹配忽略大小写与首尾空格；MC 兼容 `67/100`/`67`，
  /// RT 兼容 `69%`/`69`。
  @visibleForTesting
  static List<HeroRatingBadge> parseOmdb(String body) {
    final json = jsonDecode(body);
    if (json is! Map) return const [];
    if (json['Response'] == 'False') return const [];
    final out = <HeroRatingBadge>[];
    final imdb = double.tryParse('${json['imdbRating'] ?? ''}');
    if (imdb != null && imdb > 0) {
      out.add(HeroRatingBadge(
        RatingPlatform.imdb,
        formatRatingScore(RatingPlatform.imdb, imdb),
      ));
    }
    final ratings = json['Ratings'];
    if (ratings is List) {
      for (final row in ratings) {
        if (row is! Map) continue;
        final source = '${row['Source'] ?? ''}'.trim().toLowerCase();
        final value = '${row['Value'] ?? ''}'.trim();
        if (source == 'rotten tomatoes') {
          final v = _parseScoreText(value);
          if (v != null && v > 0) {
            out.add(HeroRatingBadge(
              RatingPlatform.rottenTomatoesCritic,
              formatRatingScore(RatingPlatform.rottenTomatoesCritic, v),
            ));
          }
        } else if (source == 'metacritic') {
          final v = _parseScoreText(value);
          if (v != null && v > 0) {
            out.add(HeroRatingBadge(
              RatingPlatform.metacritic,
              formatRatingScore(RatingPlatform.metacritic, v),
            ));
          }
        }
      }
    }
    return out;
  }

  /// 分数文本 → 数值：`67/100`→67、`69%`→69、`67`→67、`N/A`→null。
  static double? _parseScoreText(String raw) {
    final first = raw.split('/').first.trim();
    final stripped = first.endsWith('%')
        ? first.substring(0, first.length - 1).trim()
        : first;
    return double.tryParse(stripped);
  }
}
