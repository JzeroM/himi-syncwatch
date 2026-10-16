import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/services/emby_auth_service.dart';
import 'package:uuid/uuid.dart';

/// 同步落库结果：error 非 null = 业务失败文案；否则 list 为合并后的完整列表，
/// activateTarget 非 null 表示「TV 端原本为空」应激活该台（调用方负责激活）。
class TvSyncUpsertResult {
  const TvSyncUpsertResult({
    this.error,
    this.list = const [],
    this.activateTarget,
    this.syncedCount = 0,
  });

  final String? error;
  final List<EmbyServerConfig> list;
  final EmbyServerConfig? activateTarget;

  /// 本次实际接收（upsert）的服务器数量。
  final int syncedCount;

  bool get ok => error == null;
}

/// 手机推送服务器配置 → TV 端按 serverId upsert 落库。
///
/// - 已有同 serverId：覆盖配置但**保留本地 id**（server_order/选中引用不破坏）
/// - 新 serverId：id 冲突时生成 `srv_<uuid8>`；追加到列表末尾
/// - 跳过未登录（缺 accessToken/userId）与缺 serverId/serverUrl 的条目
/// - TV 端原本一台都没有时，把第一台新服务器作为 [TvSyncUpsertResult.activateTarget]
class TvConfigSyncer {
  const TvConfigSyncer({required this.auth});

  final EmbyAuthService auth;

  Future<TvSyncUpsertResult> upsert({
    required List<EmbyServerConfig> existing,
    required List<EmbyServerConfig> incoming,
  }) async {
    final storageIds = await auth.listServerIds();
    final wasEmpty = existing.isEmpty && storageIds.isEmpty;

    final accepted = incoming
        .where((s) =>
            s.serverId.isNotEmpty &&
            s.serverUrl.isNotEmpty &&
            s.isAuthenticated)
        .toList();
    if (accepted.isEmpty) {
      return const TvSyncUpsertResult(error: '没有可同步的服务器（缺少登录凭据）');
    }

    final merged = List<EmbyServerConfig>.of(existing);
    EmbyServerConfig? activateTarget;
    for (final cfg in accepted) {
      final idx = merged.indexWhere((s) => s.serverId == cfg.serverId);
      final EmbyServerConfig synced;
      if (idx >= 0) {
        final old = merged[idx];
        synced = EmbyServerConfig(
          id: old.id,
          serverUrl: cfg.serverUrl,
          serverName: cfg.serverName,
          serverId: cfg.serverId,
          username: cfg.username,
          accessToken: cfg.accessToken,
          userId: cfg.userId,
          routes: cfg.routes,
          activeRouteUrl: cfg.activeRouteUrl,
          autoFailover: cfg.autoFailover,
          strmDirectPlay: cfg.strmDirectPlay,
        );
        merged[idx] = synced;
      } else {
        var id = cfg.id;
        if (id.isEmpty || merged.any((s) => s.id == id)) {
          id = 'srv_${const Uuid().v4().substring(0, 8)}';
        }
        synced = EmbyServerConfig(
          id: id,
          serverUrl: cfg.serverUrl,
          serverName: cfg.serverName,
          serverId: cfg.serverId,
          username: cfg.username,
          accessToken: cfg.accessToken,
          userId: cfg.userId,
          routes: cfg.routes,
          activeRouteUrl: cfg.activeRouteUrl,
          autoFailover: cfg.autoFailover,
          strmDirectPlay: cfg.strmDirectPlay,
        );
        merged.add(synced);
        activateTarget ??= synced;
      }
      await auth.saveSession(
        serverId: synced.serverId,
        serverUrl: synced.serverUrl,
        serverName: synced.serverName,
        userId: synced.userId!,
        username: synced.username,
        id: synced.id,
        accessToken: synced.accessToken!,
        routes: synced.routes.map((r) => r.toJson()).toList(),
        activeRouteUrl: synced.activeRouteUrl,
        autoFailover: synced.autoFailover,
        strmDirectPlay: synced.strmDirectPlay,
      );
    }

    // 新服务器排到顺序末尾（已有的保持原位）
    final order = await auth.loadServerOrder();
    final orderedIds = <String>[
      ...order.where((id) => merged.any((s) => s.id == id)),
    ];
    for (final s in merged) {
      if (!orderedIds.contains(s.id)) orderedIds.add(s.id);
    }
    await auth.saveServerOrder(orderedIds);

    return TvSyncUpsertResult(
      list: merged,
      activateTarget: wasEmpty ? activateTarget : null,
      syncedCount: accepted.length,
    );
  }
}
