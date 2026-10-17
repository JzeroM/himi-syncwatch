import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';

import 'dolby_vision_service.dart';

/// 显示器 HDR 能力（原生探针，DisplayCapabilityPlugin 分发）。
class DisplayCapabilities {
  const DisplayCapabilities({
    this.hdrTypes = const [],
    this.hdr = false,
    this.maxLuminance,
    this.error,
  });

  /// 支持类型：hdr10 / hlg / dolbyVision / hdr10Plus。
  final List<String> hdrTypes;

  /// 当前输出模式是否 HDR（Display#isHdr，API 24+）。
  final bool hdr;

  /// 期望峰值亮度（nits，Display#HdrCapabilities）。
  final double? maxLuminance;

  final String? error;

  bool get supportsHdr10 => hdrTypes.contains('hdr10');
  bool get supportsHlg => hdrTypes.contains('hlg');
  bool get supportsDolbyVision => hdrTypes.contains('dolbyVision');

  /// 显示是否具备 HDR 输出能力（当前 HDR 模式或声明任意 HDR 类型）。
  bool get hdrCapable => hdr || hdrTypes.isNotEmpty;

  static const unknown = DisplayCapabilities();

  factory DisplayCapabilities.fromMap(Map<Object?, Object?> m) =>
      DisplayCapabilities(
        hdrTypes: ((m['hdrTypes'] as List<Object?>?) ?? const [])
            .whereType<String>()
            .toList(growable: false),
        hdr: m['hdr'] as bool? ?? false,
        maxLuminance: (m['maxLuminance'] as num?)?.toDouble(),
        error: m['displayError'] as String?,
      );

  String get display {
    if (error != null) return '探测失败: $error';
    if (hdrTypes.isEmpty && !hdr) return '不支持（SDR 显示）';
    final types = hdrTypes.isEmpty ? ['当前 HDR 模式'] : hdrTypes;
    final lum = maxLuminance != null
        ? ' · 峰值 ${maxLuminance!.round()}nits'
        : '';
    return '${types.join('/')}$lum';
  }
}

/// GL/EGL 能力探针结果（自建同款 EGL 上下文实测，非 mdk 日志推断）。
class GlCapabilities {
  const GlCapabilities({
    this.tested = false,
    this.eglOk = false,
    this.chooseConfigOk = false,
    this.renderer,
    this.glVersion,
    this.textureR16Ok = false,
    this.textureRgba16fOk = false,
    this.textureRgb10a2Ok = false,
    this.error,
  });

  /// 是否真实取得原生 GL 探针结果（false = 超时/通道不可用，
  /// 此时 [eglOk] 等字段无意义，不得据以判定「EGL 故障」）。
  final bool tested;

  /// EGL 初始化 + config + context + pbuffer 全链路可用。
  final bool eglOk;
  final bool chooseConfigOk;

  /// GL_RENDERER 串（如 Mali-450 MP）。
  final String? renderer;
  final String? glVersion;

  /// 10-bit 纹理上传测试（16x16 glTexImage2D + glGetError）。
  final bool textureR16Ok;
  final bool textureRgba16fOk;
  final bool textureRgb10a2Ok;

  final String? error;

  /// 任一 10-bit/FP16 纹理格式可上传即视为 10-bit GL 纹理可用。
  bool get tenBitTextureOk =>
      textureR16Ok || textureRgba16fOk || textureRgb10a2Ok;

  static const unknown = GlCapabilities();

  factory GlCapabilities.fromMap(Map<Object?, Object?> m) => GlCapabilities(
        tested: true,
        eglOk: m['eglOk'] as bool? ?? false,
        chooseConfigOk: m['chooseConfigOk'] as bool? ?? false,
        renderer: m['renderer'] as String?,
        glVersion: m['glVersion'] as String?,
        textureR16Ok: m['textureR16Ok'] as bool? ?? false,
        textureRgba16fOk: m['textureRgba16fOk'] as bool? ?? false,
        textureRgb10a2Ok: m['textureRgb10a2Ok'] as bool? ?? false,
        error: m['error'] as String?,
      );

