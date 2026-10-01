import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

void main() {
  group('effectiveAudioRenderer（音频后端生效值）', () {
    test('Windows 固定为自动，忽略存档的 Android 后端', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(AppSettings.effectiveAudioRenderer('AudioTrack'), 'auto');
      expect(AppSettings.effectiveAudioRenderer('aaudio'), 'auto');
      expect(AppSettings.effectiveAudioRenderer('opensl'), 'auto');
      expect(AppSettings.effectiveAudioRenderer('auto'), 'auto');
    });

    test('非 Windows 平台保持用户设置', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(AppSettings.effectiveAudioRenderer('AudioTrack'), 'AudioTrack');
      expect(AppSettings.effectiveAudioRenderer('aaudio'), 'aaudio');
      expect(AppSettings.effectiveAudioRenderer('auto'), 'auto');
    });
  });

  group('AppSettings', () {
    test('默认值', () {
      const settings = AppSettings();
      expect(settings.decodeMode, equals('auto'));
      expect(settings.showSyncDebug, isFalse);
      expect(settings.stereoDownmix, isFalse);
      expect(settings.audioRenderer, equals('AudioTrack'));
    });

    test('copyWith 保留未指定字段', () {
      const original = AppSettings(decodeMode: 'hw', stereoDownmix: true);
      final copied = original.copyWith(showSyncDebug: true);
      expect(copied.decodeMode, equals('hw'));
      expect(copied.stereoDownmix, isTrue);
      expect(copied.showSyncDebug, isTrue);
    });

    test('copyWith 修改字段', () {
      const original = AppSettings();
      final copied = original.copyWith(decodeMode: 'sw', stereoDownmix: true);
      expect(copied.decodeMode, equals('sw'));
      expect(copied.stereoDownmix, isTrue);
    });

    test('toJson 包含所有字段', () {
      const settings = AppSettings(
        decodeMode: 'hw',
        showSyncDebug: true,
        stereoDownmix: true,
        deepDiagnostics: true,
      );
      final json = settings.toJson();
      expect(json['decodeMode'], equals('hw'));
      expect(json['showSyncDebug'], isTrue);
      expect(json['stereoDownmix'], isTrue);
      expect(json['deepDiagnostics'], isTrue);
    });

    test('fromJson 解析所有字段', () {
      final json = {
        'decodeMode': 'hw',
        'showSyncDebug': true,
        'stereoDownmix': true,
        'deepDiagnostics': true,
      };
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('hw'));
      expect(settings.showSyncDebug, isTrue);
      expect(settings.stereoDownmix, isTrue);
      expect(settings.deepDiagnostics, isTrue);
    });

    test('deepDiagnostics 缺省为关闭', () {
      expect(const AppSettings().deepDiagnostics, isFalse);
      expect(AppSettings.fromJson(const {}).deepDiagnostics, isFalse);
    });

    test('copyWith 透传 deepDiagnostics', () {
      const settings = AppSettings();
      expect(settings.copyWith(deepDiagnostics: true).deepDiagnostics, isTrue);
      // 未指定时保持原值
      expect(settings.copyWith(showSyncDebug: true).deepDiagnostics, isFalse);
      expect(
        settings
            .copyWith(deepDiagnostics: true)
            .copyWith(showSyncDebug: true)
            .deepDiagnostics,
        isTrue,
      );
    });

    test('fromJson 默认值', () {
      final json = <String, dynamic>{};
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('auto'));
      expect(settings.showSyncDebug, isFalse);
      expect(settings.stereoDownmix, isFalse);
      expect(settings.audioRenderer, equals('AudioTrack'));
    });

    test('fromJson 兼容旧版 bool hardwareDecoding', () {
      final json = {'hardwareDecoding': true};
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('auto'));
    });

    test('fromJson 兼容旧版 false hardwareDecoding', () {
      final json = {'hardwareDecoding': false};
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('sw'));
    });

    test('fromJson 兼容旧版 hw+ 迁移到 auto', () {
      final json = {'decodeMode': 'hw+'};
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('auto'));
    });

    test('toJson/fromJson 往返保持一致', () {
      const original = AppSettings(
        decodeMode: 'hw',
        showSyncDebug: true,
        stereoDownmix: true,
      );
      final json = original.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.decodeMode, equals(original.decodeMode));
      expect(restored.showSyncDebug, equals(original.showSyncDebug));
      expect(restored.stereoDownmix, equals(original.stereoDownmix));
    });

    test('hardwareDecoding getter', () {
      const autoSettings = AppSettings(decodeMode: 'auto');
      expect(autoSettings.hardwareDecoding, isTrue);

      const hwSettings = AppSettings(decodeMode: 'hw');
      expect(hwSettings.hardwareDecoding, isTrue);

      const swSettings = AppSettings(decodeMode: 'sw');
      expect(swSettings.hardwareDecoding, isFalse);
    });

    test('glassUi 缺省为开启', () {
      expect(const AppSettings().glassUi, isTrue);
      expect(AppSettings.fromJson(const {}).glassUi, isTrue);
    });

    test('copyWith 透传 glassUi', () {
      const settings = AppSettings();
      expect(settings.copyWith(glassUi: false).glassUi, isFalse);
      expect(settings.copyWith(decodeMode: 'hw').glassUi, isTrue);
    });

    test('toJson/fromJson 往返保持 glassUi', () {
      const original = AppSettings(glassUi: false);
      final restored = AppSettings.fromJson(original.toJson());
      expect(restored.glassUi, isFalse);

      const enabled = AppSettings();
      expect(AppSettings.fromJson(enabled.toJson()).glassUi, isTrue);
    });

    test('themeColor 缺省为 null（跟随默认底色）', () {
      expect(const AppSettings().themeColor, isNull);
      expect(AppSettings.fromJson(const {}).themeColor, isNull);
    });

    test('copyWith 设置与显式清空 themeColor', () {
      const settings = AppSettings();
      final set = settings.copyWith(themeColor: 0xFF6366F1);
      expect(set.themeColor, equals(0xFF6366F1));

      // 其他字段更新不清掉 themeColor
      final kept = set.copyWith(decodeMode: 'hw');
      expect(kept.themeColor, equals(0xFF6366F1));

      // 显式清空为 null（依赖 unsetValue 哨兵区分「未传」）
      final cleared = kept.copyWith(themeColor: null);
      expect(cleared.themeColor, isNull);

      // 未传 themeColor 的 copyWith 不改变原值
      expect(set.copyWith(decodeMode: 'sw').themeColor, equals(0xFF6366F1));
    });

    test('toJson/fromJson 往返保持 themeColor', () {
      const withColor = AppSettings(themeColor: 0xFF22D3EE);
      expect(withColor.toJson()['themeColor'], equals(0xFF22D3EE));
      expect(
        AppSettings.fromJson(withColor.toJson()).themeColor,
        equals(0xFF22D3EE),
      );

      const withoutColor = AppSettings();
      expect(withoutColor.toJson().containsKey('themeColor'), isFalse);
      expect(AppSettings.fromJson(withoutColor.toJson()).themeColor, isNull);
    });
  });
}
