import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/services/tmdb_aggregate_service.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';

import '../helpers/test_fakes.dart';

class _FakeTmdbService extends TmdbService {
  _FakeTmdbService() : super(apiBase: 'http://localhost', credential: 'test');

  final Map<TmdbMediaType, List<TmdbItem>> lists = {
    TmdbMediaType.movie: const [],
    TmdbMediaType.tv: const [],
  };
  final Map<int, String?> logos = {};

  @override
  Future<List<TmdbItem>> trendingDay({int page = 1}) async =>
      lists[TmdbMediaType.movie]!;

  @override
  Future<TmdbPagedResult> trendingDayPage({int page = 1}) async =>
      TmdbPagedResult(
        items: lists[TmdbMediaType.movie]!,
        page: page,
        totalPages: page < 2 ? 2 : page,
        totalResults: lists[TmdbMediaType.movie]!.length,
      );

  @override
  Future<List<TmdbItem>> trendingWeek({int page = 1}) async =>
      lists[TmdbMediaType.movie]!;

  @override
  Future<List<TmdbItem>> popularMovies({int page = 1}) async =>
      lists[TmdbMediaType.movie]!;

  @override
  Future<List<TmdbItem>> popularTv({int page = 1}) async =>
      lists[TmdbMediaType.tv]!;

  @override
  Future<Map<int, String?>> platformLogos(String region) async => logos;

  @override
  Future<TmdbPagedResult> discoverPlatform({
    required int providerId,
    required TmdbMediaType type,
    required String region,
    int page = 1,
    bool allowCache = false,
  }) async {
    final all = lists[type]!;
    return TmdbPagedResult(
      items: all,
      page: page,
      totalPages: page < 2 ? 2 : page,
      totalResults: all.length,
    );
  }
}

class _ProviderEmbyService extends FakeEmbyService {
  _ProviderEmbyService(this.byTmdb);

  final Map<String, List<MediaItem>> byTmdb;
  int calls = 0;

  @override
  Future<List<MediaItem>> getItemsByProviderIds({
    required List<String> tmdbIds,
    String? includeItemTypes,
  }) async {
    calls++;
    return [
      for (final id in tmdbIds)
        ...?byTmdb[id]?.where(
          (e) => includeItemTypes == null || e.type == includeItemTypes,
        ),
    ];
  }
}

EmbyServerConfig _server(String id) => EmbyServerConfig(
      id: id,
      serverUrl: 'http://$id.local',
      serverName: '服务器$id',
      serverId: '$id-sid',
      username: 'u',
      accessToken: 'token',
      userId: 'uid',
    );

MediaItem _movie(String id, String tmdb, {String? name}) => MediaItem(
      id: id,
      name: name ?? 'Movie $tmdb',
      type: 'Movie',
      providerIds: {'Tmdb': tmdb},
    );

const _movie1 = TmdbItem(
  id: 101,
  type: TmdbMediaType.movie,
  title: 'Movie 101',
  releaseDate: '2024-01-01',
);
const _movie2 = TmdbItem(
  id: 102,
  type: TmdbMediaType.movie,
  title: 'Movie 102',
  releaseDate: '2023-01-01',
);
const _show = TmdbItem(
  id: 201,
  type: TmdbMediaType.tv,
  title: 'Show 201',
);

