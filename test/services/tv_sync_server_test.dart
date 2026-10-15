import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/services/tv_sync/tv_sync_server.dart';

void main() {
  late TvSyncServer server;
  bool? pairDecision;
  List<EmbyServerConfig>? syncedServers;
  String? syncError;

  setUp(() async {
    pairDecision = true;
    syncedServers = null;
    syncError = null;
    server = TvSyncServer(
      deviceId: 'tv_1',
      deviceName: '客厅电视',
      basePort: 0,
      onPairRequest: (phone, ip) async => pairDecision!,
      onSync: (servers) async {
        syncedServers = servers;
        return syncError;
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

  Future<Map<String, dynamic>> jsonOf(HttpClientResponse res) async {
    final raw = await utf8.decoder.bind(res).join();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  test('启动后生成 32 位 token 并可查询 info', () async {
    expect(server.isRunning, isTrue);
    expect(server.token, hasLength(32));
    final res = await request('GET', '/api/info');
    expect(res.statusCode, 200);
    final data = await jsonOf(res);
    expect(data['ok'], isTrue);
    expect(data['deviceId'], 'tv_1');
    expect(data['name'], '客厅电视');
  });

  test('POST /api/pair 同意 → 返回 token；拒绝 → 403', () async {
    var res = await request('POST', '/api/pair', body: {'phoneName': '小米13'});
    expect(res.statusCode, 200);
    var data = await jsonOf(res);
    expect(data['ok'], isTrue);
    expect(data['token'], server.token);

    pairDecision = false;
    res = await request('POST', '/api/pair', body: {'phoneName': '小米13'});
    expect(res.statusCode, 403);
    data = await jsonOf(res);
    expect(data['ok'], isFalse);
  });

  test('POST /api/sync 无 token → 403；带 token → 落到 onSync', () async {
    final serverJson = EmbyServerConfig(
      id: 'local_1',
      serverUrl: 'http://emby.local',
      serverName: 'Emby',
      serverId: 'srv_a',
      username: 'user',
      accessToken: 'tok',
      userId: 'u_1',
    ).toJson();

    var res = await request(
      'POST',
      '/api/sync',
      body: {'servers': [serverJson]},
    );
    expect(res.statusCode, 403);
    expect(syncedServers, isNull);

    res = await request(
      'POST',
      '/api/sync',
      headers: {TvSyncServer.tokenHeader: server.token!},
      body: {'servers': [serverJson]},
    );
    expect(res.statusCode, 200);
    final data = await jsonOf(res);
    expect(data['ok'], isTrue);
    expect(data['synced'], 1);
    expect(syncedServers, hasLength(1));
    expect(syncedServers!.single.serverId, 'srv_a');
  });

  test('POST /api/sync 非法 body → 400', () async {
    final res = await request(
      'POST',
      '/api/sync',
      headers: {TvSyncServer.tokenHeader: server.token!},
      body: {'servers': 'not-a-list'},
    );
    expect(res.statusCode, 400);
    expect(syncedServers, isNull);
  });

  test('onSync 返回错误文案 → 400 且透传 error', () async {
    syncError = '没有可同步的服务器';
    final res = await request(
      'POST',
      '/api/sync',
      headers: {TvSyncServer.tokenHeader: server.token!},
      body: {
        'servers': [
          EmbyServerConfig(
            id: 'l',
            serverUrl: 'http://e',
            serverName: 'n',
            serverId: 's',
            username: 'u',
            accessToken: 't',
            userId: 'u1',
          ).toJson(),
        ],
      },
    );
    expect(res.statusCode, 400);
    final data = await jsonOf(res);
    expect(data['error'], '没有可同步的服务器');
  });

  test('未知路径 → 404；stop 后端口释放', () async {
    final res = await request('GET', '/nope');
    expect(res.statusCode, 404);
    await server.stop();
    expect(server.isRunning, isFalse);
  });
}
