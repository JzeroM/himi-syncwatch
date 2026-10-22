import 'dart:math';

import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';

class _AvailCacheEntry {
  _AvailCacheEntry(this.item)
      : expiresAt = DateTime.now().add(
          item == null
              ? const Duration(minutes: 5)
              : const Duration(minutes: 15),
        );

  final MediaItem? item;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);
}

class TmdbAvailabilityResult {
  const TmdbAvailabilityResult({
    required this.items,
    this.failedServerIds = const {},
  });

  final List<TmdbAvailability> items;
  final Set<String> failedServerIds;
}

class TmdbSectionPage {
  const TmdbSectionPage({
    required this.items,
    required this.hasMore,
    this.failedServerIds = const {},
  });

  final List<TmdbAvailability> items;
  final bool hasMore;
  final Set<String> failedServerIds;
}

class TmdbPlatformPage {
  const TmdbPlatformPage({
    required this.items,
    required this.hasMore,
    this.failedServerIds = const {},
  });

  final List<TmdbAvailability> items;
  final bool hasMore;
  final Set<String> failedServerIds;
}

/// 把 TMDB 目录与 Emby 服务器库存做交集，并聚合跨服务器续播。
class TmdbAggregateService {
  TmdbAggregateService({
    required this.tmdb,
    required this.serviceFactory,
  });

  final TmdbService tmdb;
  final EmbyService Function(EmbyServerConfig server) serviceFactory;

  final Map<String, _AvailCacheEntry> _cache = {};

  static const _sectionTitles = <String, String>{
    'trending_day': '今日趋势',
    'trending_week': '本周趋势',
    'popular_movies': '热门电影',
    'popular_tv': '热门剧集',
  };

  static String sectionTitle(String key) => _sectionTitles[key] ?? 'TMDB';

  static bool isKnownSection(String key) => _sectionTitles.containsKey(key);

  List<EmbyServerConfig> _targets(
    List<EmbyServerConfig> servers,
    String? activeServerId,
  ) {
    final authenticated =
        servers.where((s) => s.isAuthenticated).toList(growable: false);
    if (activeServerId == null || activeServerId.isEmpty) return authenticated;
    final active = authenticated.where((s) => s.id == activeServerId).toList();
    if (active.isEmpty) return authenticated;
    return [
      ...active,
      ...authenticated.where((s) => s.id != activeServerId),
    ];
  }

  String _cacheKey(String serverId, TmdbMediaType type, String tmdbId) =>
      '$serverId|${type.embyType}|$tmdbId';

  Future<Map<String, Map<String, MediaItem>>> _lookupForType(
    List<EmbyServerConfig> servers,
    TmdbMediaType type,
    List<String> ids,
    Set<String> failedServerIds,
  ) async {
    final wanted = ids.where((e) => e.isNotEmpty).toSet().toList();
    final result = <String, Map<String, MediaItem>>{};
    if (wanted.isEmpty || servers.isEmpty) return result;

    Future<void> runOne(EmbyServerConfig server) async {
      final byId = <String, MediaItem>{};
      final toQuery = <String>[];
      for (final id in wanted) {
        final key = _cacheKey(server.id, type, id);
        final cached = _cache[key];
        if (cached != null && !cached.expired) {
          final item = cached.item;
          if (item != null) byId[id] = item;
        } else {
          toQuery.add(id);
        }
      }
      if (toQuery.isNotEmpty) {
        try {
          final service = serviceFactory(server);
          for (var start = 0; start < toQuery.length; start += 20) {
            final end =
                start + 20 >= toQuery.length ? toQuery.length : start + 20;
            final List<String> chunk = toQuery.sublist(start, end);
            final items = await service.getItemsByProviderIds(
              tmdbIds: chunk,
              includeItemTypes: type.embyType,
            );
            final returned = <String>{};
            for (final item in items) {
              final tmdbId = item.tmdbId;
              if (tmdbId == null || !chunk.contains(tmdbId)) continue;
              final existing = byId[tmdbId];
              if (existing == null ||
                  (existing.posterUrl == null && item.posterUrl != null)) {
                byId[tmdbId] = item;
              }
              returned.add(tmdbId);
            }
            for (final id in chunk) {
              _cache[_cacheKey(server.id, type, id)] =
                  _AvailCacheEntry(byId[id]);
            }
          }
        } catch (_) {
          failedServerIds.add(server.id);
        }
      }
      result[server.id] = byId;
    }

    await Future.wait(servers.map(runOne));
    return result;
  }

