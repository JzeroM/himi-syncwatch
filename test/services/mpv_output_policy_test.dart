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

    test('639：Windows 未手动设置时回到 Texture（Surface 会灰屏）', () {
      // 真机实证：637 让 Windows 默认 Surface 后**灰屏**——有声音/字幕/进度，
      // 画面全灰：原生子 HWND 被 Flutter 不透明窗口遮挡（项目里的
      // dwm-blur / layered-alpha / region-hole 仅是探测代码，未在正常播放
      // 时启用）。texture 走 media_kit render API，不受遮挡影响。
      //
      // 注：637 的崩溃（libmpv-2.dll + 0xc0000005）已在 638 通过换掉自建
      // libmpv 解决，与渲染模式无关。
      expect(
        MpvOutputPolicy.effectiveVideoOutput(
          configured: MpvOutputPolicy.surface,
          userSet: false,
          windows: true,
        ),
        MpvOutputPolicy.texture,
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

    test('639：Windows 默认配置下解析出的 decision 不是 nativeSurface', () {
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
      expect(d.nativeSurface, isFalse);
    });

    test('HDR 能力映射', () {
      const caps = MpvHdrCapabilities(hdr10: true, hlg: true, displayHdr: true);
      expect(caps.hdrCapable, isTrue);
      expect(caps.hdr10, isTrue);
      expect(caps.hlg, isTrue);
    });
  });
}
