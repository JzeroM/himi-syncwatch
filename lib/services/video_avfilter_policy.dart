/// 视频尺寸规范化滤镜策略（**v1.1.74 起停用生成**，E4 实验）。
///
/// 沿革：
/// - **v1.1.70 实装**（mdk 0.36.0）：非标尺寸（如 3840x1598）不加滤镜时
///   mdk renderer 持续丢帧（`VideoFrame ... not rendered`）全黑，
///   `scale=ceil16:flags=neighbor` 对齐后恢复；对齐尺寸零干预；
/// - **v1.1.73**（mdk 0.36.0 → 0.39.0）：同一滤镜反成黑屏因——非标
///   资源全平台 × 全档黑屏，而不触发滤镜的标尺寸资源全部正常（疑
///   0.39.0 `FFmpeg: Guess color space, fix scale error` 滤镜链回归）；
/// - **v1.1.74 / E4**：去滤镜直接出画验证（O1）→ 停用生成；mdk 0.39.0
///   原生处理非标尺寸，滤镜既不必要又有害。
///
/// 恢复路径：如 mdk 修复滤镜链后需重新启用，参考 git 历史 v1.1.73 及
/// 以前版本中的 ceil16 对齐实现。
///
/// 纯 Dart、无插件依赖，便于单测。
class VideoAvfilterPolicy {
  const VideoAvfilterPolicy._();

  /// 恒为 null：任何尺寸均不写 `video.avfilter`。
  ///
  /// 参数保留以兼容调用方签名（[width]/[height] 现仅作文档语义）。
  static String? resolve(int width, int height) => null;
}
