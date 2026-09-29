/// 解码器种类
enum DecoderKind { software, hardware, unknown }

/// 解码器判定结果。
///
/// [confirmed] 标明该结论是否有 mdk 事件层面的直接证据：
/// 平台预选出的底层 codec 名只是**推断**，mdk 事件点名才是**确证**。
/// 两者不可混为一谈，故标签上直接标出。
class DecoderVerdict {
  const DecoderVerdict(this.kind, {required this.confirmed});

  final DecoderKind kind;

  /// true = mdk 事件直接证实；false = 基于平台预选的推断
  final bool confirmed;

  bool get isUnknown => kind == DecoderKind.unknown;

  String get label {
    if (isUnknown) return '未知';
    final name = kind == DecoderKind.hardware ? '硬解' : '软解';
    return confirmed ? '$name(确证)' : '$name(推断)';
  }

  @override
  bool operator ==(Object other) =>
      other is DecoderVerdict &&
      other.kind == kind &&
      other.confirmed == confirmed;

  @override
  int get hashCode => Object.hash(kind, confirmed);
}

/// 单条轨道（视频或音频）的实际解码情况。
class DecoderTrack {
  const DecoderTrack({
    this.framework = '',
    this.error = 0,
    this.codec = '',
    this.codecIsSoftware,
  });

  /// mdk `decoder.video` / `decoder.audio` 事件 detail，即实际生效的
  /// 解码框架名，如 `AMediaCodec` / `FFmpeg`。
  final String framework;

  /// 上述 mdk 事件的 error 字段。成功为 0，失败为具体错误码。
  final int error;

  /// 平台预选出的底层 codec 名，如 `c2.qti.hevc.decoder`；未探测到为空
  final String codec;

  /// [codec] 是否为软件实现，由原生 `isSoftwareName` 判定
  final bool? codecIsSoftware;

  bool get hasFramework => framework.isNotEmpty;

  /// 判定硬解/软解。
  ///
  /// 判定是**保守**的：任一关键输入缺失或不可信即返回 [DecoderKind.unknown]，
  /// 绝不猜测。理由见 [_knownFrameworks]。
  DecoderVerdict get verdict {
    final fw = framework.trim().toLowerCase();
    if (fw.isEmpty) return const DecoderVerdict(DecoderKind.unknown, confirmed: false);

    // mdk 事件直接点名 FFmpeg，即软件解码，无歧义。
    if (fw == 'ffmpeg') {
      return const DecoderVerdict(DecoderKind.software, confirmed: true);
    }

    // detail 语义在 mdk 版本间不一致：我们的构建填解码器名，
    // 而 fvp issue #266 的日志里同一字段填的是状态（open）。
    // 不在白名单内就视为不可信，宁可显示未知也不输出错值。
    if (!_knownFrameworks.contains(fw)) {
      return const DecoderVerdict(DecoderKind.unknown, confirmed: false);
    }

    // 走框架解码，但不知道底层落到硬件还是软件实现
    if (codecIsSoftware == null) {
      return const DecoderVerdict(DecoderKind.unknown, confirmed: false);
    }
    return DecoderVerdict(
      codecIsSoftware! ? DecoderKind.software : DecoderKind.hardware,
      confirmed: false,
    );
  }

  /// `AMediaCodec → c2.qti.hevc.decoder  硬解(推断)  code 0`
  String get display {
    final sb = StringBuffer(hasFramework ? framework : '?');
    if (codec.isNotEmpty) sb.write(' → $codec');
    sb.write('  ${verdict.label}  code $error');
    return sb.toString();
  }

  /// 已知的 mdk 解码框架名（小写比较）。不在表内的 detail 视为不可信。
  static const _knownFrameworks = {
    'amediacodec',
    'ffmpeg',
    'videotoolbox',
    'vt',
    'vda',
    'mmal',
    'opensl',
    'audiotrack',
    'coreaudio',
  };

  DecoderTrack copyWith({
    String? framework,
    int? error,
    String? codec,
    bool? codecIsSoftware,
  }) =>
      DecoderTrack(
        framework: framework ?? this.framework,
        error: error ?? this.error,
        codec: codec ?? this.codec,
        codecIsSoftware: codecIsSoftware ?? this.codecIsSoftware,
      );
}

/// 视频 + 音频的实际解码情况快照。
///
/// 不可变，换集/切轨时直接替换整个实例触发面板重建，
/// 避免残留上一集的解码器信息。
class DecoderReport {
  const DecoderReport({
    this.video = const DecoderTrack(),
    this.audio = const DecoderTrack(),
  });

  final DecoderTrack video;
  final DecoderTrack audio;

  static const empty = DecoderReport();

  bool get isEmpty => !video.hasFramework && !audio.hasFramework;

  DecoderReport withVideo(DecoderTrack t) =>
      DecoderReport(video: t, audio: audio);

  DecoderReport withAudio(DecoderTrack t) =>
      DecoderReport(video: video, audio: t);
}
