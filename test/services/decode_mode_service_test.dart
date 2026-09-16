import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/decode_mode_service.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

void main() {
  group('resolveDecoders', () {
    test('SW 模式 → 仅软解', () {
      final result = DecodeModeService.resolveDecoders('sw');
      expect(result, equals(['FFmpeg']));
    });

    test('HW 模式 → 纯硬解，不含 FFmpeg', () {
      final result = DecodeModeService.resolveDecoders('hw');
      if (Platform.isAndroid) {
        expect(result, equals(['AMediaCodec']));
      } else if (Platform.isIOS || Platform.isMacOS) {
        expect(result, equals(['VT']));
      } else if (Platform.isWindows) {
        expect(result, contains('D3D11'));
        expect(result, isNot(contains('FFmpeg')));
      } else if (Platform.isLinux) {
        expect(result, contains('VAAPI'));
        expect(result, isNot(contains('FFmpeg')));
      }
    });

    test('Auto 模式 → 硬解+软解回退', () {
      final result = DecodeModeService.resolveDecoders('auto');
      if (Platform.isAndroid) {
        expect(result, contains('AMediaCodec'));
      } else if (Platform.isIOS || Platform.isMacOS) {
        expect(result, contains('VT'));
      } else if (Platform.isWindows) {
        expect(result, contains('D3D11'));
      } else if (Platform.isLinux) {
        expect(result, contains('VAAPI'));
      }
      expect(result, contains('FFmpeg'));
    });

    test('未知模式 → 默认 auto 解码器', () {
      final result = DecodeModeService.resolveDecoders('unknown');
      expect(result, isNotEmpty);
      expect(result, contains('FFmpeg'));
    });
  });

  group('AppSettings.fromJson - 解码模式兼容', () {
    test('新版 decodeMode 字符串值 hw', () {
      final settings = AppSettings.fromJson({'decodeMode': 'hw'});
      expect(settings.decodeMode, equals('hw'));
    });

    test('新版 decodeMode 字符串值 sw', () {
      final settings = AppSettings.fromJson({'decodeMode': 'sw'});
      expect(settings.decodeMode, equals('sw'));
    });

    test('新版 decodeMode 字符串值 auto', () {
      final settings = AppSettings.fromJson({'decodeMode': 'auto'});
      expect(settings.decodeMode, equals('auto'));
    });

    test('旧版 hw+ 迁移到 auto', () {
      final settings = AppSettings.fromJson({'decodeMode': 'hw+'});
      expect(settings.decodeMode, equals('auto'));
    });

    test('旧版 hardwareDecoding=true → auto', () {
      final settings = AppSettings.fromJson({'hardwareDecoding': true});
      expect(settings.decodeMode, equals('auto'));
    });

    test('旧版 hardwareDecoding=false → sw', () {
      final settings = AppSettings.fromJson({'hardwareDecoding': false});
      expect(settings.decodeMode, equals('sw'));
    });

    test('无效值 → 默认 auto', () {
      final settings = AppSettings.fromJson({'decodeMode': 123});
      expect(settings.decodeMode, equals('auto'));
    });

    test('bufferSizeMB 默认值 64', () {
      final settings = AppSettings.fromJson({});
      expect(settings.bufferSizeMB, equals(64));
    });

    test('bufferSizeMB 从 JSON 读取', () {
      final settings = AppSettings.fromJson({'bufferSizeMB': 128});
      expect(settings.bufferSizeMB, equals(128));
    });
  });
}
