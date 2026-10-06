import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 全局聚合搜索页：左栏服务器筛选 + 右栏资源卡片。
///
/// - 左栏：全部 + 有结果的服务器（保持服务端返回顺序），点选过滤右侧网格
/// - 右栏：2+ 列海报网格，卡片左上带服务器名角标（「全部」视图区分来源）
/// - 底色与首页/分类页一致：主题色三段渐变（未设主题色时应用底色）
/// - 结果携带 server 参数进详情，不切换激活服务器
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  /// 结果缓存（同词不重复请求，与原委托行为一致）。
  String? _cachedQuery;
  Future<List<GlobalSearchResult>>? _cachedFuture;

  /// 左栏选中服务器（null = 全部）。
  String? _selectedServerId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<List<GlobalSearchResult>> _search() {
    final q = _query.trim();
    if (_cachedQuery != q || _cachedFuture == null) {
      _cachedQuery = q;
      _cachedFuture = ref
          .read(globalSearchProvider)
          .search(q, ref.read(embyServerListProvider));
    }
    return _cachedFuture!;
  }

  void _openDetail(GlobalSearchResult r) {
    final serverId = r.server.id;
    final itemId = r.item.id;
    Navigator.of(context).pop();
    context.push('/detail/$itemId?server=${Uri.encodeComponent(serverId)}');
  }

  @override
  Widget build(BuildContext context) {
    // 主题色三段渐变底（与首页/分类页一致）
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        key: const Key('searchBackground'),
        decoration:
            BoxDecoration(gradient: PosterPalette.pageGradient(accent, base)),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('globalSearchBack'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('globalSearchField'),
                        controller: _controller,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '输入关键词搜索全部服务器',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.10),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  key: const ValueKey('globalSearchClear'),
                                  icon: const Icon(Icons.clear,
                                      color: Colors.white70),
                                  onPressed: () {
                                    _controller.clear();
                                    setState(() {
                                      _query = '';
                                      _selectedServerId = null;
                                    });
                                  },
                                ),
                        ),
                        onChanged: (v) => setState(() {
                          _query = v;
                          if (v.trim().isEmpty) _selectedServerId = null;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.trim().isEmpty) {
      return const Center(
        child: Text('输入关键词，搜索所有服务器', style: TextStyle(color: Colors.white70)),
      );
    }
    return FutureBuilder<List<GlobalSearchResult>>(
      future: _search(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? [];
        if (results.isEmpty) {
          return const Center(
            child: Text('未找到结果', style: TextStyle(color: Colors.white70)),
          );
        }

        // 按服务器分组（保持服务端返回顺序，去重）
        final servers = <EmbyServerConfig>[];
        for (final r in results) {
          if (!servers.any((s) => s.id == r.server.id)) servers.add(r.server);
        }
        // 选中服务器在新结果中消失（换词后无结果）→ 回落全部
        final selectedId = servers.any((s) => s.id == _selectedServerId)
            ? _selectedServerId
            : null;
        final shown = selectedId == null
            ? results
            : results.where((r) => r.server.id == selectedId).toList();

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 116, child: _buildServerRail(servers, selectedId)),
            Expanded(child: _buildGrid(shown)),
          ],
        );
      },
    );
  }

  /// 左栏：全部 + 各服务器筛选片。
  Widget _buildServerRail(
    List<EmbyServerConfig> servers,
    String? selectedId,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 16),
      children: [
        _ServerChip(
          key: const ValueKey('serverChip_all'),
          label: '全部',
          selected: selectedId == null,
          onTap: () => setState(() => _selectedServerId = null),
        ),
        for (final s in servers)
          _ServerChip(
            key: ValueKey('serverChip_${s.id}'),
            label: s.serverName,
            selected: selectedId == s.id,
            onTap: () => setState(() => _selectedServerId = s.id),
          ),
      ],
    );
  }

  /// 右栏：海报网格（列数随可用宽度 2~6）。
  Widget _buildGrid(List<GlobalSearchResult> results) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 与 GridView 水平 padding（8 + 12）一致，保证列宽精确不溢出
        final w = constraints.maxWidth - 20;
        final columns = (w / 170).floor().clamp(2, 6);
        final cellWidth = (w - 8 * (columns - 1)) / columns;
        final childAspectRatio = cellWidth / PosterCard.heightFor(cellWidth);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: results.length,
          itemBuilder: (context, index) {
            final r = results[index];
            return PosterCard(
              key: ValueKey('posterCard_${r.item.id}_${r.server.id}'),
              item: r.item,
              width: cellWidth,
              serverBadge: r.server.serverName,
              onTap: () => _openDetail(r),
            );
          },
        );
      },
    );
  }
}

/// 左栏服务器筛选片：选中 accent 实底，未选中半透明玻璃。
class _ServerChip extends StatelessWidget {
  const _ServerChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6366F1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TvFocusable(
        radius: 12,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: 0.20),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
