import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/glass/media_context_menu.dart';
import 'package:himi_syncwatch/widgets/home_hero_carousel.dart';
import 'package:himi_syncwatch/widgets/hover_scroll_row.dart';
import 'package:himi_syncwatch/widgets/tmdb_availability_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_discover_disc.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_platform_card.dart';
import 'package:himi_syncwatch/widgets/tmdb_poster_card.dart';
import 'package:himi_syncwatch/widgets/tmdb_resume_bar.dart';
import 'package:himi_syncwatch/widgets/tv/tv_focusable.dart';

/// TMDB 聚合首页：跨服务器续播 + 流媒体平台 + 趋势/热门栏目。
class TmdbHomeView extends ConsumerWidget {
  const TmdbHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tmdbHomeProvider);
    final resume = ref.watch(tmdbResumeProvider);
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () => refreshTmdbHome(ref),
        tvMode: tvMode,
      ),
      data: (data) {
        if (!data.configured) {
          return const _ConfigPrompt();
        }
        return _HomeList(
          data: data,
          resume: resume.valueOrNull?.entries ?? const [],
          resumeLoading: resume.isLoading,
          tvMode: tvMode,
        );
      },
    );
  }
}

class _HomeList extends ConsumerStatefulWidget {
  const _HomeList({
    required this.data,
    required this.resume,
    required this.resumeLoading,
    required this.tvMode,
  });

  final TmdbHomeData data;
  final List<TmdbResumeEntry> resume;
  final bool resumeLoading;
  final bool tvMode;

  @override
  ConsumerState<_HomeList> createState() => _HomeListState();
}

class _HomeListState extends ConsumerState<_HomeList> {
  final PageController _heroController = PageController();
  final Map<String, TmdbAvailability> _heroSources = {};
  int _heroIndex = 0;

