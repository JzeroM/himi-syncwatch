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

  group('resolveHwdec - 基础模式', () {
    test('SW 模式 → "no"', () {
      final result = DecodeModeService.resolveHwdec('sw', null);
      expect(result, equals('no'));
    });

    test('HW 模式 → 平台直通值', () {
      final result = DecodeModeService.resolveHwdec('hw', null);
      if (Platform.isAndroid) {
        expect(result, equals('mediacodec'));
      } else if (Platform.isIOS || Platform.isMacOS) {
        expect(result, equals('videotoolbox'));
      } else if (Platform.isWindows) {
        expect(result, equals('d3d11va'));
      } else if (Platform.isLinux) {
        expect(result, equals('vaapi'));
      } else {
        expect(result, equals('auto'));
      }
    });

    test('HW+ 模式 → 平台回拷值', () {
      final result = DecodeModeService.resolveHwdec('hw+', null);
      if (Platform.isAndroid) {
        expect(result, equals('mediacodec-copy'));
      } else if (Platform.isIOS || Platform.isMacOS) {
        expect(result, equals('videotoolbox-copy'));
      } else if (Platform.isWindows) {
        expect(result, equals('d3d11va-copy'));
      } else if (Platform.isLinux) {
        expect(result, equals('vaapi-copy'));
      } else {
        expect(result, equals('auto-copy'));
      }
    });

    test('未知模式 → "auto-safe"', () {
      final result = DecodeModeService.resolveHwdec('unknown', null);
      expect(result, equals('auto-safe'));
    });
  });

  group('resolveHwdec - Auto 智能化', () {
    test('有硬解能力 → 平台直通值', () {
      const deviceInfo = DeviceCodecInfo(
        hasH264Hw: true,
        hasHevcHw: true,
        hasVp9Hw: false,
        hasAv1Hw: false,
        hwDecoders: ['h264_mediacodec', 'hevc_mediacodec'],
      );
      final result = DecodeModeService.resolveHwdec('auto', deviceInfo);
      if (Platform.isAndroid) {
        expect(result, equals('mediacodec'));
      } else if (Platform.isIOS || Platform.isMacOS) {
        expect(result, equals('videotoolbox'));
      } else if (Platform.isWindows) {
        expect(result, equals('d3d11va'));
      } else if (Platform.isLinux) {
        expect(result, equals('vaapi'));
      } else {
        expect(result, equals('auto'));
      }
    });

    test('无硬解能力 → "auto-safe"', () {
      const deviceInfo = DeviceCodecInfo(
        hasH264Hw: false,
        hasHevcHw: false,
        hasVp9Hw: false,
        hasAv1Hw: false,
        hwDecoders: [],
      );
      final result = DecodeModeService.resolveHwdec('auto', deviceInfo);
      expect(result, equals('auto-safe'));
    });

    test('deviceInfo=null → "auto-safe"', () {
      final result = DecodeModeService.resolveHwdec('auto', null);
      expect(result, equals('auto-safe'));
    });

    test('deviceInfo.isUnknown → "auto-safe"', () {
      const deviceInfo = DeviceCodecInfo.unknown();
      final result = DecodeModeService.resolveHwdec('auto', deviceInfo);
      expect(result, equals('auto-safe'));
    });
  });

  group('resolveFallback', () {
    test('HW 模式 → "no"（不允许降级）', () {
      expect(DecodeModeService.resolveFallback('hw'), equals('no'));
    });

    test('HW+ 模式 → "no"（不允许降级）', () {
      expect(DecodeModeService.resolveFallback('hw+'), equals('no'));
    });

    test('Auto 模式 → "3"（允许降级）', () {
      expect(DecodeModeService.resolveFallback('auto'), equals('3'));
    });

    test('SW 模式 → "3"（无实际影响，hwdec=no）', () {
      expect(DecodeModeService.resolveFallback('sw'), equals('3'));
    });
  });

  group('parseLogMessage', () {
    test('通用硬件解码成功日志', () {
      final result = DecodeModeService.parseLogMessage(
        'Using hardware decoding (d3d11va)',
      );
      expect(result, equals(DecodeStatus.hwActive));
    });

    test('Android MediaCodec 启动成功', () {
      final result = DecodeModeService.parseLogMessage(
        'MediaCodec started successfully',
      );
      expect(result, equals(DecodeStatus.hwActive));
    });

    test('Android HW-download 回拷成功', () {
      final result = DecodeModeService.parseLogMessage(
        'HW-downloading from mediacodec',
      );
      expect(result, equals(DecodeStatus.hwActive));
    });

    test('硬件解码失败', () {
      final result = DecodeModeService.parseLogMessage(
        'Error while decoding frame',
      );
      expect(result, equals(DecodeStatus.hwFailed));
    });

    test('尝试下一种解码方法（失败）', () {
      final result = DecodeModeService.parseLogMessage(
        'Attempting next decoding method after failure',
      );
      expect(result, equals(DecodeStatus.hwFailed));
    });

    test('无关日志 → unknown', () {
      final result = DecodeModeService.parseLogMessage(
        'AO: [pulse] 48000Hz stereo 2ch',
      );
      expect(result, equals(DecodeStatus.unknown));
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

    test('Android 专属 - mediacodec-copy', () {
      final result = DecodeModeService.parseActualDecoder(
        'HW-downloading from mediacodec',
      );
      expect(result, equals('mediacodec-copy'));
    });

    test('失败日志 → "no"', () {
      final result = DecodeModeService.parseActualDecoder(
        'Error while decoding frame',
      );
      expect(result, equals('no'));
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
