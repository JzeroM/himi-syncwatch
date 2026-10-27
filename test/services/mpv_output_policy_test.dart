import 'package:flutter_test/flutter_test.dart';
import 'package:himi_mpv_core/himi_mpv_core.dart';

void main() {
  group('MpvOutputPolicy', () {
    test('HDR 内容始终走原生 Surface', () {
      expect(
        MpvOutputPolicy.useNativeSurface(
          contentHdr: true,
          textureCapable: true,
        ),
        isTrue,
      );
      expect(
        MpvOutputPolicy.useNativeSurface(
          contentHdr: true,
          textureCapable: false,
        ),
        isTrue,
      );
    });

    test('SDR 优先纹理，纹理不可用才直出', () {
      expect(
        MpvOutputPolicy.useNativeSurface(
          contentHdr: false,
          textureCapable: true,
        ),
        isFalse,
      );
      expect(
        MpvOutputPolicy.useNativeSurface(
          contentHdr: false,
          textureCapable: false,
        ),
        isTrue,
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
