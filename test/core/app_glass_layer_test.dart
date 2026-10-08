import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  testWidgets('[PATCH himi] B5：builder 注入 GlassAccessibilityScope 关闭 reduceTransparency', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpApp(tester);
      final scope = tester.widget<lg.GlassAccessibilityScope>(
        find.byType(lg.GlassAccessibilityScope),
      );
      expect(
        scope.reduceTransparency,
        isFalse,
        reason: '包默认把 highContrast（iOS 增强对比度）误当「减弱透明度」'
            '→ AdaptiveGlass 退化 40% 实心白板（iOS blur=0 连模糊都没有）',
      );
      expect(
        scope.reduceMotion,
        isNull,
        reason: 'reduceMotion 不显式覆盖，仍随系统（减弱动效要保留）',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('显式 scope 优先级最高：highContrast=true 也不触发 reduceTransparency', (
    tester,
  ) async {
    late lg.GlassAccessibilityData data;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          highContrast: true,
          disableAnimations: false,
        ),
        child: lg.GlassAccessibilityScope(
          reduceTransparency: false,
          child: Builder(
            builder: (context) {
              data = lg.GlassAccessibilityData.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(data.reduceTransparency, isFalse,
        reason: '显式 scope（优先级 1）压过 MediaQuery.highContrast（优先级 2）');
    expect(data.reduceMotion, isFalse, reason: 'reduceMotion 仍来自系统信号');
  });
}
