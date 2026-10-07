import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/screens/player/player_platform.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('平台开关', () {
    test('Windows：禁垂直手势、开滑杆、开空格、亮度跟随系统、开全屏按钮', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(PlayerPlatform.verticalVolumeBrightnessGesture, isFalse);
      expect(PlayerPlatform.volumeBrightnessSliders, isTrue);
      expect(PlayerPlatform.spaceKeyPlayPause, isTrue);
      expect(PlayerPlatform.brightnessFollowsSystem, isTrue);
      expect(PlayerPlatform.windowFullscreenButton, isTrue);
    });

    test('Android：保留手势、无滑杆、无空格、亮度不跟随、无全屏按钮', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlayerPlatform.verticalVolumeBrightnessGesture, isTrue);
      expect(PlayerPlatform.volumeBrightnessSliders, isFalse);
      expect(PlayerPlatform.spaceKeyPlayPause, isFalse);
      expect(PlayerPlatform.brightnessFollowsSystem, isFalse);
      expect(PlayerPlatform.windowFullscreenButton, isFalse);
    });

    test('iOS：与 Android 一致', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(PlayerPlatform.verticalVolumeBrightnessGesture, isTrue);
      expect(PlayerPlatform.volumeBrightnessSliders, isFalse);
      expect(PlayerPlatform.spaceKeyPlayPause, isFalse);
      expect(PlayerPlatform.windowFullscreenButton, isFalse);
    });

    test('macOS：全屏按钮开但空格/滑杆关', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(PlayerPlatform.windowFullscreenButton, isTrue);
      expect(PlayerPlatform.spaceKeyPlayPause, isFalse);
      expect(PlayerPlatform.volumeBrightnessSliders, isFalse);
    });

    test('Linux：全屏按钮开但空格/滑杆关', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(PlayerPlatform.windowFullscreenButton, isTrue);
      expect(PlayerPlatform.spaceKeyPlayPause, isFalse);
      expect(PlayerPlatform.volumeBrightnessSliders, isFalse);
    });
  });

  group('mediaLongPressSpeedBoost（长按临时倍速，仅手机）', () {
    test('Android / iOS 开', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PlayerPlatform.mediaLongPressSpeedBoost, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(PlayerPlatform.mediaLongPressSpeedBoost, isTrue);
    });

    test('桌面 / Web 关', () {
      for (final p in const [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = p;
        expect(PlayerPlatform.mediaLongPressSpeedBoost, isFalse);
      }
    });
  });

  group('initialBrightness', () {    test('跟随系统时采用当前值', () {
      expect(
        PlayerPlatform.initialBrightness(current: 0.55, followSystem: true),
        closeTo(0.55, 1e-9),
      );
    });

    test('跟随系统时当前值越界被夹紧', () {
      expect(
        PlayerPlatform.initialBrightness(current: 1.7, followSystem: true),
        1.0,
      );
      expect(
        PlayerPlatform.initialBrightness(current: -0.2, followSystem: true),
        0.0,
      );
    });

    test('跟随系统时 NaN 回退默认值', () {
      expect(
        PlayerPlatform.initialBrightness(
            current: double.nan, followSystem: true),
        closeTo(0.8, 1e-9),
      );
    });

    test('不跟随系统时总是返回 fallback', () {
      expect(
        PlayerPlatform.initialBrightness(
            current: 0.3, followSystem: false),
        closeTo(0.8, 1e-9),
      );
      expect(
        PlayerPlatform.initialBrightness(
            current: 0.3, followSystem: false, fallback: 0.6),
        closeTo(0.6, 1e-9),
      );
    });
  });
}
