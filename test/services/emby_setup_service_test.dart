import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/lan_config/emby_setup_service.dart';

import '../helpers/test_fakes.dart';

class _RecordingAuthService extends FakeEmbyAuthService {
  final List<String> deletedSessions = [];
  final List<Map<String, dynamic>> savedSessions = [];
  String? selectedId;

  @override
  Future<void> saveSession({
    required String serverId,
    required String serverUrl,
    required String serverName,
    required String userId,
    required String username,
    required String id,
    required String accessToken,
  }) async {
    savedSessions.add({
      'serverId': serverId,
      'serverUrl': serverUrl,
      'serverName': serverName,
      'userId': userId,
      'username': username,
      'id': id,
      'accessToken': accessToken,
    });
  }

  @override
  Future<void> deleteSession(String serverId) async {
    deletedSessions.add(serverId);
  }

  @override
  Future<void> saveSelectedServerId(String configId) async {
    selectedId = configId;
  }
}

void main() {
  late FakeEmbyService emby;
  late _RecordingAuthService auth;
  late EmbyServerListNotifier serverList;
  late EmbyConfigNotifier config;
  late EmbySetupService service;

  EmbyServerConfig oldServer() => EmbyServerConfig(
        id: 'old_id',
        serverUrl: 'http://old',
        serverName: '旧服务器',
        serverId: 'srv_ping_1',
        username: 'olduser',
        accessToken: 'old_token',
        userId: 'old_user',
      );

  setUp(() {
    emby = FakeEmbyService();
    auth = _RecordingAuthService();
    serverList = EmbyServerListNotifier();
    config = EmbyConfigNotifier();
    service = EmbySetupService(
      embyService: emby,
      authService: auth,
      serverListNotifier: serverList,
      configNotifier: config,
      readServers: () => serverList.state,
    );
  });

  test('成功链路：ping → 认证 → 保存会话 → 入列表 → 激活', () async {
    final result = await service.addAndActivate(
      serverUrl: '  http://emby.lan:8096 ',
      username: '  alice ',
      password: 'pw',
    );

    expect(result.serverUrl, 'http://emby.lan:8096');
    expect(result.username, 'alice');
    expect(result.serverName, '测试服务器');
    expect(result.accessToken, 'token_1');
    expect(result.userId, 'user_1');
    expect(emby.lastAuthUsername, 'alice');
    expect(emby.lastAuthPassword, 'pw');

    expect(auth.savedSessions, hasLength(1));
    expect(auth.savedSessions.single['accessToken'], 'token_1');
    expect(auth.savedSessions.single['serverId'], 'srv_ping_1');
    expect(auth.selectedId, result.id);

    expect(serverList.state, hasLength(1));
    expect(serverList.state.single.id, result.id);
    expect(config.state?.id, result.id);
  });

  test('字段为空：抛出提示且不发起请求', () async {
    await expectLater(
      service.addAndActivate(
        serverUrl: '',
        username: 'alice',
        password: 'pw',
      ),
      throwsA(isA<EmbySetupException>().having(
        (e) => e.message,
        'message',
        contains('不能为空'),
      )),
    );
    await expectLater(
      service.addAndActivate(
        serverUrl: 'http://x',
        username: '   ',
        password: 'pw',
      ),
      throwsA(isA<EmbySetupException>()),
    );
    expect(auth.savedSessions, isEmpty);
    expect(serverList.state, isEmpty);
  });

  test('认证返回空 token：抛出且不落库不激活', () async {
    emby.authResult = const {
      'User': {'Id': 'user_1'},
      'AccessToken': '',
      'ServerId': 'srv_ping_1',
    };

    await expectLater(
      service.addAndActivate(
        serverUrl: 'http://emby.lan',
        username: 'alice',
        password: 'bad',
      ),
      throwsA(isA<EmbySetupException>().having(
        (e) => e.message,
        'message',
        contains('登录失败'),
      )),
    );
    expect(auth.savedSessions, isEmpty);
    expect(serverList.state, isEmpty);
    expect(config.state, isNull);
  });

  test('网络异常原样抛出（不吞错）', () async {
    emby.pingError = Exception('连接超时');

    await expectLater(
      service.addAndActivate(
        serverUrl: 'http://down',
        username: 'alice',
        password: 'pw',
      ),
      throwsA(isA<Exception>()),
    );
    expect(serverList.state, isEmpty);
  });

  test('重复 serverId：删旧会话并移除旧条目，仅保留新配置', () async {
    serverList.addServer(oldServer());

    final result = await service.addAndActivate(
      serverUrl: 'http://new',
      username: 'alice',
      password: 'pw',
    );

    expect(auth.deletedSessions, ['srv_ping_1']);
    expect(serverList.state, hasLength(1));
    expect(serverList.state.single.id, result.id);
    expect(serverList.state.single.serverUrl, 'http://new');
  });

  test('备注名优先于服务端名称，并回调 onServerInfo', () async {
    String? notified;
    final result = await service.addAndActivate(
      serverUrl: 'http://emby.lan',
      username: 'alice',
      password: 'pw',
      serverName: ' 家里NAS ',
      onServerInfo: (name) => notified = name,
    );

    expect(result.serverName, '家里NAS');
    expect(notified, '家里NAS');
  });
}
