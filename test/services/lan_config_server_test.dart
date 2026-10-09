import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/lan_config/lan_config_server.dart';

void main() {
  late LanConfigServer server;
  late Map<String, dynamic> capturedEmby;
  String? embyError;

  setUp(() async {
    capturedEmby = {};
    embyError = null;
    server = LanConfigServer(
      basePort: 0,
      onEmby: (body) async {
        capturedEmby = body;
        return embyError;
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

  test('启动后 url 含随机 token 与端口', () {
    expect(server.isRunning, isTrue);
    expect(server.token, hasLength(32));
    expect(server.url, contains(':${server.port}/'));
    expect(server.url, contains('t=${server.token}'));
  });

  test('GET / 带正确 token → 200 且返回配置页', () async {
    final res = await request('GET', '/?t=${server.token}');
    expect(res.statusCode, HttpStatus.ok);
    expect(res.headers.contentType!.mimeType, 'text/html');
    final html = await bodyOf(res);
    expect(html, contains('emby_url'));
    expect(html, isNot(contains('agora_id')));
    expect(html, contains('连接并登录'));
    expect(res.headers.value(HttpHeaders.setCookieHeader),
        contains('himi_cfg=${server.token}'));
  });

  test('GET / token 错误 → 403', () async {
    final res = await request('GET', '/?t=wrong');
    expect(res.statusCode, HttpStatus.forbidden);
  });

  test('带会话 Cookie 可直接访问首页', () async {
    final res = await request(
      'GET',
      '/',
      headers: {HttpHeaders.cookieHeader: 'himi_cfg=${server.token}'},
    );
    expect(res.statusCode, HttpStatus.ok);
  });

  test('POST /api/emby 携带 token → 触发回调并返回成功', () async {
    final res = await request(
      'POST',
      '/api/emby?t=${server.token}',
      body: {
        'url': 'http://emby.lan',
        'username': 'alice',
        'password': 'pw',
      },
    );
    expect(res.statusCode, HttpStatus.ok);
    final json = jsonDecode(await bodyOf(res)) as Map<String, dynamic>;
    expect(json['ok'], isTrue);
    expect(capturedEmby['url'], 'http://emby.lan');
    expect(capturedEmby['username'], 'alice');
  });

  test('回调返回业务错误 → 400 且携带 error 文案', () async {
    embyError = '登录失败：用户名或密码错误';
    final res = await request(
      'POST',
      '/api/emby?t=${server.token}',
      body: {'url': 'x', 'username': 'y'},
    );
    expect(res.statusCode, HttpStatus.badRequest);
    final json = jsonDecode(await bodyOf(res)) as Map<String, dynamic>;
    expect(json['ok'], isFalse);
    expect(json['error'], '登录失败：用户名或密码错误');
  });

  test('回调抛异常 → 400 且错误文本可见', () async {
    server = LanConfigServer(
      basePort: 0,
      onEmby: (body) async => throw Exception('连接超时'),
    );
    await server.start();
    final res = await request(
      'POST',
      '/api/emby?t=${server.token}',
      body: {'url': 'x'},
    );
    expect(res.statusCode, HttpStatus.badRequest);
    final json = jsonDecode(await bodyOf(res)) as Map<String, dynamic>;
    expect(json['ok'], isFalse);
    expect(json['error'], contains('连接超时'));
  });

  test('POST /api/agora → 404（声网扫码管道已移除）', () async {
    final res = await request(
      'POST',
      '/api/agora?t=${server.token}',
      body: {'appId': 'id123', 'appCertificate': 'cert456'},
    );
    expect(res.statusCode, HttpStatus.notFound);
    await bodyOf(res);
  });

  test('POST 无凭据 → 403，回调不触发', () async {
    final res = await request('POST', '/api/emby', body: {'url': 'x'});
    expect(res.statusCode, HttpStatus.forbidden);
    expect(capturedEmby, isEmpty);
  });

  test('POST /api/danmaku 未接入回调 → 404', () async {
    final res = await request(
      'POST',
      '/api/danmaku?t=${server.token}',
      body: {'url': 'http://danmaku.lan'},
    );
    expect(res.statusCode, HttpStatus.notFound);
    await bodyOf(res);
  });

  group('onDanmaku 已接入', () {
    late LanConfigServer danmakuServer;
    late Map<String, dynamic> capturedDanmaku;
    String? danmakuError;

    setUp(() async {
      capturedDanmaku = {};
      danmakuError = null;
      danmakuServer = LanConfigServer(
        basePort: 0,
        onEmby: (body) async => null,
        onDanmaku: (body) async {
          capturedDanmaku = body;
          return danmakuError;
        },
      );
      await danmakuServer.start();
    });

    tearDown(() async {
      await danmakuServer.stop();
    });

    Future<HttpClientResponse> postDanmaku(Object body) async {
      final client = HttpClient()..findProxy = ((_) => 'DIRECT');
      addTearDown(client.close);
      final req = await client.openUrl(
        'POST',
        Uri.parse(
            'http://127.0.0.1:${danmakuServer.port}/api/danmaku?t=${danmakuServer.token}'),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      return req.close();
    }

    test('携带 token → 触发回调并返回成功', () async {
      final res = await postDanmaku({'url': 'http://192.168.1.10:9321/tok'});
      expect(res.statusCode, HttpStatus.ok);
      final json = jsonDecode(await utf8.decoder.bind(res).join())
          as Map<String, dynamic>;
      expect(json['ok'], isTrue);
      expect(json['message'], contains('弹幕'));
      expect(capturedDanmaku['url'], 'http://192.168.1.10:9321/tok');
    });

    test('回调返回业务错误 → 400 且携带 error 文案', () async {
      danmakuError = '地址格式非法';
      final res = await postDanmaku({'url': 'x'});
      expect(res.statusCode, HttpStatus.badRequest);
      final json = jsonDecode(await utf8.decoder.bind(res).join())
          as Map<String, dynamic>;
      expect(json['ok'], isFalse);
      expect(json['error'], '地址格式非法');
    });
  });

  test('非法 JSON body → 400', () async {
    final client = HttpClient()..findProxy = ((_) => 'DIRECT');
    addTearDown(client.close);
    final req = await client.openUrl(
      'POST',
      Uri.parse('${base()}/api/emby?t=${server.token}'),
    );
    req.write('not-json');
    final res = await req.close();
    expect(res.statusCode, HttpStatus.badRequest);
    await bodyOf(res);
  });

  test('未知路径带 token → 404', () async {
    final res = await request('GET', '/nope?t=${server.token}');
    expect(res.statusCode, HttpStatus.notFound);
  });

  test('stop 后端口释放，连接被拒绝', () async {
    final port = server.port;
    await server.stop();
    expect(server.isRunning, isFalse);
    expect(server.url, isNull);

    final client = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = const Duration(seconds: 2);
    addTearDown(client.close);
    expect(
      () async {
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
        await req.close();
      },
      throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
    );
  });
}
