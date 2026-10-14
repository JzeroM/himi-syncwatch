import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/server_route.dart';

EmbyServerConfig _cfg({
  List<ServerRoute> routes = const [],
  String? activeRouteUrl,
  bool autoFailover = true,
}) =>
    EmbyServerConfig(
      id: 'cfg1',
      serverUrl: 'http://main:8096',
      serverName: 'NAS',
      serverId: 'srv1',
      username: 'u',
      accessToken: 'tok',
      userId: 'uid',
      routes: routes,
      activeRouteUrl: activeRouteUrl,
      autoFailover: autoFailover,
    );

const _direct = ServerRoute(id: 'r1', name: '直连', url: 'http://r1:8096');
const _proxy = ServerRoute(
  id: 'r2',
  name: '反代',
  url: 'https://proxy.example.com',
  isReverseProxy: true,
);

void main() {
  group('EmbyServerConfig 线路序列化', () {
    test('toJson/fromJson 往返保留 routes/activeRouteUrl/autoFailover', () {
      final cfg = _cfg(
        routes: const [_direct, _proxy],
        activeRouteUrl: 'http://r1:8096',
        autoFailover: false,
      );
      final back = EmbyServerConfig.fromJson(cfg.toJson());
      expect(back.routes, hasLength(2));
      expect(back.routes[1].isReverseProxy, true);
      expect(back.activeRouteUrl, 'http://r1:8096');
      expect(back.autoFailover, false);
    });

    test('fromJson 缺线路字段 → 默认空列表 / null / true', () {
      final back = EmbyServerConfig.fromJson(const {
        'id': 'a',
        'serverUrl': 'http://x',
      });
      expect(back.routes, isEmpty);
      expect(back.activeRouteUrl, isNull);
      expect(back.autoFailover, true);
    });
  });

  group('effectiveUrl / activeRoute / mediaUrl', () {
    test('未激活线路 → 主线路', () {
      final cfg = _cfg();
      expect(cfg.effectiveUrl, 'http://main:8096');
      expect(cfg.activeRoute, isNull);
      expect(cfg.mediaUrl, 'http://main:8096');
    });

    test('激活直连线路 → API 与媒体都走线路', () {
      final cfg = _cfg(routes: const [_direct], activeRouteUrl: _direct.url);
      expect(cfg.effectiveUrl, _direct.url);
      expect(cfg.activeRoute?.name, '直连');
      expect(cfg.mediaUrl, _direct.url);
    });

    test('激活反代线路 → API 走反代、媒体直连主线路（方案 2）', () {
      final cfg = _cfg(routes: const [_proxy], activeRouteUrl: _proxy.url);
      expect(cfg.effectiveUrl, _proxy.url);
      expect(cfg.mediaUrl, 'http://main:8096');
      expect(cfg.activeRoute?.isReverseProxy, true);
    });

    test('activeRouteUrl 指向不存在的线路 → activeRoute null，URL 仍生效', () {
      final cfg = _cfg(routes: const [_direct], activeRouteUrl: 'http://ghost');
      expect(cfg.activeRoute, isNull);
      expect(cfg.effectiveUrl, 'http://ghost');
      expect(cfg.mediaUrl, 'http://ghost');
    });
  });

  group('copyWith 线路字段', () {
    test('clearActiveRoute 优先于 activeRouteUrl', () {
      final cfg = _cfg(routes: const [_direct], activeRouteUrl: _direct.url);
      final back = cfg.copyWith(activeRouteUrl: null, clearActiveRoute: true);
      expect(back.activeRouteUrl, isNull);
      expect(back.routes, hasLength(1));
    });

    test('只改 autoFailover 保留其余', () {
      final cfg = _cfg(routes: const [_direct], activeRouteUrl: _direct.url);
      final back = cfg.copyWith(autoFailover: false);
      expect(back.autoFailover, false);
      expect(back.activeRouteUrl, _direct.url);
      expect(back.routes.single.id, 'r1');
    });
  });
}
