import 'dart:typed_data';

/// mdk `Player.snapshot()` 截帧取证。
///
/// 黑屏分叉判读：截帧非黑 → mdk 已渲染出帧，问题在 Flutter 合成侧
/// （SurfaceView 通道可解）；截帧全黑/null → mdk 渲染输出即黑
/// （tunnel/解码侧问题）。
class SnapshotProbe {
  /// BGRA 原始数据的平均亮度（0-100）。
  ///
  /// [step] 为采样字节步长（应为 4 的倍数，对齐 BGRA 像素边界），
  /// 默认 64 字节 = 每 16 像素采样 1 个，兼顾速度与代表性。
  static double avgLuminancePercent(Uint8List bgra, {int step = 64}) {
    if (bgra.length < 3 || step < 4) return 0;
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i + 2 < bgra.length; i += step) {
      // BGRA: i=B, i+1=G, i+2=R
      sum += (bgra[i] + bgra[i + 1] + bgra[i + 2]) / 3;
      count++;
    }
    if (count == 0) return 0;
    return sum / count / 255 * 100;
  }
}
