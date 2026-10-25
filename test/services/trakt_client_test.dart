import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_auth_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_client.dart';
import 'package:himi_syncwatch/services/trakt/trakt_config.dart';
import 'package:himi_syncwatch/services/trakt/trakt_rate_limiter.dart';
import 'package:himi_syncwatch/services/trakt/trakt_token_store.dart';

import '../helpers/fake_secure_storage.dart';

typedef _Handler = Future<ResponseBody> Function(RequestOptions options);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final _Handler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(
  Object payload, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      ...headers,
    },
  );
}

TraktClient _client(_FakeAdapter adapter) {
  final storage = FakeSecureStorage();
  final auth = TraktAuthService(
    config: const TraktConfig(clientId: 'client-id'),
    store: TraktTokenStore(storage: storage),
  );
  final client = TraktClient(
    auth: auth,
    config: const TraktConfig(clientId: 'client-id'),
    dio: Dio()..httpClientAdapter = adapter,
    limiter: TraktRateLimiter(delay: (_) async {}),
  );
  client.tokens = TraktTokens(
    accessToken: 'access',
    refreshToken: 'refresh',
    tokenType: 'Bearer',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    createdAt: DateTime.now(),
  );
  return client;
}

void main() {
  test('分页读取 watched movies 并带齐 Trakt 请求头', () async {
    final adapter = _FakeAdapter((options) async {
      final page = options.queryParameters['page'];
      if (page == '1') {
        return _json(
          [
            {
              'movie': {
                'ids': {'tmdb': 1}
              }
            }
          ],
          headers: {
            'x-pagination-page-count': ['2'],
          },
        );
      }
      return _json(
        [
          {
            'movie': {
              'ids': {'tmdb': 2}
            }
          }
        ],
        headers: {
          'x-pagination-page-count': ['2'],
        },
      );
    });
    final client = _client(adapter);

    final rows = await client.getWatchedMovies();

    expect(rows, hasLength(2));
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.uri.path, '/sync/watched/movies');
    expect(adapter.requests.first.headers['trakt-api-key'], 'client-id');
    expect(adapter.requests.first.headers['trakt-api-version'], '2');
    expect(adapter.requests.first.headers['Authorization'], 'Bearer access');
    expect(adapter.requests.first.queryParameters['limit'], '100');
  });

  test('合并 playback 端点 404 时回退 movies/episodes', () async {
    final adapter = _FakeAdapter((options) async {
      switch (options.uri.path) {
        case '/sync/playback':
          return _json({'error': 'not_found'}, status: 404);
        case '/sync/playback/movies':
          return _json([
            {
              'id': 1,
              'progress': 10.0,
              'movie': {
                'ids': {'tmdb': 1}
              }
            }
          ]);
        case '/sync/playback/episodes':
          return _json([
            {
              'id': 2,
              'progress': 20.0,
              'episode': {
                'season': 1,
                'number': 2,
                'ids': {'tmdb': 3}
              }
            }
          ]);
      }
      return _json({'error': 'unexpected'}, status: 500);
    });
    final client = _client(adapter);

    final rows = await client.getPlayback();

    expect(rows, hasLength(2));
    expect(adapter.requests.map((e) => e.uri.path), [
      '/sync/playback',
      '/sync/playback/movies',
      '/sync/playback/episodes',
    ]);
  });
}
