import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/models/tmdb_item.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_availability_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';

final _server = EmbyServerConfig(
  id: 's1',
  serverUrl: 'https://s1',
  serverName: '服务器A',
  serverId: 'srv-s1',
  username: 'user',
  accessToken: 'token-a',
  userId: 'u1',
);

final _tmdb = TmdbItem(
  id: 101,
  type: TmdbMediaType.movie,
  title: '影片',
  posterPath: '/tmdb-poster.jpg',
  backdropPath: '/tmdb-backdrop.jpg',
);

TmdbAvailability _entry({String? posterUrl, String? backdropUrl}) =>
    TmdbAvailability(
      tmdb: _tmdb,
      item: MediaItem(
        id: 'local',
        name: '影片',
        type: 'Movie',
        posterUrl: posterUrl,
        backdropWideUrl: backdropUrl,
      ),
      server: _server,
    );

Widget _host(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 100, height: 150, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('优先服务器海报并使用来源服务器 Token', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbAvailabilityImage(
          entry: _entry(posterUrl: 'https://s1/Items/local/Images/Primary'),
          imageBase: 'https://image.example/t/p',
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<EmbyImage>(find.byType(EmbyImage));
    expect(image.url, 'https://s1/Items/local/Images/Primary');
    expect(image.accessToken, 'token-a');
    expect(image.errorWidget, isA<TmdbImage>());
  });

  testWidgets('服务器海报缺失时直接使用 TMDB 海报', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbAvailabilityImage(
          entry: _entry(),
          imageBase: 'https://image.example/t/p',
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(EmbyImage), findsNothing);
    final image = tester.widget<TmdbImage>(find.byType(TmdbImage));
    expect(image.url, 'https://image.example/t/p/w500/tmdb-poster.jpg');
  });

  testWidgets('背景优先服务器宽幅背景', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbAvailabilityImage(
          entry: _entry(backdropUrl: 'https://s1/Items/local/Images/Backdrop'),
          imageBase: 'https://image.example/t/p',
          backdrop: true,
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<EmbyImage>(find.byType(EmbyImage));
    expect(image.url, 'https://s1/Items/local/Images/Backdrop');
  });
}