void main() {
  test('可用性匹配：仅保留服务器已有条目，当前服务器优先且不重复', () async {
    final s1 = _server('s1');
    final s2 = _server('s2');
    final services = {
      's1': _ProviderEmbyService({
        '101': [_movie('s1-m1', '101')],
        '102': [_movie('s1-m2', '102')],
      }),
      's2': _ProviderEmbyService({
        '101': [_movie('s2-m1', '101')],
      }),
    };
    final tmdb = _FakeTmdbService();
    final aggregate = TmdbAggregateService(
      tmdb: tmdb,
      serviceFactory: (s) => services[s.id]!,
    );

    final result = await aggregate.resolveAvailability(
      const [_movie1, _movie2, _show],
      [s1, s2],
      activeServerId: 's2',
    );

    expect(result.items.map((e) => e.tmdb.key), [
      _movie1.key,
      _movie2.key,
    ]);
    expect(result.items.first.server.id, 's2');
    expect(result.items.last.server.id, 's1');
    expect(result.failedServerIds, isEmpty);
  });

  test('可用性缓存：同一批 TMDB id 第二次不再请求 Emby', () async {
    final s1 = _server('s1');
    final service = _ProviderEmbyService({
      '101': [_movie('m1', '101')],
    });
    final aggregate = TmdbAggregateService(
      tmdb: _FakeTmdbService(),
      serviceFactory: (_) => service,
    );

    await aggregate.resolveAvailability(const [_movie1], [s1]);
    await aggregate.resolveAvailability(const [_movie1], [s1]);

    expect(service.calls, 1);
  });

  test('单服务器失败不影响其他服务器，并记录失败 id', () async {
    final s1 = _server('s1');
    final s2 = _server('s2');
    final ok = _ProviderEmbyService({
      '101': [_movie('s2-m1', '101')],
    });
    final aggregate = TmdbAggregateService(
      tmdb: _FakeTmdbService(),
      serviceFactory: (s) {
        if (s.id == 's1') throw StateError('boom');
        return ok;
      },
    );

    final result = await aggregate.resolveAvailability(
      const [_movie1],
      [s1, s2],
    );

    expect(result.items.single.server.id, 's2');
    expect(result.failedServerIds, {'s1'});
  });

  test('findAllAvailability 返回同一 TMDB id 的全部服务器副本', () async {
    final s1 = _server('s1');
    final s2 = _server('s2');
    final services = {
      's1': _ProviderEmbyService({
        '101': [_movie('s1-m1', '101')],
      }),
      's2': _ProviderEmbyService({
        '101': [_movie('s2-m1', '101')],
      }),
    };
    final aggregate = TmdbAggregateService(
      tmdb: _FakeTmdbService(),
      serviceFactory: (s) => services[s.id]!,
    );

    final result = await aggregate.findAllAvailability(
      _movie('local', '101'),
      [s1, s2],
      activeServerId: 's2',
    );

    expect(result.items.map((e) => e.item.id), ['s2-m1', 's1-m1']);
  });

  test('findAllAvailability 无 TMDB id 时直接返回空', () async {
    final aggregate = TmdbAggregateService(
      tmdb: _FakeTmdbService(),
      serviceFactory: (_) => _ProviderEmbyService({}),
    );
    final result = await aggregate.findAllAvailability(
      MediaItem(id: 'x', name: 'X', type: 'Movie'),
      [_server('s1')],
    );
    expect(result.items, isEmpty);
  });

  test('fetchSection 拦截未知栏目且合并多页去重', () async {
    final service = _ProviderEmbyService({
      '101': [_movie('m1', '101')],
      '102': [_movie('m2', '102')],
    });
    final tmdb = _FakeTmdbService()
      ..lists[TmdbMediaType.movie] = const [_movie1, _movie2];
    final aggregate = TmdbAggregateService(
      tmdb: tmdb,
      serviceFactory: (_) => service,
    );

    final unknown = await aggregate.fetchSection('nope', [_server('s1')]);
    expect(unknown.items, isEmpty);

    final result =
        await aggregate.fetchSection('trending_day', [_server('s1')], pages: 3);
    expect(result.items.map((e) => e.tmdb.key), [_movie1.key, _movie2.key]);
  });

  test('fetchPlatformPage 合并电影/剧集并按页返回 hasMore', () async {
    final service = _ProviderEmbyService({
      '101': [_movie('m1', '101')],
      '201': [
        MediaItem(
          id: 't1',
          name: 'Show',
          type: 'Series',
          providerIds: const {'Tmdb': '201'},
        ),
      ],
    });
    final tmdb = _FakeTmdbService()
      ..lists[TmdbMediaType.movie] = const [_movie1]
      ..lists[TmdbMediaType.tv] = const [_show];
    final aggregate = TmdbAggregateService(
      tmdb: tmdb,
      serviceFactory: (_) => service,
    );

    final page = await aggregate.fetchPlatformPage(
      providerId: 8,
      region: 'US',
      page: 1,
      servers: [_server('s1')],
    );

    expect(page.items.map((e) => e.tmdb.key), [_movie1.key, _show.key]);
    expect(page.hasMore, isTrue);
  });

  test('fetchSectionPage 单页返回且 hasMore 来自 TMDB', () async {
    final tmdb = _FakeTmdbService()
      ..lists[TmdbMediaType.movie] = const [_movie1, _movie2];
    final service = _ProviderEmbyService({
      '101': [_movie('m1', '101')],
      '102': [_movie('m2', '102')],
    });
    final aggregate = TmdbAggregateService(
      tmdb: tmdb,
      serviceFactory: (_) => service,
    );

    final page = await aggregate.fetchSectionPage(
      'trending_day',
      [_server('s1')],
    );

    expect(page.items.map((e) => e.tmdb.key), [_movie1.key, _movie2.key]);
    expect(page.hasMore, isTrue);
  });
}
