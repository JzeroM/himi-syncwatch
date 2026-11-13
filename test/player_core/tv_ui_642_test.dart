import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/top_bar_clock_format.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_clock.dart';
import 'package:himi_syncwatch/screens/player/widgets/player_top_bar.dart';

import '../helpers/test_fakes.dart';

/// 642：TV 模式专属 UI 收敛。
///
/// 三条需求：
/// 1. **TV 模式开关只在安卓显示**（Windows/鸿蒙/iOS 无遥控）。
/// 2. **安卓 TV 播放页去掉左上角返回按钮**（手机保留）。
/// 3. **TV 顶栏时钟移到左侧留白、网速移到原时钟位置（最右）**。
void main() {
  group('① TV 模式开关只在安卓（642）', () {
    test('通用设置页用 showTvModeSwitch（内部 Platform.isAndroid）', () {
      final src =
          File('lib/screens/settings/general_settings_screen.dart')
              .readAsStringSync();
      // 旧实现：if (!Platform.isWindows) → 鸿蒙/iOS 仍显示开关。
      expect(src, contains('if (showTvModeSwitch())'));
      expect(src, contains('debugPlatformIsAndroidOverride ?? Platform.isAndroid'));
      expect(
        src,
        isNot(contains('if (!Platform.isWindows)')),
        reason: '鸿蒙/iOS 无遥控，不应显示 TV 模式开关',
      );
    });

    test('applyTvAutoDetection 对非安卓强制关闭并标记 userSet', () {
      final src =
          File('lib/providers/settings_provider.dart').readAsStringSync();
      expect(src, contains('platformSupportsTv'));
      expect(src, contains('TargetPlatform.android'));
      // 非安卓一律强制关（原实现只判 windows）。
      expect(
        src,
        isNot(contains('defaultTargetPlatform == TargetPlatform.windows &&')),
        reason: 'TV 模式只有安卓有，不应只特判 Windows',
      );
    });

    test('非安卓平台：遗留 tvMode=true 被强制关闭并标记 userSet', () async {
      // flutter test 默认平台是 android，需显式覆盖才能验证非安卓分支。
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final notifier = FakeSettingsNotifier(
          const AppSettings(tvMode: true, tvModeUserSet: false),
        );
        await notifier.applyTvAutoDetection(isTelevision: false);

        expect(notifier.state.tvMode, isFalse, reason: '$platform 应强制关闭');
        expect(notifier.state.tvModeUserSet, isTrue,
            reason: '$platform 需标记 userSet，防止再次被自动打开');
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test('非安卓平台：isTelevision=true 也无法重新打开 tvMode', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final notifier = FakeSettingsNotifier(
        const AppSettings(tvMode: true, tvModeUserSet: false),
      );
      await notifier.applyTvAutoDetection(isTelevision: true);

      expect(notifier.state.tvMode, isFalse);
      expect(notifier.state.tvModeUserSet, isTrue);
    });

    test('安卓平台：tvMode=true 保持开启（不误伤）', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final notifier = FakeSettingsNotifier(
        const AppSettings(tvMode: true, tvModeUserSet: true),
      );
      await notifier.applyTvAutoDetection(isTelevision: true);

      expect(notifier.state.tvMode, isTrue);
    });
  });

  group('② 返回按钮：TV 隐藏、手机保留（642）', () {
    test('showTopBarBackButton：TV=false / 非 TV=true', () {
      expect(PlayerScreen.showTopBarBackButton(tvMode: true), isFalse);
      expect(PlayerScreen.showTopBarBackButton(tvMode: false), isTrue);
    });

    test('showTopBarNetworkSpeed：TV=false / 非 TV=true', () {
      // TV 的网速移到最右（独立定位层），顶栏 Row 内不再渲染。
      expect(PlayerScreen.showTopBarNetworkSpeed(tvMode: true), isFalse);
      expect(PlayerScreen.showTopBarNetworkSpeed(tvMode: false), isTrue);
    });

    testWidgets('showBack: false → 顶栏无返回按钮', (tester) async {
      await tester.pumpWidget(_host(_bar(showBack: false)));
      expect(find.byKey(const ValueKey('playerBackButton')), findsNothing);
    });

    testWidgets('showBack: true → 顶栏有返回按钮', (tester) async {
      await tester.pumpWidget(_host(_bar(showBack: true)));
      expect(find.byKey(const ValueKey('playerBackButton')), findsOneWidget);
    });

    testWidgets('showNetworkSpeed: false → 顶栏内不渲染网速', (tester) async {
      await tester.pumpWidget(_host(_bar(
        networkSpeedText: '4.89 MB/s',
        showNetworkSpeed: false,
      )));
      expect(find.byKey(const ValueKey('playerNetworkSpeed')), findsNothing);
    });

    testWidgets('showNetworkSpeed: true → 顶栏内渲染网速', (tester) async {
      await tester.pumpWidget(_host(_bar(
        networkSpeedText: '4.89 MB/s',
        showNetworkSpeed: true,
      )));
      expect(find.byKey(const ValueKey('playerNetworkSpeed')), findsOneWidget);
    });

    test('Kotlin applyLayoutMode 按 tv 隐藏返回按钮', () {
      final src = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'NativePlayerScreenView.kt',
      ).readAsStringSync();
      expect(src, contains('backButton.visibility = if (tv) GONE else VISIBLE'));
    });

    test('Kotlin applyFocusability 在 TV 时排除返回按钮', () {
      final src = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'NativePlayerScreenView.kt',
      ).readAsStringSync();
      final start = src.indexOf('private fun applyFocusability()');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 700);
      expect(body, contains('if (tv) null else backButton'));
    });

    test('鸿蒙原生顶栏 TV 时隐藏返回', () {
      final src = File(
        'plugins/himi_mpv_ohos/ohos/src/main/ets/components/native/'
        'HimiNativePlayerView.ets',
      ).readAsStringSync();
      expect(src, contains('if (!this.state().tvMode) {'));
      expect(src, contains('this.backGlyph()'));
    });
  });

  group('③ TV 顶栏：时钟左移 / 网速最右（642）', () {
    testWidgets('时钟层 onLeft=true → 左贴边', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: Stack(
                children: [
                  PlayerClockLayer(
                    format: TopBarClockFormat.twentyFourHour,
                    tvMode: true,
                    now: () => DateTime(2026, 1, 1, 14, 5),
                    autoTick: false,
                    onLeft: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(const ValueKey('playerClock')));
      // 容器 left:12 + width 100 + Align.centerLeft → 文字左缘贴近 12。
      expect(rect.left, closeTo(12, 0.5));
    });

    testWidgets('时钟层 onLeft=false → 仍右贴边（手机不变）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: Stack(
                children: [
                  PlayerClockLayer(
                    format: TopBarClockFormat.twentyFourHour,
                    tvMode: true,
                    now: () => DateTime(2026, 1, 1, 14, 5),
                    autoTick: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(const ValueKey('playerClock')));
      expect(rect.right, closeTo(788, 0.5));
    });

    test('player_screen 传 onLeft: true 给时钟层', () {
      final src = File('lib/screens/player/player_screen.dart').readAsStringSync();
      final start = src.indexOf('PlayerClockLayer(');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 220);
      expect(body, contains('onLeft: true'));
    });

    test('697：时钟开启时标题让位（642 的硬编码 false 已修正）', () {
      final src = File('lib/screens/player/player_screen.dart').readAsStringSync();
      // 642 把时钟移到左侧后，尾部预留被硬编码为 false，但预留区当时仍在
      // Row 末尾 → 标题与左上角时钟重叠。697 改为「左侧预留 + 按需开启」。
      expect(
        src,
        contains('reserveClockSpace: tvMode && clockFormat.enabled'),
        reason: 'TV 时钟在左上角，开启时标题需让位；关闭时不让位',
      );
      expect(src, isNot(contains('reserveClockSpace: false')));
    });

    test('player_screen 有 TV 网速独立定位层', () {
      final src = File('lib/screens/player/player_screen.dart').readAsStringSync();
      expect(src, contains('playerTvNetworkSpeed'));
    });

    test('Kotlin：时钟是 topBar 首个子项、网速在最右', () {
      final src = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'NativePlayerScreenView.kt',
      ).readAsStringSync();
      final start = src.indexOf('private fun configureTopBar()');
      expect(start, greaterThan(-1));
      final body = src.substring(start, start + 9000);
      // 时钟先于返回按钮加入。
      final clockIdx = body.indexOf('topBar.addView(\n            clockWrap');
      final backIdx = body.indexOf('topBar.addView(backButton');
      expect(clockIdx, greaterThan(-1));
      expect(backIdx, greaterThan(clockIdx));
      // TV 网速在最后。
      expect(body, contains('networkTextTv'));
    });

    test('Kotlin：TV 时钟跟随设置显隐（off 时让标题左移填充）', () {
      final src = File(
        'android/app/src/main/kotlin/com/himi/syncwatch/nativeplayer/'
        'NativePlayerScreenView.kt',
      ).readAsStringSync();
      expect(
        src,
        contains('if (tv && state.clockFormat != "off") VISIBLE else GONE'),
      );
    });
  });
}

PlayerTopBar _bar({
  String title = '',
  String? networkSpeedText,
  bool showBack = true,
  bool showNetworkSpeed = true,
}) =>
    PlayerTopBar(
      title: title,
      networkSpeedText: networkSpeedText,
      showDecodeButton: false,
      decodeMenuOpen: false,
      glassEnabled: true,
      showVideoFitButton: false,
      videoFitIcon: Icons.fit_screen,
      videoFitLabel: '自适应',
      onCycleVideoFit: () {},
      showShare: false,
      onBack: () {},
      onToggleDecode: () {},
      onShare: () {},
      showBack: showBack,
      showNetworkSpeed: showNetworkSpeed,
    );

Widget _host(Widget child) {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => FakeSettingsNotifier(
            const AppSettings(),
          )),
    ],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}
