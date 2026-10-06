import 'dart:async';

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

  /// 增量聚合搜索：每台服务器返回即发一份合并快照（按服务器顺序合并），
  /// 不等最慢的一台；全部完成后发终份快照并结束流。
  ///
  /// - 中途空快照不下发（避免"未找到结果"闪烁）；全空时终份仍发一份空
  /// - 单台失败留空不阻塞；监听取消后在途结果静默丢弃
  Stream<List<GlobalSearchResult>> searchStream(
    String query,
    List<EmbyServerConfig> servers,
  ) {
    final q = query.trim();
    final targets = q.isEmpty
        ? const <EmbyServerConfig>[]
        : servers.where((s) => s.isAuthenticated).toList();

    late StreamController<List<GlobalSearchResult>> controller;
    controller = StreamController<List<GlobalSearchResult>>(
      onListen: () async {
        if (targets.isEmpty) {
          controller.add(const []);
          controller.close();
          return;
        }
        final batches =
            List.generate(targets.length, (_) => <GlobalSearchResult>[]);
        var remaining = targets.length;

        Future<void> runOne(int index, EmbyServerConfig server) async {
          try {
            final items = await serviceFactory(server).searchItems(q);
            batches[index] = [
              for (final item in items)
                GlobalSearchResult(server: server, item: item),
            ];
          } catch (_) {
            // 单台失败留空，不阻塞整体
          }
          remaining--;
          if (controller.isClosed) return;
          final merged = <GlobalSearchResult>[
            for (final batch in batches) ...batch,
          ];
          if (merged.isNotEmpty || remaining == 0) {
            controller.add(merged);
          }
          if (remaining == 0) controller.close();
        }

        for (var i = 0; i < targets.length; i++) {
          unawaited(runOne(i, targets[i]));
        }
      },
    );
    return controller.stream;
  }
}
