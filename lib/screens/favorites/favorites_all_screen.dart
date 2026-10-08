import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/favorites_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/glass/media_context_menu.dart';
import 'package:himi_syncwatch/widgets/favorite_episode_card.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';

/// 「查看所有」页：展示某分类（电影/电视剧/集）的全部收藏，网格铺开。
/// 顶层路由 `/favorites/all?type=...&title=...`。
class FavoritesAllScreen extends ConsumerWidget {
  const FavoritesAllScreen({
    super.key,
    required this.type,
    required this.title,
  });

  final String type;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;
    final async = ref.watch(favoriteItemsProvider);
    final isEpisode = type == 'episode';

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title),
      ),
      body: AnimatedContainer(
        key: const Key('favoritesAllBackground'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: PosterPalette.pageGradient(accent, base),
        ),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child:
                Text('加载失败：$e', style: const TextStyle(color: Colors.white70)),
          ),
          data: (groups) {
            final items = _pick(groups);
            if (items.isEmpty) {
              return const Center(
                child: Text('暂无收藏', style: TextStyle(color: Colors.white70)),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = isEpisode ? 210.0 : 120.0;
                return ListView(
                  padding: EdgeInsets.only(
                    top: GlassConfig.topInsetOf(context),
                    bottom: GlassConfig.bottomReserveOf(context),
                    left: 16,
                    right: 16,
                  ),
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 16,
                      children: [
                        for (final item in items)
                          SizedBox(
                            width: cardWidth,
                            child: isEpisode
                                ? FavoriteEpisodeCard(
                                    item: item,
                                    width: cardWidth,
                                    onTap: () =>
                                        context.push('/detail/${item.id}'),
                                  )
                                : PosterCard(
                                    item: item,
                                    width: cardWidth,
                                    onTap: () =>
                                        context.push('/detail/${item.id}'),
                                    onLongPress: (rect) => showPosterCardMenu(
                                        context, ref, item, rect),
                                  ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<MediaItem> _pick(FavoriteGroups groups) {
    switch (type) {
      case 'movie':
        return groups.movies;
      case 'series':
        return groups.series;
      case 'episode':
        return groups.episodes;
      default:
        return const [];
    }
  }
}
