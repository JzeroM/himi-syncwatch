import 'package:flutter_test/flutter_test.dart';
import 'package:himi_mpv_core/himi_mpv_core.dart';

void main() {
  group('MpvOutputPolicy', () {
    test('Android/鸿蒙 Surface + HDR 内容 + HDR 显示才直出', () {
      final d = MpvOutputPolicy.resolve(
        videoOutput: MpvOutputPolicy.surface,
        contentHdr: true,
        displayHdr: true,
      );
      expect(d.nativeSurface, isTrue);
      expect(d.hdrOutput, isTrue);
    });

    test('Surface + HDR 内容 + 非 HDR 显示降级为 SDR tone map', () {
      final d = MpvOutputPolicy.resolve(
        videoOutput: MpvOutputPolicy.surface,
        contentHdr: true,
        displayHdr: false,
      );
      expect(d.nativeSurface, isTrue);
      expect(d.hdrOutput, isFalse);
    });

    test('Texture 永远不请求 HDR 输出', () {
      final d = MpvOutputPolicy.resolve(
        videoOutput: MpvOutputPolicy.texture,
        contentHdr: true,
        displayHdr: true,
      );
      expect(d.nativeSurface, isFalse);
      expect(d.hdrOutput, isFalse);
    });

    test('Windows 未手动设置时默认纹理', () {
      expect(
        MpvOutputPolicy.effectiveVideoOutput(
          configured: 'surface',
          userSet: false,
          windows: true,
        ),
        'texture',
      );
      expect(
        MpvOutputPolicy.effectiveVideoOutput(
          configured: 'surface',
          userSet: true,
          windows: true,
        ),
        'surface',
      );
    });

    test('HDR 能力映射', () {
      const caps = MpvHdrCapabilities(hdr10: true, hlg: true, displayHdr: true);
      expect(caps.hdrCapable, isTrue);
      expect(caps.hdr10, isTrue);
      expect(caps.hlg, isTrue);
    });
  });
}