  String get display {
    if (!tested) return '未探测';
    if (!eglOk) return 'EGL 不可用${error != null ? '（$error）' : ''}';
    final tenBit = tenBitTextureOk
        ? '10-bit 纹理可用'
        : '10-bit 纹理不可用（R16/16F/RGB10A2 均失败）';
    return 'EGL 正常 · $tenBit'
        '${renderer != null ? ' · $renderer' : ''}';
  }
}

/// 设备能力画像：启动评估一次，供 HDR 路由 / 输出决策 / 配置页展示共用。
class DeviceProfile {
  const DeviceProfile({
    this.android = false,
    this.abi = '',
    this.is64Bit = false,
    this.sdkInt,
    this.soc,
    this.display = DisplayCapabilities.unknown,
    this.gl = GlCapabilities.unknown,
    this.vulkanVersion,
    this.hevcHdr10 = false,
    this.dvDecode,
    this.probed = false,
    this.error,
  });

  final bool android;
  final String abi;
  final bool is64Bit;
  final int? sdkInt;
  final String? soc;
  final DisplayCapabilities display;
  final GlCapabilities gl;

  /// 打包版本号（major<<22 | minor<<12 | patch），null = 无 Vulkan。
  final int? vulkanVersion;

  /// 存在声明 HEVCProfileMain10HDR10(_Plus) 的硬件解码器。
  final bool hevcHdr10;

  /// 杜比视界解码器探测（DolbyVisionService，含软件/硬件与 profile）。
  final DvProbeResult? dvDecode;

  /// 是否已真实执行过原生探测（false = unknown 兜底/非 Android）。
  final bool probed;
  final String? error;

  static const unknown = DeviceProfile();

  bool get vulkanOk => (vulkanVersion ?? 0) > 0;

  /// Vulkan 版本号解码展示（如 1.1.0 / 1.3.0）。
  String? get vulkanDisplay {
    final v = vulkanVersion;
    if (v == null || v <= 0) return null;
    return '${v >> 22}.${(v >> 12) & 0x3ff}.${v & 0xfff}';
  }

  /// 是否取得可靠的探测结论（探测执行过且未整体失败；部分字段缺失
  /// 不影响对应判定，各判定各自查看自身字段）。
  bool get _hasReliableProbe => probed && error == null;

