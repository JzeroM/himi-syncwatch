import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('默认值', () {
      const settings = AppSettings();
      expect(settings.decodeMode, equals('auto'));
      expect(settings.showSyncDebug, isFalse);
    });

    test('copyWith 保留未指定字段', () {
      const original = AppSettings(decodeMode: 'hw');
      final copied = original.copyWith(showSyncDebug: true);
      expect(copied.decodeMode, equals('hw'));
      expect(copied.showSyncDebug, isTrue);
    });

    test('copyWith 修改字段', () {
      const original = AppSettings();
      final copied = original.copyWith(decodeMode: 'sw');
      expect(copied.decodeMode, equals('sw'));
    });

    test('toJson 包含所有字段', () {
      const settings = AppSettings(
        decodeMode: 'hw',
        showSyncDebug: true,
      );
      final json = settings.toJson();
      expect(json['decodeMode'], equals('hw'));
      expect(json['showSyncDebug'], isTrue);
    });

    test('fromJson 解析所有字段', () {
      final json = {
        'decodeMode': 'hw',
        'showSyncDebug': true,
      };
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('hw'));
      expect(settings.showSyncDebug, isTrue);
    });

    test('fromJson 默认值', () {
      final json = <String, dynamic>{};
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('auto'));
      expect(settings.showSyncDebug, isFalse);
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
      );
      final json = original.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.decodeMode, equals(original.decodeMode));
      expect(restored.showSyncDebug, equals(original.showSyncDebug));
    });

    test('hardwareDecoding getter', () {
      const autoSettings = AppSettings(decodeMode: 'auto');
      expect(autoSettings.hardwareDecoding, isTrue);

      const hwSettings = AppSettings(decodeMode: 'hw');
      expect(hwSettings.hardwareDecoding, isTrue);

      const swSettings = AppSettings(decodeMode: 'sw');
      expect(swSettings.hardwareDecoding, isFalse);
    });
  });
}
