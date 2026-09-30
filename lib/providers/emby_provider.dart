import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/services/emby_auth_service.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';

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

/// Emby 服务实例工厂：按服务器配置构建独立服务（跨服务器搜索/详情/播放用）。
/// 测试可 override 注入 fake。
final embyServiceFactoryProvider =
    Provider<EmbyService Function(EmbyServerConfig server)>((ref) {
  return (server) {
    final service = EmbyService();
    if (server.isAuthenticated) {
      service.configure(
        serverUrl: server.serverUrl,
        accessToken: server.accessToken!,
        userId: server.userId!,
        serverId: server.serverId,
      );
    }
    return service;
  };
});

/// 按本地配置 id 解析服务器配置。
/// [serverId] 为 null/空或与当前激活相同 → 当前激活；未命中列表 → 回退当前激活。
final embyConfigForProvider =
    Provider.family<EmbyServerConfig?, String?>((ref, serverId) {
  if (serverId == null || serverId.isEmpty) {
    return ref.watch(embyConfigProvider);
  }
  final current = ref.watch(embyConfigProvider);
  if (current?.id == serverId) return current;
  for (final s in ref.watch(embyServerListProvider)) {
    if (s.id == serverId) return s;
  }
  return current;
});

/// 按来源服务器解析服务实例（跨服务器详情/取流）。
/// null/空或与当前激活相同 → 复用 [embyServiceProvider] 单例；
/// 否则按服务器列表中的配置独立构建。
final embyServiceForProvider = Provider.family<EmbyService, String?>(
  (ref, serverId) {
    if (serverId == null || serverId.isEmpty) {
      return ref.watch(embyServiceProvider);
    }
    final config = ref.watch(embyConfigForProvider(serverId));
    final current = ref.watch(embyConfigProvider);
    // 未命中回退/未认证/与当前激活相同 → 复用当前服务单例
    if (config == null ||
        !config.isAuthenticated ||
        (current != null && config.id == current.id)) {
      return ref.watch(embyServiceProvider);
    }
    return ref.watch(embyServiceFactoryProvider)(config);
  },
);

/// 全局聚合搜索服务：并发搜索全部已认证服务器。
final globalSearchProvider = Provider<GlobalSearchService>((ref) {
  return GlobalSearchService(
    serviceFactory: ref.watch(embyServiceFactoryProvider),
  );
});

final embyServiceProvider = Provider<EmbyService>((ref) {
  final config = ref.watch(embyConfigProvider);
  if (config == null || !config.isAuthenticated) {
    return EmbyService();
  }
  return ref.watch(embyServiceFactoryProvider)(config);
});
