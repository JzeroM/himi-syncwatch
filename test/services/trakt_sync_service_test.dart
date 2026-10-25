import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/trakt_models.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_auth_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_client.dart';
import 'package:himi_syncwatch/services/trakt/trakt_config.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_store.dart';
import 'package:himi_syncwatch/services/trakt/trakt_token_store.dart';

import '../helpers/fake_secure_storage.dart';

MediaItem _movie(
  String id,
  String tmdb, {
  bool watched = false,
  int positionMs = 0,
  int runtimeMs = 100000,
  DateTime? lastPlayed,
}) {
  return MediaItem(
    id: id,
    name: 'Movie $id',
    type: 'Movie',
    providerIds: {'Tmdb': tmdb},
    isWatched: watched,
    playbackPositionMs: positionMs,
    runTimeTicks: runtimeMs * 10000,
    lastPlayedDate: lastPlayed,
  );
}

MediaItem _series(String id, String tmdb) {
  return MediaItem(
    id: id,
    name: 'Show $id',
    type: 'Series',
    providerIds: {'Tmdb': tmdb},
  );
}

MediaItem _episode(
  String id,
  String seriesId, {
  bool watched = false,
  int positionMs = 0,
}) {
  return MediaItem(
    id: id,
    name: 'Episode $id',
    type: 'Episode',
    seriesId: seriesId,
    parentIndexNumber: 1,
    indexNumber: 2,
    providerIds: const {},
    isWatched: watched,
    playbackPositionMs: positionMs,
    runTimeTicks: 100000 * 10000,
  );
}

class _FakeEmbyService extends EmbyService {
  _FakeEmbyService(this.items, {this.fail = false});

  final List<MediaItem> items;
  bool fail;
  final List<(String, bool)> watchedCalls = [];
  final Map<String, int> positionCalls = {};
  final List<_ItemsRequest> requests = [];

  @override
  Future<List<MediaItem>> getItems({
    String? parentId,
    String? includeItemTypes,
    int? limit,
    int? startIndex,
    String? fields,
    String? sortBy,
    String? sortOrder,
    String? filters,
    String? ids,
    List<String>? anyProviderIds,
    String? genres,
    String? years,
    String? officialRatings,
  }) async {
    if (fail) throw StateError('offline');
    requests.add(_ItemsRequest(
      parentId: parentId,
      includeItemTypes: includeItemTypes,
      filters: filters,
      ids: ids,
      anyProviderIds: anyProviderIds,
      startIndex: startIndex,
    ));
    Iterable<MediaItem> source = items;
    if (ids != null && ids.isNotEmpty) {
      final wanted = ids.split(',').toSet();
      source = source.where((e) => wanted.contains(e.id));
    }
    if (anyProviderIds != null && anyProviderIds.isNotEmpty) {
      final wanted = anyProviderIds.map((e) => e.toLowerCase()).toSet();
      source = source.where(
        (e) => _tokensFor(e).any(wanted.contains),
      );
    }
    if (filters == 'IsPlayed') {
      source = source.where((e) => e.isWatched);
    } else if (filters == 'IsResumable') {
      source = source.where((e) => e.playbackPositionMs > 0);
    }
    if (parentId != null) {
      source = source.where((e) => e.seriesId == parentId);
    }
    if (includeItemTypes != null && includeItemTypes.isNotEmpty) {
      final types = includeItemTypes.split(',').toSet();
      source = source.where((e) => types.contains(e.type));
    }
    final list = source.toList();
    final from = startIndex ?? 0;
    if (from >= list.length) return const [];
    final take = limit ?? list.length;
    final to = (from + take) > list.length ? list.length : from + take;
    return list.sublist(from, to);
  }

  @override
  Future<bool> setWatched(String itemId, bool watched) async {
    watchedCalls.add((itemId, watched));
    return true;
  }

  @override
  Future<bool> setPlaybackPosition(String itemId, int positionMs) async {
    positionCalls[itemId] = positionMs;
    return true;
  }
}

class _ItemsRequest {
  final String? parentId;
  final String? includeItemTypes;
  final String? filters;
  final String? ids;
  final List<String>? anyProviderIds;
  final int? startIndex;

  const _ItemsRequest({
    this.parentId,
    this.includeItemTypes,
    this.filters,
    this.ids,
    this.anyProviderIds,
    this.startIndex,
  });
}

