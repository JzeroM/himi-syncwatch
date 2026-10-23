import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/providers/lan_config_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/lan_config/emby_setup_service.dart';

import '../helpers/test_fakes.dart';

class _StubEmbySetup extends EmbySetupService {
  _StubEmbySetup()
      : super(
          embyService: FakeEmbyService(),
          authService: FakeEmbyAuthService(),
          serverListNotifier: EmbyServerListNotifier(),
          configNotifier: EmbyConfigNotifier(),
          readServers: () => const [],
        );

  /// 成功时返回的服务器名（仅用于断言参数传递）。
  String? result;
  Object? error;
  Map<String, dynamic>? lastCall;

  @override
  Future<EmbyServerConfig> addAndActivate({
    required String serverUrl,
    required String username,
    required String password,
    String? serverName,
    void Function(String serverName)? onServerInfo,
  }) async {
    lastCall = {
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'serverName': serverName,
    };
    if (error != null) throw error!;
    onServerInfo?.call(result ?? 'stub');
    return EmbyServerConfig(
      id: 'stub',
      serverUrl: serverUrl,
      serverName: result ?? 'stub',
      serverId: 'stub_srv',
      username: username,
      accessToken: 'token',
      userId: 'user',
    );
  }
}

void main() {
  late ProviderContainer container;
  late _StubEmbySetup setup;
  late FakeEmbyAuthService auth;

  EmbyServerConfig _routeTarget() => EmbyServerConfig(
        id: 'cfg1',
        serverUrl: 'http://main:8096',
        serverName: 'NAS',
        serverId: 'srv1',
        username: 'u',
        accessToken: 'tok',
        userId: 'uid',
      );

  setUp(() {
    setup = _StubEmbySetup();
    auth = FakeEmbyAuthService();
    container = ProviderContainer(
      overrides: [
        lanConfigBasePortProvider.overrideWithValue(0),
        embySetupServiceProvider.overrideWithValue(setup),
        agoraConfigProvider.overrideWith((ref) => FakeAgoraConfigNotifier()),
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
        embyAuthServiceProvider.overrideWithValue(auth),
        embyServerListProvider.overrideWith(
          (ref) => EmbyServerListNotifier()..setList([_routeTarget()]),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<HttpClientResponse> post(String path, Object body) async {
    final state = container.read(lanConfigProvider);
    final token = Uri.parse(state.url!).queryParameters['t'];
    final client = HttpClient()..findProxy = ((_) => 'DIRECT');
    addTearDown(client.close);
    final req = await client.openUrl(
      'POST',
      Uri.parse('http://127.0.0.1:${state.port}$path?t=$token'),
    );
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    return req.close();
  }

  Future<Map<String, dynamic>> jsonOf(HttpClientResponse res) async {
    final text = await utf8.decoder.bind(res).join();
    return jsonDecode(text) as Map<String, dynamic>;
  }

  test('start 后进入 running 并给出 url/port；stop 复位', () async {
    await container.read(lanConfigProvider.notifier).start();
    var state = container.read(lanConfigProvider);
    expect(state.running, isTrue);
    expect(state.url, startsWith('http://'));
    expect(state.port, isNotNull);

    await container.read(lanConfigProvider.notifier).stop();
    state = container.read(lanConfigProvider);
    expect(state.running, isFalse);
    expect(state.url, isNull);
    expect(state.port, isNull);
    expect(state.lastMessage, isNull);
  });

  test('手机提交 Emby 成功 → 状态记录成功且参数透传', () async {
    await container.read(lanConfigProvider.notifier).start();
    setup.result = '家里NAS';

    final res = await post('/api/emby', {
      'url': 'http://emby.lan',
      'name': '家里NAS',
      'username': 'alice',
      'password': 'pw',
    });
    expect(res.statusCode, HttpStatus.ok);
    expect(await jsonOf(res), containsPair('ok', true));

    final state = container.read(lanConfigProvider);
    expect(state.lastOk, isTrue);
    expect(setup.lastCall, containsPair('serverUrl', 'http://emby.lan'));
    expect(setup.lastCall, containsPair('username', 'alice'));
    expect(setup.lastCall, containsPair('serverName', '家里NAS'));
  });

  test('Emby 业务失败 → 400 且状态记录失败文案', () async {
    await container.read(lanConfigProvider.notifier).start();
    setup.error = EmbySetupException('登录失败：用户名或密码错误');

    final res = await post('/api/emby', {'url': 'x', 'username': 'y'});
    expect(res.statusCode, HttpStatus.badRequest);
    expect(await jsonOf(res), containsPair('error', '登录失败：用户名或密码错误'));

    final state = container.read(lanConfigProvider);
    expect(state.lastOk, isFalse);
    expect(state.lastMessage, '登录失败：用户名或密码错误');
  });

  test('POST /api/agora → 404（声网扫码已移除，仅保留手动配置）', () async {
    await container.read(lanConfigProvider.notifier).start();

    final res = await post('/api/agora', {
      'appId': 'app_id_1',
      'appCertificate': 'cert_1',
    });
    expect(res.statusCode, HttpStatus.notFound);
    await jsonOf(res);

    expect(container.read(agoraConfigProvider), isNull, reason: '不落库');
    expect(container.read(lanConfigProvider).lastOk, isNull, reason: '不触碰提交状态');
  });

  test('手机提交弹幕 API 地址成功 → 落 settings.danmakuApiUrl 且状态记录成功', () async {
    await container.read(lanConfigProvider.notifier).start();

    final res = await post('/api/danmaku', {
      'url': 'http://192.168.1.10:9321/tok123',
    });
    expect(res.statusCode, HttpStatus.ok);
    expect(await jsonOf(res), containsPair('ok', true));

    expect(
      container.read(settingsProvider).danmakuApiUrl,
      'http://192.168.1.10:9321/tok123',
    );
    final state = container.read(lanConfigProvider);
    expect(state.lastOk, isTrue);
    expect(state.lastMessage, contains('弹幕'));
  });

  test('弹幕提交空地址 → 落库为空串并记录成功（清空场景）', () async {
    await container.read(lanConfigProvider.notifier).start();

    final res = await post('/api/danmaku', {'url': ''});
    expect(res.statusCode, HttpStatus.ok);
    expect(container.read(settingsProvider).danmakuApiUrl, '');
  });

  test('手机提交 TMDB 配置 → 落库 API Key、代理与区域', () async {
    await container.read(lanConfigProvider.notifier).start();

    final res = await post('/api/tmdb', {
      'apiKey': 'tmdb-key',
      'apiBase': 'https://api.proxy.example.com',
      'imageBase': 'https://img.proxy.example.com',
      'region': 'JP',
    });
    expect(res.statusCode, HttpStatus.ok);
    expect(await jsonOf(res), containsPair('ok', true));

    final s = container.read(settingsProvider);
    expect(s.tmdbApiKey, 'tmdb-key');
    expect(s.tmdbApiBase, 'https://api.proxy.example.com');
    expect(s.tmdbImageBase, 'https://img.proxy.example.com');
    expect(s.tmdbWatchRegion, 'JP');
    expect(container.read(lanConfigProvider).lastMessage, contains('TMDB'));
  });

  test('TMDB 空 Key → 400，代理与区域留空时保留当前值', () async {
    await container.read(settingsProvider.notifier).update(
          tmdbApiBase: 'https://api.proxy.example.com',
          tmdbImageBase: 'https://img.proxy.example.com',
          tmdbWatchRegion: 'JP',
        );
    await container.read(lanConfigProvider.notifier).start();

    final empty = await post('/api/tmdb', {
      'apiKey': '',
      'apiBase': '',
      'imageBase': '',
      'region': '',
    });
    expect(empty.statusCode, HttpStatus.badRequest);
    expect(
      (await jsonOf(empty))['error'],
      contains('TMDB API Key'),
    );

    final ok = await post('/api/tmdb', {
      'apiKey': 'new-key',
      'apiBase': '',
      'imageBase': '',
      'region': '',
    });
    expect(ok.statusCode, HttpStatus.ok);

    final s = container.read(settingsProvider);
    expect(s.tmdbApiKey, 'new-key');
    expect(s.tmdbApiBase, 'https://api.proxy.example.com');
    expect(s.tmdbImageBase, 'https://img.proxy.example.com');
    expect(s.tmdbWatchRegion, 'JP');
  });

  group('POST /api/route 扫码添加备用线路（v1.1.243）', () {
    Future<Map<String, dynamic>> postRoute(Map<String, dynamic> body) async {
      final res = await post('/api/route', body);
      return {'status': res.statusCode, 'json': await jsonOf(res)};
    }

    test('未注入目标服务器 → 400 提示重新扫码', () async {
      await container.read(lanConfigProvider.notifier).start();

      final r = await postRoute({'host': '1.2.3.4', 'port': '8096'});
      expect(r['status'], HttpStatus.badRequest);
      expect((r['json'] as Map)['error'], contains('目标服务器不存在'));
      expect(container.read(lanConfigProvider).lastOk, isFalse);
    });

    test('目标服务器 + 分项字段 → 拼 URL 落库到该服务器', () async {
      final notifier = container.read(lanConfigProvider.notifier);
      notifier.routeTargetServerId = 'cfg1';
      await notifier.start();

      final r = await postRoute({
        'host': '192.168.1.20',
        'port': '8097',
        'path': '/emby',
        'https': false,
        'name': '客厅盒子',
        'reverseProxy': true,
      });
      expect(r['status'], HttpStatus.ok, reason: '${r['json']}');

      final updated = container.read(embyServerListProvider).single;
      expect(updated.routes, hasLength(1));
      expect(updated.routes.single.name, '客厅盒子');
      expect(updated.routes.single.url, 'http://192.168.1.20:8097/emby');
      expect(updated.routes.single.isReverseProxy, isTrue);

      // 落盘走 updateSessionRoutes（FakeAuth 记录）
      expect(auth.updateSessionRoutesCalls, 1);
      expect(auth.lastSessionRoutes!.single['url'],
          'http://192.168.1.20:8097/emby');

      expect(container.read(lanConfigProvider).lastOk, isTrue);
      expect(container.read(lanConfigProvider).lastMessage, contains('备用线路'));
    });

    test('host 传完整 IPv6 URL → 自动拆分后落库', () async {
      final notifier = container.read(lanConfigProvider.notifier);
      notifier.routeTargetServerId = 'cfg1';
      await notifier.start();

      final r = await postRoute({
        'host': 'https://[2408:85a3::8a2e:370:7334]:8920/emby',
        'port': '8096',
        'path': 'ignored',
        'https': false,
        'name': 'IPv6 线路',
      });
      expect(r['status'], HttpStatus.ok, reason: '${r['json']}');

      final updated = container.read(embyServerListProvider).single;
      expect(
        updated.routes.single.url,
        'https://[2408:85a3::8a2e:370:7334]:8920/emby',
        reason: '完整 URL 的 scheme/端口/path 应覆盖分项字段',
      );
    });

    test('空名称 → 默认 Route N；非法 host → 400', () async {
      final notifier = container.read(lanConfigProvider.notifier);
      notifier.routeTargetServerId = 'cfg1';
      await notifier.start();

      final ok = await postRoute({'host': '10.0.0.5', 'port': '8096'});
      expect(ok['status'], HttpStatus.ok, reason: '${ok['json']}');
      expect(container.read(embyServerListProvider).single.routes.single.name,
          'Route 1');

      final bad = await postRoute({'host': '', 'port': '8096'});
      expect(bad['status'], HttpStatus.badRequest);
      expect((bad['json'] as Map)['error'], contains('地址无效'));
      expect(container.read(lanConfigProvider).lastOk, isFalse);
    });
  });
}
