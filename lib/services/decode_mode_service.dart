import 'dart:ffi';
import 'dart:collection';
import 'dart:io';
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

  /// 查询设备硬解能力（通过 mpv decoder-list）
  static Future<DeviceCodecInfo> queryDeviceCapabilities(int mpvHandle) async {
    try {
      final decoders = await _queryDecoders(mpvHandle);
      if (decoders.isEmpty) {
        return const DeviceCodecInfo.unknown();
      }
      return DeviceCodecInfo(
        hasH264Hw: decoders.any(
            (d) => d.startsWith('h264_') && _isHwDecoder(d)),
        hasHevcHw: decoders.any(
            (d) => d.startsWith('hevc_') && _isHwDecoder(d)),
        hasVp9Hw: decoders.any(
            (d) => d.startsWith('vp9_') && _isHwDecoder(d)),
        hasAv1Hw: decoders.any(
            (d) => d.startsWith('av1_') && _isHwDecoder(d)),
        hwDecoders: decoders.where((d) => _isHwDecoder(d)).toList(),
      );
    } catch (_) {
      return const DeviceCodecInfo.unknown();
    }
  }

  /// 判断 decoder-list 中的名称是否为硬件解码器（跨平台）
  static bool _isHwDecoder(String name) {
    return name.contains('_mediacodec') ||
        name.contains('_videotoolbox') ||
        name.contains('_d3d11va') ||
        name.contains('_vaapi') ||
        name.contains('_nvdec') ||
        name.contains('_vdpau');
  }

  /// 根据模式 + 设备能力 + 平台决定 hwdec 值
  static String resolveHwdec(String mode, DeviceCodecInfo? deviceInfo) {
    if (mode == 'sw') return 'no';

    final hw = _platformHwdecValues();

    if (mode == 'auto') {
      // 智能选择：有硬解能力 → 平台直通值（mpv 失败会自动重试其他方法）
      // 无硬解或查询失败 → auto-safe（mpv 安全选择）
      if (deviceInfo != null && !deviceInfo.isUnknown && deviceInfo.hasAnyHw) {
        return hw.directValue;
      }
      return 'auto-safe';
    }

    // HW / HW+ 模式：根据平台返回正确值
    switch (mode) {
      case 'hw+':
        return hw.copyValue;
      case 'hw':
        return hw.directValue;
      default:
        return 'auto-safe';
    }
  }

  /// 根据模式决定 hwdec-software-fallback 值
  /// HW/HW+ 锁死不回退，智能模式允许回退
  static String resolveFallback(String mode) {
    return (mode == 'hw' || mode == 'hw+') ? 'no' : '3';
  }

  /// 从 mpv 日志判定实际解码状态（跨平台）
  static DecodeStatus parseLogMessage(String logText) {
    // 通用成功：所有平台都输出 "Using hardware decoding (XXX)"
    if (logText.contains('Using hardware decoding')) {
      return DecodeStatus.hwActive;
    }
    // Android 专属成功
    if (logText.contains('MediaCodec started successfully') ||
        logText.contains('HW-downloading from mediacodec')) {
      return DecodeStatus.hwActive;
    }
    // 通用失败
    if (logText.contains('Error while decoding frame') ||
        logText.contains('Attempting next decoding method')) {
      return DecodeStatus.hwFailed;
    }
    return DecodeStatus.unknown;
  }

  /// 从日志文本中提取实际解码器名称（跨平台）
  static String? parseActualDecoder(String logText) {
    // 通用成功日志：所有平台都输出 "Using hardware decoding (XXX)"
    if (logText.contains('Using hardware decoding')) {
      final match =
          RegExp(r'Using hardware decoding \((\w+)\)').firstMatch(logText);
      if (match != null) return match.group(1);
    }
    // Android 专属：HW-downloading from mediacodec
    if (logText.contains('HW-downloading from mediacodec')) {
      return 'mediacodec-copy';
    }
    // 失败日志
    if (logText.contains('Error while decoding frame') ||
        logText.contains('Attempting next decoding method')) {
      return 'no';
    }
    return null;
  }

  /// 内部：通过 FFI 查询 mpv decoder-list（带错误检查）
  static Future<HashSet<String>> _queryDecoders(int handle) async {
    NativeLibrary.ensureInitialized();
    final mpv = generated.MPV(DynamicLibrary.open(NativeLibrary.path));
    final decoders = HashSet<String>();

    final name = 'decoder-list'.toNativeUtf8();
    final data = calloc<generated.mpv_node>();
    try {
      final result = mpv.mpv_get_property(
        Pointer.fromAddress(handle),
        name.cast(),
        generated.mpv_format.MPV_FORMAT_NODE,
        data.cast(),
      );
      // 检查返回值：负数表示错误
      if (result < 0) {
        return decoders;
      }
      if (data.ref.format == generated.mpv_format.MPV_FORMAT_NODE_ARRAY) {
        for (int i = 0; i < data.ref.u.list.ref.num; i++) {
          final decoder = data.ref.u.list.ref.values[i];
          if (decoder.format == generated.mpv_format.MPV_FORMAT_NODE_MAP) {
            String? codec;
            String? driver;
            for (int j = 0; j < decoder.u.list.ref.num; j++) {
              final k =
                  decoder.u.list.ref.keys[j].cast<Utf8>().toDartString();
              final v = decoder.u.list.ref.values[j];
              if (v.format != generated.mpv_format.MPV_FORMAT_STRING) continue;
              final val = v.u.string.cast<Utf8>().toDartString();
              if (k == 'codec') codec = val;
              if (k == 'driver') driver = val;
            }
            // 拼接为 mpv 标准格式: "h264_mEDIACODEC"
            if (codec != null && driver != null) {
              decoders.add('${codec}_$driver'.toLowerCase());
            } else if (codec != null) {
              decoders.add(codec);
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
