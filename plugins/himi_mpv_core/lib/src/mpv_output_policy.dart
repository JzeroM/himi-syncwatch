/// HDR 显示能力（由各平台原生探针提供）。
class MpvHdrCapabilities {
  const MpvHdrCapabilities({
    this.hdr10 = false,
    this.hlg = false,
    this.displayHdr = false,
    this.textureCapable = true,
    this.error,
  });

  final bool hdr10;
  final bool hlg;
  final bool displayHdr;

  /// 当前平台/设备的纹理输出链路是否可靠（SDR 用）。
  final bool textureCapable;

  final String? error;

  bool get hdrCapable => displayHdr || hdr10 || hlg;

  static const unknown = MpvHdrCapabilities();
}

/// 统一 MPV 输出路由：HDR 恒原生 Surface；SDR 优先纹理，纹理不可用再直出。
class MpvOutputPolicy {
  const MpvOutputPolicy._();

  static bool useNativeSurface({
    required bool contentHdr,
    required bool textureCapable,
  }) =>
      contentHdr || !textureCapable;
}
