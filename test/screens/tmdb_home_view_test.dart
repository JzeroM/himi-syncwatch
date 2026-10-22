import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/screens/home/tmdb_home_view.dart';
import 'package:himi_syncwatch/widgets/home_hero_carousel.dart';
import 'package:himi_syncwatch/widgets/tmdb_availability_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_platform_card.dart';
import 'package:himi_syncwatch/widgets/tmdb_poster_card.dart';

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

TmdbAvailability _entry(int id) => TmdbAvailability(
      tmdb: TmdbItem(
        id: id,
        type: TmdbMediaType.movie,
        title: '影片$id',
      ),
      item: MediaItem(id: '$id', name: '影片$id', type: 'Movie'),
      server: _server,
    );

TmdbHomeData _data(int count) => TmdbHomeData(
      configured: true,
      sections: [
        TmdbSectionData(
          key: 'trending_day',
          title: '今日趋势',
          items: [for (var i = 1; i <= count; i++) _entry(i)],
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required TmdbHomeData data,
  required AppSettings settings,
  List<TmdbPlatformShowcase> showcases = const [],
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(settings),
        ),
        tmdbHomeProvider.overrideWith((ref) async => data),
        tmdbPlatformShowcasesProvider.overrideWith((ref) async => showcases),
      ],
      child: const MaterialApp(
        home: Scaffold(body: TmdbHomeView()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('栏目行不显示服务器角标', (tester) async {
    await _pump(
      tester,
      data: _data(1),
      settings: const AppSettings(homeCarousel: false),
    );

    expect(find.text('今日趋势'), findsOneWidget);
    expect(find.text('服务器A'), findsNothing);
    final card = tester.widget<TmdbPosterCard>(
      find.byType(TmdbPosterCard).first,
    );
    expect(card.poster, isA<TmdbAvailabilityImage>());
  });

  testWidgets('首页轮播开启时最多取 6 个去重候选', (tester) async {
    await _pump(tester, data: _data(8), settings: const AppSettings());

    final carousel = tester.widget<HomeHeroCarousel>(
      find.byType(HomeHeroCarousel),
    );
    expect(carousel.items.length, 6);
    expect(carousel.imageBuilder, isNotNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('关闭轮播或 TV 模式时退回单英雄区', (tester) async {
    await _pump(
      tester,
      data: _data(2),
      settings: const AppSettings(homeCarousel: false),
    );
    expect(find.byType(HomeHeroCarousel), findsNothing);
    expect(find.byType(HomeHeroBackground), findsNothing);

    await _pump(
      tester,
      data: _data(2),
      settings: const AppSettings(tvMode: true),
    );
    expect(find.byType(HomeHeroCarousel), findsNothing);
  });

  testWidgets('平台栏使用服务器海报卡片', (tester) async {
    final entry = _entry(1);
    await _pump(
      tester,
      data: _data(1),
      settings: const AppSettings(homeCarousel: false),
      showcases: [
        TmdbPlatformShowcase(
          platform: const TmdbPlatform(providerId: 8, name: 'Netflix'),
          logoPath: '/netflix.png',
          highlight: entry.tmdb,
          local: entry,
        ),
      ],
    );
    await tester.pump();

    final card = tester.widget<TmdbPlatformCard>(
      find.byKey(const ValueKey('tmdbPlatform_8')),
    );
    expect(card.showcase.local?.item.id, '1');
  });
}
