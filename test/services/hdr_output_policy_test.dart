import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/device_profile.dart';
import 'package:himi_syncwatch/services/hdr_output_policy.dart';
import 'package:himi_syncwatch/services/player/player_adapter.dart';

void main() {
  const hdr10 = DisplayCapabilities(hdrTypes: ['hdr10']);
  const hlg = DisplayCapabilities(hdrTypes: ['hlg']);
  const both = DisplayCapabilities(hdrTypes: ['hdr10', 'hlg']);
  const sdr = DisplayCapabilities();

  AdapterColorSpace? resolve({
    TargetPlatform platform = TargetPlatform.android,
    bool enabled = true,
    bool isHdr10 = true,
    bool isHlg = false,
    DisplayCapabilities display = hdr10,
    bool channelCanCarryHdr = true,
  }) =>
      HdrOutputPolicy.resolve(
        platform: platform,
        enabled: enabled,
        isHdr10: isHdr10,
        isHlg: isHlg,
        display: display,
        channelCanCarryHdr: channelCanCarryHdr,
      );

  group('HdrOutputPolicy.resolve（非 DV HDR × 显示 × 载体）', () {
    test('HDR10 + 支持 HDR10 + 载体可载 HDR → bt2100PQ（真 HDR10）', () {
      expect(resolve(), AdapterColorSpace.bt2100PQ);
    });

    test('HLG + 支持 HLG + 载体可载 HDR → bt2100hlg（真 HLG）', () {
      expect(
        resolve(isHdr10: false, isHlg: true, display: hlg),
        AdapterColorSpace.bt2100hlg,
      );
      expect(
        resolve(isHdr10: false, isHlg: true, display: both),
        AdapterColorSpace.bt2100hlg,
      );
    });

    test('载体为 Flutter 纹理（不能载 HDR）→ bt709，即便屏支持 HDR', () {
      expect(
        resolve(channelCanCarryHdr: false),
        AdapterColorSpace.bt709,
      );
    });

    test('SDR 显示 → bt709（显式 tone map）', () {
      expect(resolve(display: sdr), AdapterColorSpace.bt709);
      expect(
        resolve(isHdr10: false, isHlg: true, display: sdr),
        AdapterColorSpace.bt709,
      );
    });

    test('HDR10 内容但屏仅支持 HLG → 不误判 HDR10，回落 bt709', () {
      expect(resolve(display: hlg), AdapterColorSpace.bt709);
    });

    test('非 HDR 内容 → null（不设置）', () {
      expect(resolve(isHdr10: false, isHlg: false), isNull);
    });

    test('开关关闭（hdrGlWorkaround=false）→ null，保持 A/B 基线', () {
      expect(resolve(enabled: false), isNull);
    });

    test('非 Android → null（iOS Erika / Windows media_kit 不经此策略）', () {
      for (final p in [
        TargetPlatform.iOS,
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(resolve(platform: p), isNull, reason: '$p');
      }
    });
  });

  group('媒体流 HLG 判定（MediaStream.isHLG）', () {
    test('VideoRangeType=HLG → isHLG 且不计入 isHDR（历史语义）', () {
      final s = MediaStream.fromJson(const {
        'Type': 'Video',
        'VideoRangeType': 'HLG',
      });
      expect(s.isHLG, isTrue);
      expect(s.isHDR, isFalse);
    });

    test('传输特性 arib-std-b67 → isHLG', () {
      final s = MediaStream.fromJson(const {
        'Type': 'Video',
        'ColorTransfer': 'arib-std-b67',
      });
      expect(s.isHLG, isTrue);
    });

    test('HDR10（VideoRangeType）→ isHLG 为 false', () {
      final s = MediaStream.fromJson(const {
        'Type': 'Video',
        'VideoRangeType': 'HDR10',
      });
      expect(s.isHLG, isFalse);
      expect(s.isHDR, isTrue);
    });
  });
}
