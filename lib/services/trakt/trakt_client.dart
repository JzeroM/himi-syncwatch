import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_auth_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_config.dart';
import 'package:himi_syncwatch/services/trakt/trakt_rate_limiter.dart';

class TraktApiException implements Exception {
  final int? statusCode;
  final String message;

  const TraktApiException(this.statusCode, this.message);

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'TraktApiException($statusCode): $message';
}

class TraktClient {
  final TraktConfig config;
  final TraktAuthService auth;
  final Dio _dio;
  final TraktRateLimiter limiter;

  TraktTokens? _tokens;

  TraktClient({
    required this.auth,
    this.config = const TraktConfig(),
    Dio? dio,
    TraktRateLimiter? limiter,
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 30),
              validateStatus: (_) => true,
            )),
        limiter = limiter ?? TraktRateLimiter();

  TraktTokens? get tokens => _tokens;

  set tokens(TraktTokens? value) => _tokens = value;

  bool get isAuthenticated =>
      _tokens != null && _tokens!.accessToken.isNotEmpty;

  Future<List<Map<String, dynamic>>> getWatchedMovies() {
    return _getAll('/sync/watched/movies');
  }

  Future<List<Map<String, dynamic>>> getWatchedShows() {
    return _getAll('/sync/watched/shows', query: {'extended': 'full'});
  }

  Future<List<Map<String, dynamic>>> getPlayback() async {
    try {
      return await _getAll('/sync/playback');
    } on TraktApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      final movies = await _getAll('/sync/playback/movies');
      final episodes = await _getAll('/sync/playback/episodes');
      return [...movies, ...episodes];
    }
  }

  Future<void> addHistory({
    List<Map<String, dynamic>> movies = const [],
    List<Map<String, dynamic>> shows = const [],
  }) async {
    if (movies.isEmpty && shows.isEmpty) return;
    await _write(
      'POST',
      '/sync/history',
      data: {
        if (movies.isNotEmpty) 'movies': movies,
        if (shows.isNotEmpty) 'shows': shows,
      },
    );
  }

  Future<void> removeHistory({
    List<Map<String, dynamic>> movies = const [],
    List<Map<String, dynamic>> shows = const [],
  }) async {
    if (movies.isEmpty && shows.isEmpty) return;
    await _write(
      'POST',
      '/sync/history/remove',
      data: {
        if (movies.isNotEmpty) 'movies': movies,
        if (shows.isNotEmpty) 'shows': shows,
      },
    );
  }

  Future<void> pauseMovie({
    required TraktMediaIds ids,
    required double progress,
  }) async {
    await _write(
      'POST',
      '/scrobble/pause',
      data: {
        'movie': {'ids': ids.toJson()},
        'progress': progress.clamp(0.1, 100).toDouble(),
      },
    );
  }

  Future<void> pauseEpisode({
    required TraktMediaIds ids,
    required TraktMediaIds showIds,
    required int season,
    required int episode,
    required double progress,
  }) async {
    var effectiveIds = ids;
    if (!_hasIds(ids) && _hasIds(showIds)) {
      effectiveIds = await resolveEpisodeIds(
            showIds: showIds,
            season: season,
            episode: episode,
          ) ??
          ids;
    }
    await _write(
      'POST',
      '/scrobble/pause',
      data: {
        'show': {'ids': showIds.toJson()},
        'episode': {
          'season': season,
          'number': episode,
          'ids': effectiveIds.toJson(),
        },
        'progress': progress.clamp(0.1, 100).toDouble(),
      },
    );
  }

  Future<TraktMediaIds?> resolveEpisodeIds({
    required TraktMediaIds showIds,
    required int season,
    required int episode,
  }) async {
    var show = showIds;
    if (show.trakt == null) {
      final resolved = await _lookupShow(show);
      if (resolved == null) return null;
      show = resolved;
    }
    if (show.trakt == null) return null;
    final row = await getEpisode(
      showId: show.trakt!,
      season: season,
      episode: episode,
    );
    if (row == null) return null;
    final ids = row['ids'];
    if (ids is Map) {
      return TraktMediaIds.fromJson(Map<String, dynamic>.from(ids));
    }
    return null;
  }

  Future<TraktMediaIds?> _lookupShow(TraktMediaIds ids) async {
    final searches = <(String, Object)>[
      if (ids.tmdb != null) ('tmdb', ids.tmdb!),
      if (ids.tvdb != null) ('tvdb', ids.tvdb!),
      if (ids.imdb != null && ids.imdb!.isNotEmpty) ('imdb', ids.imdb!),
    ];
    for (final entry in searches) {
      final rows = await _getAll(
        '/search/${entry.$1}/${Uri.encodeComponent(entry.$2.toString())}',
        query: {'type': 'show'},
      );
      for (final row in rows) {
        final show = row['show'];
        if (show is Map) {
          final showIds = show['ids'];
          if (showIds is Map) {
            return TraktMediaIds.fromJson(
              Map<String, dynamic>.from(showIds),
            );
          }
        }
      }
    }
    return null;
  }

  Future<void> deletePlayback(int playbackId) async {
    await _write('DELETE', '/sync/playback/$playbackId');
  }

  Future<void> deleteAllPlayback(Iterable<int> ids) async {
    for (final id in ids) {
      await deletePlayback(id);
    }
  }

  Future<Map<String, dynamic>?> lookupShowByTmdb(int tmdbId) async {
    final rows = await _getAll('/search/tmdb/$tmdbId', query: {'type': 'show'});
    if (rows.isEmpty) return null;
    final show = rows.first['show'];
    return show is Map ? Map<String, dynamic>.from(show) : null;
  }

  Future<Map<String, dynamic>?> getEpisode({
    required int showId,
    required int season,
    required int episode,
  }) async {
    final response = await _request(
      'GET',
      '/shows/$showId/seasons/$season/episodes/$episode',
      query: {'extended': 'full'},
    );
    final data = _mapBody(response);
    if (response.statusCode == 200) return data;
    if (response.statusCode == 404) return null;
    throw _exception(response, data);
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await _request('GET', '/users/me');
    final data = _mapBody(response);
    if (response.statusCode == 200) return data;
    throw _exception(response, data);
  }

  Future<List<Map<String, dynamic>>> _getAll(
    String path, {
    Map<String, String>? query,
  }) async {
    final rows = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final response = await _request(
        'GET',
        path,
        query: {
          ...?query,
          'page': '$page',
          'limit': '100',
        },
      );
      if (response.statusCode != 200) {
        throw _exception(response, _mapBody(response));
      }
      final data = response.data;
      if (data is List) {
        for (final row in data) {
          if (row is Map) rows.add(Map<String, dynamic>.from(row));
        }
      }
      final pageCount = int.tryParse(
        response.headers.value('x-pagination-page-count') ?? '',
      );
      if (pageCount == null || page >= pageCount) break;
      page++;
    }
    return rows;
  }

  Future<void> _write(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) async {
    await limiter.beforeWrite();
    final response = await _request(method, path, data: data);
    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      return;
    }
    throw _exception(response, _mapBody(response));
  }

  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? query,
  }) async {
    var tokens = _tokens;
    if (tokens == null || tokens.accessToken.isEmpty) {
      throw const TraktApiException(401, '未登录 Trakt');
    }
    tokens = await auth.ensureValid(tokens);
    _tokens = tokens;

    var response = await _send(
      method,
      path,
      tokens: tokens,
      data: data,
      query: query,
    );
    if (response.statusCode == 401) {
      final current = _tokens;
      if (current != null && current.accessToken != tokens.accessToken) {
        tokens = current;
      } else {
        tokens = await auth.refresh(tokens);
        _tokens = tokens;
      }
      response = await _send(
        method,
        path,
        tokens: tokens,
        data: data,
        query: query,
      );
    }
    if (response.statusCode == 429) {
      final retry =
          int.tryParse(response.headers.value('retry-after') ?? '') ?? 2;
      await limiter.delay(Duration(seconds: retry));
      await limiter.beforeWrite();
      response = await _send(
        method,
        path,
        tokens: tokens,
        data: data,
        query: query,
      );
    }
    return response;
  }

  Future<Response<dynamic>> _send(
    String method,
    String path, {
    required TraktTokens tokens,
    Map<String, dynamic>? data,
    Map<String, String>? query,
  }) async {
    final options = Options(
      headers: {
        'trakt-api-version': '2',
        'trakt-api-key': config.clientId,
        'User-Agent': config.userAgent,
        'Content-Type': 'application/json',
        'Authorization': '${tokens.tokenType} ${tokens.accessToken}',
      },
    );
    try {
      return await _dio.request<dynamic>(
        '${config.apiBase}$path',
        data: data == null ? null : jsonEncode(data),
        queryParameters: query,
        options: options..method = method,
      );
    } on DioException catch (e) {
      if (e.response != null) return e.response!;
      throw TraktApiException(null, e.message ?? '网络请求失败');
    }
  }

  Map<String, dynamic> _mapBody(Response<dynamic> response) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const {};
  }

  bool _hasIds(TraktMediaIds ids) =>
      (ids.trakt != null && ids.trakt! > 0) ||
      (ids.tmdb != null && ids.tmdb! > 0) ||
      (ids.tvdb != null && ids.tvdb! > 0) ||
      (ids.imdb != null && ids.imdb!.trim().isNotEmpty);

  TraktApiException _exception(
    Response<dynamic> response,
    Map<String, dynamic> data,
  ) {
    final message = data['error_description'] ??
        data['error'] ??
        data['message'] ??
        'Trakt 请求失败';
    return TraktApiException(
      response.statusCode,
      message is String ? message : 'Trakt 请求失败',
    );
  }
}
