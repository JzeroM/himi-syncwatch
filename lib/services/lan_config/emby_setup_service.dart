import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_auth_service.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:uuid/uuid.dart';

/// Emby 添加服务器用例：连接 → 认证 → 落库 → 激活。
/// 从服务器管理表单与局域网扫码配置共用，构造注入可全 fake 测试。
final embySetupServiceProvider = Provider<EmbySetupService>((ref) {
  return EmbySetupService(
    embyService: EmbyService(),
    authService: ref.read(embyAuthServiceProvider),
    serverListNotifier: ref.read(embyServerListProvider.notifier),
    configNotifier: ref.read(embyConfigProvider.notifier),
    readServers: () => ref.read(embyServerListProvider),
  );
});

/// 业务失败（认证失败/字段非法），message 可直接展示给用户。
class EmbySetupException implements Exception {
  EmbySetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class EmbySetupService {
  EmbySetupService({
    required this.embyService,
    required this.authService,
    required this.serverListNotifier,
    required this.configNotifier,
    required this.readServers,
  });

  final EmbyService embyService;
  final EmbyAuthService authService;
  final EmbyServerListNotifier serverListNotifier;
  final EmbyConfigNotifier configNotifier;
  final List<EmbyServerConfig> Function() readServers;

  /// 连接并登录 [serverUrl]，保存会话后加入列表并设为当前激活服务器。
  ///
  /// [serverName] 备注名，为空时用服务端返回的 ServerName。
  /// [onServerInfo] ping 成功后回调服务端名称（用于 UI 即时反馈）。
  /// 失败抛出 [EmbySetupException] 或底层网络异常。
  Future<EmbyServerConfig> addAndActivate({
    required String serverUrl,
    required String username,
    required String password,
    String? serverName,
    void Function(String serverName)? onServerInfo,
  }) async {
    final url = serverUrl.trim();
    final user = username.trim();
    if (url.isEmpty || user.isEmpty) {
      throw EmbySetupException('服务器地址和用户名不能为空');
    }

    final info = await embyService.pingServer(url);
    final pingedName = (info['ServerName'] as String?) ?? url;
    final pingedId = (info['Id'] as String?) ?? '';
    final displayName = (serverName != null && serverName.trim().isNotEmpty)
        ? serverName.trim()
        : pingedName;
    onServerInfo?.call(displayName);

    final authResult = await embyService.authenticate(
      serverUrl: url,
      username: user,
      password: password,
      deviceId: authService.deviceId,
    );

    final authUser = authResult['User'] as Map<String, dynamic>?;
    final userId = authUser?['Id'] as String? ?? '';
    final accessToken = authResult['AccessToken'] as String? ?? '';
    final returnedServerId = authResult['ServerId'] as String? ?? pingedId;
    if (userId.isEmpty || accessToken.isEmpty) {
      throw EmbySetupException('登录失败：服务端返回数据异常');
    }

    final configId = 'srv_${const Uuid().v4().substring(0, 8)}';

    final duplicates =
        readServers().where((s) => s.serverId == returnedServerId).toList();
    for (final old in duplicates) {
      await authService.deleteSession(old.serverId);
      serverListNotifier.removeServer(old.id);
    }

    final config = EmbyServerConfig(
      id: configId,
      serverUrl: url,
      serverName: displayName,
      serverId: returnedServerId,
      username: user,
      accessToken: accessToken,
      userId: userId,
    );

    await authService.saveSession(
      serverId: returnedServerId,
      serverUrl: url,
      serverName: displayName,
      userId: userId,
      username: user,
      accessToken: accessToken,
      id: config.id,
    );

    serverListNotifier.addServer(config);
    configNotifier.setConfig(config);
    await authService.saveSelectedServerId(config.id);
    return config;
  }
}
