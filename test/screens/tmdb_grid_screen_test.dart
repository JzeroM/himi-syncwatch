import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/screens/tmdb/tmdb_grid_screen.dart';
import 'package:himi_syncwatch/services/tmdb_aggregate_service.dart';
import 'package:himi_syncwatch/services/tmdb_service.dart';

import '../helpers/test_fakes.dart';

final _server = EmbyServerConfig(
  id: 's1',
  serverUrl: 'https://s1',
  serverName: '服务器A',
  serverId: 'srv-s1',
  username: 'user',
  accessToken: 'token',
  userId: 'u1',
);

class _FakeAggregate extends TmdbAggregateService {
  _FakeAggregate(this.entries)
      : super(
          tmdb: TmdbService(
            apiBase: 'https://example.invalid/3',
            credential: 'token',
          ),
          serviceFactory: (_) => throw UnimplementedError(),
        );

  final List<TmdbAvailability> entries;

  @override
  Future<TmdbSectionPage> fetchSectionPage(
    String sectionKey,
    List<EmbyServerConfig> servers, {
    String? activeServerId,
    int page = 1,
  }) async {
    return TmdbSectionPage(
      items: page == 1 ? entries : const [],
      hasMore: false,
    );
  }

  @override
  Future<TmdbAvailabilityResult> fetchSection(
    String sectionKey,
    List<EmbyServerConfig> servers, {
    String? activeServerId,
    int pages = 5,
    bool allowCache = true,
  }) async {
    return TmdbAvailabilityResult(items: entries);
  }
}

class _PagedFakeAggregate extends TmdbAggregateService {
  _PagedFakeAggregate(this.pages)
      : super(
          tmdb: TmdbService(
            apiBase: 'https://example.invalid/3',
            credential: 'token',
          ),
          serviceFactory: (_) => throw UnimplementedError(),
        );

  final Map<int, List<TmdbAvailability>> pages;
  final List<int> requestedPages = [];

  @override
  Future<TmdbSectionPage> fetchSectionPage(
    String sectionKey,
    List<EmbyServerConfig> servers, {
    String? activeServerId,
    int page = 1,
  }) async {
    requestedPages.add(page);
    return TmdbSectionPage(
      items: pages[page] ?? const [],
      hasMore: pages.containsKey(page + 1),
    );
  }
}

List<TmdbAvailability> _entries(int count) => [
      for (var i = 1; i <= count; i++)
        TmdbAvailability(
          tmdb: TmdbItem(
            id: i,
            type: TmdbMediaType.movie,
            title: '影片$i',
          ),
          item: MediaItem(id: '$i', name: '影片$i', type: 'Movie'),
          server: _server,
        ),
    ];

void main() {
  testWidgets('TMDB 网格跟随分类页每行海报数，并保留服务器角标', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(
              const AppSettings(categoryColumns: 6),
            ),
          ),
          tmdbAggregateServiceProvider.overrideWithValue(
            _FakeAggregate(_entries(12)),
          ),
        ],
        child: const MaterialApp(
          home: TmdbGridScreen(sectionKey: 'trending_day'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 6);
    expect(find.byKey(const ValueKey('tmdbGrid_s1_1')), findsOneWidget);
    expect(find.text('服务器A'), findsWidgets);
  });

  testWidgets('栏目全部页首屏一页并自动加载下一页', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final aggregate = _PagedFakeAggregate({
      1: _entries(1),
      2: [
        TmdbAvailability(
          tmdb: const TmdbItem(
            id: 2,
            type: TmdbMediaType.movie,
            title: '影片2',
          ),
          item: MediaItem(id: '2', name: '影片2', type: 'Movie'),
          server: _server,
        ),
      ],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings()),
          ),
          tmdbAggregateServiceProvider.overrideWithValue(aggregate),
        ],
        child: const MaterialApp(
          home: TmdbGridScreen(sectionKey: 'trending_day'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(aggregate.requestedPages, [1, 2]);
    expect(find.byKey(const ValueKey('tmdbGrid_s1_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tmdbGrid_s1_2')), findsOneWidget);
  });
}
