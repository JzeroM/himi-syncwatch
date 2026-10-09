import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';
import 'package:himi_syncwatch/widgets/tv/tv_exclude_editable.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// 全局聚合搜索页：左栏服务器筛选 + 右栏资源卡片。
///
/// - 左栏：全部 + 有结果的服务器（保持服务端返回顺序），点选过滤右侧网格
/// - 右栏：2+ 列海报网格，卡片左上带服务器名角标（「全部」视图区分来源）
/// - 底色与首页/分类页一致：主题色三段渐变（未设主题色时应用底色）
/// - 结果携带 server 参数进详情，不切换激活服务器
/// - 输入防抖 280ms：非空打字期间零网络、主区零重建；清空立即回落提示态
/// - 换词保留上一批结果 + 顶部细进度条；结果增量到达（先到先出）
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key, this.roomCode});

  /// 非空 = 房间模式：选片打开 roomMode 详情挑资源，
  /// 资源数据经本页 pop 带回（资源面板 await 本页 push 的结果）。
  final String? roomCode;

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final TextEditingController _controller = TextEditingController();

  /// 实时输入值：仅驱动清空按钮（ValueListenableBuilder 局部刷新），
  /// 打字过程不触发整屏 setState。
  final ValueNotifier<String> _liveQuery = ValueNotifier<String>('');

  /// 防抖后的搜索词（驱动搜索与主体切换）。
  String _debouncedQuery = '';

  /// 是否已有输入（false = 显示空词提示；空→非空边界时才翻转）。
  bool _hasInput = false;

  Timer? _debounceTimer;
  StreamSubscription<List<GlobalSearchResult>>? _subscription;

  /// 最近一批结果（null = 尚无）；换词期间保留旧果不闪空。
  List<GlobalSearchResult>? _results;
  bool _loading = false;

  /// 左栏选中服务器（null = 全部）。
  String? _selectedServerId;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _subscription?.cancel();
    _controller.dispose();
    _liveQuery.dispose();
    super.dispose();
  }

  /// 启动（或清空）搜索订阅：保留旧 [_results]，首批快照到达后替换。
  void _startSearch(String q) {
    _subscription?.cancel();
    _subscription = null;
    if (q.isEmpty) {
      _results = null;
      _loading = false;
      return;
    }
    _loading = true;
    _subscription = ref
        .read(globalSearchProvider)
        .searchStream(q, ref.read(embyServerListProvider))
        .listen(
      (snap) {
        if (mounted) setState(() => _results = snap);
      },
      onDone: () {
        if (mounted) setState(() => _loading = false);
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  void _onChanged(String v) {
    final wasEmpty = _liveQuery.value.trim().isEmpty;
    _liveQuery.value = v;
    _debounceTimer?.cancel();

    if (v.trim().isEmpty) {
      // 删到空：立即回落提示态（高频动作不防抖）
      if (_hasInput) {
        setState(() {
          _hasInput = false;
          _debouncedQuery = '';
          _selectedServerId = null;
          _startSearch('');
        });
      }
      return;
    }

    if (wasEmpty) {
      // 空→非空边界：仅此翻转（提示态→等待）；其余打字零重建
      setState(() => _hasInput = true);
    }
    _debounceTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final q = v.trim();
      if (q == _debouncedQuery) return;
      setState(() {
        _debouncedQuery = q;
        _startSearch(q);
      });
    });
  }

  void _clear() {
    _debounceTimer?.cancel();
    _controller.clear();
    _liveQuery.value = '';
    setState(() {
      _hasInput = false;
      _debouncedQuery = '';
      _selectedServerId = null;
      _startSearch('');
    });
  }

  Future<void> _openDetail(GlobalSearchResult r) async {
    final serverId = r.server.id;
    final itemId = r.item.id;
    final roomCode = widget.roomCode;
    if (roomCode == null) {
      Navigator.of(context).pop();
      context.push('/detail/$itemId?server=${Uri.encodeComponent(serverId)}');
      return;
    }
    // 房间模式：详情打开挑资源，返回的资源数据带回调用方（资源面板）。
    // 详情直接返回 null（未选资源）时留在本页，可继续挑选。
    final data = await context.push<Map<String, dynamic>>(
      '/detail/$itemId?server=${Uri.encodeComponent(serverId)}'
      '&roomMode=true&roomCode=${Uri.encodeComponent(roomCode)}',
    );
    if (data != null && mounted) Navigator.of(context).pop(data);
  }

  @override
  Widget build(BuildContext context) {
    // 主题色三段渐变底（与首页/分类页一致）
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
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
                      // TV 下输入框屏蔽焦点 + 不抢占（directional 下方向键
                      // 被文本编辑快捷键吞掉，打开即卡死；TV 搜索走扫码/
                      // 资源面板）。
                      child: tvExcludeEditable(
                        tvMode: tvMode,
                        child: TextField(
                          key: const ValueKey('globalSearchField'),
                          controller: _controller,
                          autofocus: !tvMode,
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
                            suffixIcon: ValueListenableBuilder<String>(
                              valueListenable: _liveQuery,
                              builder: (context, v, _) => v.isEmpty
                                  ? const SizedBox.shrink()
                                  : IconButton(
                                      key: const ValueKey('globalSearchClear'),
                                      icon: const Icon(Icons.clear,
                                          color: Colors.white70),
                                      onPressed: _clear,
                                    ),
                            ),
                          ),
                          onChanged: _onChanged,
                        ),
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
    if (!_hasInput) {
      return const Center(
        child: Text('输入关键词，搜索所有服务器', style: TextStyle(color: Colors.white70)),
      );
    }
    final results = _results;
    if (results == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.isEmpty) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : const Center(
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

    return Column(
      children: [
        // 换词/增量搜索中：保留上一批结果，仅顶部细进度条示意
        if (_loading)
          const LinearProgressIndicator(
            key: Key('searchProgressLine'),
            minHeight: 2,
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 116, child: _buildServerRail(servers, selectedId)),
              Expanded(child: _buildGrid(shown)),
            ],
          ),
        ),
      ],
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
