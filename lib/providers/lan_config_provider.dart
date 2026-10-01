import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/agora_config_model.dart';
import 'package:himi_syncwatch/providers/agora_provider.dart';
import 'package:himi_syncwatch/services/lan_config/emby_setup_service.dart';
import 'package:himi_syncwatch/services/lan_config/lan_config_server.dart';

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
/// 构造注入 [embyHandler]/[agoraHandler]（由 provider 层接真实落库逻辑），
/// 内部包装一层记录成功/失败到状态，供二维码页展示。
class LanConfigNotifier extends StateNotifier<LanConfigState> {
  LanConfigNotifier({
    required Future<String?> Function(Map<String, dynamic> body) embyHandler,
    required Future<String?> Function(Map<String, dynamic> body) agoraHandler,
    int basePort = 17890,
  }) : super(const LanConfigState()) {
    _server = LanConfigServer(
      basePort: basePort,
      onEmby: (body) => _guard(embyHandler, body),
      onAgora: (body) => _guard(agoraHandler, body),
    );
  }

  late final LanConfigServer _server;

  LanConfigServer get server => _server;

  Future<String?> _guard(
    Future<String?> Function(Map<String, dynamic> body) handler,
    Map<String, dynamic> body,
  ) async {
    try {
      final error = await handler(body);
      _record(error == null, error ?? '配置成功，已应用到电视');
      return error;
    } catch (e) {
      _record(false, e.toString());
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

  final notifier = LanConfigNotifier(
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
    agoraHandler: (body) async {
      final appId = asString(body['appId']);
      final cert = asString(body['appCertificate']);
      if (appId.isEmpty || cert.isEmpty) {
        return 'App ID 与 Certificate 不能为空';
      }
      await ref.read(agoraConfigProvider.notifier).save(
            AgoraConfigModel(appId: appId, appCertificate: cert),
          );
      return null;
    },
  );
  ref.onDispose(notifier.stop);
  return notifier;
});
