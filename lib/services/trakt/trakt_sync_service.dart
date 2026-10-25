import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_client.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_planner.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_store.dart';

class TraktSyncException implements Exception {
  final String message;

  const TraktSyncException(this.message);

  @override
  String toString() => 'TraktSyncException: $message';
}

class TraktSyncService {
  static const localFields = 'ProviderIds,UserData,RunTimeTicks,SeriesId,'
      'IndexNumber,ParentIndexNumber,ProductionYear';

  final TraktClient client;
  final TraktSyncStore store;
  final TraktSyncPlanner planner;

  TraktSyncService({
    required this.client,
    TraktSyncStore? store,
    this.planner = const TraktSyncPlanner(),
  }) : store = store ?? TraktSyncStore();

  Future<TraktSyncResult> sync(List<TraktServerHandle> servers) async {
    if (!client.isAuthenticated) {
      throw const TraktSyncException('未登录 Trakt');
    }
    if (servers.isEmpty) {
      throw const TraktSyncException('没有已启用的在线服务器');
    }

    final remote = await _fetchRemote();
    final fetched = await _fetchActiveServers(servers);
    if (fetched.serversProcessed == 0) {
      throw const TraktSyncException('没有可访问的在线服务器');
    }
    await _reverseLookup(servers, fetched, remote);

    final state = await store.read();
    final plan = planner.build(
      local: fetched.entries,
      remote: remote,
      resetAt: state.resetAt,
    );
    await _execute(plan.actions, fetched.services);
    final next = await store.recordSuccess(plan.stats);
    return TraktSyncResult(
      state: next,
      stats: plan.stats,
      serversProcessed: fetched.serversProcessed,
    );
  }

  Future<TraktSyncResult> resetAll(List<TraktServerHandle> servers) async {
    if (!client.isAuthenticated) {
      throw const TraktSyncException('未登录 Trakt');
    }
    if (servers.isEmpty) {
      throw const TraktSyncException('没有已启用的在线服务器');
    }

    final remote = await _fetchRemote();
    final watchedMovies = <Map<String, dynamic>>[];
    final watchedShows = <Map<String, dynamic>>[];
    final playbackIds = <int>{};

    for (final entry in remote) {
      if (entry.playbackId != null) {
        playbackIds.add(entry.playbackId!);
      }
      if (!entry.watched) continue;
      if (entry.isMovie && _hasIds(entry.ids)) {
        watchedMovies.add({'ids': entry.ids.toJson()});
      }
    }

    final showGroups = <String, _ResetShow>{};
    for (final entry in remote.where((e) => e.watched && e.isEpisode)) {
      if (!_hasIds(entry.showIds) ||
          entry.season == null ||
          entry.episode == null) {
        continue;
      }
      final key = entry.showIds
          .toJson()
          .entries
          .map((e) => '${e.key}:${e.value}')
          .toList()
        ..sort();
      final grouped = showGroups.putIfAbsent(
        key.join('|'),
        () => _ResetShow(entry.showIds),
      );
      grouped.add(entry.season!, entry.episode!);
    }
    for (final show in showGroups.values) {
      watchedShows.add(show.toJson());
    }

    await client.removeHistory(movies: watchedMovies, shows: watchedShows);
    await client.deleteAllPlayback(playbackIds);

    await store.recordReset(servers.map((e) => e.configId));
    final fetched = await _fetchActiveServers(servers, resolveSeries: false);
    if (fetched.serversProcessed == 0) {
      throw const TraktSyncException('没有可访问的在线服务器');
    }
    for (final entry in fetched.entries) {
      if (!entry.hasLocal) continue;
      final service = fetched.services[entry.serverConfigId];
      if (service == null) continue;
      if (entry.watched) {
        final ok = await service.setWatched(entry.itemId!, false);
        if (!ok) throw const TraktSyncException('清除已看失败');
      }
      if (entry.positionMs > 0) {
        final ok = await service.setPlaybackPosition(entry.itemId!, 0);
        if (!ok) throw const TraktSyncException('清除进度失败');
      }
    }

    final state = await store.recordSuccess(const TraktSyncStatistics());
    return TraktSyncResult(
      state: state,
      stats: const TraktSyncStatistics(),
      serversProcessed: fetched.serversProcessed,
    );
  }

