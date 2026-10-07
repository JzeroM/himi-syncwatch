import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';
import 'package:himi_syncwatch/widgets/tv/tv_refresh_hotkey.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/playback_report_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/continue_watching_card.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/glass/media_context_menu.dart';
import 'package:himi_syncwatch/widgets/media_search_button.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';
import 'package:himi_syncwatch/widgets/room_menu_button.dart';
import 'package:himi_syncwatch/widgets/server_title_dropdown.dart';
import 'package:himi_syncwatch/widgets/stats_panel.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.qrScan});

  /// 测试注入点：返回房间码模拟扫码结果；为 null 时走真实 `/scan` 路由。
  @visibleForTesting
  final Future<String?> Function()? qrScan;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _CategoryData {
  final LibraryFolder folder;
  final List<MediaItem> items;
  _CategoryData({required this.folder, required this.items});
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<_CategoryData> _categories = [];
  List<LibraryFolder> _libraries = [];

  /// 「继续观看」条目（有播放进度的视频；空则不渲染该栏）。
  List<MediaItem> _resumeItems = [];

  /// 电影/电视剧/集计数（null = 未加载或加载失败，底部面板隐藏）。
  MediaCounts? _counts;
  bool _isLoading = true;
  String? _error;
  bool _initialized = false;

  /// 加载请求序号：切换/刷新并发时丢弃过期结果，防止旧数据覆盖新内容。
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final authService = ref.read(embyAuthServiceProvider);
    final serverIds = await authService.listServerIds();

    if (serverIds.isEmpty) {
      setState(() {
        _isLoading = false;
        _initialized = true;
      });
      return;
    }

    // 并行读取各服务器 session：顺序读在服务器多时明显拖慢首屏
    final sessions = await Future.wait(
      serverIds.map((sid) => authService.loadSession(sid)),
    );
    final savedId = await authService.loadSelectedServerId();

    final configs = <EmbyServerConfig>[];
    final seenServerIds = <String>{};
    EmbyServerConfig? activeConfig;

    for (var i = 0; i < serverIds.length; i++) {
      final session = sessions[i];
      if (session == null) continue;
      final config = EmbyServerConfig.fromJson(session);
      if (seenServerIds.contains(config.serverId)) {
        await authService.deleteSession(serverIds[i]);
        continue;
      }
      seenServerIds.add(config.serverId);
      configs.add(config);
      if (activeConfig == null || config.id == savedId) {
        activeConfig = config;
      }
    }

    ref.read(embyServerListProvider.notifier).setList(configs);

    if (activeConfig != null) {
      ref.read(embyConfigProvider.notifier).setConfig(activeConfig);
      // 立即结束首屏全屏转圈，媒体内容由 _loadMedia 渐进填充
      setState(() => _initialized = true);
      unawaited(_loadMedia());
    } else {
      setState(() {
        _isLoading = false;
        _initialized = true;
      });
    }
  }

  Future<void> _loadMedia([EmbyService? serviceOverride]) async {
    final seq = ++_loadSeq;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final EmbyService embyService =
          serviceOverride ?? ref.read(embyServiceProvider);
      // 库列表与计数并发发起；计数到齐后单独填充统计面板，不阻塞首屏
      final libsFuture = embyService.getLibraries();
      unawaited(embyService.getItemCounts().then((counts) {
        if (!mounted || seq != _loadSeq) return;
        setState(() => _counts = counts);
      }));
      // 继续观看（不阻塞首屏）
      unawaited(embyService.getResumeItems().then((items) {
        if (!mounted || seq != _loadSeq) return;
        setState(() => _resumeItems = items);
      }));
      final libs = await libsFuture;

      // 每库并发取内容；哪个先回就先追加哪个分类，首屏尽快出内容。
      // slots 按库顺序占位，避免乱序返回打乱服务端排序。
      final slots = List<_CategoryData?>.filled(libs.length, null);
      final futures = <Future<void>>[
        for (var i = 0; i < libs.length; i++)
          embyService
              .getItems(
            parentId: libs[i].id,
            limit: 20,
            includeItemTypes: 'Movie,Series',
            fields:
                'ImageTags,PrimaryImageAspectRatio,ProductionYear,CommunityRating,IndexNumber',
            // DateLastContentAdded：剧集有新集数入库时 Series 的该字段会
            // 更新，更新过的剧集能浮到最前；DateCreated 是系列首次入库
            // 时间，新集不会变——表现为"更新了还排在后面"
            sortBy: 'DateLastContentAdded',
            sortOrder: 'Descending',
          )
              .then((items) {
            if (!mounted || seq != _loadSeq) return;
            slots[i] = _CategoryData(folder: libs[i], items: items);
            _applyCategories(libs, slots);
          }),
      ];
      await Future.wait(futures);

      if (!mounted || seq != _loadSeq) return;
      // 兜底：库为空或全部同步完成时确保转圈结束
      if (_isLoading) setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// 只刷新「继续观看」栏（不触发整页 loading，避免闪转圈）。
  Future<void> _refreshResume() async {
    final seq = _loadSeq;
    try {
      final items = await ref.read(embyServiceProvider).getResumeItems();
      if (!mounted || seq != _loadSeq) return;
      setState(() => _resumeItems = items);
    } catch (_) {}
  }

  /// 按当前已返回的 [slots] 重建分类与媒体库栏（过滤空库、保持服务端排序），
  /// 首个分类到达即结束转圈。
  void _applyCategories(List<LibraryFolder> libs, List<_CategoryData?> slots) {
    final categories = [
      for (final s in slots)
        if (s != null && s.items.isNotEmpty) s,
    ];
    final nonEmptyIds = {for (final c in categories) c.folder.id};
    setState(() {
      _categories = categories;
      _libraries = [
        for (final lib in libs)
          if (nonEmptyIds.contains(lib.id)) lib,
      ];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 服务器在「Emby服务器」标签页切换 / 增删后，重新加载首页媒体
    ref.listen<EmbyServerConfig?>(embyConfigProvider, (prev, next) {
      if (!_initialized || next == null || identical(prev, next)) return;
      // 显式用新配置构建服务：listen 回调先于 embyServiceProvider 失效执行，
      // 此刻 ref.read(embyServiceProvider) 拿到的仍是旧实例（切换竞态根因）
      _loadMedia(ref.read(embyServiceFactoryProvider)(next));
    });
    // 续播相关操作（播放停止/标记已观看）后即时刷新「继续观看」栏
    ref.listen<int>(resumeRevisionProvider, (_, __) => _refreshResume());

    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasServer = ref.watch(embyConfigProvider)?.isAuthenticated == true;

    // TV 模式：标题/房间/搜索全部上移到壳层顶部导航，首页自身不渲染顶栏
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));

    // 「重播」乐观隐藏：点重播即从继续观看栏移除，服务器真相回来后交回
    final hiddenResume = ref.watch(resumeOptimisticHiddenProvider);
    final resumeVisible =
        _resumeItems.where((e) => !hiddenResume.contains(e.id)).toList();

    // 主题色三段渐变背景（null 时保持应用底色）
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: tvMode
          ? null
          : AppBar(
              title: Align(
                alignment: Alignment.centerLeft,
                child: const ServerTitleDropdown(),
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GlassContainer(
                    borderRadius: const BorderRadius.all(Radius.circular(24)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    showShadow: false,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RoomMenuButton(qrScan: widget.qrScan),
                        const MediaSearchButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      body: AnimatedContainer(
        key: const Key('homeBackground'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: PosterPalette.pageGradient(accent, base),
        ),
        child: !hasServer
            ? const _EmptyState()
            : _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadMedia,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : TvRefreshHotkey(
                        onRefresh: _loadMedia,
                        child: RefreshIndicator(
                          onRefresh: _loadMedia,
                          child: ListView.builder(
                            padding: EdgeInsets.only(
                              // TV：壳层顶栏已占安全区与 60 高，内容只需小间隙；
                              // 非 TV：预留自身 AppBar（extendBodyBehindAppBar）
                              top:
                                  tvMode ? 12 : GlassConfig.topInsetOf(context),
                              bottom: GlassConfig.bottomReserveOf(context),
                            ),
                            itemCount: _categories.length +
                                (_libraries.isNotEmpty ? 1 : 0) +
                                (resumeVisible.isNotEmpty ? 1 : 0) +
                                (_counts != null ? 1 : 0),
                            itemBuilder: (context, index) {
                              var i = index;
                              if (_libraries.isNotEmpty) {
                                if (i == 0) {
                                  return _LibraryBar(
                                    libraries: _libraries,
                                    onOpen: (lib) => context.push(
                                      '/category/${lib.id}?name=${Uri.encodeComponent(lib.name)}&type=${lib.collectionType}',
                                    ),
                                  );
                                }
                                i--;
                              }
                              if (resumeVisible.isNotEmpty) {
                                if (i == 0) {
                                  return _ContinueWatchingBar(
                                    items: resumeVisible,
                                    onOpen: (item) =>
                                        context.push('/detail/${item.id}'),
                                    onItemLongPress: (item, rect) =>
                                        showResumeCardMenu(
                                            context, ref, item, rect),
                                  );
                                }
                                i--;
                              }
                              if (i < _categories.length) {
                                final cat = _categories[i];
                                return _CategorySection(
                                  category: cat,
                                  onViewAll: () => context.push(
                                    '/category/${cat.folder.id}?name=${Uri.encodeComponent(cat.folder.name)}&type=${cat.folder.collectionType}',
                                  ),
                                  onItemTap: (item) =>
                                      context.push('/detail/${item.id}'),
                                  onItemLongPress: (item, rect) =>
                                      showPosterCardMenu(context, ref, item, rect,
                                          favoritedMode: false),
                                );
                              }
                              // 列表收尾：媒体统计面板（计数加载成功才渲染）
                              return StatsPanel(
                                key: const ValueKey('statsPanel'),
                                counts: _counts!,
                              );
                            },
                          ),
                        ),
                      ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns, size: 64, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text(
            '暂无服务器',
            style: TextStyle(fontSize: 18, color: Colors.grey[400]),
          ),
          const SizedBox(height: 8),
          Text(
            '请到「Emby服务器」标签添加 Emby 服务器',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}

/// 首页「媒体库」横向栏：库封面卡片按服务端排序排列，
/// 点击进入对应分类海报墙。
/// 首页「继续观看」横向栏：有播放进度的电影/集，横版卡带进度条。
class _ContinueWatchingBar extends StatelessWidget {
  const _ContinueWatchingBar({
    required this.items,
    required this.onOpen,
    this.onItemLongPress,
  });

  final List<MediaItem> items;
  final void Function(MediaItem item) onOpen;
  final void Function(MediaItem item, Rect anchor)? onItemLongPress;

  static const double _cardWidth = 200;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '继续观看',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: ContinueWatchingCard.heightFor(_cardWidth),
          child: ListView.builder(
            // TV 焦点框放大溢出内容盒，默认 clip 会裁边
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SizedBox(
                  width: _cardWidth,
                  child: ContinueWatchingCard(
                    key: ValueKey('continueCard_${item.id}'),
                    item: item,
                    width: _cardWidth,
                    onTap: () => onOpen(item),
                    onLongPress: onItemLongPress == null
                        ? null
                        : (rect) => onItemLongPress!(item, rect),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LibraryBar extends StatelessWidget {
  const _LibraryBar({required this.libraries, required this.onOpen});

  final List<LibraryFolder> libraries;
  final void Function(LibraryFolder library) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '媒体库',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 126,
          child: ListView.builder(
            // TV 焦点框随 1.06 放大溢出内容盒，默认 clip 裁掉上下边
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: libraries.length,
            itemBuilder: (context, index) {
              final lib = libraries[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TvFocusable(
                  key: ValueKey('libraryCard_${lib.id}'),
                  onTap: () => onOpen(lib),
                  child: SizedBox(
                    width: 160,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            height: 96,
                            child: EmbyImage(
                                url: lib.posterUrl,
                                fit: BoxFit.cover,
                                cacheWidth: (160 *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .round()),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          lib.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  final _CategoryData category;
  final VoidCallback onViewAll;
  final void Function(MediaItem item) onItemTap;
  final void Function(MediaItem item, Rect anchor)? onItemLongPress;

  const _CategorySection({
    required this.category,
    required this.onViewAll,
    required this.onItemTap,
    this.onItemLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: TvFocusable(
            onTap: onViewAll,
            child: Row(
              // 收缩到内容宽：否则 Row 撑满整行，焦点环横贯全屏很难看
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  category.folder.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 22),
              ],
            ),
          ),
        ),
        SizedBox(
          height: PosterCard.heightFor(102),
          child: ListView.builder(
            // TV 焦点框随 1.06 放大溢出内容盒，默认 clip 裁掉上下边
            clipBehavior: Clip.none,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: category.items.length,
            itemBuilder: (context, index) {
              final item = category.items[index];
              return SizedBox(
                width: 110,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: PosterCard(
                    key: ValueKey('posterCard_${item.id}'),
                    item: item,
                    width: 102,
                    onTap: () => onItemTap(item),
                    onLongPress: onItemLongPress == null
                        ? null
                        : (rect) => onItemLongPress!(item, rect),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
