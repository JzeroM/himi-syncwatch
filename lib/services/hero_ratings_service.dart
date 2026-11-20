import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';

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
    this.mdblistBadges = const [],
    this.mdblistError,
  });

  final List<HeroRatingBadge> omdbBadges;
  final String? omdbError;
  final List<HeroRatingBadge> mdblistBadges;
  final String? mdblistError;
}

/// 多平台评分拼盘服务（698）：一次查询聚合各源徽章。
///
/// 数据源（缺哪枚隐藏哪枚，绝无空徽章）：
/// - **OMDb**（`omdbApiKey`，按 IMDb id）→ IMDb + 烂番茄影评 + Metacritic 三枚；
/// - **Trakt**（`traktRating` 桥，连账号即亮）→ Trakt 一枚；
/// - **MDBList**（`mdblistApiKey`，按 IMDb id）→ 烂番茄观众（🍿）一枚；
/// - TMDB 徽章来自 [HeroRatingQuery.seedBadges]（本地分，不走网络）。
///
/// 预留（数据源待接入，接入即亮）：Letterboxd、豆瓣。
///
/// 可靠性（698 修复）：
/// - **按源缓存**：某源失败不缓存该源（下次 fetch 自动重试），成功源缓存
///   不重复打——免费 key 限速导致的部分失败不再被永久缓存毒化；
/// - **串行队列**：全部 HTTP 请求服务内排队（带抖动），多条轮播并发查询
///   不再触发 OMDb/MDBList 免费 key 的并发限速。
class HeroRatingsService implements HeroRatingsSource {
  HeroRatingsService({
    this.omdbApiKey = '',
    this.mdblistApiKey = '',
    this.traktRating,
    RatingsHttpGet? httpGet,
    this.queueGap = Duration.zero,
  }) : _httpGet = httpGet ?? _dioGet;

  final String omdbApiKey;
  final String mdblistApiKey;
  final TraktRatingLookup? traktRating;

  /// 串行队列相邻请求的最小间隔（生产传 ~150ms；测试传零）。
  final Duration queueGap;

  final RatingsHttpGet _httpGet;
  final Random _random = Random();

  /// 按源缓存：key = `${源}:${[HeroRatingQuery.cacheKey]}`。
  /// null 结果 = 该源失败（不缓存，下次重试）。
  final Map<String, Future<List<HeroRatingBadge>?>> _cache = {};

  /// 串行队列尾（HTTP 请求依次执行，防免费 key 并发限速）。
  Future<void> _queue = Future<void>.value();

  /// 自检标准片：《搏击俱乐部》tt0137523（IMDb/烂番茄影评/Metacritic 三源齐备）。
  static const String selfCheckImdbId = 'tt0137523';

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