  Future<List<TraktSyncEntry>> _fetchRemote() async {
    final movies = await client.getWatchedMovies();
    final shows = await client.getWatchedShows();
    final playback = await client.getPlayback();
    final entries = <TraktSyncEntry>[];

    for (final row in movies) {
      final movie = row['movie'];
      if (movie is! Map) continue;
      final ids = _idsFromMap(movie['ids']);
      if (!_hasIds(ids)) continue;
      entries.add(TraktSyncEntry(
        kind: TraktItemKind.movie,
        ids: ids,
        watched: true,
        lastPlayed: DateTime.tryParse(
          row['last_watched_at']?.toString() ?? '',
        ),
      ));
    }

    for (final row in shows) {
      final show = row['show'];
      if (show is! Map) continue;
      final showIds = _idsFromMap(show['ids']);
      final seasons = row['seasons'];
      if (seasons is! List) continue;
      for (final seasonRow in seasons) {
        if (seasonRow is! Map) continue;
        final season = (seasonRow['number'] as num?)?.toInt();
        final episodes = seasonRow['episodes'];
        if (season == null || episodes is! List) continue;
        for (final episodeRow in episodes) {
          if (episodeRow is! Map) continue;
          final number = (episodeRow['number'] as num?)?.toInt();
          if (number == null) continue;
          entries.add(TraktSyncEntry(
            kind: TraktItemKind.episode,
            ids: _idsFromMap(episodeRow['ids']),
            showIds: showIds,
            season: season,
            episode: number,
            watched: true,
            lastPlayed: DateTime.tryParse(
              episodeRow['last_watched_at']?.toString() ?? '',
            ),
          ));
        }
      }
    }

    for (final row in playback) {
      final id = (row['id'] as num?)?.toInt();
      final progress = (row['progress'] as num?)?.toDouble();
      final movie = row['movie'];
      if (movie is Map) {
        final ids = _idsFromMap(movie['ids']);
        if (!_hasIds(ids)) continue;
        entries.add(TraktSyncEntry(
          kind: TraktItemKind.movie,
          ids: ids,
          progressPercent: progress,
          playbackId: id,
        ));
        continue;
      }
      final episode = row['episode'];
      if (episode is! Map) continue;
      final season = (episode['season'] as num?)?.toInt();
      final number = (episode['number'] as num?)?.toInt();
      if (season == null || number == null) continue;
      final show = row['show'];
      entries.add(TraktSyncEntry(
        kind: TraktItemKind.episode,
        ids: _idsFromMap(episode['ids']),
        showIds: show is Map ? _idsFromMap(show['ids']) : const TraktMediaIds(),
        season: season,
        episode: number,
        progressPercent: progress,
        playbackId: id,
      ));
    }

    return entries;
  }

  Future<_FetchedServers> _fetchActiveServers(
    List<TraktServerHandle> servers, {
    bool resolveSeries = true,
  }) async {
    final entries = <TraktSyncEntry>[];
    final services = <String, EmbyService>{};
    var processed = 0;
    for (final handle in servers) {
      try {
        final serverEntries = await _fetchActiveServer(
          handle,
          resolveSeries: resolveSeries,
        );
        entries.addAll(serverEntries);
        services[handle.configId] = handle.service;
        processed++;
      } catch (_) {}
    }
    return _FetchedServers(
      entries: entries,
      services: services,
      serversProcessed: processed,
    );
  }

  Future<List<TraktSyncEntry>> _fetchActiveServer(
    TraktServerHandle handle, {
    required bool resolveSeries,
  }) async {
    final played = await _queryItems(
      handle.service,
      includeItemTypes: 'Movie,Episode',
      filters: 'IsPlayed',
    );
    final resumable = await _queryItems(
      handle.service,
      includeItemTypes: 'Movie,Episode',
      filters: 'IsResumable',
    );

    final byId = <String, MediaItem>{};
    for (final item in played) {
      if (!item.isWatched) continue;
      _mergeActiveItem(byId, item);
    }
    for (final item in resumable) {
      if (item.playbackPositionMs <= 0) continue;
      _mergeActiveItem(byId, item);
    }

    final seriesIds = resolveSeries
        ? await _fetchSeriesMetadata(
            handle.service,
            byId.values
                .where((e) => e.isEpisode)
                .map((e) => e.seriesId)
                .whereType<String>(),
          )
        : const <String, TraktMediaIds>{};

    final items = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    final result = <TraktSyncEntry>[];
    for (final item in items) {
      if (item.isMovie) {
        final ids = _idsFromMedia(item);
        if (!_hasIds(ids)) continue;
        result.add(
          _localEntry(handle, item, ids: ids, kind: TraktItemKind.movie),
        );
      } else if (item.isEpisode) {
        final season = item.parentIndexNumber;
        final number = item.indexNumber;
        if (season == null || number == null) continue;
        final seriesId = item.seriesId;
        result.add(_localEntry(
          handle,
          item,
          ids: _idsFromMedia(item),
          showIds: seriesId == null
              ? const TraktMediaIds()
              : (seriesIds[seriesId] ?? const TraktMediaIds()),
          kind: TraktItemKind.episode,
          season: season,
          episode: number,
        ));
      }
    }
    return result;
  }

