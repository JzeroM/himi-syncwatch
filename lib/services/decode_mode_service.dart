import 'dart:ffi';
import 'dart:collection';
// ignore: implementation_imports
import 'package:media_kit/ffi/ffi.dart';
// ignore: implementation_imports
import 'package:media_kit/src/player/native/core/native_library.dart';
// ignore: implementation_imports
import 'package:media_kit/generated/libmpv/bindings.dart' as generated;

/// 设备硬解码能力信息
class DeviceCodecInfo {
  final bool hasH264Hw;
  final bool hasHevcHw;
  final bool hasVp9Hw;
  final bool hasAv1Hw;
  final List<String> hwDecoders;

  const DeviceCodecInfo({
    required this.hasH264Hw,
    required this.hasHevcHw,
    required this.hasVp9Hw,
    required this.hasAv1Hw,
    required this.hwDecoders,
  });

  bool get hasAnyHw => hasH264Hw || hasHevcHw || hasVp9Hw || hasAv1Hw;
}

/// 解码模式服务 — 参考 Yamby 的智能选择方案
class DecodeModeService {
  /// 查询设备硬解能力（通过 mpv decoder-list）
  static Future<DeviceCodecInfo> queryDeviceCapabilities(int mpvHandle) async {
    try {
      final decoders = await _queryDecoders(mpvHandle);
      return DeviceCodecInfo(
        hasH264Hw: decoders.any(
            (d) => d.toLowerCase().contains('h264') && d.toLowerCase().contains('mediacodec')),
        hasHevcHw: decoders.any(
            (d) => d.toLowerCase().contains('hevc') && d.toLowerCase().contains('mediacodec')),
        hasVp9Hw: decoders.any(
            (d) => d.toLowerCase().contains('vp9') && d.toLowerCase().contains('mediacodec')),
        hasAv1Hw: decoders.any(
            (d) => d.toLowerCase().contains('av1') && d.toLowerCase().contains('mediacodec')),
        hwDecoders: decoders
            .where((d) => d.toLowerCase().contains('mediacodec'))
            .toList(),
      );
    } catch (e) {
      // 查询失败时返回空能力（不影响播放）
      return const DeviceCodecInfo(
        hasH264Hw: false,
        hasHevcHw: false,
        hasVp9Hw: false,
        hasAv1Hw: false,
        hwDecoders: [],
      );
    }
  }

  /// 根据模式 + 设备能力决定 hwdec 值
  static String resolveHwdec(String mode, DeviceCodecInfo? deviceInfo) {
    switch (mode) {
      case 'auto':
        // 智能选择：有硬解能力 → auto-safe（让 mpv 选最优）；无 → 直接软解
        if (deviceInfo == null) return 'auto-safe';
        return deviceInfo.hasAnyHw ? 'auto-safe' : 'no';
      case 'hw+':
        return 'mediacodec-copy';
      case 'hw':
        return 'mediacodec';
      case 'sw':
        return 'no';
      default:
        return 'auto-safe';
    }
  }

  /// 根据模式决定 hwdec-software-fallback 值
  /// HW/HW+ 锁死不回退，智能模式允许回退
  static String resolveFallback(String mode) {
    return (mode == 'hw' || mode == 'hw+') ? 'no' : '3';
  }

  /// 从 mpv 日志判定实际解码状态
  static DecodeStatus parseLogMessage(String logText) {
    if (logText.contains('MediaCodec started successfully') ||
        logText.contains('HW-downloading from mediacodec')) {
      return DecodeStatus.hwActive;
    }
    if (logText.contains('Error while decoding frame') ||
        logText.contains('MediaCodec failed to start') ||
        logText.contains('Attempting next decoding method')) {
      return DecodeStatus.hwFailed;
    }
    return DecodeStatus.unknown;
  }

  /// 从日志文本中提取实际解码器名称
  static String? parseActualDecoder(String logText) {
    // HW-downloading from mediacodec → mediacodec-copy
    if (logText.contains('HW-downloading from mediacodec')) {
      return 'mediacodec-copy';
    }
    // Using hardware decoding (mediacodec) → mediacodec
    if (logText.contains('Using hardware decoding')) {
      final match = RegExp(r'Using hardware decoding \((\w+)\)').firstMatch(logText);
      if (match != null) return match.group(1);
    }
    // Fallback: mediacodec → no (software)
    if (logText.contains('Error while decoding frame') ||
        logText.contains('Attempting next decoding method')) {
      return 'no';
    }
    return null;
  }

  /// 内部：通过 FFI 查询 mpv decoder-list
  static Future<HashSet<String>> _queryDecoders(int handle) async {
    NativeLibrary.ensureInitialized();
    final mpv = generated.MPV(DynamicLibrary.open(NativeLibrary.path));
    final decoders = HashSet<String>();

    final name = 'decoder-list'.toNativeUtf8();
    final data = calloc<generated.mpv_node>();
    try {
      mpv.mpv_get_property(
        Pointer.fromAddress(handle),
        name.cast(),
        generated.mpv_format.MPV_FORMAT_NODE,
        data.cast(),
      );
      if (data.ref.format == generated.mpv_format.MPV_FORMAT_NODE_ARRAY) {
        for (int i = 0; i < data.ref.u.list.ref.num; i++) {
          final decoder = data.ref.u.list.ref.values[i];
          if (decoder.format == generated.mpv_format.MPV_FORMAT_NODE_MAP) {
            String? decoderName;
            for (int j = 0; j < decoder.u.list.ref.num; j++) {
              final k = decoder.u.list.ref.keys[j].cast<Utf8>().toDartString();
              final v = decoder.u.list.ref.values[j];
              if (k == 'codec' && v.format == generated.mpv_format.MPV_FORMAT_STRING) {
                decoderName ??= v.u.string.cast<Utf8>().toDartString();
              }
              if (k == 'driver' && v.format == generated.mpv_format.MPV_FORMAT_STRING) {
                decoderName ??= v.u.string.cast<Utf8>().toDartString();
              }
            }
            if (decoderName != null) {
              decoders.add(decoderName);
            }
          }
        }
      }
      mpv.mpv_free_node_contents(data);
    } finally {
      calloc.free(name);
      calloc.free(data);
    }

    return decoders;
  }
}

enum DecodeStatus { hwActive, hwFailed, unknown }
