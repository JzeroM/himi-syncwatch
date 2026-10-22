import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/tmdb_platform.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/widgets/emby_image.dart';
import 'package:himi_syncwatch/widgets/glass/glass_container.dart';
import 'package:himi_syncwatch/widgets/tmdb_image.dart';
import 'package:himi_syncwatch/widgets/tmdb_platform_card.dart';

import '../helpers/test_fakes.dart';

const _platform = TmdbPlatform(
  providerId: 8,
  name: 'Netflix',
  logoAsset: 'assets/images/platforms/netflix.png',
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
  testWidgets('平台卡只显示居中的本地 Logo', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          platform: _platform,
          onTap: () => tapped = true,
          width: 170,
          height: 84,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GlassContainer), findsOneWidget);
    expect(find.byType(EmbyImage), findsNothing);
    expect(find.byType(TmdbImage), findsNothing);

    final card = find.byType(TmdbPlatformCard);
    final logo = find.byKey(const ValueKey('tmdbPlatformLogo_8'));
    final image = tester.widget<Image>(logo);
    expect((image.image as AssetImage).assetName, _platform.logoAsset);
    expect(image.fit, BoxFit.contain);
    expect(tester.getCenter(logo).dx, closeTo(tester.getCenter(card).dx, 0.5));
    expect(tester.getCenter(logo).dy, closeTo(tester.getCenter(card).dy, 0.5));

    await tester.tap(card);
    expect(tapped, isTrue);
  });

  testWidgets('本地 Logo 加载失败时回退平台名称', (tester) async {
    await tester.pumpWidget(
      _host(
        TmdbPlatformCard(
          platform: const TmdbPlatform(
            providerId: 999,
            name: '未知平台',
            logoAsset: 'assets/images/platforms/missing.png',
          ),
          onTap: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未知平台'), findsOneWidget);
  });
}
