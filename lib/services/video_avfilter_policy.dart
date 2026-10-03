/// 视频尺寸规范化滤镜（v1.1.70 实验：非标尺寸黑屏验证/规避）。
///
/// 真机对照（H96_Max_RK3528，v1.1.69 截图+日志）：
/// - `3840x1598` HEVC → 直写档建立后仍全黑，帧被 mdk renderer 持续
///   丢弃（`VideoFrame ... not rendered`）；
/// - `3840x2160` HEVC / 普通 1080p → 正常出画。
///
/// 判定分两级（实测集合反推，最小干预）：
/// - **触发**：任一维非 **8** 对齐——1080p（1080/8=135）与 4K
///   （2160/8=270）全部放行不写属性，仅 1598（1598/8=199.75）等
///   真非标尺寸触发，正常片源零干预；
/// - **目标**：触发后两维均 **ceil 到 16**（宏块粒度假设：1598→1600，
///   拉伸 0.125% 不可感知），得到的滤镜串写入 `video.avfilter`。
///
/// `flags=neighbor` 对齐 fvp#333 实证用法，代价最低。
/// 纯 Dart、无插件依赖，便于单测。
class VideoAvfilterPolicy {
  const VideoAvfilterPolicy._();

  /// 尺寸 [width]x[height] 需要规范化时返回滤镜串，否则返回 null。
  ///
  /// - 宽高均为 8 的倍数 → null（不写属性，对既有播放零影响）；
  /// - 任一维非 8 对齐 → `scale=<ceil16w>:<ceil16h>:flags=neighbor`；
  /// - 非法尺寸（<=0）→ null。
  static String? resolve(int width, int height) {
    if (width <= 0 || height <= 0) return null;
    if (width % 8 == 0 && height % 8 == 0) return null;
    return 'scale=${_ceil16(width)}:${_ceil16(height)}:flags=neighbor';
  }

  static int _ceil16(int v) => (v + 15) ~/ 16 * 16;
}
