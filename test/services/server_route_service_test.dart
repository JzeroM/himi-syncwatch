import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/server_route.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/server_route_service.dart';

import '../helpers/test_fakes.dart';

/// 可注入 ping 结果的 ServerRouteService 测试夹具。
///
/// [pingResults] value = 模拟延迟 ms（fake ping 真实 sleep，
/// 让 Stopwatch 测量出可比较的延迟）；key 不存在 = 不可达。
({ServerRouteService svc, EmbyServerListNotifier list, EmbyConfigNotifier config, FakeEmbyAuthService auth})
    _fixture({Map<String, int> pingResults = const {}}) {
  final auth = FakeEmbyAuthService();
  final list = EmbyServerListNotifier();
  final config = EmbyConfigNotifier();
  final svc = ServerRouteService(
    authService: auth,
    serverListNotifier: list,
    configNotifier: config,
    readServers: () => list.state,
    readActiveConfig: () => config.state,
    ping: (url) async {
      final ms = pingResults[url];
      if (ms == null) throw Exception('unreachable: $url');
      await Future<void>.delayed(Duration(milliseconds: ms));
      return {'latency': ms};
    },
  );
  return (svc: svc, list: list, config: config, auth: auth);
}

EmbyServerConfig _server({List<ServerRoute> routes = const []}) =>
    EmbyServerConfig(
      id: 'cfg1',
      serverUrl: 'http://main:8096',
      serverName: 'NAS',
      serverId: 'srv1',
      username: 'u',
      accessToken: 'tok',
      userId: 'uid',
      routes: routes,
    );

const _r1 = ServerRoute(id: 'r1', name: '线路1', url: 'http://r1:8096');
const _r2 = ServerRoute(id: 'r2', name: '线路2', url: 'http://r2:8096');

