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

  /// 平台音频硬解器 + FFmpeg 兜底。
  ///
  /// 音频硬解可用性因设备/编码而异（EAC3 等需 SoC 支持），纯硬解
  /// 无兜底会让无硬解设备直接没声；音频「没声」比软解更不可接受，
  /// 故 hw 档音频保留 FFmpeg 兜底——与视频 hw（纯硬解不回退）语义
  /// 有意不同（1.1.187）。
  static List<String> _platformHwOnlyAudioDecoders() {
    if (Platform.isAndroid) return ['AMediaCodec', 'FFmpeg'];
    if (Platform.isWindows) return ['MFT', 'FFmpeg'];
    return ['FFmpeg'];
  }

  /// 平台自适应音频解码器（优先硬解，失败回退软解）
  static List<String> _platformAutoAudioDecoders() {
    if (Platform.isAndroid) return ['AMediaCodec', 'FFmpeg'];
    if (Platform.isWindows) return ['MFT', 'FFmpeg'];
    return ['FFmpeg'];
  }

  /// 向解码器列表内嵌 image=N 属性（Android AMediaCodec 专用，1.1.190）。
  ///
  /// mdk 官方方式：`setDecoders(["AMediaCodec:image=0"])` 属性内嵌在
  /// 解码器名中，创建时读取，不受 mdk 内部 `video.decoder=scale=WxH`
  /// 覆写影响（1.1.189 setProperty 方式被覆写导致实验无效）。
  ///
  /// 仅处理 AMediaCodec 条目；非 Android 平台或列表无 AMediaCodec
  /// 时原样返回。
  static List<String> withDecoderImage(
    List<String> decoders,
    String imageVal,
  ) {
    return decoders.map((d) {
      if (!d.startsWith('AMediaCodec')) return d;
      // 去除已有 image= 键，再追加新值
      final base = d
          .split(':')
          .where((p) => p.isNotEmpty && !p.startsWith('image='))
          .toList();
      base.add('image=$imageVal');
      return base.join(':');
    }).toList();
  }

  /// 向解码器列表内嵌 low_latency=1 属性（Android AMediaCodec 专用，1.1.192）。
  ///
  /// mdk 0.34+ 新增 AMediaCodec 解码器 low_latency 选项（默认 0，需 API 30+）。
  /// 改变硬解器内部 buffer 管理路径。用于 A/B 验证 10-bit P010 4K60
  /// 在 Adreno 740 上的簇状丢帧是否为 Qualcomm 硬解 buffer 管理 bug
  /// （硬解丢帧、软解不丢）。
  ///
  /// 仅处理 AMediaCodec 条目；非 Android 平台或列表无 AMediaCodec
  /// 时原样返回。已有 low_latency= 键则不重复追加。
  static List<String> withDecoderLowLatency(List<String> decoders) {
    return decoders.map((d) {
      if (!d.startsWith('AMediaCodec')) return d;
      if (d.contains('low_latency=')) return d;
      final parts =
          d.split(':').where((p) => p.isNotEmpty).toList();
      parts.add('low_latency=1');
      return parts.join(':');
    }).toList();
  }
}
