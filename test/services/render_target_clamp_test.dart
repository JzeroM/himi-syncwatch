import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/render_target_clamp.dart';

void main() {
  group('RenderTargetClamp.compute', () {
    test('4K 视频 + 1080p 显示 → 夹到 1080p（16:9）', () {
      final r = RenderTargetClamp.compute(
        displayPhysical: const Size(1920, 1080),
        videoSize: const Size(3840, 2160),
      );
      expect(r, isNotNull);
      expect(r!.width, closeTo(1920, 0.001));
      expect(r.height, closeTo(1080, 0.001));
    });

    test('4K 2:1 (3840x1920) + 1080p 显示 → 宽度夹满、高度按比例', () {
      final r = RenderTargetClamp.compute(
        displayPhysical: const Size(1920, 1080),
        videoSize: const Size(3840, 1920),
      );
      expect(r, isNotNull);
      expect(r!.width, closeTo(1920, 0.001));
      expect(r.height, closeTo(960, 0.001));
    });

    test('4K 视频 + 4K 显示 → 不夹（相等不夹，保住全分辨率扫描输出）', () {
      expect(
        RenderTargetClamp.compute(
          displayPhysical: const Size(3840, 2160),
          videoSize: const Size(3840, 2160),
        ),
        isNull,
      );
    });

    test('4K 2:1 + 4K 16:9 显示 → 不夹（宽相等、高在内）', () {
      expect(
        RenderTargetClamp.compute(
          displayPhysical: const Size(3840, 2160),
          videoSize: const Size(3840, 1920),
        ),
        isNull,
      );
    });

    test('1080p 视频 + 4K 显示 → 不夹（不放大）', () {
      expect(
        RenderTargetClamp.compute(
          displayPhysical: const Size(3840, 2160),
          videoSize: const Size(1920, 1080),
        ),
        isNull,
      );
    });

    test('1080p 视频 + 1080p 显示 → 不夹', () {
      expect(
        RenderTargetClamp.compute(
          displayPhysical: const Size(1920, 1080),
          videoSize: const Size(1920, 1080),
        ),
        isNull,
      );
    });

    test('8K 视频 + 4K 显示 → 夹到 4K', () {
      final r = RenderTargetClamp.compute(
        displayPhysical: const Size(3840, 2160),
        videoSize: const Size(7680, 4320),
      );
      expect(r, isNotNull);
      expect(r!.width, closeTo(3840, 0.001));
      expect(r.height, closeTo(2160, 0.001));
    });

    test('4K 竖屏 (2160x3840) + 1080p 横屏显示 → 高度夹满、宽度按比例', () {
      final r = RenderTargetClamp.compute(
        displayPhysical: const Size(1920, 1080),
        videoSize: const Size(2160, 3840),
      );
      expect(r, isNotNull);
      expect(r!.height, closeTo(1080, 0.001));
      expect(r.width, closeTo(607.5, 0.001));
    });

    test('下限保护：原生高于 minSide 时短边按比例放大回下限，且不超过原生', () {
      // 5000x1080 → 夹到 1920 宽时高 414.7 < 480，且原生高 1080 > 480
      // → 放大回高 480、宽按比例 2222.2（仍小于原生 5000）
      final r = RenderTargetClamp.compute(
        displayPhysical: const Size(1920, 1080),
        videoSize: const Size(5000, 1080),
      );
      expect(r, isNotNull);
      expect(r!.height, closeTo(480, 0.001));
      expect(r.width, closeTo(480 * (5000 / 1080), 0.001));
    });

    test('下限保护：原生本身低于 minSide → 不放大，保持 contain-fit', () {
      // 10000x100 原生高 100 < 480 → 不触发 bump（bump 会超原生）
      final r = RenderTargetClamp.compute(
        displayPhysical: const Size(1920, 1080),
        videoSize: const Size(10000, 100),
      );
      expect(r, isNotNull);
      expect(r!.width, closeTo(1920, 0.001));
      expect(r.height, closeTo(19.2, 0.001));
    });

    test('无效输入（零/负尺寸）→ null', () {
      expect(
        RenderTargetClamp.compute(
          displayPhysical: Size.zero,
          videoSize: const Size(3840, 2160),
        ),
        isNull,
      );
      expect(
        RenderTargetClamp.compute(
          displayPhysical: const Size(1920, 1080),
          videoSize: Size.zero,
        ),
        isNull,
      );
      expect(
        RenderTargetClamp.compute(
          displayPhysical: const Size(-1, 1080),
          videoSize: const Size(3840, 2160),
        ),
        isNull,
      );
    });

    test('手机 1080x2400 竖屏物理 + 4K16:9 → 夹到宽 1080', () {
      final r = RenderTargetClamp.compute(
        displayPhysical: const Size(1080, 2400),
        videoSize: const Size(3840, 2160),
      );
      expect(r, isNotNull);
      expect(r!.width, closeTo(1080, 0.001));
      expect(r.height, closeTo(607.5, 0.001));
    });

    test('手机横屏物理 2400x1080 + 4K16:9 → 夹到高 1080', () {
      final r = RenderTargetClamp.compute(
        displayPhysical: const Size(2400, 1080),
        videoSize: const Size(3840, 2160),
      );
      expect(r, isNotNull);
      expect(r!.height, closeTo(1080, 0.001));
      expect(r.width, closeTo(1920, 0.001));
    });
  });
}
