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

    test('656：Windows 未手动设置时默认 Surface（HDR 直出）', () {
      // 【656 修复】639 曾把 Windows 默认改成 texture，因为当时 surface
      // 灰屏（原生子 HWND 被 Flutter 不透明层遮挡）。但 646 用**原生顶层
      // 窗口**解决了遮挡，647 真机已验证 HDR 直出成功。
      //
      // 647 只改了 AppSettings.effectiveMpvVideoOutput（设置页显示），
      // 漏了本函数（实际播放判定）→ 设置页显示 Surface，实际走 texture
      // → 新用户 HDR 永远用不上。只有手动选过 Surface 的才真正 HDR 直出
      // （这就是 646 真机验证能成功的原因）。
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

    test('656：Windows 默认配置下解析出的 decision 是 nativeSurface', () {
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
