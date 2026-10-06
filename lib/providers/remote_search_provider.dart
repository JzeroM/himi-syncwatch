import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/remote_search/remote_search_server.dart';

/// 手机选片事件：网页 POST /api/select 触发，屏幕监听后跳电视详情。
class RemoteSelection {
  const RemoteSelection({
    required this.serverId,
    required this.itemId,
    required this.name,
  });

  final String serverId;
  final String itemId;
  final String name;
}

/// 扫码远程搜索状态：服务生命周期 + 最近一次手机选片。
class RemoteSearchState {
  const RemoteSearchState({
    this.running = false,
    this.url,
    this.ips = const [],
    this.port,
    this.lastSelectedName,
    this.error,
  });

  final bool running;
  final String? url;
  final List<String> ips;
  final int? port;

  /// 最近一次手机选中的片名（null = 尚无人选片）。
  final String? lastSelectedName;

  /// 启动失败信息（null = 正常）。
  final String? error;

  RemoteSearchState copyWith({
    bool? running,
    String? url,
    List<String>? ips,
    int? port,
    String? lastSelectedName,
    String? error,
  }) {
    return RemoteSearchState(
      running: running ?? this.running,
      url: url ?? this.url,
      ips: ips ?? this.ips,
      port: port ?? this.port,
      lastSelectedName: lastSelectedName ?? this.lastSelectedName,
      error: error,
    );
  }
}

/// 扫码远程搜索服务生命周期 + 手机选片广播。
///
/// [searchHandler] 由 provider 层注入真实 Emby 聚合查询（含海报 token 组装）；
/// 选片成功后写入 [RemoteSearchState.lastSelectedName] 并广播
/// [selections]，屏幕监听后在电视上打开详情。
class RemoteSearchNotifier extends StateNotifier<RemoteSearchState> {
  RemoteSearchNotifier({
    required RemoteSearchHandler searchHandler,
    int basePort = 17892,
  }) : super(const RemoteSearchState()) {
    _server = RemoteSearchServer(
      onSearch: (query) async {
        final items = await searchHandler(query);
        for (final item in items) {
          _names['${item.serverId}/${item.id}'] = item.name;
        }
        return items;
      },
      onSelect: (serverId, itemId) async {
        final name = _names['$serverId/$itemId'] ?? itemId;
        if (!mounted) return null;
        state = state.copyWith(lastSelectedName: name);
        _selections.add(
          RemoteSelection(serverId: serverId, itemId: itemId, name: name),
        );
        return null;
      },
      basePort: basePort,
    );
  }

  late final RemoteSearchServer _server;
  final Map<String, String> _names = {};
  final StreamController<RemoteSelection> _selections =
      StreamController<RemoteSelection>.broadcast();

  RemoteSearchServer get server => _server;

  /// 手机选片事件流（屏幕监听跳详情）。
  Stream<RemoteSelection> get selections => _selections.stream;

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
      if (!mounted) return;
      state = state.copyWith(error: '扫码服务启动失败：$e');
    }
  }

  Future<void> stop() async {
    await _server.stop();
    if (mounted) state = const RemoteSearchState();
  }

  @override
  void dispose() {
    _selections.close();
    super.dispose();
  }
}

/// 扫码服务首选端口（测试可 override 为 0 走随机端口）。
final remoteSearchBasePortProvider = Provider<int>((_) => 17892);

final remoteSearchProvider =
    StateNotifierProvider<RemoteSearchNotifier, RemoteSearchState>((ref) {
  final notifier = RemoteSearchNotifier(
    basePort: ref.watch(remoteSearchBasePortProvider),
    searchHandler: (query) async {
      final servers = ref.read(embyServerListProvider);
      final results =
          await ref.read(globalSearchProvider).search(query, servers);
      return [
        for (final r in results)
          RemoteSearchItem(
            id: r.item.id,
            name: r.item.name,
            serverId: r.server.id,
            serverName: r.server.serverName,
            year: r.item.year,
            poster: posterWithToken(r.item.posterUrl, r.server.accessToken),
          ),
      ];
    },
  );
  ref.onDispose(notifier.stop);
  return notifier;
});

/// 海报地址追加 `api_key`（手机 `<img>` 无法带请求头）。
String? posterWithToken(String? posterUrl, String? token) {
  if (posterUrl == null || posterUrl.isEmpty) return null;
  if (token == null || token.isEmpty) return posterUrl;
  final sep = posterUrl.contains('?') ? '&' : '?';
  return '$posterUrl${sep}api_key=${Uri.encodeQueryComponent(token)}';
}