  Future<TmdbAvailabilityResult> resolveAvailability(
    List<TmdbItem> tmdbItems,
    List<EmbyServerConfig> servers, {
    String? activeServerId,
  }) async {
    final ordered = _targets(servers, activeServerId);
    if (ordered.isEmpty || tmdbItems.isEmpty) {
      return const TmdbAvailabilityResult(items: []);
    }
    final byType = <TmdbMediaType, List<String>>{};
    for (final item in tmdbItems) {
      byType.putIfAbsent(item.type, () => []).add(item.id.toString());
    }
    final failed = <String>{};
    final lookups = <TmdbMediaType, Map<String, Map<String, MediaItem>>>{};
    await Future.wait(byType.entries.map((entry) async {
      lookups[entry.key] =
          await _lookupForType(ordered, entry.key, entry.value, failed);
    }));

    final out = <TmdbAvailability>[];
    final seen = <String>{};
    for (final tmdbItem in tmdbItems) {
      if (!seen.add(tmdbItem.key)) continue;
      final lookup = lookups[tmdbItem.type];
      if (lookup == null) continue;
      for (final server in ordered) {
        final local = lookup[server.id]?[tmdbItem.id.toString()];
        if (local == null) continue;
        out.add(TmdbAvailability(
          tmdb: tmdbItem,
          item: local,
          server: server,
        ));
        break;
      }
    }
    return TmdbAvailabilityResult(
      items: out,
      failedServerIds: failed,
    );
  }

  /// 查询某个本地电影/剧集在全部服务器中的副本（详情页资源栏）。
  /// 不需要 TMDB 目录接口，只使用本地 `ProviderIds.Tmdb`。
  Future<TmdbAvailabilityResult> findAllAvailability(
    MediaItem item,
    List<EmbyServerConfig> servers, {
    String? activeServerId,
  }) async {
    final tmdbId = int.tryParse(item.tmdbId ?? '');
    final type = item.isMovie
        ? TmdbMediaType.movie
        : (item.isSeries ? TmdbMediaType.tv : null);
    if (tmdbId == null || tmdbId <= 0 || type == null) {
      return const TmdbAvailabilityResult(items: []);
    }
    final ordered = _targets(servers, activeServerId);
    if (ordered.isEmpty) return const TmdbAvailabilityResult(items: []);
    final failed = <String>{};
    final lookups = await _lookupForType(
      ordered,
      type,
      [tmdbId.toString()],
      failed,
    );
    final tmdb = TmdbItem(
      id: tmdbId,
      type: type,
      title: item.name,
      overview: item.overview,
      releaseDate: item.year,
      voteAverage: item.communityRating,
    );
    final out = <TmdbAvailability>[];
    for (final server in ordered) {
      final local = lookups[server.id]?[tmdbId.toString()];
      if (local == null) continue;
      out.add(TmdbAvailability(tmdb: tmdb, item: local, server: server));
    }
    return TmdbAvailabilityResult(items: out, failedServerIds: failed);
  }

  Future<TmdbSectionPage> fetchSectionPage(
    String sectionKey,
    List<EmbyServerConfig> servers, {
    String? activeServerId,
    int page = 1,
  }) async {
    final p = page < 1 ? 1 : page;
    TmdbPagedResult? result;
    switch (sectionKey) {
      case 'trending_day':
        result = await tmdb.trendingDayPage(page: p);
        break;
      case 'trending_week':
        result = await tmdb.trendingWeekPage(page: p);
        break;
      case 'popular_movies':
        result = await tmdb.popularMoviesPage(page: p);
        break;
      case 'popular_tv':
        result = await tmdb.popularTvPage(page: p);
        break;
    }
    if (result == null) {
      return const TmdbSectionPage(items: [], hasMore: false);
    }
    final resolved = await resolveAvailability(
      result.items,
      servers,
      activeServerId: activeServerId,
    );
    return TmdbSectionPage(
      items: resolved.items,
      hasMore: result.hasMore,
      failedServerIds: resolved.failedServerIds,
    );
  }

