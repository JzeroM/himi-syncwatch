import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/services/emby_auth_service.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

final embyAuthServiceProvider = Provider<EmbyAuthService>((ref) {
  throw UnimplementedError('必须在 main.dart 中初始化');
});

final embyConfigProvider =
    StateNotifierProvider<EmbyConfigNotifier, EmbyServerConfig?>(
  (ref) => EmbyConfigNotifier(),
);

final embyServerListProvider =
    StateNotifierProvider<EmbyServerListNotifier, List<EmbyServerConfig>>(
  (ref) => EmbyServerListNotifier(),
);

class EmbyConfigNotifier extends StateNotifier<EmbyServerConfig?> {
  EmbyConfigNotifier() : super(null);

  void setConfig(EmbyServerConfig config) {
    state = config;
  }

  void clear() {
    state = null;
  }
}

class EmbyServerListNotifier extends StateNotifier<List<EmbyServerConfig>> {
  EmbyServerListNotifier() : super([]);

  void setList(List<EmbyServerConfig> list) {
    state = list;
  }

  void addServer(EmbyServerConfig config) {
    state = [...state, config];
  }

  void removeServer(String serverId) {
    state = state.where((s) => s.id != serverId).toList();
  }

  void updateServer(EmbyServerConfig config) {
    state = state.map((s) => s.id == config.id ? config : s).toList();
  }
}

final embyServiceProvider = Provider<EmbyService>((ref) {
  final service = EmbyService();
  final config = ref.watch(embyConfigProvider);

  if (config != null && config.isAuthenticated) {
    service.configure(
      serverUrl: config.serverUrl,
      accessToken: config.accessToken!,
      userId: config.userId!,
      serverId: config.serverId,
    );
  }

  return service;
});
