import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/favorites_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/services/poster_palette.dart';
import 'package:himi_syncwatch/widgets/favorite_episode_card.dart';
import 'package:himi_syncwatch/widgets/glass/glass_config.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';

/// 收藏页（壳层分支，导航栏 index 1）：电影 / 电视剧 / 集 三分区，
/// 每区全部铺开，右上「查看所有」为可选入口；数据源为当前服务器
/// Emby 收藏（[favoriteItemsProvider]）。背景同主题色三段渐变。
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  static const double _posterWidth = 110;
  static const double _episodeWidth = 190;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvMode = ref.watch(settingsProvider.select((s) => s.tvMode));
    final themeColorValue =
        ref.watch(settingsProvider.select((s) => s.themeColor));
    final accent = themeColorValue == null
        ? null
        : PosterPalette.darkenForPage(Color(themeColorValue));
    final base = Theme.of(context).scaffoldBackgroundColor;
    final async = ref.watch(favoriteItemsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: tvMode
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: const Text('收藏'),
            ),
      body: AnimatedContainer(
        key: const Key('favoritesBackground'),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: PosterPalette.pageGradient(accent, base),
        ),
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(favoriteItemsProvider.future),
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _centered('收藏加载失败：$e'),
            data: (groups) => groups.isEmpty
                ? _centered('还没有收藏，去详情页点爱心收藏吧')
                : _buildSections(context, groups, tvMode),
          ),
        ),
      ),
    );
  }

  /// 可滚动空态/错误态（RefreshIndicator 需要可滚动子级）。
  Widget _centered(String text) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSections(
      BuildContext context, FavoriteGroups groups, bool tvMode) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: tvMode ? 12 : GlassConfig.topInsetOf(context),
        bottom: GlassConfig.bottomReserveOf(context),
      ),
      children: [
        if (groups.movies.isNotEmpty)
          _FavoriteSection(
            title: '电影',
            type: 'movie',
            items: groups.movies,
            cardWidth: _posterWidth,
            episodeStyle: false,
          ),
        if (groups.series.isNotEmpty)
          _FavoriteSection(
            title: '电视剧',
            type: 'series',
            items: groups.series,
            cardWidth: _posterWidth,
            episodeStyle: false,
          ),
        if (groups.episodes.isNotEmpty)
          _FavoriteSection(
            title: '集',
            type: 'episode',
            items: groups.episodes,
            cardWidth: _episodeWidth,
            episodeStyle: true,
          ),
      ],
    );
  }
}

/// 单个分区：标题 + 「查看所有」+ 全部卡片（Wrap 铺开）。
class _FavoriteSection extends StatelessWidget {
  const _FavoriteSection({
    required this.title,
    required this.type,
    required this.items,
    required this.cardWidth,
    required this.episodeStyle,
  });

  final String title;
  final String type;
  final List<MediaItem> items;
  final double cardWidth;
  final bool episodeStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                key: Key('favoritesViewAll_$type'),
                onPressed: () => context.push(
                  '/favorites/all?type=$type&title=${Uri.encodeComponent(title)}',
                ),
                child: const Text('查看所有'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              for (final item in items)
                SizedBox(
                  width: cardWidth,
                  child: episodeStyle
                      ? FavoriteEpisodeCard(
                          item: item,
                          width: cardWidth,
                          onTap: () => context.push('/detail/${item.id}'),
                        )
                      : PosterCard(
                          item: item,
                          width: cardWidth,
                          onTap: () => context.push('/detail/${item.id}'),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
