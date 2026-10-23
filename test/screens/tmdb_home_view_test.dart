import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/image_quality_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/tmdb_provider.dart';
import 'package:himi_syncwatch/screens/home/tmdb_home_view.dart';
import 'package:himi_syncwatch/services/image_size_probe.dart';
import 'package:himi_syncwatch/widgets/home_hero_carousel.dart';
import 'package:himi_syncwatch/widgets/tmdb_availability_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_platform_card.dart';
import 'package:himi_syncwatch/widgets/tmdb_poster_card.dart';
import 'package:himi_syncwatch/widgets/tv/tv_remote_shell.dart';

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

const _netflix = TmdbPlatform(
  providerId: 8,
  name: 'Netflix',
  logoAsset: 'assets/images/platforms/netflix.png',
);

class _FakeImageSizeProbe extends ImageSizeProbe {
  @override
  Future<ImageSize?> probe(String url, {String? accessToken}) async {
    return const ImageSize(3840, 2160);
  }
}

TmdbAvailability _entry(int id) => TmdbAvailability(
      tmdb: TmdbItem(
        id: id,
        type: TmdbMediaType.movie,
        title: '影片$id',
      ),
      item: MediaItem(
        id: '$id',
        name: '影片$id',
        type: 'Movie',
        backdropOriginalUrl: 'https://s1/backdrop/$id-original.jpg',
      ),
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
  TmdbPlatformAvailabilityState availability =
      const TmdbPlatformAvailabilityState(complete: true),
  TmdbDiscData discData = const TmdbDiscData.unconfigured(),
  List<Override> extraOverrides = const [],
  Size viewSize = const Size(800, 1200),
  bool remote = false,
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final page = MaterialApp(
    home: const Scaffold(body: TmdbHomeView()),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => FakeSettingsNotifier(settings),
        ),
        imageSizeProbeProvider.overrideWithValue(_FakeImageSizeProbe()),
        tmdbHomeProvider.overrideWith((ref) => Stream.value(data)),
        tmdbDiscProvider.overrideWith((ref) => Stream.value(discData)),
        tmdbPlatformShowcaseProvider.overrideWith((ref, platform) async {
          for (final showcase in showcases) {
            if (showcase.platform.providerId == platform.providerId) {
              return showcase;
            }
          }
          return TmdbPlatformShowcase(platform: platform);
        }),
        tmdbPlatformAvailabilityProvider.overrideWith(
          (ref, platform) => Stream.value(availability),
        ),
        ...extraOverrides,
      ],
      child: remote ? TvRemoteShell(child: page) : page,
    ),
  );
  await tester.pump();
  await tester.pump();
}

bool _focusWithin(Finder finder) {
  final elements = finder.evaluate();
  if (elements.isEmpty) return false;
  final top = elements.first;
  final context = FocusManager.instance.primaryFocus?.context;
  if (context is! Element) return false;
  var found = false;
  context.visitAncestorElements((element) {
    if (element == top) {
      found = true;
      return false;
    }
    return true;
  });
  return found || context == top;
}

