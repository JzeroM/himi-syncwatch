import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';

class _RecordedRequest {
  _RecordedRequest(this.uri, this.authorization);

  final Uri uri;
  final String? authorization;
}

Future<HttpServer> _serve(
  List<_RecordedRequest> requests, {
  Map<String, dynamic>? discoverJson,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    requests.add(_RecordedRequest(
      request.uri,
      request.headers.value(HttpHeaders.authorizationHeader),
    ));
    request.response.headers.contentType = ContentType.json;
    final path = request.uri.path;
    if (path.contains('/discover/')) {
      request.response.write(jsonEncode(discoverJson ??
          {
            'page': 1,
            'total_pages': 2,
            'total_results': 1,
            'results': [
              {'id': 1, 'title': 'A', 'poster_path': '/a.jpg'},
            ],
          }));
    } else if (path.contains('/trending/')) {
      request.response.write(jsonEncode({
        'page': 1,
        'total_pages': 1,
        'total_results': 2,
        'results': [
          {'id': 1, 'media_type': 'movie', 'title': 'A'},
          {'id': 2, 'media_type': 'person', 'name': 'P'},
        ],
      }));
    } else if (path.contains('/watch/providers/')) {
      request.response.write(jsonEncode({
        'results': [
          {'provider_id': 8, 'logo_path': '/netflix.png'},
          {'provider_id': 337, 'logo_path': '/disney.png'},
        ],
      }));
    } else {
      request.response.write('{}');
    }
    await request.response.close();
  });
  return server;
}

void main() {
  test('v3 Key 走 api_key + language，v4 Token 走 Bearer', () async {
    final requests = <_RecordedRequest>[];
    final server = await _serve(requests);
    addTearDown(() => server.close(force: true));
    final base = 'http://127.0.0.1:${server.port}/3';

    await TmdbService(apiBase: base, credential: 'v3-key').testConnection();
    await TmdbService(
      apiBase: base,
      credential: 'eyJhbGciOiJIUzI1NiJ9.token',
    ).testConnection();

    expect(requests, hasLength(2));
    expect(requests[0].uri.path, '/3/configuration');
    expect(requests[0].uri.queryParameters['api_key'], 'v3-key');
    expect(requests[0].uri.queryParameters['language'], 'zh-CN');
    expect(requests[0].authorization, isNull);
    expect(requests[1].uri.queryParameters.containsKey('api_key'), isFalse);
    expect(requests[1].authorization, 'Bearer eyJhbGciOiJIUzI1NiJ9.token');
  });

  test('discoverPlatform 参数正确且第一页缓存', () async {
    final requests = <_RecordedRequest>[];
    final server = await _serve(requests);
    addTearDown(() => server.close(force: true));
    final service = TmdbService(
      apiBase: 'http://127.0.0.1:${server.port}/3',
      credential: 'k',
    );

    final first = await service.discoverPlatform(
      providerId: 8,
      type: TmdbMediaType.movie,
      region: 'JP',
      allowCache: true,
    );
    final second = await service.discoverPlatform(
      providerId: 8,
      type: TmdbMediaType.movie,
      region: 'JP',
      allowCache: true,
    );

    expect(requests, hasLength(1));
    expect(requests.single.uri.path, '/3/discover/movie');
    expect(requests.single.uri.queryParameters['with_watch_providers'], '8');
    expect(requests.single.uri.queryParameters['watch_region'], 'JP');
    expect(
      requests.single.uri.queryParameters['with_watch_monetization_types'],
      'flatrate',
    );
    expect(requests.single.uri.queryParameters['sort_by'], 'popularity.desc');
    expect(first.hasMore, isTrue);
    expect(first.items.single.type, TmdbMediaType.movie);
    expect(second.items.single.id, first.items.single.id);
  });

  test('趋势接口跳过 person 等不支持类型', () async {
    final requests = <_RecordedRequest>[];
    final server = await _serve(requests);
    addTearDown(() => server.close(force: true));
    final service = TmdbService(
      apiBase: 'http://127.0.0.1:${server.port}/3',
      credential: 'k',
    );

    final items = await service.trendingDay();

    expect(items.map((e) => e.id), [1]);
    expect(items.single.type, TmdbMediaType.movie);
  });

  test('platformLogos 合并 movie/tv 结果并按 provider id 去重', () async {
    final requests = <_RecordedRequest>[];
    final server = await _serve(requests);
    addTearDown(() => server.close(force: true));
    final service = TmdbService(
      apiBase: 'http://127.0.0.1:${server.port}/3',
      credential: 'k',
    );

    final logos = await service.platformLogos('US');

    expect(requests, hasLength(2));
    expect(logos[8], '/netflix.png');
    expect(logos[337], '/disney.png');
  });

  test('401/429 转换为可读错误', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = request.uri.path.contains('429') ? 429 : 401;
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}/3';

    await expectLater(
      TmdbService(apiBase: base, credential: 'bad').testConnection(),
      throwsA(isA<TmdbException>().having(
        (e) => e.message,
        'message',
        contains('凭据无效'),
      )),
    );
  });

  test('imageUrl 空 path 返回 null', () {
    expect(TmdbService.imageUrl('https://img', '/p.jpg'), 'https://img/w500/p.jpg');
    expect(TmdbService.imageUrl('https://img', null), isNull);
    expect(TmdbService.imageUrl('https://img', ''), isNull);
  });
}
