import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 顶部「搜索」入口按钮：已认证服务器存在时可点，打开聚合搜索。
///
/// 从首页 AppBar 迁出为共享组件：TV 顶栏与首页顶栏（非 TV）复用。
/// TV 模式渲染为带焦点环的 [TvFocusable]，非 TV 保持原 IconButton 形态。
class MediaSearchButton extends ConsumerWidget {
  const MediaSearchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 原首页逻辑：仅已认证服务器时展示搜索入口
    final hasServer = ref.watch(embyConfigProvider)?.isAuthenticated ?? false;
    if (!hasServer) return const SizedBox.shrink();

    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    if (!tvMode) {
      return IconButton(
        icon: const Icon(Icons.search),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: () => _openSearch(context, ref),
      );
    }
    return TvFocusable(
      radius: 12,
      onTap: () => _openSearch(context, ref),
      child: const SizedBox(
        width: 44,
        height: 44,
        child: Icon(Icons.search),
      ),
    );
  }

  void _openSearch(BuildContext context, WidgetRef ref) {
    showSearch(context: context, delegate: MediaSearchDelegate(ref));
  }
}

/// 聚合搜索全部已认证服务器的搜索委托。
class MediaSearchDelegate extends SearchDelegate<String> {
  MediaSearchDelegate(this.ref);

  final WidgetRef ref;

  Future<List<GlobalSearchResult>>? _cachedFuture;
  String? _cachedQuery;

  /// 聚合搜索全部已认证服务器；缓存避免 rebuild 重复触发。
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
      onPressed: () => close(context, ''),
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
                close(context, '');
                context.push(
                  '/detail/${item.id}?server=${Uri.encodeComponent(r.server.id)}',
                );
              },
            );
          },
        );
      },
    );
  }
}
