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

class _FakeEmbyService extends EmbyService {
  _FakeEmbyService(this.items, {this.fail = false});

  final List<MediaItem> items;
  bool fail;
  final List<(String, bool)> watchedCalls = [];
  final Map<String, int> positionCalls = {};

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
    String? genres,
    String? years,
    String? officialRatings,
  }) async {
    if (fail) throw StateError('offline');
    if ((startIndex ?? 0) > 0) return const [];
    return items;
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
    final result = await service.sync([
      TraktServerHandle(configId: 'a', service: serverA),
      TraktServerHandle(configId: 'b', service: serverB),
      TraktServerHandle(configId: 'offline', service: offline),
    ]);

    expect(result.serversProcessed, 2);
    expect(serverB.watchedCalls, contains(('b-m1', true)));
    expect(serverA.positionCalls['a-m2'], 70000);
    expect(serverB.positionCalls['b-m2'], 70000);
    expect(client.deletedPlayback, isEmpty);
    expect(client.addedMovies, hasLength(1));
    expect(client.addedMovies.single['ids'], {'tmdb': 3});
    expect(result.stats.movies, 2);
    expect((await syncStore.read()).lastSuccessAt, isNotNull);
  });

  test('重置清空历史/播放进度并给全部已选服务器记录水位', () async {
    final server = _FakeEmbyService([
      _movie('a-m1', '1', watched: true),
      _movie('a-m2', '2', positionMs: 50000),
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
        'id': 9,
        'progress': 30.0,
        'movie': {
          'ids': {'tmdb': 2}
        }
      }
    ];

    final service = TraktSyncService(client: client, store: syncStore);
    final result = await service.resetAll([
      TraktServerHandle(configId: 'a', service: server),
      TraktServerHandle(configId: 'offline', service: offline),
    ]);

    expect(client.removedMovies.single['ids'], {'tmdb': 1});
    expect(client.deletedPlayback, [9]);
    expect(server.watchedCalls, contains(('a-m1', false)));
    expect(server.positionCalls['a-m2'], 0);
    expect(result.stats.movies, 0);
    final state = await syncStore.read();
    expect(state.resetAt.keys, containsAll(['a', 'offline']));
    expect(state.lastSuccessAt, isNotNull);
  });
}