  Future<TmdbAvailabilityResult> fetchSection(
    String sectionKey,
    List<EmbyServerConfig> servers, {
    String? activeServerId,
    int pages = 5,
    bool allowCache = true,
  }) async {
    final pageCount = pages.clamp(1, 10);
    final futures = <Future<List<TmdbItem>>>[];
    switch (sectionKey) {
      case 'trending_day':
        for (var p = 1; p <= pageCount; p++) {
          futures.add(tmdb.trendingDay(page: p));
        }
        break;
      case 'trending_week':
        for (var p = 1; p <= pageCount; p++) {
          futures.add(tmdb.trendingWeek(page: p));
        }
        break;
      case 'popular_movies':
        for (var p = 1; p <= pageCount; p++) {
          futures.add(tmdb.popularMovies(page: p));
        }
        break;
      case 'popular_tv':
        for (var p = 1; p <= pageCount; p++) {
          futures.add(tmdb.popularTv(page: p));
        }
        break;
      default:
        return const TmdbAvailabilityResult(items: []);
    }
    final batches = await Future.wait(futures);
    final items = <TmdbItem>[];
    final seen = <String>{};
    for (final batch in batches) {
      for (final item in batch) {
        if (seen.add(item.key)) items.add(item);
      }
    }
    return resolveAvailability(
      items,
      servers,
      activeServerId: activeServerId,
    );
  }

  /// 首页平台卡：每天固定一组随机海报，服务器实图优先、TMDB 图兜底。
  Future<List<TmdbPlatformShowcase>> fetchPlatformShowcases(
    List<EmbyServerConfig> servers, {
    required String region,
    String? activeServerId,
    DateTime? today,
  }) async {
    final day = today ?? DateTime.now();
    final dayKey = day.year * 10000 + day.month * 100 + day.day;
    final ordered = _targets(servers, activeServerId);
    final candidates = <int, List<TmdbItem>>{};

    await Future.wait(tmdbPlatforms.map((platform) async {
      try {
        final results = await Future.wait(
          TmdbMediaType.values.map(
            (type) => tmdb.discoverPlatform(
              providerId: platform.providerId,
              type: type,
              region: region,
              page: 1,
              allowCache: true,
            ),
          ),
        );
        final seen = <String>{};
        final pool = <TmdbItem>[];
        for (final result in results) {
          for (final item in result.items) {
            if (item.posterPath == null || item.posterPath!.isEmpty) continue;
            if (seen.add(item.key)) pool.add(item);
          }
        }
        // 先固定顺序再按日期洗牌，避免 TMDB 返回顺序变化导致同日结果漂移。
        pool.sort((a, b) => a.key.compareTo(b.key));
        pool.shuffle(Random(dayKey * 1000 + platform.providerId));
        candidates[platform.providerId] = pool.take(6).toList(growable: false);
      } catch (_) {
        candidates[platform.providerId] = const [];
      }
    }));

    final allCandidates = <TmdbItem>[];
    final seen = <String>{};
    for (final platform in tmdbPlatforms) {
      for (final item
          in candidates[platform.providerId] ?? const <TmdbItem>[]) {
        if (seen.add(item.key)) allCandidates.add(item);
      }
    }
    final resolved = await resolveAvailability(
      allCandidates,
      ordered,
      activeServerId: activeServerId,
    );
    final byKey = {
      for (final entry in resolved.items) entry.tmdb.key: entry,
    };

    return [
      for (final platform in tmdbPlatforms)
        _showcaseFor(
          platform,
          candidates[platform.providerId] ?? const [],
          byKey,
        ),
    ];
  }

  TmdbPlatformShowcase _showcaseFor(
    TmdbPlatform platform,
    List<TmdbItem> candidates,
    Map<String, TmdbAvailability> byKey,
  ) {
    final local = <TmdbItem>[];
    final remote = <TmdbItem>[];
    for (final item in candidates) {
      (byKey.containsKey(item.key) ? local : remote).add(item);
    }
    final selected = [...local, ...remote].take(2).toList(growable: false);
    return TmdbPlatformShowcase(
      platform: platform,
      posters: [
        for (final item in selected)
          TmdbPlatformPoster(
            tmdb: item,
            availability: byKey[item.key],
          ),
      ],
    );
  }