  /// 取该条目的全部徽章：种子分（TMDB）+ 各远端源（按源缓存）。
  @override
  Future<List<HeroRatingBadge>> fetch(HeroRatingQuery query) async {
    final seed = query.seedBadges;
    final key = query.cacheKey;
    if (key == null) return seed;
    final results = await Future.wait([
      _cached('omdb', key, () => _fetchOmdb(query)),
      _cached('trakt', key, () => _fetchTrakt(query)),
      _cached('mdblist', key, () => _fetchMdblist(query)),
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
  /// 未配 key → 空成功；网络/解析异常 → null（失败）；`Response: False` → 空。
  Future<List<HeroRatingBadge>?> _fetchOmdb(HeroRatingQuery query) async {
    if (omdbApiKey.trim().isEmpty) return const [];
    final imdbId = query.imdbId?.trim();
    if (imdbId == null || imdbId.isEmpty) return const [];
    try {
      final body = await _get(
        Uri.parse('https://www.omdbapi.com/?apikey=$omdbApiKey&i=$imdbId'),
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

  /// MDBList 烂番茄观众分（🍿）。
  ///
  /// 只用 `tt…` IMDb id：MDBList 端点的裸数字 id 是 **trakt 语义**（按 TMDB id
  /// 直查会串条目），`tmdb-` 前缀在 `/ratings` 端点不路由——宁缺勿错。
  Future<List<HeroRatingBadge>?> _fetchMdblist(HeroRatingQuery query) async {
    if (mdblistApiKey.trim().isEmpty) return const [];
    final imdbId = query.imdbId?.trim();
    if (imdbId == null || imdbId.isEmpty) return const [];
    try {
      final kind = query.isMovie ? 'movie' : 'show';
      final body = await _get(
        Uri.parse(
          'https://api.mdblist.com/$kind/$imdbId/ratings'
          '?apikey=${mdblistApiKey.trim()}',
        ),
      );
      return parseMdblistAudience(body);
    } catch (_) {
      return null;
    }
  }

  /// 自检（设置页「测试评分数据源」）：用标准片实打一次网络，**不读缓存**。
  ///
  /// 三源齐备的标准片查不出 → 解析/响应形态问题；查得出而条目上没有 →
  /// 该条目数据稀疏（正常）。key 错误文案透出到 [HeroRatingsSelfCheck]。
  Future<HeroRatingsSelfCheck> selfCheck() async {
    String? omdbError;
    List<HeroRatingBadge> omdbBadges = const [];
    if (omdbApiKey.trim().isEmpty) {
      omdbError = '未配置 OMDb Key';
    } else {
      try {
        final body = await _get(Uri.parse(
          'https://www.omdbapi.com/?apikey=$omdbApiKey&i=$selfCheckImdbId',
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
    }

    String? mdblistError;
    List<HeroRatingBadge> mdblistBadges = const [];
    if (mdblistApiKey.trim().isEmpty) {
      mdblistError = '未配置 MDBList Key';
    } else {
      try {
        final body = await _get(Uri.parse(
          'https://api.mdblist.com/movie/$selfCheckImdbId/ratings'
          '?apikey=${mdblistApiKey.trim()}',
        ));
        mdblistBadges = parseMdblistAudience(body);
        if (mdblistBadges.isEmpty) {
          mdblistError = '🍿 未找到（响应形态待适配或该片无观众分）';
        }
      } catch (_) {
        mdblistError = '网络错误';
      }
    }

    return HeroRatingsSelfCheck(
      omdbBadges: omdbBadges,
      omdbError: omdbError,
      mdblistBadges: mdblistBadges,
      mdblistError: mdblistError,
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
        final source =
            '${row['Source'] ?? ''}'.trim().toLowerCase();
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

  /// 解析 MDBList 响应 → 烂番茄观众（🍿）徽章。
  ///
  /// 形态容错（真 key 实测后可再校正）：
  /// - `ratings` 为对象：`{tomatoesaudience: 9.1 | {score: 91, ...}, ...}`；
  /// - `ratings` 为数组：`[{source: "tomatoesaudience"|"rotten tomatoes",
  ///   type: "audience", score: 91, value: 9.1}, ...]`；
  /// - 顶层直接带 audience 变体键。
  /// 取值优先 `score`（0–100）；`value`/裸值 ≤10 视为 0–10 制换算百分比。
  @visibleForTesting
  static List<HeroRatingBadge> parseMdblistAudience(String body) {
    final json = jsonDecode(body);
    final v = _audienceFrom(json);
    if (v == null || v <= 0) return const [];
    return [
      HeroRatingBadge(
        RatingPlatform.rottenTomatoesAudience,
        formatRatingScore(RatingPlatform.rottenTomatoesAudience, v),
      ),
    ];
  }

  static const _audienceKeys = [
    'tomatoesaudience',
    'tomatoes_audience',
    'popcornmeter',
    'popcorn',
    'audience',
  ];

  static double? _audienceFrom(Object? json) {
    if (json is Map) {
      for (final k in _audienceKeys) {
        final v = _scoreFrom(json[k]);
        if (v != null) return v;
      }
      final ratings = json['ratings'];
      if (ratings is Map || ratings is List) return _audienceFrom(ratings);
    } else if (json is List) {
      for (final row in json) {
        if (row is! Map) continue;
        final source = '${row['source'] ?? row['name'] ?? ''}'
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[\s_-]'), '');
        final type = '${row['type'] ?? row['kind'] ?? ''}'.trim().toLowerCase();
        final isAudience = source.contains('audience') ||
            source.contains('popcorn') ||
            ((source.contains('tomato') || source.contains('rottentomatoes')) &&
                type == 'audience');
        if (!isAudience) continue;
        // 优先 score（0–100），退回 value/rating（按量级归一）。
        final v = _scoreFrom(row['score'] ?? row['value'] ?? row['rating']);
        if (v != null) return v;
      }
    }
    return null;
  }

  static double? _scoreFrom(Object? raw) {
    if (raw is num) return _normalizePercent(raw.toDouble());
    if (raw is Map) {
      return _scoreFrom(raw['score'] ?? raw['value'] ?? raw['rating']);
    }
    if (raw is String) {
      final s = raw.trim();
      if (s.endsWith('%')) {
        return double.tryParse(s.substring(0, s.length - 1).trim());
      }
      final v = double.tryParse(s);
      return v == null ? null : _normalizePercent(v);
    }
    return null;
  }

  /// 量级归一：≤10 视为 0–10 制（×10），>10 视为已是百分比。
  static double _normalizePercent(double v) => v <= 10 ? v * 10 : v;
}
