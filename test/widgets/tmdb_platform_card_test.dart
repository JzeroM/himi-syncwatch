import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_platform_card.dart';

import '../helpers/test_fakes.dart';

const _platform = TmdbPlatform(providerId: 8, name: 'Netflix');

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
  testWidgets('平台卡用模糊 Logo 铺满背景，前景 Logo 完整不变形', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          platform: _platform,
          imageBase: 'https://image.example/t/p',
          logoPath: '/netflix.png',
          onTap: () => tapped = true,
          width: 150,
          height: 84,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GlassContainer), findsOneWidget);
    expect(find.byType(TmdbImage), findsNWidgets(2));
    expect(find.byType(ImageFiltered), findsOneWidget);

    final backdrop = tester.widget<TmdbImage>(
      find.byKey(const ValueKey('tmdbPlatformBackdrop_8')),
    );
    expect(backdrop.url, 'https://image.example/t/p/w300/netflix.png');
    expect(backdrop.fit, BoxFit.cover);

    final logo = tester.widget<TmdbImage>(
      find.byKey(const ValueKey('tmdbPlatformLogo_8')),
    );
    expect(logo.url, 'https://image.example/t/p/w300/netflix.png');
    expect(logo.fit, BoxFit.contain);

    await tester.tap(find.byType(TmdbPlatformCard));
    expect(tapped, isTrue);
  });

  testWidgets('无 Logo 时显示平台名称', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          platform: _platform,
          imageBase: 'https://image.example/t/p',
          logoPath: null,
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Netflix'), findsOneWidget);
    expect(find.byType(TmdbImage), findsNothing);
  });
}
