import 'dart:ui';

/// 渲染目标尺寸夹紧（fvp 纹理/SurfaceView buffer 的减载计算）。
///
/// 高分辨率内容（如 4K60）在弱 GPU 设备上以原生尺寸过 GL/Flutter 纹理会
/// 导致丢帧；把渲染目标 contain-fit 到显示器物理尺寸可显著减载（像素量
/// 最多降为 1/4），而画质几乎无损（显示器物理像素就那么多）。
///
/// 规则：
/// - contain-fit：保持视频宽高比，不裁剪；
/// - **不放大**：视频已小于等于显示尺寸时返回 null（调用方保持原生
///   尺寸——夹紧无意义且多一次换算）；
/// - 下限保护：任一边小于 [minSide]（默认 480）时按比例放大回下限，
///   避免极端纵横比把纹理夹到不可用尺寸。
class RenderTargetClamp {
  const RenderTargetClamp._();

  /// 把 [videoSize] contain-fit 到 [displayPhysical]。
  ///
  /// 返回夹紧后的目标尺寸；视频未超过显示尺寸（含任一边相等）返回
  /// null，表示「无需夹紧，保持原生」。
  static Size? compute({
    required Size displayPhysical,
    required Size videoSize,
    double minSide = 480,
  }) {
    final dw = displayPhysical.width;
    final dh = displayPhysical.height;
    final vw = videoSize.width;
    final vh = videoSize.height;
    if (dw <= 0 || dh <= 0 || vw <= 0 || vh <= 0) return null;
    // 不放大：视频在显示尺寸内（两个维度都 ≤）→ 无需夹紧
    if (vw <= dw && vh <= dh) return null;

    final videoAspect = vw / vh;
    var w = dw;
    var h = w / videoAspect;
    if (h > dh) {
      h = dh;
      w = h * videoAspect;
    }
    // 下限保护：contain-fit 后短边过小（极端纵横比）时按比例放大回
    // minSide——但绝不超过原生尺寸（超过即变放大，违背夹紧语义；
    // 原生本身就低于下限的保持 contain-fit 结果即可）。
    if (w < minSide && minSide < vw) {
      w = minSide;
      h = w / videoAspect;
    }
    if (h < minSide && minSide < vh) {
      h = minSide;
      w = h * videoAspect;
    }
    // 夹紧后反而不小于原生（防御性）→ 视为无需夹紧
    if (w >= vw && h >= vh) return null;
    return Size(w, h);
  }
}