List<String> _tokensFor(MediaItem item) => [
      if (item.providerId('tmdb') != null) 'tmdb.${item.providerId('tmdb')}',
      if (item.providerId('tvdb') != null) 'tvdb.${item.providerId('tvdb')}',
      if (item.providerId('imdb') != null)
        'imdb.${item.providerId('imdb')!.toLowerCase()}',
    ];

class _FakeTraktClient extends TraktClient {
  _FakeTraktClient()
      : super(
          auth: TraktAuthService(
            config: const TraktConfig(clientId: 'test'),
            store: TraktTokenStore(storage: FakeSecureStorage()),
          ),
        );

  List<Map<String, dynamic>> watchedMovies = [];
  List<Map<String, dynamic>> watchedShows = [];
  List<Map<String, dynamic>> playback = [];

  final List<Map<String, dynamic>> addedMovies = [];
  final List<Map<String, dynamic>> addedShows = [];
  final List<Map<String, dynamic>> removedMovies = [];
  final List<Map<String, dynamic>> removedShows = [];
  final List<int> deletedPlayback = [];
  final List<double> pauses = [];

  @override
  bool get isAuthenticated => true;

  @override
  Future<List<Map<String, dynamic>>> getWatchedMovies() async => watchedMovies;

  @override
  Future<List<Map<String, dynamic>>> getWatchedShows() async => watchedShows;

  @override
  Future<List<Map<String, dynamic>>> getPlayback() async => playback;

  @override
  Future<void> addHistory({
    List<Map<String, dynamic>> movies = const [],
    List<Map<String, dynamic>> shows = const [],
  }) async {
    addedMovies.addAll(movies);
    addedShows.addAll(shows);
  }

  @override
  Future<void> removeHistory({
    List<Map<String, dynamic>> movies = const [],
    List<Map<String, dynamic>> shows = const [],
  }) async {
    removedMovies.addAll(movies);
    removedShows.addAll(shows);
  }

  @override
  Future<void> deletePlayback(int playbackId) async {
    deletedPlayback.add(playbackId);
  }

  @override
  Future<void> pauseMovie({
    required TraktMediaIds ids,
    required double progress,
  }) async {
    pauses.add(progress);
  }
}

