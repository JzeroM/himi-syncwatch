/// mdk/fvp 的 `CodecParameters` 只暴露 codec 名与 fourcc（见
/// `media_info.dart` 的 `CodecParameters`），**不含 MIME**。
///
/// 而平台侧的 `MediaFormat.findDecoderForFormat` 校验必须使用标准
/// MIME 字符串，因此需要一层显式映射。
///
/// 设计约束：**未命中的编码一律返回 null**，由调用方跳过探测。
/// 宁可面板显示「未知」，也不能用猜出来的 MIME 得出一个看似确凿的
/// 硬解/软解结论。
class CodecMimeMap {
  const CodecMimeMap._();

  static const _video = <String, String>{
    'hevc': 'video/hevc',
    'h265': 'video/hevc',
    'avc': 'video/avc',
    'h264': 'video/avc',
    'av1': 'video/av01',
    'vp9': 'video/x-vnd.on2.vp9',
    'vp8': 'video/x-vnd.on2.vp8',
    'mpeg2': 'video/mpeg2',
    'mpeg4': 'video/mp4v-es',
  };

  static const _audio = <String, String>{
    'aac': 'audio/mp4a-latm',
    'mp3': 'audio/mpeg',
    'eac3': 'audio/eac3',
    'ac3': 'audio/ac3',
    'truehd': 'audio/truehd',
    'atmos': 'audio/ac4',
    'ac4': 'audio/ac4',
    'dts': 'audio/vnd.dts',
    'dtshd': 'audio/vnd.dts.hd',
    'flac': 'audio/flac',
    'opus': 'audio/opus',
    'vorbis': 'audio/vorbis',
    'amr': 'audio/amr',
    'pcm': 'audio/raw',
  };

  /// 视频 codec 名对应的标准 MIME，未命中返回 null
  static String? video(String? codec) => _lookup(_video, codec);

  /// 音频 codec 名对应的标准 MIME，未命中返回 null
  static String? audio(String? codec) => _lookup(_audio, codec);

  static String? _lookup(Map<String, String> table, String? codec) {
    final c = codec?.trim().toLowerCase();
    if (c == null || c.isEmpty) return null;
    return table[c];
  }
}
