import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/player/native/native_player_gating.dart';

void main() {
  group('NativePlayerGating.shouldUse', () {
    test('Android Surface + mpv + 设置开启 → 启用', () {
      expect(
        NativePlayerGating.shouldUse(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platformName: 'android',
        ),
        isTrue,
      );
    });

    test('鸿蒙 Surface + mpv + 设置开启 → 启用', () {
      expect(
        NativePlayerGating.shouldUse(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platformName: 'ohos',
        ),
        isTrue,
      );
    });

    test('Texture 模式不启用', () {
      expect(
        NativePlayerGating.shouldUse(
          engine: 'mpv',
          actualVideoOutput: 'texture',
          platformName: 'android',
        ),
        isFalse,
      );
    });

    test('非 mpv 引擎不启用', () {
      expect(
        NativePlayerGating.shouldUse(
          engine: 'mdk',
          actualVideoOutput: 'surface',
          platformName: 'android',
        ),
        isFalse,
      );
      expect(
        NativePlayerGating.shouldUse(
          engine: 'media_kit',
          actualVideoOutput: 'surface',
          platformName: 'ohos',
        ),
        isFalse,
      );
      expect(
        NativePlayerGating.shouldUse(
          engine: 'erika',
          actualVideoOutput: 'surface',
          platformName: 'android',
        ),
        isFalse,
      );
    });

    test('Windows/iOS 等平台不启用', () {
      expect(
        NativePlayerGating.shouldUse(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platformName: 'windows',
        ),
        isFalse,
      );
      expect(
        NativePlayerGating.shouldUse(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platformName: 'iOS',
        ),
        isFalse,
      );
    });

    test('用户关闭设置后不启用', () {
      expect(
        NativePlayerGating.shouldUse(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platformName: 'android',
          settingEnabled: false,
        ),
        isFalse,
      );
    });

    test('shouldUseCurrent 可注入平台', () {
      expect(
        NativePlayerGating.shouldUseCurrent(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        NativePlayerGating.shouldUseCurrent(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platform: TargetPlatform.windows,
        ),
        isFalse,
      );
    });
  });

  group('NativePlayerGating.denyReason', () {
    test('全部满足返回 null', () {
      expect(
        NativePlayerGating.denyReason(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platformName: 'ohos',
        ),
        isNull,
      );
    });

    test('逐项给出原因', () {
      expect(
        NativePlayerGating.denyReason(
          engine: 'mdk',
          actualVideoOutput: 'surface',
          platformName: 'android',
        ),
        contains('mdk'),
      );
      expect(
        NativePlayerGating.denyReason(
          engine: 'mpv',
          actualVideoOutput: 'texture',
          platformName: 'android',
        ),
        contains('texture'),
      );
      expect(
        NativePlayerGating.denyReason(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platformName: 'windows',
        ),
        contains('windows'),
      );
      expect(
        NativePlayerGating.denyReason(
          engine: 'mpv',
          actualVideoOutput: 'surface',
          platformName: 'android',
          settingEnabled: false,
        ),
        contains('设置'),
      );
    });
  });
}
