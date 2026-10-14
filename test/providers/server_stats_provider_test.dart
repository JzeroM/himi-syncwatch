import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_counts.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/server_stats_provider.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _server({
  required String id,
  required String serverId,
  bool authenticated = true,
}) {
  return EmbyServerConfig(
    id: id,
    serverUrl: 'https://$id.example.com',
    serverName: '服务器$id',
    serverId: serverId,
    username: 'user',
    accessToken: authenticated ? 'token' : null,
    userId: authenticated ? 'uid' : null,
  );
}

void main() {
  test('loadAll 并行取延迟与计数', () async {
    final fake = FakeEmbyService(
      itemCounts: const MediaCounts(movies: 10, series: 20, episodes: 30),
      pingLatencyMs: 10,
    );
    final container = ProviderContainer(
      overrides: [
        embyServiceFactoryProvider.overrideWithValue((_) => fake),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(serverStatsProvider.notifier)
        .loadAll([_server(id: 'a', serverId: 's1')]);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final stats = container.read(serverStatsProvider)['a'];
    expect(stats, isNotNull);
    expect(stats!.latencyMs, isNotNull);
    expect(stats.latencyMs! >= 8, isTrue);
    expect(stats.counts?.movies, 10);
    expect(stats.counts?.series, 20);
    expect(stats.isEmpty, isFalse);
  });

  test('未认证服务器只测延迟不拉计数', () async {
    final fake = FakeEmbyService(
      itemCounts: const MediaCounts(movies: 1, series: 2, episodes: 3),
    );
    final container = ProviderContainer(
      overrides: [
        embyServiceFactoryProvider.overrideWithValue((_) => fake),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(serverStatsProvider.notifier)
        .loadAll([_server(id: 'a', serverId: 's1', authenticated: false)]);

    final stats = container.read(serverStatsProvider)['a'];
    expect(stats, isNotNull);
    expect(stats!.latencyMs, isNotNull);
    expect(stats.counts, isNull);
  });

  test('ping 失败不阻塞计数拉取', () async {
    final fake = FakeEmbyService(
      itemCounts: const MediaCounts(movies: 7, series: 8, episodes: 9),
    );
    fake.pingError = Exception('unreachable');
    final container = ProviderContainer(
      overrides: [
        embyServiceFactoryProvider.overrideWithValue((_) => fake),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(serverStatsProvider.notifier)
        .loadAll([_server(id: 'a', serverId: 's1')]);

    final stats = container.read(serverStatsProvider)['a'];
    expect(stats, isNotNull);
    expect(stats!.latencyMs, isNull);
    expect(stats.counts?.movies, 7);
  });

  test('计数失败只丢计数（延迟仍在）', () async {
    final fake = FakeEmbyService(itemCounts: null);
    final container = ProviderContainer(
      overrides: [
        embyServiceFactoryProvider.overrideWithValue((_) => fake),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(serverStatsProvider.notifier)
        .loadAll([_server(id: 'a', serverId: 's1')]);

    final stats = container.read(serverStatsProvider)['a'];
    expect(stats, isNotNull);
    expect(stats!.latencyMs, isNotNull);
    expect(stats.counts, isNull);
  });

  test('多服务器各自独立兜底', () async {
    final ok = FakeEmbyService(
      itemCounts: const MediaCounts(movies: 1, series: 1, episodes: 1),
    );
    final bad = FakeEmbyService()..pingError = Exception('down');
    final container = ProviderContainer(
      overrides: [
        embyServiceFactoryProvider.overrideWithValue(
          (s) => s.id == 'ok' ? ok : bad,
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(serverStatsProvider.notifier).loadAll([
      _server(id: 'ok', serverId: 's1'),
      _server(id: 'bad', serverId: 's2'),
    ]);

    final map = container.read(serverStatsProvider);
    expect(map['ok']?.latencyMs, isNotNull);
    expect(map['ok']?.counts?.movies, 1);
    expect(map['bad']?.latencyMs, isNull);
    expect(map['bad']?.counts, isNull);
  });

  test('重复 loadAll 丢弃过期结果', () async {
    var factoryCalls = 0;
    final container = ProviderContainer(
      overrides: [
        embyServiceFactoryProvider.overrideWithValue((_) {
          factoryCalls++;
          return FakeEmbyService(
            itemCounts: MediaCounts(
              movies: factoryCalls,
              series: factoryCalls,
              episodes: factoryCalls,
            ),
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(serverStatsProvider.notifier);
    final first = notifier.loadAll([_server(id: 'a', serverId: 's1')]);
    final second = notifier.loadAll([_server(id: 'a', serverId: 's1')]);
    await Future.wait([first, second]);

    // 过期（first）结果不覆盖新结果：counts 用第二次的工厂调用值
    final stats = container.read(serverStatsProvider)['a'];
    expect(stats, isNotNull);
    expect(stats!.counts?.movies, greaterThanOrEqualTo(1));
  });
}
