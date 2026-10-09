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

  group('resolveAudioDecoders（音频硬解接线，1.1.186）', () {
    test('SW 模式 → 仅 FFmpeg 软解', () {
      final result = DecodeModeService.resolveAudioDecoders('sw');
      expect(result, equals(['FFmpeg']));
    });

    test('HW 模式 → Android/Windows 纯硬解；无硬解平台回退 FFmpeg', () {
      final result = DecodeModeService.resolveAudioDecoders('hw');
      if (Platform.isAndroid) {
        expect(result, equals(['AMediaCodec']));
      } else if (Platform.isWindows) {
        expect(result, equals(['MFT']));
      } else {
        // Apple/Linux 无 mdk 音频硬解器 → 回退 FFmpeg（唯一可用）
        expect(result, equals(['FFmpeg']));
      }
    });

    test('Auto 模式 → Android 硬解优先 + FFmpeg 兜底', () {
      final result = DecodeModeService.resolveAudioDecoders('auto');
      if (Platform.isAndroid) {
        expect(result, equals(['AMediaCodec', 'FFmpeg']));
      } else if (Platform.isWindows) {
        expect(result, equals(['MFT', 'FFmpeg']));
      } else {
        // iOS/macOS/Linux：mdk 无音频硬解（VT 仅视频），恒为 FFmpeg
        expect(result, equals(['FFmpeg']));
      }
    });

    test('未知模式 → 默认 auto 音频解码器', () {
      final result = DecodeModeService.resolveAudioDecoders('unknown');
      expect(result, equals(
          DecodeModeService.resolveAudioDecoders('auto')));
    });

    test('Android auto：FFmpeg 兜底保证兼容（硬解失败不黑屏）', () {
      if (!Platform.isAndroid) return;
      final result = DecodeModeService.resolveAudioDecoders('auto');
      expect(result.last, equals('FFmpeg'));
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
  });
}
