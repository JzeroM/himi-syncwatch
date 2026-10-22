import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_platform_card.dart';

import '../helpers/test_fakes.dart';

const _platform = TmdbPlatform(providerId: 8, name: 'Netflix');

final _server = EmbyServerConfig(
  id: 's1',
  serverUrl: 'https://s1',
  serverName: '服务器A',
  serverId: 'srv-s1',
  username: 'user',
  accessToken: 'token-a',
  userId: 'u1',
);

final _tmdbItem = TmdbItem(
  id: 101,
  type: TmdbMediaType.tv,
  title: '剧集',
  posterPath: '/poster.jpg',
);

TmdbAvailability _local({String? posterUrl}) => TmdbAvailability(
      tmdb: _tmdbItem,
      item: MediaItem(
        id: 'local-1',
        name: '剧集',
        type: 'Series',
        posterUrl: posterUrl,
      ),
      server: _server,
    );

Widget _host(Widget child) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        (ref) => FakeSettingsNotifier(const AppSettings()),
      ),
      embyConfigProvider.overrideWith((ref) => EmbyConfigNotifier()),
    ],
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  testWidgets('平台卡展示服务器海报与右侧 Logo', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          showcase: TmdbPlatformShowcase(
            platform: _platform,
            logoPath: '/netflix.png',
            highlight: _tmdbItem,
            local: _local(posterUrl: 'https://s1/Items/local-1/Images/Primary'),
          ),
          imageBase: 'https://image.example/t/p',
          onTap: () => tapped = true,
          width: 170,
          height: 84,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GlassContainer), findsOneWidget);
    final poster = tester.widget<EmbyImage>(find.byType(EmbyImage));
    expect(poster.url, 'https://s1/Items/local-1/Images/Primary');
    expect(poster.accessToken, 'token-a');

    final logo = tester.widget<TmdbImage>(
      find.descendant(
        of: find.byKey(const ValueKey('tmdbPlatformLogo_8')),
        matching: find.byType(TmdbImage),
      ),
    );
    expect(logo.url, 'https://image.example/t/p/w300/netflix.png');
    expect(logo.fit, BoxFit.contain);

    await tester.tap(find.byType(TmdbPlatformCard));
    expect(tapped, isTrue);
  });

  testWidgets('服务器海报缺失时回退 TMDB 海报', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          showcase: TmdbPlatformShowcase(
            platform: _platform,
            logoPath: '/netflix.png',
            highlight: _tmdbItem,
            local: _local(),
          ),
          imageBase: 'https://image.example/t/p',
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(EmbyImage), findsNothing);
    final images = tester.widgetList<TmdbImage>(find.byType(TmdbImage));
    expect(images.any((e) => e.url?.endsWith('/poster.jpg') == true), isTrue);
  });

  testWidgets('无 Logo 时显示平台名称', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          showcase: const TmdbPlatformShowcase(platform: _platform),
          imageBase: 'https://image.example/t/p',
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Netflix'), findsOneWidget);
    expect(find.byType(TmdbImage), findsNothing);
  });
}
