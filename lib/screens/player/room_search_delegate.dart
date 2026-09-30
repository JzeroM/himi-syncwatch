import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';

/// 房间内资源搜索：聚合搜索全部已认证服务器。
///
/// 选中结果返回 `{itemId, name, poster, year, serverId}`，
/// `serverId` 为来源服务器本地配置 id（详情页跨服务器取数用）。
class RoomSearchDelegate extends SearchDelegate<Map<String, dynamic>?> {
  final WidgetRef ref;
  final String roomCode;
  RoomSearchDelegate(this.ref, {required this.roomCode});

  Future<List<GlobalSearchResult>>? _cachedFuture;
  String? _cachedQuery;

  Future<List<GlobalSearchResult>> _search() {
    final q = query.trim();
    if (_cachedQuery != q || _cachedFuture == null) {
      _cachedQuery = q;
      _cachedFuture = ref
          .read(globalSearchProvider)
          .search(q, ref.read(embyServerListProvider));
    }
    return _cachedFuture!;
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults();

  Widget _buildSearchResults() {
    if (query.trim().isEmpty) {
      return const Center(child: Text('输入关键词搜索全部服务器'));
    }
    return FutureBuilder<List<GlobalSearchResult>>(
      future: _search(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? [];
        if (results.isEmpty) return const Center(child: Text('未找到结果'));
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final r = results[index];
            final item = r.item;
            final meta = item.year != null
                ? '${r.server.serverName} · ${item.year}'
                : r.server.serverName;
            return ListTile(
              leading: SizedBox(
                width: 50,
                height: 70,
                child: EmbyImage(url: item.posterUrl, fit: BoxFit.cover),
              ),
              title: Text(item.name),
              subtitle: Text(meta),
              onTap: () {
                close(context, {
                  'itemId': item.id,
                  'name': item.name,
                  'poster': item.posterUrl ?? '',
                  'year': item.year ?? '',
                  'serverId': r.server.id,
                });
              },
            );
          },
        );
      },
    );
  }
}
