import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';

class TmdbException implements Exception {
  const TmdbException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CacheEntry<T> {
  _CacheEntry(this.value) : expiresAt = DateTime.now().add(_ttl);

  static const _ttl = Duration(minutes: 10);

  final T value;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);
}

/// TMDB v3 API 客户端：支持 v3 api_key 与 v4 Read Access Token。
class TmdbService {
  TmdbService({
    required String apiBase,
    required String credential,
  })  : _credential = credential.trim(),
        _bearer = credential.trim().startsWith('eyJ') {
    _dio = Dio(BaseOptions(
      baseUrl: apiBase,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json',
        if (_bearer) 'Authorization': 'Bearer $_credential',
      },
    ));
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      return HttpClient()
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
    };
  }

  final String _credential;
  final bool _bearer;
  late final Dio _dio;
  final Map<String, _CacheEntry<dynamic>> _cache = {};

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: {
          if (!_bearer) 'api_key': _credential,
          'language': 'zh-CN',
          ...?query,
        },
      );
      final data = response.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      throw const TmdbException('TMDB 返回数据格式异常');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) {
        throw const TmdbException('TMDB 凭据无效，请检查 API Key / Token');
      }
      if (code == 429) {
        throw const TmdbException('TMDB 请求过于频繁，请稍后重试');
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw const TmdbException('TMDB 请求超时，请检查网络或代理');
      }
      if (e.type == DioExceptionType.connectionError) {
        throw const TmdbException('无法连接 TMDB，请检查网络或 API 地址');
      }
      throw TmdbException(code != null ? 'TMDB 请求失败 ($code)' : 'TMDB 请求失败');
    }
  }

  T? _cached<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.expired) {
      _cache.remove(key);
      return null;
    }
    return entry.value as T;
  }

  void _store(String key, Object? value) {
    _cache[key] = _CacheEntry<dynamic>(value);
  }

  Future<List<TmdbItem>> _list(
    String cacheKey,
    String path, {
    TmdbMediaType? fallbackType,
    Map<String, dynamic>? query,
    bool filterUnsupportedTypes = false,
  }) async {
    final cached = _cached<List<TmdbItem>>(cacheKey);
    if (cached != null) return cached;
    final json = await _get(path, query: query);
    final result = TmdbPagedResult.fromJson(json, fallbackType: fallbackType);
    final items = filterUnsupportedTypes
        ? result.items
            .where((e) => e.type == TmdbMediaType.movie || e.type == TmdbMediaType.tv)
            .toList()
        : result.items;
    _store(cacheKey, items);
    return items;
  }

  Future<List<TmdbItem>> trendingDay({int page = 1}) => _list(
        'trending_day_$page',
        '/trending/all/day',
        query: {'page': page},
        filterUnsupportedTypes: true,
      );

  Future<List<TmdbItem>> trendingWeek({int page = 1}) => _list(
        'trending_week_$page',
        '/trending/all/week',
        query: {'page': page},
        filterUnsupportedTypes: true,
      );

  Future<List<TmdbItem>> popularMovies({int page = 1}) => _list(
        'popular_movies_$page',
        '/movie/popular',
        query: {'page': page},
        fallbackType: TmdbMediaType.movie,
      );

  Future<List<TmdbItem>> popularTv({int page = 1}) => _list(
        'popular_tv_$page',
        '/tv/popular',
        query: {'page': page},
        fallbackType: TmdbMediaType.tv,
      );

  Future<TmdbPagedResult> discoverPlatform({
    required int providerId,
    required TmdbMediaType type,
    required String region,
    int page = 1,
    bool allowCache = false,
  }) async {
    final cacheKey = 'discover_${type.apiValue}_${providerId}_${region}_$page';
    final cached = _cached<TmdbPagedResult>(cacheKey);
    if (allowCache && cached != null) return cached;
    final json = await _get(
      '/discover/${type.apiValue}',
      query: {
        'with_watch_providers': providerId,
        'watch_region': region,
        'with_watch_monetization_types': 'flatrate',
        'sort_by': 'popularity.desc',
        'page': page,
        'include_adult': false,
      },
    );
    final result =
        TmdbPagedResult.fromJson(json, fallbackType: type);
    _store(cacheKey, result);
    return result;
  }

  /// 平台 logo_path（providerId → path）。分别取 movie/tv 两组并合并。
  Future<Map<int, String?>> platformLogos(String region) async {
    final cacheKey = 'platform_logos_$region';
    final cached = _cached<Map<int, String?>>(cacheKey);
    if (cached != null) return cached;
    final results = await Future.wait([
      _get('/watch/providers/movie', query: {'watch_region': region}),
      _get('/watch/providers/tv', query: {'watch_region': region}),
    ]);
    final logos = <int, String?>{};
    for (final data in results) {
      final providers = data['results'] as List<dynamic>? ?? const [];
      for (final raw in providers.whereType<Map>()) {
        final id = (raw['provider_id'] as num?)?.toInt();
        if (id == null) continue;
        final logo = raw['logo_path'] as String?;
        if (!logos.containsKey(id) || logos[id] == null) {
          logos[id] = logo;
        }
      }
    }
    _store(cacheKey, logos);
    return logos;
  }

  Future<void> testConnection() async {
    await _get('/configuration');
  }

  void clearCache() => _cache.clear();

  static String? imageUrl(
    String imageBase,
    String? path, {
    String size = 'w500',
  }) {
    if (path == null || path.isEmpty) return null;
    return '$imageBase/$size$path';
  }
}
