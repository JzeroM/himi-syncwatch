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
        dvProfiles:
            ((map['dvProfiles'] as List<Object?>?) ?? const []).map((e) =>
                (e as num?)?.toInt() ?? 0).toList(growable: false),
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
        (!_isKnownCodec(parts.first) || _notVendor.contains(parts.first.toLowerCase()))) {
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
      final hex = dvProfiles
          .map((p) => p.toRadixString(16).padLeft(4, '0'))
          .join('/');
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

  @visibleForTesting
  static void resetCache() {
    _cached = Future.value(DvProbeResult.unknown);
    _initialized = false;
    isAndroidOverride = null;
  }
}
