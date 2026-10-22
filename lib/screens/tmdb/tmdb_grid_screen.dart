import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/services/tmdb_aggregate_service.dart';
import 'package:himi_syncwatch/utils/poster_grid.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/tmdb_availability_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_poster_card.dart';
import 'package:himi_syncwatch/widgets/tv/tv_app_bar_icon_button.dart';

enum _PlatformFilter {
  all('全部', null),
  movie('电影', TmdbMediaType.movie),
  tv('剧集', TmdbMediaType.tv);

  const _PlatformFilter(this.label, this.type);

  final String label;
  final TmdbMediaType? type;
}

/// TMDB 栏目 / 平台网格页。
/// - 栏目：`/tmdb/section/:section`
/// - 平台：`/tmdb/platform/:providerId`
class TmdbGridScreen extends ConsumerStatefulWidget {
  const TmdbGridScreen({
    super.key,
    this.sectionKey,
    this.providerId,
  });

  final String? sectionKey;
  final int? providerId;

  bool get isPlatform => providerId != null;

  @override
  ConsumerState<TmdbGridScreen> createState() => _TmdbGridScreenState();
}

class _TmdbGridScreenState extends ConsumerState<TmdbGridScreen> {
  final List<TmdbAvailability> _entries = [];
  final ScrollController _scrollController = ScrollController();
  _PlatformFilter _filter = _PlatformFilter.all;
  int _page = 0;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  TmdbAggregateService? get _service => ref.read(tmdbAggregateServiceProvider);

  String get _title {
    if (widget.isPlatform) {
      return tmdbPlatformName(widget.providerId!) ?? '平台 ${widget.providerId}';
    }
    return TmdbAggregateService.sectionTitle(widget.sectionKey ?? '');
  }

  Widget _buildTitle() {
    if (widget.isPlatform) {
      final platform = tmdbPlatformById(widget.providerId!);
      if (platform != null) {
        return Image.asset(
          platform.logoAsset,
          key: ValueKey('tmdbPlatformTitleLogo_${platform.providerId}'),
          height: 26,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          semanticLabel: platform.name,
          errorBuilder: (context, error, stackTrace) {
            return Text(platform.name);
          },
        );
      }
    }
    return Text(_title);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 600) {
      _load(reset: false);
    }
  }

  void _scheduleFillCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading || _loadingMore || !_hasMore) return;
      if (!_scrollController.hasClients) return;
      if (_scrollController.position.extentAfter < 600) {
        _load(reset: false);
      }
    });
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
        _entries.clear();
        _page = 0;
        _hasMore = true;
      });
    } else {
      if (_loading || _loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    final service = _service;
    if (service == null) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'TMDB 未配置';
      });
      return;
    }
    final settings = ref.read(settingsProvider);
    final servers = ref.read(embyServerListProvider);
    final activeId = ref.read(embyConfigProvider)?.id;

    try {
      if (widget.isPlatform) {
        final nextPage = reset ? 1 : _page + 1;
        final result = await service.fetchPlatformPage(
          providerId: widget.providerId!,
          region: settings.tmdbWatchRegion,
          page: nextPage,
          servers: servers,
          type: _filter.type,
          activeServerId: activeId,
        );
        if (!mounted) return;
        final existing =
            _entries.map((e) => '${e.server.id}|${e.item.id}').toSet();
        for (final entry in result.items) {
          if (existing.add('${entry.server.id}|${entry.item.id}')) {
            _entries.add(entry);
          }
        }
        setState(() {
          _page = nextPage;
          _hasMore = result.hasMore;
          _loading = false;
          _loadingMore = false;
        });
      } else {
        var page = reset ? 1 : _page + 1;
        var emptyStreak = 0;
        while (true) {
          final result = await service.fetchSectionPage(
            widget.sectionKey ?? '',
            servers,
            activeServerId: activeId,
            page: page,
          );
          if (!mounted) return;
          final existing =
              _entries.map((e) => '${e.server.id}|${e.item.id}').toSet();
          var added = 0;
          for (final entry in result.items) {
            if (existing.add('${entry.server.id}|${entry.item.id}')) {
              _entries.add(entry);
              added++;
            }
          }
          setState(() {
            _page = page;
            _hasMore = result.hasMore;
            _loading = false;
            _loadingMore = false;
          });
          if (added > 0 || !result.hasMore || emptyStreak >= 4) break;
          emptyStreak++;
          page++;
          if (mounted) {
            setState(() => _loadingMore = true);
          }
        }
      }
      _scheduleFillCheck();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _setFilter(_PlatformFilter value) {
    if (value == _filter) return;
    setState(() => _filter = value);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;
    final imageBase = ref.watch(tmdbImageBaseProvider);
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    final columnsSetting =
        ref.watch(settingsProvider.select((s) => s.categoryColumns));

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const TvBackButton(),
        title: _buildTitle(),
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: PosterPalette.pageGradient(accent, base),
        ),
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = posterGridColumns(
                width: constraints.maxWidth,
                tvMode: tvMode,
                columns: columnsSetting,
              );
              final cellWidth =
                  (constraints.maxWidth - 16 - 8 * (columns - 1)) / columns;
              final cellHeight = TmdbPosterCard.heightFor(cellWidth);
              final topInset = GlassConfig.topInsetOf(context);

              return CustomScrollView(
                key: const ValueKey('tmdbGridScroll'),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (widget.isPlatform)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, topInset, 16, 12),
                      sliver: SliverToBoxAdapter(
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final filter in _PlatformFilter.values)
                              ChoiceChip(
                                key: ValueKey('tmdbFilter_${filter.name}'),
                                label: Text(filter.label),
                                selected: _filter == filter,
                                onSelected: (_) => _setFilter(filter),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_loading)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: widget.isPlatform ? 120 : topInset + 120,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    )
                  else if (_error != null)
                    SliverToBoxAdapter(
                      child: _ErrorView(
                        error: _error!,
                        onRetry: () => _load(reset: true),
                      ),
                    )
                  else if (_entries.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: widget.isPlatform ? 120 : topInset + 120,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _hasMore ? '本页暂无匹配条目' : '服务器中没有匹配的条目',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              if (_hasMore) ...[
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  key: const Key('tmdbEmptyLoadMore'),
                                  onPressed: () => _load(reset: false),
                                  child: const Text('继续加载'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        8,
                        widget.isPlatform ? 8 : topInset + 8,
                        8,
                        8,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: cellHeight,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final entry = _entries[index];
                            return TmdbPosterCard(
                              key: ValueKey(
                                'tmdbGrid_${entry.server.id}_${entry.item.id}',
                              ),
                              item: entry.tmdb,
                              imageBase: imageBase,
                              width: cellWidth,
                              poster: TmdbAvailabilityImage(
                                entry: entry,
                                imageBase: imageBase,
                                cacheWidth: (cellWidth *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                              ),
                              serverBadge: entry.server.label,
                              onTap: () => context.push(
                                '/detail/${entry.item.id}?server=${Uri.encodeComponent(entry.server.id)}&aggregate=true',
                              ),
                            );
                          },
                          childCount: _entries.length,
                        ),
                      ),
                    ),
                  if (!_loading && _error == null && _entries.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.only(top: 20),
                        child: Center(
                          child: _loadingMore
                              ? const CircularProgressIndicator()
                              : _hasMore
                                  ? ElevatedButton(
                                      key: const Key('tmdbLoadMore'),
                                      onPressed: () => _load(reset: false),
                                      child: const Text('加载更多'),
                                    )
                                  : const Text(
                                      '没有更多了',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: GlassConfig.bottomReserveOf(context),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Column(
        children: [
          Text(error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
