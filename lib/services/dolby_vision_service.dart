import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// 单个 Dolby Vision 解码器的能力描述
class DvDecoder {
  const DvDecoder({
    required this.name,
    required this.mime,
    required this.dvProfiles,
    required this.isSoftware,
  });

  final String name;
  final String mime;

  /// 该解码器声明的 DV profile（0x0100 段），可能为空
  final List<int> dvProfiles;
  final bool isSoftware;

  factory DvDecoder.fromMap(Map<Object?, Object?> map) => DvDecoder(
        name: (map['name'] as String?) ?? '?',
        mime: (map['mime'] as String?) ?? '',
        dvProfiles: ((map['dvProfiles'] as List<Object?>?) ?? const [])
            .map((e) => (e as num?)?.toInt() ?? 0)
            .toList(growable: false),
        isSoftware: (map['isSoftware'] as bool?) ?? false,
      );

  /// 去掉平台前缀与厂商段，取有辨识度的部分。
  ///
  /// `c2.qti.hevc.decoder` → `hevc.decoder`
  /// `OMX.MS.HEVCDV.Decoder` → `HEVCDV`
  /// `OMX.RTK.video.decoder.tunneled` → `video.decoder.tunneled`
  String get shortName {
    var n = name;
    for (final p in const ['c2.', 'OMX.', 'omx.']) {
      if (n.startsWith(p)) {
        n = n.substring(p.length);
        break;
      }
    }
    final parts = n.split('.');
    // 去掉厂商/平台段（如 qti / MS / RTK / android），但保留有意义的后续段
    if (parts.length > 1 &&
        parts.first.length <= 8 &&
        (!_isKnownCodec(parts.first) ||
            _notVendor.contains(parts.first.toLowerCase()))) {
      parts.removeAt(0);
    }
    return parts.join('.');
  }

  static bool _isKnownCodec(String s) {
    const known = {'hevc', 'avc', 'av1', 'vp9', 'vp8', 'mpeg2', 'mpeg4'};
    return known.contains(s.toLowerCase());
  }

  /// `android` 是 Google 软件解码器的平台标记而非厂商，需与 qti/MS/RTK 一同剔除。
  static const _notVendor = {'android', 'google', 'default'};

  /// 例如 `hevc.decoder (hevc, p0103/0109)`
  String get display {
    final b = StringBuffer('$shortName (${mime.replaceFirst('video/', '')}');
    if (dvProfiles.isNotEmpty) {
      final hex =
          dvProfiles.map((p) => p.toRadixString(16).padLeft(4, '0')).join('/');
      b.write(', p$hex');
    }
    b.write(')');
    return b.toString();
  }
}

/// 设备 Dolby Vision 解码能力探测结果
class DvProbeResult {
  const DvProbeResult({
    required this.supported,
    required this.hardware,
    required this.decoders,
    this.error,
  });

  final bool supported;

  /// 存在非软件实现的 DV 解码器
  final bool hardware;
  final List<DvDecoder> decoders;
  final String? error;

  static const unknown =
      DvProbeResult(supported: false, hardware: false, decoders: []);

  String get summary {
    if (error != null) return '探测失败: $error';
    if (decoders.isEmpty) return '未发现 DV 解码器';
    final tag = hardware ? '支持硬解' : '仅软解';
    final list = decoders.take(4).map((d) => d.display).join('  ');
    return '$tag | $list';
  }
}

/// 平台预选的解码器。
///
/// 注意：这是「Android 会为该格式选谁」的**推断**，
/// 并非「mdk 实际已选中谁」的实证。两者可能因 mdk 的 DV 策略而分叉，
/// 因此调用方在展示时必须标注置信度。
class CodecSelection {
  const CodecSelection({
    this.picked,
    this.mime,
    this.isSoftware,
    this.supported = const [],
    this.dvProfiles = const [],
    this.error,
  });

  /// findDecoderForFormat 选出的 codec 名
  final String? picked;

  /// 命中时使用的 MIME（DV 场景下可能是 video/dolby-vision 或 video/hevc）
  final String? mime;

  /// [picked] 是否为软件实现
  final bool? isSoftware;

  /// 经 isFormatSupported 逐个校验后，真正吃下该格式的全部候选
  final List<String> supported;

  /// [picked] 声明的 DV profile（0x0100 段）
  final List<int> dvProfiles;

  final String? error;

  static const unknown = CodecSelection();

  bool get hasPicked => picked != null && picked!.isNotEmpty;

  String get display => hasPicked ? picked! : (error == null ? '未探测' : '探测失败');

  factory CodecSelection.fromMap(Map<Object?, Object?> map) => CodecSelection(
        picked: map['picked'] as String?,
        mime: map['mime'] as String?,
        isSoftware: map['isSoftware'] as bool?,
        supported: ((map['supported'] as List<Object?>?) ?? const [])
            .whereType<String>()
            .toList(growable: false),
        dvProfiles: ((map['dvProfiles'] as List<Object?>?) ?? const [])
            .map((e) => (e as num?)?.toInt() ?? 0)
            .toList(growable: false),
        error: map['error'] as String?,
      );
}

class DolbyVisionService {
  static const _channel = MethodChannel('com.himi/dolby_vision');

  static Future<DvProbeResult> _cached = Future.value(DvProbeResult.unknown);
  static bool _initialized = false;

  /// 平台判断注入点。生产环境为 null 时读 `Platform.isAndroid`；
  /// 单元测试运行在 desktop VM 上，需要覆盖才能测到平台通道分支。
  @visibleForTesting
  static bool? isAndroidOverride;

