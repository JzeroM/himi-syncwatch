import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/services/tmdb_aggregate_service.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';

import '../helpers/test_fakes.dart';

const _platform = TmdbPlatform(
  providerId: 8,
  name: 'Netflix',
  logoAsset: 'assets/images/platforms/netflix.png',
);

const _poster = TmdbItem(
  id: 101,
  type: TmdbMediaType.movie,
  title: 'Poster 101',
  posterPath: '/poster101.jpg',
);

EmbyServerConfig _server(String id) => EmbyServerConfig(
      id: id,
      serverUrl: 'https://$id.local',
      serverName: '服务器$id',
      serverId: '$id-sid',
      username: 'user',
      accessToken: 'token',
      userId: 'uid',
    );

class _StagedPlatformAggregate extends TmdbAggregateService {
  _StagedPlatformAggregate({this.emptyFull = false})
      : super(
          tmdb: TmdbService(apiBase: 'http://localhost', credential: 'test'),
          serviceFactory: (_) => FakeEmbyService(),
        );

  final bool emptyFull;
  final List<List<String>> calls = [];

  @override
  Future<Map<String, TmdbAvailability>> resolvePlatformShowcase(
    TmdbPlatformShowcase showcase,
    List<EmbyServerConfig> servers, {
    String? activeServerId,
  }) async {
    calls.add([for (final server in servers) server.id]);
    if (emptyFull && calls.length > 1) return const {};
    final server = servers.first;
    return {
      for (final poster in showcase.posters)
        poster.tmdb.key: TmdbAvailability(
          tmdb: poster.tmdb,
          item: MediaItem(
            id: '${server.id}-${poster.tmdb.id}',
            name: poster.tmdb.title,
            type: 'Movie',
          ),
          server: server,
        ),
    };
  }
}

void main() {
  test('平台海报先当前服务器，再后台补齐全部服务器', () async {
    final s1 = _server('s1');
    final s2 = _server('s2');
    final aggregate = _StagedPlatformAggregate();
    final servers = EmbyServerListNotifier()..setList([s1, s2]);
    final config = EmbyConfigNotifier()..setConfig(s1);
    final showcase = const TmdbPlatformShowcase(
      platform: _platform,
      posters: [TmdbPlatformPoster(tmdb: _poster)],
    );
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(
            const AppSettings(tmdbApiKey: 'test-key'),
          ),
        ),
        tmdbAggregateServiceProvider.overrideWithValue(aggregate),
        tmdbPlatformShowcaseProvider.overrideWith(
          (ref, platform) async => showcase,
        ),
        embyServerListProvider.overrideWith((ref) => servers),
        embyConfigProvider.overrideWith((ref) => config),
      ],
    );
    addTearDown(container.dispose);

    final values = <TmdbPlatformAvailabilityState>[];
    final subscription = container.listen(
      tmdbPlatformAvailabilityProvider(_platform),
      (_, next) {
        if (next.hasValue) values.add(next.value!);
      },
      fireImmediately: true,
    );
    await pumpEventQueue();

    expect(aggregate.calls, [
      ['s1'],
      ['s1', 's2'],
    ]);
    expect(values.first.complete, isFalse);
    expect(values.first.entries[_poster.key]?.server.id, 's1');
    expect(values.last.complete, isTrue);
    expect(values.last.entries[_poster.key]?.server.id, 's1');

    subscription.close();
  });

  test('后台补齐返回空时保留当前服务器实图', () async {
    final s1 = _server('s1');
    final s2 = _server('s2');
    final aggregate = _StagedPlatformAggregate(emptyFull: true);
    final servers = EmbyServerListNotifier()..setList([s1, s2]);
    final config = EmbyConfigNotifier()..setConfig(s1);
    final showcase = const TmdbPlatformShowcase(
      platform: _platform,
      posters: [TmdbPlatformPoster(tmdb: _poster)],
    );
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(
            const AppSettings(tmdbApiKey: 'test-key'),
          ),
        ),
        tmdbAggregateServiceProvider.overrideWithValue(aggregate),
        tmdbPlatformShowcaseProvider.overrideWith(
          (ref, platform) async => showcase,
        ),
        embyServerListProvider.overrideWith((ref) => servers),
        embyConfigProvider.overrideWith((ref) => config),
      ],
    );
    addTearDown(container.dispose);

    final values = <TmdbPlatformAvailabilityState>[];
    final subscription = container.listen(
      tmdbPlatformAvailabilityProvider(_platform),
      (_, next) {
        if (next.hasValue) values.add(next.value!);
      },
      fireImmediately: true,
    );
    await pumpEventQueue();

    expect(values.last.complete, isTrue);
    expect(values.last.entries[_poster.key]?.server.id, 's1');

    subscription.close();
  });
}