  void _mergeActiveItem(Map<String, MediaItem> byId, MediaItem item) {
    final existing = byId[item.id];
    if (existing == null || (!existing.isWatched && item.isWatched)) {
      byId[item.id] = item;
    }
  }

  Future<Map<String, TraktMediaIds>> _fetchSeriesMetadata(
    EmbyService service,
    Iterable<String> ids,
  ) async {
    final unique = ids.toSet().toList();
    final result = <String, TraktMediaIds>{};
    for (final chunk in _chunks(unique, 50)) {
      final series = await _queryItems(
        service,
        includeItemTypes: 'Series',
        ids: chunk.join(','),
        fields: 'ProviderIds',
      );
      for (final item in series) {
        if (!item.isSeries) continue;
        result[item.id] = _idsFromMedia(item);
      }
    }
    return result;
  }

  Future<List<MediaItem>> _queryItems(
    EmbyService service, {
    String? includeItemTypes,
    String? filters,
    String? parentId,
    String? ids,
    List<String>? anyProviderIds,
    String fields = localFields,
  }) async {
    final result = <MediaItem>[];
    var start = 0;
    const pageSize = 500;
    String? previousFirst;
    for (var page = 0; page < 1000; page++) {
      final chunk = await service.getItems(
        includeItemTypes: includeItemTypes,
        parentId: parentId,
        filters: filters,
        ids: ids,
        anyProviderIds: anyProviderIds,
        fields: fields,
        limit: pageSize,
        startIndex: start,
      );
      if (chunk.isEmpty) break;
      if (chunk.first.id == previousFirst) break;
      previousFirst = chunk.first.id;
      result.addAll(chunk);
      start += chunk.length;
      if (ids != null) break;
    }
    return result;
  }

  Future<void> _reverseLookup(
    List<TraktServerHandle> servers,
    _FetchedServers fetched,
    List<TraktSyncEntry> remote,
  ) async {
    final movieTokens = <String>{};
    final showTargets = <_ShowTarget>[];
    for (final entry in [...fetched.entries, ...remote]) {
      if (entry.isMovie) {
        movieTokens.addAll(_providerTokens(entry.ids));
        continue;
      }
      if (!entry.isEpisode || entry.season == null || entry.episode == null) {
        continue;
      }
      final tokens = _providerTokens(entry.showIds);
      if (tokens.isEmpty) continue;
      final episodeKey = 's${entry.season}|e${entry.episode}';
      _ShowTarget? target;
      for (final existing in showTargets) {
        if (existing.tokens.any(tokens.contains)) {
          target = existing;
          break;
        }
      }
      if (target == null) {
        target = _ShowTarget(tokens: tokens.toSet());
        showTargets.add(target);
      } else {
        target.tokens.addAll(tokens);
      }
      target.episodes.add(episodeKey);
    }
    if (movieTokens.isEmpty && showTargets.isEmpty) return;

    for (final handle in servers) {
      if (!fetched.services.containsKey(handle.configId)) continue;
      final existingIds = fetched.entries
          .where((e) => e.serverConfigId == handle.configId)
          .map((e) => e.itemId)
          .whereType<String>()
          .toSet();
      try {
        await _reverseMovies(
          handle,
          movieTokens,
          existingIds,
          fetched.entries,
        );
        await _reverseEpisodes(
          handle,
          showTargets,
          existingIds,
          fetched.entries,
        );
      } catch (_) {}
    }
  }

  Future<void> _reverseMovies(
    TraktServerHandle handle,
    Set<String> tokens,
    Set<String> existingIds,
    List<TraktSyncEntry> output,
  ) async {
    for (final chunk in _chunks(tokens.toList(), 50)) {
      final items = await _queryItems(
        handle.service,
        includeItemTypes: 'Movie',
        anyProviderIds: chunk,
      );
      for (final item in items) {
        if (!item.isMovie || existingIds.contains(item.id)) continue;
        if (!_matchesProviderTokens(item, chunk)) continue;
        final ids = _idsFromMedia(item);
        if (!_hasIds(ids)) continue;
        output.add(
          _localEntry(handle, item, ids: ids, kind: TraktItemKind.movie),
        );
        existingIds.add(item.id);
      }
    }
  }

