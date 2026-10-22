import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/hover_scroll_row.dart';
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
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        error: e.toString(),
        onRetry: () => ref.invalidate(tmdbHomeProvider),
        tvMode: tvMode,
      ),
      data: (data) {
        if (!data.configured) {
          return const _ConfigPrompt();
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(tmdbHomeProvider.future),
          child: _HomeList(data: data, tvMode: tvMode),
        );
      },
    );
  }
}

class _HomeList extends ConsumerWidget {
  const _HomeList({required this.data, required this.tvMode});

  final TmdbHomeData data;
  final bool tvMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageBase = ref.watch(tmdbImageBaseProvider);
    final hero = _heroItem(data);
    final sections = data.sections.where((s) => s.items.isNotEmpty).toList();
    if (sections.isEmpty && data.resume.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: tvMode ? 20 : GlassConfig.topInsetOf(context),
          bottom: GlassConfig.bottomReserveOf(context),
        ),
        children: const [
          SizedBox(height: 160),
          Center(
            child: Text(
              'TMDB 暂无聚合内容\n请确认服务器媒体带 TMDB id，或换个观看区域',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      );
    }

    final headerCount = hero != null ? 1 : 0;
    final itemCount = headerCount +
        (data.resume.isNotEmpty ? 1 : 0) +
        1 + // 平台栏
        sections.length +
        (data.failedServerCount > 0 ? 1 : 0);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: hero != null ? 0 : (tvMode ? 12 : GlassConfig.topInsetOf(context)),
        bottom: GlassConfig.bottomReserveOf(context),
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        var i = index;
        if (hero != null) {
          if (i == 0) {
            return _Hero(
              item: hero,
              imageBase: imageBase,
              onTap: () => _openDetail(context, hero),
            );
          }
          i--;
        }
        if (data.resume.isNotEmpty) {
          if (i == 0) {
            return TmdbResumeBar(
              entries: data.resume,
              onOpen: (entry) => _openResume(context, entry),
            );
          }
          i--;
        }
        if (i == 0) {
          return _PlatformBar(
            logos: data.platformLogos,
            imageBase: imageBase,
            tvMode: tvMode,
          );
        }
        i--;
        if (i < sections.length) {
          return _SectionRow(
            section: sections[i],
            imageBase: imageBase,
            tvMode: tvMode,
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            '有 ${data.failedServerCount} 台服务器数据加载失败',
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
          ),
        );
      },
    );
  }

  static TmdbAvailability? _heroItem(TmdbHomeData data) {
    for (final key in ['trending_day', 'trending_week', 'popular_movies']) {
      for (final section in data.sections) {
        if (section.key == key && section.items.isNotEmpty) {
          return section.items.first;
        }
      }
    }
    for (final section in data.sections) {
      if (section.items.isNotEmpty) return section.items.first;
    }
    return null;
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
    final height = (MediaQuery.sizeOf(context).height * 0.40)
        .clamp(260.0, 440.0);
    final image =
        item.tmdb.backdropUrl(imageBase) ?? item.tmdb.posterUrl(imageBase);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TmdbImage(url: image),
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

class _PlatformBar extends StatelessWidget {
  const _PlatformBar({
    required this.logos,
    required this.imageBase,
    required this.tvMode,
  });

  final Map<int, String?> logos;
  final String imageBase;
  final bool tvMode;

  static const double _height = 84;

  @override
  Widget build(BuildContext context) {
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
              final platform = tmdbPlatforms[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TmdbPlatformCard(
                  key: ValueKey('tmdbPlatform_${platform.providerId}'),
                  platform: platform,
                  imageBase: imageBase,
                  logoPath: logos[platform.providerId],
                  onTap: () => context.push(
                    '/tmdb/platform/${platform.providerId}',
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
                    key: ValueKey(
                        'tmdbPoster_${section.key}_${entry.tmdb.key}'),
                    item: entry.tmdb,
                    imageBase: imageBase,
                    width: 102,
                    serverBadge: entry.server.label,
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
