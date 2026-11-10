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

  /// 平台默认路径：Android / 鸿蒙 / **Windows 均为 Surface**。
  ///
  /// 【656：Windows 默认从 texture 改回 surface】
  ///
  /// 639 曾把 Windows 默认改成 texture，因为当时 surface **灰屏**（原生子
  /// HWND 被 Flutter 的 DirectComposition 不透明层遮挡）。639 的注释写
  /// 「后续要做 Surface + HDR 直出时，需先实现窗口挖洞（region-hole）」。
  ///
  /// 但 646 用**原生顶层窗口**（`WS_OVERLAPPEDWINDOW`，不是 Flutter 的
  /// 子窗口）解决了遮挡——不需要挖洞，因为 mpv 不再挂在 Flutter 窗口下，
  /// 而是自己拥有一个顶层窗口。646/647 真机已验证
  /// `vo=gpu-next` + `target-colorspace-hint=yes` 的 **HDR 直出成功**。
  ///
  /// 【这个 bug 为什么隐蔽】647 只改了
  /// `AppSettings.effectiveMpvVideoOutput`（设置页显示用）→ `surface`，
  /// 但本函数（**实际播放路径判定**）没同步改，仍返回 `texture`。于是：
  ///
  ///   设置页显示：视频路径 = Surface
  ///   实际播放：  走 texture（SDR tone map，HDR 永远用不上）
  ///
  /// 只有**手动选过 Surface**（`userSet == true`）的用户才真正走了 HDR
  /// 直出——这也解释了为什么 646 真机验证能成功（当时手动设置过）。
  /// 新用户 / 重装用户从未手动设置 → 默认 texture → HDR 用不上。
  ///
  /// 现在两处统一为 surface。手动选过 texture 的仍尊重用户选择。
  static String effectiveVideoOutput({
    required String configured,
    required bool userSet,
    required bool windows,
  }) {
    if (windows && !userSet) return surface;
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
