import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/services/tmdb_aggregate_service.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';

import '../helpers/test_fakes.dart';

class _FakeAggregate extends TmdbAggregateService {
  _FakeAggregate(this.sections)
      : super(
          tmdb: TmdbService(apiBase: 'http://localhost', credential: 'test'),
          serviceFactory: (_) => FakeEmbyService(),
        );

  final Map<String, Completer<TmdbAvailabilityResult>> sections;

  @override
  Future<TmdbAvailabilityResult> fetchSection(
    String sectionKey,
    List<EmbyServerConfig> servers, {
    String? activeServerId,
    int pages = 5,
    bool allowCache = true,
  }) {
    return sections[sectionKey]!.future;
  }
}

class _StagedAggregate extends TmdbAggregateService {
  _StagedAggregate(this.byServer, {this.emptyFull = false})
      : super(
          tmdb: TmdbService(apiBase: 'http://localhost', credential: 'test'),
          serviceFactory: (_) => FakeEmbyService(),
        );

  final Map<String, List<TmdbAvailability>> byServer;
  final bool emptyFull;
  final List<List<String>> calls = [];

  @override
  Future<TmdbAvailabilityResult> fetchSection(
    String sectionKey,
    List<EmbyServerConfig> servers, {
    String? activeServerId,
    int pages = 5,
    bool allowCache = true,
  }) async {
    calls.add([for (final server in servers) server.id]);
    if (emptyFull && calls.length > 4) {
      return const TmdbAvailabilityResult(items: []);
    }
    return TmdbAvailabilityResult(
      items: [
        for (final server in servers) ...?byServer[server.id],
      ],
    );
  }
}

EmbyServerConfig _server(String id) => EmbyServerConfig(
      id: id,
      serverUrl: 'https://$id.local',
      serverName: '服务器$id',
      serverId: '$id-sid',
      username: 'user',
      accessToken: 'token',
      userId: 'uid',
    );

TmdbAvailability _entryT(String serverId, int tmdbId) => TmdbAvailability(
      tmdb: TmdbItem(
        id: tmdbId,
        type: TmdbMediaType.movie,
        title: '影片$tmdbId',
      ),
      item: MediaItem(
        id: '$serverId-$tmdbId',
        name: '影片$tmdbId',
        type: 'Movie',
      ),
      server: _server(serverId),
    );

