import 'dart:io';

/// 解码模式服务 — 基于平台静态判断，适配 fvp/libmdk
class DecodeModeService {
  /// 根据解码模式返回 fvp 的 videoDecoders 列表
  ///
  /// - auto: 自适应，优先硬解，失败回退软解
  /// - hw: 纯硬解，失败不回退
  /// - sw: 纯软解
  static List<String> resolveDecoders(String mode) {
    switch (mode) {
      case 'sw':
        return ['FFmpeg'];
      case 'hw':
        return _platformHwOnlyDecoders();
      case 'auto':
      default:
        return _platformAutoDecoders();
    }
  }

  /// 平台硬解器（不含 FFmpeg 回退，纯硬解）
  static List<String> _platformHwOnlyDecoders() {
    if (Platform.isAndroid) return ['AMediaCodec'];
    if (Platform.isIOS || Platform.isMacOS) return ['VT'];
    if (Platform.isWindows) return ['D3D11', 'DXVA'];
    if (Platform.isLinux) return ['VAAPI', 'VDPAU'];
    return ['FFmpeg'];
  }

  /// 平台自适应解码器（优先硬解，失败回退软解）
  static List<String> _platformAutoDecoders() {
    if (Platform.isAndroid) return ['AMediaCodec', 'FFmpeg'];
    if (Platform.isIOS || Platform.isMacOS) return ['VT', 'FFmpeg'];
    if (Platform.isWindows) return ['D3D11', 'DXVA', 'FFmpeg'];
    if (Platform.isLinux) return ['VAAPI', 'VDPAU', 'FFmpeg'];
    return ['FFmpeg'];
  }

  /// 根据解码模式返回 fvp 的 audioDecoders 列表。
  ///
  /// 音频硬解器（mdk Decoders wiki）：Android=AMediaCodec、
  /// Windows=MFT、OHOS=OH；Apple 平台 mdk 无音频硬解（VT 仅视频），
  /// 恒为 FFmpeg 软解。
  ///
  /// Android 上不接线音频硬解时 mdk 默认直接 FFmpeg 软解 EAC3 等，
  /// 音频钟抖动会让视频按 avsync 成簇判迟到丢帧（1.1.186 诊断结论），
  /// 故 auto/hw 档优先 AMediaCodec，FFmpeg 兜底保证兼容。
  static List<String> resolveAudioDecoders(String mode) {
    switch (mode) {
      case 'sw':
        return ['FFmpeg'];
      case 'hw':
        return _platformHwOnlyAudioDecoders();
      case 'auto':
      default:
        return _platformAutoAudioDecoders();
    }
  }

  /// 平台音频硬解器（不含 FFmpeg 回退，纯硬解）
  static List<String> _platformHwOnlyAudioDecoders() {
    if (Platform.isAndroid) return ['AMediaCodec'];
    if (Platform.isWindows) return ['MFT'];
    return ['FFmpeg'];
  }

  /// 平台自适应音频解码器（优先硬解，失败回退软解）
  static List<String> _platformAutoAudioDecoders() {
    if (Platform.isAndroid) return ['AMediaCodec', 'FFmpeg'];
    if (Platform.isWindows) return ['MFT', 'FFmpeg'];
    return ['FFmpeg'];
  }
}
