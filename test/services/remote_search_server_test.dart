import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/remote_search/remote_search_server.dart';

void main() {
  late RemoteSearchServer server;
  late List<String> searchQueries;
  late List<String> selectedPair;
  String? selectError;

  setUp(() async {
    searchQueries = [];
    selectedPair = [];
    selectError = null;
    server = RemoteSearchServer(
      basePort: 0,
      onSearch: (q) async {
        searchQueries.add(q);
        if (q.isEmpty) return const [];
        return [
          const RemoteSearchItem(
            id: 'm1',
            name: '甲影片',
            serverId: 'a',
            serverName: '服务器甲',
            year: '2026',
            poster: 'https://a.example.com/p.jpg?api_key=tok',
          ),
        ];
      },
      onSelect: (serverId, itemId) async {
        selectedPair = [serverId, itemId];
        return selectError;
      },
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  String base() => 'http://127.0.0.1:${server.port}';

  Future<HttpClientResponse> request(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final client = HttpClient()..findProxy = ((_) => 'DIRECT');
    addTearDown(client.close);
    final uri = Uri.parse('${base()}$path');
    final req = await client.openUrl(method, uri);
    headers?.forEach(req.headers.add);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    return req.close();
  }

  Future<String> bodyOf(HttpClientResponse res) =>
      utf8.decoder.bind(res).join();

  Future<Map<String, dynamic>> jsonOf(HttpClientResponse res) async =>
      jsonDecode(await bodyOf(res)) as Map<String, dynamic>;

  test('启动后 url 含随机 token 与端口', () {
    expect(server.isRunning, isTrue);
    expect(server.token, hasLength(32));
    expect(server.url, contains(':${server.port}/'));
    expect(server.url, contains('t=${server.token}'));
  });

  test('GET / 带正确 token → 200 搜索单页并下发 Cookie', () async {
    final res = await request('GET', '/?t=${server.token}');
    expect(res.statusCode, HttpStatus.ok);
    expect(res.headers.contentType?.mimeType, 'text/html');
    final body = await bodyOf(res);
    expect(body, contains('HIMI 手机搜索'));
    expect(body, contains('/api/search'));
    expect(body, contains('/api/select'));
    final cookie = res.headers.value(HttpHeaders.setCookieHeader) ?? '';
    expect(
        cookie, contains('${RemoteSearchServer.cookieName}=${server.token}'));
  });

  test('GET / 无 token → 403', () async {
    final res = await request('GET', '/');
    expect(res.statusCode, HttpStatus.forbidden);
  });

  test('POST /api/search 带 token → 200 且结果序列化完整', () async {
    final res = await request(
      'POST',
      '/api/search?t=${server.token}',
      body: {'q': '影片'},
    );
    expect(res.statusCode, HttpStatus.ok);
    expect(searchQueries, ['影片']);
    final json = await jsonOf(res);
    expect(json['ok'], isTrue);
    final results = json['results'] as List<dynamic>;
    expect(results, hasLength(1));
    final first = results.single as Map<String, dynamic>;
    expect(first['id'], 'm1');
    expect(first['name'], '甲影片');
    expect(first['serverId'], 'a');
    expect(first['serverName'], '服务器甲');
    expect(first['year'], '2026');
    expect(first['poster'], contains('api_key=tok'));
  });

  test('POST /api/search 带 Cookie 授权（后续请求无需带 t）', () async {
    final page = await request('GET', '/?t=${server.token}');
    final cookie = page.headers.value(HttpHeaders.setCookieHeader)!;
    final raw = cookie.split(';').first;
    final res = await request(
      'POST',
      '/api/search',
      headers: {HttpHeaders.cookieHeader: raw},
      body: {'q': '影片'},
    );
    expect(res.statusCode, HttpStatus.ok);
  });

  test('POST /api/search 无 token → 403；非 JSON → 400；q 非字符串 → 400', () async {
    final noAuth = await request('POST', '/api/search', body: {'q': 'x'});
    expect(noAuth.statusCode, HttpStatus.forbidden);

    final badJson = await request(
      'POST',
      '/api/search?t=${server.token}',
      body: ['not', 'object'],
    );
    expect(badJson.statusCode, HttpStatus.badRequest);

    final badQ = await request(
      'POST',
      '/api/search?t=${server.token}',
      body: {'q': 123},
    );
    expect(badQ.statusCode, HttpStatus.badRequest);
  });

  test('POST /api/select → 回调收到 serverId/itemId 并返回成功', () async {
    final res = await request(
      'POST',
      '/api/select?t=${server.token}',
      body: {'serverId': 'a', 'itemId': 'm1'},
    );
    expect(res.statusCode, HttpStatus.ok);
    expect(selectedPair, ['a', 'm1']);
    expect((await jsonOf(res))['message'], '已在电视上打开');
  });

  test('POST /api/select 缺字段 → 400；回调报错 → 400 透传', () async {
    final missing = await request(
      'POST',
      '/api/select?t=${server.token}',
      body: {'serverId': 'a'},
    );
    expect(missing.statusCode, HttpStatus.badRequest);
    expect(selectedPair, isEmpty);

    selectError = '目标服务器不在线';
    final failed = await request(
      'POST',
      '/api/select?t=${server.token}',
      body: {'serverId': 'a', 'itemId': 'm1'},
    );
    expect(failed.statusCode, HttpStatus.badRequest);
    expect((await jsonOf(failed))['error'], '目标服务器不在线');
  });

  test('带 token 的未知路径 → 404；stop 后停止服务', () async {
    final res = await request('GET', '/nope?t=${server.token}');
    expect(res.statusCode, HttpStatus.notFound);

    await server.stop();
    expect(server.isRunning, isFalse);
    expect(server.url, isNull);

    // stop 后可再次启动
    await server.start();
    expect(server.isRunning, isTrue);
    await server.stop();
  });
}
