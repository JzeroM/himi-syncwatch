import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/widgets/tmdb_disc_shape.dart';

void main() {
  test('中心到侧边逐渐收窄并保持内容形变不超过 3%', () {
    final center = TmdbDiscStickerShape.fromOffset(0);
    final middle = TmdbDiscStickerShape.fromOffset(0.5);
    final side = TmdbDiscStickerShape.fromOffset(1);
    final left = TmdbDiscStickerShape.fromOffset(-1);

    expect(center.progress, 0);
    expect(middle.progress, closeTo(0.5, 0.0001));
    expect(side.progress, 1);
    expect(center.topWidthFactor, 0.60);
    expect(middle.topWidthFactor, closeTo(0.535, 0.0001));
    expect(side.topWidthFactor, 0.47);
    expect(center.bottomWidthFactor, 1);
    expect(side.bottomWidthFactor, 0.94);
    expect(center.contentScaleX, 1);
    expect(side.contentScaleX, closeTo(0.97, 0.0001));
    expect(center.contentSkewX, 0);
    expect(side.contentSkewX, closeTo(0.03, 0.0001));
    expect(left.contentSkewX, closeTo(-0.03, 0.0001));
  });

  test('贴纸路径包含中心且左右方向镜像', () {
    const size = Size(140, 160);
    final center = TmdbDiscStickerShape.fromOffset(0).buildClipPath(size);
    final left = TmdbDiscStickerShape.fromOffset(-1).buildClipPath(size);
    final right = TmdbDiscStickerShape.fromOffset(1).buildClipPath(size);
    const middle = Offset(70, 80);

    expect(center.contains(middle), isTrue);
    expect(left.contains(middle), isTrue);
    expect(right.contains(middle), isTrue);
    expect(center.contains(Offset.zero), isFalse);
    expect(left.contains(Offset.zero), isFalse);
    expect(right.contains(Offset.zero), isFalse);

    final leftBounds = left.getBounds();
    final rightBounds = right.getBounds();
    expect(leftBounds.left, closeTo(size.width - rightBounds.right, 0.1));
    expect(leftBounds.right, closeTo(size.width - rightBounds.left, 0.1));
  });
}