  Future<TmdbPlatformPage> fetchPlatformPage({
    required int providerId,
    required String region,
    required int page,
    required List<EmbyServerConfig> servers,
    TmdbMediaType? type,
    String? activeServerId,
  }) async {
    final types = type == null ? TmdbMediaType.values : [type];
    final results = await Future.wait(types.map((t) {
      return tmdb.discoverPlatform(
        providerId: providerId,
        type: t,
        region: region,
        page: page,
        allowCache: page == 1,
      );
    }));
    final items = <TmdbItem>[];
    final seen = <String>{};
    for (final result in results) {
      for (final item in result.items) {
        if (seen.add(item.key)) items.add(item);
      }
    }
    final resolved = await resolveAvailability(
      items,
      servers,
      activeServerId: activeServerId,
    );
    return TmdbPlatformPage(
      items: resolved.items,
      hasMore: results.any((r) => r.hasMore),
      failedServerIds: resolved.failedServerIds,
    );
  }

  Future<TmdbHomeData> fetchSections(
    List<EmbyServerConfig> servers, {
    String? activeServerId,
  }) async {
    final ordered = _targets(servers, activeServerId);
    if (ordered.isEmpty) {
      return const TmdbHomeData(configured: true);
    }

    final lists = await Future.wait([
      tmdb.trendingDay(),
      tmdb.trendingWeek(),
      tmdb.popularMovies(),
      tmdb.popularTv(),
    ]);
    final failed = <String>{};
    final sections = <TmdbSectionData>[];
    final sectionResults = await Future.wait([
      resolveAvailability(lists[0], ordered, activeServerId: activeServerId),
      resolveAvailability(lists[1], ordered, activeServerId: activeServerId),
      resolveAvailability(lists[2], ordered, activeServerId: activeServerId),
      resolveAvailability(lists[3], ordered, activeServerId: activeServerId),
    ]);
    const keys = [
      'trending_day',
      'trending_week',
      'popular_movies',
      'popular_tv',
    ];
    for (var i = 0; i < keys.length; i++) {
      failed.addAll(sectionResults[i].failedServerIds);
      sections.add(TmdbSectionData(
        key: keys[i],
        title: sectionTitle(keys[i]),
        items: sectionResults[i].items,
      ));
    }

    return TmdbHomeData(
      configured: true,
      sections: sections,
      failedServerCount: failed.length,
    );
  }

  Future<TmdbHomeData> fetchHome(
    List<EmbyServerConfig> servers, {
    String? activeServerId,
  }) async {
    final sectionsFuture = fetchSections(
      servers,
      activeServerId: activeServerId,
    );
    final resumeFuture = fetchResume(
      _targets(servers, activeServerId),
      activeServerId,
    );
    final sections = await sectionsFuture;
    final resume = await resumeFuture;
    return TmdbHomeData(
      configured: true,
      resume: resume.entries,
      sections: sections.sections,
      failedServerCount:
          sections.failedServerCount + resume.failedServerIds.length,
    );
  }

  Future<TmdbResumeResult> fetchResume(
    List<EmbyServerConfig> servers,
    String? activeServerId,
  ) async {
    final failed = <String>{};
    final entries = <TmdbResumeEntry>[];
    await Future.wait(servers.map((server) async {
      try {
        final items = await serviceFactory(server).getResumeItems(limit: 24);
        entries.addAll(items
            .where((e) => e.playbackPositionMs > 0 || e.playedPercentage > 0)
            .map((e) => TmdbResumeEntry(item: e, server: server)));
      } catch (_) {
        failed.add(server.id);
      }
    }));

    final byKey = <String, TmdbResumeEntry>{};
    final activeId = activeServerId;
    for (final entry in entries) {
      final prev = byKey[entry.dedupeKey];
      if (prev == null) {
        byKey[entry.dedupeKey] = entry;
        continue;
      }
      final prevTime = prev.playedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final nextTime = entry.playedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final preferNext = nextTime.isAfter(prevTime) ||
          (nextTime.isAtSameMomentAs(prevTime) &&
              (activeId != null && entry.server.id == activeId));
      if (preferNext) byKey[entry.dedupeKey] = entry;
    }
    final sorted = byKey.values.toList()
      ..sort((a, b) {
        final at = a.playedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.playedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    return TmdbResumeResult(entries: sorted, failedServerIds: failed);
  }
}
