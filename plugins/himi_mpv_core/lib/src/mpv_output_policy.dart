/// HDR 显示能力（由各平台原生探针提供）。
class MpvHdrCapabilities {
  const MpvHdrCapabilities({
    this.hdr10 = false,
    this.hlg = false,
    this.hdrVivid = false,
    this.displayHdr = false,
    this.textureCapable = true,
    this.error,
  });

  final bool hdr10;
  final bool hlg;
  final bool hdrVivid;
  final bool displayHdr;

  /// 当前平台/设备的纹理输出链路是否可靠（SDR 用）。
  final bool textureCapable;

  final String? error;

  bool get hdrCapable => displayHdr || hdr10 || hlg || hdrVivid;

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

  /// 平台默认路径：Android / 鸿蒙默认 Surface；**Windows 默认 Texture**。
  ///
  /// Windows 为什么不能用 Surface（639 回退，真机实证）：
  /// - 637 曾让 Windows 默认 Surface（`gpu-next` + HWND），但**灰屏**：
  ///   有声音/字幕/进度，画面区域全灰——原生子 HWND 被 Flutter 不透明窗口
  ///   遮挡（见 `buildWindowsMpvTextureOptions` 的注释：texture 走
  ///   media_kit render API 正是为了避开这个遮挡）。
  /// - 项目里的透明化方案（dwm-blur / layered-alpha / region-hole）目前只是
  ///   `setTransparencyProbe` 探测代码，**未在正常播放时启用**。
  /// - 而 637 的崩溃（`libmpv-2.dll` + 0xc0000005）已在 638 通过换掉自建
  ///   libmpv（改 media_kit 官方 + shinchiro 完整版）解决，与渲染模式无关。
  ///
  /// 后续要做 Surface + HDR 直出时，需先实现窗口挖洞（region-hole）。
  /// 用户仍可在设置里显式选 Surface（`userSet == true` 时尊重配置）。
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
