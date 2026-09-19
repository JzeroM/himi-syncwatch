import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('默认值', () {
      const settings = AppSettings();
      expect(settings.decodeMode, equals('auto'));
      expect(settings.showSyncDebug, isFalse);
      expect(settings.stereoDownmix, isFalse);
      expect(settings.videoCacheSize, equals(64));
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
        videoCacheSize: 128,
      );
      final json = settings.toJson();
      expect(json['decodeMode'], equals('hw'));
      expect(json['showSyncDebug'], isTrue);
      expect(json['stereoDownmix'], isTrue);
      expect(json['videoCacheSize'], equals(128));
    });

    test('fromJson 解析所有字段', () {
      final json = {
        'decodeMode': 'hw',
        'showSyncDebug': true,
        'stereoDownmix': true,
        'videoCacheSize': 256,
      };
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('hw'));
      expect(settings.showSyncDebug, isTrue);
      expect(settings.stereoDownmix, isTrue);
      expect(settings.videoCacheSize, equals(256));
    });

    test('fromJson 默认值', () {
      final json = <String, dynamic>{};
      final settings = AppSettings.fromJson(json);
      expect(settings.decodeMode, equals('auto'));
      expect(settings.showSyncDebug, isFalse);
      expect(settings.stereoDownmix, isFalse);
      expect(settings.videoCacheSize, equals(64));
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
        videoCacheSize: 128,
      );
      final json = original.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.decodeMode, equals(original.decodeMode));
      expect(restored.showSyncDebug, equals(original.showSyncDebug));
      expect(restored.stereoDownmix, equals(original.stereoDownmix));
      expect(restored.videoCacheSize, equals(original.videoCacheSize));
    });

    test('hardwareDecoding getter', () {
      const autoSettings = AppSettings(decodeMode: 'auto');
      expect(autoSettings.hardwareDecoding, isTrue);

      const hwSettings = AppSettings(decodeMode: 'hw');
      expect(hwSettings.hardwareDecoding, isTrue);

      const swSettings = AppSettings(decodeMode: 'sw');
      expect(swSettings.hardwareDecoding, isFalse);
    });

    test('videoCacheSize 默认值为 64', () {
      const settings = AppSettings();
      expect(settings.videoCacheSize, equals(64));
    });

    test('videoCacheSize copyWith 修改', () {
      const original = AppSettings();
      final copied = original.copyWith(videoCacheSize: 256);
      expect(copied.videoCacheSize, equals(256));
      expect(original.videoCacheSize, equals(64));
    });

    test('videoCacheSize toJson/fromJson 往返', () {
      const original = AppSettings(videoCacheSize: 512);
      final json = original.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.videoCacheSize, equals(512));
    });

    test('videoCacheSize 旧版无此字段时默认 64', () {
      final json = <String, dynamic>{};
      final settings = AppSettings.fromJson(json);
      expect(settings.videoCacheSize, equals(64));
    });
  });
}