void main() {
  group('ServerRouteService.addRoute', () {
    test('添加线路 → 列表更新 + session 落盘', () async {
      final f = _fixture();
      final cfg = _server();
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      final route = await f.svc.addRoute(
        cfg,
        name: '备用',
        url: 'http://backup:8096',
        isReverseProxy: false,
      );

      expect(f.list.state.single.routes, hasLength(1));
      expect(f.list.state.single.routes.single.url, 'http://backup:8096');
      expect(f.auth.updateSessionRoutesCalls, 1);
      expect(f.auth.lastSessionRoutes, [route.toJson()]);
    });
  });

  group('ServerRouteService.switchRoute', () {
    test('切到备用线路 → activeRouteUrl 更新 + 激活 config 同步', () async {
      final f = _fixture();
      final cfg = _server(routes: [_r1]);
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      await f.svc.switchRoute(cfg, _r1.url);

      expect(f.list.state.single.activeRouteUrl, _r1.url);
      expect(f.config.state?.activeRouteUrl, _r1.url);
      expect(f.config.state?.effectiveUrl, _r1.url);
      expect(f.auth.lastActiveRouteUrl, _r1.url);
    });

    test('回主线路 → activeRouteUrl 清空', () async {
      final f = _fixture();
      final cfg = _server(routes: [_r1]).copyWith(activeRouteUrl: _r1.url);
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      await f.svc.switchRoute(cfg, null);

      expect(f.list.state.single.activeRouteUrl, isNull);
      expect(f.config.state?.effectiveUrl, 'http://main:8096');
      expect(f.auth.lastActiveRouteUrl, isNull);
    });

    test('非激活服务器不更新 config', () async {
      final f = _fixture();
      final other = EmbyServerConfig(
        id: 'cfg2',
        serverUrl: 'http://other:8096',
        serverName: 'Other',
        serverId: 'srv2',
        username: 'u',
        accessToken: 'tok',
        userId: 'uid',
        routes: const [_r1],
      );
      f.list.addServer(other);
      // 激活的是另一台
      f.config.setConfig(_server());

      await f.svc.switchRoute(other, _r1.url);

      expect(f.list.state.firstWhere((s) => s.id == 'cfg2').activeRouteUrl,
          _r1.url);
      expect(f.config.state?.activeRouteUrl, isNull);
    });
  });

  group('ServerRouteService.reorderRoutes', () {
    test('ReorderableListView 语义：拖到末尾 newIndex=列表长（0→2）', () async {
      final f = _fixture();
      final cfg = _server(routes: [_r1, _r2]);
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      // 把第 0 项拖到第 2 项之后（2 项列表的末尾 drop 点）
      await f.svc.reorderRoutes(0, 2);
      expect(
        f.list.state.single.routes.map((r) => r.id).toList(),
        ['r2', 'r1'],
      );
    });

    test('向上拖（1→0）顺序反转', () async {
      final f = _fixture();
      final cfg = _server(routes: [_r1, _r2]);
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      await f.svc.reorderRoutes(1, 0);
      expect(
        f.list.state.single.routes.map((r) => r.id).toList(),
        ['r2', 'r1'],
      );
    });

    test('同位置 no-op', () async {
      final f = _fixture();
      final cfg = _server(routes: [_r1, _r2]);
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      await f.svc.reorderRoutes(1, 1);
      expect(
        f.list.state.single.routes.map((r) => r.id).toList(),
        ['r1', 'r2'],
      );
    });

    test('无激活服务器时直接返回', () async {
      final f = _fixture();
      await f.svc.reorderRoutes(0, 1);
      expect(f.list.state, isEmpty);
    });
  });

  group('ServerRouteService.failoverIfNeeded', () {
    test('无备用线路 → 不切', () async {
      final f = _fixture(pingResults: {'http://main:8096': 50});
      final cfg = _server();
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      expect(await f.svc.failoverIfNeeded(cfg), isNull);
      expect(f.list.state.single.activeRouteUrl, isNull);
    });

    test('当前可达 → 不切', () async {
      final f = _fixture(pingResults: {
        'http://main:8096': 50,
        _r1.url: 10,
        _r2.url: 20,
      });
      final cfg = _server(routes: [_r1, _r2]);
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      expect(await f.svc.failoverIfNeeded(cfg), isNull);
      expect(f.list.state.single.activeRouteUrl, isNull);
    });

    test('主线路不可达 → 切延迟最低可达线路', () async {
      final f = _fixture(pingResults: {
        // main 不可达
        _r1.url: 120,
        _r2.url: 80,
      });
      final cfg = _server(routes: [_r1, _r2]);
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      final switched = await f.svc.failoverIfNeeded(cfg);

      expect(switched, isNotNull);
      expect(f.list.state.single.activeRouteUrl, _r2.url);
      expect(f.auth.lastActiveRouteUrl, _r2.url);
    });

    test('激活线路不可达且主线路可达 → 切回主线路', () async {
      final f = _fixture(pingResults: {
        'http://main:8096': 40,
        // _r1 不可达
      });
      final cfg =
          _server(routes: [_r1]).copyWith(activeRouteUrl: _r1.url);
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      final switched = await f.svc.failoverIfNeeded(cfg);

      expect(switched, isNotNull);
      expect(f.list.state.single.activeRouteUrl, isNull);
    });

    test('全部不可达 → 不切', () async {
      final f = _fixture(); // 全部 ping 抛异常
      final cfg = _server(routes: [_r1, _r2]);
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      expect(await f.svc.failoverIfNeeded(cfg), isNull);
      expect(f.list.state.single.activeRouteUrl, isNull);
    });

    test('激活线路可达但主线路不可达 → 不动（当前可达即不切）', () async {
      final f = _fixture(pingResults: {
        // main 不可达
        _r1.url: 30,
      });
      final cfg =
          _server(routes: [_r1]).copyWith(activeRouteUrl: _r1.url);
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      expect(await f.svc.failoverIfNeeded(cfg), isNull);
      expect(f.list.state.single.activeRouteUrl, _r1.url);
    });
  });

  group('ServerRouteService.setAutoFailover', () {
    test('开关翻转 → 更新 + 落盘', () async {
      final f = _fixture();
      final cfg = _server();
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      await f.svc.setAutoFailover(cfg, false);

      expect(f.list.state.single.autoFailover, false);
      expect(f.auth.lastAutoFailover, false);
    });

    test('值不变 no-op', () async {
      final f = _fixture();
      final cfg = _server();
      f.list.addServer(cfg);
      f.config.setConfig(cfg);

      await f.svc.setAutoFailover(cfg, true); // 默认已是 true
      expect(f.auth.updateSessionRoutesCalls, 0);
    });
  });

  group('ServerRouteService.measureAll', () {
    test('主线路 + 备用全部并发测速，按序返回', () async {
      final f = _fixture(pingResults: {
        'http://main:8096': 30,
        _r1.url: 60,
        _r2.url: 10,
      });
      final cfg = _server(routes: [_r1, _r2]);

      final probe = await f.svc.measureAll(cfg);

      expect(probe.main.url, 'http://main:8096');
      expect(probe.main.reachable, true);
      // 按注入延迟排序：r2 最快 < main < r1
      expect(probe.routes[1].latencyMs! < probe.main.latencyMs!, true);
      expect(probe.main.latencyMs! < probe.routes[0].latencyMs!, true);
      expect(probe.routes.map((r) => r.url).toList(), [_r1.url, _r2.url]);
    });

    test('不可达线路 latencyMs=null', () async {
      final f = _fixture(pingResults: {'http://main:8096': 10});
      final cfg = _server(routes: [_r1]);

      final probe = await f.svc.measureAll(cfg);
      expect(probe.routes.single.reachable, false);
    });
  });

  group('riverpod provider 接线', () {
    test('serverRouteServiceProvider 可从容器解析', () {
      final container = ProviderContainer(
        overrides: [
          embyAuthServiceProvider.overrideWithValue(FakeEmbyAuthService()),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(serverRouteServiceProvider), isNotNull);
    });
  });
}
