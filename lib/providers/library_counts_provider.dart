import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/library_counts.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';

/// 资源统计加载状态：loading 期间 counts 为 null。
class LibraryCountsState {
  const LibraryCountsState({this.counts, this.loading = false});

  final LibraryCounts? counts;
  final bool loading;
}

/// 按服务器 id 懒加载资源统计（打开面板才请求）。
///
/// key = server.id；loading=true 表示请求中；counts=null 且 loading=false 表示失败/空。
final libraryCountsProvider = StateNotifierProvider.family<
    LibraryCountsNotifier, LibraryCountsState, String>((ref, serverId) {
  return LibraryCountsNotifier(
    serverId: serverId,
    serviceFactory: ref.watch(embyServiceFactoryProvider),
    serverList: ref.watch(embyServerListProvider),
  );
});

class LibraryCountsNotifier extends StateNotifier<LibraryCountsState> {
  LibraryCountsNotifier({
    required this.serverId,
    required EmbyService Function(EmbyServerConfig) serviceFactory,
    required List<EmbyServerConfig> serverList,
  })  : _serviceFactory = serviceFactory,
        _serverList = serverList,
        super(const LibraryCountsState());

  final String serverId;
  final EmbyService Function(EmbyServerConfig) _serviceFactory;
  final List<EmbyServerConfig> _serverList;
  int _seq = 0;
  bool _loaded = false;

  /// 首次调用发起请求；已加载则跳过（幂等）。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    await load();
  }

  /// 强制重新加载（失败重试用）。
  Future<void> load() async {
    final seq = ++_seq;
    state = const LibraryCountsState(loading: true);
    final server = _serverList.where((s) => s.id == serverId).firstOrNull;
    if (server == null || !server.isAuthenticated) {
      state = const LibraryCountsState();
      return;
    }
    final service = _serviceFactory(server);
    try {
      final result = await service.getLibraryCounts();
      if (!mounted || seq != _seq) return;
      state = LibraryCountsState(counts: result);
    } catch (_) {
      if (!mounted || seq != _seq) return;
      state = const LibraryCountsState();
    }
  }
}
