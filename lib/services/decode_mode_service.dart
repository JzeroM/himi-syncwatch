import 'dart:io';

/// 解码模式服务 — 基于平台静态判断，适配 fvp/libmdk
class DecodeModeService {
  /// 根据解码模式返回 fvp 的 videoDecoders 列表
  static List<String> resolveDecoders(String mode) {
    switch (mode) {
      case 'sw':
        return ['FFmpeg'];
      case 'hw':
        return _platformHwDecoders();
      case 'hw+':
        return _platformHwDecoders();
      case 'auto':
      default:
        return _platformAutoDecoders();
    }
  }

  /// 平台硬件解码器列表（强制硬解）
  static List<String> _platformHwDecoders() {
    if (Platform.isAndroid) {
      return ['AMediaCodec', 'FFmpeg'];
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return ['VT', 'FFmpeg'];
    }
    if (Platform.isWindows) {
      return ['D3D11', 'DXVA', 'FFmpeg'];
    }
    if (Platform.isLinux) {
      return ['VAAPI', 'VDPAU', 'FFmpeg'];
    }
    return ['FFmpeg'];
  }

  /// 平台自动解码器列表（优先硬解，失败回退软解）
  static List<String> _platformAutoDecoders() {
    if (Platform.isAndroid) {
      return ['AMediaCodec', 'FFmpeg'];
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return ['VT', 'FFmpeg'];
    }
    if (Platform.isWindows) {
      return ['D3D11', 'DXVA', 'FFmpeg'];
    }
    if (Platform.isLinux) {
      return ['VAAPI', 'VDPAU', 'FFmpeg'];
    }
    return ['FFmpeg'];
  }
}
