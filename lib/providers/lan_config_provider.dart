import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/server_route.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/emby_error.dart';
import 'package:himi_syncwatch/services/lan_config/emby_setup_service.dart';
import 'package:himi_syncwatch/services/lan_config/lan_config_server.dart';
import 'package:himi_syncwatch/services/server_route_service.dart';

/// 局域网扫码配置状态。
class LanConfigState {
  const LanConfigState({
    this.running = false,
    this.url,
    this.ips = const [],
    this.port,
    this.lastOk,
    this.lastMessage,
  });

  final bool running;
  final String? url;
  final List<String> ips;
  final int? port;

  /// 最近一次手机提交结果：null=尚未提交。
  final bool? lastOk;
  final String? lastMessage;

  LanConfigState copyWith({
    bool? running,
    String? url,
    List<String>? ips,
    int? port,
    bool? lastOk,
    String? lastMessage,
  }) {
    return LanConfigState(
      running: running ?? this.running,
      url: url ?? this.url,
      ips: ips ?? this.ips,
      port: port ?? this.port,
      lastOk: lastOk ?? this.lastOk,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}

/// 扫码配置服务生命周期 + 手机提交结果。
///
/// 构造注入 [embyHandler]/[danmakuHandler]/[routeHandler]（由 provider 层
/// 接真实落库逻辑），内部包装一层记录成功/失败到状态，供二维码页展示。
class LanConfigNotifier extends StateNotifier<LanConfigState> {
  LanConfigNotifier({
    required Future<String?> Function(Map<String, dynamic> body) embyHandler,
    Future<String?> Function(Map<String, dynamic> body)? danmakuHandler,
    Future<String?> Function(Map<String, dynamic> body)? routeHandler,
    int basePort = 17890,
  }) : super(const LanConfigState()) {
    _server = LanConfigServer(
      basePort: basePort,
      onEmby: (body) =>
          _guard(embyHandler, body, successMessage: '配置成功，已应用到电视'),
      onDanmaku: danmakuHandler == null
          ? null
          : (body) =>
              _guard(danmakuHandler, body, successMessage: '弹幕 API 地址已配置'),
      onRoute: routeHandler == null
          ? null
          : (body) => _guard(routeHandler, body, successMessage: '备用线路已添加'),
    );
  }

  /// 扫码添加线路的目标服务器本地配置 id（QR 页打开时注入）。
  String? routeTargetServerId;

  late final LanConfigServer _server;

  LanConfigServer get server => _server;

  Future<String?> _guard(
    Future<String?> Function(Map<String, dynamic> body) handler,
    Map<String, dynamic> body, {
    required String successMessage,
  }) async {
    try {
      final error = await handler(body);
      _record(error == null, error ?? successMessage);
      return error;
    } catch (e) {
      _record(false, friendlyEmbyError(e));
      rethrow;
    }
  }

  void _record(bool ok, String message) {
    if (!mounted) return;
    state = state.copyWith(lastOk: ok, lastMessage: message);
  }

  Future<void> start() async {
    if (state.running) return;
    try {
      await _server.start();
      if (!mounted) return;
      state = state.copyWith(
        running: true,
        url: _server.url,
        ips: _server.ips,
        port: _server.port,
      );
    } catch (e) {
      _record(false, '扫码服务启动失败：$e');
    }
  }

  Future<void> stop() async {
    await _server.stop();
    if (mounted) state = const LanConfigState();
  }
}

/// 扫码服务首选端口（测试可 override 为 0 走随机端口）。
final lanConfigBasePortProvider = Provider<int>((_) => 17890);

final lanConfigProvider =
    StateNotifierProvider<LanConfigNotifier, LanConfigState>((ref) {
  String asString(dynamic v) => v is String ? v : '';

  late final LanConfigNotifier notifier;
  notifier = LanConfigNotifier(
    basePort: ref.watch(lanConfigBasePortProvider),
    embyHandler: (body) async {
      await ref.read(embySetupServiceProvider).addAndActivate(
            serverUrl: asString(body['url']),
            username: asString(body['username']),
            password: asString(body['password']),
            serverName: asString(body['name']),
          );
      return null;
    },
    danmakuHandler: (body) async {
      ref
          .read(settingsProvider.notifier)
          .update(danmakuApiUrl: asString(body['url']));
      return null;
    },
    // 手机提交备用线路：字段分项 → 拼 URL → ServerRouteService.addRoute
    routeHandler: (body) async {
      final targetId = notifier.routeTargetServerId;
      final servers = ref.read(embyServerListProvider);
      EmbyServerConfig? target;
      for (final s in servers) {
        if (s.id == targetId) {
          target = s;
          break;
        }
      }
      if (target == null) return '目标服务器不存在，请重新扫码';

      final rawHost = asString(body['host']).trim();
      final parsed =
          looksLikeFullServerUrl(rawHost) ? parseServerUrl(rawHost) : null;
      final url = buildServerUrl(
        host: parsed?.host ?? rawHost,
        port: parsed?.port ?? asString(body['port']),
        path: parsed?.path ?? asString(body['path']),
        useHttps: parsed?.useHttps ?? body['https'] == true,
      );
      if (url == null) return '服务器地址无效（IP、域名或 [IPv6]）';

      final name = asString(body['name']);
      await ref.read(serverRouteServiceProvider).addRoute(
            target,
            name: name.isEmpty ? ServerRoute.defaultName(target.routes) : name,
            url: url,
            isReverseProxy: body['reverseProxy'] == true,
          );
      return null;
    },
  );
  ref.onDispose(notifier.stop);
  return notifier;
});
