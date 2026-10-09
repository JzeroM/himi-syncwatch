import 'dart:io';
import 'dart:ui' show Size;

/// 解码模式服务 — 基于平台静态判断，适配 fvp/libmdk
class DecodeModeService {
  /// Android AMediaCodec 调优属性：AImageReader 直出（best perf）+ 复用 eglimage。
  static const String androidCodecTuning = 'image=1:reuse=1';

  /// Android 硬解器名（可带调优属性）。
  static String androidHwDecoder({required bool tuning}) =>
      tuning ? 'AMediaCodec:$androidCodecTuning' : 'AMediaCodec';

  /// Apple(VT) 硬解器名（可带解码输出缩放；tuning 关/尺寸无效则不带）。
  ///
  /// `VT:width/height` 请求按物理像素输出，可减小后续 Metal 渲染与整帧
  /// blit 到 CVPixelBuffer 的开销。
  static String appleHwDecoder({required bool tuning, Size? outputSize}) {
    if (!tuning ||
        outputSize == null ||
        outputSize.width <= 0 ||
        outputSize.height <= 0) {
      return 'VT';
    }
    return 'VT:width=${outputSize.width.round()}:height=${outputSize.height.round()}';
  }

  /// 根据解码模式返回 fvp 的 videoDecoders 列表
  ///
  /// - auto: 自适应，优先硬解，失败回退软解
  /// - hw: 纯硬解，失败不回退
  /// - sw: 纯软解
  ///
  /// [decodeTuning]（默认关）：Android 硬解带 AImageReader 调优；
  /// [vtOutputSize]：iOS/macOS VT 解码输出缩放目标（物理像素）。
  static List<String> resolveDecoders(
    String mode, {
    bool decodeTuning = false,
    Size? vtOutputSize,
  }) {
    switch (mode) {
      case 'sw':
        return ['FFmpeg'];
      case 'hw':
        return _platformHwOnlyDecoders(decodeTuning, vtOutputSize);
      case 'auto':
      default:
        return _platformAutoDecoders(decodeTuning, vtOutputSize);
    }
  }

  /// 平台硬解器（不含 FFmpeg 回退，纯硬解）
  static List<String> _platformHwOnlyDecoders(bool tuning, Size? vt) {
    if (Platform.isAndroid) return [androidHwDecoder(tuning: tuning)];
    if (Platform.isIOS || Platform.isMacOS) {
      return [appleHwDecoder(tuning: tuning, outputSize: vt)];
    }
    if (Platform.isWindows) return ['D3D11', 'DXVA'];
    if (Platform.isLinux) return ['VAAPI', 'VDPAU'];
    return ['FFmpeg'];
  }

  /// 平台自适应解码器（优先硬解，失败回退软解）
  static List<String> _platformAutoDecoders(bool tuning, Size? vt) {
    if (Platform.isAndroid) {
      return [androidHwDecoder(tuning: tuning), 'FFmpeg'];
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return [appleHwDecoder(tuning: tuning, outputSize: vt), 'FFmpeg'];
    }
    if (Platform.isWindows) return ['D3D11', 'DXVA', 'FFmpeg'];
    if (Platform.isLinux) return ['VAAPI', 'VDPAU', 'FFmpeg'];
    return ['FFmpeg'];
  }
}