  @override
  void didUpdateWidget(covariant _HomeList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final heroes = _heroCandidates(widget.data);
    if (_heroIndex >= heroes.length) {
      _heroIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _heroController.hasClients) {
          _heroController.jumpToPage(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  static List<TmdbAvailability> _heroCandidates(TmdbHomeData data) {
    final preferred = <TmdbAvailability>[];
    final fallback = <TmdbAvailability>[];
    final seen = <String>{};
    for (final section in data.sections) {
      for (final entry in section.items) {
        if (!seen.add(entry.tmdb.key)) continue;
        if (entry.tmdb.backdropPath != null) {
          preferred.add(entry);
        } else {
          fallback.add(entry);
        }
      }
    }
    return [...preferred, ...fallback].take(6).toList(growable: false);
  }

  HomeHeroItem _toHero(TmdbAvailability entry, String imageBase) {
    final serverUrl = entry.item.backdropWideUrl ??
        entry.item.backdropUrl ??
        entry.item.posterUrl;
    final tmdbUrl = entry.tmdb.backdropUrl(imageBase, size: 'w780') ??
        entry.tmdb.posterUrl(imageBase);
    if (serverUrl != null) _heroSources[serverUrl] = entry;
    return HomeHeroItem(
      title: entry.tmdb.title,
      imageUrl: serverUrl ?? tmdbUrl,
      year: entry.tmdb.year,
      rating: entry.tmdb.voteAverage,
      genres: [entry.tmdb.type.label],
      payload: entry,
    );
  }

  Widget _heroImage(
    String url, {
    BoxFit fit = BoxFit.cover,
    int? cacheWidth,
    bool transparent = false,
    Widget? errorWidget,
  }) {
    final entry = _heroSources[url];
    if (entry == null) {
      return TmdbImage(
        url: url,
        fit: fit,
        cacheWidth: cacheWidth,
        placeholder: transparent ? const SizedBox.shrink() : null,
        errorWidget:
            errorWidget ?? (transparent ? const SizedBox.shrink() : null),
      );
    }
    return TmdbAvailabilityImage(
      entry: entry,
      imageBase: ref.read(tmdbImageBaseProvider),
      backdrop: true,
      fit: fit,
      cacheWidth: cacheWidth,
      backdropSize: cacheWidth != null && cacheWidth <= 320 ? 'w300' : 'w780',
      serverMaxWidth: cacheWidth,
      transparent: transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final imageBase = ref.watch(tmdbImageBaseProvider);
    _heroSources.clear();
    final heroes = _heroCandidates(widget.data);
    final hero =
        heroes.isEmpty ? null : heroes[_heroIndex.clamp(0, heroes.length - 1)];
    final sections =
        widget.data.sections.where((s) => s.items.isNotEmpty).toList();
    final sectionsLoading = widget.data.sectionsLoading;
    if (sections.isEmpty &&
        widget.resume.isEmpty &&
        !widget.resumeLoading &&
        !sectionsLoading) {
      return _EmptyHome(tvMode: widget.tvMode);
    }

    final carouselEnabled = settings.homeCarousel && !widget.tvMode;
    final heroHeight = MediaQuery.sizeOf(context).height * 0.42;
    final headerCount = (hero != null || sectionsLoading) ? 1 : 0;
    final itemCount = headerCount +
        (widget.resume.isNotEmpty ? 1 : 0) +
        1 +
        1 +
        sections.length +
        (widget.data.failedServerCount > 0 ? 1 : 0);

    final list = RefreshIndicator(
      onRefresh: () => refreshTmdbHome(ref),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: headerCount > 0
              ? 0
              : (widget.tvMode ? 12 : GlassConfig.topInsetOf(context)),
          bottom: GlassConfig.bottomReserveOf(context),
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          var i = index;
          if (headerCount > 0) {
            if (i == 0) {
              if (hero == null) return _HeroSkeleton(height: heroHeight);
              if (carouselEnabled) {
                return HomeHeroCarousel(
                  items: [
                    for (final entry in heroes) _toHero(entry, imageBase),
                  ],
                  controller: _heroController,
                  height: heroHeight,
                  imageBuilder: _heroImage,
                  onPageChanged: (value) => setState(() => _heroIndex = value),
                  onTap: (item) {
                    final entry = item.payload;
                    if (entry is TmdbAvailability) {
                      _openDetail(context, entry);
                    }
                  },
                );
              }
              return _Hero(
                item: hero,
                imageBase: imageBase,
                onTap: () => _openDetail(context, hero),
              );
            }
            i--;
          }
          if (widget.resume.isNotEmpty) {
            if (i == 0) {
              return TmdbResumeBar(
                entries: widget.resume,
                onOpen: (entry) => _openResume(context, entry),
                onLongPress: (entry, anchor) => showResumeCardMenu(
                  context,
                  ref,
                  entry.item,
                  anchor,
                  serverId: entry.server.id,
                ),
              );
            }
            i--;
          }
          if (i == 0) {
            return _PlatformBar(
              tvMode: widget.tvMode,
              allowServerPosters: !widget.data.sectionsLoading,
            );
          }
          i--;
          if (i == 0) {
            return TmdbDiscoverDisc(tvMode: widget.tvMode);
          }
          i--;
          if (i < sections.length) {
            return _SectionRow(
              section: sections[i],
              imageBase: imageBase,
              tvMode: widget.tvMode,
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              '有 ${widget.data.failedServerCount} 台服务器数据加载失败',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          );
        },
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (carouselEnabled && hero != null)
          HomeHeroBackground(
            imageUrl: _toHero(hero, imageBase).imageUrl,
            baseColor: Theme.of(context).scaffoldBackgroundColor,
            heroHeight: heroHeight,
            imageBuilder: _heroImage,
          ),
        list,
      ],
    );
  }

  void _openResume(BuildContext context, TmdbResumeEntry entry) {
    final item = entry.item;
    final q = 'server=${Uri.encodeComponent(entry.server.id)}&aggregate=true';
    if (item.isEpisode && item.seriesId != null) {
      context.push('/detail/${item.seriesId}?$q&episode=${item.id}');
    } else {
      context.push('/detail/${item.id}?$q');
    }
  }

  void _openDetail(BuildContext context, TmdbAvailability entry) {
    context.push(
      '/detail/${entry.item.id}?server=${Uri.encodeComponent(entry.server.id)}&aggregate=true',
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF202329), Color(0xFF111317)],
          ),
        ),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.item,
    required this.imageBase,
    required this.onTap,
  });

  final TmdbAvailability item;
  final String imageBase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final height =
        (MediaQuery.sizeOf(context).height * 0.40).clamp(260.0, 440.0);
    final cacheWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round();
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TmdbAvailabilityImage(
            entry: item,
            imageBase: imageBase,
            backdrop: true,
            backdropSize: 'w780',
            cacheWidth: cacheWidth,
            serverMaxWidth: cacheWidth,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x22000000),
                  Color(0x66000000),
                  Color(0xE6000000),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.tmdb.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (item.tmdb.year != null) item.tmdb.year!,
                    item.tmdb.type.label,
                    if (item.tmdb.voteAverage != null)
                      '★ ${item.tmdb.voteAverage!.toStringAsFixed(1)}',
                  ].join('  ·  '),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (item.tmdb.overview?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.tmdb.overview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                ],
                const SizedBox(height: 14),
                TvFocusable(
                  radius: 22,
                  onTap: onTap,
                  child: GlassContainer(
                    borderRadius: BorderRadius.circular(22),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow, size: 18),
                        SizedBox(width: 4),
                        Text('查看详情',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHome extends ConsumerWidget {
  const _EmptyHome({required this.tvMode});

  final bool tvMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tmdbDiscProvider);
    final disc = async.valueOrNull;
    final loading = disc != null ? disc.loading : !async.hasError;
    final hasContent =
        disc?.sections.any((section) => section.items.isNotEmpty) ?? false;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: tvMode ? 20 : GlassConfig.topInsetOf(context),
        bottom: GlassConfig.bottomReserveOf(context),
      ),
      children: [
        _PlatformBar(tvMode: tvMode, allowServerPosters: true),
        TmdbDiscoverDisc(tvMode: tvMode),
        if (!loading && !hasContent)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Text(
              'TMDB 暂无聚合内容\n请确认服务器媒体带 TMDB id，或换个观看区域',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
      ],
    );
  }
}

