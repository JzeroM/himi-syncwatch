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

    test('637：Windows 未手动设置时默认 Surface（不再默认纹理）', () {
      // 真机崩溃实证：texture 路径（vo=libmpv + VideoController）在开播
      // 首帧访问失效的 render context →
      //   libmpv-2.dll / 0xc0000005 @ mpv_render_context_render+0x1ab7c
      // 改走 Surface（gpu-next + HWND）后不再创建 render context。
      expect(
        MpvOutputPolicy.effectiveVideoOutput(
          configured: MpvOutputPolicy.surface,
          userSet: false,
          windows: true,
        ),
        MpvOutputPolicy.surface,
      );
      expect(
        MpvOutputPolicy.effectiveVideoOutput(
          configured: MpvOutputPolicy.surface,
          userSet: true,
          windows: true,
        ),
        MpvOutputPolicy.surface,
      );
    });

    test('637：Windows 显式选纹理时仍尊重用户配置', () {
      expect(
        MpvOutputPolicy.effectiveVideoOutput(
          configured: MpvOutputPolicy.texture,
          userSet: true,
          windows: true,
        ),
        MpvOutputPolicy.texture,
      );
    });

    test('637：Windows 默认配置下解析出的 decision 是 nativeSurface', () {
      final output = MpvOutputPolicy.effectiveVideoOutput(
        configured: MpvOutputPolicy.surface,
        userSet: false,
        windows: true,
      );
      final d = MpvOutputPolicy.resolve(
        videoOutput: output,
        contentHdr: false,
        displayHdr: false,
      );
      expect(d.nativeSurface, isTrue);
    });

    test('HDR 能力映射', () {
      const caps = MpvHdrCapabilities(hdr10: true, hlg: true, displayHdr: true);
      expect(caps.hdrCapable, isTrue);
      expect(caps.hdr10, isTrue);
      expect(caps.hlg, isTrue);
    });
  });
}
