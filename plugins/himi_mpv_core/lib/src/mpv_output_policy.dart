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

/// MPV 最终输出决策。
class MpvOutputDecision {
  const MpvOutputDecision({
    required this.nativeSurface,
    required this.hdrOutput,
  });

  /// 是否使用平台原生 Surface（而不是 Flutter 纹理）。
  final bool nativeSurface;

  /// 是否向 mpv 请求 HDR 输出。只有 Surface + HDR 内容 + HDR 显示才为 true。
  final bool hdrOutput;

  @override
  String toString() =>
      'MpvOutputDecision(nativeSurface=$nativeSurface, hdrOutput=$hdrOutput)';
}

/// MPV 输出策略：视频路径显式选择，不再按 HDR 自动切换载体。
class MpvOutputPolicy {
  const MpvOutputPolicy._();

  static const surface = 'surface';
  static const texture = 'texture';

  static String normalizeVideoOutput(String? value) =>
      value == texture ? texture : surface;

  /// 平台默认路径：Android/鸿蒙 Surface；Windows 当前仍默认 Texture。
  static String effectiveVideoOutput({
    required String configured,
    required bool userSet,
    required bool windows,
  }) {
    if (windows && !userSet) return texture;
    return normalizeVideoOutput(configured);
  }

  /// 根据用户路径、内容 HDR 与显示 HDR 能力计算最终输出。
  static MpvOutputDecision resolve({
    required String videoOutput,
    required bool contentHdr,
    required bool displayHdr,
    bool forceNativeSurface = false,
  }) {
    final nativeSurface =
        forceNativeSurface || normalizeVideoOutput(videoOutput) == surface;
    return MpvOutputDecision(
      nativeSurface: nativeSurface,
      hdrOutput: nativeSurface && contentHdr && displayHdr,
    );
  }
}
