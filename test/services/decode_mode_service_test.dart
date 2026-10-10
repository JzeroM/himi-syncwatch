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

    test('HW 模式 → 硬解优先 + FFmpeg 兜底（音频无硬解防没声，1.1.187）', () {
      final result = DecodeModeService.resolveAudioDecoders('hw');
      if (Platform.isAndroid) {
        expect(result, equals(['AMediaCodec', 'FFmpeg']));
      } else if (Platform.isWindows) {
        expect(result, equals(['MFT', 'FFmpeg']));
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

  group('DecodeModeService.withDecoderImage（1.1.190 官方 setDecoders 方式）', () {
    test('AMediaCodec 无属性 → 追加 image=0', () {
      expect(
        DecodeModeService.withDecoderImage(['AMediaCodec'], '0'),
        ['AMediaCodec:image=0'],
      );
    });

    test('AMediaCodec + FFmpeg → 仅 AMediaCodec 追加 image=0', () {
      expect(
        DecodeModeService.withDecoderImage(['AMediaCodec', 'FFmpeg'], '0'),
        ['AMediaCodec:image=0', 'FFmpeg'],
      );
    });

    test('已有 image=1 → 替换为 image=0', () {
      expect(
        DecodeModeService.withDecoderImage(['AMediaCodec:image=1'], '0'),
        ['AMediaCodec:image=0'],
      );
    });

    test('已有 image=0 → 不重复追加', () {
      expect(
        DecodeModeService.withDecoderImage(['AMediaCodec:image=0'], '0'),
        ['AMediaCodec:image=0'],
      );
    });

    test('恢复 SDR：image=0 → image=1', () {
      expect(
        DecodeModeService.withDecoderImage(['AMediaCodec:image=0'], '1'),
        ['AMediaCodec:image=1'],
      );
    });

    test('多属性合并：保留其他键', () {
      expect(
        DecodeModeService.withDecoderImage(['AMediaCodec:low_latency=1'], '0'),
        ['AMediaCodec:low_latency=1:image=0'],
      );
    });

    test('非 AMediaCodec 条目原样保留', () {
      expect(
        DecodeModeService.withDecoderImage(['FFmpeg'], '0'),
        ['FFmpeg'],
      );
    });

    test('混合列表：仅 AMediaCodec 被修改', () {
      expect(
        DecodeModeService.withDecoderImage(
            ['AMediaCodec', 'FFmpeg', 'VT'], '0'),
        ['AMediaCodec:image=0', 'FFmpeg', 'VT'],
      );
    });

    test('image 键在中间 → 原位替换', () {
      expect(
        DecodeModeService.withDecoderImage(
            ['AMediaCodec:image=1:foo=2'], '0'),
        ['AMediaCodec:foo=2:image=0'],
      );
    });
  });

  group('DecodeModeService.withDecoderLowLatency（1.1.192 实验）', () {
    test('AMediaCodec 无属性 → 追加 low_latency=1', () {
      expect(
        DecodeModeService.withDecoderLowLatency(['AMediaCodec']),
        ['AMediaCodec:low_latency=1'],
      );
    });

    test('AMediaCodec + FFmpeg → 仅 AMediaCodec 追加', () {
      expect(
        DecodeModeService.withDecoderLowLatency(['AMediaCodec', 'FFmpeg']),
        ['AMediaCodec:low_latency=1', 'FFmpeg'],
      );
    });

    test('已有 low_latency=1 → 不重复追加', () {
      expect(
        DecodeModeService.withDecoderLowLatency(['AMediaCodec:low_latency=1']),
        ['AMediaCodec:low_latency=1'],
      );
    });

    test('已有 low_latency=0 → 不追加（contains 检查任意 low_latency= 值）', () {
      // 实现用 d.contains('low_latency=') 检查，low_latency=0 也视为已有
      expect(
        DecodeModeService.withDecoderLowLatency(['AMediaCodec:low_latency=0']),
        ['AMediaCodec:low_latency=0'],
      );
    });

    test('已有 image=0 → 保留 image 属性', () {
      expect(
        DecodeModeService.withDecoderLowLatency(['AMediaCodec:image=0']),
        ['AMediaCodec:image=0:low_latency=1'],
      );
    });

    test('image=0 + low_latency=1 组合 → 两属性共存', () {
      expect(
        DecodeModeService.withDecoderLowLatency(
            ['AMediaCodec:image=0:low_latency=1']),
        ['AMediaCodec:image=0:low_latency=1'],
      );
    });

    test('非 AMediaCodec 条目原样保留', () {
      expect(
        DecodeModeService.withDecoderLowLatency(['FFmpeg']),
        ['FFmpeg'],
      );
    });

    test('混合列表：仅 AMediaCodec 被修改', () {
      expect(
        DecodeModeService.withDecoderLowLatency(
            ['AMediaCodec', 'FFmpeg', 'VT']),
        ['AMediaCodec:low_latency=1', 'FFmpeg', 'VT'],
      );
    });
  });
}
