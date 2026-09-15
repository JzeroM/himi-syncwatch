import 'dart:io';

/// 设备硬解码能力信息
class DeviceCodecInfo {
  final bool hasH264Hw;
  final bool hasHevcHw;
  final bool hasVp9Hw;
  final bool hasAv1Hw;
  final List<String> hwDecoders;
  final bool isUnknown;

  const DeviceCodecInfo({
    required this.hasH264Hw,
    required this.hasHevcHw,
    required this.hasVp9Hw,
    required this.hasAv1Hw,
    required this.hwDecoders,
    this.isUnknown = false,
  });

  /// decoder-list 查询失败时的降级状态
  const DeviceCodecInfo.unknown()
      : hasH264Hw = false,
        hasHevcHw = false,
        hasVp9Hw = false,
        hasAv1Hw = false,
        hwDecoders = const [],
        isUnknown = true;

  bool get hasAnyHw => hasH264Hw || hasHevcHw || hasVp9Hw || hasAv1Hw;
}

/// 平台 hwdec 值映射
class _PlatformHwdec {
  final String directValue; // HW 模式
  final String copyValue; // HW+ 模式
  const _PlatformHwdec(this.directValue, this.copyValue);
}

/// 解码模式服务 — 参考 Yamby 的智能选择方案，全平台适配
class DecodeModeService {
  /// 获取当前平台的 hwdec 值
  static _PlatformHwdec _platformHwdecValues() {
    if (Platform.isAndroid) {
      return const _PlatformHwdec('mediacodec', 'mediacodec-copy');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return const _PlatformHwdec('videotoolbox', 'videotoolbox-copy');
    }
    if (Platform.isWindows) {
      return const _PlatformHwdec('d3d11va', 'd3d11va-copy');
    }
    if (Platform.isLinux) {
      return const _PlatformHwdec('vaapi', 'vaapi-copy');
    }
    return const _PlatformHwdec('auto', 'auto-copy');
  }

  /// 根据模式 + 设备能力 + 平台决定解码器列表
  static List<String> resolveDecoders(String mode, DeviceCodecInfo? deviceInfo) {
    if (mode == 'sw') {
      return ['FFmpeg'];
    }

    final hw = _platformHwdecValues();

    if (mode == 'auto') {
      // 智能选择：有硬解能力 → 平台解码器
      if (deviceInfo != null && !deviceInfo.isUnknown && deviceInfo.hasAnyHw) {
        return [hw.directValue, 'FFmpeg'];
      }
      return ['auto'];
    }

    // HW / HW+ 模式
    switch (mode) {
      case 'hw+':
        return [hw.copyValue, 'FFmpeg'];
      case 'hw':
        return [hw.directValue, 'FFmpeg'];
      default:
        return ['auto'];
    }
  }

  /// 根据模式决定是否允许回退到软解
  static bool allowFallback(String mode) {
    return mode != 'hw' && mode != 'hw+';
  }

  /// 从日志文本中提取实际解码器名称（跨平台）
  static String? parseActualDecoder(String logText) {
    // fvp/MDK 日志格式不同
    if (logText.contains('Using hardware decoding')) {
      final match =
          RegExp(r'Using hardware decoding \((.+?)\)').firstMatch(logText);
      if (match != null) return match.group(1);
    }
    return null;
  }
}

enum DecodeStatus { hwActive, hwFailed, unknown }