class _PlatformBar extends ConsumerWidget {
  const _PlatformBar({
    required this.tvMode,
    required this.allowServerPosters,
  });

  final bool tvMode;
  final bool allowServerPosters;

  static const double _height = 84;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth =
        ((screenWidth - 32) / (tvMode ? 3 : 2)).clamp(150.0, 280.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(
            '流媒体平台',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: _height,
          child: HoverScrollRow(
            height: _height,
            arrowAnchorHeight: _height,
            itemCount: tmdbPlatforms.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _PlatformCard(
                  platform: tmdbPlatforms[index],
                  width: cardWidth,
                  allowServerPosters: allowServerPosters,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlatformCard extends ConsumerWidget {
  const _PlatformCard({
    required this.platform,
    required this.width,
    required this.allowServerPosters,
  });

  final TmdbPlatform platform;
  final double width;
  final bool allowServerPosters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base =
        ref.watch(tmdbPlatformShowcaseProvider(platform)).valueOrNull ??
            TmdbPlatformShowcase(platform: platform);
    final availability = allowServerPosters
        ? ref.watch(tmdbPlatformAvailabilityProvider(platform)).valueOrNull
        : null;
    final entries = availability?.entries;
    final showcase = entries == null || entries.isEmpty
        ? base
        : TmdbPlatformShowcase(
            platform: platform,
            posters: [
              for (final poster in base.posters)
                TmdbPlatformPoster(
                  tmdb: poster.tmdb,
                  availability: entries[poster.tmdb.key] ?? poster.availability,
                ),
            ],
          );
    return TmdbPlatformCard(
      key: ValueKey('tmdbPlatform_${platform.providerId}'),
      showcase: showcase,
      imageBase: ref.watch(tmdbImageBaseProvider),
      width: width,
      serverLookupComplete: availability?.complete ?? false,
      onTap: () => context.push(
        '/tmdb/platform/${platform.providerId}',
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.imageBase,
    required this.tvMode,
  });

  final TmdbSectionData section;
  final String imageBase;
  final bool tvMode;

  @override
  Widget build(BuildContext context) {
    final height = TmdbPosterCard.heightFor(102);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              TvFocusable(
                onTap: () => context.push('/tmdb/section/${section.key}'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      section.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right,
                        color: Colors.grey[400], size: 22),
                  ],
                ),
              ),
              const Spacer(),
              TextButton(
                key: ValueKey('tmdbViewAll_${section.key}'),
                onPressed: () => context.push('/tmdb/section/${section.key}'),
                child: const Text('查看所有'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: HoverScrollRow(
            height: height,
            arrowAnchorHeight: TmdbPosterCard.mediaHeightFor(102),
            itemCount: section.items.length,
            itemBuilder: (context, index) {
              final entry = section.items[index];
              return SizedBox(
                width: 110,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: TmdbPosterCard(
                    key:
                        ValueKey('tmdbPoster_${section.key}_${entry.tmdb.key}'),
                    item: entry.tmdb,
                    imageBase: imageBase,
                    width: 102,
                    poster: TmdbAvailabilityImage(
                      entry: entry,
                      imageBase: imageBase,
                      cacheWidth: (102 * MediaQuery.devicePixelRatioOf(context))
                          .round(),
                      posterSize: 'w154',
                      fadeInDuration: const Duration(milliseconds: 120),
                    ),
                    onTap: () => context.push(
                      '/detail/${entry.item.id}?server=${Uri.encodeComponent(entry.server.id)}&aggregate=true',
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

class _ConfigPrompt extends StatelessWidget {
  const _ConfigPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.key_off_outlined, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('TMDB 聚合模式未配置',
                style: TextStyle(fontSize: 18, color: Colors.white70)),
            const SizedBox(height: 8),
            const Text(
              '填入自己的 TMDB API Key 或 v4 Read Token 后，'
              '即可跨服务器浏览趋势与平台内容。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              key: const Key('tmdbConfigureButton'),
              onPressed: () => context.push('/settings/general/tmdb'),
              child: const Text('去配置 TMDB'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.error,
    required this.onRetry,
    required this.tvMode,
  });

  final String error;
  final VoidCallback onRetry;
  final bool tvMode;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 56, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('TMDB 加载失败',
              style: TextStyle(fontSize: 18, color: Colors.white70)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(height: 16),
          if (!tvMode)
            ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
