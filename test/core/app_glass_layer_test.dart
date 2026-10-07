import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/core/app.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import '../helpers/test_fakes.dart';

/// iOS premium（Impeller）grouped 玻璃需要祖先 LiquidGlassLayer 提供背景采样，
/// 否则全部退化为不透明纯灰。验证 [HimiSyncApp] 在 iOS 挂载
/// [lg.AdaptiveLiquidGlassLayer]（LiquidGlassLayer + 背景 BackdropGroup 根层），
/// 其余平台保持既有路径不挂载（Android 标准路径不需要）。
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

  testWidgets('iOS：挂载 AdaptiveLiquidGlassLayer（premium 根渲染层）',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpApp(tester);
      expect(find.byType(lg.AdaptiveLiquidGlassLayer), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android：不挂载（标准路径无需共享层，避免改动既有观感）',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpApp(tester);
      expect(find.byType(lg.AdaptiveLiquidGlassLayer), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
