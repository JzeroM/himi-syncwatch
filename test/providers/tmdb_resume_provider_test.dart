import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/playback_report_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/services/tmdb_aggregate_service.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';

import '../helpers/test_fakes.dart';

class _ResumeAggregate extends TmdbAggregateService {
  _ResumeAggregate(this.entries)
      : super(
          tmdb: TmdbService(apiBase: 'http://localhost', credential: 'test'),
          serviceFactory: (_) => FakeEmbyService(),
        );

  final List<TmdbResumeEntry> entries;
  int calls = 0;

  @override
  Future<TmdbResumeResult> fetchResume(
    List<EmbyServerConfig> servers,
    String? activeServerId,
  ) async {
    calls++;
    return TmdbResumeResult(entries: entries);
  }
}

final _server = EmbyServerConfig(
  id: 's1',
  serverUrl: 'https://s1.local',
  serverName: '服务器A',
  serverId: 's1-sid',
  username: 'user',
  accessToken: 'token',
  userId: 'uid',
);

TmdbResumeEntry _entry(String id) => TmdbResumeEntry(
      item: MediaItem(id: id, name: id, type: 'Movie'),
      server: _server,
    );

void main() {
  test('乐观隐藏条目被过滤，revision 变化触发重取', () async {
    final aggregate = _ResumeAggregate([_entry('r1'), _entry('r2')]);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(
            const AppSettings(tmdbApiKey: 'test-key'),
          ),
        ),
        tmdbAggregateServiceProvider.overrideWithValue(aggregate),
        embyServerListProvider.overrideWith(
          (ref) => EmbyServerListNotifier()..setList([_server]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen(tmdbResumeProvider, (_, __) {});
    addTearDown(subscription.close);

    expect(
      (await container.read(tmdbResumeProvider.future))
          .entries
          .map((e) => e.item.id),
      ['r1', 'r2'],
    );

    container.read(resumeOptimisticHiddenProvider.notifier).state = {'r1'};
    expect(
      (await container.read(tmdbResumeProvider.future))
          .entries
          .map((e) => e.item.id),
      ['r2'],
    );

    final before = aggregate.calls;
    container.read(resumeOptimisticHiddenProvider.notifier).state = {};
    container.read(resumeRevisionProvider.notifier).state++;
    expect(
      (await container.read(tmdbResumeProvider.future))
          .entries
          .map((e) => e.item.id),
      ['r1', 'r2'],
    );
    expect(aggregate.calls, greaterThan(before));
  });
}