  static bool get _isAndroid => isAndroidOverride ?? Platform.isAndroid;

  /// 查询设备 Dolby Vision 解码能力。
  ///
  /// 探测会同时检查标准 `video/dolby-vision`、video/hevc / video/avc 的
  /// profileLevels 中声明的 DV profile，以及厂商私有 DV MIME，避免在
  /// 骁龙等平台上漏判导致上层误强制软件解码。
  static Future<DvProbeResult> probe() async {
    if (!_isAndroid) {
      return const DvProbeResult(
        supported: false,
        hardware: false,
        decoders: [],
        error: '非 Android 平台',
      );
    }
    if (_initialized) return _cached;
    final pending = _load();
    _cached = pending;
    _initialized = true;
    return pending;
  }

  static Future<DvProbeResult> _load() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getDolbyVisionInfo',
      );
      if (raw == null) return DvProbeResult.unknown;
      final list = ((raw['decoders'] as List<Object?>?) ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(DvDecoder.fromMap)
          .toList(growable: false);
      return DvProbeResult(
        supported: (raw['supported'] as bool?) ?? list.isNotEmpty,
        hardware: (raw['hardware'] as bool?) ?? false,
        decoders: list,
        error: raw['error'] as String?,
      );
    } catch (e) {
      return DvProbeResult(
        supported: false,
        hardware: false,
        decoders: [],
        error: e.toString(),
      );
    }
  }

  /// 是否支持 DV 硬件解码。探测异常时返回 false，调用方不应据此强制软件解码。
  static Future<bool> isSupported() async => (await probe()).hardware;

  /// 让平台为给定格式预选解码器。
  ///
  /// 复用 `com.himi/dolby_vision` 通道（该原生插件本就是 MediaCodec 能力探测器），
  /// 不再单开一套注册。结果随格式而变，故不做缓存。
  static Future<CodecSelection> selectDecoder({
    required String mime,
    int? width,
    int? height,
    bool dolbyVision = false,
  }) async {
    if (!_isAndroid) {
      return const CodecSelection(error: '非 Android 平台');
    }
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'selectDecoder',
        <String, Object?>{
          'mime': mime,
          'width': width,
          'height': height,
          'dolbyVision': dolbyVision,
        },
      );
      if (raw == null) return CodecSelection.unknown;
      return CodecSelection.fromMap(raw);
    } catch (e) {
      return CodecSelection(error: e.toString());
    }
  }

  /// 产物身份自证：应用版本 + 原生通道是否真正进包。
  ///
  /// 通道能应答本身就证明原生插件已随包发布。CI 曾整体覆盖 android/ 导致
  /// 插件在发布包中消失，那时这里会拿到 MissingPluginException——诊断报告
  /// 首行据此直接说明「这份日志来自缺插件的旧包」，避免再误判为代码 bug。
  static Future<BuildIdentity> buildIdentity() async {
    if (!_isAndroid) {
      // 通道仅 Android 注册：channelOk=false 是平台差异而非缺插件，
      // applicable=false 让 summary/channelMissing 不再误报
      return const BuildIdentity(error: '非 Android 平台', applicable: false);
    }
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getAppVersion',
      );
      if (raw == null) {
        return const BuildIdentity(error: '原生未返回版本信息');
      }
      return BuildIdentity(
        versionName: (raw['versionName'] as String?) ?? '',
        versionCode: (raw['versionCode'] as num?)?.toInt(),
        error: raw['error'] as String?,
        channelOk: true,
      );
    } on MissingPluginException catch (e) {
      return BuildIdentity(channelOk: false, error: e.toString());
    } catch (e) {
      return BuildIdentity(channelOk: false, error: e.toString());
    }
  }

  @visibleForTesting
  static void resetCache() {
    _cached = Future.value(DvProbeResult.unknown);
    _initialized = false;
    isAndroidOverride = null;
  }
}

/// 当前构建的身份信息。
class BuildIdentity {
  const BuildIdentity({
    this.versionName,
    this.versionCode,
    this.error,
    this.channelOk = false,
    this.applicable = true,
  });

  /// 应用版本号，如 `1.1.16`；取不到时为 null 或空串。
  final String? versionName;

  /// 构建号，如 `186`。
  final int? versionCode;

  /// 原生侧错误；通道未注册时为 MissingPluginException 全文。
  final String? error;

  /// `com.himi/dolby_vision` 通道是否应答。false 即产物缺原生插件。
  final bool channelOk;

  /// 通道在当前平台是否适用（原生插件仅注册在 Android）。
  /// false = 非 Android，此时 channelOk=false 属正常，不是缺插件。
  final bool applicable;

  bool get hasVersion => versionName != null && versionName!.isNotEmpty;

  /// 是否因通道未注册而无法确认版本——诊断报告必须醒目提示这种情况。
  /// 非 Android 平台通道本就不存在，不构成「缺插件」问题。
  bool get channelMissing => applicable && !channelOk;

  /// 报告首行的一行摘要。
  String get summary {
    if (!applicable) {
      return '不适用 | DV通道仅Android';
    }
    if (!channelOk) {
      return '未知 | DV通道未注册(产物缺原生插件)';
    }
    final v = hasVersion
        ? '$versionName+${versionCode ?? '?'}'
        : (error == null ? '未知' : '未知($error)');
    return '$v | DV通道已注册';
  }
}
