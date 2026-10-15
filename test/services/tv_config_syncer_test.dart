import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/server_route.dart';
import 'package:himi_syncwatch/services/tv_sync/tv_config_syncer.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _cfg({
  String id = '',
  String serverId = 'srv_a',
  String serverUrl = 'http://emby.a',
  String serverName = 'A',
  String username = 'user',
  String? accessToken = 'tok',
  String? userId = 'u1',
  List<ServerRoute> routes = const [],
}) =>
    EmbyServerConfig(
      id: id,
      serverUrl: serverUrl,
      serverName: serverName,
      serverId: serverId,
      username: username,
      accessToken: accessToken,
      userId: userId,
      routes: routes,
    );

void main() {
  late FakeEmbyAuthService auth;
  late TvConfigSyncer syncer;

  setUp(() {
    auth = FakeEmbyAuthService();
    syncer = TvConfigSyncer(auth: auth);
  });

  test('空库推入一台：进列表 + activateTarget 非空 + 落盘', () async {
    final result = await syncer.upsert(
      existing: [],
      incoming: [
        _cfg(id: 'phone_1'),
      ],
    );
    expect(result.ok, isTrue);
    expect(result.list, hasLength(1));
    expect(result.list.single.id, 'phone_1');
    expect(result.list.single.serverId, 'srv_a');
    // TV 端原本为空 → 激活首台
    expect(result.activateTarget, isNotNull);
    expect(result.activateTarget!.id, 'phone_1');
    // 顺序包含新 id
    expect(auth.lastSavedServerOrder, ['phone_1']);
    // saveSession 参数正确
    expect(auth.lastSavedActiveRouteUrl, isNull);
    expect(auth.lastSavedSessionRoutes, isEmpty);
  });

  test('同 serverId 再推：覆盖配置但保留本地 id', () async {
    final existing = [
      _cfg(id: 'local_keep', serverId: 'srv_a', accessToken: 'old'),
    ];
    auth.serverOrder = ['local_keep'];
    final result = await syncer.upsert(
      existing: existing,
      incoming: [
        _cfg(
          id: 'phone_other',
          serverId: 'srv_a',
          serverUrl: 'http://emby.a.v2',
          serverName: 'A升级',
          accessToken: 'new',
        ),
      ],
    );
    expect(result.ok, isTrue);
    expect(result.list, hasLength(1));
    // 本地 id 保留 → server_order / 选中引用不破坏
    expect(result.list.single.id, 'local_keep');
    expect(result.list.single.serverUrl, 'http://emby.a.v2');
    expect(result.list.single.accessToken, 'new');
    // 已有服务器不重复激活
    expect(result.activateTarget, isNull);
    expect(auth.lastSavedServerOrder, ['local_keep']);
    expect(result.syncedCount, 1);
  });

  test('多台推入：新服务器追加末尾，旧的保持原位', () async {
    final existing = [
      _cfg(id: 'keep_1', serverId: 'srv_x'),
      _cfg(id: 'keep_2', serverId: 'srv_y'),
    ];
    auth.serverOrder = ['keep_2', 'keep_1']; // 顺序与列表不同，验证按 order 保留
    final result = await syncer.upsert(
      existing: existing,
      incoming: [
        _cfg(id: 'p_new1', serverId: 'srv_new1'),
        _cfg(id: 'p_new2', serverId: 'srv_new2'),
      ],
    );
    expect(result.ok, isTrue);
    expect(result.list.map((s) => s.id).toList(),
        ['keep_1', 'keep_2', 'p_new1', 'p_new2']);
    // order 保留原有相对顺序，新 id 追加末尾
    expect(auth.lastSavedServerOrder, ['keep_2', 'keep_1', 'p_new1', 'p_new2']);
    // wasEmpty=false → 不激活
    expect(result.activateTarget, isNull);
    expect(result.syncedCount, 2);
  });

  test('新服务器本地 id 冲突 → 生成 srv_ 前缀随机 id', () async {
    final existing = [_cfg(id: 'dup_id', serverId: 'srv_x')];
    final result = await syncer.upsert(
      existing: existing,
      incoming: [
        _cfg(id: 'dup_id', serverId: 'srv_y'),
      ],
    );
    expect(result.ok, isTrue);
    expect(result.list, hasLength(2));
    final added = result.list[1];
    expect(added.serverId, 'srv_y');
    expect(added.id, startsWith('srv_'));
    expect(added.id, isNot('dup_id'));
    expect(auth.lastSavedServerOrder, contains(added.id));
  });

  test('未登录/缺字段的条目被跳过；全部无效 → 业务错误', () async {
    final result = await syncer.upsert(
      existing: [],
      incoming: [
        _cfg(id: 'n1', accessToken: null), // 未登录
        _cfg(id: 'n2', userId: null), // 未登录
        _cfg(id: 'n3', serverId: ''), // 缺 serverId
        _cfg(id: 'n4', serverUrl: ''), // 缺 serverUrl
      ],
    );
    expect(result.ok, isFalse);
    expect(result.error, contains('没有可同步的服务器'));
    expect(result.list, isEmpty);

    // 部分有效：只接收有效条目
    final partial = await syncer.upsert(
      existing: [],
      incoming: [
        _cfg(id: 'bad', accessToken: null),
        _cfg(id: 'good', serverId: 'srv_good'),
      ],
    );
    expect(partial.ok, isTrue);
    expect(partial.list, hasLength(1));
    expect(partial.list.single.id, 'good');
    expect(partial.syncedCount, 1);
  });

  test('列表为空但 storage 已有服务器 → 不激活（wasEmpty 双条件）', () async {
    final withStorage = FakeEmbyAuthService(serverIds: ['exists']);
    final syncer2 = TvConfigSyncer(auth: withStorage);
    final result = await syncer2.upsert(
      existing: [],
      incoming: [_cfg(id: 'p1')],
    );
    expect(result.ok, isTrue);
    expect(result.activateTarget, isNull);
  });

  test('routes / activeRouteUrl / autoFailover 透传落盘', () async {
    final routes = [
      const ServerRoute(id: 'r1', name: '备用', url: 'http://proxy.a'),
    ];
    final result = await syncer.upsert(
      existing: [],
      incoming: [
        _cfg(
          id: 'p_r',
          serverId: 'srv_r',
          routes: routes,
          accessToken: 't',
          userId: 'u',
        ),
      ],
    );
    expect(result.ok, isTrue);
    expect(result.list.single.routes, hasLength(1));
    expect(auth.lastSavedSessionRoutes, hasLength(1));
  });
}
