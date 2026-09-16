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
}
