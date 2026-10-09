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

  setUp(() {
    setup = _StubEmbySetup();
    container = ProviderContainer(
      overrides: [
        lanConfigBasePortProvider.overrideWithValue(0),
        embySetupServiceProvider.overrideWithValue(setup),
        agoraConfigProvider.overrideWith((ref) => FakeAgoraConfigNotifier()),
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier()),
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

  test('手机提交弹幕 API 地址成功 → 落 settings.danmakuApiUrl 且状态记录成功',
      () async {
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
}
