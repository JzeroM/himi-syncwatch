import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/providers/trakt_provider.dart';
import 'package:himi_syncwatch/screens/settings/trakt_settings_screen.dart';
import 'package:himi_syncwatch/services/trakt/trakt_auth_service.dart';
import 'package:himi_syncwatch/services/trakt/trakt_config.dart';
import 'package:himi_syncwatch/services/trakt/trakt_token_store.dart';

import '../helpers/fake_secure_storage.dart';
import '../helpers/test_fakes.dart';

Widget _app(AppSettings settings) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
      traktAuthServiceProvider.overrideWithValue(
        TraktAuthService(
          config: const TraktConfig(clientId: 'test-client'),
          store: TraktTokenStore(storage: FakeSecureStorage()),
        ),
      ),
    ],
    child: const MaterialApp(home: TraktSettingsScreen()),
  );
}

void main() {
  testWidgets('TV 模式显示扫码配置入口', (tester) async {
    await tester.pumpWidget(_app(const AppSettings(tvMode: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('traktQrLogin')), findsOneWidget);
    expect(find.byKey(const ValueKey('traktBrowserLogin')), findsNothing);
  });

  testWidgets('非 TV 模式不显示扫码配置入口', (tester) async {
    await tester.pumpWidget(_app(const AppSettings(tvMode: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('traktQrLogin')), findsNothing);
  });
}
