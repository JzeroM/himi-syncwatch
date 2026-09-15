import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

void main() {
  group('AppSettings dvHwDecode', () {
    test('默认值为 false', () {
      const settings = AppSettings();
      expect(settings.dvHwDecode, isFalse);
    });

    test('copyWith 保留 dvHwDecode', () {
      const original = AppSettings(dvHwDecode: true);
      final copied = original.copyWith(decodeMode: 'hw');
      expect(copied.dvHwDecode, isTrue);
      expect(copied.decodeMode, equals('hw'));
    });

    test('copyWith 修改 dvHwDecode', () {
      const original = AppSettings();
      final copied = original.copyWith(dvHwDecode: true);
      expect(copied.dvHwDecode, isTrue);
    });

    test('toJson 包含 dvHwDecode', () {
      const settings = AppSettings(dvHwDecode: true);
      final json = settings.toJson();
      expect(json['dvHwDecode'], isTrue);
    });

    test('fromJson 解析 dvHwDecode', () {
      final json = {
        'decodeMode': 'auto',
        'bufferSizeMB': 64,
        'showSyncDebug': false,
        'dvHwDecode': true,
      };
      final settings = AppSettings.fromJson(json);
      expect(settings.dvHwDecode, isTrue);
    });

    test('fromJson 默认 dvHwDecode 为 false', () {
      final json = {
        'decodeMode': 'auto',
        'bufferSizeMB': 64,
        'showSyncDebug': false,
      };
      final settings = AppSettings.fromJson(json);
      expect(settings.dvHwDecode, isFalse);
    });

    test('toJson/fromJson 往返保持一致', () {
      const original = AppSettings(
        decodeMode: 'hw+',
        bufferSizeMB: 128,
        showSyncDebug: true,
        dvHwDecode: true,
      );
      final json = original.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.decodeMode, equals(original.decodeMode));
      expect(restored.bufferSizeMB, equals(original.bufferSizeMB));
      expect(restored.showSyncDebug, equals(original.showSyncDebug));
      expect(restored.dvHwDecode, equals(original.dvHwDecode));
    });
  });
}