  Future<void> _reverseEpisodes(
    TraktServerHandle handle,
    List<_ShowTarget> targets,
    Set<String> existingIds,
    List<TraktSyncEntry> output,
  ) async {
    final showTokens = targets.expand((e) => e.tokens).toSet().toList();
    final seriesById = <String, MediaItem>{};
    for (final chunk in _chunks(showTokens, 50)) {
      final series = await _queryItems(
        handle.service,
        includeItemTypes: 'Series',
        anyProviderIds: chunk,
        fields: 'ProviderIds',
      );
      for (final item in series) {
        if (!item.isSeries) continue;
        if (!_matchesProviderTokens(item, chunk)) continue;
        seriesById[item.id] = item;
      }
    }

    for (final series in seriesById.values) {
      final seriesTokens = _providerTokens(_idsFromMedia(series));
      if (seriesTokens.isEmpty) continue;
      final wanted = <String>{};
      for (final target in targets) {
        if (target.tokens.any(seriesTokens.contains)) {
          wanted.addAll(target.episodes);
        }
      }
      if (wanted.isEmpty) continue;
      final episodes = await _queryItems(
        handle.service,
        parentId: series.id,
        includeItemTypes: 'Episode',
      );
      final showIds = _idsFromMedia(series);
      for (final item in episodes) {
        if (!item.isEpisode || existingIds.contains(item.id)) continue;
        final season = item.parentIndexNumber;
        final number = item.indexNumber;
        if (season == null || number == null) continue;
        if (!wanted.contains('s$season|e$number')) continue;
        output.add(_localEntry(
          handle,
          item,
          ids: _idsFromMedia(item),
          showIds: showIds,
          kind: TraktItemKind.episode,
          season: season,
          episode: number,
        ));
        existingIds.add(item.id);
      }
    }
  }

  List<String> _providerTokens(TraktMediaIds ids) {
    final tokens = <String>[];
    if (ids.tmdb != null && ids.tmdb! > 0) tokens.add('tmdb.${ids.tmdb}');
    if (ids.tvdb != null && ids.tvdb! > 0) tokens.add('tvdb.${ids.tvdb}');
    final imdb = ids.imdb?.trim().toLowerCase() ?? '';
    if (imdb.isNotEmpty) tokens.add('imdb.$imdb');
    return tokens;
  }

  bool _matchesProviderTokens(MediaItem item, List<String> tokens) {
    final itemTokens = _providerTokens(_idsFromMedia(item));
    return itemTokens.any(tokens.contains);
  }

  static Iterable<List<T>> _chunks<T>(List<T> values, int size) sync* {
    for (var start = 0; start < values.length; start += size) {
      yield values.sublist(
        start,
        start + size > values.length ? values.length : start + size,
      );
    }
  }

  TraktSyncEntry _localEntry(
    TraktServerHandle handle,
    MediaItem item, {
    required TraktMediaIds ids,
    required TraktItemKind kind,
    TraktMediaIds showIds = const TraktMediaIds(),
    int? season,
    int? episode,
  }) {
    final runtimeTicks = item.runTimeTicks ?? 0;
    return TraktSyncEntry(
      kind: kind,
      ids: ids,
      showIds: showIds,
      season: season,
      episode: episode,
      watched: item.isWatched,
      positionMs: item.playbackPositionMs,
      runtimeMs: runtimeTicks > 0 ? runtimeTicks ~/ 10000 : null,
      lastPlayed: item.lastPlayedDate,
      serverConfigId: handle.configId,
      itemId: item.id,
    );
  }

  Future<void> _execute(
    List<TraktSyncAction> actions,
    Map<String, EmbyService> services,
  ) async {
    final history = actions
        .where((a) => a.type == TraktActionType.addTraktHistory)
        .map((a) => a.entry)
        .whereType<TraktSyncEntry>()
        .toList();
    await _flushHistory(history);
    for (final action in actions) {
      if (action.type == TraktActionType.addTraktHistory) continue;
      final service = action.serverConfigId == null
          ? null
          : services[action.serverConfigId];
      final entry = action.entry;
      switch (action.type) {
        case TraktActionType.markEmbyWatched:
          if (service == null || action.itemId == null) continue;
          if (!await service.setWatched(action.itemId!, true)) {
            throw const TraktSyncException('写入已看失败');
          }
          break;
        case TraktActionType.unmarkEmbyWatched:
          if (service == null || action.itemId == null) continue;
          if (!await service.setWatched(action.itemId!, false)) {
            throw const TraktSyncException('清除已看失败');
          }
          break;
        case TraktActionType.clearEmbyProgress:
          if (service == null || action.itemId == null) continue;
          if (!await service.setPlaybackPosition(action.itemId!, 0)) {
            throw const TraktSyncException('清除进度失败');
          }
          break;
        case TraktActionType.writeEmbyProgress:
          if (service == null ||
              action.itemId == null ||
              action.positionMs == null) {
            continue;
          }
          if (!await service.setPlaybackPosition(
            action.itemId!,
            action.positionMs!,
          )) {
            throw const TraktSyncException('写入进度失败');
          }
          break;
        case TraktActionType.addTraktHistory:
          break;
        case TraktActionType.deleteTraktPlayback:
          if (action.playbackId == null) continue;
          await client.deletePlayback(action.playbackId!);
          break;
        case TraktActionType.pauseTrakt:
          if (entry == null) continue;
          final percent = action.progressPercent;
          if (percent == null) continue;
          if (entry.isMovie) {
            await client.pauseMovie(ids: entry.ids, progress: percent);
          } else {
            await client.pauseEpisode(
              ids: entry.ids,
              showIds: entry.showIds,
              season: entry.season ?? 0,
              episode: entry.episode ?? 0,
              progress: percent,
            );
          }
          break;
      }
    }
  }

