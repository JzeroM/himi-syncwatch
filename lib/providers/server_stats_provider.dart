import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

/// 单台服务器的统计数据（延迟 + 媒体计数，均可能为 null = 未取到）。
class ServerStats {
  const ServerStats({this.latencyMs, this.counts});

  final int? latencyMs;
  final MediaCounts? counts;

  bool get isEmpty => latencyMs == null && counts == null;
}

/// 服务器页统计：进页并行逐服务器测延迟 + 拉计数。
///
/// 每台服务器独立兜底（失败只丢该项数据，不阻塞其他服务器）；
/// 重复 loadAll 用序号丢弃过期结果。
class ServerStatsNotifier extends StateNotifier<Map<String, ServerStats>> {
  ServerStatsNotifier({required EmbyService Function(EmbyServerConfig) serviceFactory})
      : _serviceFactory = serviceFactory,
        super(const {});

  final EmbyService Function(EmbyServerConfig) _serviceFactory;
  int _seq = 0;

  Future<void> loadAll(List<EmbyServerConfig> servers) async {
    final seq = ++_seq;
    await Future.wait(servers.map((s) => _loadOne(seq, s)));
  }

  Future<void> _loadOne(int seq, EmbyServerConfig server) async {
    final service = _serviceFactory(server);
    int? latencyMs;
    MediaCounts? counts;
    // ping / 计数各自独立兜底：ping 失败不阻塞计数
    try {
      final stopwatch = Stopwatch()..start();
      // pingServer 走 GET /System/Info/Public，无需认证，可测全部服务器
      await service.pingServer(server.serverUrl);
      latencyMs = stopwatch.elapsedMilliseconds;
    } catch (_) {
      latencyMs = null;
    }
    if (server.isAuthenticated) {
      try {
        counts = await service.getItemCounts();
      } catch (_) {
        counts = null;
      }
    }
    if (!mounted || seq != _seq) return;
    state = {
      ...state,
      server.id: ServerStats(latencyMs: latencyMs, counts: counts),
    };
  }
}

final serverStatsProvider = StateNotifierProvider<
    ServerStatsNotifier, Map<String, ServerStats>>((ref) {
  return ServerStatsNotifier(
    serviceFactory: ref.watch(embyServiceFactoryProvider),
  );
});
