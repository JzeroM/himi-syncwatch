import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';

/// 收藏条目按类型分组（电影 / 电视剧 / 集），供收藏页三分区展示。
class FavoriteGroups {
  const FavoriteGroups({
    this.movies = const [],
    this.series = const [],
    this.episodes = const [],
  });

  final List<MediaItem> movies;
  final List<MediaItem> series;
  final List<MediaItem> episodes;

  bool get isEmpty => movies.isEmpty && series.isEmpty && episodes.isEmpty;

  /// 按 `Type` 分组（忽略其它类型）。
  static FavoriteGroups fromItems(List<MediaItem> items) {
    final movies = <MediaItem>[];
    final series = <MediaItem>[];
    final episodes = <MediaItem>[];
    for (final it in items) {
      switch (it.type) {
        case 'Movie':
          movies.add(it);
          break;
        case 'Series':
          series.add(it);
          break;
        case 'Episode':
          episodes.add(it);
          break;
      }
    }
    return FavoriteGroups(
      movies: movies,
      series: series,
      episodes: episodes,
    );
  }
}

/// 收藏修订号：详情页每次收藏/取消成功后 +1 → 收藏页 [favoriteItemsProvider]
/// 重新拉取（Emby 为收藏唯一数据源，本地不缓存）。
final favoritesRevisionProvider = StateProvider<int>((ref) => 0);

/// 当前服务器收藏分组。随激活服务器变化、修订号变化自动重取。
final favoriteItemsProvider =
    FutureProvider.autoDispose<FavoriteGroups>((ref) async {
  ref.watch(favoritesRevisionProvider);
  // 激活服务器切换也触发重取（embyServiceProvider 依赖 embyConfigProvider）
  ref.watch(embyConfigProvider);
  final items = await ref.watch(embyServiceProvider).getFavoriteItems();
  return FavoriteGroups.fromItems(items);
});
