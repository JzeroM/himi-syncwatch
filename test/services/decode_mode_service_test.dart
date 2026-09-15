import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/decode_mode_service.dart';
import 'package:himi_syncwatch/models/app_settings.dart';

void main() {
  group('DeviceCodecInfo', () {
    test('hasAnyHw - 有 H264 硬解', () {
      const info = DeviceCodecInfo(
        hasH264Hw: true,
        hasHevcHw: false,
        hasVp9Hw: false,
        hasAv1Hw: false,
        hwDecoders: ['h264_mediacodec'],
      );
      expect(info.hasAnyHw, isTrue);
    });

    test('hasAnyHw - 有 HEVC 硬解', () {
      const info = DeviceCodecInfo(
        hasH264Hw: false,
        hasHevcHw: true,
        hasVp9Hw: false,
        hasAv1Hw: false,
        hwDecoders: ['hevc_videotoolbox'],
      );
      expect(info.hasAnyHw, isTrue);
    });

    test('hasAnyHw - 无任何硬解', () {
      const info = DeviceCodecInfo(
        hasH264Hw: false,
        hasHevcHw: false,
        hasVp9Hw: false,
        hasAv1Hw: false,
        hwDecoders: [],
      );
      expect(info.hasAnyHw, isFalse);
    });

    test('unknown() 工厂构造 - isUnknown=true, hasAnyHw=false', () {
      const info = DeviceCodecInfo.unknown();
      expect(info.isUnknown, isTrue);
      expect(info.hasAnyHw, isFalse);
      expect(info.hwDecoders, isEmpty);
    });
  });

  group('resolveDecoders - 基础模式', () {
    test('SW 模式 → [FFmpeg]', () {
      final result = DecodeModeService.resolveDecoders('sw', null);
      expect(result, equals(['FFmpeg']));
    });

    test('HW 模式 → 平台解码器', () {
      final result = DecodeModeService.resolveDecoders('hw', null);
      if (Platform.isAndroid) {
        expect(result, contains('mediacodec'));
      } else if (Platform.isIOS || Platform.isMacOS) {
        expect(result, contains('videotoolbox'));
      } else if (Platform.isWindows) {
        expect(result, contains('d3d11va'));
      } else if (Platform.isLinux) {
        expect(result, contains('vaapi'));
      } else {
        expect(result, contains('auto'));
      }
    });

    test('HW+ 模式 → 平台解码器（回拷）', () {
      final result = DecodeModeService.resolveDecoders('hw+', null);
      if (Platform.isAndroid) {
        expect(result, contains('mediacodec-copy'));
      } else if (Platform.isIOS || Platform.isMacOS) {
        expect(result, contains('videotoolbox-copy'));
      } else if (Platform.isWindows) {
        expect(result, contains('d3d11va-copy'));
      } else if (Platform.isLinux) {
        expect(result, contains('vaapi-copy'));
      } else {
        expect(result, contains('auto-copy'));
      }
    });

    test('未知模式 → [auto]', () {
      final result = DecodeModeService.resolveDecoders('unknown', null);
      expect(result, equals(['auto']));
    });
  });

  group('resolveDecoders - Auto 智能化', () {
    test('有硬解能力 → 平台解码器', () {
      const deviceInfo = DeviceCodecInfo(
        hasH264Hw: true,
        hasHevcHw: true,
        hasVp9Hw: false,
        hasAv1Hw: false,
        hwDecoders: ['h264_mediacodec', 'hevc_mediacodec'],
      );
      final result = DecodeModeService.resolveDecoders('auto', deviceInfo);
      if (Platform.isAndroid) {
        expect(result, contains('mediacodec'));
      } else if (Platform.isIOS || Platform.isMacOS) {
        expect(result, contains('videotoolbox'));
      } else if (Platform.isWindows) {
        expect(result, contains('d3d11va'));
      } else if (Platform.isLinux) {
        expect(result, contains('vaapi'));
      } else {
        expect(result, contains('auto'));
      }
    });

    test('无硬解能力 → [auto]', () {
      const deviceInfo = DeviceCodecInfo(
        hasH264Hw: false,
        hasHevcHw: false,
        hasVp9Hw: false,
        hasAv1Hw: false,
        hwDecoders: [],
      );
      final result = DecodeModeService.resolveDecoders('auto', deviceInfo);
      expect(result, equals(['auto']));
    });

    test('deviceInfo=null → [auto]', () {
      final result = DecodeModeService.resolveDecoders('auto', null);
      expect(result, equals(['auto']));
    });

    test('deviceInfo.isUnknown → [auto]', () {
      const deviceInfo = DeviceCodecInfo.unknown();
      final result = DecodeModeService.resolveDecoders('auto', deviceInfo);
      expect(result, equals(['auto']));
    });
  });

  group('allowFallback', () {
    test('HW 模式 → false（不允许降级）', () {
      expect(DecodeModeService.allowFallback('hw'), isFalse);
    });

    test('HW+ 模式 → false（不允许降级）', () {
      expect(DecodeModeService.allowFallback('hw+'), isFalse);
    });

    test('Auto 模式 → true（允许降级）', () {
      expect(DecodeModeService.allowFallback('auto'), isTrue);
    });

    test('SW 模式 → true（无实际影响）', () {
      expect(DecodeModeService.allowFallback('sw'), isTrue);
    });
  });

  group('parseActualDecoder', () {
    test('通用成功 - 提取解码器名称', () {
      final result = DecodeModeService.parseActualDecoder(
        'Using hardware decoding (d3d11va)',
      );
      expect(result, equals('d3d11va'));
    });

    test('通用成功 - videotoolbox', () {
      final result = DecodeModeService.parseActualDecoder(
        'Using hardware decoding (videotoolbox)',
      );
      expect(result, equals('videotoolbox'));
    });

    test('无关日志 → null', () {
      final result = DecodeModeService.parseActualDecoder(
        'Using software decoding.',
      );
      expect(result, isNull);
    });
  });

  group('AppSettings.fromJson - 解码模式兼容', () {
    test('新版 decodeMode 字符串值', () {
      final settings = AppSettings.fromJson({'decodeMode': 'hw+'});
      expect(settings.decodeMode, equals('hw+'));
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
