/// 音频滤镜（mdk `audio.avfilter`）选择策略。
///
/// 纯 Dart 实现，不依赖 mdk / Flutter，便于单元测试。
///
/// 背景：iOS 上 TrueHD/MLP 音轨无声（上游 mdk-sdk issue #364 至今未修复）。
/// FFmpeg 解出 `s32 7.1` PCM 后送入 Apple AudioQueue 后端无法出声；
/// Android/Windows 同片源有声，故仅 iOS 规避。做法是在音频进入渲染器
/// 之前转成立体声 + `s16|flt`：`aformat` 一次性完成降混与采样格式转换
/// （`channel_layouts`/`sample_fmts` 为各 FFmpeg 版本均支持的选项，
/// 上游作者在 issue #294 中建议的写法；早前的
/// `aresample=ochl=stereo` 用的 `ochl` 是 FFmpeg 7.x 才有的选项名，
/// 旧版解析失败会让整条滤镜失效）。
library;

class AudioFilterPolicy {
  const AudioFilterPolicy._();

  /// iOS TrueHD/MLP 无声规避滤镜：降混立体声 + 转采样格式。
  /// `aformat` 的 `channel_layouts`/`sample_fmts` 各 FFmpeg 版本均支持。
  static const String truehdIosFilter =
      'aformat=sample_fmts=s16|flt:channel_layouts=stereo';

  /// 用户「立体声降混」开关的滤镜。
  static const String stereoDownmixFilter = 'aformat=channel_layouts=stereo';

  /// 会触发 iOS 无声的音轨编码（FFmpeg/Emby 惯例为小写，比较前统一处理）。
  static const Set<String> iosSilentCodecs = {'truehd', 'mlp'};

  /// 计算应写入 `audio.avfilter` 的滤镜串。
  ///
  /// [codec]：当前活跃音轨编码（如 `truehd`），未知传空。
  /// [stereoDownmix]：用户「立体声降混」开关。
  /// [isIOS]：是否 iOS（仅 iOS 受无声问题影响）。
  ///
  /// 优先级：iOS 问题编码 > 用户降混开关 > 无滤镜。
  /// iOS+TrueHD 场景下滤镜已含降混，无需叠加用户开关。
  static String resolve({
    String codec = '',
    required bool stereoDownmix,
    required bool isIOS,
  }) {
    final c = codec.trim().toLowerCase();
    if (isIOS && iosSilentCodecs.contains(c)) return truehdIosFilter;
    if (stereoDownmix) return stereoDownmixFilter;
    return '';
  }
}