void main() {
  testWidgets('栏目加载中先显示英雄骨架和平台栏，不显示空态', (tester) async {
    await _pump(
      tester,
      data: const TmdbHomeData(configured: true, sectionsLoading: true),
      settings: const AppSettings(homeCarousel: false),
    );

    expect(find.text('TMDB 暂无聚合内容\n请确认服务器媒体带 TMDB id，或换个观看区域'), findsNothing);
    expect(find.text('流媒体平台'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('首页聚合为空时保留平台栏并提示', (tester) async {
    await _pump(
      tester,
      data: const TmdbHomeData(configured: true),
      settings: const AppSettings(homeCarousel: false),
    );
    await tester.pump();

    expect(find.text('流媒体平台'), findsOneWidget);
    expect(
      find.textContaining('TMDB 暂无聚合内容'),
      findsOneWidget,
    );
  });

  testWidgets('首页聚合为空但光盘有内容时不显示空态提示', (tester) async {
    await _pump(
      tester,
      data: const TmdbHomeData(configured: true),
      settings: const AppSettings(homeCarousel: false, glassUi: false),
      discData: TmdbDiscData(
        configured: true,
        sections: [
          TmdbDiscSectionData(
            key: 'high_score_movies',
            title: '高分热门电影',
            items: [_entry(1)],
          ),
        ],
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('tmdbDiscoverDisc')),
      findsOneWidget,
    );
    expect(find.text('高分热门电影'), findsOneWidget);
    expect(find.textContaining('TMDB 暂无聚合内容'), findsNothing);
  });

  testWidgets('光盘栏位于本周趋势与热门电影之间且间距紧凑', (tester) async {
    await _pump(
      tester,
      viewSize: const Size(800, 2400),
      data: TmdbHomeData(
        configured: true,
        sections: [
          TmdbSectionData(
            key: 'trending_day',
            title: '今日趋势',
            items: [_entry(1)],
          ),
          TmdbSectionData(
            key: 'trending_week',
            title: '本周趋势',
            items: [_entry(2)],
          ),
          TmdbSectionData(
            key: 'popular_movies',
            title: '热门电影',
            items: [_entry(3)],
          ),
        ],
      ),
      settings: const AppSettings(homeCarousel: false, glassUi: false),
      discData: TmdbDiscData(
        configured: true,
        sections: [
          TmdbDiscSectionData(
            key: 'high_score_movies',
            title: '高分热门电影',
            items: [_entry(4)],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final week = tester.getRect(
      find.byKey(const ValueKey('tmdbSection_trending_week')),
    );
    final disc = tester.getRect(
      find.byKey(const ValueKey('tmdbDiscoverDisc')),
    );
    final panel = tester.getRect(
      find.byKey(const ValueKey('tmdbDiscPanel_high_score_movies')),
    );
    final popular = tester.getRect(
      find.byKey(const ValueKey('tmdbSection_popular_movies')),
    );

    expect(week.bottom, lessThan(disc.top));
    expect(disc.bottom, lessThan(popular.top));
    expect(disc.top - week.bottom, inInclusiveRange(6, 14));
    expect(popular.top - disc.bottom, inInclusiveRange(6, 14));
    expect(panel.top - week.bottom, inInclusiveRange(8, 20));
    expect(popular.top - panel.bottom, inInclusiveRange(8, 24));
  });

  testWidgets('TV：遥控器可遍历到光盘栏并左右切换', (tester) async {
    await _pump(
      tester,
      viewSize: const Size(800, 2200),
      remote: true,
      data: TmdbHomeData(
        configured: true,
        sections: [
          TmdbSectionData(
            key: 'trending_day',
            title: '今日趋势',
            items: [_entry(1)],
          ),
          TmdbSectionData(
            key: 'trending_week',
            title: '本周趋势',
            items: [_entry(2)],
          ),
          TmdbSectionData(
            key: 'popular_movies',
            title: '热门电影',
            items: [_entry(3)],
          ),
        ],
      ),
      settings: const AppSettings(
        tvMode: true,
        homeCarousel: false,
      ),
      discData: TmdbDiscData(
        configured: true,
        sections: [
          TmdbDiscSectionData(
            key: 'high_score_movies',
            title: '高分热门电影',
            items: [_entry(4)],
          ),
          TmdbDiscSectionData(
            key: 'classic_movies',
            title: '经典老片',
            items: [_entry(5)],
          ),
        ],
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final discFocus = find.byKey(const ValueKey('tmdbDiscFocus'));
    var guard = 0;
    while (!_focusWithin(discFocus) && guard < 30) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      guard++;
    }
    expect(
      _focusWithin(discFocus),
      isTrue,
      reason: '方向键应能从首页其他区域走到光盘栏',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      _focusWithin(discFocus),
      isTrue,
      reason: '光盘栏左右切换后焦点不应丢失',
    );
  });

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
    final poster = card.poster! as TmdbAvailabilityImage;
    expect(poster.posterSize, 'w154');
    expect(poster.showTmdbWhileLoading, isFalse);
  });

  testWidgets('首页轮播开启时最多取 6 个去重候选', (tester) async {
    await _pump(tester, data: _data(8), settings: const AppSettings());

    final carousel = tester.widget<HomeHeroCarousel>(
      find.byType(HomeHeroCarousel),
    );
    expect(carousel.items.length, 6);
    expect(carousel.imageBuilder, isNotNull);
    expect(
      carousel.items.every(
        (item) =>
            item.imageUrl!.contains('original') &&
            !item.imageUrl!.contains('image.tmdb.org'),
      ),
      isTrue,
      reason: 'TMDB 顶部轮播只使用服务器原图',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('关闭轮播时退回单英雄区', (tester) async {
    await _pump(
      tester,
      data: _data(2),
      settings: const AppSettings(homeCarousel: false),
    );
    expect(find.byType(HomeHeroCarousel), findsNothing);
    expect(find.byType(HomeHeroBackground), findsNothing);
    expect(find.text('查看详情'), findsOneWidget);
  });

  testWidgets('TV 模式不显示顶部大封面与查看详情', (tester) async {
    await _pump(
      tester,
      data: _data(8),
      settings: const AppSettings(tvMode: true),
    );

    expect(find.byType(HomeHeroCarousel), findsNothing);
    expect(find.byType(HomeHeroBackground), findsNothing);
    expect(find.text('查看详情'), findsNothing);
    expect(find.text('流媒体平台'), findsOneWidget);
  });

  testWidgets('TV 光盘栏位于继续观看与平台栏上方', (tester) async {
    final resume = TmdbResumeEntry(
      item: MediaItem(id: 'r1', name: '续播影片', type: 'Movie'),
      server: _server,
    );
    await _pump(
      tester,
      viewSize: const Size(800, 1600),
      data: _data(1),
      settings: const AppSettings(tvMode: true, homeCarousel: false),
      discData: TmdbDiscData(
        configured: true,
        sections: [
          TmdbDiscSectionData(
            key: 'high_score_movies',
            title: '高分热门电影',
            items: [_entry(2)],
          ),
        ],
      ),
      extraOverrides: [
        tmdbResumeProvider.overrideWith(
          (ref) async => TmdbResumeResult(entries: [resume]),
        ),
      ],
    );
    await tester.pumpAndSettle();

    final disc = tester.getRect(
      find.byKey(const ValueKey('tmdbDiscoverDisc')),
    );
    final resumeBar = tester.getRect(find.text('继续观看'));
    final platform = tester.getRect(
      find.byKey(const ValueKey('tmdbPlatform_8')),
    );

    expect(disc.top, lessThan(resumeBar.top));
    expect(resumeBar.top, lessThan(platform.top));
  });

  testWidgets('TV 空首页光盘栏仍在平台栏上方', (tester) async {
    await _pump(
      tester,
      viewSize: const Size(800, 1600),
      data: const TmdbHomeData(configured: true),
      settings: const AppSettings(tvMode: true, homeCarousel: false),
      discData: TmdbDiscData(
        configured: true,
        sections: [
          TmdbDiscSectionData(
            key: 'high_score_movies',
            title: '高分热门电影',
            items: [_entry(2)],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final disc = tester.getRect(
      find.byKey(const ValueKey('tmdbDiscoverDisc')),
    );
    final platform = tester.getRect(
      find.byKey(const ValueKey('tmdbPlatform_8')),
    );

    expect(disc.top, lessThan(platform.top));
  });

  testWidgets('TV 无续播时光盘栏仍在平台栏上方', (tester) async {
    await _pump(
      tester,
      viewSize: const Size(800, 1600),
      data: _data(1),
      settings: const AppSettings(tvMode: true, homeCarousel: false),
      discData: TmdbDiscData(
        configured: true,
        sections: [
          TmdbDiscSectionData(
            key: 'high_score_movies',
            title: '高分热门电影',
            items: [_entry(2)],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final disc = tester.getRect(
      find.byKey(const ValueKey('tmdbDiscoverDisc')),
    );
    final platform = tester.getRect(
      find.byKey(const ValueKey('tmdbPlatform_8')),
    );

    expect(disc.top, lessThan(platform.top));
  });

  testWidgets('TV 栏目加载中不显示英雄骨架', (tester) async {
    await _pump(
      tester,
      data: const TmdbHomeData(configured: true, sectionsLoading: true),
      settings: const AppSettings(tvMode: true),
    );

    expect(find.text('流媒体平台'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('平台栏按顺序展示本地 Logo 卡片', (tester) async {
    await _pump(
      tester,
      data: _data(1),
      settings: const AppSettings(homeCarousel: false),
    );

    final card = tester.widget<TmdbPlatformCard>(
      find.byKey(const ValueKey('tmdbPlatform_8')),
    );
    expect(card.showcase.platform.name, 'Netflix');
    expect(card.showcase.platform.logoAsset, endsWith('netflix.png'));

    final platformList = tester
        .widgetList<ListView>(find.byType(ListView))
        .firstWhere((list) => list.childrenDelegate.estimatedChildCount == 7);
    expect(platformList.scrollDirection, Axis.horizontal);
    expect(tmdbPlatforms[5].name, 'Prime Video');
  });

  testWidgets('平台栏反查未完成时只显示中性骨架，不加载 TMDB 图', (tester) async {
    await _pump(
      tester,
      data: _data(1),
      settings: const AppSettings(homeCarousel: false),
      showcases: const [
        TmdbPlatformShowcase(
          platform: _netflix,
          posters: [
            TmdbPlatformPoster(
              tmdb: TmdbItem(
                id: 11,
                type: TmdbMediaType.movie,
                title: 'Poster 11',
                posterPath: '/p11.jpg',
              ),
            ),
          ],
        ),
      ],
      availability: const TmdbPlatformAvailabilityState(complete: false),
    );
    await tester.pump();

    final card = tester.widget<TmdbPlatformCard>(
      find.byKey(const ValueKey('tmdbPlatform_8')),
    );
    expect(card.serverLookupComplete, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tmdbPlatform_8')),
        matching: find.byType(TmdbImage),
      ),
      findsNothing,
    );
  });

  testWidgets('继续观看长按菜单按来源服务器移除历史', (tester) async {
    final current = FakeEmbyService();
    final source = FakeEmbyService();
    final sourceServer = EmbyServerConfig(
      id: 's2',
      serverUrl: 'https://s2',
      serverName: '服务器B',
      serverId: 'srv-s2',
      username: 'user',
      accessToken: 'token2',
      userId: 'u2',
    );
    final servers = EmbyServerListNotifier()..setList([_server, sourceServer]);
    final config = EmbyConfigNotifier()..setConfig(_server);
    await _pump(
      tester,
      data: _data(0),
      settings: const AppSettings(homeCarousel: false),
      extraOverrides: [
        tmdbResumeProvider.overrideWith(
          (ref) async => TmdbResumeResult(entries: [
            TmdbResumeEntry(
              item: MediaItem(id: 'r1', name: '续播影片', type: 'Movie'),
              server: sourceServer,
            ),
          ]),
        ),
        embyServerListProvider.overrideWith((ref) => servers),
        embyConfigProvider.overrideWith((ref) => config),
        embyServiceFactoryProvider.overrideWithValue(
          (server) => server.id == sourceServer.id ? source : current,
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const ValueKey('tmdbResume_s2_r1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('移除历史'), findsOneWidget);

    await tester.tap(find.text('移除历史'));
    await tester.pumpAndSettle();

    expect(current.removedResumeCalls, isEmpty);
    expect(source.removedResumeCalls, ['r1']);
  });

  testWidgets('平台栏展示两张海报与图片基地址', (tester) async {
    await _pump(
      tester,
      data: _data(1),
      settings: const AppSettings(homeCarousel: false),
      showcases: const [
        TmdbPlatformShowcase(
          platform: _netflix,
          posters: [
            TmdbPlatformPoster(
              tmdb: TmdbItem(
                id: 11,
                type: TmdbMediaType.movie,
                title: 'Poster 11',
                posterPath: '/p11.jpg',
              ),
            ),
            TmdbPlatformPoster(
              tmdb: TmdbItem(
                id: 12,
                type: TmdbMediaType.tv,
                title: 'Poster 12',
                posterPath: '/p12.jpg',
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();

    final card = tester.widget<TmdbPlatformCard>(
      find.byKey(const ValueKey('tmdbPlatform_8')),
    );
    expect(card.showcase.posters, hasLength(2));
    expect(card.imageBase, contains('image.tmdb.org'));
  });
}
