import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/emby_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_auth_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_client.dart';
import 'package:himi_syncwatch/services/trakt/trakt_config.dart';
import 'package:himi_syncwatch/services/trakt/trakt_item_reset_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_sync_models.dart';
import 'package:himi_syncwatch/services/trakt/trakt_token_store.dart';

import '../helpers/fake_secure_storage.dart';

MediaItem _movie(
  String id,
  String tmdb, {
  int positionMs = 0,
}) {
  return MediaItem(
    id: id,
    name: 'Movie $id',
    type: 'Movie',
    providerIds: {'Tmdb': tmdb},
    playbackPositionMs: positionMs,
    runTimeTicks: 100000 * 10000,
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
  int positionMs = 0,
}) {
  return MediaItem(
    id: id,
    name: 'Episode $id',
    type: 'Episode',
    seriesId: seriesId,
    parentIndexNumber: 1,
    indexNumber: 2,
    playbackPositionMs: positionMs,
    runTimeTicks: 100000 * 10000,
  );
}

class _FakeEmbyService extends EmbyService {
  _FakeEmbyService(this.items);

  final List<MediaItem> items;
  final List<(String, bool)> watchedCalls = [];
  final Map<String, int> positionCalls = {};

  @override
  Future<MediaItem?> getItemDetails(String id) async {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

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
    Iterable<MediaItem> source = items;
    if (anyProviderIds != null && anyProviderIds.isNotEmpty) {
      final wanted = anyProviderIds.map((e) => e.toLowerCase()).toSet();
      source = source.where((e) => _tokensFor(e).any(wanted.contains));
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

class _FakeTraktClient extends TraktClient {
  _FakeTraktClient()
      : super(
          auth: TraktAuthService(
            config: const TraktConfig(clientId: 'test'),
            store: TraktTokenStore(storage: FakeSecureStorage()),
          ),
        );

  List<Map<String, dynamic>> playback = [];
  final List<int> deletedPlayback = [];
  final List<Map<String, dynamic>> removedMovies = [];
  final List<Map<String, dynamic>> removedShows = [];

  @override
  bool get isAuthenticated => true;

  @override
  Future<List<Map<String, dynamic>>> getPlayback() async => playback;

  @override
  Future<void> deletePlayback(int playbackId) async {
    deletedPlayback.add(playbackId);
  }

  @override
  Future<void> removeHistory({
    List<Map<String, dynamic>> movies = const [],
    List<Map<String, dynamic>> shows = const [],
  }) async {
    removedMovies.addAll(movies);
    removedShows.addAll(shows);
  }
}

List<String> _tokensFor(MediaItem item) => [
      if (item.providerId('tmdb') != null) 'tmdb.${item.providerId('tmdb')}',
      if (item.providerId('tvdb') != null) 'tvdb.${item.providerId('tvdb')}',
      if (item.providerId('imdb') != null)
        'imdb.${item.providerId('imdb')!.toLowerCase()}',
    ];

void main() {
  late _FakeTraktClient client;

  setUp(() {
    client = _FakeTraktClient();
  });

  test('重播未看条目：删 Trakt playback、清其他服务器进度、不动历史', () async {
    final serverA = _FakeEmbyService([
      _movie('a-m1', '1', positionMs: 50000),
    ]);
    final serverB = _FakeEmbyService([
      _movie('b-m1', '1', positionMs: 30000),
    ]);
    client.playback = [
      {
        'id': 9,
        'movie': {
          'ids': {'tmdb': 1}
        }
      }
    ];
    final service = TraktItemResetService(client: client);

    final ok = await service.resetItem(
      servers: [
        TraktServerHandle(configId: 'a', service: serverA),
        TraktServerHandle(configId: 'b', service: serverB),
      ],
      serverConfigId: 'a',
      itemId: 'a-m1',
      removeWatched: false,
    );

    expect(ok, isTrue);
    expect(client.deletedPlayback, [9]);
    expect(client.removedMovies, isEmpty);
    expect(serverA.positionCalls['a-m1'], isNull);
    expect(serverB.positionCalls['b-m1'], 0);
    expect(serverA.watchedCalls, isEmpty);
    expect(serverB.watchedCalls, isEmpty);
  });

  test('重播已看电影：删 playback + history，并取消所有服务器已看', () async {
    final serverA = _FakeEmbyService([_movie('a-m1', '1')]);
    final serverB = _FakeEmbyService([_movie('b-m1', '1')]);
    client.playback = [
      {
        'id': 9,
        'movie': {
          'ids': {'tmdb': 1}
        }
      }
    ];
    final service = TraktItemResetService(client: client);

    await service.resetItem(
      servers: [
        TraktServerHandle(configId: 'a', service: serverA),
        TraktServerHandle(configId: 'b', service: serverB),
      ],
      serverConfigId: 'a',
      itemId: 'a-m1',
      removeWatched: true,
    );

    expect(client.deletedPlayback, [9]);
    expect(client.removedMovies.single['ids'], {'tmdb': 1});
    expect(serverA.watchedCalls, isEmpty);
    expect(serverB.watchedCalls, contains(('b-m1', false)));
    expect(serverA.positionCalls['a-m1'], isNull);
    expect(serverB.positionCalls['b-m1'], 0);
  });

  test('单集重播：按剧集/季/集删 history 并跨服务器取消已看', () async {
    final serverA = _FakeEmbyService([
      _series('s-a', '10'),
      _episode('a-e1', 's-a', positionMs: 50000),
    ]);
    final serverB = _FakeEmbyService([
      _series('s-b', '10'),
      _episode('b-e1', 's-b', positionMs: 30000),
    ]);
    client.playback = [
      {
        'id': 7,
        'episode': {
          'season': 1,
          'number': 2,
          'ids': <String, dynamic>{},
        },
        'show': {
          'ids': {'tmdb': 10}
        },
      }
    ];
    final service = TraktItemResetService(client: client);

    await service.resetItem(
      servers: [
        TraktServerHandle(configId: 'a', service: serverA),
        TraktServerHandle(configId: 'b', service: serverB),
      ],
      serverConfigId: 'a',
      itemId: 'a-e1',
      removeWatched: true,
    );

    expect(client.deletedPlayback, [7]);
    expect(client.removedShows.single['ids'], {'tmdb': 10});
    expect(serverA.watchedCalls, isEmpty);
    expect(serverB.watchedCalls, contains(('b-e1', false)));
    expect(serverA.positionCalls['a-e1'], isNull);
    expect(serverB.positionCalls['b-e1'], 0);
  });
}
