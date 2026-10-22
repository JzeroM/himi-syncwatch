import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';

/// 收藏条目 + 来源服务器（跨服务器聚合时用于正确进入详情/操作）。
class FavoriteEntry {
  const FavoriteEntry({required this.item, this.server});

  final MediaItem item;
  final EmbyServerConfig? server;

  String get id => item.id;
  String get name => item.name;
  String get type => item.type;
  String? get serverId => server?.id;
}

/// 收藏条目按类型分组（电影 / 电视剧 / 集），供收藏页三分区展示。
class FavoriteGroups {
  const FavoriteGroups({
    this.movies = const [],
    this.series = const [],
    this.episodes = const [],
    this.failedServerCount = 0,
  });

  final List<FavoriteEntry> movies;
  final List<FavoriteEntry> series;
  final List<FavoriteEntry> episodes;
  final int failedServerCount;

  bool get isEmpty => movies.isEmpty && series.isEmpty && episodes.isEmpty;

  /// 按 `Type` 分组（忽略其它类型）。[server] 用于详情页来源服务器。
  static FavoriteGroups fromItems(
    List<MediaItem> items, {
    EmbyServerConfig? server,
  }) {
    return fromEntries([
      for (final item in items) FavoriteEntry(item: item, server: server),
    ]);
  }

  static FavoriteGroups fromEntries(List<FavoriteEntry> entries) {
    final movies = <FavoriteEntry>[];
    final series = <FavoriteEntry>[];
    final episodes = <FavoriteEntry>[];
    for (final entry in entries) {
      switch (entry.item.type) {
        case 'Movie':
          movies.add(entry);
          break;
        case 'Series':
          series.add(entry);
          break;
        case 'Episode':
          episodes.add(entry);
          break;
      }
    }
    return FavoriteGroups(
      movies: movies,
      series: series,
      episodes: episodes,
    );
  }

  static FavoriteGroups failed(int count) =>
      FavoriteGroups(failedServerCount: count);
}

/// 收藏修订号：详情页每次收藏/取消成功后 +1 → 收藏页重新拉取
/// （Emby 为收藏唯一数据源，本地不缓存）。
final favoritesRevisionProvider = StateProvider<int>((ref) => 0);

/// 当前服务器收藏分组。随激活服务器变化、修订号变化自动重取。
final favoriteItemsProvider =
    FutureProvider.autoDispose<FavoriteGroups>((ref) async {
  ref.watch(favoritesRevisionProvider);
  final config = ref.watch(embyConfigProvider);
  final items = await ref.watch(embyServiceProvider).getFavoriteItems();
  return FavoriteGroups.fromItems(items, server: config);
});

String _favoriteDedupeKey(MediaItem item) {
  final tmdb = item.tmdbId;
  if (item.isEpisode) {
    if (tmdb != null) return 'e:$tmdb';
    return 'e:${item.seriesName ?? item.name}|'
        '${item.parentIndexNumber ?? 0}|${item.indexNumber ?? 0}';
  }
  if (tmdb != null) return '${item.type}:$tmdb';
  return '${item.type}:${item.name.trim().toLowerCase()}|${item.year ?? ''}';
}

/// 聚合模式收藏：并发读取全部已认证服务器的收藏，按 TMDB id 去重。
/// 单台失败不阻塞其它服务器；去重代表项优先当前激活服务器。
final aggregateFavoriteItemsProvider =
    FutureProvider.autoDispose<FavoriteGroups>((ref) async {
  ref.watch(favoritesRevisionProvider);
  final servers = ref
      .watch(embyServerListProvider)
      .where((s) => s.isAuthenticated)
      .toList(growable: false);
  if (servers.isEmpty) return const FavoriteGroups();
  final activeId = ref.watch(embyConfigProvider)?.id;
  final ordered = <EmbyServerConfig>[
    if (activeId != null) ...servers.where((s) => s.id == activeId),
    ...servers.where((s) => s.id != activeId),
  ];
  final factory = ref.watch(embyServiceFactoryProvider);

  final failed = <String>{};
  final batches = await Future.wait(ordered.map((server) async {
    try {
      final items = await factory(server).getFavoriteItems();
      return [
        for (final item in items)
          FavoriteEntry(item: item, server: server),
      ];
    } catch (_) {
      failed.add(server.id);
      return <FavoriteEntry>[];
    }
  }));

  final seen = <String>{};
  final deduped = <FavoriteEntry>[];
  for (final entry in batches.expand((e) => e)) {
    if (seen.add(_favoriteDedupeKey(entry.item))) deduped.add(entry);
  }
  final grouped = FavoriteGroups.fromEntries(deduped);
  return FavoriteGroups(
    movies: grouped.movies,
    series: grouped.series,
    episodes: grouped.episodes,
    failedServerCount: failed.length,
  );
});
