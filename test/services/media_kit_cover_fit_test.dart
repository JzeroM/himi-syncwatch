import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/player_core/adapters/nipa_media_kit_adapter.dart'
    show mediaKitCoverZoom;

void main() {
  test('mediaKit cover zoom 计算 16:9 视频在 20:9 容器中的 log2 倍率', () {
    final zoom = mediaKitCoverZoom(
      container: const Size(2400, 1080),
      video: const Size(1920, 1080),
    );

    expect(zoom, closeTo(0.3219, 0.0001));
  });

  test('mediaKit cover zoom 同比例容器为 0', () {
    expect(
      mediaKitCoverZoom(
        container: const Size(1920, 1080),
        video: const Size(1920, 1080),
      ),
      closeTo(0, 0.000001),
    );
  });

  test('mediaKit cover zoom 非法尺寸返回 0', () {
    expect(
      mediaKitCoverZoom(
        container: Size.zero,
        video: const Size(1920, 1080),
      ),
      0,
    );
  });
}