void main() {
  test('首页先产出壳，再按栏目完成顺序渐进更新', () async {
    const keys = [
      'trending_day',
      'trending_week',
      'popular_movies',
      'popular_tv',
    ];
    final completers = {
      for (final key in keys) key: Completer<TmdbAvailabilityResult>(),
    };
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(
            const AppSettings(tmdbApiKey: 'test-key'),
          ),
        ),
        tmdbAggregateServiceProvider.overrideWithValue(
          _FakeAggregate(completers),
        ),
        embyServerListProvider.overrideWith(
          (ref) => EmbyServerListNotifier(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final values = <TmdbHomeData>[];
    final subscription = container.listen(
      tmdbHomeProvider,
      (_, next) {
        if (next.hasValue) values.add(next.value!);
      },
      fireImmediately: true,
    );
    await pumpEventQueue();

    expect(values, isNotEmpty);
    expect(values.first.configured, isTrue);
    expect(values.first.sectionsLoading, isTrue);
    expect(values.first.sections, isEmpty);

    completers['trending_week']!.complete(
      const TmdbAvailabilityResult(items: []),
    );
    await pumpEventQueue();
    expect(
      values.last.sections.map((e) => e.key),
      ['trending_week'],
      reason: '先完成的栏目应先出现',
    );
    expect(values.last.sectionsLoading, isTrue);

    for (final key in keys.where((key) => key != 'trending_week')) {
      completers[key]!.complete(const TmdbAvailabilityResult(items: []));
    }
    await pumpEventQueue();

    expect(values.last.sectionsLoading, isFalse);
    expect(
      values.last.sections.map((e) => e.key),
      keys,
      reason: '全部完成后按固定顺序排列',
    );

    subscription.close();
  });

  test('双服务器：先当前服务器出栏目，再后台补齐另一台服务器', () async {
    final s1 = _server('s1');
    final s2 = _server('s2');
    final aggregate = _StagedAggregate({
      's1': [_entryT('s1', 1)],
      's2': [_entryT('s2', 2)],
    });
    final servers = EmbyServerListNotifier()..setList([s1, s2]);
    final config = EmbyConfigNotifier()..setConfig(s1);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(
            const AppSettings(tmdbApiKey: 'test-key'),
          ),
        ),
        tmdbAggregateServiceProvider.overrideWithValue(aggregate),
        embyServerListProvider.overrideWith((ref) => servers),
        embyConfigProvider.overrideWith((ref) => config),
      ],
    );
    addTearDown(container.dispose);

    final values = <TmdbHomeData>[];
    final subscription = container.listen(
      tmdbHomeProvider,
      (_, next) {
        if (next.hasValue) values.add(next.value!);
      },
      fireImmediately: true,
    );
    await pumpEventQueue(times: 20);

    expect(
      aggregate.calls
          .take(4)
          .every((ids) => ids.length == 1 && ids.first == 's1'),
      isTrue,
      reason: '首轮只查当前服务器',
    );
    expect(
      aggregate.calls.skip(4).every((ids) => ids.length == 2),
      isTrue,
      reason: '第二轮补齐全部服务器',
    );
    expect(
      values.any((data) =>
          data.sections.any((s) => s.items.any((e) => e.server.id == 's1'))),
      isTrue,
    );
    expect(
      values.last.sections.any((s) => s.items.any((e) => e.server.id == 's2')),
      isTrue,
    );
    expect(values.last.sectionsLoading, isFalse);

    subscription.close();
  });

  test('后台补齐返回空时不回退已展示的当前服务器内容', () async {
    final s1 = _server('s1');
    final s2 = _server('s2');
    final aggregate = _StagedAggregate(
      {
        's1': [_entryT('s1', 1)],
      },
      emptyFull: true,
    );
    final servers = EmbyServerListNotifier()..setList([s1, s2]);
    final config = EmbyConfigNotifier()..setConfig(s1);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(
            const AppSettings(tmdbApiKey: 'test-key'),
          ),
        ),
        tmdbAggregateServiceProvider.overrideWithValue(aggregate),
        embyServerListProvider.overrideWith((ref) => servers),
        embyConfigProvider.overrideWith((ref) => config),
      ],
    );
    addTearDown(container.dispose);

    final values = <TmdbHomeData>[];
    final subscription = container.listen(
      tmdbHomeProvider,
      (_, next) {
        if (next.hasValue) values.add(next.value!);
      },
      fireImmediately: true,
    );
    await pumpEventQueue(times: 20);

    expect(
      values.last.sections.first.items.single.server.id,
      's1',
    );
    expect(values.last.sectionsLoading, isFalse);

    subscription.close();
  });

  test('光盘先产出 5 个分区壳，再按分区完成顺序渐进更新', () async {
    const keys = TmdbAggregateService.discSectionKeys;
    final completers = {
      for (final key in keys) key: Completer<TmdbAvailabilityResult>(),
    };
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(
            const AppSettings(tmdbApiKey: 'test-key'),
          ),
        ),
        tmdbAggregateServiceProvider.overrideWithValue(
          _FakeAggregate(completers),
        ),
        embyServerListProvider.overrideWith(
          (ref) => EmbyServerListNotifier(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final values = <TmdbDiscData>[];
    final subscription = container.listen(
      tmdbDiscProvider,
      (_, next) {
        if (next.hasValue) values.add(next.value!);
      },
      fireImmediately: true,
    );
    await pumpEventQueue();

    expect(values, isNotEmpty);
    expect(values.first.sections.map((e) => e.key), keys);
    expect(values.first.sections.every((e) => e.loading), isTrue);
    expect(values.first.loading, isTrue);

    completers['classic_movies']!.complete(
      TmdbAvailabilityResult(items: [_entryT('s1', 9)]),
    );
    await pumpEventQueue();
    expect(
      values.last.sections
          .firstWhere((e) => e.key == 'classic_movies')
          .items
          .single
          .server
          .id,
      's1',
    );
    expect(values.last.loading, isTrue);

    for (final key in keys.where((key) => key != 'classic_movies')) {
      completers[key]!.complete(const TmdbAvailabilityResult(items: []));
    }
    await pumpEventQueue();

    expect(values.last.loading, isFalse);
    expect(values.last.sections.map((e) => e.key), keys);
    expect(
      values.last.sections
          .firstWhere((e) => e.key == 'classic_movies')
          .items
          .single
          .tmdb
          .id,
      9,
    );

    subscription.close();
  });

  test('光盘两阶段：先当前服务器，再补齐全部服务器', () async {
    final s1 = _server('s1');
    final s2 = _server('s2');
    final aggregate = _StagedAggregate({
      's1': [_entryT('s1', 1)],
      's2': [_entryT('s2', 2)],
    });
    final servers = EmbyServerListNotifier()..setList([s1, s2]);
    final config = EmbyConfigNotifier()..setConfig(s1);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(
            const AppSettings(tmdbApiKey: 'test-key'),
          ),
        ),
        tmdbAggregateServiceProvider.overrideWithValue(aggregate),
        embyServerListProvider.overrideWith((ref) => servers),
        embyConfigProvider.overrideWith((ref) => config),
      ],
    );
    addTearDown(container.dispose);

    final values = <TmdbDiscData>[];
    final subscription = container.listen(
      tmdbDiscProvider,
      (_, next) {
        if (next.hasValue) values.add(next.value!);
      },
      fireImmediately: true,
    );
    await pumpEventQueue(times: 20);

    expect(
      aggregate.calls
          .take(TmdbAggregateService.discSectionKeys.length)
          .every((ids) => ids.length == 1 && ids.first == 's1'),
      isTrue,
    );
    expect(
      aggregate.calls
          .skip(TmdbAggregateService.discSectionKeys.length)
          .every((ids) => ids.length == 2),
      isTrue,
    );
    expect(
      values.last.sections.any(
        (section) => section.items.any((e) => e.server.id == 's2'),
      ),
      isTrue,
    );
    expect(values.last.loading, isFalse);

    subscription.close();
  });

  test('未配置 TMDB 时直接返回未配置壳', () async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(const AppSettings()),
        ),
        embyServerListProvider.overrideWith(
          (ref) => EmbyServerListNotifier(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final data = await container.read(tmdbHomeProvider.future);
    expect(data.configured, isFalse);
    expect(data.sectionsLoading, isFalse);
  });

  test('服务器轮播从全部已认证服务器抽取并保留服务器信息', () async {
    final serverA = _server('a');
    final serverB = _server('b');
    final fakeA = FakeEmbyService(items: [
      MediaItem(
        id: 'a-m1',
        name: 'A 电影',
        type: 'Movie',
        backdropWideUrl: 'https://a/backdrop/1.jpg',
        logoUrl: 'https://a/logo/1.png',
        year: '2024',
        communityRating: 8.5,
        genres: const ['动作'],
        providerIds: const {'Tmdb': '1'},
      ),
    ]);
    final fakeB = FakeEmbyService(items: [
      MediaItem(
        id: 'b-m2',
        name: 'B 电影',
        type: 'Movie',
        backdropWideUrl: 'https://b/backdrop/2.jpg',
        providerIds: const {'Tmdb': '2'},
      ),
    ]);
    final list = EmbyServerListNotifier()..setList([serverA, serverB]);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(
            const AppSettings(tmdbApiKey: 'test-key'),
          ),
        ),
        embyServerListProvider.overrideWith((ref) => list),
        embyServiceFactoryProvider.overrideWithValue(
          (server) => server.id == 'b' ? fakeB : fakeA,
        ),
      ],
    );
    addTearDown(container.dispose);

    final heroes = await container.read(tmdbHeroItemsProvider.future);

    expect(heroes, hasLength(2));
    expect(heroes.map((e) => e.item.id), containsAll(['a-m1', 'b-m2']));
    final a = heroes.firstWhere((e) => e.item.id == 'a-m1');
    expect(a.item.name, 'A 电影');
    expect(a.item.logoUrl, 'https://a/logo/1.png');
    expect(a.item.year, '2024');
    expect(a.item.communityRating, 8.5);
    expect(a.item.genres, ['动作']);
  });
}