void main() {
  late FakeSecureStorage storage;
  late TraktSyncStore syncStore;
  late _FakeTraktClient client;

  setUp(() {
    storage = FakeSecureStorage();
    syncStore = TraktSyncStore(storage: storage);
    client = _FakeTraktClient();
  });

  test('跨服务器合并并写回 Emby/Trakt，跳过离线服务器', () async {
    final now = DateTime.utc(2026, 1, 1, 12);
    final serverA = _FakeEmbyService([
      _movie('a-m1', '1', watched: true, lastPlayed: now),
      _movie('a-m2', '2', positionMs: 50000, lastPlayed: now),
      _movie('a-m3', '3', watched: true, lastPlayed: now),
    ]);
    final serverB = _FakeEmbyService([
      _movie('b-m1', '1'),
      _movie('b-m2', '2', positionMs: 20000, lastPlayed: now),
    ]);
    final offline = _FakeEmbyService([], fail: true);
    client.watchedMovies = [
      {
        'movie': {
          'ids': {'tmdb': 1}
        }
      }
    ];
    client.playback = [
      {
        'id': 77,
        'progress': 70.0,
        'movie': {
          'ids': {'tmdb': 2}
        }
      }
    ];

    final service = TraktSyncService(client: client, store: syncStore);
    final progress = <TraktSyncProgress>[];
    final result = await service.sync(
      [
        TraktServerHandle(configId: 'a', service: serverA),
        TraktServerHandle(configId: 'b', service: serverB),
        TraktServerHandle(configId: 'offline', service: offline),
      ],
      onProgress: progress.add,
    );

    expect(result.serversProcessed, 2);
    expect(serverB.watchedCalls, contains(('b-m1', true)));
    expect(serverA.positionCalls['a-m2'], 70000);
    expect(serverB.positionCalls['b-m2'], 70000);
    expect(client.deletedPlayback, isEmpty);
    expect(client.addedMovies, hasLength(1));
    expect(client.addedMovies.single['ids'], {'tmdb': 3});
    expect(result.stats.movies, 3);
    expect((await syncStore.read()).lastSuccessAt, isNotNull);
    expect(
      progress.map((e) => e.phase).toSet(),
      containsAll([
        TraktSyncPhase.readingRemote,
        TraktSyncPhase.scanningServers,
        TraktSyncPhase.matching,
        TraktSyncPhase.writing,
      ]),
    );
    final last = progress.last;
    expect(last.phase, TraktSyncPhase.writing);
    expect(last.actionsDone, last.actionsTotal);
    expect(
      serverA.requests.where(
        (r) =>
            r.filters == null &&
            r.ids == null &&
            r.anyProviderIds == null &&
            r.parentId == null,
      ),
      isEmpty,
    );
    expect(
      serverA.requests.any((r) => r.filters == 'IsPlayed'),
      isTrue,
    );
    expect(
      serverA.requests.any((r) => r.filters == 'IsResumable'),
      isTrue,
    );
    expect(
      serverA.requests.any((r) => r.anyProviderIds != null),
      isTrue,
    );
  });

  test('Trakt 已看条目反向补齐本地未看条目', () async {
    final server = _FakeEmbyService([
      _movie('b-m1', '1'),
    ]);
    client.watchedMovies = [
      {
        'movie': {
          'ids': {'tmdb': 1}
        }
      }
    ];

    final service = TraktSyncService(client: client, store: syncStore);
    await service.sync([
      TraktServerHandle(configId: 'b', service: server),
    ]);

    expect(server.watchedCalls, contains(('b-m1', true)));
  });

  test('A 服有进度、B 服无进度时只补 B 进度，不清 A 进度', () async {
    final serverA = _FakeEmbyService([
      _movie('a-m1', '1', positionMs: 50000),
    ]);
    final serverB = _FakeEmbyService([
      _movie('b-m1', '1'),
    ]);

    final service = TraktSyncService(client: client, store: syncStore);
    final result = await service.sync([
      TraktServerHandle(configId: 'a', service: serverA),
      TraktServerHandle(configId: 'b', service: serverB),
    ]);

    expect(serverA.positionCalls['a-m1'], isNull);
    expect(serverB.positionCalls['b-m1'], 50000);
    expect(result.stats.movies, 1);
  });

  test('旧 reset_at 存档不再清除任何服务器进度', () async {
    storage.data[TraktSyncStore.stateKey] = jsonEncode({
      'reset_at': {
        'a': DateTime.utc(2026, 1, 1).toIso8601String(),
        'b': DateTime.utc(2026, 1, 1).toIso8601String(),
      },
      'movies': 10,
      'shows': 10,
      'episodes': 10,
    });
    final serverA = _FakeEmbyService([
      _movie('a-m1', '1', positionMs: 50000),
    ]);
    final serverB = _FakeEmbyService([
      _movie('b-m1', '1'),
    ]);

    final service = TraktSyncService(client: client, store: syncStore);
    await service.sync([
      TraktServerHandle(configId: 'a', service: serverA),
      TraktServerHandle(configId: 'b', service: serverB),
    ]);

    expect(serverA.positionCalls['a-m1'], isNull);
    expect(serverB.positionCalls['b-m1'], 50000);
  });

  test('Trakt 进度反向写回本地未看条目', () async {
    final server = _FakeEmbyService([
      _movie('b-m1', '1'),
    ]);
    client.playback = [
      {
        'id': 5,
        'progress': 50.0,
        'movie': {
          'ids': {'tmdb': 1}
        }
      }
    ];

    final service = TraktSyncService(client: client, store: syncStore);
    await service.sync([
      TraktServerHandle(configId: 'b', service: server),
    ]);

    expect(server.positionCalls['b-m1'], 50000);
  });

  test('单集按剧集 ProviderIds 反向补齐并写入 Trakt 历史', () async {
    final serverA = _FakeEmbyService([
      _series('s-a', '10'),
      _episode('a-e1', 's-a', watched: true),
    ]);
    final serverB = _FakeEmbyService([
      _series('s-b', '10'),
      _episode('b-e1', 's-b'),
    ]);

    final service = TraktSyncService(client: client, store: syncStore);
    await service.sync([
      TraktServerHandle(configId: 'a', service: serverA),
      TraktServerHandle(configId: 'b', service: serverB),
    ]);

    expect(serverB.watchedCalls, contains(('b-e1', true)));
    expect(client.addedShows, hasLength(1));
    expect(client.addedShows.single['ids'], {'tmdb': 10});
    expect(
      serverB.requests.where(
        (r) =>
            r.filters == null &&
            r.ids == null &&
            r.anyProviderIds == null &&
            r.parentId == null,
      ),
      isEmpty,
    );
  });
}
