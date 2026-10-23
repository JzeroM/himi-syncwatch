import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tmdb_availability_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_platform_card.dart';

import '../helpers/test_fakes.dart';

const _platform = TmdbPlatform(
  providerId: 8,
  name: 'Netflix',
  logoAsset: 'assets/images/platforms/netflix.png',
);

const _poster0 = TmdbPlatformPoster(
  tmdb: TmdbItem(
    id: 101,
    type: TmdbMediaType.movie,
    title: 'Poster 101',
    posterPath: '/poster101.jpg',
  ),
);

const _poster1 = TmdbPlatformPoster(
  tmdb: TmdbItem(
    id: 102,
    type: TmdbMediaType.tv,
    title: 'Poster 102',
    posterPath: '/poster102.jpg',
  ),
);

Widget _host(Widget child) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        (ref) => FakeSettingsNotifier(const AppSettings()),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  testWidgets('平台卡展示两张错层海报和右侧小 Logo', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          showcase: const TmdbPlatformShowcase(
            platform: _platform,
            posters: [_poster0, _poster1],
          ),
          imageBase: 'https://image.example',
          onTap: () => tapped = true,
          width: 170,
          height: 84,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GlassContainer), findsOneWidget);
    expect(find.byType(TmdbImage), findsNWidgets(2));

    final front = find.byKey(const ValueKey('tmdbPlatformPoster_8_0'));
    final back = find.byKey(const ValueKey('tmdbPlatformPoster_8_1'));
    final logo = find.byKey(const ValueKey('tmdbPlatformLogo_8'));
    expect(front, findsOneWidget);
    expect(back, findsOneWidget);
    expect(logo, findsOneWidget);

    final frontCenter = tester.getCenter(front);
    final backCenter = tester.getCenter(back);
    expect(backCenter.dx, greaterThan(frontCenter.dx), reason: '后景海报在右侧');
    expect(frontCenter.dy, greaterThan(backCenter.dy), reason: '前景海报在下方');
    expect(tester.getCenter(logo).dx, greaterThan(backCenter.dx));

    final image = tester.widget<Image>(logo);
    expect((image.image as AssetImage).assetName, _platform.logoAsset);
    expect(image.fit, BoxFit.contain);
    expect(image.height, 20);

    await tester.tap(find.byType(TmdbPlatformCard));
    expect(tapped, isTrue);
  });

  testWidgets('只有一张海报时只展示一张', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          showcase: const TmdbPlatformShowcase(
            platform: _platform,
            posters: [_poster0],
          ),
          imageBase: 'https://image.example',
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const ValueKey('tmdbPlatformPoster_8_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('tmdbPlatformPoster_8_1')), findsNothing);
    expect(find.byType(TmdbImage), findsOneWidget);
  });

  testWidgets('没有海报时展示两张灰色占位', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          showcase: const TmdbPlatformShowcase(platform: _platform),
          imageBase: 'https://image.example',
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    expect(
        find.byKey(const ValueKey('tmdbPlatformPoster_8_0')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('tmdbPlatformPoster_8_1')), findsOneWidget);
    expect(find.byType(TmdbImage), findsNothing);
    expect(find.byIcon(Icons.movie_outlined), findsNWidgets(2));
  });

  testWidgets('有服务器实图时直接使用服务器图，不预加载 TMDB', (tester) async {
    final item = TmdbItem(
      id: 201,
      type: TmdbMediaType.movie,
      title: 'Poster 201',
      posterPath: '/poster201.jpg',
    );
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          showcase: TmdbPlatformShowcase(
            platform: _platform,
            posters: [
              TmdbPlatformPoster(
                tmdb: item,
                availability: TmdbAvailability(
                  tmdb: item,
                  item: MediaItem(
                    id: 'local-201',
                    name: 'Poster 201',
                    type: 'Movie',
                    posterUrl:
                        'https://s1/Items/local-201/Images/Primary?maxHeight=400',
                  ),
                  server: EmbyServerConfig(
                    id: 's1',
                    serverUrl: 'https://s1',
                    serverName: '服务器A',
                    serverId: 'srv-s1',
                    username: 'user',
                    accessToken: 'token',
                    userId: 'u1',
                  ),
                ),
              ),
            ],
          ),
          imageBase: 'https://image.example',
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<TmdbAvailabilityImage>(
      find.byType(TmdbAvailabilityImage),
    );
    expect(image.posterSize, 'w154');
    expect(image.serverMaxHeight, 240);
    expect(image.showTmdbWhileLoading, isFalse);
    expect(find.byType(TmdbImage), findsNothing);
  });

  testWidgets('服务器反查未完成时使用中性骨架，不加载 TMDB', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          showcase: const TmdbPlatformShowcase(
            platform: _platform,
            posters: [_poster0, _poster1],
          ),
          imageBase: 'https://image.example',
          onTap: () {},
          serverLookupComplete: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('tmdbPlatformPoster_8_0')),
      findsOneWidget,
    );
    expect(find.byType(TmdbImage), findsNothing);
    expect(find.byType(TmdbAvailabilityImage), findsNothing);
  });

  testWidgets('本地 Logo 加载失败时回退平台名称', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          showcase: const TmdbPlatformShowcase(
            platform: TmdbPlatform(
              providerId: 999,
              name: '未知平台',
              logoAsset: 'assets/images/platforms/missing.png',
            ),
          ),
          imageBase: 'https://image.example',
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未知平台'), findsOneWidget);
  });
}