  /// Erika Android HDR（extended-linear scRGB）前置：Vulkan + HDR 显示。
  ///
  /// 未探测或探测失败（[probed] false / [error] 非空）时对 Android
  /// 返回 true——保持历史行为（手机 HDR 走 Erika），避免探针失败把
  /// 手机路由误降级为 mdk；盒子等已探测成功且无 Vulkan/HDR 显示的
  /// 设备返回 false → mdk 直写。
  bool erikaHdrCapable(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return _hasReliableProbe ? (vulkanOk && display.hdrCapable) : true;
      case TargetPlatform.iOS:
        return true;
      default:
        return false;
    }
  }

  /// mdk 直写/tunnel HDR 透传：显示声明 HDR10/HLG/DV 任一即可
  /// （解码器直写 surface，HDR 元数据随 sideband 透传，不依赖 GL）。
  bool get mdkHdrPassthroughCapable =>
      display.supportsHdr10 ||
      display.supportsHlg ||
      display.supportsDolbyVision;

  /// GL 10-bit 纹理可用（EGL 链路正常 + 10-bit 纹理上传成功）。
  bool get gl10BitOk => gl.eglOk && gl.tenBitTextureOk;

  /// 实测到「EGL 正常但 10-bit 纹理上传全失败」：GL 渲染 10-bit 帧
  /// 不可用，输出层应强制直写。未探测/未实测/EGL 已坏均返回 false
  /// （EGL 坏由 eglFault 路径接管，不在此重复介入）。
  bool get tenBitGlBroken =>
      probed && gl.tested && gl.eglOk && !gl.tenBitTextureOk;

  /// EGL 链路不健康（探针**明确**失败，或被持久标记认定故障）。
  ///
  /// 探针未取得结果（[GlCapabilities.tested] false，如超时）不判定
  /// 故障——避免误置位直写标记。
  bool eglBroken({required bool eglFaultSeen}) =>
      eglFaultSeen || (probed && gl.tested && !gl.eglOk);

  /// 组装探针原始 map（DeviceCapabilityPlugin）。
  factory DeviceProfile.fromProbe({
    required Map<Object?, Object?> raw,
    required String abi,
    bool android = true,
    DvProbeResult? dvDecode,
  }) {
    final glRaw = raw['gl'];
    return DeviceProfile(
      android: android,
      abi: abi,
      is64Bit: abi.contains('64'),
      sdkInt: (raw['sdkInt'] as num?)?.toInt(),
      soc: raw['soc'] as String?,
      display: DisplayCapabilities.fromMap(raw),
      gl: glRaw is Map<Object?, Object?>
          ? GlCapabilities.fromMap(glRaw)
          : GlCapabilities.unknown,
      vulkanVersion: (raw['vulkanVersion'] as num?)?.toInt(),
      hevcHdr10: raw['hevcHdr10'] as bool? ?? false,
      dvDecode: dvDecode,
      probed: true,
      error: raw['probeError'] as String?,
    );
  }

  /// 供日志/卡片取证的单行摘要。
  String get summary {
    if (!probed) return '未探测';
    final parts = [
      if (android) 'ABI=$abi${is64Bit ? '(64)' : '(32)'}',
      if (soc != null) 'SoC=$soc',
      '显示=${display.display}',
      'GL=${gl.display}',
      'Vulkan=${vulkanDisplay ?? '无'}',
      'HEVC-HDR10=${hevcHdr10 ? '支持' : '不支持'}',
      if (dvDecode != null) 'DV=${dvDecode!.summary}',
      if (error != null) 'error=$error',
    ];
    return parts.join(' | ');
  }
}

/// 启动设备能力评估服务：原生探针 + DV 解码探测一次，结果供全局共享。
class DeviceProfileService {
  DeviceProfileService._();

  static final DeviceProfileService instance = DeviceProfileService._();

  static const _channel = MethodChannel('himi/device_capability');

  /// 平台判断注入点（单测在桌面 VM 运行，需覆盖才能测到 Android 分支）。
  @visibleForTesting
  static bool? isAndroidOverride;

  /// ABI 注入点（单测无法改写真实 Abi.current()）。
  @visibleForTesting
  static String? abiOverride;

  static bool get _isAndroid => isAndroidOverride ?? Platform.isAndroid;

  static String get _abi {
    final override = abiOverride;
    if (override != null) return override;
    try {
      return Abi.current().toString();
    } catch (_) {
      return 'unknown';
    }
  }

  /// 执行一次完整评估。
  ///
  /// 原生探针有 [timeout] 上限（怪驱动卡死时降级为「EGL 不可用」，
  /// 不阻塞启动）；DV 探测复用 DolbyVisionService 缓存。
  Future<DeviceProfile> probe({
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    if (!_isAndroid) {
      return DeviceProfile(abi: _abi, is64Bit: _abi.contains('64'));
    }
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('probe')
          .timeout(timeout);
      final dv = await DolbyVisionService.probe().timeout(timeout);
      return DeviceProfile.fromProbe(
        raw: raw ?? const {},
        abi: _abi,
        dvDecode: dv,
      );
    } catch (e) {
      return DeviceProfile(
        android: true,
        abi: _abi,
        is64Bit: _abi.contains('64'),
        probed: true,
        error: e.toString(),
      );
    }
  }
}
