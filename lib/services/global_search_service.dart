import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

/// 聚合搜索结果：条目 + 来源服务器。
class GlobalSearchResult {
  final EmbyServerConfig server;
  final MediaItem item;

  const GlobalSearchResult({required this.server, required this.item});
}

/// 全局聚合搜索：并发搜索多台 Emby 服务器，按服务器顺序合并结果。
///
/// 单台服务器失败返回空结果，不阻塞整体；未认证服务器自动跳过。
class GlobalSearchService {
  final EmbyService Function(EmbyServerConfig server) serviceFactory;

  GlobalSearchService({required this.serviceFactory});

  Future<List<GlobalSearchResult>> search(
    String query,
    List<EmbyServerConfig> servers,
  ) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final targets = servers.where((s) => s.isAuthenticated).toList();
    if (targets.isEmpty) return [];

    final futures = targets.map((server) async {
      try {
        final items = await serviceFactory(server).searchItems(q);
        return items
            .map((item) => GlobalSearchResult(server: server, item: item))
            .toList();
      } catch (_) {
        return <GlobalSearchResult>[];
      }
    }).toList();

    final batches = await Future.wait(futures);
    return [for (final batch in batches) ...batch];
  }
}
