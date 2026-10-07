import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/app.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import '../helpers/test_fakes.dart';

/// 全平台统一 standard 玻璃路径（自带 RepaintBoundary 捕获），不再挂载
/// iOS premium 专用根层 [lg.AdaptiveLiquidGlassLayer]。
void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            (ref) => FakeSettingsNotifier(const AppSettings()),
          ),
          embyAuthServiceProvider.overrideWith((ref) => FakeEmbyAuthService()),
          embyServiceProvider.overrideWith((ref) => FakeEmbyService()),
        ],
        child: const HimiSyncApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('iOS：不挂载 premium 根层 AdaptiveLiquidGlassLayer',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpApp(tester);
      expect(find.byType(lg.AdaptiveLiquidGlassLayer), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android：不挂载（标准路径无需共享层）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpApp(tester);
      expect(find.byType(lg.AdaptiveLiquidGlassLayer), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
