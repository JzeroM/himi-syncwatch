import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
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
}