  Future<void> _flushHistory(List<TraktSyncEntry> entries) async {
    const chunkSize = 100;
    for (var start = 0; start < entries.length; start += chunkSize) {
      final chunk = entries.skip(start).take(chunkSize).toList();
      final movies = <Map<String, dynamic>>[];
      final shows = <String, _HistoryShow>{};
      for (final entry in chunk) {
        if (entry.isMovie) {
          if (_hasIds(entry.ids)) movies.add({'ids': entry.ids.toJson()});
          continue;
        }
        if (entry.season == null ||
            entry.episode == null ||
            !_hasIds(entry.showIds)) {
          continue;
        }
        final key = entry.showIds
            .toJson()
            .entries
            .map((e) => '${e.key}:${e.value}')
            .toList()
          ..sort();
        final show = shows.putIfAbsent(
          key.join('|'),
          () => _HistoryShow(entry.showIds),
        );
        show.add(entry.season!, entry.episode!);
      }
      if (movies.isEmpty && shows.isEmpty) continue;
      await client.addHistory(
        movies: movies,
        shows: shows.values.map((e) => e.toJson()).toList(),
      );
    }
  }

  TraktMediaIds _idsFromMedia(MediaItem item) {
    return TraktMediaIds(
      tmdb: int.tryParse(item.providerId('tmdb') ?? ''),
      tvdb: int.tryParse(item.providerId('tvdb') ?? ''),
      imdb: item.providerId('imdb'),
    );
  }

  TraktMediaIds _idsFromMap(Object? raw) {
    if (raw is Map<String, dynamic>) return TraktMediaIds.fromJson(raw);
    if (raw is Map)
      return TraktMediaIds.fromJson(Map<String, dynamic>.from(raw));
    return const TraktMediaIds();
  }

  bool _hasIds(TraktMediaIds ids) =>
      (ids.trakt != null && ids.trakt! > 0) ||
      (ids.tmdb != null && ids.tmdb! > 0) ||
      (ids.tvdb != null && ids.tvdb! > 0) ||
      (ids.imdb != null && ids.imdb!.trim().isNotEmpty);
}

class _ShowTarget {
  final Set<String> tokens;
  final Set<String> episodes = {};

  _ShowTarget({required this.tokens});
}

class _FetchedServers {
  final List<TraktSyncEntry> entries;
  final Map<String, EmbyService> services;
  final int serversProcessed;

  const _FetchedServers({
    required this.entries,
    required this.services,
    required this.serversProcessed,
  });
}

class _ResetShow {
  final TraktMediaIds ids;
  final Map<int, Set<int>> seasons = {};

  _ResetShow(this.ids);

  void add(int season, int episode) {
    seasons.putIfAbsent(season, () => <int>{}).add(episode);
  }

  Map<String, dynamic> toJson() => {
        'ids': ids.toJson(),
        'seasons': seasons.entries
            .map((e) => {
                  'number': e.key,
                  'episodes': e.value.map((n) => {'number': n}).toList(),
                })
            .toList(),
      };
}

class _HistoryShow {
  final TraktMediaIds ids;
  final Map<int, Set<int>> seasons = {};

  _HistoryShow(this.ids);

  void add(int season, int episode) {
    seasons.putIfAbsent(season, () => <int>{}).add(episode);
  }

  Map<String, dynamic> toJson() => {
        'ids': ids.toJson(),
        'seasons': seasons.entries
            .map((e) => {
                  'number': e.key,
                  'episodes': e.value.map((n) => {'number': n}).toList(),
                })
            .toList(),
      };
}
