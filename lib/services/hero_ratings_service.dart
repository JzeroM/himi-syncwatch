import 'dart:convert';

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

/// 多平台评分拼盘服务（698）：一次查询聚合各源徽章。
///
/// 数据源（缺哪枚隐藏哪枚，绝无空徽章）：
/// - **OMDb**（`omdbApiKey`，按 IMDb id）→ IMDb + 烂番茄影评 + Metacritic 三枚；
/// - **Trakt**（`traktRating` 桥，连账号即亮）→ Trakt 一枚；
/// - **Simkl**（`simklApiKey`，按 TMDB id）→ Simkl 一枚；
/// - TMDB 徽章来自 [HeroRatingQuery.seedBadges]（本地分，不走网络）。
///
/// 预留（数据源待接入，接入即亮）：烂番茄观众、Letterboxd、豆瓣。
///
/// 结果按 IMDb id 内存缓存；**全源失败不缓存**（下次构建重试），
/// 部分成功即缓存（已成功的源不再重复打）。
class HeroRatingsService implements HeroRatingsSource {
  HeroRatingsService({
    this.omdbApiKey = '',
    this.simklApiKey = '',
    this.traktRating,
    RatingsHttpGet? httpGet,
  }) : _httpGet = httpGet ?? _dioGet;

  final String omdbApiKey;
  final String simklApiKey;
  final TraktRatingLookup? traktRating;
  final RatingsHttpGet _httpGet;

  /// 缓存：key = [HeroRatingQuery.cacheKey]；null 值 = 全源失败（未缓存）。
  final Map<String, Future<List<HeroRatingBadge>?>> _cache = {};

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

  /// 取该条目的全部徽章：种子分（TMDB）+ 各远端源。
  @override
  Future<List<HeroRatingBadge>> fetch(HeroRatingQuery query) async {
    final seed = query.seedBadges;
    final key = query.cacheKey;
    if (key == null) return seed;
    var future = _cache[key];
    if (future == null) {
      future = _fetchRemote(query);
      _cache[key] = future;
    }
    final remote = await future;
    if (remote == null) {
      // 全源失败：清缓存，下次构建重试。
      _cache.remove(key);
      return seed;
    }
    return [...seed, ...remote];
  }

  Future<List<HeroRatingBadge>?> _fetchRemote(HeroRatingQuery query) async {
    final results = await Future.wait([
      _fetchOmdb(query),
      _fetchTrakt(query),
      _fetchSimkl(query),
    ]);
    // 全部源都失败（网络/解析异常）才算失败；未配置的源返回空成功。
    if (results.every((r) => r == null)) return null;
    return [for (final r in results) ...?r];
  }

  /// OMDb 一枚 key 拿三枚：IMDb + 烂番茄影评 + Metacritic。
  /// 未配 key → 空成功；网络/解析异常 → null（失败）；`Response: False` → 空。
  Future<List<HeroRatingBadge>?> _fetchOmdb(HeroRatingQuery query) async {
    if (omdbApiKey.trim().isEmpty) return const [];
    final imdbId = query.imdbId?.trim();
    if (imdbId == null || imdbId.isEmpty) return const [];
    try {
      final body = await _httpGet(
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

  /// Simkl 评分（0–10，按 TMDB id）。
  Future<List<HeroRatingBadge>?> _fetchSimkl(HeroRatingQuery query) async {
    if (simklApiKey.trim().isEmpty) return const [];
    final tmdbId = query.tmdbId?.trim();
    if (tmdbId == null || tmdbId.isEmpty) return const [];
    try {
      final body = await _httpGet(
        Uri.parse(
          'https://api.simkl.com/search/id?tmdb=$tmdbId'
          '&type=${query.isMovie ? 'movie' : 'show'}',
        ),
        headers: {'simkl-api-key': simklApiKey.trim()},
      );
      return parseSimkl(body);
    } catch (_) {
      return null;
    }
  }

  /// 解析 OMDb 响应 → IMDb / 烂番茄影评 / Metacritic 徽章。
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
        final source = '${row['Source']}';
        final value = '${row['Value']}';
        if (source == 'Rotten Tomatoes') {
          final v = double.tryParse(value.replaceAll('%', ''));
          if (v != null && v > 0) {
            out.add(HeroRatingBadge(
              RatingPlatform.rottenTomatoesCritic,
              formatRatingScore(RatingPlatform.rottenTomatoesCritic, v),
            ));
          }
        } else if (source == 'Metacritic') {
          final v = double.tryParse(value.split('/').first);
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

  /// 解析 Simkl 响应（对象或单元素数组）→ Simkl 徽章。
  @visibleForTesting
  static List<HeroRatingBadge> parseSimkl(String body) {
    dynamic json = jsonDecode(body);
    if (json is List) {
      json = json.isEmpty ? null : json.first;
    }
    if (json is! Map) return const [];
    final ratings = json['ratings'];
    if (ratings is! Map) return const [];
    final simkl = ratings['simkl'];
    if (simkl is! Map) return const [];
    final v = (simkl['rating'] as num?)?.toDouble();
    if (v == null || v <= 0) return const [];
    return [
      HeroRatingBadge(
        RatingPlatform.simkl,
        formatRatingScore(RatingPlatform.simkl, v),
      ),
    ];
  }
}
