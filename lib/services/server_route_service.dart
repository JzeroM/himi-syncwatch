import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/server_route.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_auth_service.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

final serverRouteServiceProvider = Provider<ServerRouteService>((ref) {
  return ServerRouteService(
    authService: ref.read(embyAuthServiceProvider),
    serverListNotifier: ref.read(embyServerListProvider.notifier),
    configNotifier: ref.read(embyConfigProvider.notifier),
    readServers: () => ref.read(embyServerListProvider),
    readActiveConfig: () => ref.read(embyConfigProvider),
    ping: (url) => EmbyService().pingServer(url),
  );
});

/// 单条线路的测速结果。
class RouteProbeResult {
  const RouteProbeResult({required this.url, this.latencyMs});

  final String url;

  /// null = 不可达。
  final int? latencyMs;

  bool get reachable => latencyMs != null;
}

/// 服务器线路管理：增删改排序、测速、切换、自动故障转移。
///
/// 状态与持久化双写：`embyServerListProvider.updateServer` + 激活时
/// `embyConfigProvider.setConfig`（service 实例经 Riverpod 链自动重建），
/// 再 `updateSessionRoutes` 落盘 secure storage。
class ServerRouteService {
  ServerRouteService({
    required this.authService,
    required this.serverListNotifier,
    required this.configNotifier,
    required this.readServers,
    required this.readActiveConfig,
    required this.ping,
  });

  final EmbyAuthService authService;
  final EmbyServerListNotifier serverListNotifier;
  final EmbyConfigNotifier configNotifier;
  final List<EmbyServerConfig> Function() readServers;
  final EmbyServerConfig? Function() readActiveConfig;

  /// 注入可测：并发 ping 某 URL，返回耗时 ms；失败抛异常。
  final Future<Map<String, dynamic>> Function(String url) ping;

  /// 更新线路字段并落盘（列表 + 激活 + session 三写）。
  Future<void> persist(EmbyServerConfig config) async {
    serverListNotifier.updateServer(config);
    if (readActiveConfig()?.id == config.id) {
      configNotifier.setConfig(config);
    }
    await authService.updateSessionRoutes(
      serverId: config.serverId,
      routes: config.routes.map((r) => r.toJson()).toList(),
      activeRouteUrl: config.activeRouteUrl,
      autoFailover: config.autoFailover,
      strmDirectPlay: config.strmDirectPlay,
    );
  }

  /// 单线测速：ping [url] 返回延迟 ms；失败返回 null。
  Future<int?> measureUrl(String url) async {
    final sw = Stopwatch()..start();
    try {
      await ping(url);
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// 并发测速主线路 + 全部备用线路，按 [config.routes] 顺序返回备用结果，
  /// 主线路结果放 [mainResult]。
  Future<({RouteProbeResult main, List<RouteProbeResult> routes})> measureAll(
    EmbyServerConfig config,
  ) async {
    final urls = [config.serverUrl, ...config.routes.map((r) => r.url)];
    final latencies = await Future.wait(urls.map(measureUrl));
    return (
      main: RouteProbeResult(url: config.serverUrl, latencyMs: latencies.first),
      routes: [
        for (var i = 0; i < config.routes.length; i++)
          RouteProbeResult(
              url: config.routes[i].url, latencyMs: latencies[i + 1]),
      ],
    );
  }

  /// 点击切换激活线路；[routeUrl] 为 null 或等于主线路 → 回主线路。
  Future<void> switchRoute(EmbyServerConfig config, String? routeUrl) async {
    final url = (routeUrl == null || routeUrl == config.serverUrl)
        ? null
        : routeUrl;
    if (config.activeRouteUrl == url) return;
    await persist(config.copyWith(activeRouteUrl: url, clearActiveRoute: url == null));
  }

  /// 添加备用线路。
  Future<ServerRoute> addRoute(
    EmbyServerConfig config, {
    required String name,
    required String url,
    required bool isReverseProxy,
  }) async {
    final route = ServerRoute(
      id: ServerRoute.newId(config.routes),
      name: name.trim(),
      url: url,
      isReverseProxy: isReverseProxy,
    );
    await persist(config.copyWith(routes: [...config.routes, route]));
    return route;
  }

  /// 拖拽重排备用线路（[oldIndex]→[newIndex]，ReorderableListView 语义）。
  Future<void> reorderRoutes(int oldIndex, int newIndex) async {
    final active = readActiveConfig();
    if (active == null) return;
    var o = oldIndex;
    var n = newIndex;
    if (n > o) n--;
    if (o == n) return;
    final routes = [...active.routes];
    final item = routes.removeAt(o);
    routes.insert(n, item);
    await persist(active.copyWith(routes: routes));
  }

  /// 切换自动故障转移开关。
  Future<void> setAutoFailover(EmbyServerConfig config, bool enabled) async {
    if (config.autoFailover == enabled) return;
    await persist(config.copyWith(autoFailover: enabled));
  }

  /// 切换 STRM 直链播放开关。
  Future<void> setStrmDirectPlay(EmbyServerConfig config, bool enabled) async {
    if (config.strmDirectPlay == enabled) return;
    await persist(config.copyWith(strmDirectPlay: enabled));
  }

  /// 自动故障转移：测速全部线路，当前线路（激活 URL）不可达时切到
  /// 延迟最低的可达线路。返回切换后的 config（未切换返回 null）。
  ///
  /// - 无备用线路 → 跳过（null）；
  /// - 当前可达 → 不动（null）；
  /// - 全部不可达 → 不动（null）。
  Future<EmbyServerConfig?> failoverIfNeeded(EmbyServerConfig config) async {
    if (config.routes.isEmpty) return null;
    final probe = await measureAll(config);
    final currentUrl = config.effectiveUrl;
    final currentReachable = probe.main.url == currentUrl
        ? probe.main.reachable
        : probe.routes.any((r) => r.url == currentUrl && r.reachable);
    if (currentReachable) return null;

    // 候选 = 可达线路（主 + 备），取延迟最低。
    RouteProbeResult? best;
    if (probe.main.reachable) best = probe.main;
    for (final r in probe.routes) {
      if (!r.reachable) continue;
      if (best == null || r.latencyMs! < best.latencyMs!) best = r;
    }
    if (best == null || best.url == currentUrl) return null;

    final switched = config.copyWith(
      activeRouteUrl: best.url == config.serverUrl ? null : best.url,
      clearActiveRoute: best.url == config.serverUrl,
    );
    await persist(switched);
    return switched;
  }
}
