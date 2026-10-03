import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/snapshot_probe.dart';

void main() {
  group('SnapshotProbe.avgLuminancePercent', () {
    Uint8List frame(List<int> pixel, int pixels) {
      final data = Uint8List(pixels * 4);
      for (var i = 0; i < pixels; i++) {
        data.setAll(i * 4, pixel);
      }
      return data;
    }

    test('全黑帧 → 0%（mdk 渲染输出即黑的判读依据）', () {
      expect(
          SnapshotProbe.avgLuminancePercent(frame([0, 0, 0, 255], 256)), 0.0);
    });

    test('全白帧 → 100%', () {
      expect(
        SnapshotProbe.avgLuminancePercent(frame([255, 255, 255, 255], 256)),
        closeTo(100.0, 0.001),
      );
    });

    test('灰帧 (128) → 约 50%', () {
      final lum =
          SnapshotProbe.avgLuminancePercent(frame([128, 128, 128, 0], 256));
      expect(lum, closeTo(128 / 255 * 100, 0.01));
    });

    test('默认步长 64 字节按像素边界采样（黑白各半 → 约 50%）', () {
      // 64 字节 = 16 个 BGRA 像素；前半黑后半白
      final data = Uint8List(128);
      for (var i = 64; i < 128; i++) {
        data[i] = (i % 4 == 3) ? 255 : 255; // BGRA 全 255（含 alpha）
      }
      final lum = SnapshotProbe.avgLuminancePercent(data);
      expect(lum, closeTo(50.0, 0.01), reason: '步长 64 只采样像素 0 与像素 16，应各采黑白各一次');
    });

    test('空数据与不足一个像素 → 0', () {
      expect(SnapshotProbe.avgLuminancePercent(Uint8List(0)), 0.0);
      expect(
          SnapshotProbe.avgLuminancePercent(Uint8List.fromList([1, 2])), 0.0);
    });

    test('非法 step → 0（不越界不误采）', () {
      expect(
        SnapshotProbe.avgLuminancePercent(frame([255, 255, 255, 255], 64),
            step: 2),
        0.0,
      );
    });
  });
}
